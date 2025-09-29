#!/bin/bash
# Explicitly use bash to avoid dash compatibility issues
set -euo pipefail

# ipu6_install_v48.sh
# Fixed version addressing shell compatibility and systemd-nspawn container setup
# for Samsung Galaxy Book4 Ultra IPU6 webcam on Pop!_OS 22.04

MACHINE=ipu6-noble
ROOT=/var/lib/machines/${MACHINE}
LOG=/tmp/ipu6_install_v48.$(date +%Y%m%d-%H%M%S).log

# Color output functions
bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG"; }
die()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [FATAL] $*" | tee -a "$LOG" >&2; exit 1; }

# Ensure we're running as root
if [[ $EUID -ne 0 ]]; then
  die "This script must be run as root: sudo $0"
fi

# Detect current user for later use
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo 0)

bold "Samsung Galaxy Book4 Ultra IPU6 Webcam Fix v48"
info "Real user: $REAL_USER (UID: $REAL_UID)"
info "Kernel: $(uname -r)"

# ---------- Host Prerequisites ----------
bold "Checking host prerequisites..."

# Check if IPU6 hardware is present
if ! lspci -nn | grep -q "Image.*Processing.*Unit"; then
  warn "IPU6 device not detected in lspci output"
  info "Continuing anyway - device might be present but not visible"
fi

# Install essential host packages
info "Installing host dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >>"$LOG" 2>&1
apt-get install -y -qq \
  debootstrap systemd-container curl wget gpg ca-certificates \
  dbus-x11 v4l-utils linux-firmware >>"$LOG" 2>&1

# Ensure cgroup v2 is available
if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
  die "cgroup v2 required. Add 'systemd.unified_cgroup_hierarchy=1' to kernel parameters"
fi
info "cgroup v2 detected"

# ---------- Container Creation ----------
if [[ ! -d "$ROOT" || ! -f "$ROOT/etc/os-release" ]]; then
  bold "Creating Ubuntu Noble (24.04) container..."

  # Create container with systemd support
  debootstrap --include=systemd,dbus,sudo --arch=amd64 noble "$ROOT" \
    http://archive.ubuntu.com/ubuntu >>"$LOG" 2>&1 || die "debootstrap failed"

  # Generate machine ID for systemd
  systemd-machine-id-setup --root="$ROOT"

  # Set up basic networking in container
  cat > "$ROOT/etc/systemd/resolved.conf" <<'EOF'
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=8.8.4.4 1.0.0.1
EOF

else
  info "Noble container exists, reusing"
fi

# ---------- Container Execution Helpers ----------

# Basic execution (no device access, for setup)
nspawn_setup() {
  systemd-nspawn \
    --directory="$ROOT" \
    --machine="$MACHINE" \
    --resolv-conf=copy-host \
    --register=no \
    --console=pipe \
    --setenv=DEBIAN_FRONTEND=noninteractive \
    --capability=CAP_NET_ADMIN \
    bash -c "$*"
}

# Runtime execution with full device access
nspawn_runtime() {
  local binds=()

  # Bind all video/media devices
  for dev in /dev/video* /dev/media* /dev/dri; do
    [[ -e "$dev" ]] && binds+=( "--bind=$dev" )
  done

  # Bind essential system directories
  binds+=( "--bind=/sys/bus/pci" )
  binds+=( "--bind=/sys/devices" )
  binds+=( "--bind=/proc/bus/pci" )

  # Bind X11 socket for GUI applications
  if [[ -S /tmp/.X11-unix/X0 ]]; then
    binds+=( "--bind=/tmp/.X11-unix" )
  fi

  systemd-nspawn \
    --directory="$ROOT" \
    --machine="$MACHINE" \
    --resolv-conf=copy-host \
    --register=no \
    --console=interactive \
    --setenv=DISPLAY="${DISPLAY:-:0}" \
    --setenv=XDG_RUNTIME_DIR="/tmp" \
    --capability=CAP_NET_ADMIN \
    --capability=CAP_SYS_ADMIN \
    "${binds[@]}" \
    bash -c "$*"
}

