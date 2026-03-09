#!/usr/bin/env bash
set -euo pipefail

# === Config ===
ROOTFS=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
HOST_VCAM_NR=${HOST_VCAM_NR:-0}            # /dev/video0
HOST_VCAM_LABEL=${HOST_VCAM_LABEL:-"Intel MIPI Virtual Camera"}
DEBIAN_FRONTEND=noninteractive

log(){ printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

need_root(){
  if [[ $EUID -ne 0 ]]; then echo "Run as root (sudo)"; exit 1; fi
}

ensure_host_bits(){
  log "Host preflight…"
  modprobe v4l2loopback || true
  # (Re)load one virtual device at /dev/video${HOST_VCAM_NR}
  if ! ls /dev/video${HOST_VCAM_NR} >/dev/null 2>&1; then
    modprobe -r v4l2loopback 2>/dev/null || true
    modprobe v4l2loopback \
      video_nr=${HOST_VCAM_NR} \
      exclusive_caps=1 \
      card_label="${HOST_VCAM_LABEL}"
  fi
  log "Host v4l2loopback ready at /dev/video${HOST_VCAM_NR}"
}

ensure_rootfs(){
  if [[ -d "$ROOTFS" && -f "$ROOTFS/etc/os-release" ]]; then
    log "Noble rootfs present: $ROOTFS"
    return
  fi
  log "Creating Ubuntu Noble rootfs at $ROOTFS …"
  apt-get update -qq
  apt-get install -y -qq debootstrap ca-certificates curl gnupg
  debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu
}

container_sh(){
  systemd-nspawn --directory="$ROOTFS" --machine="$MACHINE" --quiet --as-pid2 \
    --setenv=DEBIAN_FRONTEND=noninteractive \
    --bind-ro=/sys --bind=/run/udev \
    "$@"
}

cfg_apt_inside(){
  log "Configuring APT sources & keyrings inside container…"
  install -d -m 0755 "$ROOTFS/etc/apt/keyrings"

  # Base Ubuntu Noble sources
  cat >"$ROOTFS/etc/apt/sources.list"<<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF

  # OEM IPU6 PPA (Noble). Use proper Launchpad signing key via keyserver.
  # (This is the Launchpad "OEM Solutions Group" PPA key that signs oem-solutions-group/intel-ipu6)
  # If it ever rotates, add the new fingerprint here.
  KEYRING="$ROOTFS/etc/apt/keyrings/oem-intel-ipu6.gpg"
  FPR="0xA630CA96910990FF"   # Launchpad PPA for OEM Solutions Group
  curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=${FPR}" \
    | gpg --dearmor --yes -o "$KEYRING"

  cat >"$ROOTFS/etc/apt/sources.list.d/ipu6-ppa.list"<<'EOF'
deb [signed-by=/etc/apt/keyrings/oem-intel-ipu6.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

  # Name resolution inside the container (avoid the resolv.conf warning)
  install -D -m0644 /etc/resolv.conf "$ROOTFS/etc/resolv.conf" || true

  log "Updating APT metadata inside container…"
  container_sh apt-get update -qq
}

install_ipu6_stack(){
  log "Installing IPU6 HAL + plugin + tools inside container…"
  # software-properties-common is optional; we already added the source & key
  container_sh apt-get install -y -qq \
    ca-certificates gnupg curl \
    gstreamer1.0-tools v4l-utils \
    libcamhal0 libcamhal-ipu6epmtl gstreamer1.0-icamera || true

  # Try v4l2-relayd if available on this build; ignore if not found.
  container_sh bash -lc 'apt-get install -y -qq v4l2-relayd 2>/dev/null || true'
}

make_wrapper_and_service(){
  log "Installing host wrapper and systemd service…"

  install -D -m0755 /dev/stdin /usr/local/sbin/ipu6-relay-run <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOTFS=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
OUT_NR=${HOST_VCAM_NR:-0}  # Host v4l2loopback (/dev/video${OUT_NR})

# Build dynamic --bind list for all present video/media/mei nodes
bind_flags=()
for n in /dev/video* /dev/media* /dev/mei* ; do
  [[ -e "$n" ]] && bind_flags+=(--bind="$n")
done
# Ensure sysfs + udev are visible (critical for HAL)
bind_flags+=(--bind-ro=/sys --bind=/run/udev)

# Prefer v4l2-relayd (if installed), else fall back to GStreamer pipeline
CMD='if command -v v4l2-relayd >/dev/null 2>&1; then
        exec v4l2-relayd --output /dev/video'"${OUT_NR}"' --fps 30
     else
        export LIBCAMHAL_PLUGIN_PATH=/usr/lib/libcamhal/plugins
        export GST_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/gstreamer-1.0
        exec gst-launch-1.0 -v icamerasrc ! \
             video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
             queue ! videoconvert ! video/x-raw,format=YUY2 ! \
             v4l2sink device=/dev/video'"${OUT_NR}"' sync=false qos=false
     fi'

exec systemd-nspawn \
  --directory="${ROOTFS}" --machine="${MACHINE}" \
  --resolv-conf=replace-host --console=pipe \
  "${bind_flags[@]}" \
  /bin/bash -lc "$CMD"
EOF

  install -D -m0644 /dev/stdin /etc/systemd/system/ipu6-relay.service <<'EOF'
[Unit]
Description=Intel IPU6 webcam relay (containerized) -> /dev/video0
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/sbin/ipu6-relay-run
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now ipu6-relay.service || true
}

main(){
  need_root
  ensure_host_bits
  ensure_rootfs
  cfg_apt_inside
  install_ipu6_stack
  make_wrapper_and_service
  log "Done. Verify with: v4l2-ctl --list-devices (look for \"Intel MIPI Virtual Camera\" at /dev/video0)"
}

main "$@"
