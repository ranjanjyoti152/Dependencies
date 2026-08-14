#!/usr/bin/env bash
#
# install-nvidia-cuda13.sh
#
# Installs, on Ubuntu 24.04 (noble) x86_64:
#   - NVIDIA open-kernel-module driver (Ubuntu-packaged, prebuilt + signed)
#   - CUDA Toolkit 13.1  (nvcc, libraries, headers)
#   - cuDNN 9 built against CUDA 13
#   - CUDA env vars appended to ~/.bashrc
#
# Design decisions (learned the hard way on a 2x RTX PRO 6000 Blackwell box):
#
#   1. OPEN kernel modules, not proprietary. Blackwell (and every GPU from
#      Turing on with recent branches) requires the open modules. The
#      proprietary module does not support these GPUs.
#
#   2. Driver comes from the UBUNTU archive, not NVIDIA's repo, and we
#      prefer the linux-modules-nvidia-* prebuilt binary module matching the
#      running kernel. On new HWE kernels (6.17, 7.0) a DKMS source build can
#      fail outright; the prebuilt module is already compiled and signed
#      against that exact kernel ABI. DKMS is used only as a fallback.
#
#   3. nouveau must be gone BEFORE the NVIDIA driver initialises the GPU.
#      If nouveau touched the GPU this boot, it leaves the GSP firmware
#      carve-out (WPR2) up, and the NVIDIA driver fails with:
#         "unexpected WPR2 already up, cannot proceed with booting GSP"
#      A PCI function-level reset clears this without rebooting. The driver
#      package blacklists nouveau, so this only bites on the install boot.
#
#   4. cuDNN version must match the CUDA MAJOR version. cuDNN 9.6's local
#      repo only ships CUDA 11.8 and 12.6 builds - installing the plain
#      `cudnn` meta there pulls libcudnn9-cuda-12, which links the CUDA 12
#      runtime and will NOT work with CUDA 13.1. We install
#      cudnn9-cuda-13 from the network repo instead.
#
#   5. APT pin keeps the driver on Ubuntu's build so a later `apt upgrade`
#      cannot silently swap in NVIDIA's DKMS packages on a kernel that
#      cannot build them.
#
# Usage:
#   sudo ./install-nvidia-cuda13.sh              # install everything
#        ./install-nvidia-cuda13.sh --verify     # only run the checks
#   sudo ./install-nvidia-cuda13.sh --no-cudnn   # skip cuDNN
#
# Safe to re-run: every step is idempotent.
#
set -euo pipefail

CUDA_MAJOR_MINOR="13.1"
CUDA_PKG_SUFFIX="13-1"          # apt package naming: cuda-toolkit-13-1
CUDA_HOME_PATH="/usr/local/cuda-${CUDA_MAJOR_MINOR}"
DRIVER_BRANCH="${DRIVER_BRANCH:-}"   # e.g. DRIVER_BRANCH=610 to force a branch
DO_CUDNN=1
VERIFY_ONLY=0
REBOOT_REQUIRED=0

for arg in "$@"; do
  case "$arg" in
    --verify)   VERIFY_ONLY=1 ;;
    --no-cudnn) DO_CUDNN=0 ;;
    -h|--help)  sed -n '2,50p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# ----- output helpers ---------------------------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=''; G=''; Y=''; R=''; N=''
fi
step() { echo; echo "${B}==> $*${N}"; }
ok()   { echo "  ${G}[ ok ]${N} $*"; }
warn() { echo "  ${Y}[warn]${N} $*"; }
die()  { echo "  ${R}[fail]${N} $*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"
}

# The invoking user's home, not root's, so ~/.bashrc lands in the right place.
target_user="${SUDO_USER:-$(id -un)}"
target_home="$(getent passwd "$target_user" | cut -d: -f6)"

