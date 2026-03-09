#!/usr/bin/env bash
set -euo pipefail

# Intel IPU6 webcam relay via systemd-nspawn (Ubuntu Noble container) -> v4l2loopback (/dev/video0)
# v62

MACHINE=ipu6-noble
ROOT=/var/lib/machines/${MACHINE}

log(){ echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# 1) Host preflight: tools + v4l2loopback
log "Host preflight…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  debootstrap systemd-container gpg ca-certificates curl \
  v4l2loopback-dkms v4l-utils gstreamer1.0-tools >/dev/null

# Load one v4l2loopback device at /dev/video0 for apps to consume
log "Ensuring v4l2loopback (/dev/video0)…"
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback devices=1 video_nr=0 exclusive_caps=1 card_label="Intel MIPI Camera Front"
log "Host v4l2loopback ready at /dev/video0"

# 2) Base container (Ubuntu 24.04 Noble)
if [[ ! -d "${ROOT}" || ! -f "${ROOT}/etc/os-release" ]]; then
  log "Creating Ubuntu Noble rootfs in ${ROOT}…"
  debootstrap --arch=amd64 noble "${ROOT}" http://archive.ubuntu.com/ubuntu >/dev/null
else
  log "Noble rootfs present: ${ROOT}"
fi

# 3) Inside-container: fix Intel IPU6 PPA (dedupe & correct keyring)
log "Configuring Intel IPU6 PPA inside container…"
systemd-nspawn -D "${ROOT}" --quiet --console=pipe /bin/bash -lc '
  set -euo pipefail

  mkdir -p /etc/apt/keyrings /etc/apt/sources.list.d

  # Remove any stale/duplicate Intel IPU6 PPA definitions and keyrings
  rm -f /etc/apt/sources.list.d/*intel*ipu6*.list \
        /etc/apt/sources.list.d/*oem*ipu6*.list \
        /etc/apt/sources.list.d/ipu6-ppa.list~ 2>/dev/null || true

  # Import the Launchpad PPA key (A630CA96910990FF) non-interactively
  tmpdir="$(mktemp -d)"
  GNUPGHOME="$tmpdir"
  export GNUPGHOME
  gpg --batch --keyserver keyserver.ubuntu.com --recv-keys A630CA96910990FF
  gpg --batch --export A630CA96910990FF > /etc/apt/keyrings/ipu6-ppa.gpg
  chmod 0644 /etc/apt/keyrings/ipu6-ppa.gpg
  rm -rf "$tmpdir"

  # Single authoritative PPA list
  cat >/etc/apt/sources.list.d/ipu6-ppa.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] \
http://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

  apt-get update -qq
'

# 4) Inside-container: install HAL + plugin + tools
log "Installing IPU6 HAL + icamerasrc + tools inside container…"
systemd-nspawn -D "${ROOT}" --quiet --console=pipe /bin/bash -lc '
  set -euo pipefail
  apt-get install -y -qq ca-certificates gnupg curl v4l-utils gstreamer1.0-tools \
    libcamhal0 libcamhal-ipu6epmtl gstreamer1.0-icamera >/dev/null
'

# 5) Host-side runner: enumerates devices and starts the relay in the container
install -d -m 0755 /usr/local/sbin
cat >/usr/local/sbin/ipu6-relay-run <<'RUN'
#!/usr/bin/env bash
set -euo pipefail

ROOT="/var/lib/machines/ipu6-noble"
MACHINE="ipu6-noble"

# Build bind list dynamically (video/media/subdev/mei0 if present)
binds=()
for p in /dev/video* /dev/media* /dev/v4l-subdev* /dev/mei0 ; do
  [[ -e "$p" ]] && binds+=(--bind="$p")
done

# Also pass sysfs/proc/udev view (read-only) and host resolv.conf
exec systemd-nspawn \
  --directory="$ROOT" \
  --machine="$MACHINE" \
  --register=yes \
  --resolv-conf=bind-host \
  --private-users=off \
  --console=pipe \
  --bind-ro=/sys \
  --bind-ro=/proc \
  --bind-ro=/run/udev \
  "${binds[@]}" \
  /bin/bash -lc '
    export LIBCAMHAL_PLUGIN_PATH=/usr/lib/libcamhal/plugins
    export GST_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/gstreamer-1.0

    # Optional override: e.g. IPU6_SRC_ARGS="device-index=0"
    : "${IPU6_SRC_ARGS:=}"

    # Basic 720p relay into the host virtual cam at /dev/video0
    exec gst-launch-1.0 -v \
      icamerasrc ${IPU6_SRC_ARGS} ! \
      video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
      queue ! videoconvert ! video/x-raw,format=YUY2 ! \
      v4l2sink device=/dev/video0 sync=false qos=false
  '
RUN
chmod +x /usr/local/sbin/ipu6-relay-run

# 6) systemd unit on host
cat >/etc/systemd/system/ipu6-relay.service <<'UNIT'
[Unit]
Description=Intel IPU6 webcam relay (containerized) -> /dev/video0
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/ipu6-relay-run
Restart=on-failure
RestartSec=3
# Give it time to settle devices
StartLimitBurst=5
StartLimitIntervalSec=60
# Journal tags
SyslogIdentifier=ipu6-relay

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now ipu6-relay.service

log "Done. Check status: systemctl status ipu6-relay --no-pager"
log "If not streaming yet, view logs: journalctl -u ipu6-relay -b --no-pager"
