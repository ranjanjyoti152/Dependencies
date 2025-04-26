#!/bin/bash

# Cockpit Manager Script for Ubuntu
# Includes GPU utilization monitoring and GPU passthrough for VMs
# Author: ranjanjyoti152
# Date: 2025-04-26 05:26:25

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        echo "Please run with sudo or as root user."
        exit 1
    fi
}

# Function to check if a package exists in repos
package_exists() {
    apt-cache show "$1" &>/dev/null
    return $?
}

# Function to set appropriate permissions for files and directories
set_secure_permissions() {
    local path="$1"
    local type="$2"  # "file" or "dir"
    local is_executable="$3"  # true or false for files
    
    if [ "$type" = "file" ]; then
        if [ "$is_executable" = "true" ]; then
            # Executable files: owner can read/write/execute, group/others can read/execute
            chmod 755 "$path"
        else
            # Non-executable files: owner can read/write, group/others can read
            chmod 644 "$path"
        fi
        # Ensure root ownership
        chown root:root "$path"
    elif [ "$type" = "dir" ]; then
        # Directories: owner can read/write/exec, group/others can read/exec
        chmod 755 "$path"
        chown root:root "$path"
    fi
}

# Function to install Cockpit with all dependencies and features
install_cockpit() {
    echo -e "${YELLOW}Starting Cockpit installation...${NC}"
    
    # Update package lists
    echo -e "${YELLOW}Updating package lists...${NC}"
    apt update -y || { echo -e "${RED}Failed to update package lists!${NC}"; exit 1; }
    
    # Install Cockpit base package
    echo -e "${YELLOW}Installing Cockpit base package...${NC}"
    apt install -y cockpit || { echo -e "${RED}Failed to install Cockpit!${NC}"; exit 1; }
    
    # Install all official Cockpit modules available in the repositories
    echo -e "${YELLOW}Installing available official Cockpit modules...${NC}"
    
    # Core modules most likely to be available in Ubuntu
    CORE_MODULES="cockpit-pcp cockpit-packagekit cockpit-storaged cockpit-podman cockpit-networkmanager cockpit-system cockpit-ws cockpit-bridge"
    apt install -y $CORE_MODULES || { echo -e "${YELLOW}Warning: Some core modules could not be installed. Continuing...${NC}"; }
    
    # Additional modules that might not be available in all Ubuntu versions
    echo -e "${YELLOW}Checking for additional Cockpit modules...${NC}"
    ADDITIONAL_MODULES=""
    
    # Check each module individually
    for module in cockpit-machines cockpit-sosreport cockpit-389-ds cockpit-navigator cockpit-certificate cockpit-file-sharing cockpit-ostree; do
        if package_exists "$module"; then
            ADDITIONAL_MODULES="$ADDITIONAL_MODULES $module"
        else
            echo -e "${YELLOW}Module $module is not available in your repositories. Skipping...${NC}"
        fi
    done
    
    # Install additional modules if any are available
    if [ -n "$ADDITIONAL_MODULES" ]; then
        echo -e "${YELLOW}Installing additional available Cockpit modules...${NC}"
        apt install -y $ADDITIONAL_MODULES || { echo -e "${YELLOW}Warning: Some additional modules could not be installed. Continuing...${NC}"; }
    fi
    
    # Install GPU monitoring and passthrough capabilities
    install_gpu_support
    
    # Enable and start Cockpit socket service
    echo -e "${YELLOW}Enabling and starting Cockpit service...${NC}"
    systemctl enable --now cockpit.socket || { echo -e "${RED}Failed to enable Cockpit service!${NC}"; exit 1; }
    
    # Open firewall if ufw is active
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        echo -e "${YELLOW}Opening firewall port for Cockpit (9090)...${NC}"
        ufw allow 9090/tcp || { echo -e "${RED}Failed to open firewall port!${NC}"; }
    fi
    
    # Display installed Cockpit modules
    echo -e "${GREEN}Installed Cockpit modules:${NC}"
    dpkg -l | grep cockpit | awk '{print "- " $2}' | sort
    
    # Check if Cockpit is running
    if systemctl is-active --quiet cockpit.socket; then
        # Get server IP for user convenience
        SERVER_IP=$(hostname -I | awk '{print $1}')
        echo -e "${GREEN}Cockpit successfully installed!${NC}"
        echo -e "${GREEN}You can access Cockpit by navigating to:${NC}"
        echo -e "${GREEN}https://$SERVER_IP:9090${NC}"
        echo -e "${GREEN}or${NC}"
        echo -e "${GREEN}https://$(hostname):9090${NC}"
    else
        echo -e "${RED}Something went wrong. Cockpit service is not running.${NC}"
        exit 1
    fi
}

