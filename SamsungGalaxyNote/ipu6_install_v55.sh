#!/usr/bin/env bash
set -Eeuo pipefail

ROOTFS=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
VDEV_NR=42
VDEV_PATH=/dev/video${VDEV_NR}
CARD_LABEL="Intel MIPI Virtual Camera"
PPA_KEY_FP="A630CA96910990FF"   # Intel IPU6 PPA public key (not the private key)

log(){ printf "[%(%F %T)T] %s\n" -1 "$*"; }
die(){ echo "[FATAL] $*" >&2; exit 1; }

require_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Run as root"; }

ensure_host_packages(){
  log "Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…"
  apt-get update -y
  apt-get install -y --no-install-recommends \
    debootstrap systemd-container ca-certificates curl gpg \
    v4l2loopback-dkms v4l-utils gstreamer1.0-tools
}

ensure_v4l2loopback(){
  if ! modinfo v4l2loopback >/dev/null 2>&1; then
    die "v4l2loopback-dkms not installed correctly"
  fi
  # Load module with a fixed node number and label (idempotent)
  if ! lsmod | grep -q '^v4l2loopback'; then
    log "Loading v4l2loopback on host…"
    modprobe v4l2loopback exclusive_caps=1 video_nr=${VDEV_NR} card_label="${CARD_LABEL}"
  fi
  if [ ! -e "${VDEV_PATH}" ]; then
    log "[WARN] ${VDEV_PATH} not present yet; continuing (service will retry)."
  else
    log "Host v4l2loopback ready at ${VDEV_PATH}"
  fi
}

bootstrap_rootfs(){
  if [ -e "${ROOTFS}/etc/os-release" ]; then
    log "Noble rootfs already exists, reusing."
    return
  fi
  log "Bootstrapping Noble rootfs at ${ROOTFS}…"
  mkdir -p "${ROOTFS}"
  debootstrap --variant=minbase noble "${ROOTFS}" http://archive.ubuntu.com/ubuntu
}

configure_apt_inside_rootfs(){
  log "Configuring APT sources & keyrings inside container…"
  install -d -m 0755 "${ROOTFS}/etc/apt/keyrings"
  # Base Ubuntu (enable main + universe; security + updates)
  cat >"${ROOTFS}/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF
  # Intel IPU6 PPA for Noble
  # Put the PPA key in place (fetch with fallback)
  if ! [ -s "${ROOTFS}/etc/apt/keyrings/ipu6-ppa.gpg" ]; then
    TMPKEY=$(mktemp)
    if curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${PPA_KEY_FP}" -o "${TMPKEY}"; then
      gpg --dearmor < "${TMPKEY}" > "${ROOTFS}/etc/apt/keyrings/ipu6-ppa.gpg"
      rm -f "${TMPKEY}"
    else
      # Fallback: use gpg keyserver from host and copy
      gpg --keyserver keyserver.ubuntu.com --recv-keys "${PPA_KEY_FP}"
      gpg --export "${PPA_KEY_FP}" | gpg --dearmor > "${ROOTFS}/etc/apt/keyrings/ipu6-ppa.gpg"
    fi
  fi
  cat >"${ROOTFS}/etc/apt/sources.list.d/intel-ipu6.list" <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF
  # Clean out any accidentally-added jammy entries to avoid Signed-By conflicts
  rm -f "${ROOTFS}/etc/apt/sources.list.d/"*jammy*.list 2>/dev/null || true
}

nspawn_run(){
  # Helper to run a command inside the container with safe console and working DNS
  systemd-nspawn \
    --directory="${ROOTFS}" \
    --quiet \
    --machine="${MACHINE}" \
    --resolv-conf=replace-host \
    --console=pipe \
    /bin/bash -lc "$*"
}

install_userspace_in_container(){
  log "Updating APT metadata inside container…"
  nspawn_run "apt-get update -y"

  log "Installing IPU6 HAL + icamerasrc + tools inside container…"
  nspawn_run "apt-get install -y --no-install-recommends ca-certificates gnupg curl gstreamer1.0-tools libcamhal0 gstreamer1.0-icamera"
}

make_relay_service(){
  log "Creating host systemd service to run the relay inside the container…"

  # Build bind list for only the devices we need
  BINDS=()
  for p in /dev/video* /dev/media* /dev/v4l-subdev* /dev/mei*; do
    [ -e "$p" ] && BINDS+=( "--bind=${p}" )
  done

  # Persist binds into a file for ExecStart readability
  BIND_ARGS_FILE=/etc/ipu6.bind-args
  printf "%s\n" "${BINDS[@]}" > "${BIND_ARGS_FILE}"

  # Service that runs a persistent GStreamer pipeline inside the container
  # Relays icamerasrc -> v4l2sink at ${VDEV_PATH}
  cat >/etc/systemd/system/ipu6-relay.service <<EOF
[Unit]
Description=Intel IPU6 webcam relay (containerized) -> ${VDEV_PATH}
After=multi-user.target
RequiresMountsFor=${ROOTFS}

[Service]
Type=simple
# Keep trying if something (re)loads late
Restart=always
RestartSec=2
# Build args: safe console + working DNS + needed device binds only
ExecStart=/bin/bash -lc '\
  set -euo pipefail; \
  mapfile -t BINDS < ${BIND_ARGS_FILE} || true; \
  exec systemd-nspawn --directory="${ROOTFS}" --machine="${MACHINE}" \
    --resolv-conf=replace-host --console=pipe \
    "\${BINDS[@]}" \
    /bin/bash -lc "exec gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12 ! v4l2sink device=${VDEV_PATH}" \
'
# Give it access to the v4l2loopback node
DeviceAllow=${VDEV_PATH} rw

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now ipu6-relay.service
}

main(){
  require_root
  log "Host preflight…"
  ensure_host_packages
  ensure_v4l2loopback
  bootstrap_rootfs
  configure_apt_inside_rootfs
  install_userspace_in_container
  make_relay_service
  log "Done. Check with: v4l2-ctl --list-devices"
}

main "$@"
