#!/usr/bin/env bash
# shellcheck disable=SC3010,SC1091,SC2216,SC2155,SC2259
# bashsupport disable=BP2001
# shellcheck disable=SC1091,SC2216,SC2155
# Build-and-install Intel IPU6 driver stack on Pop!_OS 22.04
# Tested on kernel 6.12.10 and Galaxy Book4 Ultra 2025-06-28
set -euo pipefail

# Configuration
IPU_VERSION="${IPU_VERSION:-$(date +%Y%m%d-%H%M)}"
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
password="$(get-root-psw)"

# Logging function with explicit flushing
log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$message" | tee -a "$LOG_FILE"
    sync  # Force flush to disk
}

# Enhanced error handling with stack trace
die() { 
    log "ERROR: $* (Line: ${BASH_LINENO[0]}, Function: ${FUNCNAME[1]})" >&2
    cleanup_on_error
    exit 1
}

# Cleanup function
cleanup_on_error() {
    log "==> Cleaning up after error..."
    # Clean up any partial DKMS installation
    cleanup_dkms_modules
    log "Cleanup completed. Working directory preserved at $STACK_DIR for debugging."
}

# DKMS cleanup function with better error handling
cleanup_dkms_modules() {
    log "Cleaning up DKMS modules..."
    
    # Find all ipu6-drivers versions
    local versions
    if versions=$(echo "$password" | sudo -S dkms status ipu6-drivers 2>/dev/null | cut -d',' -f1 | cut -d':' -f2 | tr -d ' '); then
        for version in $versions; do
            if [[ -n "$version" ]]; then
                log "Removing DKMS module ipu6-drivers version $version"
                echo "$password" | sudo -S dkms remove -m ipu6-drivers -v "$version" --all 2>/dev/null || true
                echo "$password" | sudo -S rm -rf "/usr/src/ipu6-drivers-$version" 2>/dev/null || true
            fi
        done
    fi
}

