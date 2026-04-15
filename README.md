# 🚀 Kubernetes Setup Guide (RHEL / CentOS)

This guide explains how to install and set up a Kubernetes cluster using the provided script (`k8s_setup.sh`) on **RHEL / CentOS machines (VMs or instances)**.

---
## 📋 Prerequisites

Before starting, make sure:

* You have **at least 2 machines**

  * 1 Master Node
  * 1 or more Worker Nodes
* OS: **RHEL 8/9 or CentOS Stream 8/9**
* Root or sudo access
* Internet connectivity enabled

---

## 📁 Step 1: Copy Script to All Nodes
Copy the script (`k8s_setup.sh`) to **all machines (master + workers)**.

Example:
scp k8s_setup.sh user@<node-ip>:/root/

---

## 🔐 Step 2: Give Execute Permission
Run on all nodes:
chmod +x k8s_setup.sh

---

## 🧠 Step 3: Setup Master Node
Login to your **master node**, then run:
./k8s_setup.sh master


### ✅ What this does:

* Installs container runtime (containerd)
* Installs Kubernetes components (kubeadm, kubelet, kubectl)
* Initializes Kubernetes cluster
* Configures kubectl
* Installs Flannel CNI network
* Generates **join command for worker nodes**

---

## 📌 Important Output (SAVE THIS)
After master setup, you will see output like:

kubeadm join <MASTER-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>


👉 **Copy this command** — you will need it for worker nodes.

---

## ⚙️ Step 4: Setup Worker Node(s)
Login to each **worker node**, then run:

./k8s_setup.sh worker "<paste-join-command>"


### Example:

./k8s_setup.sh worker "kubeadm join 192.168.1.10:6443 --token abc123... --discovery-token-ca-cert-hash sha256:xyz456..."

---

## 🔍 Step 5: Verify Cluster

Run this on **master node**:
kubectl get nodes


### ✅ Expected Output:
NAME        STATUS   ROLES           AGE   VERSION
master      Ready    control-plane   ...
worker1     Ready    <none>          ...

---

## 🧪 Step 6: Test Deployment (Optional)
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc

---

## ⚠️ Notes

* Firewall is disabled in this setup (good for lab/testing)
* Swap is disabled (required for Kubernetes)
* SELinux is set to permissive mode
* Uses **Flannel CNI** for networking

---
## ❗ Troubleshooting

### Check node status:
kubectl get nodes


### Check pods
kubectl get pods -A


### Restart kubelet:
systemctl restart kubelet


---

## Summary
| Step           | Command                                  |
| -------------- | ---------------------------------------- |
| Master Setup   | `./k8s_setup.sh master`                   |
| Worker Join    | `./k8s_setup.sh worker "<join-command>"` |
| Verify Cluster | `kubectl get nodes`                      |

---

## 👍 You're Done!
Your Kubernetes cluster is now ready to use 🚀



