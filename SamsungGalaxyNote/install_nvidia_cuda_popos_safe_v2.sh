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

path_owned_by_dpkg() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 1
  p="$(readlink -f "$p" 2>/dev/null || printf '%s' "$p")"
  dpkg-query -S "$p" >/dev/null 2>&1
}

capture_cmd() {
  local outfile="$1"; shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"$outfile" 2>&1 || true
}

check_no_broken_dpkg() {
  if dpkg --audit | grep -q .; then
    dpkg --audit || true
    die "dpkg reports unfinished/broken package state. Fix that before running this script."
  fi
}

check_no_broken_apt() {
  if ! apt-get check >/dev/null; then
    apt-get check || true
    die "apt-get check failed. Fix package problems before continuing."
  fi
}

check_disk_space() {
  local free_kb min_kb
  free_kb="$(df --output=avail / | tail -n1 | tr -d '[:space:]')"
  min_kb=$((8 * 1024 * 1024))   # 8 GiB
  [[ "$free_kb" =~ ^[0-9]+$ ]] || die "Unable to determine free disk space."
  if (( free_kb < min_kb )); then
    die "Less than 8 GiB free on /. Free some space before installing CUDA."
  fi
}

assert_package_managed_driver() {
  local nsmi
  nsmi="$(command -v nvidia-smi || true)"
  [[ -n "$nsmi" ]] || die "nvidia-smi is not available. Install/fix the NVIDIA driver first."
  if ! path_owned_by_dpkg "$nsmi"; then
    die "Current nvidia-smi is not owned by a dpkg package. This suggests a manual/runfile-managed driver. Refusing to mix install methods."
  fi
}

find_unmanaged_cuda_artifacts() {
  local f found=1
  shopt -s nullglob
  for f in /usr/local/cuda/bin/nvcc \
           /usr/local/cuda-*/bin/nvcc \
           /usr/local/cuda/bin/cuda-uninstaller \
           /usr/local/cuda-*/bin/cuda-uninstaller \
           /usr/bin/nvcc; do
    [[ -e "$f" ]] || continue
    if ! path_owned_by_dpkg "$f"; then
      printf '%s\n' "$f"
      found=0
    fi
  done
  shopt -u nullglob
  return "$found"
}

build_install_list() {
  local driver_branch="$1" toolkit_pkg="$2"
  local -a install_list candidates
  local pkg

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
      install_list+=("$pkg")
    fi
  done

  if ! pkg_installed "$toolkit_pkg"; then
    install_list+=("$toolkit_pkg")
  fi

  printf '%s\n' "${install_list[@]}"
}

