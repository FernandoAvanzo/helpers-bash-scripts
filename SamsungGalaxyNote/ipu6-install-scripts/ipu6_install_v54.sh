#!/usr/bin/env bash
# Samsung Galaxy Book (IPU6/MIPI) — containerized userspace bridge to v4l2loopback
# Version: v54
# Host tested: Pop!_OS 22.04 (systemd 249), kernel 6.16.*
#
# What changed vs v53:
#  - FIX: stop bind-mounting the entire /dev into the container (this
#    conflicted with nspawn's /dev/console handling and caused
#    "Failed to create /dev/console symlink: File exists").
#  - Use --console=pipe for nspawn calls (so it won't try to create /dev/console at all).
#  - Only bind the *specific* camera device nodes we need (/dev/video*, /dev/media*,
#    /dev/v4l-subdev*, /dev/mei*), generated dynamically at runtime.
#  - Keep the DNS fix ( --resolv-conf=copy-host ) to avoid getaddrinfo(16) errors.
#  - Keep the APT cleanup to avoid Signed-By keyring conflicts.
#  - Install upstream Ubuntu Noble packages for v4l2-relayd + Intel IPU6 stack.
#  - Provide a small host wrapper that systemd runs to launch the pipeline in the container.

set -Eeuo pipefail

# --------------------------- Config ---------------------------
MACHINE="ipu6-noble"
ROOT="/var/lib/machines/${MACHINE}"
UBU_MIRROR="http://archive.ubuntu.com/ubuntu"  # change to a local mirror if needed
V4L2_NODE="/dev/video42"                        # v4l2loopback device on host
WIDTH=${WIDTH:-1280}
HEIGHT=${HEIGHT:-720}
FPS=${FPS:-30}

# Packages we want inside the container (Ubuntu 24.04 Noble)
CONTAINER_PKGS=(
  ca-certificates gnupg gpg curl
  v4l2-relayd gstreamer1.0-tools v4l-utils
  ipu6-camera-hal ipu6-camera-bins gstreamer1.0-icamera
)

log() { printf "[%(%F %T)T] %s
" -1 "$*"; }
require_root() { [[ $EUID -eq 0 ]] || { echo "This script must run as root"; exit 1; }; }

collect_binds() {
  # Build a list of --bind= arguments for just the camera-related nodes
  BIND_ARGS=()
  local p
  for p in /dev/video* /dev/media* /dev/v4l-subdev* /dev/mei*; do
    [[ -e "$p" ]] && BIND_ARGS+=(--bind="$p")
  done
}

nspawn() {
  # Wrapper with sane defaults that dodge prior errors:
  #  --resolv-conf=copy-host fixes DNS inside container
  #  --console=pipe avoids /dev/console symlink creation entirely
  #  DO NOT bind the whole /dev; only specific nodes via collect_binds
  collect_binds
  systemd-nspawn \
    --quiet --register=no --resolv-conf=copy-host --console=pipe \
    --machine="${MACHINE}" -D "${ROOT}" \
    "${BIND_ARGS[@]}" \
    "$@"
}

apt_in_container() {
  nspawn /usr/bin/env DEBIAN_FRONTEND=noninteractive \
    apt-get -y --option=Acquire::Retries=3 --no-install-recommends "$@"
}

# --------------------------- Preflight (host) ---------------------------
require_root

log "Host preflight…"
apt-get update -y || true
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

# Remove any stale /dev/console file that may confuse nspawn
rm -f "${ROOT}/dev/console" || true

# --------------------------- APT sources (container) ---------------------------
log "Configuring Intel IPU6 userspace PPA in container (Noble only)…"
install -d -m 0755 "${ROOT}/etc/apt/keyrings" "${ROOT}/etc/apt/sources.list.d"

# Purge any stale/conflicting ipu6 sources & keys from older attempts
rm -f "${ROOT}/etc/apt/sources.list.d"/*ipu6*.list || true
rm -f "${ROOT}/etc/apt/trusted.gpg.d"/*ipu6*.gpg || true
rm -f "${ROOT}/etc/apt/keyrings"/ipu6-*.gpg || true

cat >"${ROOT}/etc/apt/sources.list.d/ipu6-ppa.list" <<EOF
# Intel MIPI IPU6 (edge) — use with care
# https://launchpad.net/~oem-solutions-group/+archive/ubuntu/intel-ipu6
deb [arch=amd64 signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] \
  https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

# Import the PPA signing key (fingerprint A630 CA96 9109 90FF)
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xA630CA96910990FF" \
  | gpg --dearmor -o "${ROOT}/etc/apt/keyrings/ipu6-ppa.gpg"
chmod 0644 "${ROOT}/etc/apt/keyrings/ipu6-ppa.gpg"

# --------------------------- Install userspace stack ---------------------------
log "Updating APT metadata inside container…"
apt_in_container update

log "Installing IPU6 HAL + icamerasrc + helpers inside container…"
apt_in_container install "${CONTAINER_PKGS[@]}"

# --------------------------- Host wrapper and service ---------------------------
WRAP="/usr/local/sbin/ipu6-bridge-run"
log "Installing host wrapper: ${WRAP}"
install -D -m 0755 /dev/stdin "${WRAP}" <<'RUN'
#!/usr/bin/env bash
set -Eeuo pipefail
MACHINE="ipu6-noble"
ROOT="/var/lib/machines/${MACHINE}"
V4L2_NODE="/dev/video42"
WIDTH=${WIDTH:-1280}
HEIGHT=${HEIGHT:-720}
FPS=${FPS:-30}

collect_binds() {
  BIND_ARGS=()
  local p
  for p in /dev/video* /dev/media* /dev/v4l-subdev* /dev/mei*; do
    [[ -e "$p" ]] && BIND_ARGS+=(--bind="$p")
  done
}
collect_binds

exec systemd-nspawn \
  --quiet --register=no --resolv-conf=copy-host --console=pipe \
  --machine="${MACHINE}" -D "${ROOT}" \
  "${BIND_ARGS[@]}" \
  /usr/bin/env GST_DEBUG=0 \
  gst-launch-1.0 \
    icamerasrc ! \
    video/x-raw,format=NV12,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1 ! \
    v4l2sink device=${V4L2_NODE}
RUN

# Environment file for easy tuning
install -D -m 0644 /dev/stdin /etc/default/ipu6-bridge <<EOF
# ipu6-bridge defaults
WIDTH=${WIDTH}
HEIGHT=${HEIGHT}
FPS=${FPS}
EOF

SERVICE="/etc/systemd/system/ipu6-bridge.service"
log "Installing host systemd unit: ${SERVICE}"
cat >"${SERVICE}" <<'UNIT'
[Unit]
Description=Intel IPU6 -> v4l2loopback bridge (containerized userspace)
After=network-online.target systemd-udevd.service
Requires=systemd-udevd.service

[Service]
Type=simple
EnvironmentFile=-/etc/default/ipu6-bridge
ExecStart=/usr/local/sbin/ipu6-bridge-run
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
log "  - In apps: select 'IPU6 Bridge' camera (video42)"
