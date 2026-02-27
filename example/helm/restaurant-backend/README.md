# Restaurant Backend Helm Chart

## Database: Supabase (Managed PostgreSQL)

This chart deploys the backend with Supabase as the database. **Secrets are injected via environment variables, not hardcoded in YAML files.**

## Quick Start - Using Deploy Scripts

### Linux/Mac
```bash
# Load environment variables
source ../../.env.prod    # Or your .env file

# Install
cd ../../helm
./deploy.sh install

# Upgrade
./deploy.sh upgrade

# Dry-run (preview)
./deploy.sh dry-run
```

### Windows
```powershell
# Load environment variables
# Create .env.prod in backend folder with:
# DB_USER=postgres.xxx
# DB_HOST=xxx.supabase.com
# DB_PASSWORD=your_password
# DB_NAME=postgres
# DB_PORT=6543

cd helm
# Then run deploy.bat with env vars set
deploy.bat install

# Or set env vars first:
set DB_USER=postgres.xxx
set DB_HOST=xxx.supabase.com
set DB_PASSWORD=your_password
set DB_NAME=postgres
set DB_PORT=6543
deploy.bat install
```

## Manual Installation with Helm CLI

```bash
# Set environment variables
export DB_USER=
export DB_HOST=
export DB_PASSWORD=
export DB_NAME=
export DB_PORT=

# Install
helm install restaurant-backend ./restaurant-backend \
  -n restaurant \
  --create-namespace \
  --set supabase.user=$DB_USER \
  --set supabase.host=$DB_HOST \
  --set supabase.password=$DB_PASSWORD \
  --set supabase.database=$DB_NAME \
  --set supabase.port=$DB_PORT \
  --set backend.image.repository=your-registry/restaurant-backend \
  --set backend.image.tag=latest

# Upgrade
helm upgrade restaurant-backend ./restaurant-backend \
  -n restaurant \
  --set supabase.user=$DB_USER \
  --set supabase.host=$DB_HOST \
  --set supabase.password=$DB_PASSWORD \
  --set supabase.database=$DB_NAME \
  --set supabase.port=$DB_PORT

# Dry-run
helm install restaurant-backend ./restaurant-backend \
  -n restaurant \
  --dry-run --debug \
  --set supabase.user=$DB_USER \
  --set supabase.host=$DB_HOST \
  --set supabase.password=$DB_PASSWORD \
  --set supabase.database=$DB_NAME \
  --set supabase.port=$DB_PORT
```

## Environment Variables (REQUIRED)

| Variable | Description | Example |
|----------|-------------|---------|
| `DB_USER` | Supabase user | `postgres.iyhxwysdtwqcmmmpsial` |
| `DB_HOST` | Supabase host | `aws-1-ap-south-1.pooler.supabase.com` |
| `DB_PASSWORD` | Supabase password | `vfY#hEy*tn4_gGj` |
| `DB_NAME` | Database name | `postgres` |
| `DB_PORT` | Connection pool port | `6543` |

## Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `backend.image.repository` | Docker image registry | `your-registry/restaurant-backend` |
| `backend.image.tag` | Docker image tag | `latest` |
| `backend.replicas` | Pod replicas | `2` |
| `backend.port` | Container port | `5001` |
| `ingress.host` | Ingress domain | `api.restaurant.local` |

## Managing Secrets Securely

### Option 1: Use Deploy Scripts (Recommended)
Set environment variables and use deploy script - secrets never touch YAML files.

### Option 2: Environment File
```bash
# Create .env.prod (add to .gitignore)
source .env.prod
./deploy.sh install
```

### Option 3: Kubernetes Secrets (Alternative)
```bash
# Create secret directly
kubectl create secret generic restaurant-db-secret \
  -n restaurant \
  --from-literal=DB_USER=$DB_USER \
  --from-literal=DB_HOST=$DB_HOST \
  --from-literal=DB_PASSWORD=$DB_PASSWORD \
  --from-literal=DB_NAME=$DB_NAME \
  --from-literal=DB_PORT=$DB_PORT
```

## Common Commands

```bash
# Get deployment status
kubectl get deployments -n restaurant
kubectl get pods -n restaurant

# View logs
kubectl logs -n restaurant -l app=restaurant-backend
kubectl logs -n restaurant deployment/restaurant-backend-backend

# Port forward for local testing
kubectl port-forward -n restaurant svc/restaurant-backend-backend 5001:5001

# Upgrade
helm upgrade restaurant-backend ./restaurant-backend -n restaurant \
  --set supabase.user=$DB_USER \
  --set supabase.host=$DB_HOST \
  --set supabase.password=$DB_PASSWORD \
  --set supabase.database=$DB_NAME \
  --set supabase.port=$DB_PORT

# Rollback
helm rollback restaurant-backend -n restaurant

# Uninstall
helm uninstall restaurant-backend -n restaurant
```

## Troubleshooting

### Pod not starting
```bash
# Check events
kubectl describe pod -n restaurant -l app=restaurant-backend

# Check logs
kubectl logs -n restaurant -l app=restaurant-backend --previous

# Port forward and test connection
kubectl port-forward -n restaurant svc/restaurant-backend-backend 5001:5001
curl http://localhost:5001/health
```

### Secrets not injected
```bash
# Verify secret exists
kubectl get secret -n restaurant
kubectl get secret restaurant-backend-db-secret -n restaurant -o yaml

# Verify pod environment
kubectl exec -it -n restaurant <pod-name> -- env | grep DB_
```
