#!/bin/bash

# Color codes for colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

# Prompt for sudo password at the beginning and store it
read -s -p "Enter your password: " SUDO_PASSWORD
echo

# Function to check if a tool is installed, if not, install it
install_tool() {
    tool=$1
    package=$2
    if ! command -v $tool &> /dev/null; then
        echo -e "${YELLOW}$tool is not installed. Installing...${NC}"
        echo "$SUDO_PASSWORD" | sudo -S apt-get install -y $package
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}$tool installed successfully.${NC}"
        else
            echo -e "${RED}Failed to install $tool.${NC}"
        fi
    else
        echo -e "${GREEN}$tool is already installed.${NC}"
    fi
}

# Function to install GPU-Burn (for CUDA GPUs)
install_gpu_burn() {
    if [ ! -d "$HOME/gpu-burn" ]; then
        echo -e "${YELLOW}gpu-burn not found. Installing...${NC}"
        git clone https://github.com/wilicc/gpu-burn.git $HOME/gpu-burn
        cd $HOME/gpu-burn
        make
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}gpu-burn installed successfully.${NC}"
        else
            echo -e "${RED}Failed to install gpu-burn.${NC}"
        fi
        cd - || exit # Return to previous directory
    else
        echo -e "${GREEN}gpu-burn already installed.${NC}"
    fi
}

# Function to check if the script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root (using sudo).${NC}"
        exit 1
    fi
}

# Function to install required packages
install_required_packages() {
    echo -e "${BLUE}Checking and installing required packages...${NC}"

    # Update package list
    echo "$SUDO_PASSWORD" | sudo -S apt-get update

    # Check and install each required tool
    install_tool "lscpu" "util-linux"
    install_tool "free" "procps"
    install_tool "lshw" "lshw"
    install_tool "smartctl" "smartmontools"
    install_tool "dmidecode" "dmidecode"
    install_tool "lspci" "pciutils"
    install_tool "stress-ng" "stress-ng"
    install_tool "fio" "fio"
    install_tool "enscript" "enscript"
    install_tool "ps2pdf" "ghostscript"

    # Check for glmark2 or fall back to stress-ng for GPU testing
    install_tool "glmark2" "glmark2"
    install_gpu_burn

    echo -e "${GREEN}All required packages are installed.${NC}"
}

# Create a report file
REPORT_FILE="$HOME/Desktop/system_report.txt"

