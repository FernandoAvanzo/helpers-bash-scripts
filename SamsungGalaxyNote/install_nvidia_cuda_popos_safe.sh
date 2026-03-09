#!/usr/bin/env bash
set -Eeuo pipefail

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

trap 'printf "[ERROR] Failed at line %s. Review the log and backup directory.\n" "$LINENO" >&2' ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

fetch() {
  local url="$1" out="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  else
    die "Neither wget nor curl is installed."
  fi
}

pkg_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

pkg_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

main() {
  [[ $EUID -eq 0 ]] || exec sudo -E bash "$0" "$@"

  require_cmd hostnamectl
  require_cmd apt-get
  require_cmd apt-cache
  require_cmd dpkg
  require_cmd grep
  require_cmd awk
  require_cmd sed

  export DEBIAN_FRONTEND=noninteractive

  local ts backup_dir log_file
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_dir="/var/backups/nvidia-cuda-safe-${ts}"
  mkdir -p "$backup_dir"
  log_file="${backup_dir}/install.log"
  exec > >(tee -a "$log_file") 2>&1

  log "Starting safe NVIDIA userspace/CUDA installation"
  log "Backup directory: ${backup_dir}"

  local os_name os_version arch kernel
  os_name="$(. /etc/os-release && printf '%s' "${NAME:-unknown}")"
  os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")"
  arch="$(dpkg --print-architecture)"
  kernel="$(uname -r)"

  log "Detected OS: ${os_name} ${os_version}"
  log "Detected kernel: ${kernel}"
  log "Detected architecture: ${arch}"

  [[ "$arch" == "amd64" ]] || die "This script is written for amd64/x86_64 systems."
  [[ "$os_name" == "Pop!_OS" || "$os_name" == "Ubuntu" ]] || die "This script expects Pop!_OS or Ubuntu."
  [[ "$os_version" == "24.04" ]] || warn "This script was prepared for Pop!_OS/Ubuntu 24.04. Continuing with caution."

  if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
      warn "Secure Boot appears to be enabled. Because this script avoids changing the kernel driver branch, it may still work, but any later driver rebuild/update can fail under Secure Boot."
    fi
  fi

  if ! lspci | grep -qi nvidia; then
    die "No NVIDIA GPU was detected by lspci."
  fi

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    die "nvidia-smi is not available. Install/fix the NVIDIA driver first."ç
  fi

  local driver_full driver_branch
  driver_full="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d '[:space:]')"
  [[ -n "$driver_full" ]] || die "Could not determine NVIDIA driver version."
  driver_branch="${driver_full%%.*}"

  log "Detected NVIDIA driver version: ${driver_full}"
  log "Detected NVIDIA driver branch: ${driver_branch}"

  if [[ "$driver_branch" -lt 580 ]]; then
    die "CUDA 13.x requires driver branch 580 or newer. Current branch: ${driver_branch}"
  fi

  if dpkg --audit | grep -q .; then
    dpkg --audit || true
    die "dpkg reports unfinished/broken package state. Fix that before running this script."
  fi

  if ! apt-get check; then
    die "apt-get check failed. Fix package problems before continuing."
  fi

  local free_kb min_kb
  free_kb="$(df --output=avail / | tail -n1 | tr -d '[:space:]')"
  min_kb=$((8 * 1024 * 1024))   # conservative 8 GiB floor
  if [[ "$free_kb" -lt "$min_kb" ]]; then
    die "Less than 8 GiB free on /. Free some space before installing CUDA."
  fi

  if ! pkg_installed "linux-headers-${kernel}"; then
    warn "Kernel headers for ${kernel} are not installed. This script does not rebuild the driver, but headers are recommended for future DKMS work."
  fi

  if ! command -v gcc >/dev/null 2>&1; then
    warn "gcc not found; installing build-essential because CUDA development uses gcc."
    apt-get update
    apt-get install -y build-essential
  fi

  if [[ -f /var/log/nvidia-installer.log ]]; then
    warn "Found /var/log/nvidia-installer.log. That can indicate a previous runfile-based NVIDIA install."
  fi

  local conflicting=0
  if compgen -G '/usr/local/cuda-*' >/dev/null 2>&1 && ! dpkg-query -W 'cuda-toolkit*' >/dev/null 2>&1; then
    warn "Found /usr/local/cuda-* directories without dpkg-owned CUDA toolkit packages."
    conflicting=1
  fi
  if [[ -f /var/log/nvidia-installer.log ]] && ! dpkg-query -W 'cuda-keyring' >/dev/null 2>&1; then
    warn "Possible previous runfile install detected."
    conflicting=1
  fi
  if [[ "$conflicting" -eq 1 ]]; then
    die "Possible conflicting manual/runfile CUDA/NVIDIA installation detected. Remove that first to avoid mixing install methods."
  fi

  log "Saving pre-change snapshots"
  cp -a /etc/apt "$backup_dir/etc-apt"
  dpkg-query -W > "${backup_dir}/dpkg-query-before.txt"
  dpkg-query -W 'nvidia*' 'libnvidia*' 'cuda*' 'nsight*' 2>/dev/null | sort > "${backup_dir}/gpu-packages-before.txt" || true
  apt-mark showhold > "${backup_dir}/apt-holds-before.txt" || true
  nvidia-smi -q > "${backup_dir}/nvidia-smi-before.txt" || true
  hostnamectl > "${backup_dir}/hostnamectl-before.txt" || true

  log "Refreshing APT metadata"
  apt-get update

  local -a candidates missing
  candidates=(
    "libnvidia-common-${driver_branch}"
    "libnvidia-cfg1-${driver_branch}"
    "libnvidia-compute-${driver_branch}"
    "libnvidia-decode-${driver_branch}"
    "libnvidia-encode-${driver_branch}"
    "libnvidia-extra-${driver_branch}"
    "libnvidia-fbc1-${driver_branch}"
    "libnvidia-gl-${driver_branch}"
    "nvidia-compute-utils-${driver_branch}"
    "nvidia-utils-${driver_branch}"
  )

  for pkg in "${candidates[@]}"; do
    if pkg_available "$pkg" && ! pkg_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done

  if ((${#missing[@]} > 0)); then
    log "Installing missing NVIDIA ${driver_branch}-series user-space libraries:"
    printf '  %s\n' "${missing[@]}"
    apt-get install -y "${missing[@]}"
  else
    log "All selected NVIDIA ${driver_branch}-series user-space libraries are already installed."
  fi

  local cuda_repo_distro cuda_repo_arch keyring_url tmp_deb
  cuda_repo_distro="ubuntu2404"
  cuda_repo_arch="x86_64"
  keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${cuda_repo_distro}/${cuda_repo_arch}/cuda-keyring_1.1-1_all.deb"
  tmp_deb="${backup_dir}/cuda-keyring_1.1-1_all.deb"

  if ! pkg_installed cuda-keyring && [[ ! -f /etc/apt/sources.list.d/cuda-${cuda_repo_distro}-${cuda_repo_arch}.list ]]; then
    log "Adding NVIDIA CUDA repository for Ubuntu 24.04 / x86_64"
    fetch "$keyring_url" "$tmp_deb"
    dpkg -i "$tmp_deb"
  else
    log "CUDA repository/keyring already present; skipping repository bootstrap."
  fi

  apt-get update

  local toolkit_pkg
  toolkit_pkg="cuda-toolkit-13-0"
  if ! pkg_available "$toolkit_pkg"; then
    warn "${toolkit_pkg} not found; falling back to cuda-toolkit (latest stable in NVIDIA repo)."
    toolkit_pkg="cuda-toolkit"
  fi

  if pkg_installed "$toolkit_pkg"; then
    log "Toolkit package already installed: ${toolkit_pkg}"
  else
    log "Installing CUDA toolkit package: ${toolkit_pkg}"
    apt-get install -y "$toolkit_pkg"
  fi

  local cuda_profile="/etc/profile.d/cuda-path.sh"
  if ! command -v nvcc >/dev/null 2>&1; then
    if [[ -x /usr/local/cuda/bin/nvcc ]]; then
      log "nvcc exists in /usr/local/cuda/bin; writing ${cuda_profile} so it appears in future shells."
      cat > "$cuda_profile" <<'EOF'
export PATH=/usr/local/cuda/bin:${PATH}
EOF
      chmod 0644 "$cuda_profile"
      export PATH=/usr/local/cuda/bin:${PATH}
    elif [[ -x /usr/local/cuda-13.0/bin/nvcc ]]; then
      log "nvcc exists in /usr/local/cuda-13.0/bin; writing ${cuda_profile} so it appears in future shells."
      cat > "$cuda_profile" <<'EOF'
export PATH=/usr/local/cuda-13.0/bin:${PATH}
EOF
      chmod 0644 "$cuda_profile"
      export PATH=/usr/local/cuda-13.0/bin:${PATH}
    fi
  fi

  command -v nvcc >/dev/null 2>&1 || die "nvcc was not found after installation."

  log "Running post-install checks"
  apt-get check
  nvidia-smi | tee "${backup_dir}/nvidia-smi-after.txt"
  nvcc -V | tee "${backup_dir}/nvcc-after.txt"

  if command -v dkms >/dev/null 2>&1; then
    dkms status | tee "${backup_dir}/dkms-status-after.txt" || true
  fi

  cat > "${backup_dir}/cuda-smoke.cu" <<'EOF'
#include <cstdio>
#include <cuda_runtime.h>

int main() {
    int count = 0;
    cudaError_t err = cudaGetDeviceCount(&count);
    if (err != cudaSuccess) {
        std::fprintf(stderr, "cudaGetDeviceCount failed: %s\n", cudaGetErrorString(err));
        return 1;
    }
    std::printf("CUDA devices visible: %d\n", count);
    return (count > 0) ? 0 : 2;
}
EOF

  local nvcc_path
  nvcc_path="$(command -v nvcc)"
  "$nvcc_path" -o "${backup_dir}/cuda-smoke" "${backup_dir}/cuda-smoke.cu"
  "${backup_dir}/cuda-smoke" | tee "${backup_dir}/cuda-smoke-output.txt"

  dpkg-query -W 'nvidia*' 'libnvidia*' 'cuda*' 'nsight*' 2>/dev/null | sort > "${backup_dir}/gpu-packages-after.txt" || true

  cat > "${backup_dir}/ROLLBACK.txt" <<EOF
Rollback notes
==============

1) Remove the CUDA toolkit if you decide to undo only the toolkit layer:
   sudo apt remove ${toolkit_pkg} cuda-keyring

2) Remove the NVIDIA CUDA repo entry if needed:
   sudo rm -f /etc/apt/sources.list.d/cuda-${cuda_repo_distro}-${cuda_repo_arch}.list
   sudo apt update

3) If graphics/login breaks on Pop!_OS, boot to recovery or a TTY and reinstall the System76 NVIDIA driver:
   sudo apt update
   sudo apt install --reinstall system76-driver-nvidia

4) If the desktop still fails to start after that:
   sudo apt install --reinstall gdm3 pop-desktop gnome-shell
   sudo systemctl reboot
EOF

  log "Done."
  log "Backup, logs, smoke test, and rollback notes are in: ${backup_dir}"
  log "A reboot is recommended before heavy CUDA use."
}

main "$@"
