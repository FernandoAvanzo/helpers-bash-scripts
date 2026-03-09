#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/var/lib/machines/ipu6-noble
MACHINE=ipu6-noble
PPA_URL="https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu"
# Two Launchpad short key IDs used by this PPA (import both)
PPA_KEYS=("A630CA96910990FF" "B52B913A41086767")

die(){ echo "[FATAL] $*" >&2; exit 1; }
log(){ echo "[ipu6_install_v41] $*"; }

need_root(){ [[ $EUID -eq 0 ]] || die "Run as root (sudo)."; }

host_preflight(){
  log "Kernel: $(uname -r)"
  command -v systemd-nspawn >/dev/null || die "systemd-nspawn not installed. apt-get install -y systemd-container"
  command -v debootstrap >/dev/null || die "debootstrap not installed. apt-get install -y debootstrap"
  # cgroup v2 check (nspawn works best)
  if ! grep -qw unified /proc/filesystems; then
    echo "[WARN] cgroup v2 not listed; systemd-nspawn may still work but full features require cgroup v2."
  fi
  mkdir -p /var/lib/machines
  # camera nodes
  if ! ls /dev/video* /dev/media* >/dev/null 2>&1; then
    echo "[WARN] No /dev/video* or /dev/media* found. Kernel/IPU6 might not be ready."
  else
    log "OK: video/media nodes exist."
  fi
  # v4l2loopback present?
  if ! modinfo v4l2loopback >/dev/null 2>&1; then
    log "Ensuring v4l2loopback-dkms on host…"
    apt-get update -y >/dev/null || true
    apt-get install -y v4l2loopback-dkms >/dev/null || echo "[WARN] Could not install v4l2loopback-dkms"
  fi
}

mk_rootfs(){
  if [[ -e "$ROOT" && -d "$ROOT" && -f "$ROOT/etc/os-release" ]]; then
    log "Noble rootfs already exists, reusing."
    return
  fi
  log "Creating Noble rootfs at $ROOT (this can take a minute)…"
  debootstrap --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu || die "debootstrap failed"
}

container_write_sources(){
  log "Configuring apt sources inside container…"
  cat >"$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main universe multiverse
EOF

  # Use the IPU6 PPA's Jammy series inside Noble container (more complete IPU6 userspace)
  mkdir -p "$ROOT/etc/apt/sources.list.d"
  cat >"$ROOT/etc/apt/sources.list.d/ipu6-ppa.list" <<EOF
deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/ipu6-ppa.gpg] $PPA_URL jammy main
EOF
}

container_import_keys(){
  log "Importing Intel IPU6 PPA keys inside container…"
  mkdir -p "$ROOT/etc/apt/trusted.gpg.d"
  rm -f "$ROOT/etc/apt/trusted.gpg.d/ipu6-ppa.gpg"
  tmpd="$(mktemp -d)"
  for k in "${PPA_KEYS[@]}"; do
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${k}" \
      | gpg --dearmor >"$tmpd/$k.gpg" || die "Failed fetching key $k"
  done
  # merge both into one keyring file
  cat "$tmpd"/*.gpg >"$ROOT/etc/apt/trusted.gpg.d/ipu6-ppa.gpg"
  rm -rf "$tmpd"
}

container_apt_update(){
  log "Running apt-get update inside container…"
  systemd-nspawn -D "$ROOT" --quiet \
    /bin/sh -c "apt-get update -y" \
    || die "apt update failed inside container (check network/keys)"
}

container_install_base(){
  log "Installing base runtime (gstreamer, v4l utils) inside container…"
  systemd-nspawn -D "$ROOT" --quiet \
    /bin/sh -c "apt-get install -y --no-install-recommends ca-certificates curl wget \
                gpg dirmngr gnupg \
                libdrm2 libexpat1 libv4l-0 gstreamer1.0-tools gstreamer1.0-plugins-base \
                libgstreamer1.0-0 libgstreamer-plugins-base1.0-0" \
    || die "base packages failed"
}

container_install_ipu6(){
  log "Installing Intel IPU6 userspace & GStreamer inside container…"
  # Try full meta first
  if ! systemd-nspawn -D "$ROOT" --quiet /bin/sh -lc \
    "apt-get install -y --no-install-recommends \
       libipu6 libbroxton-ia-pal0 libgcss0 \
       libia-aiqb-parser0 libia-aiq-file-debug0 libia-aiq0 libia-bcomp0 libia-cca0 libia-ccat0 \
       libia-dvs0 libia-emd-decoder0 libia-exc0 libia-lard0 libia-log0 libia-ltm0 libia-mkn0 libia-nvm0 \
       libcamhal-common libcamhal-ipu6ep0 libcamhal0 gstreamer1.0-icamera"; then
    echo "[WARN] First attempt failed; retrying with packages that sometimes have '0i' suffix in this PPA…"
    systemd-nspawn -D "$ROOT" --quiet /bin/sh -lc \
      "apt-get install -y --no-install-recommends \
       libipu6 libbroxton-ia-pal0 libgcss0 \
       libia-aiqb-parser0 libia-aiq-file-debug0 libia-aiq0 libia-bcomp0 libia-cca0 libia-ccat0 \
       libia-dvs0 libia-emd-decoder0 libia-exc0 libia-lard0 libia-log0 libia-ltm0 libia-mkn0 libia-nvm0 \
       libia-cmc-parser0i libia-coordinate0i libia-isp-bxt0i || true; \
       apt-get -y -f install; \
       apt-get install -y --no-install-recommends libcamhal-common libcamhal-ipu6ep0 libcamhal0 gstreamer1.0-icamera" \
      || die "IPU6 userspace install failed (PPA state?)"
  fi
}

make_wrappers(){
  log "Creating helper wrappers…"
  cat >/usr/local/bin/ipu6-nspawn <<EOF
#!/usr/bin/env bash
set -e
ROOT="$ROOT"
exec systemd-nspawn -M "$MACHINE" -D "\$ROOT" \\
  --bind=/dev \\
  --bind=/run \\
  --bind=/tmp/.X11-unix \\
  --setenv=DISPLAY=\${DISPLAY:-:0} \\
  /bin/bash -l
EOF
  chmod +x /usr/local/bin/ipu6-nspawn

  cat >/usr/local/bin/ipu6-test <<'EOF'
#!/usr/bin/env bash
set -e
ROOT="/var/lib/machines/ipu6-noble"
CMD=${1:-inspect}
if [[ "$CMD" == "inspect" ]]; then
  exec systemd-nspawn -M ipu6-noble -D "$ROOT" --bind=/dev --quiet \
    /bin/bash -lc 'gst-inspect-1.0 icamerasrc || exit 1'
else
  exec systemd-nspawn -M ipu6-noble -D "$ROOT" --bind=/dev --quiet \
    /bin/bash -lc 'gst-launch-1.0 icamerasrc ! fakesink -v'
fi
EOF
  chmod +x /usr/local/bin/ipu6-test
}

smoke_test(){
  log "Smoke test inside container (gst-inspect icamerasrc)…"
  if ! /usr/local/bin/ipu6-test inspect; then
    echo "[WARN] icamerasrc failed to load. Check container apt output for missing deps."
  else
    log "icamerasrc loads in the container. Try: ipu6-test run"
  fi
}

main(){
  need_root
  host_preflight
  mk_rootfs
  container_write_sources
  container_import_keys
  container_apt_update
  container_install_base
  container_install_ipu6
  make_wrappers
  smoke_test
  log "Done. Use:  ipu6-nspawn   (shell in container with /dev bound)"
  log "      or:   ipu6-test run  (quick camera pipeline to fakesink)"
}
main "$@"