# =============================================================================
# 0. Preflight
# =============================================================================
preflight() {
  step "Preflight checks"

  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ] || die "this script targets Ubuntu (found ID=${ID:-unknown})"
  case "${VERSION_ID:-}" in
    24.04) ok "Ubuntu ${VERSION_ID} (${VERSION_CODENAME})" ;;
    *) warn "tested on Ubuntu 24.04; found ${VERSION_ID}. Repo URLs may need changing." ;;
  esac

  [ "$(uname -m)" = "x86_64" ] || die "x86_64 required (found $(uname -m))"

  local ngpu
  ngpu=$(lspci -nn -d 10de: 2>/dev/null | grep -Ec '\[030[02]\]' || true)
  [ "${ngpu:-0}" -gt 0 ] || die "no NVIDIA GPU found on the PCI bus"
  ok "found ${ngpu} NVIDIA GPU(s):"
  lspci -nn -d 10de: | grep -E '\[030[02]\]' | sed 's/^/         /'

  KERNEL="$(uname -r)"
  ok "kernel ${KERNEL}"
  [ -d "/lib/modules/${KERNEL}/build" ] \
    || warn "no kernel headers for ${KERNEL}; DKMS fallback would fail"

  if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
      warn "Secure Boot is ENABLED. Ubuntu's prebuilt modules are signed, so"
      warn "they load fine. A DKMS fallback build would need MOK enrollment."
    else
      ok "Secure Boot disabled"
    fi
  fi

  local avail
  avail=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
  [ "${avail:-0}" -ge 20 ] || die "need ~20GB free on /, have ${avail}G"
  ok "${avail}G free on /"
}

# =============================================================================
# 1. Driver
# =============================================================================
pick_driver_branch() {
  # Newest nvidia-driver-<N>-open metapackage available from the Ubuntu archive.
  apt-cache search --names-only '^nvidia-driver-[0-9]+-open$' 2>/dev/null \
    | awk '{print $1}' \
    | sed -E 's/nvidia-driver-([0-9]+)-open/\1/' \
    | sort -n | tail -1
}

install_driver() {
  step "Installing NVIDIA driver (open kernel modules)"

  if [ -z "$DRIVER_BRANCH" ]; then
    DRIVER_BRANCH="$(pick_driver_branch)"
    [ -n "$DRIVER_BRANCH" ] || die "no nvidia-driver-*-open package found in apt"
  fi
  ok "driver branch: ${DRIVER_BRANCH} (open)"

  local running
  running=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)
  if [ -n "$running" ]; then
    ok "driver already loaded and responding (${running}); skipping install"
    return 0
  fi

  # Prefer the prebuilt signed module for THIS kernel. Falls back to the
  # flavour metapackage, then to DKMS.
  local exact="linux-modules-nvidia-${DRIVER_BRANCH}-open-${KERNEL}"
  local flavour_pkg="" modpkg=""

  if apt-cache show "$exact" >/dev/null 2>&1; then
    modpkg="$exact"
    ok "prebuilt module matches running kernel exactly: ${modpkg}"
  else
    # Map kernel to its HWE/generic flavour metapackage.
    local f
    for f in generic-hwe-24.04 generic; do
      if apt-cache show "linux-modules-nvidia-${DRIVER_BRANCH}-open-${f}" >/dev/null 2>&1; then
        flavour_pkg="linux-modules-nvidia-${DRIVER_BRANCH}-open-${f}"
        break
      fi
    done
    if [ -n "$flavour_pkg" ]; then
      modpkg="$flavour_pkg"
      ok "using flavour metapackage: ${modpkg}"
    else
      warn "no prebuilt module found; falling back to DKMS (builds from source)"
    fi
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  # Refuse to proceed if apt wants to REMOVE things - that means a conflict.
  local plan
  plan=$(apt-get install -y -s --no-install-recommends \
           "nvidia-driver-${DRIVER_BRANCH}-open" \
           ${modpkg:+"$modpkg"} \
           "nvidia-utils-${DRIVER_BRANCH}" 2>&1) || die "apt could not resolve the driver install"
  if echo "$plan" | grep -q '^Remv'; then
    echo "$plan" | grep '^Remv' | sed 's/^/         /'
    die "apt wants to REMOVE packages; refusing. Resolve the conflict above first."
  fi

  apt-get install -y --no-install-recommends \
    "nvidia-driver-${DRIVER_BRANCH}-open" \
    ${modpkg:+"$modpkg"} \
    "nvidia-utils-${DRIVER_BRANCH}"
  ok "driver packages installed"

  # Pin the kernel/userspace driver to Ubuntu's build. CUDA + cuDNN still
  # come from NVIDIA's repo; only the driver stack is pinned.
  cat > /etc/apt/preferences.d/99-nvidia-driver-from-ubuntu <<'PIN'
