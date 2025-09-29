
#!/usr/bin/env bash
set -euo pipefail

# ipu6_install_v47.sh
# Samsung Galaxy Book4 Ultra IPU6 webcam fix for Pop!_OS 22.04 + kernel 6.16.3
# Uses mainline kernel IPU6 drivers with compatible userspace on Noble (24.04)

MACHINE=ipu6-noble
ROOT=/var/lib/machines/${MACHINE}
LOG=/tmp/ipu6_install_v47.$(date +%Y%m%d-%H%M%S).log

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
die()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [FATAL] $*" | tee -a "$LOG" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# Check if we're root
[[ $EUID -eq 0 ]] || die "This script must be run as root: sudo $0"

# ---------- Host preflight ----------
bold "Host preflight checks…"
require_cmd systemd-nspawn
require_cmd debootstrap

KERNEL_VER=$(uname -r)
info "Running kernel: $KERNEL_VER"

# Check if IPU6 is detected
if lspci -nn | grep -q "0000:00:05.0.*Image"; then
  info "IPU6 device detected on PCI bus"
else
  die "IPU6 device not found - ensure Intel IPU6 is present"
fi

# Check cgroup v2
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
  info "cgroup v2 present"
else
  die "cgroup v2 required for systemd-nspawn. Add 'systemd.unified_cgroup_hierarchy=1' to kernel params"
fi

# Install host dependencies
info "Installing host dependencies…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >>"$LOG" 2>&1
apt-get install -y -qq \
  debootstrap systemd-container curl wget gpg ca-certificates \
  v4l-utils gstreamer1.0-tools linux-firmware >>"$LOG" 2>&1

# ---------- Container setup ----------
if [[ ! -d "$ROOT" || ! -f "$ROOT/etc/os-release" ]]; then
  bold "Creating Noble (24.04) rootfs…"
  debootstrap --include=systemd,dbus --arch=amd64 noble "$ROOT" \
    http://archive.ubuntu.com/ubuntu >>"$LOG" 2>&1 || die "debootstrap failed"

  # Set up basic container config
  systemd-machine-id-setup --root="$ROOT"
else
  info "Noble rootfs exists, reusing"
fi

# Container execution helper with proper networking and device access
nspawn_exec() {
  systemd-nspawn \
    -D "$ROOT" \
    --machine="$MACHINE" \
    --resolv-conf=copy-host \
    --register=no \
    --console=pipe \
    --bind=/dev/log \
    --capability=CAP_NET_ADMIN \
    --network-veth \
    --as-pid2 \
    /usr/bin/env bash -c "$*"
}

# Runtime execution with device binding
nspawn_cam() {
  local binds=()
  # Bind all video/media devices
  for dev in /dev/video* /dev/media* /dev/dri /dev/bus/usb; do
    [[ -e "$dev" ]] && binds+=( "--bind=${dev}" )
  done

  systemd-nspawn \
    -D "$ROOT" \
    --machine="$MACHINE" \
    --resolv-conf=copy-host \
    --register=no \
    --console=interactive \
    "${binds[@]}" \
    /usr/bin/env bash -c "$*"
}

bold "Setting up container APT sources…"

# Configure Noble sources
cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF

# Add Intel IPU6 PPA with proper key handling
info "Adding Intel IPU6 PPA…"
install -d "$ROOT/etc/apt/keyrings"
# Download and install the PPA key
nspawn_exec "apt-get update && apt-get install -y gnupg" >>"$LOG" 2>&1
nspawn_exec "gpg --keyserver keyserver.ubuntu.com --recv-keys A630CA96910990FF" >>"$LOG" 2>&1
nspawn_exec "gpg --export A630CA96910990FF | tee /etc/apt/keyrings/intel-ipu6.gpg" >>"$LOG" 2>&1

