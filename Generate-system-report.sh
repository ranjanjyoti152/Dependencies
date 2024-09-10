#!/bin/bash

# Function to check if a tool is installed, if not, install it
install_tool() {
    tool=$1
    package=$2
    if ! command -v $tool &> /dev/null; then
        echo "$tool is not installed. Installing..."
        sudo apt-get install -y $package
    else
        echo "$tool is already installed."
    fi
}

# Function to install required packages
install_required_packages() {
    echo "Checking and installing required packages..."

    # Update package list
    sudo apt-get update

    # Check and install each required tool
    install_tool "lscpu" "util-linux"
    install_tool "free" "procps"
    install_tool "lshw" "lshw"
    install_tool "smartctl" "smartmontools"
    install_tool "dmidecode" "dmidecode"
    install_tool "lspci" "pciutils"
    install_tool "stress-ng" "stress-ng"
    install_tool "fio" "fio"
    install_tool "glmark2" "glmark2"
    install_tool "enscript" "enscript"
    install_tool "ps2pdf" "ghostscript"

    echo "All required packages are installed."
}

# Create a report file
REPORT_FILE="$HOME/Desktop/system_report.txt"

# Function to check CPU status and perform stress test for 1 hour
check_cpu() {
    echo "===== CPU INFO =====" | tee -a $REPORT_FILE
    lscpu | tee -a $REPORT_FILE
    echo "Starting CPU stress test for 1 hour..." | tee -a $REPORT_FILE
    sudo stress-ng --cpu 4 --timeout 3600 | tee -a $REPORT_FILE
    echo "CPU stress test completed." | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check GPU status and perform stress test for 1 hour
check_gpu() {
    echo "===== GPU INFO =====" | tee -a $REPORT_FILE
    lspci | grep -E "VGA|3D" | tee -a $REPORT_FILE
    echo "Starting GPU stress test with glmark2 for 1 hour..." | tee -a $REPORT_FILE
    glmark2 --run-for=3600 | tee -a $REPORT_FILE
    echo "GPU stress test completed. Press Ctrl+C to stop the GPU test early if needed." | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check RAM status and perform stress test for 1 hour
check_ram() {
    echo "===== RAM INFO =====" | tee -a $REPORT_FILE
    free -h | tee -a $REPORT_FILE
    echo "Starting RAM stress test for 1 hour..." | tee -a $REPORT_FILE
    sudo stress-ng --vm 2 --vm-bytes 80% --timeout 3600 | tee -a $REPORT_FILE
    echo "RAM stress test completed." | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check SSD health and perform stress test for 1 hour
check_ssd() {
    echo "===== SSD HEALTH =====" | tee -a $REPORT_FILE
    for disk in $(lsblk -nd -o NAME); do
        sudo smartctl -H /dev/$disk | tee -a $REPORT_FILE
    done
    echo "Starting SSD stress test for 1 hour using fio..." | tee -a $REPORT_FILE
    sudo fio --name=randwrite --ioengine=libaio --iodepth=1 --rw=randwrite --bs=4k --direct=1 --size=1G --numjobs=4 --runtime=3600 --group_reporting | tee -a $REPORT_FILE
    echo "SSD stress test completed." | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to check motherboard information (no stress test available for motherboard)
check_motherboard() {
    echo "===== MOTHERBOARD INFO =====" | tee -a $REPORT_FILE
    sudo dmidecode -t baseboard | tee -a $REPORT_FILE
    echo "Motherboard stability cannot be stressed directly, but the overall system test covers it." | tee -a $REPORT_FILE
    echo "" | tee -a $REPORT_FILE
}

# Function to convert the report to a PDF and save it on the Desktop
generate_pdf_report() {
    PDF_FILE="$HOME/Desktop/system_report.pdf"
    echo "Generating PDF report..."
    enscript $REPORT_FILE -o - | ps2pdf - $PDF_FILE
    echo "Report saved as $PDF_FILE"
}

# Main function to perform all checks and stress tests
main() {
    echo "Starting system health and stability check..."

    # Install necessary packages if missing
    install_required_packages

    # Checking and stressing each hardware component
    check_cpu
    check_gpu
    check_ram
    check_ssd
    check_motherboard

    # Generate PDF report
    generate_pdf_report

    echo "System health and stability check completed."
}

# Execute the main function
main
