#!/bin/bash

# Update the package list
sudo apt update -y

# Install Docker
sudo apt install docker.io -y

# Enable Docker
sudo systemctl enable docker

# Add Kubernetes keys
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/kubernetes.gpg

# Add Kubernetes software repos
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/kubernetes.gpg] http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list

# Install Kubernetes components
sudo apt install kubeadm kubelet kubectl -y

# Prevent Kubernetes components from being updated
sudo apt-mark hold kubeadm kubelet kubectl

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules for containerd
sudo echo "overlay" >> /etc/modules-load.d/containerd.conf
sudo echo "br_netfilter" >> /etc/modules-load.d/containerd.conf
sudo modprobe overlay

# Configure network settings for Kubernetes
sudo echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/kubernetes.conf
sudo echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/kubernetes.conf
sudo echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/kubernetes.conf
sudo sysctl --system

# Set hostname for the master node
sudo hostnamectl set-hostname master-node

# Configure the Kubelet service
sudo sh -c 'echo "KUBELET_EXTRA_ARGS=--cgroup-driver=cgroupfs" >> /etc/default/kubelet'
sudo systemctl daemon-reload
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

sudo systemctl daemon-reload
sudo systemctl restart docker

# Configure Kubelet to ignore swap errors
sudo sh -c 'echo "Environment=\"KUBELET_EXTRA_ARGS=--fail-swap-on=false\"" >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf'
sudo systemctl daemon-reload
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
echo " sudo kubeadm join <master-node>:6443 --token abcdef.1234567890abcdef --discovery-token-ca-cert-hash sha256:1234..cdef --node-name worker-node"