run_apt_simulation_guard() {
  local sim_log="$1"; shift
  local -a pkgs=( "$@" )

  if ((${#pkgs[@]} == 0)); then
    log "Nothing to install after preflight checks."
    return 0
  fi

  log "Running APT simulation before real changes"
  apt-get -s install "${pkgs[@]}" | tee "$sim_log"

  if grep -E '^(Remv|Purg) ' "$sim_log" | grep -Eq '(system76-driver-nvidia|pop-desktop|gdm3|gnome-shell|nvidia|cuda)'; then
    die "APT simulation wants to remove critical NVIDIA/desktop packages. Aborting to protect the system."
  fi
}

write_cuda_path_profile() {
  local cuda_profile="/etc/profile.d/cuda-path.sh"

  if command -v nvcc >/dev/null 2>&1; then
    return 0
  fi

  if [[ -x /usr/local/cuda/bin/nvcc ]]; then
    cat > "$cuda_profile" <<'EOF'
export PATH=/usr/local/cuda/bin:${PATH}
EOF
    chmod 0644 "$cuda_profile"
    export PATH=/usr/local/cuda/bin:${PATH}
    return 0
  fi

  shopt -s nullglob
  local nvcc_candidates=(/usr/local/cuda-*/bin/nvcc)
  shopt -u nullglob
  if ((${#nvcc_candidates[@]} > 0)); then
    local nvcc_dir
    nvcc_dir="$(dirname "${nvcc_candidates[0]}")"
    cat > "$cuda_profile" <<EOF
export PATH=${nvcc_dir}:\${PATH}
EOF
    chmod 0644 "$cuda_profile"
    export PATH="${nvcc_dir}:${PATH}"
    return 0
  fi

  return 1
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
  require_cmd lspci
  require_cmd df

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
      warn "Secure Boot appears to be enabled. Future driver rebuilds/updates may fail under Secure Boot."
    fi
  fi

  if ! lspci | grep -qi nvidia; then
    die "No NVIDIA GPU was detected by lspci."
  fi

  local driver_full driver_branch
  assert_package_managed_driver
  driver_full="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d '[:space:]')"
  [[ -n "$driver_full" ]] || die "Could not determine NVIDIA driver version."
  driver_branch="${driver_full%%.*}"

  log "Detected NVIDIA driver version: ${driver_full}"
  log "Detected NVIDIA driver branch: ${driver_branch}"

  if [[ "$driver_branch" -lt 580 ]]; then
    die "CUDA 13.x requires driver branch 580 or newer. Current branch: ${driver_branch}"
  fi

  check_no_broken_dpkg
  check_no_broken_apt
  check_disk_space

  if ! pkg_installed "linux-headers-${kernel}"; then
    warn "Kernel headers for ${kernel} are not installed. Not fatal for toolkit install, but recommended for future DKMS work."
  fi

  if ! command -v gcc >/dev/null 2>&1; then
    warn "gcc not found; installing build-essential because CUDA development uses gcc."
    apt-get update
    apt-get install -y build-essential
  fi

  if [[ -f /var/log/nvidia-installer.log ]]; then
    warn "Found /var/log/nvidia-installer.log. This alone is not a proof of an active runfile install."
  fi

  local unmanaged_artifacts=""
  unmanaged_artifacts="$(find_unmanaged_cuda_artifacts || true)"
  if [[ -n "$unmanaged_artifacts" ]] && ! dpkg-query -W 'cuda-toolkit*' >/dev/null 2>&1; then
    printf '%s\n' "$unmanaged_artifacts" | sed 's/^/[WARN] Unmanaged CUDA artifact: /'
    die "Detected unmanaged CUDA toolkit artifacts not owned by dpkg. Refusing to mix install methods."
  fi

  if [[ -f /var/log/nvidia-installer.log ]] && [[ -z "$unmanaged_artifacts" ]]; then
    warn "Proceeding because driver files are dpkg-managed and no active unmanaged CUDA toolkit artifacts were detected."
  fi

  log "Saving pre-change snapshots"
  cp -a /etc/apt "$backup_dir/etc-apt"
  dpkg-query -W > "${backup_dir}/dpkg-query-before.txt"
  dpkg-query -W 'nvidia*' 'libnvidia*' 'cuda*' 'nsight*' 2>/dev/null | sort > "${backup_dir}/gpu-packages-before.txt" || true
  apt-mark showhold > "${backup_dir}/apt-holds-before.txt" || true
  capture_cmd "${backup_dir}/hostnamectl-before.txt" hostnamectl
  capture_cmd "${backup_dir}/nvidia-smi-before.txt" nvidia-smi
  capture_cmd "${backup_dir}/nvidia-smi-q-before.txt" nvidia-smi -q
  capture_cmd "${backup_dir}/lsmod-before.txt" lsmod
  capture_cmd "${backup_dir}/modinfo-nvidia-before.txt" modinfo nvidia
  capture_cmd "${backup_dir}/ldconfig-before.txt" ldconfig -p
  capture_cmd "${backup_dir}/dpkg-audit-before.txt" dpkg --audit
  capture_cmd "${backup_dir}/apt-check-before.txt" apt-get check

  log "Refreshing APT metadata"
  apt-get update

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

  mapfile -t INSTALL_LIST < <(build_install_list "$driver_branch" "$toolkit_pkg")
  printf '%s\n' "${INSTALL_LIST[@]-}" > "${backup_dir}/planned-install-list.txt"
  run_apt_simulation_guard "${backup_dir}/apt-simulation.txt" "${INSTALL_LIST[@]-}"

  if ((${#INSTALL_LIST[@]} > 0)); then
    log "Installing packages:"
    printf '  %s\n' "${INSTALL_LIST[@]}"
    apt-get install -y "${INSTALL_LIST[@]}"
  else
    log "All selected NVIDIA ${driver_branch}-series libraries and ${toolkit_pkg} are already installed."
  fi

  write_cuda_path_profile || true
  command -v nvcc >/dev/null 2>&1 || die "nvcc was not found after installation."

  log "Running post-install system health checks"
  check_no_broken_dpkg
  check_no_broken_apt
  check_disk_space

  capture_cmd "${backup_dir}/nvidia-smi-after.txt" nvidia-smi
  capture_cmd "${backup_dir}/nvidia-smi-q-after.txt" nvidia-smi -q
  capture_cmd "${backup_dir}/nvcc-after.txt" nvcc -V
  capture_cmd "${backup_dir}/lsmod-after.txt" lsmod
  capture_cmd "${backup_dir}/modinfo-nvidia-after.txt" modinfo nvidia
  capture_cmd "${backup_dir}/ldconfig-after.txt" ldconfig -p
  capture_cmd "${backup_dir}/dpkg-audit-after.txt" dpkg --audit
  capture_cmd "${backup_dir}/apt-check-after.txt" apt-get check
  capture_cmd "${backup_dir}/driver-owner-after.txt" dpkg-query -S "$(readlink -f "$(command -v nvidia-smi)")"

  if command -v dkms >/dev/null 2>&1; then
    capture_cmd "${backup_dir}/dkms-status-after.txt" dkms status
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

1) Remove the CUDA toolkit layer:
   sudo apt remove ${toolkit_pkg} cuda-keyring

2) Remove the NVIDIA CUDA repo entry if needed:
   sudo rm -f /etc/apt/sources.list.d/cuda-${cuda_repo_distro}-${cuda_repo_arch}.list
   sudo apt update

3) Reinstall the Pop!_OS NVIDIA driver stack if graphics/login breaks:
   sudo apt update
   sudo apt full-upgrade
   sudo apt install --reinstall system76-driver-nvidia

4) If desktop packages also need repair:
   sudo apt install --reinstall gdm3 pop-desktop gnome-shell
   sudo systemctl reboot
EOF

  log "Done."
  log "Backup, logs, simulation output, smoke test, and rollback notes are in: ${backup_dir}"
  log "A reboot is recommended before heavy CUDA use."
}

main "$@"
