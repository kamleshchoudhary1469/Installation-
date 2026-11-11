
#!/bin/bash

set -e

# ============================================================
# KUBERNETES CLUSTER SETUP – RHEL / CENTOS 8
# ============================================================
#
# PURPOSE:
# This script prepares Linux servers and installs Kubernetes
# components with CRI-O as the container runtime.
#
# SUPPORTED NODES:
# 1. Master Node - Creates and manages the Kubernetes cluster.
# 2. Worker Node - Joins the existing Kubernetes cluster.
#
# COMPONENTS USED:
# - Kubernetes: Container orchestration platform.
# - CRI-O: Container runtime used to run containers.
# - kubeadm: Tool to initialize and join Kubernetes nodes.
# - kubelet: Service that manages Pods on each node.
# - kubectl: Command-line tool to manage the cluster.
# - Calico: Network plugin for Pod communication.
#
# EXECUTION:
# Master Node:
# bash k8s-setup.sh master
#
# Worker Node:
# bash k8s-setup.sh worker "<JOIN COMMAND>"
#
# ============================================================

echo "==== Kubernetes Cluster Setup (RHEL/CentOS 8) ===="

# --------------------------------------------------
# STEP 1: Disable SELinux
# --------------------------------------------------
# WHY:
# SELinux provides security by controlling access to files,
# processes and system resources.
# It can block some container operations if policies are
# not configured correctly.
# setenforce 0 temporarily changes SELinux to permissive mode.
# The configuration file disables SELinux after reboot.
echo "[1] Disabling SELinux"

setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# --------------------------------------------------
# STEP 2: Disable Swap
# --------------------------------------------------
# WHY:
# Kubernetes kubelet normally requires swap to be disabled.
# Swap uses disk space when RAM is full.
# Kubernetes needs predictable memory management for Pods.
# swapoff -a disables currently active swap.
# sed modifies fstab so swap does not start after reboot.
echo "[2] Disabling Swap"

swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# --------------------------------------------------
# STEP 3: Disable Firewall
# --------------------------------------------------
# WHY:
# Kubernetes nodes need to communicate with each other.
# Firewalld may block required Kubernetes ports and traffic.
# This command stops and disables the firewall.
# In production, configure the required firewall ports
# instead of completely disabling the firewall.
echo "[3] Disabling firewalld"

systemctl disable --now firewalld || true

# --------------------------------------------------
# STEP 4: Load Kernel Modules
# --------------------------------------------------
# WHY:
# overlay:
# Used by the container runtime to manage container
# image layers and container filesystems.
#
# br_netfilter:
# Allows bridged network traffic to pass through iptables.
# This is required for Kubernetes network communication.
#
# /etc/modules-load.d/k8s.conf:
# Saves the module names so they load automatically
# when the server starts.
#
# modprobe:
# Loads the kernel modules immediately without reboot.
echo "[4] Loading Kernel Modules"

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# --------------------------------------------------
# STEP 5: Configure Sysctl
# --------------------------------------------------
# WHY:
# These settings configure Linux kernel networking.
#
# bridge-nf-call-iptables:
# Allows iptables to process bridged IPv4 traffic.
#
# bridge-nf-call-ip6tables:
# Allows ip6tables to process bridged IPv6 traffic.
#
# ip_forward:
# Allows the server to forward network traffic
# between different network interfaces.
# Required for Pod communication across nodes.
#
# sysctl --system:
# Loads and applies the configured kernel settings.
echo "[5] Configuring sysctl"

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# --------------------------------------------------
# STEP 6: Install Dependencies
# --------------------------------------------------
# WHY:
# Installs packages required for Kubernetes and CRI-O setup.
#
# yum-utils:
# Provides tools to manage software repositories.
#
# device-mapper-persistent-data:
# Provides device-mapper storage support.
#
# lvm2:
# Manages Linux Logical Volumes.
#
# curl:
# Downloads files from remote servers.
#
# bash-completion:
# Provides command auto-completion in Bash.
#
# container-selinux:
# Provides SELinux policies needed by container software.
echo "[6] Installing dependencies"

dnf install -y \
yum-utils \
device-mapper-persistent-data \
lvm2 \
curl \
bash-completion \
container-selinux

# --------------------------------------------------
# STEP 7: Define Kubernetes & CRI-O Versions
# --------------------------------------------------
# WHY:
# Kubernetes and CRI-O versions should be compatible.
# Both versions are defined here so the correct
# package repositories can be configured.
#
# KUBERNETES_VERSION:
# Selects the Kubernetes package repository version.
#
# CRIO_VERSION:
# Selects the CRI-O package repository version.
#
# v1.34 means the stable 1.34 release series.
echo "[7] Setting Kubernetes and CRI-O versions"

KUBERNETES_VERSION=v1.34
CRIO_VERSION=v1.34

# --------------------------------------------------
# STEP 8: Add Kubernetes Repository
# --------------------------------------------------
# WHY:
# Adds the official Kubernetes RPM package repository.
#
# baseurl:
# Location from where Kubernetes packages are downloaded.
#
# enabled=1:
# Enables this repository for package installation.
#
# gpgcheck=1:
# Checks package signatures to improve package security.
#
# gpgkey:
# Provides the GPG key used to verify packages.
echo "[8] Adding Kubernetes repository"

cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/rpm/repodata/repomd.xml.key
EOF

# --------------------------------------------------
# STEP 9: Add CRI-O Repository
# --------------------------------------------------
# WHY:
# CRI-O is the container runtime used by Kubernetes.
# Kubernetes uses CRI (Container Runtime Interface)
# to communicate with the container runtime.
#
# This repository provides CRI-O installation packages.
#
# Matching the CRI-O minor version with the Kubernetes
# minor version helps maintain compatibility.
#
# GPG verification checks the package signatures.
echo "[9] Adding CRI-O repository"

