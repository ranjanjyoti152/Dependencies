#!/usr/bin/env bash
# Read-only RK3576 diagnostics. No sudo, package installs, or raw disk reads.
# Writes only into a new output directory and its accompanying archive.
set -u
umask 077
export LC_ALL=C

base=${1:-"$PWD"}
if [[ ! -d "$base" || ! -w "$base" ]]; then
    echo "Output directory must exist and be writable: $base" >&2
    exit 1
fi
base=$(cd "$base" && pwd -P) || exit 1
out=$(mktemp -d "$base/rk3576-collect-XXXXXXXX") || exit 1
mkdir -p "$out/reports" "$out/files" || exit 1
errors="$out/reports/copy-errors.txt"

report() {
    local name=$1
    shift
    { "$@"; } >"$out/reports/$name.txt" 2>&1 || true
}

# Limit file copies to 256 MiB each and 1 GiB total (uncompressed).
# Do not follow symbolic links when recursively collecting directories.
total=0
copy_file() {
    local src=$1 size dest
    [[ -f "$src" && -r "$src" && ! -L "$src" ]] || return 0
    size=$(stat -c %s -- "$src" 2>/dev/null) || return 0
    if (( size > 268435456 || total + size > 1073741824 )); then
        printf 'Size limit: %s (%s bytes)\n' "$src" "$size" >>"$errors"
        return 0
    fi
    dest="$out/files$src"
    mkdir -p "$(dirname "$dest")" || return 0
    if cp -- "$src" "$dest" 2>>"$errors"; then
        total=$((total + size))
    else
        rm -f -- "$dest"
    fi
}

printf 'Collecting board information into:\n%s\n' "$out"
report uname uname -a
report os-release cat /etc/os-release
report cpu cat /proc/cpuinfo
report memory free -h
report storage lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
report mounts findmnt
report kernel-command-line cat /proc/cmdline
report loaded-modules cat /proc/modules
report kernel-log dmesg
report packages dpkg-query -W '-f=${Package}\t${Version}\t${Architecture}\n'
report boot-listing find /boot -maxdepth 5 -ls
report firmware-listing find /lib/firmware -maxdepth 3 -type f
report kernel-modules-listing find /lib/modules -maxdepth 3 -type f

{
    for p in /sys/firmware/devicetree/base/model /sys/firmware/devicetree/base/compatible; do
        echo "=== $p ==="
        if [[ -r "$p" ]]; then tr '\000' '\n' < "$p"; echo; fi
    done
    for p in /sys/block/mmcblk*/device/{name,type,manfid,oemid}; do
        [[ -r "$p" ]] || continue
        echo "=== $p ==="
        cat "$p"
        echo
    done
    for p in /sys/class/drm/card*-*/status; do
        [[ -r "$p" ]] || continue
        echo "=== $p ==="
        cat "$p"
    done
} > "$out/reports/board.txt" 2>&1

# Exact running flattened device tree, when the kernel exposes it.
if [[ -r /sys/firmware/fdt ]]; then
    cat /sys/firmware/fdt > "$out/running.dtb" 2>>"$errors" || true
fi
# Also collect the live tree; /proc/device-tree is usually a symlink here.
if [[ -d /sys/firmware/devicetree/base ]]; then
    mkdir -p "$out/live-device-tree"
    cp -R /sys/firmware/devicetree/base/. "$out/live-device-tree/" 2>>"$errors" || true
    if command -v dtc >/dev/null 2>&1; then
        dtc -I fs -O dts -o "$out/running.dts" /sys/firmware/devicetree/base \
            2>"$out/reports/dtc.txt" || true
    fi
fi

# Collect only boot-relevant file types, not arbitrary files or credentials.
for dir in /boot /usr/lib/u-boot /usr/lib/linux-image-"$(uname -r)"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' p; do
        case "${p##*/}" in
            *.dtb|*.dtbo|*.itb|*.dtb.*|*.dtbo.*|Image|Image-*|Image.gz|Image.gz-*|Image.lz4|vmlinuz*|zImage*|initrd*|initramfs*|config-*|System.map*|extlinux.conf|armbianEnv.txt|uEnv.txt|ubuntuEnv.txt|boot.cmd|boot.scr|boot.ini|idbloader.img|u-boot*.bin|uboot.img|trust.img|parameter.txt)
                copy_file "$p" ;;
        esac
    done < <(find "$dir" -maxdepth 6 -type f -print0 2>>"$errors")
done
copy_file /etc/fstab
copy_file /etc/initramfs-tools/modules

cat > "$out/README.txt" <<'EOF'
RK3576 board diagnostic collection

Collected without sudo. No disk, bootloader, partition, or system configuration
was modified. Only this output folder and its archive were written.
Missing/permission-restricted commands and files are expected; see reports.
Boot-file copies are capped at 256 MiB per file and 1 GiB total.
Kernel modules and /lib/firmware contents are NOT copied (listings only).
This is NOT a full backup or a complete bootloader extraction.

PRIVACY: inspect before sharing. Reports and device trees can include hardware
serial numbers, MAC addresses, UUIDs, hostnames, mount paths, kernel command-line
parameters, and boot configuration. An initramfs may contain site-specific
configuration or secrets. Do not post this archive publicly without review.
EOF

archive="$out.tar.gz"
if tar -czf "$archive" -C "$base" "${out##*/}"; then
    echo
    echo "DONE. Copy this archive to your USB drive and share it:"
    printf '%s\n' "$archive"
    ls -lh "$archive"
    echo "Review README.txt inside the output folder before sharing."
else
    echo "Archive failed; collected files remain at: $out" >&2
    exit 1
fi
