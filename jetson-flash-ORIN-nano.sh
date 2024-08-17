#!/bin/bash

# List of possible device interfaces (adjust as needed)
devices=("usb0" "usb1" "usb2" "usb3" "usb4" "usb5" "usb6" "usb7" "usb8" "usb9" 
         "usb10" "usb11" "usb12" "usb13" "usb14" "usb15" "usb16" "usb17" "usb18" "usb19")

# Check if the USB device is connected by checking if the network interface exists
connected_devices=()

for device in "${devices[@]}"; do
    if ip link show $device &> /dev/null; then
        connected_devices+=($device)
    fi
done

# Flash each connected device with progress display
for device in "${connected_devices[@]}"; do
    log_file="flashing_${device}.log"
    echo "Flashing device on $device... (log: $log_file)"
    
    sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 \
    -c tools/kernel_flash/flash_l4t_external.xml -p "-c bootloader/t186ref/cfg/flash_t234_qspi.xml" \
    --showlogs --network $device jetson-orin-nano-devkit internal \
    | tee $log_file &

done

wait
echo "Flashing complete for all connected devices."

# Optionally, display a summary of all log files
echo "Summary of flashing logs:"
for device in "${connected_devices[@]}"; do
    echo "Device $device log:"
    tail -n 10 "flashing_${device}.log"  # Display the last 10 lines of each log
    echo
done
