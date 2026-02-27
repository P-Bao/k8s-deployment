#!/bin/bash

# Helm Deployment Script with Environment Variables
# This script deploys the backend using Helm with secrets passed via CLI

set -a
source .env
set +a

set -e

# Configuration
RELEASE_NAME="restaurant-backend"
NAMESPACE="restaurant"
CHART_PATH="./restaurant-backend"

# Function to check if variable is set
check_env_var() {
    local var_name=$1
    local var_value=${!var_name}
    
    if [ -z "$var_value" ]; then
        echo -e "Error: $var_name is not set"
        return 1
    fi
    return 0
}

# Function to display usage
show_usage() {
    cat << EOF
Usage: ./deploy.sh [COMMAND] [OPTIONS]

Commands:
  install     Install Helm chart
  upgrade     Upgrade existing Helm chart
  dry-run     Preview what would be deployed (dry-run)
  uninstall   Remove Helm chart
  
Environment Variables Required:
  DB_USER          Supabase user (e.g., postgres.xxx)
  DB_HOST          Supabase host (e.g., xxx.supabase.com)
  DB_PASSWORD      Supabase password
  DB_NAME          Database name (usually 'postgres')
  DB_PORT          Database port (usually '6543')
  
Optional:
  IMAGE_REPO       Docker registry (default: your-registry/restaurant-backend)
  IMAGE_TAG        Docker image tag (default: latest)
  REPLICAS         Number of replicas (default: 2)
  
Examples:
  export DB_USER=postgres.xxx
  export DB_HOST=aws-1-ap-south-1.pooler.supabase.com
  export DB_PASSWORD='vfY#hEy*tn4_gGj'
  export DB_NAME=postgres
  export DB_PORT=6543
  ./deploy.sh install
  
  # Or use .env file
  source .env.prod
  ./deploy.sh upgrade --namespace production

EOF
}

# Parse command
COMMAND=${1:-install}
shift 2>/dev/null || true

# Check for help flag
if [ "$COMMAND" = "-h" ] || [ "$COMMAND" = "--help" ] || [ "$COMMAND" = "help" ]; then
    show_usage
    exit 0
fi

# Validate required environment variables
echo -e "Validating environment variables..."

check_env_var "DB_USER" || exit 1
check_env_var "DB_HOST" || exit 1
check_env_var "DB_PASSWORD" || exit 1
check_env_var "DB_NAME" || exit 1
check_env_var "DB_PORT" || exit 1

echo -e "$All required variables are set"

# Set optional variables with defaults
IMAGE_REPO=${IMAGE_REPO:-"phbao/restaurant-backend"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
REPLICAS=${REPLICAS:-"2"}

# Parse --namespace option
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Make sure namespace exists
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------------------------
# Fix HPA Metrics Issue (Enable Kubelet Read-Only Port)
# -----------------------------------------------
echo -e "Checking HPA metrics configuration..."

# Add read-only port to kubelet config if not present
if ! grep -q "readOnlyPort" /var/lib/kubelet/config.yaml; then
    echo -e "Adding kubelet read-only port..."
    echo "" | sudo tee -a /var/lib/kubelet/config.yaml > /dev/null
    echo "# Enable read-only Kubelet port for metrics monitoring" | sudo tee -a /var/lib/kubelet/config.yaml > /dev/null
    echo "readOnlyPort: 10255" | sudo tee -a /var/lib/kubelet/config.yaml > /dev/null
    
    echo -e "Restarting kubelet..."
    sudo systemctl restart kubelet
    sleep 5
fi

# Patch metrics-server if needed
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    echo -e "$Patching metrics-server for HPA support..."
    kubectl patch deployment metrics-server -n kube-system \
      -p '{"spec":{"template":{"spec":{"containers":[{"name":"metrics-server","args":["--cert-dir=/tmp","--secure-port=10250","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname","--kubelet-use-node-status-port","--metric-resolution=15s","--kubelet-insecure-tls"]}]}}}' \
      2>/dev/null || true
    
    # Wait for metrics-server to be ready
    echo -e "Waiting for metrics-server to be ready..."
    kubectl rollout status deployment/metrics-server -n kube-system --timeout=60s 2>/dev/null || true
    sleep 10
fi

echo -e "HPA metrics configured"

# Build helm command
HELM_CMD="helm $COMMAND $RELEASE_NAME $CHART_PATH"
HELM_CMD="$HELM_CMD -n $NAMESPACE"

# Add secrets via --set (NOT hardcoded in YAML)
HELM_CMD="$HELM_CMD --set supabase.user=$DB_USER"
HELM_CMD="$HELM_CMD --set supabase.host=$DB_HOST"
HELM_CMD="$HELM_CMD --set supabase.password=$DB_PASSWORD"
HELM_CMD="$HELM_CMD --set supabase.database=$DB_NAME"
HELM_CMD="$HELM_CMD --set supabase.port=$DB_PORT"

# Add optional values
HELM_CMD="$HELM_CMD --set backend.image.repository=$IMAGE_REPO"
HELM_CMD="$HELM_CMD --set backend.image.tag=$IMAGE_TAG"
HELM_CMD="$HELM_CMD --set backend.replicas=$REPLICAS"

# Add install-specific flags
if [ "$COMMAND" = "install" ]; then
    HELM_CMD="$HELM_CMD --create-namespace"
fi

# Add dry-run flag if requested
if [ "$COMMAND" = "dry-run" ]; then
    HELM_CMD="helm install $RELEASE_NAME $CHART_PATH"
    HELM_CMD="$HELM_CMD -n $NAMESPACE"
    HELM_CMD="$HELM_CMD --set supabase.user=$DB_USER"
    HELM_CMD="$HELM_CMD --set supabase.host=$DB_HOST"
    HELM_CMD="$HELM_CMD --set supabase.password=$DB_PASSWORD"
    HELM_CMD="$HELM_CMD --set supabase.database=$DB_NAME"
    HELM_CMD="$HELM_CMD --set supabase.port=$DB_PORT"
    HELM_CMD="$HELM_CMD --set backend.image.repository=$IMAGE_REPO"
    HELM_CMD="$HELM_CMD --set backend.image.tag=$IMAGE_TAG"
    HELM_CMD="$HELM_CMD --set backend.replicas=$REPLICAS"
    HELM_CMD="$HELM_CMD --dry-run --debug"
fi

# Display what we're about to do
echo ""
echo -e "Deployment Configuration:"
echo "  Release: $RELEASE_NAME"
echo "  Chart: $CHART_PATH"
echo "  Namespace: $NAMESPACE"
echo "  Command: $COMMAND"
echo "  Image: $IMAGE_REPO:$IMAGE_TAG"
echo "  Replicas: $REPLICAS"
echo "  Database Host: $DB_HOST"
echo "  Database User: $DB_USER"
echo ""

if [ "$COMMAND" != "dry-run" ]; then
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 1
    fi
fi

# Execute helm command
echo -e "Executing Helm command..."
echo ""
eval $HELM_CMD

if [ $? -eq 0 ]; then
    echo ""
    echo -e "Deployment successful!"
    echo ""
    echo "Check deployment status:"
    echo "  kubectl get deployments -n $NAMESPACE"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app=restaurant-backend"
    echo ""
    echo "Check HPA status:"
    echo "  kubectl get hpa -n $NAMESPACE"
    echo "  kubectl top pods -n $NAMESPACE"
else
    echo -e "Deployment failed!"
    exit 1
fi