cat <<EOF | tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/rpm/repodata/repomd.xml.key
EOF

# --------------------------------------------------
# STEP 10: Install Kubernetes Components
# --------------------------------------------------
# WHY:
# cri-o:
# Container runtime responsible for running containers.
#
# kubelet:
# Runs on every Kubernetes node and manages Pods.
#
# kubeadm:
# Initializes the Kubernetes Master and joins Worker Nodes.
#
# kubectl:
# Allows administrators to manage Kubernetes resources
# such as Pods, Deployments, Services and Namespaces.
echo "[10] Installing kubeadm, kubelet, kubectl and CRI-O"

dnf install -y cri-o kubelet kubeadm kubectl

# --------------------------------------------------
# STEP 11: Enable Services
# --------------------------------------------------
# WHY:
# CRI-O:
# Starts the container runtime service.
# It must be running before kubelet can manage containers.
#
# kubelet:
# Starts the Kubernetes node management service.
# It communicates with the API Server and container runtime.
#
# enable:
# Starts the service automatically after server reboot.
#
# --now:
# Starts the service immediately.
echo "[11] Enabling CRI-O and kubelet"

systemctl enable --now crio
systemctl enable --now kubelet

# --------------------------------------------------
# STEP 12: Verify Kernel Settings
# --------------------------------------------------
# WHY:
# Checks whether required network settings and kernel
# modules are enabled before Kubernetes initialization.
#
# Expected output:
# net.ipv4.ip_forward = 1
#
# lsmod:
# Displays currently loaded kernel modules.
#
# br_netfilter:
# Should appear in the output if successfully loaded.
echo "[12] Verifying kernel settings"

sysctl net.ipv4.ip_forward
lsmod | grep br_netfilter

# --------------------------------------------------
# STEP 13: Master Node Setup
# --------------------------------------------------
# WHY:
# This section runs only when the argument is "master".
#
# kubeadm init:
# Creates the Kubernetes Control Plane.
#
# --pod-network-cidr:
# Defines the IP address range used by Kubernetes Pods.
# 192.168.0.0/16 is the Pod CIDR selected for this setup.
#
# --apiserver-advertise-address:
# Defines the IP address through which Worker Nodes
# communicate with the Kubernetes API Server.
if [[ "$1" == "master" ]]; then

    echo "[13] Initializing Kubernetes Master"

    kubeadm init \
    --pod-network-cidr=192.168.0.0/16 \
    --apiserver-advertise-address=$(hostname -I | awk '{print $1}')

    # --------------------------------------------------
    # STEP 14: Configure kubectl
    # --------------------------------------------------
    # WHY:
    # admin.conf contains Kubernetes administrator credentials.
    # Copying it to ~/.kube/config allows the current user
    # to manage the cluster using kubectl.
    #
    # chown:
    # Gives the current user ownership of the config file.
    #
    # KUBECONFIG:
    # Specifies which Kubernetes configuration file to use.
    echo "[14] Configuring kubectl"

    mkdir -p $HOME/.kube

    cp -f /etc/kubernetes/admin.conf $HOME/.kube/config

    chown $(id -u):$(id -g) $HOME/.kube/config

    export KUBECONFIG=/etc/kubernetes/admin.conf

    # --------------------------------------------------
    # STEP 15: Install Calico CNI
    # --------------------------------------------------
    # WHY:
    # CNI means Container Network Interface.
    # Kubernetes needs a CNI plugin for Pod networking.
    #
    # Calico provides:
    # - Pod-to-Pod communication.
    # - Networking between Kubernetes nodes.
    # - Network routing.
    # - Network policies to control Pod traffic.
    #
    # tigera-operator.yaml:
    # Installs the Calico operator that manages Calico.
    #
    # custom-resources.yaml:
    # Creates the Calico networking configuration.
    #
    # sleep 30:
    # Waits for some time to allow Calico components
    # to start before checking cluster resources.
    echo "[15] Installing Calico Network Plugin"

    kubectl create -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

    kubectl apply -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml

    echo "Waiting for Calico pods to start..."
    sleep 30

    # Displays Kubernetes node status.
    kubectl get nodes

    # Displays Pods running in all namespaces.
    kubectl get pods -A

    echo "==== MASTER NODE READY ===="

    # Generates a token and complete command
    # required to register Worker Nodes in the cluster.
    echo "Worker Join Command:"
    kubeadm token create --print-join-command

fi

# --------------------------------------------------
# STEP 16: Worker Node Join
# --------------------------------------------------
# WHY:
# This section runs only when the argument is "worker".
#
# kubeadm join:
# Connects the Worker Node to the existing Master Node.
#
# The join command contains:
# - Kubernetes API Server address.
# - Authentication token.
# - CA certificate hash for secure verification.
#
# After successful joining, the Worker Node becomes
# available to run application Pods.
if [[ "$1" == "worker" ]]; then

    echo "[16] Joining Worker Node"

    kubeadm join $2

fi

# --------------------------------------------------
# STEP 17: Enable kubectl Autocomplete
# --------------------------------------------------
# WHY:
# Enables Bash completion for kubectl commands.
#
# This helps administrators automatically complete:
# - Kubernetes commands.
# - Resource names.
# - Pod names.
# - Namespace names.
#
# ~/.bashrc:
# Loads the autocomplete configuration in new Bash sessions.
echo "[17] Enabling kubectl autocomplete"

echo 'source <(kubectl completion bash)' >> ~/.bashrc

source ~/.bashrc

echo "==== Kubernetes Setup Completed Successfully ===="
