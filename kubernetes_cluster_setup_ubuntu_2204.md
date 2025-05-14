# Setting Up a Kubernetes Cluster on Ubuntu 22.04 (1 Master, 2 Nodes) using Kubeadm

This guide provides step-by-step instructions to create a basic Kubernetes cluster consisting of one master node and two worker nodes, all running Ubuntu 22.04. We will use `kubeadm` for this setup.

**Date:** 2025-05-14
**Author:** @ranjanjyoti152 (via Copilot)

## Table of Contents
1.  [Prerequisites (All Nodes)](#prerequisites-all-nodes)
2.  [Step 1: Prepare Each Node](#step-1-prepare-each-node)
    *   [Update System](#update-system)
    *   [Install Container Runtime (containerd)](#install-container-runtime-containerd)
    *   [Disable Swap](#disable-swap)
    *   [Configure Kernel Parameters](#configure-kernel-parameters)
    *   [Install Kubernetes Packages (`kubeadm`, `kubelet`, `kubectl`)](#install-kubernetes-packages-kubeadm-kubelet-kubectl)
3.  [Step 2: Initialize the Master Node](#step-2-initialize-the-master-node)
4.  [Step 3: Configure `kubectl` on Master Node](#step-3-configure-kubectl-on-master-node)
5.  [Step 4: Install a Pod Network Add-on (Master Node)](#step-4-install-a-pod-network-add-on-master-node)
6.  [Step 5: Join Worker Nodes to the Cluster](#step-5-join-worker-nodes-to-the-cluster)
7.  [Step 6: Verify Cluster Status (Master Node)](#step-6-verify-cluster-status-master-node)
8.  [Important Notes](#important-notes)

---

## Prerequisites (All Nodes)

Before you begin, ensure each of your three Ubuntu 22.04 machines meets the following requirements:

*   **Ubuntu 22.04 LTS** installed.
*   **Minimum 2 CPUs** per machine.
*   **Minimum 2GB RAM** per machine (more is recommended for the master node).
*   **Full network connectivity** between all machines. If using VMs, ensure they are on the same network and can reach each other.
*   **Unique hostname, MAC address, and `product_uuid`** for each machine.
    *   Check `product_uuid`: `sudo cat /sys/class/dmi/id/product_uuid`
*   **Specific ports open** between nodes. Refer to the [Kubernetes documentation](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) for the full list. Key ports include:
    *   **Master Node:** 6443, 2379-2380, 10250, 10251, 10252
    *   **Worker Nodes:** 10250, 30000-32767
*   **Sudo privileges** on all machines.

---

## Step 1: Prepare Each Node

Perform these steps on **ALL THREE** machines (the master and both worker nodes).

### Update System
```bash
sudo apt update
sudo apt upgrade -y
```

### Install Container Runtime (containerd)

Kubernetes requires a container runtime. We'll use `containerd`.

```bash
# Install dependencies
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker's official GPG key (containerd is part of Docker distribution)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the stable repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install containerd
sudo apt update
sudo apt install -y containerd.io

# Configure containerd to use systemd cgroup driver
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Disable Swap

`kubelet` requires swap to be disabled.

```bash
# Disable swap immediately
sudo swapoff -a

# Disable swap permanently (comment out swap entries in /etc/fstab)
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### Configure Kernel Parameters

Ensure netfilter bridge and IP forwarding are enabled.

```bash
# Load required kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Create a configuration file for sysctl
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Apply sysctl parameters without reboot
sudo sysctl --system
```

### Install Kubernetes Packages (`kubeadm`, `kubelet`, `kubectl`)

```bash
# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This is for K8s v1.29. For other versions, check the K8s documentation.

# Add Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package list and install Kubernetes tools
sudo apt update
sudo apt install -y kubelet kubeadm kubectl

# Hold the packages to prevent unintended updates
sudo apt-mark hold kubelet kubeadm kubectl
```

---

## Step 2: Initialize the Master Node

Perform these steps **ONLY ON THE MASTER NODE**.

1.  **Choose a Pod Network CIDR:**
    We'll use `192.168.0.0/16` for this example (Calico's default). If you choose a different one, ensure your network add-on supports it.

2.  **Initialize the Kubernetes Control Plane:**
    Replace `<MASTER_NODE_IP>` with the actual private IP address of your master node.

    ```bash
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=<MASTER_NODE_IP>
    ```
    *   `--pod-network-cidr`: Essential for the pod network add-on.
    *   `--apiserver-advertise-address`: The IP address the API Server will advertise on.

3.  **Important Output:**
    After successful initialization, `kubeadm init` will output:
    *   Commands to set up `kubectl` for your user (see next step).
    *   A `kubeadm join` command with a token and hash. **COPY THIS JOIN COMMAND AND SAVE IT SECURELY.** You will need it to join your worker nodes to the cluster. It looks something like this:
        ```
        kubeadm join <MASTER_NODE_IP>:6443 --token <YOUR_TOKEN> \
            --discovery-token-ca-cert-hash sha256:<YOUR_HASH>
        ```

---

## Step 3: Configure `kubectl` on Master Node

Perform these steps **ONLY ON THE MASTER NODE** to interact with your new cluster.

```bash
# Create .kube directory if it doesn't exist
mkdir -p $HOME/.kube

# Copy the admin configuration to your user's .kube directory
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Set the correct ownership
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

You can verify `kubectl` access by running:
```bash
kubectl get nodes
```
Initially, you'll see only the master node, and its status might be `NotReady` until a pod network is installed.

---

## Step 4: Install a Pod Network Add-on (Master Node)

Perform these steps **ONLY ON THE MASTER NODE**.
A Pod Network is necessary for pods to communicate across nodes. We will use Calico.

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```
*(Ensure you use a Calico version compatible with your Kubernetes version. Check Calico's documentation for the latest manifest URL.)*

Wait a few minutes for the Calico pods to start. You can check their status:
```bash
kubectl get pods -n kube-system
```
Once the Calico pods are running, your master node's status should change to `Ready` when you run `kubectl get nodes`.

---

## Step 5: Join Worker Nodes to the Cluster

Perform these steps **ON EACH WORKER NODE**.

Use the `kubeadm join` command that you saved from the `kubeadm init` output on the master node. It will look similar to this:

```bash
sudo kubeadm join <MASTER_NODE_IP>:6443 --token <YOUR_TOKEN> \
    --discovery-token-ca-cert-hash sha256:<YOUR_HASH>
```
Replace `<MASTER_NODE_IP>`, `<YOUR_TOKEN>`, and `<YOUR_HASH>` with the actual values from your `kubeadm init` output.

If you lost the token or it expired, you can generate a new one on the **master node**:
```bash
sudo kubeadm token create --print-join-command
```
This will output a new `kubeadm join` command.

---

## Step 6: Verify Cluster Status (Master Node)

Go back to your **MASTER NODE**.
Check the status of all nodes in the cluster:

```bash
kubectl get nodes -o wide
```
You should see all three nodes (1 master, 2 workers) listed with a status of `Ready`. It might take a few minutes for the worker nodes to become ready after joining.

Example output:
```
NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
master-node    Ready    control-plane   10m   v1.29.x   192.168.1.10   <none>        Ubuntu 22.04.x LTS   5.15.0-xx-generic   containerd://1.7.x
worker-node1   Ready    <none>          5m    v1.29.x   192.168.1.11   <none>        Ubuntu 22.04.x LTS   5.15.0-xx-generic   containerd://1.7.x
worker-node2   Ready    <none>          5m    v1.29.x   192.168.1.12   <none>        Ubuntu 22.04.x LTS   5.15.0-xx-generic   containerd://1.7.x
```

**Congratulations! You have successfully set up a Kubernetes cluster.**

---

## Important Notes

*   **Firewall:** Ensure your firewall (e.g., `ufw`) is configured to allow traffic on the necessary ports between the nodes.
    *   On Master: `sudo ufw allow 6443/tcp`, `sudo ufw allow 2379:2380/tcp`, `sudo ufw allow 10250/tcp`, `sudo ufw allow 10251/tcp`, `sudo ufw allow 10252/tcp` (and ports for your CNI, e.g., Calico might use BGP port 179).
    *   On Workers: `sudo ufw allow 10250/tcp`, `sudo ufw allow 30000:32767/tcp` (and CNI ports).
    *   Allow traffic from your pod network CIDR and service CIDR if necessary.
*   **Persistent Storage:** This setup does not include persistent storage solutions. For stateful applications, you'll need to configure persistent volumes.
*   **Security:** This is a basic setup. For production environments, implement further security measures (RBAC, network policies, secrets management, etc.).
*   **Troubleshooting:**
    *   Check `kubelet` logs: `sudo journalctl -u kubelet -f`
    *   Check `containerd` logs: `sudo journalctl -u containerd -f`
    *   Describe pods or nodes for issues: `kubectl describe pod <pod-name> -n <namespace>`, `kubectl describe node <node-name>`
*   **Versions:** Kubernetes, Calico, and `containerd` versions are rapidly evolving. Always refer to the official documentation for the latest compatible versions and installation instructions. The versions used here (e.g., K8s v1.29, Calico v3.27.0) are examples and might need adjustment based on current releases.

---
This document provides a foundation. For advanced configurations, high availability, and production best practices, consult the official Kubernetes documentation.