#!/usr/bin/env bash
set -euo pipefail

MACHINE=ipu6-noble
ROOT=/var/lib/machines/$MACHINE
PPA_LIST=/etc/apt/sources.list.d/intel-ipu6-ppa.list
PPA_URL="https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu"
SERIES=noble

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" ; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root (sudo)." >&2; exit 1
  fi
}

host_preflight(){
  log "Host preflight checks…"
  # systemd-nspawn + debootstrap
  if ! command -v systemd-nspawn >/dev/null || ! command -v debootstrap >/dev/null; then
    log "Installing host tools (systemd-container, debootstrap, binutils, wget, curl, gpg)…"
    apt-get update -y
    apt-get install -y systemd-container debootstrap binutils wget curl gpg ca-certificates
  fi

  # cgroup v2 status
  if ! mount | grep -q "type cgroup2"; then
    log "[WARN] cgroup v2 not active. nspawn works, but full features need unified cgroup v2."
    log "       To enable: add 'systemd.unified_cgroup_hierarchy=1' to kernel cmdline & reboot."
  fi

  # ipu6 nodes
  if ! ls /dev/video* /dev/media* >/dev/null 2>&1; then
    log "[WARN] No /dev/video* or /dev/media* found. Kernel/IPU6 not exposing nodes."
  else
    log "OK: IPU6 video/media nodes exist."
  fi

  # v4l2loopback
  if ! dpkg -s v4l2loopback-dkms >/dev/null 2>&1; then
    log "Installing v4l2loopback-dkms…"
    apt-get install -y v4l2loopback-dkms
  fi
}

ensure_rootfs(){
  if [[ ! -d $ROOT ]]; then
    log "Creating $SERIES rootfs at $ROOT (debootstrap)…"
    debootstrap --include=ca-certificates,gnupg,gnupg2,dbus,$(printf "%s" gpg) "$SERIES" "$ROOT" http://archive.ubuntu.com/ubuntu
  else
    log "$SERIES rootfs already exists, reusing."
  fi
}

container_sh(){
  # Run a command inside the container with minimal, predictable console.
  local cmd="$*"
  systemd-nspawn \
    --machine="$MACHINE" \
    --directory="$ROOT" \
    --register=no \
    --capability=CAP_SYS_ADMIN \
    --bind=/dev \
    --bind=/run/udev \
    --bind=/sys \
    --bind=/proc \
    --console=pipe \
    /bin/bash -lc "$cmd"
}

prep_container_apt(){
  log "Configuring apt sources inside container…"
  # Write base sources.list to series (avoid old artifacts)
  cat >"$ROOT/etc/apt/sources.list" <<EOF
deb http://archive.ubuntu.com/ubuntu $SERIES main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $SERIES-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $SERIES-security main restricted universe multiverse
EOF

  # Remove any old IPU6 PPA lists (jammy/noble) to avoid mixing
  rm -f "$ROOT"/etc/apt/sources.list.d/*intel-ipu6* 2>/dev/null || true

  # Ensure keyrings dir exists (inside container)
  install -d -m 0755 "$ROOT/etc/apt/keyrings"

  # Install tools and import PPA keys *inside* container; write keyring to container path
  container_sh "apt-get update -y && apt-get install -y ca-certificates curl wget gnupg gpg dirmngr"
  container_sh "
    set -e
    mkdir -p /etc/apt/keyrings
    gpg --keyserver keyserver.ubuntu.com --recv-keys A630CA96910990FF B52B913A41086767
    gpg --export A630CA96910990FF B52B913A41086767 >/etc/apt/keyrings/ipu6-ppa.gpg
    chmod 0644 /etc/apt/keyrings/ipu6-ppa.gpg
  "

  # Add **only** noble IPU6 PPA
  cat >"$ROOT$PPA_LIST" <<EOF
deb [signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] $PPA_URL $SERIES main
EOF

  container_sh "apt-get update -y"
}

install_ipu6_userspace(){
  log "Installing base runtime inside container (GStreamer, v4l)…"
  container_sh "apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-base libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libdrm2 libexpat1 libv4l-0"

  log "Installing Intel IPU6 userspace (noble set) inside container…"
  # Install everything in one go, so APT resolves the exact noble versions together.
  container_sh "
    set -e
    apt-get install -y \
      libipu6 \
      libbroxton-ia-pal0 \
      libgcss0 \
      libia-aiqb-parser0 \
      libia-aiq-file-debug0 \
      libia-aiq0 \
      libia-bcomp0 \
      libia-cca0 \
      libia-ccat0 \
      libia-dvs0 \
      libia-emd-decoder0 \
      libia-exc0 \
      libia-lard0 \
      libia-log0 \
      libia-ltm0 \
      libia-mkn0 \
      libia-nvm0 \
      libcamhal0 libcamhal-common libcamhal-ipu6ep0 \
      gstreamer1.0-icamera
  "
}

create_helpers(){
  log "Creating helper wrappers on host…"
  install -d -m 0755 /usr/local/sbin

  cat >/usr/local/sbin/ipu6-nspawn <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
MACHINE=ipu6-noble
ROOT=/var/lib/machines/$MACHINE
exec systemd-nspawn \
  --machine="$MACHINE" \
  --directory="$ROOT" \
  --register=no \
  --bind=/dev \
  --bind=/run/udev \
  --bind=/sys \
  --bind=/proc \
  --console=read-only \
  /bin/bash -l
EOS
  chmod +x /usr/local/sbin/ipu6-nspawn

  cat >/usr/local/sbin/ipu6-test <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
MACHINE=ipu6-noble
ROOT=/var/lib/machines/$MACHINE
CMD='GST_DEBUG=icamerasrc:3,gstpluginloading:3 gst-inspect-1.0 icamerasrc && GST_DEBUG=icamerasrc:4 gst-launch-1.0 icamerasrc ! fakesink -v'
exec systemd-nspawn \
  --machine="$MACHINE" \
  --directory="$ROOT" \
  --register=no \
  --bind=/dev \
  --bind=/run/udev \
  --bind=/sys \
  --bind=/proc \
  --console=pipe \
  /bin/bash -lc "$CMD"
EOS
  chmod +x /usr/local/sbin/ipu6-test
}

smoke_test(){
  log "Smoke test: gst-inspect icamerasrc inside container…"
  set +e
  if ! ipu6-test >/tmp/ipu6-test.log 2>&1; then
    log "[WARN] icamerasrc test did not fully succeed. See /tmp/ipu6-test.log"
  else
    log "icamerasrc loaded in the container."
  fi
  set -e
}

main(){
  require_root
  host_preflight
  ensure_rootfs
  prep_container_apt
  install_ipu6_userspace
  create_helpers
  smoke_test
  log "Done. Use 'ipu6-nspawn' for a shell, or 'ipu6-test' to try the camera pipeline."
}

main "$@"
