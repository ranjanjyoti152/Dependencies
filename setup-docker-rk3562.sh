#!/usr/bin/env bash
#
# setup-docker-rk3562.sh
#
# Installs a WORKING Docker engine on Rockchip RK3562 boards running the
# vendor kernel 5.10.198 (Ubuntu userspace). The vendor kernel is flashed to
# eMMC and cannot be replaced via apt, and it is built without several
# features Docker needs. This script works around each one:
#
#   MISSING KERNEL FEATURE      WORKAROUND APPLIED HERE
#   --------------------------  --------------------------------------------
#   CONFIG_VETH                 build veth.ko from upstream 5.10.198 source
#                               and load it into the running kernel
#   CONFIG_OVERLAY_FS           use the "vfs" storage driver instead
#   CONFIG_POSIX_MQUEUE         runc wrapper strips the /dev/mqueue mount
#   CONFIG_BPF_SYSCALL          patched runc treats ENOSYS from BPF_PROG_QUERY
#                               and BPF_PROG_LOAD as "no device filter"
#   xtables out-of-tree match   no bridge NAT; host networking only
#
# This is only possible because the vendor kernel sets CONFIG_MODULES=y with
# CONFIG_MODULE_SIG and CONFIG_MODVERSIONS both OFF, so unsigned out-of-tree
# modules load.
#
# READ THIS BEFORE USING (see also --help):
#   * Containers get NO device cgroup isolation. The runc patch skips the BPF
#     device filter entirely because the kernel cannot do it. Treat every
#     container as roughly device-privileged. Do not run untrusted images.
#   * Host networking only. Port publishing (-p) does NOT work.
#     Use --network=host and bind ports directly.
#   * "vfs" storage full-copies every layer. Slow and space-hungry.
#
# MODES
#   (default)         full build on this device (~30-60 min, downloads ~190 MB)
#   --from-bundle DIR install prebuilt veth.ko + runc from DIR (fast, minutes)
#   --export DIR      on an ALREADY-WORKING device, save artifacts to DIR so
#                     other identical boards can use --from-bundle
#   --verify          check an existing install and run a container
#
set -euo pipefail

KVER_EXPECTED="5.10.198"
GO_VER="1.24.7"
KSRC_DIR="/usr/local/src/docker-rk3562/kernel"
RUNC_SRC_DIR="/usr/local/src/docker-rk3562/runc"
WRAPPER="/usr/local/bin/runc-nomq"
RUNC_PATCHED="/usr/local/bin/runc-patched"
MOD_DIR="/lib/modules/$(uname -r)/extra"
STATE_DIR="/var/lib/docker-rk3562"
KEEP_SRC=0
MODE="build"
BUNDLE_DIR=""

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '    \033[1;32mok\033[0m  %s\n' "$*"; }
warn() { printf '    \033[1;33m!!\033[0m  %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n\n' "$*" >&2; exit 1; }

usage() { sed -n '2,55p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --from-bundle|--export)
      # Note: plain `shift 2` would fail under `set -e` when the value is
      # missing, exiting 0 without a message. Validate first.
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "$1 requires a directory argument"
      case "$1" in
        --from-bundle) MODE="from-bundle" ;;
        --export)      MODE="export" ;;
      esac
      BUNDLE_DIR="$2"
      shift; shift ;;
    --verify)      MODE="verify";      shift ;;
    --keep-source) KEEP_SRC=1;         shift ;;
    -h|--help)     usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ "$MODE" = "export" ] || [ "$(id -u)" = "0" ] || \
  die "run as root: sudo $0 $*"

