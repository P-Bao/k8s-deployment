#!/bin/bash

# 1. Tắt Swap (Bắt buộc cho Kubernetes)
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# 2. Cấu hình Kernel Modules cho Networking
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 3. Cấu hình Sysctl cho Bridging
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 4. Cài đặt các gói phụ trợ và Docker Repo (để lấy containerd)
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gpg conntrack

# 5. Cấu hình containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
# Sửa SystemdCgroup thành true trong file config
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 6. Thêm Kubernetes Repository (v1.31)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 7. Cài đặt Kubelet, Kubeadm, Kubectl
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 8. Khởi tạo Cluster (Control Plane)
# Lưu ý: 10.244.0.0/16 là dải IP mặc định của Flannel
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# 9. Cấu hình Kubectl cho User hiện tại
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 10. Cài đặt Flannel Network
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 11. Gỡ bỏ Taint để chạy Pod trên Control Plane (Single Node Cluster)
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 12. Cài đặt Metrics Server với cấu hình insecure (để kubectl top hoạt động)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# 13. Cài đặt Local Path Provisioner (Storage)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "Cài đặt Kubernetes hoàn tất!"