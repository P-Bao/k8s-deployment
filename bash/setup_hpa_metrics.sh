#!/bin/bash

set -e

echo "[1/10] Cài metrics-server để cung cấp metrics CPU/MEM cho HPA"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.1/components.yaml
echo "[VERIFY] Kiểm tra metrics API"
kubectl get apiservice | grep metrics || true

echo "[2/10] Kiểm tra NVIDIA GPU trên node"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi
else
    echo "Không tìm thấy nvidia-smi"
fi

echo "[3/10] Kiểm tra Kubernetes đã nhận GPU chưa"
echo "--- Kiểm tra nvidia.com/gpu (native) ---"
kubectl describe node | grep "nvidia.com/gpu" || echo "GPU chưa được Kubernetes nhận"
echo "--- Kiểm tra nvidia.com/gpu.shared (time-slicing) ---"
kubectl describe node | grep "nvidia.com/gpu.shared" || echo "GPU shared chưa được kích hoạt (chạy enable_gpu_shared.sh trước)"

echo "[4/10] Kiểm tra NVIDIA device plugin đã chạy chưa"
kubectl get pods -n kube-system | grep nvidia-device-plugin || echo "NVIDIA device plugin chưa chạy - hãy chạy enable_gpu_shared.sh trước"

echo "[5/10] Cài DCGM exporter để thu thập GPU metrics"
# NOTE: Khi dùng GPU time-slicing (nvidia.com/gpu.shared), DCGM exporter
# KHÔNG cần biết về gpu.shared. DCGM luôn thu thập metrics ở mức GPU vật lý.
# Metrics như DCGM_FI_DEV_GPU_UTIL vẫn hoạt động bình thường vì DCGM
# giao tiếp trực tiếp với NVIDIA driver, không qua Kubernetes resource API.
#
# Vấn đề thường gặp: dcgm-exporter crash vì không tìm thấy GPU device.
# Fix: mount đúng device files và dùng runtimeClassName nvidia.
helm repo add gpu-helm-charts https://nvidia.github.io/gpu-monitoring-tools/helm-charts || true
helm repo update >/dev/null 2>&1

cat <<EOF > dcgm-values-temp.yaml
serviceMonitor:
  enabled: true
  namespace: monitoring
extraEnv:
  - name: DCGM_EXPORTER_KUBERNETES
    value: "true"
# Quan trọng: DCGM exporter cần truy cập GPU device trực tiếp
# Khi dùng time-slicing, KHÔNG request nvidia.com/gpu.shared
# mà dùng volume mount để DCGM có thể đọc GPU metrics
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
# Dùng tolerations để chạy trên node có GPU
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
# Volume mounts để DCGM exporter truy cập GPU devices trực tiếp
# mà không cần request nvidia.com/gpu resource (bị time-slicing chiếm)
extraVolumeMounts:
  - name: nvidia-install-dir-host
    mountPath: /usr/local/nvidia
    readOnly: true
  - name: dev-nvidiactl
    mountPath: /dev/nvidiactl
  - name: dev-nvidia-uvm
    mountPath: /dev/nvidia-uvm
  - name: dev-nvidia-uvm-tools
    mountPath: /dev/nvidia-uvm-tools
  - name: dev-nvidia0
    mountPath: /dev/nvidia0
extraVolumes:
  - name: nvidia-install-dir-host
    hostPath:
      path: /usr/local/nvidia
      type: DirectoryOrCreate
  - name: dev-nvidiactl
    hostPath:
      path: /dev/nvidiactl
  - name: dev-nvidia-uvm
    hostPath:
      path: /dev/nvidia-uvm
  - name: dev-nvidia-uvm-tools
    hostPath:
      path: /dev/nvidia-uvm-tools
  - name: dev-nvidia0
    hostPath:
      path: /dev/nvidia0
# Chạy privileged để có quyền truy cập GPU device files
securityContext:
  privileged: true
EOF

helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  --create-namespace \
  -f dcgm-values-temp.yaml
echo "[VERIFY] Kiểm tra pod DCGM exporter"
kubectl get pods -n monitoring | grep dcgm || true

echo "[6/10] Cài kube-prometheus-stack (Prometheus/Grafana + Alertmanager)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

echo "[VERIFY] Kiểm tra pod Prometheus"
kubectl get pods -n monitoring | grep prometheus || true

echo "[7/10] Xác định service Prometheus"
kubectl get svc -n monitoring | grep prometheus

echo "[8/10] Tạo file cấu hình Prometheus Adapter"
# Dùng DCGM metrics ở mức GPU vật lý, rồi map về pod qua label.
# Khi time-slicing, nhiều pod share 1 GPU vật lý => GPU util là shared metric.
# HPA sẽ scale dựa trên GPU utilization trung bình của GPU mà pod đang dùng.
cat <<EOF > adapter-values.yaml
prometheus:
  url: http://prometheus-kube-prometheus-prometheus.monitoring.svc
  port: 9090
rules:
  custom:
  - seriesQuery: 'DCGM_FI_DEV_GPU_UTIL{namespace!="",pod!=""}'
    resources:
      overrides:
        namespace:
          resource: namespace
        pod:
          resource: pod
    name:
      matches: "DCGM_FI_DEV_GPU_UTIL"
      as: "gpu_utilization"
    metricsQuery: |
      avg(DCGM_FI_DEV_GPU_UTIL{<<.LabelMatchers>>}) by (namespace,pod)
  - seriesQuery: 'DCGM_FI_DEV_FB_USED{namespace!="",pod!=""}'
    resources:
      overrides:
        namespace:
          resource: namespace
        pod:
          resource: pod
    name:
      matches: "DCGM_FI_DEV_FB_USED"
      as: "gpu_memory_used"
    metricsQuery: |
      avg(DCGM_FI_DEV_FB_USED{<<.LabelMatchers>>}) by (namespace,pod)
EOF

echo "[9/10] Cài Prometheus Adapter để chuyển Prometheus metrics thành custom.metrics.k8s.io"
helm upgrade --install prometheus-adapter \
prometheus-community/prometheus-adapter \
-n monitoring \
-f adapter-values.yaml
echo "[VERIFY] Kiểm tra pod prometheus-adapter"
kubectl get pods -n monitoring | grep adapter || true

echo "[10/10] Kiểm tra Metrics API và custom metrics"
echo "--- API Services ---"
kubectl get apiservice | grep metrics || true

echo "--- Custom Metrics ---"
sleep 10  # Chờ adapter khởi động
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" 2>/dev/null | head || echo "Custom metrics API chưa sẵn sàng (adapter đang khởi động)"

echo "[VERIFY] Kiểm tra GPU metric gpu_utilization"
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/gpu_utilization" 2>/dev/null || echo "GPU metric chưa xuất hiện (có thể cần workload GPU chạy trước)"

echo "-----------------------------------------"
echo "HOÀN TẤT THIẾT LẬP GPU HPA STACK"
echo ""
echo "LƯU Ý khi dùng với GPU time-slicing:"
echo "  - GPU metrics (DCGM) là ở mức GPU vật lý, KHÔNG phải per-slice"
echo "  - Khi nhiều pod share 1 GPU, gpu_utilization phản ánh toàn bộ GPU"
echo "  - HPA sẽ scale dựa trên utilization trung bình"
echo "  - Pod workload cần request: nvidia.com/gpu.shared (KHÔNG phải nvidia.com/gpu)"
echo "-----------------------------------------"