# ---------------------------------------------------------------------------
# guards - refuse to run on hardware this recipe was not validated against
# ---------------------------------------------------------------------------
check_platform() {
  log "Checking platform"
  local kver arch model
  kver="$(uname -r)"; arch="$(uname -m)"
  model="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"

  [ "$arch" = "aarch64" ] || die "expected aarch64, got $arch"
  if [ "$kver" != "$KVER_EXPECTED" ]; then
    die "kernel is $kver, this script is validated only for $KVER_EXPECTED.
    A different kernel may already support Docker natively, or may need
    different workarounds. Check first:
      zcat /proc/config.gz | grep -E 'CONFIG_VETH|CONFIG_OVERLAY_FS|CONFIG_BPF_SYSCALL'"
  fi
  ok "kernel $kver on $arch"
  ok "board: $model"

  [ -r /proc/config.gz ] || die "/proc/config.gz unreadable; cannot confirm kernel config"
  local cfg; cfg="$(zcat /proc/config.gz)"
  grep -q '^CONFIG_MODULES=y'            <<<"$cfg" || die "CONFIG_MODULES is not y - cannot load modules, no way forward"
  grep -q '^# CONFIG_MODULE_SIG is not'  <<<"$cfg" || warn "CONFIG_MODULE_SIG is set - unsigned veth.ko may be refused"
  grep -q '^# CONFIG_MODVERSIONS is not' <<<"$cfg" || warn "CONFIG_MODVERSIONS is set - module symbol check may reject veth.ko"
  ok "unsigned out-of-tree modules are loadable"

  # Record what we expect to work around, for the summary.
  grep -q '^# CONFIG_POSIX_MQUEUE is not' <<<"$cfg" && ok "confirmed: no POSIX_MQUEUE (wrapper needed)"
  grep -q '^# CONFIG_BPF_SYSCALL is not'  <<<"$cfg" && ok "confirmed: no BPF_SYSCALL (runc patch needed)"
  grep -q '^# CONFIG_OVERLAY_FS is not'   <<<"$cfg" && ok "confirmed: no OVERLAY_FS (vfs storage needed)"
}

check_space() {
  local need_mb="$1" avail_mb
  avail_mb=$(df -Pm / | awk 'NR==2{print $4}')
  [ "$avail_mb" -ge "$need_mb" ] || die "need ${need_mb}MB free on /, have ${avail_mb}MB"
  ok "disk: ${avail_mb}MB free"
}

# ---------------------------------------------------------------------------
# DNS - the jammy release upgrade commonly leaves systemd-resolved disabled
# while /etc/resolv.conf still points into its runtime dir, breaking apt.
# ---------------------------------------------------------------------------
fix_dns() {
  log "Checking DNS"
  if getent hosts download.docker.com >/dev/null 2>&1; then
    ok "DNS already working"
    return
  fi
  warn "DNS is broken - repairing"

  systemctl enable --now systemd-resolved >/dev/null 2>&1 || true

  local gw servers
  gw="$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')"
  servers="${gw:+$gw }1.1.1.1 8.8.8.8"

  mkdir -p /etc/systemd/resolved.conf.d
  cat > /etc/systemd/resolved.conf.d/99-dns.conf <<EOF
# Written by setup-docker-rk3562.sh
# The vendor 'wan' interface is legacy ifupdown-managed and feeds no DNS to
# systemd-resolved, so set it explicitly.
[Resolve]
DNS=$servers
FallbackDNS=8.8.4.4
EOF
  systemctl restart systemd-resolved
  sleep 4
  getent hosts download.docker.com >/dev/null 2>&1 \
    && ok "DNS repaired (servers: $servers)" \
    || die "DNS still broken. Check networking manually, then re-run."
}

# ---------------------------------------------------------------------------
# Docker packages
# ---------------------------------------------------------------------------
install_docker_packages() {
  log "Installing Docker packages"
  export DEBIAN_FRONTEND=noninteractive

  apt-get install -y ca-certificates curl gnupg >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -s /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename; codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $codename stable" \
    > /etc/apt/sources.list.d/docker.list
  ok "repo pinned to $codename"

  apt-get update >/dev/null
  # Unhold in case of a re-run, otherwise install is a no-op.
  apt-mark unhold docker-ce containerd.io >/dev/null 2>&1 || true
  apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || true

  command -v dockerd >/dev/null || die "docker-ce did not install"
  # dockerd will have failed to start here; that is expected until configured.
  systemctl stop docker docker.socket >/dev/null 2>&1 || true
  systemctl reset-failed docker >/dev/null 2>&1 || true
  ok "docker $(docker --version | awk '{print $3}' | tr -d ,) installed"
}