# Keep the NVIDIA kernel driver and its userspace from the Ubuntu archive.
# Ubuntu ships prebuilt, signed modules matching the HWE kernel; NVIDIA's repo
# ships DKMS packages that may fail to build on very new kernels.
# CUDA toolkit and cuDNN are unaffected and still come from NVIDIA's repo.
Package: nvidia-driver-* nvidia-dkms-* nvidia-kernel-* nvidia-utils-* nvidia-compute-utils-* linux-modules-nvidia-* libnvidia-* xserver-xorg-video-nvidia-* nvidia-firmware-*
Pin: release o=Ubuntu
Pin-Priority: 1001
PIN
  ok "pinned driver stack to Ubuntu archive"
}

# =============================================================================
# 2. Bring the GPUs up without a reboot
# =============================================================================
#   nouveau leaves the GSP WPR2 region up, which blocks the NVIDIA driver.
#   Unload nouveau, unload the nvidia stack, PCI-reset each GPU, reload.
activate_driver() {
  step "Activating driver on the running kernel"

  if nvidia-smi >/dev/null 2>&1; then
    ok "nvidia-smi already working; nothing to do"
    return 0
  fi

  if lsmod | grep -q '^nouveau'; then
    warn "nouveau is loaded; unloading"
    # Stop the display manager if it is holding nouveau open.
    if ! modprobe -r nouveau 2>/dev/null; then
      local dm
      for dm in gdm3 lightdm sddm; do
        if systemctl is-active --quiet "$dm" 2>/dev/null; then
          warn "stopping ${dm} to release nouveau"
          systemctl stop "$dm" || true
        fi
      done
      modprobe -r nouveau 2>/dev/null || true
    fi
    lsmod | grep -q '^nouveau' \
      && { warn "could not unload nouveau; a reboot is required"; REBOOT_REQUIRED=1; return 0; }
    ok "nouveau unloaded"
  fi

  # Drop the nvidia stack so the PCI reset is clean.
  local m
  for m in nvidia_uvm nvidia_drm nvidia_modeset nvidia; do
    modprobe -r "$m" 2>/dev/null || true
  done

  # Function-level reset clears the stale WPR2 / GSP state left by nouveau.
  local dev
  for dev in $(lspci -D -d 10de: | grep -E '\[030[02]\]' | awk '{print $1}'); do
    if [ -w "/sys/bus/pci/devices/${dev}/reset" ]; then
      if echo 1 > "/sys/bus/pci/devices/${dev}/reset" 2>/dev/null; then
        ok "PCI reset ${dev}"
      else
        warn "PCI reset failed for ${dev} (may need a reboot)"
      fi
    fi
  done

  modprobe nvidia 2>/dev/null || true
  modprobe nvidia_uvm 2>/dev/null || true
  sleep 3

  if nvidia-smi >/dev/null 2>&1; then
    ok "driver active, GPUs responding"
  else
    warn "driver not responding yet - a reboot will clear this"
    warn "kernel log:"
    dmesg 2>/dev/null | grep -i 'NVRM' | tail -5 | sed 's/^/         /' || true
    REBOOT_REQUIRED=1
  fi
}