# Function to install GPU support for monitoring and passthrough
install_gpu_support() {
    echo -e "${BLUE}Setting up GPU monitoring and passthrough capabilities...${NC}"
    
    # Create necessary directories with proper permissions
    mkdir -p /usr/local/bin
    set_secure_permissions "/usr/local/bin" "dir"
    
    mkdir -p /var/run
    set_secure_permissions "/var/run" "dir"
    
    # Install PCP (Performance Co-Pilot) for monitoring
    echo -e "${YELLOW}Installing Performance Co-Pilot for system monitoring...${NC}"
    apt install -y pcp || { echo -e "${RED}Failed to install Performance Co-Pilot!${NC}"; }
    
    # Check for NVIDIA GPUs
    if lspci | grep -i nvidia > /dev/null; then
        echo -e "${YELLOW}NVIDIA GPU detected. Installing NVIDIA monitoring tools...${NC}"
        
        # Install NVIDIA driver and tools if not already installed
        if ! command -v nvidia-smi &> /dev/null; then
            echo -e "${YELLOW}Installing NVIDIA drivers and tools...${NC}"
            apt install -y nvidia-utils-* nvidia-driver-* || { echo -e "${RED}Failed to install NVIDIA drivers. You might need to install them manually.${NC}"; }
        fi
        
        # Install NVTOP for GPU monitoring
        if ! package_exists "nvtop"; then
            echo -e "${YELLOW}Adding universe repository for NVTOP...${NC}"
            add-apt-repository -y universe
            apt update -y
        fi
        
        echo -e "${YELLOW}Installing NVTOP for GPU monitoring...${NC}"
        apt install -y nvtop || { echo -e "${RED}Failed to install NVTOP.${NC}"; }
        
        # Create a script to collect NVIDIA metrics
        cat > /usr/local/bin/collect_nvidia_metrics.sh << 'EOF'
#!/bin/bash

# Exit if nvidia-smi is not available
if ! command -v nvidia-smi &> /dev/null; then
    exit 1
fi

# Collect GPU metrics
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu,memory.total,memory.used,memory.free --format=csv,noheader,nounits

# Exit with success
exit 0
EOF
        
        # Set appropriate permissions
        set_secure_permissions "/usr/local/bin/collect_nvidia_metrics.sh" "file" "true"
        
        # Create a systemd service to run the collection script periodically
        cat > /etc/systemd/system/nvidia-metrics.service << 'EOF'
[Unit]
Description=NVIDIA GPU Metrics Collection
After=network.target

[Service]
ExecStart=/bin/bash -c 'while true; do /usr/local/bin/collect_nvidia_metrics.sh > /var/run/nvidia_metrics.csv; sleep 5; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        # Set appropriate permissions
        set_secure_permissions "/etc/systemd/system/nvidia-metrics.service" "file" "false"
        
        # Enable and start the service
        systemctl daemon-reload
        systemctl enable --now nvidia-metrics.service
        
        echo -e "${GREEN}NVIDIA metrics collection configured.${NC}"
    fi
    
    # Check for AMD GPUs
    if lspci | grep -i amd > /dev/null || lspci | grep -i radeon > /dev/null; then
        echo -e "${YELLOW}AMD GPU detected. Installing AMD monitoring tools...${NC}"
        
        # Install AMD driver and tools
        apt install -y radeontop || { echo -e "${RED}Failed to install AMD monitoring tools.${NC}"; }
        
        # Create a script to collect AMD metrics
        cat > /usr/local/bin/collect_amd_metrics.sh << 'EOF'
#!/bin/bash

# Exit if radeontop is not available
if ! command -v radeontop &> /dev/null; then
    exit 1
fi

# Collect GPU metrics (run radeontop in dump mode for one sample)
radeontop -d - -l 1 | grep -v "^$"

# Exit with success
exit 0
EOF
        
        # Set appropriate permissions
        set_secure_permissions "/usr/local/bin/collect_amd_metrics.sh" "file" "true"
        
        # Create a systemd service to run the collection script periodically
        cat > /etc/systemd/system/amd-metrics.service << 'EOF'
[Unit]
Description=AMD GPU Metrics Collection
After=network.target

[Service]
ExecStart=/bin/bash -c 'while true; do /usr/local/bin/collect_amd_metrics.sh > /var/run/amd_metrics.txt; sleep 5; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        # Set appropriate permissions
        set_secure_permissions "/etc/systemd/system/amd-metrics.service" "file" "false"
        
        # Enable and start the service
        systemctl daemon-reload
        systemctl enable --now amd-metrics.service
        
        echo -e "${GREEN}AMD metrics collection configured.${NC}"
    fi
    
    # Create a Cockpit extension for GPU monitoring
    echo -e "${YELLOW}Creating Cockpit extension for GPU monitoring...${NC}"
    
    # Create directory for custom Cockpit extension
    mkdir -p /usr/share/cockpit/gpu-monitor
    set_secure_permissions "/usr/share/cockpit/gpu-monitor" "dir"
    
    # Create manifest.json
    cat > /usr/share/cockpit/gpu-monitor/manifest.json << 'EOF'
{
    "version": 1,
    "name": "gpu-monitor",
    "description": "GPU Monitoring for Cockpit",
    "requires": {
        "cockpit": "122"
    },
    "menu": {
        "index": {
            "label": "GPU Monitor",
            "order": 35,
            "icon": "fa-microchip"
        }
    }
}
EOF
    
    # Set appropriate permissions
    set_secure_permissions "/usr/share/cockpit/gpu-monitor/manifest.json" "file" "false"
    
    # Create HTML page for the extension
    cat > /usr/share/cockpit/gpu-monitor/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GPU Monitor</title>
    <link rel="stylesheet" href="../base1/patternfly.css">
    <script src="../base1/jquery.js"></script>
    <script src="../base1/cockpit.js"></script>
    <style>
        .gpu-card {
            margin-bottom: 20px;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        .gpu-metric {
            margin: 10px 0;
            padding: 5px;
            background-color: #f8f8f8;
            border-radius: 3px;
        }
        .metric-name {
            font-weight: bold;
            display: inline-block;
            width: 150px;
        }
        .metric-value {
            display: inline-block;
        }
        .refresh-btn {
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container-fluid">
        <h1>GPU Monitoring</h1>
        <button id="refresh-btn" class="btn btn-primary refresh-btn">Refresh Data</button>
        
        <div id="gpu-cards"></div>
        
        <div id="no-gpu-message" style="display:none;">
            <div class="alert alert-info">
                <span class="pficon pficon-info"></span>
                <strong>No GPU detected or GPU monitoring tools are not installed.</strong>
            </div>
        </div>
    </div>

    <script>
        $(function() {
            function checkNvidiaGPU() {
                return cockpit.script("test -f /var/run/nvidia_metrics.csv && echo yes || echo no")
                    .then(function(data) {
                        return data.trim() === "yes";
                    });
            }
            
            function checkAmdGPU() {
                return cockpit.script("test -f /var/run/amd_metrics.txt && echo yes || echo no")
                    .then(function(data) {
                        return data.trim() === "yes";
                    });
            }
            
            function getNvidiaMetrics() {
                return cockpit.script("cat /var/run/nvidia_metrics.csv")
                    .then(function(data) {
                        const lines = data.trim().split('\n');
                        const gpus = [];
                        
                        lines.forEach((line, index) => {
                            const values = line.split(', ');
                            if (values.length >= 6) {
                                gpus.push({
                                    id: index,
                                    type: 'NVIDIA',
                                    utilization: values[0],
                                    memoryUtilization: values[1],
                                    temperature: values[2],
                                    memoryTotal: values[3],
                                    memoryUsed: values[4],
                                    memoryFree: values[5]
                                });
                            }
                        });
                        
                        return gpus;
                    });
            }
            
            function getAmdMetrics() {
                return cockpit.script("cat /var/run/amd_metrics.txt")
                    .then(function(data) {
                        const lines = data.trim().split('\n');
                        const gpu = {
                            id: 0,
                            type: 'AMD',
                            metrics: {}
                        };
                        
                        lines.forEach(line => {
                            const parts = line.split(':');
                            if (parts.length === 2) {
                                const key = parts[0].trim();
                                const value = parts[1].trim();
                                gpu.metrics[key] = value;
                            }
                        });
                        
                        return [gpu];
                    });
            }
            
            function updateGPUDisplay() {
                Promise.all([checkNvidiaGPU(), checkAmdGPU()])
                    .then(function([hasNvidia, hasAmd]) {
                        const promises = [];
                        
                        if (hasNvidia) {
                            promises.push(getNvidiaMetrics());
                        }
                        
                        if (hasAmd) {
                            promises.push(getAmdMetrics());
                        }
                        
                        if (promises.length === 0) {
                            $('#gpu-cards').hide();
                            $('#no-gpu-message').show();
                            return;
                        }
                        
                        return Promise.all(promises)
                            .then(function(results) {
                                $('#gpu-cards').empty();
                                
                                results.forEach(gpus => {
                                    gpus.forEach(gpu => {
                                        let html = '';
                                        
                                        if (gpu.type === 'NVIDIA') {
                                            html = `
                                                <div class="gpu-card">
                                                    <h3>${gpu.type} GPU #${gpu.id + 1}</h3>
                                                    <div class="gpu-metric">
                                                        <span class="metric-name">GPU Utilization:</span>
                                                        <span class="metric-value">${gpu.utilization}%</span>
                                                    </div>
                                                    <div class="gpu-metric">
                                                        <span class="metric-name">Memory Utilization:</span>
                                                        <span class="metric-value">${gpu.memoryUtilization}%</span>
                                                    </div>
                                                    <div class="gpu-metric">
                                                        <span class="metric-name">Temperature:</span>
                                                        <span class="metric-value">${gpu.temperature}°C</span>
                                                    </div>
                                                    <div class="gpu-metric">
                                                        <span class="metric-name">Memory Total:</span>
                                                        <span class="metric-value">${gpu.memoryTotal} MB</span>
                                                    </div>
                                                    <div class="gpu-metric">
                                                        <span class="metric-name">Memory Used:</span>
                                                        <span class="metric-value">${gpu.memoryUsed} MB</span>
                                                    </div>
                                                    <div class="gpu-metric">
                                                        <span class="metric-name">Memory Free:</span>
                                                        <span class="metric-value">${gpu.memoryFree} MB</span>
                                                    </div>
                                                </div>
                                            `;
                                        } else if (gpu.type === 'AMD') {
                                            html = `
                                                <div class="gpu-card">
                                                    <h3>${gpu.type} GPU #${gpu.id + 1}</h3>
                                                `;
                                                
                                            for (const [key, value] of Object.entries(gpu.metrics)) {
                                                html += `
                                                    <div class="gpu-metric">
                                                        <span class="metric-name">${key}:</span>
                                                        <span class="metric-value">${value}</span>
                                                    </div>
                                                `;
                                            }
                                            
                                            html += `</div>`;
                                        }
                                        
                                        $('#gpu-cards').append(html);
                                    });
                                });
                                
                                $('#gpu-cards').show();
                                $('#no-gpu-message').hide();
                            });
                    });
            }
            
            $('#refresh-btn').on('click', function() {
                updateGPUDisplay();
            });
            
            // Initial update
            updateGPUDisplay();
            
            // Update every 10 seconds
            setInterval(updateGPUDisplay, 10000);
        });
    </script>
</body>
</html>
EOF
    
    # Set appropriate permissions
    set_secure_permissions "/usr/share/cockpit/gpu-monitor/index.html" "file" "false"
    
    echo -e "${GREEN}Cockpit GPU monitoring extension created.${NC}"
    
    # Setup for GPU passthrough to VMs
    echo -e "${BLUE}Setting up GPU passthrough for virtual machines...${NC}"
    
    # Check if virtualization is supported
    if ! grep -E 'vmx|svm' /proc/cpuinfo > /dev/null; then
        echo -e "${RED}CPU virtualization not detected. GPU passthrough may not work.${NC}"
    else
        # Install required virtualization packages
        echo -e "${YELLOW}Installing virtualization requirements for GPU passthrough...${NC}"
        apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager || { echo -e "${RED}Failed to install some virtualization packages.${NC}"; }
        
        # Enable IOMMU in GRUB if not already enabled
        if ! grep -q "intel_iommu=on" /etc/default/grub && ! grep -q "amd_iommu=on" /etc/default/grub; then
            echo -e "${YELLOW}Enabling IOMMU in GRUB configuration...${NC}"
            
            # Detect CPU vendor for correct IOMMU parameter
            if grep -q "GenuineIntel" /proc/cpuinfo; then
                IOMMU_PARAM="intel_iommu=on iommu=pt"
            else
                IOMMU_PARAM="amd_iommu=on iommu=pt"
            fi
            
            # Update GRUB command line
            sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$IOMMU_PARAM /" /etc/default/grub
            update-grub
            
            echo -e "${YELLOW}IOMMU has been enabled. A system reboot will be required for GPU passthrough to work.${NC}"
        fi
        
        # Configure VFIO if needed
        if ! grep -q "vfio" /etc/modules; then
            echo -e "${YELLOW}Configuring VFIO kernel modules...${NC}"
            cat >> /etc/modules << EOF
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
            
            # Set appropriate permissions
            set_secure_permissions "/etc/modules" "file" "false"
            
            # Create modprobe config for VFIO
            cat > /etc/modprobe.d/vfio.conf << EOF
options vfio-pci ids=
softdep nvidia pre: vfio-pci
softdep amdgpu pre: vfio-pci
EOF
            
            # Set appropriate permissions
            set_secure_permissions "/etc/modprobe.d/vfio.conf" "file" "false"
            
            echo -e "${YELLOW}VFIO modules configured. You'll need to add your GPU's vendor and device IDs to enable full passthrough.${NC}"
            echo -e "${YELLOW}You can use 'lspci -nn' to identify your GPU's IDs.${NC}"
        fi
        
        # Enable nested virtualization if on an Intel CPU
        if grep -q "GenuineIntel" /proc/cpuinfo; then
            echo -e "${YELLOW}Enabling nested virtualization for Intel CPUs...${NC}"
            if [ ! -f /etc/modprobe.d/kvm-intel.conf ]; then
                echo "options kvm-intel nested=1" > /etc/modprobe.d/kvm-intel.conf
                # Set appropriate permissions
                set_secure_permissions "/etc/modprobe.d/kvm-intel.conf" "file" "false"
                echo -e "${YELLOW}Nested virtualization enabled for Intel CPU.${NC}"
            fi
        fi
        
        # Enable nested virtualization if on an AMD CPU
        if grep -q "AuthenticAMD" /proc/cpuinfo; then
            echo -e "${YELLOW}Enabling nested virtualization for AMD CPUs...${NC}"
            if [ ! -f /etc/modprobe.d/kvm-amd.conf ]; then
                echo "options kvm-amd nested=1" > /etc/modprobe.d/kvm-amd.conf
                # Set appropriate permissions
                set_secure_permissions "/etc/modprobe.d/kvm-amd.conf" "file" "false"
                echo -e "${YELLOW}Nested virtualization enabled for AMD CPU.${NC}"
            fi
        fi
        
        # Create a helper script for GPU passthrough
        cat > /usr/local/bin/setup-gpu-passthrough.sh << 'EOF'
#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root!${NC}"
    exit 1
fi

echo -e "${YELLOW}Detecting available GPUs for passthrough...${NC}"
lspci -nn | grep -i "VGA\|3D\|Display" 

echo
echo -e "${YELLOW}To enable GPU passthrough, enter the GPU's vendor and device IDs${NC}"
echo -e "${YELLOW}Example format: 10de:1234,10de:5678${NC}"
echo -e "${YELLOW}(Leave empty to cancel)${NC}"
read -p "Enter GPU IDs: " gpu_ids

if [ -z "$gpu_ids" ]; then
    echo -e "${YELLOW}No IDs entered. Exiting without changes.${NC}"
    exit 0
fi

# Update VFIO config
echo -e "${YELLOW}Updating VFIO configuration...${NC}"
sed -i "s/options vfio-pci ids=/options vfio-pci ids=$gpu_ids/" /etc/modprobe.d/vfio.conf

echo -e "${YELLOW}Updating initramfs...${NC}"
update-initramfs -u

echo -e "${GREEN}Configuration complete. Please reboot your system.${NC}"
echo -e "${GREEN}After reboot, you can create a VM in Cockpit and add the GPU as a PCI device.${NC}"
EOF

        # Set appropriate permissions
        set_secure_permissions "/usr/local/bin/setup-gpu-passthrough.sh" "file" "true"
        
        # Create a helper script for identifying GPUs
        cat > /usr/local/bin/list-gpus.sh << 'EOF'
#!/bin/bash

echo "GPU devices available for passthrough:"
echo "--------------------------------------"
lspci -nnk | grep -A 3 "VGA\|3D\|Display"
echo
echo "Use the IDs in brackets [vendor:device] with the setup-gpu-passthrough.sh script"
EOF

        # Set appropriate permissions
        set_secure_permissions "/usr/local/bin/list-gpus.sh" "file" "true"
    fi
    
    # Install Cockpit machines module if available
    if ! dpkg -l | grep -q cockpit-machines; then
        echo -e "${YELLOW}Installing Cockpit VM management module...${NC}"
        apt install -y cockpit-machines || { echo -e "${RED}Failed to install Cockpit VM management module.${NC}"; }
    fi
    
    # Fix permissions for all created files
    echo -e "${YELLOW}Setting appropriate permissions for all files...${NC}"
    find /usr/local/bin -type f -name "*.sh" -exec chmod 755 {} \;
    find /etc/systemd/system -name "*.service" -exec chmod 644 {} \;
    find /usr/share/cockpit -type f -exec chmod 644 {} \;
    find /usr/share/cockpit -type d -exec chmod 755 {} \;
    
    echo -e "${GREEN}GPU support setup complete.${NC}"
    echo -e "${YELLOW}Note: A system reboot may be required for some changes to take effect.${NC}"
    echo -e "${YELLOW}To list available GPUs, run: ${NC}sudo /usr/local/bin/list-gpus.sh"
    echo -e "${YELLOW}To setup GPU passthrough, run: ${NC}sudo /usr/local/bin/setup-gpu-passthrough.sh"
}

# Function to remove Cockpit and its components
remove_cockpit() {
    echo -e "${YELLOW}Removing Cockpit and all its components...${NC}"
    
    # Stop and disable Cockpit service
    echo -e "${YELLOW}Stopping Cockpit service...${NC}"
    systemctl stop cockpit.socket
    systemctl disable cockpit.socket
    
    # Stop and disable GPU monitoring services
    echo -e "${YELLOW}Stopping GPU monitoring services...${NC}"
    systemctl stop nvidia-metrics.service 2>/dev/null || true
    systemctl disable nvidia-metrics.service 2>/dev/null || true
    systemctl stop amd-metrics.service 2>/dev/null || true
    systemctl disable amd-metrics.service 2>/dev/null || true
    
    # Remove custom GPU monitoring scripts and services
    echo -e "${YELLOW}Removing custom GPU monitoring components...${NC}"
    rm -f /usr/local/bin/collect_nvidia_metrics.sh 2>/dev/null || true
    rm -f /usr/local/bin/collect_amd_metrics.sh 2>/dev/null || true
    rm -f /etc/systemd/system/nvidia-metrics.service 2>/dev/null || true
    rm -f /etc/systemd/system/amd-metrics.service 2>/dev/null || true
    rm -f /usr/local/bin/setup-gpu-passthrough.sh 2>/dev/null || true
    rm -f /usr/local/bin/list-gpus.sh 2>/dev/null || true
    systemctl daemon-reload
    
    # Remove GPU monitoring extension
    echo -e "${YELLOW}Removing GPU monitoring extension...${NC}"
    rm -rf /usr/share/cockpit/gpu-monitor 2>/dev/null || true
    
    # Remove all Cockpit packages
    echo -e "${YELLOW}Removing all Cockpit packages...${NC}"
    apt remove -y cockpit cockpit-* || { echo -e "${RED}Failed to remove some Cockpit packages!${NC}"; }
    
    # Purge configurations
    echo -e "${YELLOW}Purging Cockpit configurations...${NC}"
    apt purge -y cockpit cockpit-* || { echo -e "${RED}Failed to purge some Cockpit configurations!${NC}"; }
    
    # Remove GPU monitoring tools
    echo -e "${YELLOW}Removing GPU monitoring tools...${NC}"
    apt remove -y nvtop radeontop 2>/dev/null || true
    
    # Clean up
    echo -e "${YELLOW}Cleaning up...${NC}"
    apt autoremove -y
    
    echo -e "${GREEN}Cockpit and related components have been successfully removed from your system.${NC}"
}

# Function to update Cockpit to the latest version
update_cockpit() {
    echo -e "${YELLOW}Updating Cockpit to the latest version...${NC}"
    
    # Update package lists
    echo -e "${YELLOW}Updating package lists...${NC}"
    apt update -y || { echo -e "${RED}Failed to update package lists!${NC}"; exit 1; }
    
    # Check if Cockpit is installed
    if ! dpkg -l | grep -q cockpit; then
        echo -e "${RED}Cockpit is not installed. Please install it first.${NC}"
        exit 1
    fi
    
    # Update Cockpit packages
    echo -e "${YELLOW}Upgrading Cockpit packages...${NC}"
    apt upgrade -y cockpit cockpit-* || { echo -e "${RED}Failed to update some Cockpit packages!${NC}"; }
    
    # Update GPU monitoring tools
    echo -e "${YELLOW}Updating GPU monitoring tools...${NC}"
    apt upgrade -y nvtop radeontop || { echo -e "${YELLOW}Some GPU tools could not be updated or are not installed.${NC}"; }
    
    # Restart Cockpit service to apply changes
    echo -e "${YELLOW}Restarting Cockpit service...${NC}"
    systemctl restart cockpit.socket || { echo -e "${RED}Failed to restart Cockpit service!${NC}"; exit 1; }
    
    # Restart GPU monitoring services if they exist
    if systemctl is-active --quiet nvidia-metrics.service; then
        echo -e "${YELLOW}Restarting NVIDIA metrics service...${NC}"
        systemctl restart nvidia-metrics.service
    fi
    
    if systemctl is-active --quiet amd-metrics.service; then
        echo -e "${YELLOW}Restarting AMD metrics service...${NC}"
        systemctl restart amd-metrics.service
    fi
    
    # Display updated Cockpit modules
    echo -e "${GREEN}Installed Cockpit modules:${NC}"
    dpkg -l | grep cockpit | awk '{print "- " $2 " (version: " $3 ")"}' | sort
    
    # Check if Cockpit is running
    if systemctl is-active --quiet cockpit.socket; then
        echo -e "${GREEN}Cockpit successfully updated!${NC}"
    else
        echo -e "${RED}Something went wrong. Cockpit service is not running after update.${NC}"
        exit 1
    fi
}

# Function to display help information
display_help() {
    echo "Cockpit Manager Script for Ubuntu"
    echo "--------------------------------"
    echo "This script provides options to install, remove, or update Cockpit on Ubuntu servers."
    echo "Includes GPU monitoring and passthrough capabilities for virtual machines."
    echo
    echo "Usage: $0 [option]"
    echo "Options:"
    echo "  install   Install Cockpit with all dependencies and features"
    echo "  remove    Remove Cockpit completely from the system"
    echo "  update    Update Cockpit to the latest version"
    echo "  help      Display this help message"
    echo
    echo "Examples:"
    echo "  sudo $0 install"
    echo "  sudo $0 remove"
    echo "  sudo $0 update"
}

# Function to provide interactive menu
interactive_menu() {
    echo "=== Cockpit Manager for Ubuntu ==="
    echo "Please select an option:"
    echo "1) Install Cockpit with GPU support"
    echo "2) Remove Cockpit"
    echo "3) Update Cockpit"
    echo "4) Exit"
    echo
    
    read -p "Enter your choice [1-4]: " choice
    
    case $choice in
        1)
            install_cockpit
            ;;
        2)
            remove_cockpit
            ;;
        3)
            update_cockpit
            ;;
        4)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            exit 1
            ;;
    esac
}

