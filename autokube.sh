#!/bin/bash

# Exit immediately if any command exits with a non-zero status
set -e

# Set the hostname for the master node
sudo hostnamectl set-hostname master-node
sudo bash 

# Update the package list
sudo apt-get update

# Install necessary packages for managing repositories over HTTPS
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common

# Add the Kubernetes GPG key and repository
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo add-apt-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"

# Update the package list again
sudo apt-get update

# Install Docker and Kubernetes components
sudo apt-get install -y docker.io kubeadm kubelet kubectl

# Prevent Kubernetes components from being automatically updated
sudo apt-mark hold kubeadm kubelet kubectl

# Disable swap memory
sudo swapoff -a

# Update /etc/fstab to disable swap memory
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

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

# Set cgroup driver for kubelet
echo 'KUBELET_EXTRA_ARGS=--cgroup-driver=cgroupfs' | sudo tee /etc/default/kubelet

# Configure Docker to use systemd as the cgroup driver
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Restart Docker and kubelet services
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl restart kubelet

# Set fail-swap-on=false for kubelet
sudo mkdir -p /etc/systemd/system/kubelet.service.d/
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--fail-swap-on=false"
EOF

# Reload systemd for the final time
sudo systemctl daemon-reload

# Initialize the control plane
sudo kubeadm init --control-plane-endpoint=master-node --upload-certs

# Set up the Kubernetes config file
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install the Flannel network plugin
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Taint the nodes
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Restart the containerd service
sudo systemctl restart containerd.service

# Output join command for worker nodes
echo "Run the kubeadm join command on worker nodes to"