# =============================================================================
# 3. CUDA toolkit
# =============================================================================
install_cuda() {
  step "Installing CUDA Toolkit ${CUDA_MAJOR_MINOR}"

  if [ -x "${CUDA_HOME_PATH}/bin/nvcc" ]; then
    ok "already present: $("${CUDA_HOME_PATH}/bin/nvcc" --version | grep -oP 'release \K[0-9.]+')"
  else
    export DEBIAN_FRONTEND=noninteractive

    # Network repo + keyring. Provides the toolkit and the CUDA-13 cuDNN
    # builds, and stays current without a multi-GB local .deb.
    if [ ! -f /usr/share/keyrings/cuda-archive-keyring.gpg ] \
       && ! ls /etc/apt/sources.list.d/ 2>/dev/null | grep -q '^cuda-'; then
      local tmp; tmp="$(mktemp -d)"
      ( cd "$tmp"
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
        dpkg -i cuda-keyring_1.1-1_all.deb >/dev/null
      )
      rm -rf "$tmp"
      ok "added NVIDIA CUDA apt repository"
    else
      ok "NVIDIA CUDA repository already configured"
    fi

    apt-get update -qq

    apt-cache policy "cuda-toolkit-${CUDA_PKG_SUFFIX}" 2>/dev/null \
      | grep -q 'Candidate: [0-9]' \
      || die "cuda-toolkit-${CUDA_PKG_SUFFIX} not available in the repo"

    # cuda-toolkit-* deliberately does NOT pull a driver, so it cannot
    # clobber the pinned Ubuntu driver. Verify that assumption anyway.
    local plan
    plan=$(apt-get install -y -s "cuda-toolkit-${CUDA_PKG_SUFFIX}" 2>&1)
    if echo "$plan" | grep -q '^Remv'; then
      echo "$plan" | grep '^Remv' | sed 's/^/         /'
      die "CUDA install wants to REMOVE packages; refusing"
    fi

    apt-get install -y "cuda-toolkit-${CUDA_PKG_SUFFIX}"
    ldconfig
    ok "cuda-toolkit-${CUDA_PKG_SUFFIX} installed"
  fi
}

# =============================================================================
# 4. cuDNN  (must match CUDA major version)
# =============================================================================
install_cudnn() {
  [ "$DO_CUDNN" -eq 1 ] || { warn "skipping cuDNN (--no-cudnn)"; return 0; }
  step "Installing cuDNN for CUDA ${CUDA_MAJOR_MINOR%%.*}"

  local cuda_major="${CUDA_MAJOR_MINOR%%.*}"
  local pkg="cudnn9-cuda-${cuda_major}"

  if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
    ok "${pkg} already installed"
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-cache policy "$pkg" 2>/dev/null | grep -q 'Candidate: [0-9]' \
    || die "${pkg} not available. Do NOT install the bare 'cudnn' meta: on
         older cuDNN local repos it pulls the CUDA 12 build, which is
         incompatible with CUDA ${CUDA_MAJOR_MINOR}."

  apt-get install -y "$pkg"

  # The .debs land in /usr/lib/x86_64-linux-gnu (already an ldconfig dir), but
  # the linker cache is not always refreshed by the postinst. Without this,
  # dlopen("libcudnn.so.9") fails even though the file is present - which is
  # how PyTorch/TensorFlow look cuDNN up at runtime.
  ldconfig
  ok "${pkg} installed and linker cache refreshed"
}