# ---------------------------------------------------------------------------
# veth.ko - built from upstream source at the exact running kernel version
# ---------------------------------------------------------------------------
build_veth() {
  log "Building veth.ko from upstream $KVER_EXPECTED source"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y build-essential bc bison flex libelf-dev >/dev/null
  ok "build dependencies installed"

  mkdir -p "$KSRC_DIR"; cd "$KSRC_DIR"
  local tb="linux-${KVER_EXPECTED}.tar.xz"
  if [ ! -d "linux-${KVER_EXPECTED}" ]; then
    [ -s "$tb" ] || { ok "downloading kernel source (~116 MB)"; \
      curl -fL --retry 3 -o "$tb" \
        "https://cdn.kernel.org/pub/linux/kernel/v5.x/${tb}"; }
    ok "extracting"
    tar xf "$tb"
  fi
  cd "linux-${KVER_EXPECTED}"

  # Seed from the RUNNING config so vermagic matches the vendor kernel.
  zcat /proc/config.gz > .config
  ./scripts/config --file .config -m VETH
  make ARCH=arm64 olddefconfig >/dev/null
  grep -q '^CONFIG_VETH=m' .config || die "could not enable CONFIG_VETH=m"
  ok "config seeded from running kernel, VETH=m"

  ok "preparing tree (a few minutes)"
  make ARCH=arm64 modules_prepare -j"$(nproc)" >/dev/null
  ok "building module"
  make ARCH=arm64 -j"$(nproc)" M=drivers/net modules >/dev/null 2>&1

  [ -f drivers/net/veth.ko ] || die "veth.ko did not build"
  local vm; vm="$(modinfo drivers/net/veth.ko | awk '/^vermagic/{print $2}')"
  [ "$vm" = "$KVER_EXPECTED" ] || die "veth.ko vermagic '$vm' != running kernel"
  ok "veth.ko built (vermagic $vm)"

  install -D -m 0644 drivers/net/veth.ko "$MOD_DIR/veth.ko"
}

install_veth() {
  log "Installing and loading veth"
  depmod -a 2>/dev/null || true
  modprobe veth 2>/dev/null || insmod "$MOD_DIR/veth.ko"
  lsmod | grep -q '^veth' || die "veth failed to load"
  ok "veth loaded"

  echo veth > /etc/modules-load.d/docker-modules.conf
  ok "veth set to load at boot"
}