# ---------- Container Software Setup ----------
bold "Configuring container software repositories..."

# Set up Noble repositories
cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF

# Install base packages
info "Installing base packages in container..."
nspawn_setup "apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl wget gnupg2 software-properties-common \
  systemd dbus sudo" >>"$LOG" 2>&1 || die "Base package installation failed"

# Add Intel IPU6 PPA
info "Adding Intel IPU6 PPA..."
nspawn_setup "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A630CA96910990FF" >>"$LOG" 2>&1

cat > "$ROOT/etc/apt/sources.list.d/intel-ipu6.list" <<'EOF'
deb [trusted=yes] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

# Update package lists
nspawn_setup "apt-get update" >>"$LOG" 2>&1 || die "APT update failed in container"

# Install IPU6 userspace packages
bold "Installing IPU6 userspace in container..."
nspawn_setup "apt-get install -y --no-install-recommends \
  ipu6-camera-bins ipu6-camera-hal \
  libcamera0.3 libcamera-tools libcamera-apps \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-tools gstreamer1.0-libcamera \
  v4l-utils mesa-utils" >>"$LOG" 2>&1 || die "IPU6 package installation failed"

# ---------- Host Integration Scripts ----------
bold "Creating host integration scripts..."

# Main camera test script
cat > /usr/local/bin/ipu6-test <<EOF
#!/bin/bash
set -euo pipefail

echo "=== IPU6 Camera Test ==="
echo "Kernel: \$(uname -r)"
echo "IPU6 modules loaded:"
lsmod | grep intel_ipu6 || echo "No intel_ipu6 modules found"
echo

echo "Available video devices:"
ls -la /dev/video* 2>/dev/null || echo "No video devices found"
echo

echo "Testing libcamera in container..."
systemd-nspawn \\
  --directory="$ROOT" \\
  --machine="$MACHINE" \\
  --resolv-conf=copy-host \\
  --register=no \\
  --console=pipe \\
  --bind=/dev/video0 --bind=/dev/video1 --bind=/dev/video2 --bind=/dev/video3 \\
  --bind=/dev/media0 --bind=/dev/dri \\
  bash -c "libcamera-hello --list-cameras; echo 'Exit code: \$?'"
EOF
chmod +x /usr/local/bin/ipu6-test

# Interactive shell script
cat > /usr/local/bin/ipu6-shell <<EOF
#!/bin/bash
set -euo pipefail

echo "Starting IPU6 container shell..."
echo "Try: libcamera-hello --list-cameras"
echo "Or: v4l2-ctl --list-devices"
echo

exec systemd-nspawn \\
  --directory="$ROOT" \\
  --machine="$MACHINE" \\
  --resolv-conf=copy-host \\
  --register=no \\
  --console=interactive \\
  --bind=/dev/video0 --bind=/dev/video1 --bind=/dev/video2 --bind=/dev/video3 \\
  --bind=/dev/media0 --bind=/dev/dri \\
  --setenv=PS1="[ipu6-container] \\$ " \\
  bash
EOF
chmod +x /usr/local/bin/ipu6-shell

# GUI camera application
cat > /usr/local/bin/ipu6-camera <<EOF
#!/bin/bash
set -euo pipefail

# Ensure X11 is available
if [[ -z "\${DISPLAY:-}" ]]; then
  export DISPLAY=:0
fi

echo "Starting camera preview in container..."
exec systemd-nspawn \\
  --directory="$ROOT" \\
  --machine="$MACHINE" \\
  --resolv-conf=copy-host \\
  --register=no \\
  --console=pipe \\
  --bind=/dev/video0 --bind=/dev/video1 --bind=/dev/video2 --bind=/dev/video3 \\
  --bind=/dev/media0 --bind=/dev/dri \\
  --bind=/tmp/.X11-unix \\
  --setenv=DISPLAY="\$DISPLAY" \\
  bash -c "libcamera-hello --qt-preview --timeout=0"
EOF
chmod +x /usr/local/bin/ipu6-camera

