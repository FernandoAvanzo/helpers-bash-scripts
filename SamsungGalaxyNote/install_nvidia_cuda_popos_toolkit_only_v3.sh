#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

SCRIPT_VERSION="v3-toolkit-only"

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

trap 'rc=$?; printf "[ERROR] Failed at line %s (exit %s). Review the log and backup directory.\n" "$LINENO" "$rc" >&2' ERR

DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./install_nvidia_cuda_popos_toolkit_only_v3.sh [--dry-run]

What this script does:
  - Keeps the currently installed NVIDIA driver untouched
  - Installs only the NVIDIA CUDA Toolkit from NVIDIA's Ubuntu 24.04 repo
  - Selects the newest CUDA Toolkit release that is fully supported by the
    currently installed driver version
  - Refuses to install any NVIDIA driver packages or desktop-breaking removals

What this script does not do:
  - It does not replace, upgrade, downgrade, or uninstall your NVIDIA driver
  - It does not try to "fix" a broken manual NVIDIA driver install
  - It does not layer a repo-managed toolkit on top of an already installed
    runfile-managed CUDA Toolkit
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

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

pkg_version_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Version}\n' "$pkg" 2>/dev/null || true
}

path_owned_by_dpkg() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 1
  p="$(readlink -f "$p" 2>/dev/null || printf '%s' "$p")"
  dpkg-query -S "$p" >/dev/null 2>&1
}

