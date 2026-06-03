#!/usr/bin/env bash
# fix-nvidia-dkms.sh – Remove incompatible NVIDIA DKMS module and install a kernel-compatible driver
# This script must be run with root privileges.  It will purge the existing NVIDIA 580 driver,
# reconfigure any half-installed kernel packages and then install the latest available driver.
set -euo pipefail

log() {
  printf '\n[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

log "Refreshing package lists..."
apt-get update

# Determine if the problematic driver is installed
if dpkg -l | grep -qE '^ii\s+nvidia-(driver|dkms)-580'; then
  log "Removing incompatible NVIDIA 580 driver packages..."
  apt-get -y purge 'nvidia-driver-580*' 'nvidia-dkms-580*' || true
fi

# Hold kernel packages if the user wants to stay on the current kernel (optional)
# Uncomment the next lines to hold the new kernel version and avoid automatic upgrades
# log "Holding new kernel packages to prevent reinstallation..."
# apt-mark hold linux-image-7.0.* linux-headers-7.0.*

log "Configuring any partially installed packages..."
dpkg --configure -a || true

log "Installing latest NVIDIA driver (if available)..."
# Replace nvidia-driver-595 with the version that supports Linux 7.x in your repo.
# This command will install both the driver and its DKMS module.
apt-get -y install nvidia-driver-595 || {
  log "No compatible NVIDIA driver found. Continuing without proprietary driver."
}

log "Reinstalling kernel headers to ensure dkms has sources..."
apt-get -y install --reinstall linux-headers-$(uname -r)

log "Running dkms autoinstall to build modules..."
dkms autoinstall || {
  log "DKMS autoinstall encountered errors. Review /var/lib/dkms/*/build/make.log for details."
  exit 1
}

log "Finished. Reboot the system to use the new kernel and driver."
exit 0
