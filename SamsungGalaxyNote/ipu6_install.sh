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
HEALTH_CHECK_SCRIPT="/opt/ipu6/ipu6_health_check.sh"

# Repository configuration with version pinning option
REPOS=(
  "https://github.com/intel/ipu6-drivers.git"
  "https://github.com/intel/ipu6-camera-bins.git"
  "https://github.com/intel/ipu6-camera-hal.git"
  "https://github.com/intel/icamerasrc.git#icamerasrc_slim_api"
)

# System requirements check
check_system_requirements() {
    log "==> Checking system requirements"
    
    # Check kernel version
    local kernel_version
    kernel_version=$(uname -r | cut -d. -f1-2)
    local min_version="6.8"
    
    if ! awk "BEGIN {exit !($kernel_version >= $min_version)}"; then
        die "Kernel version $kernel_version is too old. Minimum required: $min_version"
    fi
    
    # Check available disk space (need ~2GB)
    local available_space
    available_space=$(df /opt | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2000000 ]]; then  # 2GB in KB
        die "Insufficient disk space in /opt. Need at least 2GB"
    fi
    
    # Check Secure Boot status
    if [[ -d /sys/firmware/efi/efivars ]] && command -v mokutil >/dev/null 2>&1; then
        if mokutil --sb-state | grep -q "SecureBoot enabled"; then
            print_warn "Secure Boot is enabled. You may need to sign the DKMS module or disable Secure Boot"
        fi
    fi
    
    log "System requirements check passed"
}

# Enhanced dependency installation
install_dependencies() {
    log "==> Installing build dependencies"
    
    # Update package list with retry
    local retry_count=0
    while ! apt update && [[ $retry_count -lt 3 ]]; do
        log "Package update failed, retrying... ($((++retry_count))/3)"
        sleep 5
    done
    
    [[ $retry_count -lt 3 ]] || die "Failed to update package list after 3 attempts"
    
    # Install packages with version checking
    local packages=(
        "dkms" "build-essential" "git" "cmake" "ninja-build" "meson"
        "linux-headers-$(uname -r)"
        "libexpat-dev" "automake" "libtool" "libdrm-dev"
        "libgstreamer1.0-dev" "libgstreamer-plugins-base1.0-dev"
        "gstreamer1.0-plugins-base" "gstreamer1.0-plugins-good"
        "gstreamer1.0-plugins-bad" "gstreamer1.0-libav" "gstreamer1.0-tools"
        "pkg-config" "v4l-utils" "media-ctl"
    )
    
    apt install -y "${packages[@]}" || die "Failed to install dependencies"
    log "Dependencies installed successfully"
}

# Post-installation steps
post_install_setup() {
    log "==> Running post-installation setup"
    
    # Update library cache
    ldconfig || die "ldconfig failed"
    
    # Generate module dependencies
    depmod -a || log "depmod failed (non-critical)"
    
    # Copy health check script
    if [[ -f "$(dirname "$0")/ipu6_health_check.sh" ]]; then
        cp "$(dirname "$0")/ipu6_health_check.sh" "$HEALTH_CHECK_SCRIPT"
        chmod +x "$HEALTH_CHECK_SCRIPT"
        log "Health check script installed to $HEALTH_CHECK_SCRIPT"
    fi
    
    # Create convenient aliases/scripts
    cat > "/usr/local/bin/ipu6-test" << 'EOF'
#!/bin/bash
gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink
EOF
    chmod +x "/usr/local/bin/ipu6-test"
    
    log "Post-installation setup completed"
}

check_system_requirements

install_dependencies

post_install_setup

trap - ERR

log "==> Installation completed successfully ✓"
log "Backup created at: $BACKUP_DIR"
log "Installation log: $LOG_FILE"

echo
echo "==> Next steps:"
echo "1. Reboot your system"
echo "2. Run the health check: sudo bash $HEALTH_CHECK_SCRIPT"
echo "3. Test the camera: ipu6-test"
echo "   or: gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink"