# ---------------------------------------------------------------------------
# runc - patched to survive a kernel with no BPF_SYSCALL
# ---------------------------------------------------------------------------
build_runc() {
  log "Building patched runc"
  local rv
  rv="$(runc --version 2>/dev/null | awk '/^runc version/{print $3}')" \
    || die "runc not found; install docker packages first"
  ok "matching installed runc $rv"

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y pkg-config libseccomp-dev >/dev/null
  ok "build dependencies installed"

  if [ ! -x /usr/local/go/bin/go ]; then
    ok "installing Go $GO_VER (~72 MB)"
    curl -fsSL --retry 3 -o /tmp/go.tgz \
      "https://go.dev/dl/go${GO_VER}.linux-arm64.tar.gz"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tgz
    rm -f /tmp/go.tgz
  fi
  ok "$(/usr/local/go/bin/go version)"

  mkdir -p "$RUNC_SRC_DIR"; cd "$RUNC_SRC_DIR"
  if [ ! -d "runc-${rv#v}" ]; then
    curl -fsSL --retry 3 -o runc.tgz \
      "https://github.com/opencontainers/runc/archive/refs/tags/v${rv#v}.tar.gz"
    tar xzf runc.tgz
  fi
  cd "runc-${rv#v}"

  local f=vendor/github.com/opencontainers/cgroups/devices/ebpf_linux.go
  [ -f "$f" ] || die "expected $f in runc $rv - source layout changed, patch needs review"

  python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()

# 1. BPF_PROG_QUERY: a kernel without CONFIG_BPF_SYSCALL returns ENOSYS. Such
#    a kernel cannot have any BPF_CGROUP_DEVICE program attached, so an empty
#    list is the correct answer rather than a fatal error.
q_old = '\t\t\treturn nil, fmt.Errorf("bpf_prog_query(BPF_CGROUP_DEVICE) failed: %w", errno)'
q_new = '''\t\t\t// Kernels built without CONFIG_BPF_SYSCALL return ENOSYS. They
\t\t\t// cannot have any BPF_CGROUP_DEVICE program attached, so report an
\t\t\t// empty list instead of failing container creation.
\t\t\tif errno == unix.ENOSYS {
\t\t\t\treturn nil, nil
\t\t\t}
''' + q_old

# 2. BPF_PROG_LOAD: same kernel cannot create the program either. Skip
#    attaching the device filter. NOTE: containers then run with NO device
#    cgroup restriction - unavoidable on such a kernel.
a_old = '''\tprog, err := ebpf.NewProgram(spec)
\tif err != nil {
\t\treturn nilCloser, err
\t}'''
a_new = '''\tprog, err := ebpf.NewProgram(spec)
\tif err != nil {
\t\t// Kernels built without CONFIG_BPF_SYSCALL cannot create BPF programs
\t\t// at all (ENOSYS). Device cgroup filtering is impossible there, so skip
\t\t// attaching rather than refusing to run the container.
\t\tif errors.Is(err, unix.ENOSYS) {
\t\t\tlogrus.Warn("kernel lacks BPF_PROG_LOAD (CONFIG_BPF_SYSCALL); skipping cgroup device filter -- device access is NOT restricted")
\t\t\treturn nilCloser, nil
\t\t}
\t\treturn nilCloser, err
\t}'''

changed = 0
if 'unix.ENOSYS {\n\t\t\t\treturn nil, nil' not in s:
    if s.count(q_old) != 1:
        sys.exit("patch 1: expected exactly 1 match, found %d" % s.count(q_old))
    s = s.replace(q_old, q_new); changed += 1
if 'skipping cgroup device filter' not in s:
    if s.count(a_old) != 1:
        sys.exit("patch 2: expected exactly 1 match, found %d" % s.count(a_old))
    s = s.replace(a_old, a_new); changed += 1

open(p, 'w').write(s)
print("    ok  applied %d patch(es)" % changed)
PY

  ok "compiling runc (a few minutes)"
  PATH=/usr/local/go/bin:$PATH GOFLAGS=-mod=vendor GOCACHE=/tmp/gocache \
    go build -mod=vendor -trimpath -tags "seccomp urfave_cli_no_docs" -o runc-patched .
  [ -x runc-patched ] || die "runc build failed"
  ./runc-patched --version >/dev/null || die "patched runc will not run"
  install -m 0755 runc-patched "$RUNC_PATCHED"
  ok "installed $RUNC_PATCHED"
}

