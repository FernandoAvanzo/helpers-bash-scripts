#!/usr/bin/env bash
set -euo pipefail

log(){ printf "[ipu6_install_v17] %s\n" "$*"; }
die(){ printf "[ipu6_install_v17][ERROR] %s\n" "$*" >&2; exit 1; }

need_root(){ [ "$(id -u)" -eq 0 ] || die "Run as root"; }

# Return highest GLIBCXX symbol found in current libstdc++
glibcxx_max() {
  local so="/usr/lib/x86_64-linux-gnu/libstdc++.so.6"
  [ -e "$so" ] || so="/lib/x86_64-linux-gnu/libstdc++.so.6"
  [ -e "$so" ] || return 1
  strings -a "$so" | sed -n 's/^.*\(GLIBCXX_[0-9.]\+\).*$/\1/p' | sort -V | tail -n1
}

ensure_apt_clean(){
  log "Sanity cleanup (apt state, diversions, stale loopbacks)…"
  apt-get -y -o Dpkg::Options::=--force-confnew update >/dev/null 2>&1 || true
  dpkg --configure -a || true
  apt-get -f install -y || true
  # Remove any left-over v4l2loopback nodes created by old services
  pkill -f "gst-launch-1.0.*icamerasrc" 2>/dev/null || true
  rmmod v4l2loopback 2>/dev/null || true
}

ensure_toolchain_libstdcxx(){
  local need="GLIBCXX_3.4.32"
  local have
  have="$(glibcxx_max || echo "none")"
  log "libstdc++ GLIBCXX max on system: ${have}"
  if [ "$have" != "none" ] && [ "$(printf "%s\n%s\n" "$need" "$have" | sort -V | tail -1)" = "$have" ]; then
    log "libstdc++ is new enough (>= ${need})."
    return 0
  fi

  log "Adding Ubuntu Toolchain PPA for newer libstdc++6 (safe runtime upgrade on 22.04)…"
  apt-get update -y >/dev/null
  apt-get install -y --no-install-recommends software-properties-common ca-certificates curl gnupg
  add-apt-repository -y ppa:ubuntu-toolchain-r/test
  apt-get update -y
  log "Upgrading libstdc++6 …"
  apt-get install -y libstdc++6

  local after
  after="$(glibcxx_max || echo "none")"
  log "libstdc++ after upgrade: ${after}"
  if [ "$after" = "none" ] || [ "$(printf "%s\n%s\n" "$need" "$after" | sort -V | tail -1)" != "$after" ]; then
    die "libstdc++ still too old (need ${need}). Consider upgrading Pop!_OS base or pulling libstdc++6 from Noble."
  fi
}

ensure_intel_ipa(){
  # You already have this PPA configured and HAL installed (v16 worked).
  # We still refresh to ensure packages are present; we do NOT force re-install if already OK.
  log "Ensuring Intel IPU6 OEM userspace (HAL + icamerasrc) is present…"
  apt-get update -y
  # Try both names seen in the PPA
  apt-get install -y --no-install-recommends \
    gstreamer1.0-icamera || apt-get install -y gstreamer1.0-icamerasrc || true

  # HAL bits (if not already installed)
  apt-get install -y --no-install-recommends \
    libcamhal-common libcamhal0 libcamhal-ipu6ep0 libipu6 libbroxton-ia-pal0 || true
}

ipu6_kernel_ready(){
  if lsmod | grep -qE '^intel_ipu6(_isys)?\b'; then return 0; fi
  dmesg | grep -q "intel-ipu6 .*Connected 1 cameras" && return 0
  return 1
}

ensure_v4l2loopback(){
  log "Ensuring v4l2loopback-dkms is installed for $(uname -r)…"
  apt-get install -y --no-install-recommends v4l2loopback-dkms
  # Load with a stable label; do NOT force a number to avoid clashes.
  log "Loading v4l2loopback module…"
  modprobe v4l2loopback exclusive_caps=1 card_label="Intel IPU6 Virtual Camera" || true
}

find_loopback_device(){
  # Find /dev/videoX whose name (card) matches our label
  for n in /sys/class/video4linux/video*/name; do
    [ -e "$n" ] || continue
    if grep -q "Intel IPU6 Virtual Camera" "$n"; then
      echo "/dev/$(basename "$(dirname "$n")")"
      return 0
    fi
  done
  # fallback: highest video node (better than nothing)
  ls -1 /dev/video* 2>/dev/null | sort -V | tail -n1
}

icamerasrc_ok(){
  # Will fail hard if HAL can’t load; we suppress noise, just want exit code.
  GST_DEBUG=0 gst-inspect-1.0 icamerasrc >/dev/null 2>&1
}

start_preview(){
  local sink="${1:-autovideosink}"
  log "Starting a 10s preview to ${sink} to verify end-to-end userspace…"
  timeout 10 gst-launch-1.0 -q icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 \
    ! videoconvert ! "${sink}" || true
}

start_loopback_pipeline(){
  local dev="$1"
  log "Starting background pipeline into ${dev}… (Ctrl+C will not kill it; use: systemctl stop ipu6-vircam)"
  install -d /etc/ipu6
  printf "DEVICE=%s\n" "$dev" > /etc/ipu6/vircam.conf

  cat >/etc/systemd/system/ipu6-vircam.service <<'EOF'
[Unit]
Description=Intel IPU6 -> v4l2loopback virtual camera
After=multi-user.target

[Service]
Type=simple
EnvironmentFile=/etc/ipu6/vircam.conf
ExecStart=/usr/bin/gst-launch-1.0 -e icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! queue ! v4l2sink device=${DEVICE}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now ipu6-vircam.service
}

main(){
  need_root
  log "Kernel: $(uname -r)"
  ensure_apt_clean

  if ! ipu6_kernel_ready; then
    die "IPU6 kernel modules aren’t active. Reboot into the kernel where they load (your 6.16.x does)."
  fi

  # 1) Fix the blocker: outdated libstdc++ (GLIBCXX)
  ensure_toolchain_libstdcxx

  # 2) Make sure Intel HAL/icamerasrc are present
  ensure_intel_ipa

  # 3) Confirm icamerasrc can load now (HAL + stdc++)
  if ! icamerasrc_ok; then
    die "icamerasrc still fails to load. Re-run and attach output of: GST_DEBUG=DEFAULT gst-inspect-1.0 icamerasrc"
  fi
  log "icamerasrc loaded successfully."

  # 4) v4l2loopback device with a stable label
  ensure_v4l2loopback
  local dev
  dev="$(find_loopback_device)"
  [ -n "$dev" ] || die "Could not locate v4l2loopback device."

  log "Virtual camera device: ${dev}"
  # Quick smoke test to a window (you should see video if shutter is open)
  start_preview autovideosink

  # 5) Launch the always-on pipeline into the loopback device
  start_loopback_pipeline "$dev"

  log "Done. Check with: v4l2-ctl --list-devices | sed -n '/Intel IPU6 Virtual Camera/,+5p'"
  log "And try Meet/Zoom selecting: Intel IPU6 Virtual Camera"
}

main "$@"
