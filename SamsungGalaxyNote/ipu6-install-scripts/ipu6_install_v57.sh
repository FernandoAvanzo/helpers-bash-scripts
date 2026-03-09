#!/usr/bin/env bash
# Samsung Galaxy Book (IPU6/MIPI) — containerized userspace bridge to v4l2loopback
# Version: v57
# Host tested: Pop!_OS 22.04 (systemd 249), kernel 6.16.*
#
# What changed vs v56:
#  - FIX 1: Install the *platform plugin* package `libcamhal-ipu6epmtl` inside
#    the container. Your logs show CamHAL tried to dlopen
#    /usr/lib/libcamhal/plugins/ipu6epmtl.so and failed. This package provides
#    that .so on Meteor Lake (MTL). Without it, icamerasrc enumerations break,
#    leading to GLib-GObject warnings during gst plugin scan.
#  - FIX 2: Clean up duplicate PPA list files (intel-ipu6.list *and*
#    ipu6-ppa.list) to remove the "Target Packages configured multiple times"
#    warnings and ensure we only track Noble.
#  - FIX 3: Replace the complex ExecStart quoting with a small host wrapper
#    (/usr/local/sbin/ipu6-relay-run). This avoids the "Unbalanced quoting"
#    error and makes logs simpler.
#  - Keep: nspawn console/DNS fixes, selective /dev binds, single-loopback at
#    /dev/video0, browser-friendly NV12->YUY2 pipeline.

set -Eeuo pipefail

ROOTFS=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
WIDTH=${WIDTH:-1280}
HEIGHT=${HEIGHT:-720}
FPS=${FPS:-30}
V4L2_NODE=/dev/video0         # enforced v4l2loopback sink for apps
PPA_KEY_FP="A630CA96910990FF" # Intel IPU6 PPA public key

log(){ printf "[%(%F %T)T] %s
" -1 "$*"; }
die(){ echo "[FATAL] $*" >&2; exit 1; }
require_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Run as root"; }

collect_binds(){
  BIND_ARGS=()
  local p
  for p in /dev/video* /dev/media* /dev/v4l-subdev* /dev/mei*; do
    [[ -e "$p" ]] && BIND_ARGS+=("--bind=$p")
  done
}

nspawn_run(){
  systemd-nspawn \
    --directory="${ROOTFS}" --machine="${MACHINE}" \
    --resolv-conf=replace-host --console=pipe --quiet \
    /bin/bash -lc "$*"
}

ensure_host_packages(){
  log "Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…"
  apt-get update -y || true
  apt-get install -y --no-install-recommends \
    debootstrap systemd-container ca-certificates curl gpg \
    v4l2loopback-dkms v4l-utils gstreamer1.0-tools
}

ensure_v4l2loopback(){
  modprobe -r v4l2loopback 2>/dev/null || true
  log "Loading v4l2loopback (1 device) at ${V4L2_NODE}…"
  modprobe v4l2loopback devices=1 exclusive_caps=1 video_nr=0 card_label="Intel MIPI Virtual Camera"
  for i in {1..10}; do [[ -e ${V4L2_NODE} ]] && break; sleep 0.2; done
  [[ -e ${V4L2_NODE} ]] || die "${V4L2_NODE} not present after modprobe"
  log "Host v4l2loopback ready at ${V4L2_NODE}"
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
  install -d -m 0755 "${ROOTFS}/etc/apt/keyrings" "${ROOTFS}/etc/apt/sources.list.d"
  # Base Ubuntu (enable main + universe)
  cat >"${ROOTFS}/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF
  # Clean any old ipu6 PPA list files to avoid duplicates
  rm -f "${ROOTFS}/etc/apt/sources.list.d/"*ipu6*.list || true
  # IPU6 PPA (Noble)
  if ! [ -s "${ROOTFS}/etc/apt/keyrings/ipu6-ppa.gpg" ]; then
    TMPKEY=$(mktemp)
    if curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${PPA_KEY_FP}" -o "${TMPKEY}"; then
      gpg --dearmor < "${TMPKEY}" > "${ROOTFS}/etc/apt/keyrings/ipu6-ppa.gpg"; rm -f "${TMPKEY}"
    else
      gpg --keyserver keyserver.ubuntu.com --recv-keys "${PPA_KEY_FP}"
      gpg --export "${PPA_KEY_FP}" | gpg --dearmor > "${ROOTFS}/etc/apt/keyrings/ipu6-ppa.gpg"
    fi
  fi
  cat >"${ROOTFS}/etc/apt/sources.list.d/intel-ipu6.list" <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF
}

install_userspace_in_container(){
  log "Updating APT metadata inside container…"
  nspawn_run "apt-get update -y"
  log "Installing IPU6 HAL + platform plugin + icamerasrc + tools inside container…"
  nspawn_run "apt-get install -y --no-install-recommends \
    ca-certificates gnupg curl gstreamer1.0-tools v4l-utils \
    libcamhal0 libcamhal-ipu6epmtl gstreamer1.0-icamera"
  # Validate the platform plugin landed where CamHAL expects it
  nspawn_run "test -r /usr/lib/libcamhal/plugins/ipu6epmtl.so" || die "Missing /usr/lib/libcamhal/plugins/ipu6epmtl.so in container"
  # Sanity check plugin registry
  nspawn_run "gst-inspect-1.0 icamerasrc >/dev/null" || die "icamerasrc plugin not found in container"
}

install_wrapper_and_service(){
  log "Installing host wrapper and systemd service…"
  install -D -m 0755 /dev/stdin /usr/local/sbin/ipu6-relay-run <<'WRAP'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOTFS=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
V4L2_NODE=/dev/video0
WIDTH=${WIDTH:-1280}
HEIGHT=${HEIGHT:-720}
FPS=${FPS:-30}
# Build binds
BINDS=()
for p in /dev/video* /dev/media* /dev/v4l-subdev* /dev/mei*; do
  [[ -e "$p" ]] && BINDS+=("--bind=$p")
done
exec systemd-nspawn \
  --directory="${ROOTFS}" --machine="${MACHINE}" \
  --resolv-conf=replace-host --console=pipe \
  "${BINDS[@]}" \
  /bin/bash -lc "exec gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1 ! videoconvert ! video/x-raw,format=YUY2 ! v4l2sink device=${V4L2_NODE} sync=false qos=false"
WRAP

  cat >/etc/systemd/system/ipu6-relay.service <<'UNIT'
[Unit]
Description=Intel IPU6 webcam relay (containerized) -> /dev/video0
After=systemd-udevd.service
Requires=systemd-udevd.service

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/local/sbin/ipu6-relay-run

[Install]
WantedBy=multi-user.target
UNIT

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
  install_wrapper_and_service
  log "Done. Verify with: v4l2-ctl --list-devices (look for \"Intel MIPI Virtual Camera\" at ${V4L2_NODE})"
}

main "$@"