# =============================================================================
# 5. Environment
# =============================================================================
setup_env() {
  step "Configuring CUDA environment in ${target_home}/.bashrc"

  local rc="${target_home}/.bashrc"
  [ -f "$rc" ] || { touch "$rc"; chown "$target_user:$target_user" "$rc"; }

  if grep -q '# >>> CUDA' "$rc" 2>/dev/null; then
    ok "CUDA block already present; leaving it alone"
  else
    cp -a "$rc" "${rc}.bak.pre-cuda"
    cat >> "$rc" <<EOF

# >>> CUDA ${CUDA_MAJOR_MINOR} >>>
export CUDA_HOME=${CUDA_HOME_PATH}
export PATH="\$CUDA_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="\$CUDA_HOME/lib64\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
# <<< CUDA ${CUDA_MAJOR_MINOR} <<<
EOF
    ok "appended CUDA env (backup: ${rc}.bak.pre-cuda)"
  fi

  # System-wide too, so non-login shells, systemd units and cron see nvcc.
  cat > /etc/profile.d/cuda.sh <<EOF
export CUDA_HOME=${CUDA_HOME_PATH}
export PATH="\$CUDA_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="\$CUDA_HOME/lib64\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
  chmod 0644 /etc/profile.d/cuda.sh
  ok "wrote /etc/profile.d/cuda.sh"
}

# =============================================================================
# 6. Verify - compile and RUN real code, do not just check versions
# =============================================================================
verify() {
  step "Verification"
  local fails=0

  # -- driver --
  if nvidia-smi >/dev/null 2>&1; then
    ok "nvidia-smi: driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
    nvidia-smi --query-gpu=index,name,memory.total,compute_cap \
               --format=csv,noheader 2>/dev/null | sed 's/^/         GPU /'
  else
    warn "nvidia-smi not working$([ "$REBOOT_REQUIRED" -eq 1 ] && echo ' - reboot required')"
    fails=$((fails+1))
  fi

  # -- nvcc --
  local nvcc="${CUDA_HOME_PATH}/bin/nvcc"
  if [ -x "$nvcc" ]; then
    ok "nvcc: $("$nvcc" --version | grep -oP 'release \K[0-9.]+, V[0-9.]+')"
  else
    warn "nvcc not found at ${nvcc}"; fails=$((fails+1)); nvcc=""
  fi

  # -- cuDNN --
  local cudnn_so
  cudnn_so=$(ldconfig -p 2>/dev/null | awk '/libcudnn\.so\.[0-9]/{print $NF; exit}')
  if [ -n "$cudnn_so" ]; then
    ok "cuDNN: $(basename "$cudnn_so")"
  elif [ "$DO_CUDNN" -eq 1 ]; then
    warn "libcudnn not found by ldconfig"; fails=$((fails+1))
  fi

  # -- run an actual kernel on every GPU --
  if [ -n "$nvcc" ] && nvidia-smi >/dev/null 2>&1 && command -v gcc >/dev/null 2>&1; then
    local d; d="$(mktemp -d)"
    cat > "$d/t.cu" <<'CU'
#include <cstdio>
#include <cuda_runtime.h>
__global__ void saxpy(int n, float a, float* x, float* y) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) y[i] = a * x[i] + y[i];
}
int main() {
  int nd = 0;
  if (cudaGetDeviceCount(&nd) != cudaSuccess || nd == 0) { printf("no CUDA devices\n"); return 1; }
  int rt = 0, dv = 0;
  cudaRuntimeGetVersion(&rt); cudaDriverGetVersion(&dv);
  printf("runtime %d.%d / driver %d.%d / %d device(s)\n",
         rt/1000, (rt%1000)/10, dv/1000, (dv%1000)/10, nd);
  int bad = 0;
  for (int dev = 0; dev < nd; ++dev) {
    cudaSetDevice(dev);
    cudaDeviceProp p; cudaGetDeviceProperties(&p, dev);
    const int n = 1 << 22; const size_t sz = n * sizeof(float);
    float *x = nullptr, *y = nullptr;
    if (cudaMalloc(&x, sz) != cudaSuccess || cudaMalloc(&y, sz) != cudaSuccess) {
      printf("GPU%d %s: cudaMalloc FAILED\n", dev, p.name); bad++; continue;
    }
    float* hx = (float*)malloc(sz); float* hy = (float*)malloc(sz);
    for (int i = 0; i < n; ++i) { hx[i] = 1.0f; hy[i] = 2.0f; }
    cudaMemcpy(x, hx, sz, cudaMemcpyHostToDevice);
    cudaMemcpy(y, hy, sz, cudaMemcpyHostToDevice);
    saxpy<<<(n + 255) / 256, 256>>>(n, 3.0f, x, y);
    cudaError_t e = cudaDeviceSynchronize();
    cudaMemcpy(hy, y, sz, cudaMemcpyDeviceToHost);
    double err = 0.0;
    for (int i = 0; i < n; ++i) { double dd = hy[i] - 5.0; err += dd < 0 ? -dd : dd; }
    int pass = (e == cudaSuccess) && (err == 0.0);
    printf("GPU%d %s sm_%d%d %.0fGB: %s\n", dev, p.name, p.major, p.minor,
           p.totalGlobalMem / 1073741824.0, pass ? "PASS" : "FAIL");
    if (!pass) bad++;
    cudaFree(x); cudaFree(y); free(hx); free(hy);
  }
  return bad ? 1 : 0;
}
CU
    if "$nvcc" -o "$d/t" "$d/t.cu" >"$d/build.log" 2>&1; then
      if "$d/t" 2>&1 | sed 's/^/         /'; then
        ok "CUDA kernel executed successfully on all GPUs"
      else
        warn "CUDA kernel run reported a failure"; fails=$((fails+1))
      fi
    else
      warn "nvcc failed to compile the test:"; tail -5 "$d/build.log" | sed 's/^/         /'
      fails=$((fails+1))
    fi

    # -- cuDNN handle on the GPU --
    if [ -n "$cudnn_so" ]; then
      local inc=""
      [ -f /usr/include/cudnn.h ] && inc="/usr/include"
      [ -f /usr/include/x86_64-linux-gnu/cudnn.h ] && inc="/usr/include/x86_64-linux-gnu"
      if [ -n "$inc" ]; then
        cat > "$d/c.cu" <<'CUDNN'
