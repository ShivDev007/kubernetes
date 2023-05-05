#!/bin/bash

# Update the package list
sudo apt-get update

# Install Docker
sudo apt-get install -y docker.io

# Enable Docker service
sudo systemctl enable docker

# Add Kubernetes GPG key and repository
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update the package list again
sudo apt-get update

# Install Kubernetes components
sudo apt-get install -y kubeadm kubelet kubectl

# Prevent Kubernetes components from being automatically updated
sudo apt-mark hold kubeadm kubelet kubectl

# Disable swap memory
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Load overlay and br_netfilter modules
echo "overlay" | sudo tee /etc/modules-load.d/containerd.conf
echo "br_netfilter" | sudo tee -a /etc/modules-load.d/containerd.conf
sudo modprobe overlay
sudo modprobe br_netfilter

# Set kernel parameters for Kubernetes networking
cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Set hostname for master node
sudo hostnamectl set-hostname master-node
sudo sed -i "s/127.0.1.1.*/127.0.1.1\tmaster-node/g" /etc/hosts

# Set cgroup driver for kubelet
echo 'KUBELET_EXTRA_ARGS=--cgroup-driver=systemd' | sudo tee /etc/default/kubelet

# Configure Docker to use systemd as the cgroup driver
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF'

# Reload systemd
sudo systemctl daemon-reload

# Restart services
sudo systemctl restart kubelet docker

# Set fail-swap-on=false for kubelet
sudo mkdir -p /etc/systemd/system/kubelet.service.d/
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--fail-swap-on=false"
EOF'

# Reload systemd for the final time
sudo systemctl daemon-reload

# Initialize the control plane
sudo kubeadm init --control-plane-endpoint=$(hostname -i) --upload-certs

# Set up the Kubernetes config file
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel network plugin
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Taint the nodes
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Stop the AppArmor service
sudo systemctl stop apparmor

# Restart the containerd service
sudo systemctl restart containerd.service

echo "Done. Now run the kubeadm join command on worker nodes to join them to the cluster."
