#!/usr/bin/env bash
set -euo pipefail

say(){ echo -e "[ipu6_install_v9] $*"; }

# 0) Pre-reqs
say "Preflight…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  apt-transport-https ca-certificates curl wget software-properties-common \
  v4l-utils gstreamer1.0-tools

# 1) Add Intel IPU6 OEM PPA (Jammy) – contains libcamhal, icamerasrc, v4l2-relayd
if ! apt-cache policy | grep -q "oem-solutions-group/intel-ipu6"; then
  say "Adding PPA: ppa:oem-solutions-group/intel-ipu6"
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6
  apt-get update -y
fi

# 2) Try to ensure kernel side is available (but do NOT hard-fail here)
KVER="$(uname -r)"
say "Kernel: $KVER"

try_modprobe(){
  for m in intel_ipu6 intel_ipu6_isys intel_ipu6_psys; do
    if modinfo "$m" >/dev/null 2>&1; then
      modprobe "$m" || true
    fi
  done
}
try_modprobe

kernel_ready=false
if lsmod | grep -qE '(^|_)intel_ipu6(_|$)'; then
  kernel_ready=true
elif [ -d /sys/bus/pci/drivers/intel-ipu6 ] && ls /sys/bus/pci/drivers/intel-ipu6 | grep -qE '0000:'; then
  kernel_ready=true
elif dmesg | grep -qi 'intel-ipu6'; then
  kernel_ready=true
fi

if ! $kernel_ready; then
  say "WARNING: Could not prove intel-ipu6 is loaded yet. Continuing anyway (built-in drivers don't show in lsmod)."
fi

# 3) Userspace pieces: libcamera + GStreamer + HAL + bridge
say "Installing userspace (libcamera, HAL, v4l2loopback, v4l2-relayd)…"
# libcamera (tools include libcamera-hello)
apt-get install -y libcamera-tools gstreamer1.0-libcamera || true

# Intel HAL & icamerasrc from IPU6 PPA (names as shipped in the OEM PPA)
apt-get install -y libcamhal0 libcamhal-ipu6ep0 gstreamer1.0-icamera || true

# Bridge: v4l2loopback + relayd + PipeWire SPA libcamera
apt-get install -y v4l2loopback-dkms v4l2loopback-utils v4l2-relayd libspa-0.2-libcamera || true

# 4) Make v4l2loopback persistent and sane
say "Configuring v4l2loopback…"
install -Dm0644 /dev/stdin /etc/modprobe.d/v4l2loopback.conf <<'EOF'
options v4l2loopback exclusive_caps=1 card_label="Virtual Camera" video_nr=10
EOF
install -Dm0644 /dev/stdin /etc/modules-load.d/v4l2loopback.conf <<'EOF'
v4l2loopback
EOF

# (re)load module with new options
if lsmod | grep -q v4l2loopback; then rmmod v4l2loopback || true; fi
modprobe v4l2loopback exclusive_caps=1 card_label="Virtual Camera" video_nr=10 || true

# 5) Enable & start v4l2-relayd (creates the virtual camera backed by libcamera/icamerasrc)
say "Enabling v4l2-relayd service…"
systemctl daemon-reload || true
systemctl enable --now v4l2-relayd.service || true

# 6) Access permissions: add current desktop user to 'video'
if ! id -nG "${SUDO_USER:-$USER}" | grep -qw video; then
  say "Adding ${SUDO_USER:-$USER} to 'video' group (effective after relogin)."
  usermod -aG video "${SUDO_USER:-$USER}" || true
fi

# 7) Quick smoke test hints
say "Done. Next steps:"
say " - Run: libcamera-hello --list-cameras   (should list your IPU6 sensors)"
say " - Check: systemctl status v4l2-relayd   (should be active)"
say " - Look for: /dev/video10 (Virtual Camera) via 'v4l2-ctl --all -d /dev/video10'"
say " - Restart your browser / video app and pick the 'Virtual Camera'."