version_ge() {
  dpkg --compare-versions "$1" ge "$2"
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

driver_mode() {
  local nsmi="$1"
  if path_owned_by_dpkg "$nsmi"; then
    printf 'dpkg-managed'
  else
    printf 'manual-or-non-dpkg'
  fi
}

find_unmanaged_cuda_toolkit_artifacts() {
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

assert_no_existing_conflicting_toolkit() {
  local nvcc_path unmanaged
  nvcc_path="$(command -v nvcc || true)"

  if [[ -n "$nvcc_path" ]]; then
    if path_owned_by_dpkg "$nvcc_path"; then
      log "CUDA Toolkit already appears to be installed from packages: $nvcc_path"
      capture_cmd "${BACKUP_DIR}/nvcc-existing.txt" nvcc -V
      die "CUDA Toolkit is already installed. Remove it first if you want a different version."
    else
      die "An existing non-dpkg CUDA Toolkit was found at ${nvcc_path}. Remove it with the matching CUDA uninstaller before using this script."
    fi
  fi

  unmanaged="$(find_unmanaged_cuda_toolkit_artifacts || true)"
  if [[ -n "$unmanaged" ]]; then
    printf '%s\n' "$unmanaged" | sed 's/^/[WARN] Unmanaged CUDA toolkit artifact: /'
    die "Detected an existing unmanaged CUDA Toolkit installation. Refusing to mix toolkit install methods."
  fi
}

ensure_cuda_repo() {
  local cuda_repo_distro="ubuntu2404"
  local cuda_repo_arch="x86_64"
  local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${cuda_repo_distro}/${cuda_repo_arch}/cuda-keyring_1.1-1_all.deb"
  local tmp_deb="${BACKUP_DIR}/cuda-keyring_1.1-1_all.deb"

  if ! pkg_installed cuda-keyring && [[ ! -f /etc/apt/sources.list.d/cuda-${cuda_repo_distro}-${cuda_repo_arch}.list ]]; then
    log "Adding NVIDIA CUDA network repository for Ubuntu 24.04 / x86_64"
    fetch "$keyring_url" "$tmp_deb"
    dpkg -i "$tmp_deb"
  else
    log "NVIDIA CUDA repo/keyring already present; skipping repository bootstrap."
  fi

  apt-get update
}

pkg_version_available() {
  local pkg="$1" ver="$2"
  apt-cache madison "$pkg" 2>/dev/null | awk '{print $3}' | grep -Fxq "$ver"
}

select_toolkit_package() {
  local driver="$1"
  local entry min pkg ver label
  local -a matrix=(
    '595.45.04|cuda-toolkit-13-2|13.2.0-1|CUDA 13.2 GA'
    '590.48.01|cuda-toolkit-13-1|13.1.1-1|CUDA 13.1 Update 1'
    '590.44.01|cuda-toolkit-13-1|13.1.0-1|CUDA 13.1 GA'
    '580.95.05|cuda-toolkit-13-0|13.0.2-1|CUDA 13.0 Update 2'
    '580.82.07|cuda-toolkit-13-0|13.0.1-1|CUDA 13.0 Update 1'
    '580.65.06|cuda-toolkit-13-0|13.0.0-1|CUDA 13.0 GA'
    '575.57.08|cuda-toolkit-12-9|12.9.1-1|CUDA 12.9 Update 1'
    '575.51.03|cuda-toolkit-12-9|12.9.0-1|CUDA 12.9 GA'
    '570.124.06|cuda-toolkit-12-8|12.8.1-1|CUDA 12.8 Update 1'
    '570.26|cuda-toolkit-12-8|12.8.0-1|CUDA 12.8 GA'
    '560.35.05|cuda-toolkit-12-6|12.6.3-1|CUDA 12.6 Update 3'
    '560.35.03|cuda-toolkit-12-6|12.6.2-1|CUDA 12.6 Update 2'
    '560.28.03|cuda-toolkit-12-6|12.6.0-1|CUDA 12.6 GA'
    '555.42.06|cuda-toolkit-12-5|12.5.1-1|CUDA 12.5 Update 1'
  )

  for entry in "${matrix[@]}"; do
    IFS='|' read -r min pkg ver label <<<"$entry"
    if version_ge "$driver" "$min"; then
      if pkg_version_available "$pkg" "$ver"; then
        SELECTED_TOOLKIT_PKG="$pkg"
        SELECTED_TOOLKIT_VER="$ver"
        SELECTED_TOOLKIT_LABEL="$label"
        SELECTED_TOOLKIT_MIN_DRIVER="$min"
        return 0
      fi
    fi
  done

  die "Could not find a fully supported CUDA Toolkit package in NVIDIA's Ubuntu 24.04 repo for driver ${driver}. Upgrade the driver manually with NVIDIA's installer first, or use a container-based CUDA workflow."
}

run_apt_simulation_guard() {
  local sim_log="$1"; shift
  local -a pkgs=( "$@" )

  [[ ${#pkgs[@]} -gt 0 ]] || die "Internal error: simulation called with empty package list."

  log "Running APT simulation before real changes"
  apt-get -s install --allow-downgrades "${pkgs[@]}" | tee "$sim_log"

  if grep -E '^(Remv|Purg) ' "$sim_log" | grep -Eq '(system76-driver-nvidia|pop-desktop|gdm3|gnome-shell|cuda|nvidia)'; then
    die "APT simulation wants to remove critical NVIDIA/CUDA/desktop packages. Aborting to protect the system."
  fi

  if grep -E '^Inst ' "$sim_log" | awk '{print $2}' | grep -Eq '^(cuda-drivers|cuda-runtime|cuda-compat|nvidia-driver|nvidia-dkms|nvidia-kernel|nvidia-utils-[0-9]+|nvidia-compute-utils-[0-9]+|libnvidia-|xserver-xorg-video-nvidia|nvidia-fabricmanager)'; then
    die "APT simulation wants to install NVIDIA driver-related packages. This script is toolkit-only and refuses to touch the driver stack."
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
  [[ $EUID -eq 0 ]] || exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"

  require_cmd hostnamectl
  require_cmd apt-get
  require_cmd apt-cache
  require_cmd dpkg
  require_cmd grep
  require_cmd awk
  require_cmd sed
  require_cmd lspci
  require_cmd df
  require_cmd sha256sum

  export DEBIAN_FRONTEND=noninteractive

  local ts log_file
  ts="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="/var/backups/nvidia-cuda-toolkit-only-${ts}"
  mkdir -p "$BACKUP_DIR"
  log_file="${BACKUP_DIR}/install.log"
  exec > >(tee -a "$log_file") 2>&1

  log "Starting NVIDIA CUDA Toolkit installation (${SCRIPT_VERSION})"
  log "Backup directory: ${BACKUP_DIR}"

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
      warn "Secure Boot appears to be enabled. Manual NVIDIA driver installs often do not cooperate well with Secure Boot."
    fi
  fi

  if ! lspci | grep -qi nvidia; then
    die "No NVIDIA GPU was detected by lspci."
  fi

  local nsmi driver_full driver_kind driver_hash_before
  nsmi="$(command -v nvidia-smi || true)"
  [[ -n "$nsmi" ]] || die "nvidia-smi is not available. Install/fix the NVIDIA driver first."

  driver_full="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d '[:space:]')"
  [[ -n "$driver_full" ]] || die "Could not determine NVIDIA driver version from nvidia-smi."

  driver_kind="$(driver_mode "$nsmi")"
  driver_hash_before="$(sha256sum "$(readlink -f "$nsmi")" | awk '{print $1}')"

  log "Detected NVIDIA driver version: ${driver_full}"
  log "Detected NVIDIA driver ownership mode: ${driver_kind}"
  if [[ "$driver_kind" == "manual-or-non-dpkg" ]]; then
    warn "Driver is not owned by dpkg. That is acceptable here because this script installs only the CUDA Toolkit and explicitly blocks driver packages."
  fi

  check_no_broken_dpkg
  check_no_broken_apt
  check_disk_space
  assert_no_existing_conflicting_toolkit

  if ! command -v gcc >/dev/null 2>&1; then
    warn "gcc not found; installing build-essential because CUDA development requires a host compiler."
    apt-get update
    apt-get install -y build-essential
  fi

  log "Saving pre-change snapshots"
  cp -a /etc/apt "${BACKUP_DIR}/etc-apt"
  dpkg-query -W > "${BACKUP_DIR}/dpkg-query-before.txt"
  dpkg-query -W 'nvidia*' 'libnvidia*' 'cuda*' 'nsight*' 2>/dev/null | sort > "${BACKUP_DIR}/gpu-packages-before.txt" || true
  apt-mark showhold > "${BACKUP_DIR}/apt-holds-before.txt" || true
  capture_cmd "${BACKUP_DIR}/hostnamectl-before.txt" hostnamectl
  capture_cmd "${BACKUP_DIR}/nvidia-smi-before.txt" nvidia-smi
  capture_cmd "${BACKUP_DIR}/nvidia-smi-q-before.txt" nvidia-smi -q
  capture_cmd "${BACKUP_DIR}/lsmod-before.txt" lsmod
  capture_cmd "${BACKUP_DIR}/modinfo-nvidia-before.txt" modinfo nvidia
  capture_cmd "${BACKUP_DIR}/ldconfig-before.txt" ldconfig -p
  capture_cmd "${BACKUP_DIR}/dpkg-audit-before.txt" dpkg --audit
  capture_cmd "${BACKUP_DIR}/apt-check-before.txt" apt-get check
  printf '%s\n' "$driver_hash_before" > "${BACKUP_DIR}/nvidia-smi-sha256-before.txt"

  ensure_cuda_repo
  select_toolkit_package "$driver_full"

  log "Selected toolkit: ${SELECTED_TOOLKIT_LABEL}"
  log "Selected package: ${SELECTED_TOOLKIT_PKG}=${SELECTED_TOOLKIT_VER}"
  log "Minimum driver for selected toolkit: ${SELECTED_TOOLKIT_MIN_DRIVER}"

  local current_pkg_ver install_spec
  current_pkg_ver="$(pkg_version_installed "$SELECTED_TOOLKIT_PKG")"
  install_spec="${SELECTED_TOOLKIT_PKG}=${SELECTED_TOOLKIT_VER}"

  if [[ "$current_pkg_ver" == "$SELECTED_TOOLKIT_VER" ]]; then
    log "The selected CUDA Toolkit package is already installed at the exact requested version."
  else
    printf '%s\n' "$install_spec" > "${BACKUP_DIR}/planned-install-list.txt"
    run_apt_simulation_guard "${BACKUP_DIR}/apt-simulation.txt" "$install_spec"

    if (( DRY_RUN )); then
      log "Dry-run requested; stopping before installation."
      exit 0
    fi

    log "Installing toolkit package: ${install_spec}"
    apt-get install -y --allow-downgrades "$install_spec"
  fi

  write_cuda_path_profile || true
  command -v nvcc >/dev/null 2>&1 || die "nvcc was not found after installation."

  local driver_after driver_hash_after
  driver_after="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d '[:space:]')"
  driver_hash_after="$(sha256sum "$(readlink -f "$nsmi")" | awk '{print $1}')"
  printf '%s\n' "$driver_hash_after" > "${BACKUP_DIR}/nvidia-smi-sha256-after.txt"

  if [[ "$driver_after" != "$driver_full" ]]; then
    die "Driver version changed from ${driver_full} to ${driver_after}. This script is supposed to leave the driver untouched."
  fi

  if [[ "$driver_hash_after" != "$driver_hash_before" ]]; then
    warn "The nvidia-smi binary hash changed even though the reported driver version did not. Review the APT simulation log and package list."
  fi

  log "Running post-install system health checks"
  check_no_broken_dpkg
  check_no_broken_apt
  check_disk_space

  capture_cmd "${BACKUP_DIR}/nvidia-smi-after.txt" nvidia-smi
  capture_cmd "${BACKUP_DIR}/nvidia-smi-q-after.txt" nvidia-smi -q
  capture_cmd "${BACKUP_DIR}/nvcc-after.txt" nvcc -V
  capture_cmd "${BACKUP_DIR}/lsmod-after.txt" lsmod
  capture_cmd "${BACKUP_DIR}/modinfo-nvidia-after.txt" modinfo nvidia
  capture_cmd "${BACKUP_DIR}/ldconfig-after.txt" ldconfig -p
  capture_cmd "${BACKUP_DIR}/dpkg-audit-after.txt" dpkg --audit
  capture_cmd "${BACKUP_DIR}/apt-check-after.txt" apt-get check

  cat > "${BACKUP_DIR}/cuda-smoke.cu" <<'EOF'
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
  "$nvcc_path" -o "${BACKUP_DIR}/cuda-smoke" "${BACKUP_DIR}/cuda-smoke.cu"
  "${BACKUP_DIR}/cuda-smoke" | tee "${BACKUP_DIR}/cuda-smoke-output.txt"

  dpkg-query -W 'nvidia*' 'libnvidia*' 'cuda*' 'nsight*' 2>/dev/null | sort > "${BACKUP_DIR}/gpu-packages-after.txt" || true

  cat > "${BACKUP_DIR}/ROLLBACK.txt" <<EOF
Rollback notes
==============

1) Remove the CUDA toolkit package installed by this script:
   sudo apt remove ${SELECTED_TOOLKIT_PKG}

2) Remove the NVIDIA CUDA repo entry if needed:
   sudo apt remove cuda-keyring
   sudo rm -f /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list
   sudo apt update

3) Remove the PATH helper added by this script if needed:
   sudo rm -f /etc/profile.d/cuda-path.sh

4) This script does not manage the NVIDIA driver. If you need to change the driver,
   use NVIDIA's own driver installer or your preferred existing driver workflow.

5) Verify:
   nvidia-smi
   nvcc -V
EOF

  log "Done."
  log "Toolkit package installed without intentionally modifying the driver stack."
  log "Backup, logs, simulation output, smoke test, and rollback notes are in: ${BACKUP_DIR}"
  log "A logout/login (or reboot) is recommended before heavy CUDA use."
}

declare -a ORIGINAL_ARGS=( "$@" )
declare BACKUP_DIR=""
declare SELECTED_TOOLKIT_PKG=""
declare SELECTED_TOOLKIT_VER=""
declare SELECTED_TOOLKIT_LABEL=""
declare SELECTED_TOOLKIT_MIN_DRIVER=""

main "$@"