# Process the combined command format (username + action)
parse_combined_command() {
    local input="$1"
    
    if [[ "$input" == *"install"* ]]; then
        echo "install"
    elif [[ "$input" == *"remove"* ]]; then
        echo "remove"
    elif [[ "$input" == *"update"* ]]; then
        echo "update"
    else
        echo "unknown"
    fi
}

# Main script execution
check_root

# Detect if we're being piped through wget or similar
if [ "$0" = "sh" ] || [ "$0" = "bash" ] || [ "$0" = "-" ]; then
    # Handle the specific format used in the command
    if [[ "$1" == *"install"* || "$1" == *"remove"* || "$1" == *"update"* || "$1" == *"set"* ]]; then
        action=$(parse_combined_command "$1")
        case "$action" in
            install)
                install_cockpit
                ;;
            remove)
                remove_cockpit
                ;;
            update)
                update_cockpit
                ;;
            *)
                install_cockpit  # Default action for phrases like "set appropriate permissions"
                ;;
        esac
        exit 0
    fi
fi

# First argument is the script name when piped through sh
# Shift to get the actual first argument
if [ "$1" = "sh" ] || [ "$1" = "bash" ] || [ "$1" = "-" ]; then
    shift
fi

# Process command line arguments
if [ $# -eq 0 ]; then
    # No arguments provided, show interactive menu
    interactive_menu
else
    case "$1" in
        install)
            install_cockpit
            ;;
        remove)
            remove_cockpit
            ;;
        update)
            update_cockpit
            ;;
        help)
            display_help
            ;;
        *)
            # Check if this might be a combined username+command
            action=$(parse_combined_command "$1")
            if [ "$action" != "unknown" ]; then
                case "$action" in
                    install)
                        install_cockpit
                        ;;
                    remove)
                        remove_cockpit
                        ;;
                    update)
                        update_cockpit
                        ;;
                esac
            else
                echo -e "${RED}Error: Invalid option '$1'${NC}"
                display_help
                exit 1
            fi
            ;;
    esac
fi

exit 0
