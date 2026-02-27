# Kubernetes Deployment Guide

Hướng dẫn deploy backend lên Kubernetes cluster (sử dụng Supabase cho database).

---

## Prerequisites

- Kubernetes cluster đang chạy (k3s, kubeadm, microk8s...)
- `kubectl` đã cấu hình kết nối cluster
- Docker registry (Docker Hub hoặc private registry)
- Supabase account + connection credentials

---

## Bước 1: Push Backend Image lên Registry

```bash
# Trên máy Windows (đã build image)
docker tag restaurant-backend:latest <your-registry>/restaurant-backend:latest
docker push <your-registry>/restaurant-backend:latest
```

---

## Bước 2: Chuẩn bị Supabase Credentials

```bash
# Thay thế các giá trị thực tế
export DB_USER="postgres.iyhxwysdtwqcmmmpsial"
export DB_HOST="aws-1-ap-south-1.pooler.supabase.com"
export DB_PASSWORD="vfY#hEy*tn4_gGj"
export DB_NAME="postgres"
export DB_PORT="6543"
```

---

## Bước 3: Tạo Kubernetes Secrets

```bash
# Tạo namespace
kubectl create namespace restaurant

# Tạo secrets (KHÔNG hardcode trong YAML)
kubectl create secret generic backend-secrets \
  -n restaurant \
  --from-literal=DB_USER=$DB_USER \
  --from-literal=DB_HOST=$DB_HOST \
  --from-literal=DB_PASSWORD=$DB_PASSWORD \
  --from-literal=DB_NAME=$DB_NAME \
  --from-literal=DB_PORT=$DB_PORT
```

---

## Bước 4: Deploy Backend (Option A - Using YAML)

```bash
# Chỉnh sửa backend-deployment.yaml với image registry của bạn
# Sau đó deploy:

kubectl apply -f namespace.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f ingress.yaml
```

---

## Bước 5: Deploy Backend (Option B - Using Helm - RECOMMENDED)

```bash
# Chuyển đến thư mục Helm
cd ../helm

# Set environment variables
export DB_USER="postgres.iyhxwysdtwqcmmmpsial"
export DB_HOST="aws-1-ap-south-1.pooler.supabase.com"
export DB_PASSWORD="vfY#hEy*tn4_gGj"
export DB_NAME="postgres"
export DB_PORT="6543"

# Option 1: Sử dụng deploy script
./deploy.sh install
# hoặc: deploy.bat install (Windows)

# Option 2: Sử dụng helm command trực tiếp
helm install restaurant-backend ./restaurant-backend \
  -n restaurant \
  --create-namespace \
  --set supabase.user=$DB_USER \
  --set supabase.host=$DB_HOST \
  --set supabase.password=$DB_PASSWORD \
  --set supabase.database=$DB_NAME \
  --set supabase.port=$DB_PORT \
  --set backend.image.repository=<your-registry>/restaurant-backend \
  --set backend.image.tag=latest
```

---

## Bước 6: Kiểm Tra Deployment

```bash
# Kiểm tra pods
kubectl get pods -n restaurant

# Kiểm tra services
kubectl get svc -n restaurant

# Kiểm tra secrets
kubectl get secret -n restaurant
kubectl describe secret backend-secrets -n restaurant

# Xem logs
kubectl logs -n restaurant -l app=backend
kubectl logs -n restaurant deployment/backend

# Test API
kubectl port-forward -n restaurant svc/backend 5001:5001
curl http://localhost:5001/test-db
```

---

## Cập nhật Deployment (Upgrade)

```bash
# Nếu dùng Helm
helm upgrade restaurant-backend ./restaurant-backend \
  -n restaurant \
  --set supabase.user=$DB_USER \
  --set supabase.host=$DB_HOST \
  --set supabase.password=$DB_PASSWORD \
  --set supabase.database=$DB_NAME \
  --set supabase.port=$DB_PORT \
  --set backend.image.tag=v2.0.0

# Nếu dùng kubectl
kubectl set image deployment/backend \
  -n restaurant \
  backend=<your-registry>/restaurant-backend:v2.0.0
```

---

## Rollback

```bash
# Nếu dùng Helm
helm rollback restaurant-backend -n restaurant

# Nếu dùng kubectl
kubectl rollout undo deployment/backend -n restaurant
```

---

## Troubleshooting

```bash
# Pod không start - kiểm tra events
kubectl describe pod -n restaurant -l app=backend

# Kiểm tra logs
kubectl logs -n restaurant -l app=backend --previous

# Kiểm tra environment variables
kubectl exec -it -n restaurant <pod-name> -- env | grep DB_

# Port forward để test connection
kubectl port-forward -n restaurant svc/backend 5001:5001
curl http://localhost:5001/health

# Xem tất cả resources
kubectl get all -n restaurant
```

---

## ⚠️ SECURITY NOTES

- **KHÔNG** commit file secrets.yaml với credentials thực tế
- Sử dụng environment variables hoặc K8s Secrets
- Nếu dùng Helm, pass secrets via CLI không hardcode trong YAML
- Xem `.gitignore` để kiểm tra files bị ignore


