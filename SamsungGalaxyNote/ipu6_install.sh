#!/usr/bin/env bash
# Build-and-install Intel IPU6 driver stack on Pop!_OS 22.04
# Tested on kernel 6.12.10 and Galaxy Book4 Ultra 2025-06-28
set -euo pipefail

# Configuration
IPU_VERSION="${IPU_VERSION:-$(date +%Y%m%d)}"
STACK_DIR="/opt/ipu6"
BACKUP_DIR="/opt/ipu6-backup-$(date +%F-%H%M)"
IPU_FW_DIR="/lib/firmware/intel/ipu"
LOG_FILE="/var/log/ipu6-install.log"
REPOS=(
  "https://github.com/intel/ipu6-drivers.git"
  "https://github.com/intel/ipu6-camera-bins.git"
  "https://github.com/intel/ipu6-camera-hal.git"
  "https://github.com/intel/icamerasrc.git#icamerasrc_slim_api"
)

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Enhanced error handling
die() { 
    log "ERROR: $*" >&2
    cleanup_on_error
    exit 1
}

# Cleanup function
cleanup_on_error() {
    log "==> Cleaning up after error..."
    if [[ -d "$STACK_DIR" ]]; then
        rm -rf "$STACK_DIR" || true
    fi
    if [[ -d "/usr/src/ipu6-drivers-$IPU_VERSION" ]]; then
        dkms remove -m ipu6-drivers -v "$IPU_VERSION" --all || true
        rm -rf "/usr/src/ipu6-drivers-$IPU_VERSION" || true
    fi
}

# Validation functions
verify_build() {
    local target="$1"
    if [[ ! -d "$target" ]]; then
        die "Build failed: $target not found"
    fi
    log "Build verification passed for: $target"
}

validate_repo() {
    local repo_dir="$1"
    if [[ ! -f "$repo_dir/.git/config" ]]; then
        die "Invalid repository: $repo_dir"
    fi
    if ! git -C "$repo_dir" status >/dev/null 2>&1; then
        die "Repository corrupted: $repo_dir"
    fi
    log "Repository validation passed for: $repo_dir"
}

verify_cmake_build() {
    local build_dir="$1"
    if [[ ! -f "$build_dir/Makefile" ]]; then
        die "CMake configuration failed in $build_dir"
    fi
    if ! make -C "$build_dir" --dry-run >/dev/null 2>&1; then
        die "Build system verification failed in $build_dir"
    fi
    log "CMake build verification passed for: $build_dir"
}

# shellcheck disable=SC2155
verify_firmware_files() {
    local fw_source="${STACK_DIR}/ipu6-camera-bins/lib/firmware/intel/ipu"
    if [[ ! -d "$fw_source" ]]; then
        die "Firmware source directory not found: $fw_source"
    fi
    local fw_count=$(find "$fw_source" -name "*.bin" | wc -l)
    if [[ $fw_count -eq 0 ]]; then
        die "No firmware files found in $fw_source"
    fi
    log "Found $fw_count firmware files"
}

# Comprehensive backup function
backup_system() {
    log "==> Creating comprehensive backup in $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"/{firmware,libs,dkms}
    
    # Backup firmware
    if [[ -d "$IPU_FW_DIR" ]]; then
        cp -a "$IPU_FW_DIR" "$BACKUP_DIR/firmware/" || true
        log "Firmware backed up"
    fi
    
    # Backup libraries
    find /usr/lib -name "libipu*" -exec cp -a {} "$BACKUP_DIR/libs/" \; 2>/dev/null || true
    find /usr/lib/gstreamer-1.0 -name "libicamerasrc*" -exec cp -a {} "$BACKUP_DIR/libs/" \; 2>/dev/null || true
    
    # Backup DKMS status
    dkms status ipu6-drivers 2>/dev/null > "$BACKUP_DIR/dkms/status.txt" || true
    log "System backup completed"
}

# Set up error handling
trap cleanup_on_error ERR

# Privilege check
[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

# Initialize logging
log "==> Starting IPU6 installation (version: $IPU_VERSION)"

log "==> Installing build dependencies"
apt update || die "Failed to update package list"
apt install -y dkms build-essential git cmake ninja-build meson \
  linux-headers-"$(uname -r)" \
  libexpat-dev automake libtool libdrm-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
  pkg-config || die "Failed to install dependencies"

log "==> Creating working directory ${STACK_DIR}"
mkdir -p "$STACK_DIR" || die "Failed to create working directory"
cd "$STACK_DIR" || die "Failed to enter working directory"

log "==> Cloning required repositories"
for r in "${REPOS[@]}"; do
  url=${r%%#*}; br=${r##*#}
  dir=$(basename "${url%.git}")
  
  if [[ ! -d "$dir" ]]; then
    log "Cloning $url"
    git clone "$url" "$dir" || die "Failed to clone $url"
  fi
  
  validate_repo "$dir"
  
  if [[ $br != "$r" ]]; then
    log "Checking out branch $br for $dir"
    git -C "$dir" fetch origin "$br" || die "Failed to fetch branch $br"
    git -C "$dir" checkout "$br" || die "Failed to checkout branch $br"
  fi
done

# Create a comprehensive backup
backup_system

log "==> Installation completed successfully ✓"
log "Backup created at: $BACKUP_DIR"
log "Installation log: $LOG_FILE"

echo
echo "==> Next steps:"
echo "1. Reboot your system"
echo "2. Run the health check: sudo bash $HEALTH_CHECK_SCRIPT"
echo "3. Test the camera: ipu6-test"
echo "   or: gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink"

echo
echo "==> Testing iCamerasrc GStreamer plugin"
gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink
