#!/usr/bin/env bash
set -euo pipefail

log() { printf "[ipu6_install_v16] %s\n" "$*" >&2; }
die() { printf "[ipu6_install_v16][ERROR] %s\n" "$*" >&2; exit 1; }

RELEASE_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
KERNEL="$(uname -r)"

# Packages we actually need from the Intel IPU6 PPA
PKGS_ICAMERA=(gstreamer1.0-icamera libcamhal-ipu6ep0 libcamhal0 libcamhal-common)
# GStreamer plumbing & tools
PKGS_GST=(gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-base gstreamer1.0-plugins-bad)
# v4l2loopback kernel module
PKG_LOOP=v4l2loopback-dkms

VLOOP_NR=9
VLOOP_LABEL="MIPI Camera (icamera)"
SERVICE_NAME="icamera-virtualcam.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

require_root() { [[ $EUID -eq 0 ]] || die "Run as root (sudo)."; }

apt_ok() {
  command -v apt-get >/dev/null || die "APT not found."
  apt-get update -o Acquire::Retries=3 -o Acquire::http::No-Cache=true >/dev/null
}

ensure_basic_tools() {
  apt-get install -y --no-install-recommends ca-certificates curl gnupg software-properties-common
}

sanity_cleanup() {
  log "Sanity cleanup (dpkg/apt state, stale loopbacks)…"
  # Fix half-configured packages if any
  dpkg --configure -a || true
  apt-get -f install -y || true
  # Unload any lingering loopback devices so we can reload with our params
  if lsmod | grep -q '^v4l2loopback'; then
    modprobe -r v4l2loopback || true
  fi
}

ensure_ppas() {
  # Intel IPU6 PPA (official)
  if ! grep -Rqs "oem-solutions-group/intel-ipu6" /etc/apt/; then
    log "Adding Intel IPU6 PPA…"
    add-apt-repository -y ppa:oem-solutions-group/intel-ipu6
  fi
  apt-get update
}

have_pkg() { dpkg -s "$1" >/dev/null 2>&1; }

install_pkgs_if_missing() {
  local to_install=()
  for p in "$@"; do
    have_pkg "$p" || to_install+=("$p")
  done
  if ((${#to_install[@]})); then
    log "Installing: ${to_install[*]}"
    apt-get install -y "${to_install[@]}"
  else
    log "All requested packages already present."
  fi
}

check_kernel_ready() {
  # We won't fail if lsmod is empty yet (some kernels autoload on first open),
  # but we do a friendly hint.
  if ! grep -qE 'intel_ipu6' < <(lsmod || true); then
    log "WARNING: intel_ipu6 modules not shown by lsmod; if this kernel normally loads them on demand, it's OK."
  fi
  # Must see media controller
  [[ -e /dev/media0 ]] || log "WARNING: /dev/media0 missing; if camera is disabled by a privacy switch, enable it and reboot."
}

install_userspace() {
  install_pkgs_if_missing "${PKGS_GST[@]}"
  # Try Intel PPA packages; only install what the PPA actually provides
  local found_any=false
  for p in "${PKGS_ICAMERA[@]}"; do
    if apt-cache policy "$p" | grep -q oem-solutions-group; then
      found_any=true
      install_pkgs_if_missing "$p"
    fi
  done
  $found_any || die "Intel IPU6 PPA reachable but expected packages not published for ${RELEASE_CODENAME}. Try later."
}

verify_icamerasrc() {
  if ! command -v gst-inspect-1.0 >/dev/null; then
    die "gst-inspect-1.0 missing (gstreamer1.0-tools should provide it)."
  fi
  if ! gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
    die "icamerasrc plugin not found. Ensure 'gstreamer1.0-icamera' installed from the Intel IPU6 PPA."
  fi
  log "icamerasrc detected."
}

ensure_v4l2loopback() {
  install_pkgs_if_missing "$PKG_LOOP"
  # Load with predictable node and browser-friendly caps
  modprobe v4l2loopback video_nr="${VLOOP_NR}" exclusive_caps=1 card_label="${VLOOP_LABEL}" || true
}

write_service() {
  cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Intel IPU6 icamerasrc -> v4l2loopback virtual camera
After=multi-user.target
StartLimitIntervalSec=20

[Service]
Type=simple
Environment=GST_DEBUG=0
ExecStartPre=/sbin/modprobe v4l2loopback video_nr=${VLOOP_NR} exclusive_caps=1 card_label="${VLOOP_LABEL}"
# 720p@30 in YUY2 (browser-friendly). Adjust width/height if needed.
ExecStart=/usr/bin/gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! queue leaky=2 max-size-buffers=2 ! v4l2convert n-threads=2 ! video/x-raw,format=YUY2 ! v4l2sink device=/dev/video${VLOOP_NR} sync=false
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}"
}

print_postcheck() {
  cat <<'EOT'
Post-checks you can run now:
  # 1) Confirm plugin is present
  gst-inspect-1.0 icamerasrc | head -n 5

  # 2) See the new virtual webcam
  v4l2-ctl --list-devices | sed -n '/loopback/,+5p'
  v4l2-ctl --all -d /dev/video9 | sed -n '1,20p'

  # 3) Quick live preview (optional)
  gst-launch-1.0 -v icamerasrc ! videoconvert ! autovideosink
EOT
}

main() {
  require_root
  log "Kernel: ${KERNEL}"
  apt_ok
  ensure_basic_tools
  sanity_cleanup
  check_kernel_ready
  ensure_ppas
  install_userspace
  verify_icamerasrc
  ensure_v4l2loopback
  write_service
  log "Done. Open a browser and pick the camera named: ${VLOOP_LABEL}"
  print_postcheck
}

main "$@"