cat > "$ROOT/etc/apt/sources.list.d/intel-ipu6.list" <<'EOF'
deb [signed-by=/etc/apt/keyrings/intel-ipu6.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

bold "Installing IPU6 userspace in container…"
nspawn_exec "apt-get update" >>"$LOG" 2>&1 || die "APT update failed in container"

# Install compatible libcamera and IPU6 packages
nspawn_exec "DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ipu6-camera-bins ipu6-camera-hal \
  libcamera0.3 libcamera-tools libcamera-v4l2 \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-tools gstreamer1.0-libcamera \
  v4l-utils pipewire wireplumber" >>"$LOG" 2>&1 || die "Package installation failed"

# Create host wrapper scripts
install -d /usr/local/bin

# IPU6 shell wrapper
cat > /usr/local/bin/ipu6-shell <<'EOF'
#!/usr/bin/env bash
# Interactive shell in IPU6 container
ROOT="/var/lib/machines/ipu6-noble"
MACHINE="ipu6-noble"

binds=()
for dev in /dev/video* /dev/media* /dev/dri /dev/bus/usb; do
  [[ -e "$dev" ]] && binds+=( "--bind=${dev}" )
done

exec systemd-nspawn \
  -D "$ROOT" \
  --machine="$MACHINE" \
  --resolv-conf=copy-host \
  --register=no \
  --console=interactive \
  "${binds[@]}" \
  /bin/bash
EOF
chmod +x /usr/local/bin/ipu6-shell

# Camera test wrapper
cat > /usr/local/bin/ipu6-test <<'EOF'
#!/usr/bin/env bash
# Test IPU6 camera functionality
ROOT="/var/lib/machines/ipu6-noble"
MACHINE="ipu6-noble"

binds=()
for dev in /dev/video* /dev/media* /dev/dri /dev/bus/usb; do
  [[ -e "$dev" ]] && binds+=( "--bind=${dev}" )
done

echo "Testing libcamera detection..."
systemd-nspawn \
  -D "$ROOT" \
  --machine="$MACHINE" \
  --resolv-conf=copy-host \
  --register=no \
  --console=pipe \
  "${binds[@]}" \
  /usr/bin/cam --list

echo "Testing GStreamer pipeline..."
systemd-nspawn \
  -D "$ROOT" \
  --machine="$MACHINE" \
  --resolv-conf=copy-host \
  --register=no \
  --console=pipe \
  "${binds[@]}" \
  /usr/bin/gst-launch-1.0 libcamerasrc ! videoconvert ! fakesink -v
EOF
chmod +x /usr/local/bin/ipu6-test

# Libcamera GUI wrapper
cat > /usr/local/bin/ipu6-camera-gui <<'EOF'
#!/usr/bin/env bash
# GUI camera test (requires X11 forwarding)
ROOT="/var/lib/machines/ipu6-noble"
MACHINE="ipu6-noble"

binds=()
for dev in /dev/video* /dev/media* /dev/dri /dev/bus/usb; do
  [[ -e "$dev" ]] && binds+=( "--bind=${dev}" )
done

# Bind X11 socket for GUI
binds+=( "--bind=/tmp/.X11-unix" )
binds+=( "--setenv=DISPLAY=$DISPLAY" )

exec systemd-nspawn \
  -D "$ROOT" \
  --machine="$MACHINE" \
  --resolv-conf=copy-host \
  --register=no \
  --console=pipe \
  "${binds[@]}" \
  /usr/bin/libcamera-hello --qt-preview
EOF
chmod +x /usr/local/bin/ipu6-camera-gui

bold "Testing container setup…"
info "Verifying libcamera in container…"
if nspawn_exec "libcamera-hello --version" >>"$LOG" 2>&1; then
  info "libcamera installed successfully"
else
  echo "[WARN] libcamera version check failed - see $LOG"
fi

bold "Installation complete!"
echo
echo "Log: $LOG"
echo
echo "Usage:"
echo "  sudo ipu6-shell          # Interactive shell in container"
echo "  sudo ipu6-test           # Test camera functionality"
echo "  sudo ipu6-camera-gui     # GUI camera preview (needs X11)"
echo
echo "If camera doesn't work immediately:"
echo "1. Reboot to ensure all drivers are loaded"
echo "2. Check: lsmod | grep intel_ipu6"
echo "3. Run: sudo ipu6-test"
echo "4. For GUI apps: export DISPLAY=:0 && sudo ipu6-camera-gui"
