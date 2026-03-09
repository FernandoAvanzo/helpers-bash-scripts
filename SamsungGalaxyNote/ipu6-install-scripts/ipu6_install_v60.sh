#!/usr/bin/env bash
set -euo pipefail

# Intel IPU6 webcam relay into a v4l2loopback device using a systemd-nspawn (Noble) container.
# Host: Pop!_OS 22.04 (Jammy) — Kernel and IPU6 drivers already working.

ROOTFS=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
LOOPBACK_DEV=/dev/video0

log(){ printf '[%(%F %T)T] %s\n' -1 "$*"; }

need_host_pkgs=(
  ca-certificates curl gpg debootstrap systemd-container
  v4l2loopback-dkms gstreamer1.0-tools v4l-utils
)

log "Host preflight…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y "${need_host_pkgs[@]}" >/dev/null

# Make sure v4l2loopback exists as /dev/video0 (single device, consistent name)
if ! modinfo v4l2loopback >/dev/null 2>&1; then
  log "v4l2loopback module not available"; exit 1
fi
if ! ls /dev/video0 >/dev/null 2>&1; then
  log "Loading v4l2loopback (1 device) at ${LOOPBACK_DEV}…"
  modprobe -r v4l2loopback 2>/dev/null || true
  modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Intel MIPI Virtual Camera"
fi
log "Host v4l2loopback ready at ${LOOPBACK_DEV}"

# Bootstrap Noble rootfs if missing
if [ ! -d "$ROOTFS" ] || [ ! -f "$ROOTFS/etc/os-release" ]; then
  log "Creating Noble rootfs at $ROOTFS…"
  debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu
fi
log "Noble rootfs present: $ROOTFS"

# Configure Intel IPU6 PPA in container
log "Configuring APT sources & keyrings inside container…"
install -d "$ROOTFS/etc/apt/keyrings"
curl -fsSL https://keyserver.ubuntu.com/pks/lookup?op=get\&search=0x0F164EEB3CF47C3D \
  | gpg --dearmor -o "$ROOTFS/etc/apt/keyrings/intel-ipu6.gpg"
cat >"$ROOTFS/etc/apt/sources.list.d/ipu6-ppa.list" <<'EOF'
deb [signed-by=/etc/apt/keyrings/intel-ipu6.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

# Basic apt sources (if not present)
grep -q '^deb .*/ubuntu noble ' "$ROOTFS/etc/apt/sources.list" 2>/dev/null || {
  cat >"$ROOTFS/etc/apt/sources.list"<<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF
}

log "Updating APT metadata inside container…"
systemd-nspawn -D "$ROOTFS" --machine="$MACHINE" --quiet \
  --bind-ro=/sys --bind=/dev \
  apt-get update -qq

log "Installing IPU6 HAL + platform plugin + icamerasrc + tools inside container…"
systemd-nspawn -D "$ROOTFS" --machine="$MACHINE" --quiet \
  --bind-ro=/sys --bind=/dev \
  bash -lc 'DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ca-certificates curl gnupg v4l-utils gstreamer1.0-tools \
      libcamhal0 libcamhal-ipu6epmtl gstreamer1.0-icamera >/dev/null'

# Host wrapper to run the relay
install -d /usr/local/sbin
cat > /usr/local/sbin/ipu6-relay-run <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOTFS=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
LOOP=/dev/video0

# Build bind list for all relevant device nodes
binds=( --bind-ro=/sys )
for pat in /dev/video* /dev/media* /dev/v4l-subdev* /dev/mei* /dev/dma_heap/*; do
  for n in $pat; do [ -e "$n" ] && binds+=( --bind="$n" ); done
done

# Compose a small detection+relay script that runs inside the container.
read -r -d '' inside <<'INSIDE'
set -euo pipefail
export LIBCAMHAL_PLUGIN_PATH=/usr/lib/libcamhal/plugins
export GST_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/gstreamer-1.0

# Try to discover an enumerated device-name; if none, fall back to first index.
devname=$(
  gst-inspect-1.0 icamerasrc 2>/dev/null \
    | awk '/Possible values:/,0' \
    | sed -n 's/ *\([A-Za-z0-9:_.-]\+\).*/\1/p' \
    | head -n1 || true
)
if [ -n "${devname:-}" ]; then
  DEVARG="device-name=${devname}"
else
  DEVARG=""   # let icamerasrc pick the first sensor
fi

# Run the pipeline: NV12 → convert → YUY2 → loopback
exec gst-launch-1.0 -q icamerasrc ${DEVARG} ! \
  video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
  queue ! videoconvert ! video/x-raw,format=YUY2 ! \
  v4l2sink device=/dev/video0 sync=false qos=false
INSIDE

# Run it
exec systemd-nspawn -D "$ROOTFS" --machine="$MACHINE" --quiet \
  --capability=all --console=pipe "${binds[@]}" \
  /bin/bash -lc "$inside"
EOF
chmod +x /usr/local/sbin/ipu6-relay-run

# Systemd unit on the host
cat > /etc/systemd/system/ipu6-relay.service <<'EOF'
[Unit]
Description=Intel IPU6 webcam relay (containerized) -> /dev/video0
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/sbin/ipu6-relay-run
Restart=on-failure
RestartSec=1
# Helpful env for debugging; comment out to silence
Environment=GST_DEBUG=icamerasrc:3,DEFAULT:2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ipu6-relay.service

log "Done. Verify with: v4l2-ctl --list-devices (look for a loopback at ${LOOPBACK_DEV}),"
log "then test:  ffplay -f v4l2 -input_format yuyv422 -video_size 1280x720 -i ${LOOPBACK_DEV}  (or open in Meet/Zoom)."