# ---------------------------------------------------------------------------
# runc wrapper - strips what the kernel cannot provide from each OCI spec
# ---------------------------------------------------------------------------
write_wrapper() {
  log "Installing runc wrapper"
  command -v python3 >/dev/null || die "python3 required by the wrapper"

  cat > "$WRAPPER" <<'WRAP'
#!/bin/bash
# Written by setup-docker-rk3562.sh
#
# Adapts each OCI spec to the RK3562 vendor kernel (5.10.198), which lacks:
#   CONFIG_POSIX_MQUEUE -> remove the /dev/mqueue mount (bool, cannot be a
#                          module, so it can never be added at runtime)
#   CONFIG_BPF_SYSCALL  -> remove linux.resources.devices, which runc would
#                          otherwise try to enforce via BPF_CGROUP_DEVICE
# Then hand off to the patched runc.
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "create" || "${!i}" == "run" ]]; then
    B=""
    for ((j=i+1; j<=$#; j++)); do
      a="${!j}"
      if [[ "$a" == "--bundle" ]]; then k=$((j+1)); B="${!k}"; break
      elif [[ "$a" == --bundle=* ]]; then B="${a#--bundle=}"; break; fi
    done
    B="${B:-$PWD}"
    if [[ -f "$B/config.json" ]]; then
      python3 - "$B/config.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f: c = json.load(f)
c["mounts"] = [m for m in c.get("mounts", []) if m.get("destination") != "/dev/mqueue"]
res = c.setdefault("linux", {}).get("resources")
if isinstance(res, dict):
    res.pop("devices", None)
with open(p, "w") as f: json.dump(c, f)
PY
    fi
    break
  fi
done
exec /usr/local/bin/runc-patched "$@"
WRAP
  chmod 0755 "$WRAPPER"
  ok "installed $WRAPPER"
}

# ---------------------------------------------------------------------------
# iptables + daemon config
# ---------------------------------------------------------------------------
configure_iptables() {
  log "Switching iptables to the legacy backend"
  # The nft backend needs nft-flavoured kernel modules this kernel does not
  # have. Legacy is closer to working, though bridge NAT stays unavailable
  # because out-of-tree xtables matches will not register either.
  if [ -x /usr/sbin/iptables-legacy ]; then
    update-alternatives --set iptables  /usr/sbin/iptables-legacy  >/dev/null 2>&1 || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true
    ok "$(iptables -V)"
    warn "other tooling on this board that writes nft rules will be affected"
  else
    warn "iptables-legacy not present, leaving alternatives alone"
  fi
}

configure_daemon() {
  log "Writing /etc/docker/daemon.json"
  install -d -m 0755 /etc/docker
  [ ! -f /etc/docker/daemon.json ] || \
    cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak-$(date +%Y%m%d-%H%M%S)"

  cat > /etc/docker/daemon.json <<'JSON'
{
  "storage-driver": "vfs",
  "iptables": false,
  "ip6tables": false,
  "bridge": "none",
  "default-runtime": "nomq",
  "runtimes": {
    "nomq": {
      "path": "/usr/local/bin/runc-nomq"
    }
  },
  "exec-opts": [
    "native.cgroupdriver=cgroupfs"
  ]
}
JSON
  ok "vfs storage, iptables off, nomq runtime"
}

start_docker() {
  log "Starting Docker"
  systemctl daemon-reload
  systemctl enable containerd docker >/dev/null 2>&1
  systemctl restart containerd; sleep 3
  systemctl restart docker;     sleep 8
  systemctl is-active --quiet docker \
    || die "dockerd failed to start. Inspect: journalctl -u docker -n 40 --no-pager"
  ok "containerd + docker active and enabled at boot"

  # A containerd upgrade would ship a new /usr/bin/runc and could bump the
  # runc version out of sync with our patched build.
  apt-mark hold docker-ce containerd.io >/dev/null
  ok "docker-ce and containerd.io held (upgrades would break the runc patch)"

  local u="${SUDO_USER:-}"
  if [ -n "$u" ] && [ "$u" != root ]; then
    usermod -aG docker "$u"
    ok "added '$u' to the docker group (effective next login)"
  fi
}

verify() {
  log "Verifying"
  systemctl is-active --quiet docker || die "docker.service is not active"
  docker info >/dev/null 2>&1 || die "cannot talk to the daemon"
  ok "server $(docker info --format '{{.ServerVersion}}')"
  ok "storage driver $(docker info --format '{{.Driver}}')"
  lsmod | grep -q '^veth' && ok "veth loaded" || warn "veth NOT loaded"

  ok "running hello-world"
  if docker run --rm hello-world 2>&1 | grep -q 'Hello from Docker'; then
    ok "container ran successfully"
  else
    die "hello-world failed. Inspect: journalctl -u docker -n 40 --no-pager"
  fi

  ok "testing host networking"
  docker run --rm --network=host ubuntu:22.04 true 2>/dev/null \
    && ok "host networking works" \
    || warn "could not pull/run ubuntu:22.04 (network or registry issue)"
}

summary() {
  cat <<'EOS'

------------------------------------------------------------------------
Docker is working. Three limitations are inherent to this kernel:

  1. NO device cgroup isolation. The runc patch skips the BPF device
     filter because the kernel has no CONFIG_BPF_SYSCALL. Containers are
     effectively device-privileged. Do not run untrusted images.

  2. Host networking only. Port publishing (-p 8080:80) does NOT work;
     the kernel will not register out-of-tree xtables matches. Use:
         docker run --network=host ...

  3. "vfs" storage full-copies every layer. Slow, and disk grows fast.
     Watch free space if you stack many images.

Also changed: iptables switched to the legacy backend; docker-ce and
containerd.io are apt-mark hold (unholding and upgrading will replace
runc and break containers - re-run this script if you do).

To provision another identical board quickly, run on THIS device:
    sudo ./setup-docker-rk3562.sh --export /path/to/bundle
then on the new board:
    sudo ./setup-docker-rk3562.sh --from-bundle /path/to/bundle
------------------------------------------------------------------------
EOS
}

# ---------------------------------------------------------------------------
# bundle export / import - artifacts are portable across identical boards
# ---------------------------------------------------------------------------
do_export() {
  log "Exporting artifacts to $BUNDLE_DIR"
  local src_mod="$MOD_DIR/veth.ko"
  [ -f "$src_mod" ]      || die "$src_mod not found - is this a configured device?"
  [ -x "$RUNC_PATCHED" ] || die "$RUNC_PATCHED not found - is this a configured device?"

  mkdir -p "$BUNDLE_DIR"
  cp "$src_mod" "$BUNDLE_DIR/veth.ko"
  cp "$RUNC_PATCHED" "$BUNDLE_DIR/runc-patched"
  cat > "$BUNDLE_DIR/MANIFEST" <<EOF
kernel_vermagic=$(modinfo "$src_mod" | awk '/^vermagic/{print $2}')
kernel_release=$(uname -r)
runc_version=$("$RUNC_PATCHED" --version | awk '/^runc version/{print $3}')
exported_from=$(hostname)
exported_on=$(date -Is)
EOF
  chmod 0644 "$BUNDLE_DIR/veth.ko"; chmod 0755 "$BUNDLE_DIR/runc-patched"
  ok "wrote veth.ko, runc-patched, MANIFEST"
  cat "$BUNDLE_DIR/MANIFEST" | sed 's/^/    /'
  printf '\nCopy this directory to another identical board and run:\n    sudo %s --from-bundle <dir>\n\n' "$(basename "$0")"
}

do_from_bundle() {
  log "Installing from bundle $BUNDLE_DIR"
  [ -f "$BUNDLE_DIR/veth.ko" ]      || die "no veth.ko in $BUNDLE_DIR"
  [ -x "$BUNDLE_DIR/runc-patched" ] || [ -f "$BUNDLE_DIR/runc-patched" ] \
    || die "no runc-patched in $BUNDLE_DIR"

  local vm; vm="$(modinfo "$BUNDLE_DIR/veth.ko" | awk '/^vermagic/{print $2}')"
  [ "$vm" = "$(uname -r)" ] \
    || die "bundle veth.ko vermagic '$vm' does not match this kernel '$(uname -r)'.
    The bundle came from a board with a different kernel; build from source
    instead by running this script with no arguments."
  ok "veth.ko vermagic matches ($vm)"

  install -D -m 0644 "$BUNDLE_DIR/veth.ko" "$MOD_DIR/veth.ko"
  install -m 0755 "$BUNDLE_DIR/runc-patched" "$RUNC_PATCHED"
  ok "artifacts installed"
}

# ---------------------------------------------------------------------------
main() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true

  case "$MODE" in
    export)
      check_platform
      do_export
      return ;;
    verify)
      check_platform
      verify
      return ;;
    from-bundle)
      check_platform
      check_space 3000
      fix_dns
      install_docker_packages
      do_from_bundle
      install_veth
      write_wrapper
      configure_iptables
      configure_daemon
      start_docker
      verify
      summary
      return ;;
    build)
      check_platform
      check_space 12000
      fix_dns
      install_docker_packages
      build_veth
      install_veth
      build_runc
      write_wrapper
      configure_iptables
      configure_daemon
      start_docker
      verify
      if [ "$KEEP_SRC" = 0 ]; then
        log "Cleaning up build trees"
        rm -rf /usr/local/src/docker-rk3562
        ok "removed source trees (~1.5 GB); pass --keep-source to retain them"
      fi
      summary
      return ;;
  esac
}

main "$@"
