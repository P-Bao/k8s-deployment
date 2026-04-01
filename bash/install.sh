#!/bin/bash
set -e

echo "=============================="
echo " Cài đặt Kubernetes + Helm"
echo "=============================="

# -----------------------------------------------
# 1. Tắt Swap (Bắt buộc cho Kubernetes)
# -----------------------------------------------
echo "[1/13] Tắt Swap..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# -----------------------------------------------
# 2. Cấu hình Kernel Modules cho Networking
# -----------------------------------------------
echo "[2/13] Cấu hình kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# -----------------------------------------------
# 3. Cấu hình Sysctl cho Bridging
# -----------------------------------------------
echo "[3/13] Cấu hình sysctl..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# -----------------------------------------------
# 4. Cài đặt các gói phụ trợ
# -----------------------------------------------
echo "[4/13] Cài đặt gói phụ trợ..."
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gpg conntrack

# -----------------------------------------------
# 5. Cài đặt containerd từ Docker repo
#    (Bước này bị thiếu trong script gốc - containerd.io
#     cần được cài trước khi chạy "containerd config default")
# -----------------------------------------------
echo "[5/13] Cài đặt containerd..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y containerd.io

# -----------------------------------------------
# 6. Cấu hình containerd với SystemdCgroup = true
# -----------------------------------------------
echo "[6/13] Cấu hình containerd..."
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Kiểm tra containerd chạy ổn
sudo systemctl is-active --quiet containerd \
  && echo "containerd: OK" \
  || { echo "containerd FAILED - dừng lại"; exit 1; }

# -----------------------------------------------
# 7. Thêm Kubernetes Repository (v1.31)
#    Lưu ý: echo phải trên 1 dòng để tránh lỗi nguồn repo bị xuống dòng
#    (Đây là lỗi bạn gặp phải khi chạy lần đầu)
# -----------------------------------------------
echo "[7/13] Thêm Kubernetes repo..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

# -----------------------------------------------
# 8. Cài đặt Kubelet, Kubeadm, Kubectl
# -----------------------------------------------
echo "[8/13] Cài đặt kubelet, kubeadm, kubectl..."
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# -----------------------------------------------
# 9. Khởi tạo Cluster (Control Plane)
#    10.244.0.0/16 là dải IP mặc định của Flannel
# -----------------------------------------------
echo "[9/13] Khởi tạo Kubernetes cluster..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# -----------------------------------------------
# 10. Cấu hình Kubectl cho user hiện tại
# -----------------------------------------------
echo "[10/13] Cấu hình kubectl..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# -----------------------------------------------
# 11. Cài đặt Flannel Network + tạo thư mục cần thiết
#     (Bạn đã gặp lỗi flannel thiếu /run/flannel)
# -----------------------------------------------
echo "[11/13] Cài đặt Flannel..."
sudo mkdir -p /run/flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "Chờ Flannel khởi động (30s)..."
sleep 30
kubectl get pods -n kube-flannel

# -----------------------------------------------
# 12. Gỡ Taint để chạy Pod trên Control Plane (Single Node)
# -----------------------------------------------
echo "[12/13] Gỡ taint control-plane..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# -----------------------------------------------
# 13. Cài đặt các add-ons
# -----------------------------------------------
echo "[13/13] Cài đặt add-ons..."

# Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Local Path Provisioner (Storage mặc định)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# -----------------------------------------------
# 14. Cài đặt Helm
# -----------------------------------------------
echo "[Helm] Cài đặt Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

# -----------------------------------------------
# Kiểm tra kết quả
# -----------------------------------------------
echo ""
echo "=============================="
echo " Kiểm tra cài đặt"
echo "=============================="
kubectl get nodes
kubectl get pods -A
helm version

echo ""
echo "Cài đặt Kubernetes + Helm hoàn tất!"