#include <cstdio>
#include <cudnn.h>
int main() {
  cudnnHandle_t h;
  cudnnStatus_t s = cudnnCreate(&h);
  printf("cuDNN %zu cudnnCreate: %s\n", cudnnGetVersion(), cudnnGetErrorString(s));
  if (s != CUDNN_STATUS_SUCCESS) return 1;
  cudnnDestroy(h);
  return 0;
}
CUDNN
        if "$nvcc" -I"$inc" -o "$d/c" "$d/c.cu" -lcudnn >"$d/cudnn.log" 2>&1 \
           && "$d/c" 2>&1 | sed 's/^/         /'; then
          ok "cuDNN initialised on the GPU"
        else
          warn "cuDNN test failed:"; tail -3 "$d/cudnn.log" 2>/dev/null | sed 's/^/         /'
          fails=$((fails+1))
        fi
      fi
    fi
    rm -rf "$d"
  fi

  echo
  if [ "$fails" -eq 0 ]; then
    echo "${G}${B}All checks passed.${N}"
  else
    echo "${Y}${B}${fails} check(s) need attention.${N}"
  fi
  return 0
}

# =============================================================================
main() {
  if [ "$VERIFY_ONLY" -eq 1 ]; then
    KERNEL="$(uname -r)"
    verify
    exit 0
  fi

  need_root
  preflight
  install_driver
  activate_driver
  install_cuda
  install_cudnn
  setup_env
  verify

  step "Done"
  echo "  Open a new shell (or: source ${target_home}/.bashrc) to pick up nvcc."
  if [ "$REBOOT_REQUIRED" -eq 1 ]; then
    echo
    echo "  ${Y}${B}Reboot required${N} to finish loading the driver:  sudo reboot"
    echo "  Then re-check with:  $0 --verify"
  fi
}

main "$@"
