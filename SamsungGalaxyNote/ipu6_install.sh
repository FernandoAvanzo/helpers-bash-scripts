#!/usr/bin/env bash
# shellcheck disable=SC1091
# Build-and-install Intel IPU6 driver stack on Pop!_OS 22.04
# Tested on kernel 6.12.10 and Galaxy Book4 Ultra 2025-06-28
set -euo pipefail

# Configuration
IPU_VERSION="${IPU_VERSION:-$(date +%Y%m%d)}"
STACK_DIR="/opt/ipu6"
BACKUP_DIR="/opt/ipu6-bkp/ipu6-backup-$(date +%F-%H%M)"
IPU_FW_DIR="/lib/firmware/intel/ipu"
LOG_FILE="/var/log/ipu6-install.log"
HEALTH_CHECK_SCRIPT="/opt/ipu6/ipu6_health_check.sh"
REPOS=(
  "https://github.com/intel/ipu6-drivers.git"
  "https://github.com/intel/ipu6-camera-bins.git"
  "https://github.com/intel/ipu6-camera-hal.git"
  "https://github.com/intel/icamerasrc.git#icamerasrc_slim_api"
)

# Import required helpers
export PROJECTS=$HOME/Projects/
export HELPERS_BASH_SCRIPTS="/home/fernandoavanzo/Projects/helpers-bash-scripts"
export HELPERS="$HELPERS_BASH_SCRIPTS/BashLib/src/helpers"

# shellcheck source=./helpers/root-password.sh
source "$HELPERS"/root-password.sh

# Get the root password once at the beginning
password="$(getRootPassword)"

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
        echo "$password" | sudo -S rm -rf "$STACK_DIR" || true
    fi
    if [[ -d "/usr/src/ipu6-drivers-$IPU_VERSION" ]]; then
        echo "$password" | sudo -S dkms remove -m ipu6-drivers -v "$IPU_VERSION" --all || true
        echo "$password" | sudo -S rm -rf "/usr/src/ipu6-drivers-$IPU_VERSION" || true
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
    echo "$password" | sudo -S mkdir -p "$BACKUP_DIR"/{firmware,libs,dkms}
    
    # Backup firmware
    if [[ -d "$IPU_FW_DIR" ]]; then
        echo "$password" | sudo -S cp -a "$IPU_FW_DIR" "$BACKUP_DIR/firmware/" || true
        log "Firmware backed up"
    fi
    
    # Backup libraries
    echo "$password" | sudo -S find /usr/lib -name "libipu*" -exec cp -a {} "$BACKUP_DIR/libs/" \; 2>/dev/null || true
    echo "$password" | sudo -S find /usr/lib/gstreamer-1.0 -name "libicamerasrc*" -exec cp -a {} "$BACKUP_DIR/libs/" \; 2>/dev/null || true
    
    # Backup DKMS status
    echo "$password" | sudo -S sh -c "dkms status ipu6-drivers 2>/dev/null > '$BACKUP_DIR/dkms/status.txt'" || true
    log "System backup completed"
}

# Set up error handling
trap cleanup_on_error ERR

# Privilege check 
if [[ $EUID -eq 0 ]]; then
    die "Do not run as root. Run as regular user - sudo will be used with password authentication."
fi 

# Initialize logging with sudo
echo "$password" | sudo -S touch "$LOG_FILE"
echo "$password" | sudo -S chown "$(whoami):$(whoami)" "$LOG_FILE"

log "==> Starting IPU6 installation (version: $IPU_VERSION)"

log "==> Installing build dependencies"
echo "$password" | sudo -S apt update || die "Failed to update package list"
echo "$password" | sudo -S apt install -y dkms build-essential git cmake ninja-build meson \
  linux-headers-"$(uname -r)" \
  libexpat-dev automake libtool libdrm-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
  pkg-config || die "Failed to install dependencies"

log "==> Creating working directory ${STACK_DIR}"
echo "$password" | sudo -S mkdir -p "$STACK_DIR" || die "Failed to create working directory"
echo "$password" | sudo -S chown "$(whoami):$(whoami)" "$STACK_DIR" || die "Failed to change ownership of working directory"

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

