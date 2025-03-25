#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Use sudo."
  exit 1
fi

# Variables
SOURCE_DISK="/dev/nvme1n1"
TARGET_DISK="/dev/nvme0n1"
RAID_EFI="/dev/md0"
RAID_ROOT="/dev/md1"
MOUNT_POINT="/mnt/raid"

# Confirm with user
echo "This script will create a RAID 1 array between $SOURCE_DISK (Ubuntu) and $TARGET_DISK (blank)."
echo "Ensure you have backed up all data. This process is destructive."
read -p "Continue? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

# Install mdadm if not present
if ! command -v mdadm &> /dev/null; then
  echo "Installing mdadm..."
  apt update && apt install -y mdadm || { echo "Failed to install mdadm"; exit 1; }
fi

# Partition the blank NVMe (nvme0n1) to match nvme1n1
echo "Partitioning $TARGET_DISK to match $SOURCE_DISK..."
(
  echo "g"              # Create GPT partition table
  echo "n"              # New partition (EFI)
  echo "1"              # Partition number 1
  echo ""               # Default start
  echo "+512M"          # 512M size
  echo "t"              # Change type
  echo "1"              # EFI System
  echo "n"              # New partition (Root)
  echo "2"              # Partition number 2
  echo ""               # Default start
  echo ""               # Rest of disk
  echo "t"              # Change type
  echo "2"              # Select partition 2
  echo "fd"             # Linux RAID autodetect
  echo "w"              # Write changes
) | fdisk "$TARGET_DISK" || { echo "Partitioning failed"; exit 1; }

# Create RAID 1 arrays with 'missing' for initial setup
echo "Creating RAID 1 array for EFI partition ($RAID_EFI)..."
mdadm --create "$RAID_EFI" --level=1 --raid-devices=2 "$TARGET_DISK"p1 missing || { echo "RAID creation failed for EFI"; exit 1; }

echo "Creating RAID 1 array for root filesystem ($RAID_ROOT)..."
mdadm --create "$RAID_ROOT" --level=1 --raid-devices=2 "$TARGET_DISK"p2 missing || { echo "RAID creation failed for root"; exit 1; }

# Format the RAID arrays
echo "Formatting $RAID_EFI as FAT32..."
mkfs.vfat -F 32 "$RAID_EFI" || { echo "Formatting EFI failed"; exit 1; }

echo "Formatting $RAID_ROOT as ext4..."
mkfs.ext4 "$RAID_ROOT" || { echo "Formatting root failed"; exit 1; }

# Mount and copy data
echo "Mounting $RAID_ROOT and copying root filesystem..."
mkdir -p "$MOUNT_POINT" || { echo "Failed to create mount point"; exit 1; }
mount "$RAID_ROOT" "$MOUNT_POINT" || { echo "Mount failed"; exit 1; }
rsync -aHAX --progress / "$MOUNT_POINT/" || { echo "Copying root failed"; exit 1; }

echo "Mounting $RAID_EFI and copying EFI partition..."
mkdir -p "$MOUNT_POINT/boot/efi" || { echo "Failed to create EFI mount point"; exit 1; }
mount "$RAID_EFI" "$MOUNT_POINT/boot/efi" || { echo "Mounting EFI failed"; exit 1; }
rsync -aHAX --progress /boot/efi/ "$MOUNT_POINT/boot/efi/" || { echo "Copying EFI failed"; exit 1; }

# Mount system directories and chroot
echo "Preparing chroot environment..."
for dir in /dev /proc /sys /run; do
  mount --bind "$dir" "$MOUNT_POINT$dir" || { echo "Failed to bind $dir"; exit 1; }
done

# Update fstab and GRUB in chroot
echo "Updating fstab and GRUB..."
chroot "$MOUNT_POINT" /bin/bash <<EOF
  # Update fstab
  echo "UUID=$(blkid -s UUID -o value $RAID_EFI) /boot/efi vfat defaults 0 2" > /etc/fstab
  echo "UUID=$(blkid -s UUID -o value $RAID_ROOT) / ext4 defaults 0 1" >> /etc/fstab

  # Reinstall GRUB
  grub-install $SOURCE_DISK
  grub-install $TARGET_DISK
  update-grub
EOF

# Exit chroot and unmount
echo "Cleaning up chroot environment..."
umount "$MOUNT_POINT/run" "$MOUNT_POINT/sys" "$MOUNT_POINT/proc" "$MOUNT_POINT/dev" "$MOUNT_POINT/boot/efi" "$MOUNT_POINT" || { echo "Unmount failed"; exit 1; }

# Add original drive to RAID arrays
echo "Adding $SOURCE_DISK partitions to RAID arrays..."
mdadm --zero-superblock "$SOURCE_DISK"p1 || { echo "Zeroing EFI superblock failed"; exit 1; }
mdadm --zero-superblock "$SOURCE_DISK"p2 || { echo "Zeroing root superblock failed"; exit 1; }
mdadm "$RAID_EFI" --add "$SOURCE_DISK"p1 || { echo "Adding EFI to RAID failed"; exit 1; }
mdadm "$RAID_ROOT" --add "$SOURCE_DISK"p2 || { echo "Adding root to RAID failed"; exit 1; }

# Save RAID configuration
echo "Saving RAID configuration..."
mdadm --detail --scan | tee -a /etc/mdadm/mdadm.conf || { echo "Failed to save RAID config"; exit 1; }
update-initramfs -u || { echo "Failed to update initramfs"; exit 1; }

# Wait for RAID sync
echo "Waiting for RAID arrays to sync (this may take a while)..."
while grep -q "resync" /proc/mdstat; do
  cat /proc/mdstat
  sleep 10
done
echo "RAID sync complete."

# Final instructions
echo "Setup complete! Please reboot with 'sudo reboot' and verify RAID status with 'mdadm --detail $RAID_EFI' and 'mdadm --detail $RAID_ROOT'."
echo "If the system fails to boot, use a live USB to troubleshoot GRUB or RAID configuration."