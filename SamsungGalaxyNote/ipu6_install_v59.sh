#!/usr/bin/env bash
# Samsung Galaxy Book (MTL) • IPU6 containerized relay -> /dev/video0
# v59 — binds missing kernel devices (/dev/v4l-subdev*, /dev/dma_heap/*) and /run/udev,
#       selects the OVTI02C1:00 sensor explicitly, and journals full gst output.
#       Keeps the good bits from v57/58 (Noble rootfs, Intel IPU6 PPA, platform plugin).

set -Eeuo pipefail
IFS=$'\n\t'

ROOT=/var/lib/machines/ipu6-noble
DIST=noble
MACHINE=ipu6-noble
SENSOR_DEFAULT="OVTI02C1:00"   # can be overridden via systemd Environment=SENSOR=...

log(){ printf "[%s] %s\n" "$(date +%F' '%T)" "$*"; }
fatal(){ log "[FATAL] $*"; exit 1; }

req_pkgs=(debootstrap systemd-container v4l2loopback-dkms gstreamer1.0-tools v4l-utils curl gnupg ca-certificates)

ensure_host_pkgs(){
  log "Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…"
  apt-get update -yq >/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${req_pkgs[@]}"
}

ensure_loopback(){
  # Create exactly one loopback at /dev/video0 with a friendly name
  if ! lsmod | grep -q '^v4l2loopback\b'; then
    modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Intel MIPI Virtual Camera"
  fi
  # If something else occupied video0, reload loopback to claim it
  if [[ ! -e /dev/video0 ]] || ! v4l2-ctl --all --device=/dev/video0 >/dev/null 2>&1; then
    rmmod v4l2loopback 2>/dev/null || true
    modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Intel MIPI Virtual Camera"
  fi
  log "Host v4l2loopback ready at /dev/video0"
}

bootstrap_rootfs(){
  if [[ ! -d "$ROOT" || ! -e "$ROOT/etc/os-release" ]]; then
    log "Bootstrapping Ubuntu $DIST rootfs at $ROOT…"
    install -d "$ROOT"
    debootstrap --arch=amd64 "$DIST" "$ROOT" http://archive.ubuntu.com/ubuntu
  else
    log "Rootfs exists, reusing: $ROOT"
  fi
}

configure_apt_in_container(){
  log "Configuring Intel IPU6 PPA in container ($DIST)…"
  install -d "$ROOT/etc/apt/keyrings" "$ROOT/etc/apt/sources.list.d"
  # Key (Launchpad IPU6 PPA)
  curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xA630CA96910990FF" \
    | gpg --dearmor -o "$ROOT/etc/apt/keyrings/ipu6-ppa.gpg"

  # Single, clean list file (avoid duplicates from earlier attempts)
  cat >"$ROOT/etc/apt/sources.list.d/ipu6-ppa.list" <<EOF
# Intel IPU6 userspace (HAL, icamerasrc) — development PPA, containerized on purpose
# Using Noble packages regardless of host release

deb [signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu $DIST main
EOF

  # Make sure we have DNS in the rootfs to avoid nspawn warning
  install -Dm644 /etc/resolv.conf "$ROOT/etc/resolv.conf" || true

  systemd-nspawn --directory="$ROOT" --machine="$MACHINE" \
    --resolv-conf=replace-host --quiet --pipe \
    apt-get update -y
}

install_userspace_in_container(){
  log "Installing IPU6 HAL + platform plugin + icamerasrc inside container…"
  systemd-nspawn --directory="$ROOT" --machine="$MACHINE" \
    --resolv-conf=replace-host --quiet --pipe \
    apt-get install -y --no-install-recommends \
    ca-certificates gnupg curl \
    libcamhal0 libcamhal-ipu6epmtl \
    gstreamer1.0-icamera v4l-utils gstreamer1.0-tools libv4l-0
}

install_wrapper_and_unit(){
  log "Installing relay wrapper and systemd unit on host…"
  install -d /usr/local/sbin
  cat > /usr/local/sbin/ipu6-relay-run <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
SENSOR="${SENSOR:-OVTI02C1:00}"

# Build bind list – include raw IPU6 nodes and supporting heaps
CANDIDATES=(/dev/video[0-9]* /dev/media* /dev/v4l-subdev* /dev/mei* /dev/dma_heap/*)
BIND_ARGS=()
for patt in "${CANDIDATES[@]}"; do
  for n in $patt; do
    [[ -e "$n" ]] && BIND_ARGS+=(--bind="$n")
  done
done

# Ensure we have a resolv.conf in the rootfs so nspawn won't whine
install -Dm644 /etc/resolv.conf "$ROOT/etc/resolv.conf" || true

# Run the pipeline; tee logs inside the rootfs for post-mortem
exec systemd-nspawn \
  --directory="$ROOT" --machine="$MACHINE" \
  --resolv-conf=replace-host --console=pipe \
  --bind-ro=/run/udev \
  "${BIND_ARGS[@]}" \
  /bin/bash -lc "mkdir -p /var/log; \
    echo 'LIBCAMHAL_PLUGIN_PATH='\"/usr/lib/libcamhal/plugins\"; \
    echo 'GST_PLUGIN_PATH='\"/usr/lib/x86_64-linux-gnu/gstreamer-1.0\"; \
    export LIBCAMHAL_PLUGIN_PATH=/usr/lib/libcamhal/plugins; \
    export GST_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/gstreamer-1.0; \
    export GST_DEBUG=icamerasrc:4,v4l2:3,default:2; \
    gst-inspect-1.0 icamerasrc || true; \
    gst-launch-1.0 -v icamerasrc device-name='${SENSOR}' ! \
      video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
      videoconvert ! video/x-raw,format=YUY2 ! \
      v4l2sink device=/dev/video0 sync=false qos=false \
      2>&1 | tee /var/log/ipu6-relay.log; \
    exit ${PIPESTATUS[0]}"
SH
  chmod +x /usr/local/sbin/ipu6-relay-run

  cat > /etc/systemd/system/ipu6-relay.service <<'UNIT'
[Unit]
Description=Intel IPU6 webcam relay (containerized) -> /dev/video0
After=multi-user.target
RequiresMountsFor=/var/lib/machines/ipu6-noble
ConditionPathExists=/var/lib/machines/ipu6-noble

[Service]
Type=simple
Environment=SENSOR=OVTI02C1:00
ExecStart=/usr/local/sbin/ipu6-relay-run
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now ipu6-relay.service || true
}

### MAIN
ensure_host_pkgs
ensure_loopback
bootstrap_rootfs
configure_apt_in_container
install_userspace_in_container
install_wrapper_and_unit

log "Done. Check: 'systemctl status ipu6-relay --no-pager' and 'journalctl -u ipu6-relay -b --no-pager'"
log "Container log (inside rootfs): $ROOT/var/log/ipu6-relay.log"
log "Apps should pick: Intel MIPI Virtual Camera (/dev/video0)."
