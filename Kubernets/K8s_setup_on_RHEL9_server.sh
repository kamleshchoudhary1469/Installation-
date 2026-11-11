
#!/bin/bash
set -e

# ============================================================
# Kubernetes Cluster Prerequisites Setup – RHEL / CentOS
# ============================================================
#
# PURPOSE:
# Automates the installation and configuration of Kubernetes
# prerequisites on RHEL / CentOS-based Linux servers.
#
# SUPPORTED NODE TYPES:
# 1. Master Node  - Initializes Kubernetes Control Plane.
# 2. Worker Node  - Joins an existing Kubernetes Cluster.
#
# WHY THIS CONFIGURATION IS REQUIRED:
# - Disable SELinux to avoid SELinux policy interference.
# - Disable Swap for kubelet compatibility.
# - Disable Firewalld to avoid firewall-related connectivity issues.
# - Load required kernel modules for container networking.
# - Configure sysctl parameters for Kubernetes networking.
# - Install required system dependencies.
# - Install containerd as the container runtime.
# - Configure systemd cgroup driver.
# - Configure the official Kubernetes package repository.
# - Install kubelet, kubeadm and kubectl.
# - Initialize the Kubernetes Control Plane.
# - Install Flannel CNI for Pod networking.
# - Join Worker Nodes to the Kubernetes Cluster.
# - Enable kubectl command autocompletion.
#
# EXECUTION:
# Master Node : bash k8s-setup.sh master
# Worker Node : bash k8s-setup.sh worker "<JOIN COMMAND>"
#
# ============================================================

echo "==== Kubernetes Prerequisites Setup (RHEL/CentOS) ===="

# -------------------------------
# STEP 1: Disable SELinux
# -------------------------------
# WHY:
# SELinux provides Mandatory Access Control (MAC) security.
# Its policies can restrict container runtime and Kubernetes
# operations if the required policies are not configured.
# This configuration disables SELinux enforcement.
echo "[1] Disabling SELinux"
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# -------------------------------
# STEP 2: Disable Swap
# -------------------------------
# WHY:
# Kubernetes kubelet requires swap to be disabled by default.
# Swap can affect predictable Pod memory management and
# Kubernetes node resource scheduling.
# swapoff disables currently active swap.
# /etc/fstab modification prevents swap from enabling after reboot.
echo "[2] Disabling Swap"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# -------------------------------
# STEP 3: Disable Firewall
# -------------------------------
# WHY:
# Firewalld can block communication between Kubernetes nodes.
# Kubernetes requires network communication between:
# - API Server (6443)
# - Kubelet (10250)
# - etcd (2379-2380)
# - Flannel VXLAN (8472/UDP)
# Disabling firewalld avoids firewall-related issues in this setup.
echo "[3] Disabling Firewalld"
systemctl stop firewalld || true
systemctl disable firewalld || true

# -------------------------------
# STEP 4: Load Kernel Modules
# -------------------------------
# WHY:
# overlay:
# Required for OverlayFS, which containerd uses for container
# image layers and writable container filesystems.
#
# br_netfilter:
# Allows bridged network traffic to be processed by iptables.
# This is important for Kubernetes Pod networking and
# network policy / packet forwarding operations.
#
# /etc/modules-load.d/k8s.conf:
# Ensures these kernel modules are loaded automatically
# during system startup.
echo "[4] Loading Kernel Modules"
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# -------------------------------
# STEP 5: Sysctl Config
# -------------------------------
# WHY:
# net.bridge.bridge-nf-call-iptables:
# Allows iptables to process bridged IPv4 traffic.
#
# net.bridge.bridge-nf-call-ip6tables:
# Allows ip6tables to process bridged IPv6 traffic.
#
# net.ipv4.ip_forward:
# Enables IPv4 packet forwarding between network interfaces.
# Required for communication between Kubernetes Pods,
# nodes and external networks.
#
# /etc/sysctl.d/k8s.conf:
# Stores persistent kernel network configurations.
#
# sysctl --system:
# Applies the configured kernel parameters immediately.
echo "[5] Configuring sysctl"
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# -------------------------------
# STEP 6: Install Dependencies
# -------------------------------
# WHY:
# Installs required packages for containerd installation
# and repository management.
#
# yum-utils:
# Provides repository management utilities.
#
# device-mapper-persistent-data:
# Provides device-mapper storage support.
#
# lvm2:
# Provides Logical Volume Manager utilities.
#
# curl:
# Used to download files and access remote repositories.
echo "[6] Installing dependencies"
dnf install -y yum-utils device-mapper-persistent-data lvm2 curl

# -------------------------------
# STEP 7: Install containerd
# -------------------------------
# WHY:
# containerd is the container runtime used by Kubernetes.
# It manages container images, container lifecycle and
# execution of containers through the CRI interface.
#
# Docker repository:
# Provides access to Docker's containerd.io package.
#
# containerd config default:
# Generates the default containerd configuration file.
#
# SystemdCgroup = true:
# Configures containerd to use the systemd cgroup driver.
# Kubernetes kubelet and containerd should use compatible
# cgroup drivers for proper resource management.
#
# systemctl daemon-reexec:
# Re-executes the systemd manager.
#
# systemctl enable --now containerd:
# Enables containerd at boot and starts it immediately.
echo "[7] Installing containerd"
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

dnf install -y containerd.io

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

# Enable systemd cgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl daemon-reexec
systemctl enable --now containerd

# -------------------------------
# STEP 8: Kubernetes Repo
# -------------------------------
# WHY:
# Adds the official Kubernetes RPM repository.
# This repository provides Kubernetes packages through DNF.
#
# baseurl:
# Specifies the Kubernetes v1.29 stable package repository.
#
# enabled=1:
# Enables this repository for package installation.
#
# gpgcheck=1:
# Enables GPG signature verification for package security.
#
# gpgkey:
# Specifies the repository signing key used to verify packages.
echo "[8] Adding Kubernetes repo"
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
EOF

# -------------------------------
# STEP 9: Install K8s Components
# -------------------------------
# WHY:
# kubelet:
# Runs on every Kubernetes node and manages Pods and containers.
#
# kubeadm:
# Automates Kubernetes cluster initialization and node joining.
#
# kubectl:
# Command-line tool used to communicate with the Kubernetes API
# Server and manage cluster resources.
#
# systemctl enable --now kubelet:
# Enables kubelet during system startup and starts the service.
echo "[9] Installing kubeadm, kubelet, kubectl"
dnf install -y kubelet kubeadm kubectl

systemctl enable --now kubelet

# -------------------------------
# STEP 10: Enable IP Forward Check
# -------------------------------
# WHY:
# Verifies whether IPv4 packet forwarding is enabled.
#
# Expected output:
# 1 = IP forwarding enabled.
# 0 = IP forwarding disabled.
#
# Kubernetes requires IP forwarding for Pod and network
# communication across different network interfaces.
echo "[10] IP Forward status:"
cat /proc/sys/net/ipv4/ip_forward

# -------------------------------
# STEP 11: Master Setup
# -------------------------------
# WHY:
# This section executes only when the script receives
# the "master" argument.
#
# kubeadm init:
# Initializes the Kubernetes Control Plane.
#
# --pod-network-cidr:
# Defines the Pod network range.
# 10.244.0.0/16 is the Pod CIDR used by this Flannel setup.
#
# --apiserver-advertise-address:
# Specifies the IP address through which other nodes
# communicate with the Kubernetes API Server.
#
# kubectl configuration:
# Copies admin.conf into the user's .kube directory.
# This allows the administrator to manage the cluster.
#
# Flannel CNI:
# Provides Pod-to-Pod networking across Kubernetes nodes.
#
# kubeadm token create:
# Generates the command required to join Worker Nodes
# to the Kubernetes Control Plane.
if [[ "$1" == "master" ]]; then
  echo "[11] Initializing Kubernetes Master"

  kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$(hostname -I | awk '{print $1}')

  echo "[12] Configuring kubectl"
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config

  echo "[13] Installing Flannel CNI"
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.4/Documentation/kube-flannel.yml

  echo "==== MASTER READY ===="
  kubeadm token create --print-join-command
fi

# -------------------------------
# STEP 12: Worker Join
# -------------------------------
# WHY:
# This section executes only when the script receives
# the "worker" argument.
#
# kubeadm join:
# Connects the Worker Node to the existing Kubernetes Cluster.
#
# The join command contains:
# - Control Plane API Server address and port.
# - Bootstrap token for authentication.
# - CA certificate hash for API Server verification.
#
# After successful joining, the Worker Node becomes
# available for scheduling application Pods.
if [[ "$1" == "worker" ]]; then
  echo "[12] Joining Worker Node"
  kubeadm join $2
fi

# -------------------------------
# STEP 13: kubectl Autocomplete
# -------------------------------
# WHY:
# Installs Bash completion support and enables kubectl
# command autocompletion.
#
# This helps administrators quickly find:
# - Kubernetes commands.
# - Resource types.
# - Namespace names.
# - Pod and deployment names.
# - Available command options.
#
# ~/.bashrc:
# Loads kubectl completion automatically in Bash sessions.
echo "[13] Enabling kubectl autocomplete"
dnf install -y bash-completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc

echo "==== Kubernetes Setup Completed Successfully ===="

