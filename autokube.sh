#!/bin/bash

# Update the package list
sudo apt-get update

# Install Docker
sudo apt-get install -y docker.io

# Enable Docker service
sudo systemctl enable docker

# Add Kubernetes GPG key
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - 

# Add Kubernetes repository
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"

# Update the package list again
sudo apt-get update

# Install Kubernetes components
sudo apt-get install -y kubeadm kubelet kubectl

# Prevent Kubernetes components from being automatically updated
sudo apt-mark hold kubeadm kubelet kubectl

# Disable swap memory
sudo swapoff -a

# Update /etc/fstab to disable swap memory
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load overlay and br_netfilter modules
sudo echo "overlay" >> /etc/modules-load.d/containerd.conf
sudo echo "br_netfilter" >> /etc/modules-load.d/containerd.conf
sudo modprobe overlay
sudo modprobe br_netfilter

# Set kernel parameters for Kubernetes networking
sudo echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/kubernetes.conf
sudo echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/kubernetes.conf
sudo echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/kubernetes.conf
sudo sysctl --system

# Set hostname for master node
sudo hostnamectl set-hostname master-node
bash 

# Set cgroup driver for kubelet
sudo echo "KUBELET_EXTRA_ARGS=--cgroup-driver=cgroupfs" >> /etc/default/kubelet

# Reload systemd
sudo systemctl daemon-reload

# Restart kubelet
sudo systemctl restart kubelet

# Configure Docker to use systemd as the cgroup driver
sudo bash -c 'cat <<EOF >> /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF'

# Reload systemd again
sudo systemctl daemon-reload

# Restart Docker
sudo systemctl restart docker

# Set fail-swap-on=false for kubelet
sudo bash -c 'echo "Environment=\"KUBELET_EXTRA_ARGS=--fail-swap-on=false\"" >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf'

# Reload systemd for the final time
sudo systemctl daemon-reload

# Restart kubelet
sudo systemctl restart kubelet

# Initialize the control plane
sudo kubeadm init --control-plane-endpoint=[master-node] --upload-certs

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

# Join worker nodes to the cluster
echo "Run the kubeadm join command on worker nodes to join them to the cluster."