# V4L2 compatibility layer setup
cat > /usr/local/bin/ipu6-v4l2-setup <<EOF
#!/bin/bash
set -euo pipefail

echo "Setting up V4L2 compatibility layer..."

# Load v4l2loopback module
modprobe v4l2loopback devices=1 video_nr=20 card_label="IPU6 Virtual Camera" exclusive_caps=0 || {
  echo "Failed to load v4l2loopback - installing..."
  apt-get update && apt-get install -y v4l2loopback-dkms
  modprobe v4l2loopback devices=1 video_nr=20 card_label="IPU6 Virtual Camera" exclusive_caps=0
}

echo "Virtual camera created at /dev/video20"
echo "Use 'ipu6-v4l2-stream' to start streaming to it"
EOF
chmod +x /usr/local/bin/ipu6-v4l2-setup

# V4L2 streaming script
cat > /usr/local/bin/ipu6-v4l2-stream <<EOF
#!/bin/bash
set -euo pipefail

echo "Starting IPU6 -> V4L2 loopback streaming..."
echo "This will make the camera available as /dev/video20 for legacy applications"

exec systemd-nspawn \\
  --directory="$ROOT" \\
  --machine="$MACHINE" \\
  --resolv-conf=copy-host \\
  --register=no \\
  --console=pipe \\
  --bind=/dev/video0 --bind=/dev/video1 --bind=/dev/video2 --bind=/dev/video3 \\
  --bind=/dev/video20 --bind=/dev/media0 --bind=/dev/dri \\
  bash -c "gst-launch-1.0 -v libcamerasrc ! videoconvert ! v4l2sink device=/dev/video20"
EOF
chmod +x /usr/local/bin/ipu6-v4l2-stream

# ---------- Final Setup ----------
bold "Performing final setup..."

# Test container connectivity
info "Testing container setup..."
if nspawn_setup "libcamera-hello --version" >>"$LOG" 2>&1; then
  info "Container setup successful"
else
  warn "Container test failed - check $LOG"
fi

# Set permissions for regular user access
if [[ "$REAL_USER" != "root" ]] && id "$REAL_USER" >/dev/null 2>&1; then
  usermod -aG video "$REAL_USER" 2>/dev/null || true
  info "Added $REAL_USER to video group"
fi

# Create desktop file for easy access
if [[ "$REAL_USER" != "root" ]] && [[ -d "/home/$REAL_USER" ]]; then
  DESKTOP_DIR="/home/$REAL_USER/Desktop"
  if [[ -d "$DESKTOP_DIR" ]]; then
    cat > "$DESKTOP_DIR/IPU6 Camera.desktop" <<EOF
[Desktop Entry]
Name=IPU6 Camera
Comment=Samsung Galaxy Book4 Ultra Camera
Icon=camera-web
Exec=sudo /usr/local/bin/ipu6-camera
Type=Application
Categories=AudioVideo;Photography;
EOF
    chmod +x "$DESKTOP_DIR/IPU6 Camera.desktop"
    chown "$REAL_USER:$(id -gn "$REAL_USER")" "$DESKTOP_DIR/IPU6 Camera.desktop" 2>/dev/null || true
    info "Created desktop shortcut"
  fi
fi

bold "Installation Complete!"
echo
echo "Log file: $LOG"
echo
echo "Available commands:"
echo "  sudo ipu6-test           # Test camera detection and basic functionality"
echo "  sudo ipu6-shell          # Interactive shell in container"
echo "  sudo ipu6-camera         # GUI camera preview"
echo "  sudo ipu6-v4l2-setup     # Set up V4L2 compatibility layer"
echo "  sudo ipu6-v4l2-stream    # Stream to /dev/video20 for legacy apps"
echo
echo "Quick test: sudo ipu6-test"
echo "GUI test:   sudo ipu6-camera"
echo
echo "For browser/app compatibility:"
echo "1. Run: sudo ipu6-v4l2-setup"
echo "2. Run: sudo ipu6-v4l2-stream (keep running)"
echo "3. Select 'IPU6 Virtual Camera' in your application"