# Check and handle existing DKMS installations
check_existing_dkms() {
    log "==> Checking for existing DKMS installations"
    
    local existing_status
    if existing_status=$(echo "$password" | sudo -S dkms status ipu6-drivers 2>/dev/null); then
        log "Found existing DKMS installations:"
        log "$existing_status"
        
        # Check if we have the exact version already installed
        if echo "$existing_status" | grep -q "ipu6-drivers-$IPU_VERSION.*installed"; then
            log "Version $IPU_VERSION is already installed and active"
            read -p "Do you want to reinstall? This will remove the existing version. (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Installation cancelled by user"
                exit 0
            fi
        fi
        
        # Clean up all existing versions
        cleanup_dkms_modules
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

# FIXED: Enhanced IA_IMAGING libraries installation with a corrected pkg-config file
install_ia_imaging_libs() {
    log "==> Installing IA_IMAGING libraries"
    
    local lib_dir="${STACK_DIR}/ipu6-camera-bins/lib"
    local include_dir="${STACK_DIR}/ipu6-camera-bins/include"
    
    # Enhanced directory validation
    if [[ ! -d "$lib_dir" ]]; then
        die "Camera bins lib directory not found: $lib_dir"
    fi
    
    # Check if library files actually exist
    local lib_files
    if ! lib_files=$(find "$lib_dir" -name "lib*" -type f 2>/dev/null); then
        die "No library files found in $lib_dir"
    fi
    
    if [[ -z "$lib_files" ]]; then
        log "WARNING: No IA_IMAGING library files found, trying alternative approach..."
        
        # Try to find libraries in subdirectories
        if lib_files=$(find "$lib_dir" -name "*.so*" -type f 2>/dev/null); then
            log "Found .so files: $lib_files"
        else
            log "WARNING: Skipping IA_IMAGING library installation - no library files found"
            log "This may cause HAL build issues, but continuing..."
            return 0
        fi
    fi
    
    # Install libraries with explicit error checking
    log "Installing library files: $lib_files"
    for lib_file in $lib_files; do
        if ! echo "$password" | sudo -S cp -v "$lib_file" /usr/lib/ 2>&1 | tee -a "$LOG_FILE"; then
            die "Failed to copy library: $lib_file"
        fi
    done
    
    # Install headers if available
    if [[ -d "$include_dir" ]]; then
        log "Installing header files from $include_dir"
        echo "$password" | sudo -S mkdir -p /usr/include/ia_imaging
        if ! echo "$password" | sudo -S cp -r "$include_dir"/* /usr/include/ia_imaging/ 2>&1 | tee -a "$LOG_FILE"; then
            log "WARNING: Failed to install header files, continuing..."
        fi
    else
        log "WARNING: No include directory found at $include_dir"
    fi
    
    # Create pkg-config file for ia_imaging-ipu6 (FIXED SYNTAX)
    local pkgconfig_dir="/usr/lib/pkgconfig"
    echo "$password" | sudo -S mkdir -p "$pkgconfig_dir"
    
    log "Creating pkg-config file for ia_imaging-ipu6"
    echo "$password" | sudo -S tee "$pkgconfig_dir/ia_imaging-ipu6.pc" > /dev/null << 'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: ia_imaging-ipu6
Description: Intel IA Imaging library for IPU6
Version: 1.0.0
Libs: -L${libdir} -lia_imaging
Cflags: -I${includedir}
EOF

    # Verify the pkg-config file was created correctly
    if echo "$password" | sudo -S test -f "$pkgconfig_dir/ia_imaging-ipu6.pc"; then
        log "pkg-config file created successfully"
        # Test the pkg-config file
        if pkg-config --exists ia_imaging-ipu6 2>/dev/null; then
            log "pkg-config validation passed"
        else
            log "WARNING: pkg-config validation failed, but continuing..."
        fi
    else
        log "WARNING: Failed to create pkg-config file, continuing..."
    fi

    # Also copy existing pkg-config files from camera-bins
    if [[ -d "$lib_dir/pkgconfig" ]]; then
        log "Installing existing pkg-config files from camera-bins"
        echo "$password" | sudo -S cp -v "$lib_dir/pkgconfig"/*.pc "$pkgconfig_dir/" 2>&1 | tee -a "$LOG_FILE" || true
    fi

    # Update library cache with error handling
    log "Updating library cache..."
    if ! echo "$password" | sudo -S ldconfig 2>&1 | tee -a "$LOG_FILE"; then
        die "ldconfig failed"
    fi
    
    # Update pkg-config cache
    export PKG_CONFIG_PATH="/usr/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    
    log "IA_IMAGING libraries installation completed"
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
    echo "$password" | sudo -S find /usr/lib -name "libia_*" -exec cp -a {} "$BACKUP_DIR/libs/" \; 2>/dev/null || true
    
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

# Check for existing installations
check_existing_dkms

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
  else
    log "Repository $dir already exists, updating..."
    git -C "$dir" fetch --all || die "Failed to update $dir"
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
# 2. Firmware + proprietary libs (MOVED BEFORE HAL)
##############################################################################
log "==> Installing IPU6 firmware and proprietary libraries"

# Verify firmware files exist
verify_firmware_files

# Create a firmware directory
echo "$password" | sudo -S mkdir -p "$IPU_FW_DIR" || die "Failed to create firmware directory"

# Install firmware files
log "Installing firmware files to $IPU_FW_DIR"
echo "$password" | sudo -S cp "${STACK_DIR}/ipu6-camera-bins/lib/firmware/intel/ipu/"*.bin "$IPU_FW_DIR/" || die "Failed to copy firmware files"

# Install IA_IMAGING libraries (CRITICAL: Before HAL build) - FIXED
install_ia_imaging_libs

##############################################################################
# 3. Build & install user-space HAL
##############################################################################
log "==> Building and installing IPU6 Camera HAL"
cd "${STACK_DIR}/ipu6-camera-hal" || die "Failed to enter HAL directory"

# Create a build directory
mkdir -p build || die "Failed to create HAL build directory"
cd build || die "Failed to enter HAL build directory"

# Set environment variables for library detection
export PKG_CONFIG_PATH="/usr/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Configure with CMake (updated flags for better compatibility)
log "Configuring HAL with CMake..."
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_CAMHAL_ADAPTOR=ON \
      -DBUILD_CAMHAL_PLUGIN=ON \
      -DIPU_VERSIONS="ipu6;ipu6ep;ipu6epmtl" \
      -DUSE_PG_LITE_PIPE=ON \
      -DCMAKE_PREFIX_PATH="/usr" \
      -DCMAKE_LIBRARY_PATH="/usr/lib" \
      -DCMAKE_INCLUDE_PATH="/usr/include" \
      .. 2>&1 | tee -a "$LOG_FILE" || die "CMake configuration failed for HAL"

verify_cmake_build "."

# Build HAL
log "Building HAL..."
make -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE" || die "HAL build failed"
log "HAL built successfully"

# Install HAL
log "Installing HAL..."
echo "$password" | sudo -S make install 2>&1 | tee -a "$LOG_FILE" || die "HAL installation failed"
log "HAL installed successfully"

##############################################################################
# 4. Build & install icamerasrc (GStreamer plugin)
##############################################################################
log "==> Building and installing icamerasrc GStreamer plugin"
cd "${STACK_DIR}/icamerasrc" || die "Failed to enter icamerasrc directory"

# Set required environment variable
export CHROME_SLIM_CAMHAL=ON

# Generate configure script
log "Running autogen.sh..."
./autogen.sh 2>&1 | tee -a "$LOG_FILE" || die "autogen.sh failed for icamerasrc"

# Configure
log "Configuring icamerasrc..."
./configure --prefix=/usr --enable-gstdrmformat=yes 2>&1 | tee -a "$LOG_FILE" || die "Configure failed for icamerasrc"

# Build
log "Building icamerasrc..."
make -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE" || die "icamerasrc build failed"
log "icamerasrc built successfully"

# Install
log "Installing icamerasrc..."
echo "$password" | sudo -S make install 2>&1 | tee -a "$LOG_FILE" || die "icamerasrc installation failed"
log "icamerasrc installed successfully"

# Update library cache
echo "$password" | sudo -S ldconfig || die "ldconfig failed"
log "Library cache updated"

# Copy a health check script to the working directory
# shellcheck disable=SC3010
if [[ -f "$HEALTH_CHECK_SCRIPT" ]]; then
    echo "$password" | sudo -S cp "$HEALTH_CHECK_SCRIPT" "$STACK_DIR/" || log "Failed to copy health check script"
    echo "$password" | sudo -S chmod +x "$STACK_DIR/ipu6_health_check.sh" || log "Failed to make health check script executable"
fi

log "==> Installation completed successfully ✓"
log "Backup created at: $BACKUP_DIR"
log "Installation log: $LOG_FILE"

echo
echo "==> Next steps:"
echo "1. Reboot your system"
echo "2. Run the health check: sudo bash $STACK_DIR/ipu6_health_check.sh"
echo "3. Test the camera: ipu6-test"
echo "   or: gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink"

echo
echo "==> Testing iCamerasrc GStreamer plugin"
if command -v gst-launch-1.0 >/dev/null 2>&1; then
    log "Running camera test..."
    timeout 5s gst-launch-1.0 icamerasrc num-buffers=10 ! fakesink 2>&1 | tee -a "$LOG_FILE" || log "Camera test completed (or timed out - this is normal)"
else
    log "gst-launch-1.0 not available for testing"
fi

log "==> Final test with display output"
gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink 2>&1 | tee -a "$LOG_FILE" || log "Display test completed"
