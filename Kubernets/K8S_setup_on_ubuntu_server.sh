
#!/bin/bash
set -e

# ============================================================
# Kubernetes Cluster Prerequisites Setup – Ubuntu Server
# ============================================================
#
# PURPOSE:
# This script automates the installation and configuration of
# Kubernetes prerequisites on Ubuntu servers.
#
# SUPPORTED NODE TYPES:
# 1. Master Node  - Initializes the Kubernetes Control Plane.
# 2. Worker Node  - Joins the existing Kubernetes Cluster.
#
# WHY THIS CONFIGURATION IS REQUIRED:
# - Disable Swap for Kubernetes kubelet compatibility.
# - Load kernel modules required for container networking.
# - Configure network forwarding and packet filtering.
# - Install containerd as the Kubernetes container runtime.
# - Configure systemd cgroup driver for kubelet compatibility.
# - Configure the official Kubernetes package repository.
# - Install kubelet, kubeadm and kubectl.
# - Initialize the control plane on the Master Node.
# - Install Flannel CNI for Pod-to-Pod networking.
# - Join Worker Nodes to the Kubernetes Cluster.
# - Enable kubectl command autocompletion.
#
# EXECUTION:
# Master Node : bash k8s-setup.sh master
# Worker Node : bash k8s-setup.sh worker "<JOIN COMMAND>"
#
# ============================================================

echo "==== Kubernetes Prerequisites Setup (Ubuntu) ===="

# -------------------------------
# STEP 1: Disable Swap
# -------------------------------
# WHY:
# Kubernetes kubelet requires swap to be disabled by default.
# Disabling swap ensures predictable memory management for Pods
# and prevents kubelet startup failures.
echo "[1] Disabling Swap"
swapoff -a
sed -i '/swap/d' /etc/fstab

# -------------------------------
# STEP 2: Load Kernel Modules
# -------------------------------
# WHY:
# overlay     - Required for overlay filesystem used by containers.
# br_netfilter - Allows bridged network traffic to pass through
#                iptables rules for Kubernetes networking.
echo "[2] Loading Kernel Modules"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# -------------------------------
# STEP 3: Sysctl Config
# -------------------------------
# WHY:
# bridge-nf-call-iptables  - Allows iptables to process bridged traffic.
# bridge-nf-call-ip6tables - Allows ip6tables to process bridged traffic.
# ip_forward              - Enables packet forwarding between networks.
# These settings are essential for Pod and cluster networking.
echo "[3] Configuring sysctl"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# -------------------------------
# STEP 4: Install Dependencies
# -------------------------------
# WHY:
# Installs required utilities for downloading packages,
# managing HTTPS repositories, handling GPG keys and
# configuring the Kubernetes package repository.
echo "[4] Installing dependencies"
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

# -------------------------------
# STEP 5: Install containerd
# -------------------------------
# WHY:
# containerd is the container runtime responsible for
# downloading container images and managing containers.
# Kubernetes uses the CRI interface to communicate with it.
#
# SystemdCgroup = true:
# Ensures containerd and kubelet use the same systemd
# cgroup driver for consistent resource management.
echo "[5] Installing containerd"
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

# Enable systemd cgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# -------------------------------
# STEP 6: Add Kubernetes Repo
# -------------------------------
# WHY:
# Adds the official Kubernetes package repository.
# GPG key verification ensures packages are authenticated.
# Version v1.29 repository ensures Kubernetes components
# are installed from the selected release channel.
echo "[6] Adding Kubernetes repo"

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y

# -------------------------------
# STEP 7: Install Kubernetes
# -------------------------------
# WHY:
# kubelet - Runs on every node and manages Pods.
# kubeadm  - Initializes the control plane and joins nodes.
# kubectl  - CLI tool to communicate with the Kubernetes API.
#
# apt-mark hold prevents automatic package upgrades that
# could cause unexpected Kubernetes version changes.
echo "[7] Installing kubelet, kubeadm, kubectl"
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# -------------------------------
# STEP 8: Master Setup
# -------------------------------
# WHY:
# Initializes the Kubernetes Control Plane.
# Configures API Server advertisement address and Pod CIDR.
# Configures kubectl access for cluster administration.
# Installs Flannel CNI to provide Pod networking.
# Generates the worker join command for cluster registration.
if [[ "$1" == "master" ]]; then
  echo "[8] Initializing Kubernetes Master"

  kubeadm init --pod-network-cidr=10.244.0.0/16 \
    --apiserver-advertise-address=$(hostname -I | awk '{print $1}')

  echo "[9] Configuring kubectl"
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config

  echo "[10] Installing Flannel CNI"
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.4/Documentation/kube-flannel.yml

  echo "==== MASTER READY ===="
  kubeadm token create --print-join-command
fi

# -------------------------------
# STEP 9: Worker Join
# -------------------------------
# WHY:
# Registers the Worker Node with the existing Kubernetes
# Control Plane using the token and discovery information.
# Once joined, the node can run application Pods.
if [[ "$1" == "worker" ]]; then
  echo "[9] Joining Worker Node"
  kubeadm join $2
fi

# -------------------------------
# STEP 10: kubectl Autocomplete
# -------------------------------
# WHY:
# Enables Bash command autocompletion for kubectl.
# Helps administrators quickly find Kubernetes commands,
# resources and available command options.
echo "[10] Enabling kubectl autocomplete"
apt-get install -y bash-completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc

echo "==== Kubernetes Setup Completed Successfully ===="

