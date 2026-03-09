#!/usr/bin/env bash
# Samsung Galaxy Book (IPU6/MIPI) — containerized userspace bridge to v4l2loopback
# Tested on Pop!_OS 22.04 (Jammy base) host with kernel 6.16.*
# Strategy:
#  - Keep the kernel/firmware on the HOST (already working per dmesg)
#  - Run Intel IPU6 userspace (HAL + icamerasrc + helpers) inside a
#    minimal Ubuntu 24.04 (Noble) systemd-nspawn container
#  - Bind host /dev/* so the container can access the IPU6 nodes and v4l2loopback sink
#  - Avoid all previous apt key/sources conflicts and resolv.conf/DNS pitfalls
#  - Provide a systemd service that launches the GStreamer pipeline into /dev/video42

set -Eeuo pipefail

# --------------------------- Config ---------------------------
MACHINE="ipu6-noble"
ROOT="/var/lib/machines/${MACHINE}"
UBU_MIRROR="http://archive.ubuntu.com/ubuntu"  # change if you need a regional mirror
V4L2_NODE="/dev/video42"                        # v4l2loopback device on host
WIDTH=${WIDTH:-1280}
HEIGHT=${HEIGHT:-720}
FPS=${FPS:-30}

# Packages we want inside the container
CONTAINER_PKGS=(
  ca-certificates gnupg gpg curl
  gstreamer1.0-tools v4l-utils
  ipu6-camera-hal ipu6-camera-bins
  gst-plugins-icamera v4l2-relayd
)

# --------------------------- Helpers ---------------------------
log() { printf "[%(%F %T)T] %s\n" -1 "$*"; }
require_root() { [[ $EUID -eq 0 ]] || { echo "This script must run as root"; exit 1; }; }

nspawn() {
  # Wrapper with sane defaults that dodge prior errors:
  #  --resolv-conf=copy-host fixes DNS inside the container (no stub-resolv hassle)
  #  --register=no avoids spurious registry errors on some hosts
  #  --bind=/dev gives the container access to /dev/video*, /dev/media*, /dev/mei0, v4l2loopback, etc
  systemd-nspawn \
    --quiet --register=no --resolv-conf=copy-host \
    --machine="${MACHINE}" -D "${ROOT}" \
    --bind=/dev \
    "$@"
}

apt_in_container() {
  nspawn /usr/bin/env DEBIAN_FRONTEND=noninteractive \
    apt-get -y --no-install-recommends "$@"
}

# --------------------------- Preflight (host) ---------------------------
require_root

log "Host preflight…"
# Ensure mandatory host packages
apt-get update -y
apt-get install -y --no-install-recommends \
  debootstrap systemd-container ca-certificates curl gpg \
  v4l2loopback-dkms gstreamer1.0-tools v4l-utils || true

# Ensure v4l2loopback exists on the host
if [[ ! -e ${V4L2_NODE} ]]; then
  log "Loading v4l2loopback on host (creating ${V4L2_NODE})…"
  modprobe v4l2loopback exclusive_caps=1 video_nr=42 card_label="IPU6 Bridge"
  sleep 1
fi
if [[ ! -e ${V4L2_NODE} ]]; then
  log "[FATAL] ${V4L2_NODE} not present after modprobe."; exit 1
fi

# --------------------------- Bootstrap container ---------------------------
if [[ ! -d ${ROOT} || ! -e ${ROOT}/bin/sh ]]; then
  log "Bootstrapping Noble rootfs at ${ROOT}…"
  mkdir -p "${ROOT}"
  debootstrap \
    --variant=minbase \
    --include=systemd,ca-certificates,gnupg,gpg,curl \
    noble "${ROOT}" "${UBU_MIRROR}"
else
  log "Rootfs exists, reusing: ${ROOT}"
fi

# Fix prior /dev/console symlink/device conflicts that killed nspawn
rm -f "${ROOT}/dev/console" || true

# --------------------------- APT sources (container) ---------------------------
log "Configuring Intel IPU6 userspace PPA in container (Noble only)…"
install -d -m 0755 "${ROOT}/etc/apt/keyrings" "${ROOT}/etc/apt/sources.list.d"

# Purge any stale/conflicting ipu6 sources & keys from older attempts
rm -f "${ROOT}/etc/apt/sources.list.d"/*ipu6*.list || true
rm -f "${ROOT}/etc/apt/trusted.gpg.d"/*ipu6*.gpg || true
rm -f "${ROOT}/etc/apt/keyrings"/ipu6-*.gpg || true

# Add the PPA for noble only, with a single Signed-By key to avoid conflicts
cat >"${ROOT}/etc/apt/sources.list.d/ipu6-ppa.list" <<EOF
# Edge development PPA for Intel IPU6 userspace (use at your own risk)
# https://launchpad.net/~oem-solutions-group/+archive/ubuntu/intel-ipu6
# Noble series
deb [arch=amd64 signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] \
  https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

# Import the PPA signing key (fingerprint A630 CA96 9109 90FF)
# Source: Launchpad page shows this key ID and fingerprint.
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xA630CA96910990FF" \
  | gpg --dearmor -o "${ROOT}/etc/apt/keyrings/ipu6-ppa.gpg"
chmod 0644 "${ROOT}/etc/apt/keyrings/ipu6-ppa.gpg"

# --------------------------- Install userspace stack ---------------------------
log "Updating APT metadata inside container…"
apt_in_container update

log "Installing IPU6 HAL + icamerasrc + helpers inside container…"
apt_in_container install "${CONTAINER_PKGS[@]}"

# --------------------------- Host service to bridge camera ---------------------------
SERVICE="/etc/systemd/system/ipu6-bridge.service"
log "Installing host systemd unit: ${SERVICE}"
cat >"${SERVICE}" <<UNIT
[Unit]
Description=Intel IPU6 -> v4l2loopback bridge (containerized userspace)
After=network-online.target systemd-udevd.service
Requires=systemd-udevd.service

[Service]
Type=simple
# Launch the GStreamer pipeline inside the container and push frames to ${V4L2_NODE}
ExecStart=/usr/bin/systemd-nspawn \
  --quiet --register=no --resolv-conf=copy-host \
  --machine=${MACHINE} -D ${ROOT} \
  --bind=/dev \
  /usr/bin/gst-launch-1.0 \
    icamerasrc ! \
    video/x-raw,format=NV12,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1 ! \
    v4l2sink device=${V4L2_NODE}
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now ipu6-bridge.service

log "All done. Useful checks:"
log "  - journalctl -u ipu6-bridge -b   # see pipeline logs"
log "  - v4l2-ctl --list-devices        # confirm ${V4L2_NODE} exists"
log "  - Try in apps: select 'IPU6 Bridge' camera (video42)"
