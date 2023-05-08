#!/bin/bash

# Set hostname
hostnamectl set-hostname k8s_master

# Refresh the session
exec bash

# Update OS
apt update

# Install Kubernetes helper package
apt install apt-transport-https curl -y

# Install and set up containerd
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install containerd.io -y
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sed -i 's/^# SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# Install Kubernetes helper packages
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
apt update
apt install kubeadm kubelet kubectl kubernetes-cni -y

# Disable swap
swapoff -a

# Enable bridge network
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1

# Pull Kubernetes images
kubeadm config images pull

# Initialize Kubernetes cluster master plane
kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel network
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.20.2/Documentation/kube-flannel.yml

# Check nodes
kubectl get nodes -o wide
