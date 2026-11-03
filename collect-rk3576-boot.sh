#!/usr/bin/env bash
# RK3576 second-stage collector. Reads board storage; NEVER writes to devices.
# Run as the normal user first. Use sudo only if you have authorized access.
set -u
umask 077
export LC_ALL=C
base=${1:-"$PWD"}
[[ -d "$base" && -w "$base" ]] || { echo "Output folder must exist and be writable: $base" >&2; exit 1; }
base=$(cd "$base" && pwd -P) || exit 1
out=$(mktemp -d "$base/rk3576-boot-XXXXXXXX") || exit 1
mkdir -p "$out/reports" "$out/images" "$out/files"
log="$out/reports/collection.txt"
echo "Collecting into: $out"
report() { local n=$1; shift; "$@" > "$out/reports/$n.txt" 2>&1 || true; }
report identity id
report storage lsblk -b -o NAME,PATH,SIZE,TYPE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINT,MODEL
report by-partlabel ls -l /dev/disk/by-partlabel
report partitions cat /proc/partitions
report partition-map sfdisk --json /dev/mmcblk0
report partition-table fdisk -l /dev/mmcblk0
report block-identification blkid
report boot-links ls -l /dev/block/by-name /dev/disk/by-partlabel
report mounts findmnt

# Confirm the hard-coded source is eMMC, not SD or NVMe, before reading images.
is_emmc=false
if [[ -r /sys/block/mmcblk0/device/type ]] && [[ $(cat /sys/block/mmcblk0/device/type) == MMC ]]; then
    is_emmc=true
fi

read_image() {
    local src=$1 dst=$2 count=$3
    if [[ ! -b "$src" || ! -r "$src" ]]; then
        echo "SKIPPED (not readable): $src" >> "$log"
        return
    fi
    # All destinations are ordinary files in the newly created output folder.
    if dd if="$src" of="$out/images/$dst" bs=512 count="$count" 2>>"$log"; then
        echo "SAVED: $src -> $dst" >> "$log"
    else
        echo "FAILED: $src -> $dst (partial output removed)" >> "$log"
        rm -f -- "$out/images/$dst"
    fi
}

if $is_emmc; then
    # First 16 MiB: partition table and possible loader area. Not a full backup.
    read_image /dev/mmcblk0 emmc-first-16MiB.img 32768
    # Only read small, explicitly boot-labelled partitions. Never rootfs,
    # userdata, OEM, NVMe, recovery, or partitions with unknown labels.
    for sys in /sys/class/block/mmcblk0p*; do
        [[ -r "$sys/uevent" && -r "$sys/size" ]] || continue
        name=${sys##*/}
        label=$(sed -n 's/^PARTNAME=//p' "$sys/uevent")
        sectors=$(cat "$sys/size")
        printf '%s label=%s sectors=%s\n' "$name" "$label" "$sectors" >> "$log"
        case "$label" in
            uboot|u-boot|trust|boot|boot_a|boot_b|resource|dtb|dtbo|vbmeta)
                if [[ "$sectors" =~ ^[0-9]+$ ]] && (( sectors > 0 && sectors <= 524288 )); then
                    read_image "/dev/$name" "$name-$label.img" "$sectors"
                else
                    echo "SKIPPED size limit: $name" >> "$log"
                fi ;;
            *) echo "SKIPPED non-boot or unknown label: $name" >> "$log" ;;
        esac
    done
else
    echo "No confirmed mmcblk0 eMMC; raw image collection skipped." >> "$log"
fi

# Preserve firmware/config and locate vendor modules and GPU libraries.
# Never follow symlinks while scanning; dereference only selected regular files.
# All file copies together are capped at 768 MiB, 128 MiB per file.
total=0
copy_file() {
    local src=$1 size dst
    [[ -f "$src" && -r "$src" ]] || return
    size=$(stat -Lc %s -- "$src" 2>/dev/null) || return
    [[ "$size" =~ ^[0-9]+$ ]] || return
    if (( size > 134217728 || total + size > 805306368 )); then
        echo "SKIPPED file size limit: $src" >> "$log"
        return
    fi
    dst="$out/files$src"
    mkdir -p "$(dirname "$dst")"
    if cp -L -- "$src" "$dst" 2>>"$log"; then
        total=$((total + size))
    else
        rm -f -- "$dst"
    fi
}
for p in /proc/config.gz /sys/firmware/fdt /etc/ld.so.conf /etc/X11/xorg.conf; do
    copy_file "$p"
done
for dir in /lib/firmware /usr/lib/firmware /lib/modules /usr/lib/modules /oem /usr/lib/aarch64-linux-gnu /usr/lib /usr/local/lib /etc/X11/xorg.conf.d /etc/ld.so.conf.d; do
    [[ -d "$dir" ]] || continue
    # These scans may overlap; copied files are skipped below.
    while IFS= read -r -d '' p; do
        [[ -e "$out/files$p" ]] && continue
        case "$p" in
            /lib/firmware/*|/usr/lib/firmware/*|/etc/X11/xorg.conf.d/*.conf|/etc/ld.so.conf.d/*.conf) copy_file "$p" ;;
            *) case "${p##*/}" in
                *.ko|*.ko.xz|*.ko.zst|libmali*|libMali*|*aic8800*|*8800d80*|*rk3576*.dtb) copy_file "$p" ;;
               esac ;;
        esac
    done < <(find "$dir" -maxdepth 7 \( -type f -o -type l \) -print0 2>>"$log")
done
report module-locations sh -c 'find /oem /usr/lib /usr/local/lib /opt -maxdepth 7 -type f \( -name "*.ko" -o -name "*.ko.xz" -o -name "*.ko.zst" -o -name "libmali*" -o -name "libMali*" \) 2>/dev/null'
report graphics-packages sh -c 'dpkg-query -W 2>/dev/null | grep -Ei "mali|mesa|rockchip|aic|xserver|wayland"'

cat > "$out/README.txt" <<'EOF'
RK3576 boot and vendor-file collection

Read-only toward storage and system configuration. No installs, mounts, password
changes, device writes, or formatting. Only this folder and archive are written.

Raw reads only target confirmed mmcblk0 eMMC: first 16 MiB and selected boot-
labelled partitions of at most 256 MiB each. NO NVMe reads. NOT a full backup.
Missing/permission-denied components are listed in reports/collection.txt.
Normal users often cannot read boot partitions; root may be needed.

PRIVATE: contains partition identifiers, possible boot secrets, vendor firmware
and libraries. Inspect before sharing. Do not publish publicly. Collected vendor
binaries may have redistribution restrictions.
EOF
# Generate checksums if available.
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$out" && find images files -type f -exec sha256sum {} +) > "$out/SHA256SUMS"
fi
if tar -czf "$out.tar.gz" -C "$base" "${out##*/}"; then
    echo
    echo "DONE: $out.tar.gz"
    ls -lh "$out.tar.gz"
    echo "Check reports/collection.txt for unreadable boot partitions."
    echo "No existing disk or system configuration was modified."
else
    echo "Archive failed; files remain at $out" >&2
    exit 1
fi