# Function to check CPU status and perform stress test for 1 hour
check_cpu() {
    echo -e "${BLUE}===== CPU INFO =====${NC}" | tee -a $REPORT_FILE
    lscpu | tee -a $REPORT_FILE
    cpu_cores=$(nproc)  # Dynamic core count
    echo -e "${YELLOW}Starting CPU stress test for 1 hour on $cpu_cores cores...${NC}" | tee -a $REPORT_FILE
    echo "$SUDO_PASSWORD" | sudo -S stress-ng --cpu $cpu_cores --timeout 3600 | tee -a $REPORT_FILE
    echo -e "${GREEN}CPU stress test completed.${NC}" | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check GPU status and perform stress test for 1 hour
check_gpu() {
    echo -e "${BLUE}===== GPU INFO =====${NC}" | tee -a $REPORT_FILE
    lspci | grep -E "VGA|3D" | tee -a $REPORT_FILE
    
    # First, try using glmark2 for GPU stress testing
    if command -v glmark2 &> /dev/null; then
        echo -e "${YELLOW}Starting GPU stress test with glmark2 for 1 hour...${NC}" | tee -a $REPORT_FILE
        glmark2 --run-for=3600 | tee -a $REPORT_FILE
    else
        # If glmark2 fails, try using gpu-burn for CUDA GPUs
        if command -v nvidia-smi &> /dev/null; then
            echo -e "${YELLOW}CUDA GPU detected. Starting GPU stress test with gpu-burn for 1 hour...${NC}" | tee -a $REPORT_FILE
            cd $HOME/gpu-burn && ./gpu_burn 3600 | tee -a $REPORT_FILE
            cd - || exit
        else
            # Fall back to stress-ng for basic GPU stress if CUDA is not available
            echo -e "${YELLOW}glmark2 and CUDA tools not available. Starting GPU stress test with stress-ng...${NC}" | tee -a $REPORT_FILE
            echo "$SUDO_PASSWORD" | sudo -S stress-ng --gpu 4 --timeout 3600 | tee -a $REPORT_FILE
        fi
    fi
    echo -e "${GREEN}GPU stress test completed.${NC}" | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check RAM status and perform stress test for 1 hour
check_ram() {
    echo -e "${BLUE}===== RAM INFO =====${NC}" | tee -a $REPORT_FILE
    free -h | tee -a $REPORT_FILE
    echo -e "${YELLOW}Starting RAM stress test for 1 hour...${NC}" | tee -a $REPORT_FILE
    echo "$SUDO_PASSWORD" | sudo -S stress-ng --vm 2 --vm-bytes 80% --timeout 3600 | tee -a $REPORT_FILE
    echo -e "${GREEN}RAM stress test completed.${NC}" | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check SSD health and perform stress test for 1 hour
check_ssd() {
    echo -e "${BLUE}===== SSD HEALTH =====${NC}" | tee -a $REPORT_FILE
    for disk in $(lsblk -nd -o NAME); do
        echo "$SUDO_PASSWORD" | sudo -S smartctl -H /dev/$disk | tee -a $REPORT_FILE
    done
    echo -e "${YELLOW}Starting SSD stress test for 1 hour using fio...${NC}" | tee -a $REPORT_FILE
    echo "$SUDO_PASSWORD" | sudo -S fio --name=randwrite --ioengine=libaio --iodepth=1 --rw=randwrite --bs=4k --direct=1 --size=1G --numjobs=4 --runtime=3600 --group_reporting | tee -a $REPORT_FILE
    echo -e "${GREEN}SSD stress test completed.${NC}" | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check motherboard information (no stress test available for motherboard)
check_motherboard() {
    echo -e "${BLUE}===== MOTHERBOARD INFO =====${NC}" | tee -a $REPORT_FILE
    echo "$SUDO_PASSWORD" | sudo -S dmidecode -t baseboard | tee -a $REPORT_FILE
    echo -e "${YELLOW}Motherboard stability cannot be stressed directly, but the overall system test covers it.${NC}" | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check Kernel and Syslog errors
check_logs() {
    echo -e "${BLUE}===== SYSTEM LOG ERRORS =====${NC}" | tee -a $REPORT_FILE
    echo -e "${YELLOW}Checking kernel logs for errors...${NC}" | tee -a $REPORT_FILE
    dmesg | grep -iE "error|fail|critical" | tee -a $REPORT_FILE
    echo -e "${YELLOW}Checking syslog for errors...${NC}" | tee -a $REPORT_FILE
    echo "$SUDO_PASSWORD" | sudo -S grep -iE "error|fail|critical" /var/log/syslog | tee -a $REPORT_FILE
    echo -e "${GREEN}Log error check completed.${NC}" | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to convert the report to a PDF and save it on the Desktop
generate_pdf_report() {
    PDF_FILE="$HOME/Desktop/system_report.pdf"
    echo -e "${YELLOW}Generating PDF report...${NC}"
    enscript $REPORT_FILE -o - | ps2pdf - $PDF_FILE
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Report saved as $PDF_FILE${NC}"
    else
        echo -e "${RED}Failed to generate PDF report.${NC}"
    fi
}

# Main function to perform all checks and stress tests
main() {
    echo -e "${BLUE}Starting system health and stability check...${NC}"

    # Install necessary packages if missing
    install_required_packages

    # Checking and stressing each hardware component
    check_cpu
    check_gpu
    check_ram
    check_ssd
    check_motherboard

    # Check logs for errors
    check_logs

    # Generate PDF report
    generate_pdf_report

    echo -e "${GREEN}System health and stability check completed.${NC}"
}

# Execute the main function
main