##############################################################################
# 1. Kernel driver via DKMS
##############################################################################
log "==> Installing IPU6 kernel drivers via DKMS"
DRIVER_SRC="${STACK_DIR}/ipu6-drivers"

# Copy source to DKMS location
echo "$password" | sudo -S cp -a "$DRIVER_SRC" "/usr/src/ipu6-drivers-$IPU_VERSION" || die "Failed to copy driver source"

# Register with DKMS
echo "$password" | sudo -S dkms add -m ipu6-drivers -v "$IPU_VERSION" || die "DKMS add failed"
log "DKMS module registered"

# Build the module
echo "$password" | sudo -S dkms build -m ipu6-drivers -v "$IPU_VERSION" || die "DKMS build failed"
log "DKMS module built successfully"

# Install the module
echo "$password" | sudo -S dkms install -m ipu6-drivers -v "$IPU_VERSION" || die "DKMS install failed"
log "DKMS module installed successfully"

##############################################################################
# 2. Firmware + proprietary libs
##############################################################################
log "==> Installing IPU6 firmware and proprietary libraries"

# Verify firmware files exist
verify_firmware_files

# Create a firmware directory
echo "$password" | sudo -S mkdir -p "$IPU_FW_DIR" || die "Failed to create firmware directory"

# Install firmware files
log "Installing firmware files to $IPU_FW_DIR"
echo "$password" | sudo -S cp "${STACK_DIR}/ipu6-camera-bins/lib/firmware/intel/ipu/"*.bin "$IPU_FW_DIR/" || die "Failed to copy firmware files"

# Install proprietary libraries
log "Installing proprietary libraries"
pushd "${STACK_DIR}/ipu6-camera-bins/lib" >/dev/null || die "Failed to enter camera-bins lib directory"

# Create symlinks for libraries (required by HAL)
for lib in lib*.so.*; do 
    if [[ -f "$lib" ]]; then
        ln -sf "$lib" "${lib%.*}" || die "Failed to create symlink for $lib"
    fi
done

# Copy libraries to a system
echo "$password" | sudo -S cp -P lib* /usr/lib/ || die "Failed to copy libraries to /usr/lib"
log "Proprietary libraries installed"

popd >/dev/null

##############################################################################
# 3. Build & install user-space HAL
##############################################################################
log "==> Building and installing IPU6 Camera HAL"
cd "${STACK_DIR}/ipu6-camera-hal" || die "Failed to enter HAL directory"

# Create a build directory
mkdir -p build || die "Failed to create HAL build directory"
cd build || die "Failed to enter HAL build directory"

# Configure with CMake
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_CAMHAL_ADAPTOR=ON \
      -DBUILD_CAMHAL_PLUGIN=ON \
      -DIPU_VERSIONS="ipu6;ipu6ep;ipu6epmtl" \
      -DUSE_PG_LITE_PIPE=ON \
      .. || die "CMake configuration failed for HAL"

verify_cmake_build "."

# Build HAL
make -j"$(nproc)" || die "HAL build failed"
log "HAL built successfully"

# Install HAL
echo "$password" | sudo -S make install || die "HAL installation failed"
log "HAL installed successfully"

##############################################################################
# 4. Build & install icamerasrc (GStreamer plugin)
##############################################################################
log "==> Building and installing icamerasrc GStreamer plugin"
cd "${STACK_DIR}/icamerasrc" || die "Failed to enter icamerasrc directory"

# Set required environment variable
export CHROME_SLIM_CAMHAL=ON

# Generate configure script
./autogen.sh || die "autogen.sh failed for icamerasrc"

# Configure
./configure --prefix=/usr --enable-gstdrmformat=yes || die "Configure failed for icamerasrc"

# Build
make -j"$(nproc)" || die "icamerasrc build failed"
log "icamerasrc built successfully"

# Install
echo "$password" | sudo -S make install || die "icamerasrc installation failed"
log "icamerasrc installed successfully"

# Update library cache
echo "$password" | sudo -S ldconfig || die "ldconfig failed"
log "Library cache updated"

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
if command -v gst-launch-1.0 >/dev/null 2>&1; then
    timeout 5s gst-launch-1.0 icamerasrc num-buffers=10 ! fakesink || log "Camera test completed (or timed out - this is normal)"
else
    log "gst-launch-1.0 not available for testing"
fi
gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink
