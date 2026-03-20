#!/usr/bin/env bash
set -Eeuo pipefail

# popos-nvidia-graphics-stack-safe-setup.sh
# Purpose:
#   Safely install OpenGL/EGL/GLX/Vulkan user-space libraries and tools on
#   Pop!_OS / Ubuntu systems with NVIDIA graphics, without forcibly changing
#   the NVIDIA driver branch.
#
# What it does:
#   - validates the host is Pop!_OS / Ubuntu and that APT is healthy
#   - records pre-install diagnostics
#   - installs only packages that actually exist in the configured repos
#   - avoids purging or replacing the NVIDIA driver metapackage
#   - records post-install diagnostics for verification
#
# What it does NOT do:
#   - install CUDA toolkit / OptiX SDK
#   - purge existing graphics drivers
#   - switch driver branches automatically
#
# Usage:
#   chmod +x popos-nvidia-graphics-stack-safe-setup.sh
#   sudo ./popos-nvidia-graphics-stack-safe-setup.sh

LOG_DIR="/var/log/popos-gpu-setup"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/run-${RUN_STAMP}.log"
REPORT_FILE="${LOG_DIR}/report-${RUN_STAMP}.txt"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE" "$REPORT_FILE"
chmod 600 "$LOG_FILE" "$REPORT_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo
    echo "ERROR: Script aborted with exit code $exit_code"
    echo "Check log: $LOG_FILE"
  fi
}
trap cleanup EXIT

msg() { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
die() { echo "FATAL: $*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this script with sudo or as root."
}

require_commands() {
  local missing=()
  local cmds=(apt-get dpkg apt-cache grep awk sed tee uname df findmnt lsmod modprobe)
  for c in "${cmds[@]}"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing required commands: ${missing[*]}"
}

read_os_info() {
  source /etc/os-release || die "Unable to read /etc/os-release"
  OS_ID="${ID:-unknown}"
  OS_NAME="${PRETTY_NAME:-unknown}"
  VERSION_CODENAME="${VERSION_CODENAME:-}"
  [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "pop" ]] || die "This script supports Pop!_OS / Ubuntu only. Detected: $OS_NAME"
}

check_disk_space() {
  # Require at least ~1.5 GiB free on /
  local avail_kb
  avail_kb="$(df --output=avail / | tail -n1 | tr -d ' ')"
  [[ "$avail_kb" =~ ^[0-9]+$ ]] || die "Unable to determine free disk space."
  if (( avail_kb < 1572864 )); then
    die "Less than 1.5 GiB free on /. Free some disk space first."
  fi
}

check_apt_health() {
  msg "Checking package manager health"
  export DEBIAN_FRONTEND=noninteractive

  if dpkg --audit | grep -q .; then
    dpkg --audit
    die "dpkg reports partially installed packages. Repair those first."
  fi

  if ! apt-get check >/dev/null 2>&1; then
    die "apt-get check failed. Repair APT state before continuing."
  fi

  if apt-mark showhold | grep -q .; then
    msg "Held packages detected:"
    apt-mark showhold || true
    msg "Continuing, but held packages can block dependency resolution."
  fi
}

collect_prechecks() {
  msg "Collecting pre-install diagnostics"
  {
    echo "==== HOST ===="
    hostnamectl || true
    echo

    echo "==== OS ===="
    cat /etc/os-release || true
    echo

    echo "==== KERNEL ===="
    uname -a
    echo

    echo "==== DISK ===="
    df -h /
    echo

    echo "==== GPU PCI DEVICES ===="
    lspci -nnk | grep -A3 -E 'VGA|3D|Display' || true
    echo

    echo "==== NVIDIA MODULES ===="
    lsmod | grep -E '^nvidia|^nouveau' || true
    echo

    echo "==== INSTALLED NVIDIA PACKAGES ===="
    dpkg-query -W -f='${binary:Package}\t${Version}\n' 'nvidia-*' 'libnvidia-*' 2>/dev/null | sort || true
    echo

    echo "==== RENDER OFFLOAD ENV ===="
    env | grep -E '__(NV|GLX|VK)_|^DRI_PRIME=' || true
    echo
  } | tee -a "$REPORT_FILE"

  if command -v nvidia-smi >/dev/null 2>&1; then
    {
      echo "==== NVIDIA-SMI (PRE) ===="
      nvidia-smi || true
      echo
    } | tee -a "$REPORT_FILE"
  fi

  if command -v glxinfo >/dev/null 2>&1; then
    {
      echo "==== GLXINFO -B (PRE) ===="
      glxinfo -B || true
      echo
    } | tee -a "$REPORT_FILE"
  fi

  if command -v vulkaninfo >/dev/null 2>&1; then
    {
      echo "==== VULKANINFO --SUMMARY (PRE) ===="
      vulkaninfo --summary || true
      echo
    } | tee -a "$REPORT_FILE"
  fi
}

build_package_list() {
  # Candidate packages chosen to improve OpenGL/EGL/GLX/Vulkan runtime coverage
  # and diagnostics, while keeping the installed NVIDIA driver branch intact.
  local candidates=(
    mesa-utils
    mesa-utils-bin
    mesa-vulkan-drivers
    vulkan-tools
    libvulkan1
    libegl1
    libegl-mesa0
    libgl1
    libgl1-mesa-dri
    libglx-mesa0
    libgles2
    libopengl0
    libnvidia-egl-wayland1
    clinfo
    pciutils
    inxi
  )

  AVAILABLE_PKGS=()
  SKIPPED_PKGS=()
  for pkg in "${candidates[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
      AVAILABLE_PKGS+=("$pkg")
    else
      SKIPPED_PKGS+=("$pkg")
    fi
  done

  [[ ${#AVAILABLE_PKGS[@]} -gt 0 ]] || die "No candidate packages were found in configured repositories."

  msg "Packages that will be considered for installation:"
  printf '  %s\n' "${AVAILABLE_PKGS[@]}"

  if [[ ${#SKIPPED_PKGS[@]} -gt 0 ]]; then
    msg "Packages not found in current repositories and skipped:"
    printf '  %s\n' "${SKIPPED_PKGS[@]}"
  fi
}

dry_run_install() {
  msg "Refreshing package indexes"
  apt-get update

  msg "Simulating installation"
  if ! apt-get -s install --no-install-recommends "${AVAILABLE_PKGS[@]}"; then
    die "APT simulation failed. No changes were made."
  fi
}

install_packages() {
  msg "Installing packages"
  apt-get install -y --no-install-recommends "${AVAILABLE_PKGS[@]}"
}

collect_postchecks() {
  msg "Running post-install checks"

  if ! apt-get check >/dev/null 2>&1; then
    die "Post-install apt-get check failed."
  fi

  ldconfig

  {
    echo "==== INSTALLED GRAPHICS/VULKAN PACKAGES (POST) ===="
    dpkg-query -W -f='${binary:Package}\t${Version}\n' \
      mesa-utils mesa-utils-bin mesa-vulkan-drivers vulkan-tools \
      libvulkan1 libegl1 libegl-mesa0 libgl1 libgl1-mesa-dri \
      libglx-mesa0 libgles2 libopengl0 libnvidia-egl-wayland1 \
      clinfo pciutils inxi 2>/dev/null | sort || true
    echo

    echo "==== NVIDIA MODULES (POST) ===="
    lsmod | grep -E '^nvidia|^nouveau' || true
    echo
  } | tee -a "$REPORT_FILE"

  if command -v nvidia-smi >/dev/null 2>&1; then
    {
      echo "==== NVIDIA-SMI (POST) ===="
      nvidia-smi || true
      echo
    } | tee -a "$REPORT_FILE"
  fi

  if command -v glxinfo >/dev/null 2>&1; then
    {
      echo "==== GLXINFO -B (POST) ===="
      glxinfo -B || true
      echo
    } | tee -a "$REPORT_FILE"
  fi

  if command -v vulkaninfo >/dev/null 2>&1; then
    {
      echo "==== VULKANINFO --SUMMARY (POST) ===="
      vulkaninfo --summary || true
      echo
    } | tee -a "$REPORT_FILE"
  fi

  {
    echo "==== QUICK GUIDANCE ===="
    echo "Blender:"
    echo "  - In Edit > Preferences > System, set Cycles Render Devices to CUDA or OptiX if available."
    echo "  - To test: blender --debug-gpu"
    echo
    echo "FreeCAD:"
    echo "  - It primarily depends on a healthy OpenGL stack."
    echo "  - To inspect the active renderer: glxinfo -B"
    echo
    echo "Wayland / hybrid render offload examples:"
    echo "  - __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia appname"
    echo "  - __VK_LAYER_NV_optimus=NVIDIA_only appname"
    echo
    echo "Reports:"
    echo "  - Log file:    $LOG_FILE"
    echo "  - Report file: $REPORT_FILE"
    echo
    echo "A reboot is usually not required for these user-space packages,"
    echo "but logging out/in can help Wayland and desktop sessions pick up new libraries."
  } | tee -a "$REPORT_FILE"
}

main() {
  require_root
  require_commands
  read_os_info
  check_disk_space
  check_apt_health

  msg "Starting safe graphics stack setup on $OS_NAME"
  collect_prechecks
  build_package_list
  dry_run_install
  install_packages
  collect_postchecks

  msg "Completed successfully"
  echo "Log:    $LOG_FILE"
  echo "Report: $REPORT_FILE"
}

main "$@"
