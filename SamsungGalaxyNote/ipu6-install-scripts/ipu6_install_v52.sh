#!/usr/bin/env bash
# Samsung Galaxy Book (IPU6) webcam helper, v52
# Host: Pop!_OS 22.04 (jammy). Container: Ubuntu 24.04 (noble) via systemd-nspawn.
# It fixes DNS in the container, cleans APT key clashes, installs the IPU6 userspace,
# and runs a GStreamer relay to v4l2loopback (/dev/video42).

set -Eeuo pipefail

MACHINE=ipu6-noble
ROOT=/var/lib/machines/$MACHINE
VIDEO_DEV=${VIDEO_DEV:-/dev/video42}
USE_PPA=${USE_PPA:-1}          # 1 = enable Intel IPU6 PPA inside container for icamerasrc/v4l2-relayd
ARCHIVE_MIRROR=${ARCHIVE_MIRROR:-http://archive.ubuntu.com/ubuntu}

log() { printf '[%(%F %T)T] %s\n' -1 "$*"; }
warn(){ printf '[%(%F %T)T] [WARN] %s\n' -1 "$*"; }
die() { printf '[%(%F %T)T] [FATAL] %s\n' -1 "$*"; exit 1; }

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root (sudo)."; }

preflight_host() {
  log "Host preflight…"
  [[ -f /sys/fs/cgroup/cgroup.controllers ]] || die "cgroup v2 not enabled."
  apt-get update -y >/dev/null || true
  apt-get install -y --no-install-recommends debootstrap systemd-container ca-certificates curl gpg \
    v4l2loopback-dkms v4l-utils gstreamer1.0-tools >/dev/null
  # ensure v4l2loopback on ${VIDEO_DEV}
  if [[ ! -e "$VIDEO_DEV" ]]; then
    modprobe v4l2loopback devices=1 video_nr=${VIDEO_DEV#/dev/video} card_label="IPU6 Virtual Cam" exclusive_caps=1 || true
    sleep 1
  fi
  [[ -e "$VIDEO_DEV" ]] || warn "v4l2loopback node $VIDEO_DEV not found yet (continuing)."
}

bootstrap_rootfs() {
  if [[ ! -d $ROOT ]]; then
    log "Bootstrapping $MACHINE rootfs (noble)…"
    debootstrap --arch=amd64 --variant=minbase \
      --include=systemd,ca-certificates,gnupg,curl \
      noble "$ROOT" "$ARCHIVE_MIRROR"
  else
    log "Rootfs exists, reusing: $ROOT"
  fi

  # reliable DNS inside container: copy host resolv.conf as a plain file
  install -Dm0644 /etc/resolv.conf "$ROOT/etc/resolv.conf"

  # minimal sources.list
  cat >"$ROOT/etc/apt/sources.list"<<EOF
deb $ARCHIVE_MIRROR noble main universe multiverse restricted
deb $ARCHIVE_MIRROR noble-updates main universe multiverse restricted
deb $ARCHIVE_MIRROR noble-security main universe multiverse restricted
EOF

  # clean any previous broken ipu6 PPA definitions/keys
  rm -f "$ROOT"/etc/apt/sources.list.d/oem-solutions-group-ubuntu-intel-ipu6*.list || true
  rm -f "$ROOT"/etc/apt/trusted.gpg.d/*ipu6*.gpg || true
  mkdir -p "$ROOT/etc/apt/keyrings"

  if [[ "$USE_PPA" == "1" ]]; then
    log "Configuring Intel IPU6 PPA (edge/dev; keep other packages from official archive)…"
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x8c47be8f8f1b1e2f" \
      | gpg --dearmor > "$ROOT/etc/apt/keyrings/ipu6-ppa.gpg"
    cat >"$ROOT/etc/apt/sources.list.d/intel-ipu6-ppa.list"<<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] \
https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF
  fi
}

apt_in_nspawn() {
  # use our copied resolv.conf; avoid bind-mounting the host stub resolver
  systemd-nspawn -D "$ROOT" --resolv-conf=off bash -lc "apt-get update -y" \
    || die "apt update failed inside container"
  systemd-nspawn -D "$ROOT" --resolv-conf=off bash -lc \
    "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
     gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
     v4l2-relayd || true"

  # try icamerasrc from PPA (preferred for IPU6 HAL); if unavailable, fall back to libcamera-tools
  if ! systemd-nspawn -D "$ROOT" --resolv-conf=off bash -lc \
    "DEBIAN_FRONTEND=noninteractive apt-get install -y gstreamer1.0-icamerasrc"; then
    warn "gstreamer1.0-icamerasrc not available; falling back to libcamera."
    systemd-nspawn -D "$ROOT" --resolv-conf=off bash -lc \
      "DEBIAN_FRONTEND=noninteractive apt-get install -y libcamera-tools"
  fi
}

write_nspawn_config() {
  # Make booted container, veth networking, and sane resolv.conf behavior.
  mkdir -p /etc/systemd/nspawn
  cat >/etc/systemd/nspawn/${MACHINE}.nspawn <<'EOF'
[Exec]
Boot=yes

[Network]
VirtualEthernet=yes

[Files]
# Pass all video/media nodes; simplest and robust
Bind=/dev:/dev
# Let container see running kernel's modules read-only (some tools look at /lib/modules)
BindReadOnly=/lib/modules

[Resolve]
# IMPORTANT: copy host resolv.conf into /etc/resolv.conf (avoid stub bind)
ResolvConf=copy-host
EOF
}

install_container_service() {
  # Service inside the container that relays camera to the host v4l2loopback device
  local inner_service_dir="$ROOT/etc/systemd/system"
  mkdir -p "$inner_service_dir"

  # Prefer icamerasrc (IPU6 HAL). If not present, use libcamerasrc.
  local runner='/usr/bin/bash -lc'
  local pipeline_icam="GST_DEBUG=icamerasrc:3 gst-launch-1.0 -e \
    icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 \
    ! videoconvert ! v4l2sink device=${VIDEO_DEV} sync=false"

  local pipeline_libcam="libcamera-vid -t 0 --width 1280 --height 720 --framerate 30 \
    --codec yuv420 --stdout | gst-launch-1.0 -e fdsrc ! rawvideoparse format=i420 width=1280 height=720 framerate=30/1 \
    ! videoconvert ! v4l2sink device=${VIDEO_DEV} sync=false"

  cat >"$inner_service_dir/ipu6-relay.service"<<EOF
[Unit]
Description=IPU6 camera → v4l2loopback relay
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=${runner} 'command -v gst-launch-1.0 >/dev/null && command -v icamerasrc >/dev/null && ${pipeline_icam} || ${pipeline_libcam}'
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

start_everything() {
  log "Enabling and starting machine unit…"
  systemctl enable --now systemd-nspawn@${MACHINE}.service

  log "Enable container relay service…"
  # enable inside the container
  machinectl shell ${MACHINE} /usr/bin/systemctl enable --now ipu6-relay.service || true

  log "Done. Test with:  v4l2-ctl --all --device=${VIDEO_DEV}  and open the virtual camera in apps."
}

# --- main
require_root
preflight_host
bootstrap_rootfs
apt_in_nspawn
write_nspawn_config
install_container_service
start_everything
