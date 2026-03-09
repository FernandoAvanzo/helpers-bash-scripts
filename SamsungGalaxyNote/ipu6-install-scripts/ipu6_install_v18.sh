#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf "[ipu6_install_v18] %s\n" "$*" >&2; }
die() { printf "[ipu6_install_v18][ERROR] %s\n" "$*" >&2; exit 1; }

require_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || die "Run as root (sudo)."; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# --- Readiness checks that don't rely solely on lsmod ---
ipu6_ready() {
  # 1) A media graph exists and belongs to intel-ipu6, or
  # 2) v4l2-ctl shows an ipu6 card with multiple nodes.
  if have_cmd v4l2-ctl; then
    if v4l2-ctl --list-devices 2>/dev/null | grep -qi '^ipu6'; then
      return 0
    fi
  fi
  # Fallback: a /dev/media0 exists and is claimed by intel-ipu6
  if have_cmd media-ctl && [ -e /dev/media0 ]; then
    if media-ctl -p -d /dev/media0 2>/dev/null | grep -qi 'driver.*intel-ipu6'; then
      return 0
    fi
  fi
  # Last fallback: dmesg evidence from this boot
  if dmesg | grep -qiE 'intel-ipu6.*(Connected .* cameras|CSE authenticate_run done)'; then
    return 0
  fi
  return 1
}

# --- Minimal "tail-chasing" cleanup ---
sanity_cleanup() {
  log "Sanity cleanup (apt state, diversions, stale loopbacks, cache)…"
  DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confnew -f install || true
  dpkg --configure -a || true

  # Remove known conflicts: community libcamera GStreamer plugin (we use Intel's icamerasrc stack)
  if dpkg -l | awk '$1 ~ /^ii/ && $2 ~ /^gstreamer1.0-libcamera$/ {found=1} END {exit !found}'; then
    DEBIAN_FRONTEND=noninteractive apt-get -y remove --purge gstreamer1.0-libcamera || true
  fi

  # Clear per-user GStreamer registry so a stale cache doesn't mask new plugins
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    su - "$SUDO_USER" -c 'rm -f ~/.cache/gstreamer-1.0/registry.*' || true
  fi
}

add_repo_if_missing() {
  local ppa="$1"
  if ! grep -Rqs "ppa.launchpadcontent.net/${ppa#ppa:}" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
    log "Adding PPA: $ppa"
    add-apt-repository -y "$ppa"
  else
    log "PPA already present: $ppa"
  fi
}

install_base_tools() {
  log "Installing base tools…"
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl gnupg software-properties-common \
    v4l-utils gstreamer1.0-tools gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    media-utils || true
}

install_ipu6_userspace() {
  log "Ensuring Intel IPU6 OEM PPA & userspace (HAL + icamerasrc)…"
  add_repo_if_missing ppa:oem-solutions-group/intel-ipu6
  DEBIAN_FRONTEND=noninteractive apt-get update -y

  # Try to install HAL + icamerasrc. Package names come from Intel's PPA.
  # Some days the PPA is in flux; install what exists and continue.
  local pkgs=(
    gstreamer1.0-icamera
    libcamhal0
    libcamhal-common
    libcamhal-ipu6ep0
    libipu6
  )
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" || true
}

install_newer_libstdcpp() {
  log "Installing newer libstdc++ (for GLIBCXX_3.4.32)…"
  add_repo_if_missing ppa:ubuntu-toolchain-r/test
  # Pin only libstdc++6 from the toolchain PPA to avoid pulling the whole GCC stack.
  install -Dm644 /dev/stdin /etc/apt/preferences.d/99-libstdcpp-toolchain <<'PIN'
Package: libstdc++6
Pin: release o=LP-PPA-ubuntu-toolchain-r*
Pin-Priority: 700
PIN
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confnew libstdc++6

  if ! strings /usr/lib/x86_64-linux-gnu/libstdc++.so.6 | grep -q 'GLIBCXX_3\.4\.32'; then
    die "libstdc++6 did not provide GLIBCXX_3.4.32. Aborting."
  fi
}

ensure_v4l2loopback() {
  log "Installing & loading v4l2loopback (virtual camera)…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms
  # Load (idempotent). Use exclusive_caps to satisfy browsers, give a friendly label.
  modprobe -r v4l2loopback 2>/dev/null || true
  modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Virtual Camera"
}

post_checks() {
  log "Post-install checks…"
  # 1) icamerasrc must now be discoverable
  if ! gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
    die "GStreamer can't find icamerasrc (HAL still not loading)."
  fi
  # 2) HAL plugin for Meteor Lake should now load without GLIBCXX error
  if gst-inspect-1.0 icamerasrc 2>&1 | grep -q 'GLIBCXX_3\.4\.32.*not found'; then
    die "HAL still failing to load due to GLIBCXX. libstdc++ upgrade didn’t take."
  fi

  # 3) We should have a v4l2loopback device now
  if ! v4l2-ctl --list-devices | grep -q "Virtual Camera"; then
    die "v4l2loopback device missing."
  fi
}

main() {
  require_root
  log "Kernel: $(uname -r)"

  install_base_tools
  sanity_cleanup

  # Do NOT hard-fail if lsmod doesn’t show intel_ipu6 modules; trust device nodes/media graph.
  if ! ipu6_ready; then
    log "WARNING: IPU6 devices not enumerated yet. Continuing (userspace fix still applies)…"
  else
    log "IPU6 devices present; proceeding with userspace setup."
  fi

  install_ipu6_userspace
  install_newer_libstdcpp
  ensure_v4l2loopback
  post_checks

  cat <<'EONOTES'
[ipu6_install_v18] Success.

Quick tests you can run as your desktop user:

  # 1) Verify icamerasrc loads cleanly
  gst-inspect-1.0 icamerasrc | head -n 40

  # 2) Try a preview window
  gst-launch-1.0 -v icamerasrc ! videoconvert ! autovideosink

  # 3) Publish to the virtual /dev/video10 for apps (Chrome/Zoom/etc.)
  #    v4l2sink prefers fixed-rate video; force a sane format:
  gst-launch-1.0 -v icamerasrc \
      ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 \
      ! videoconvert ! videorate \
      ! v4l2sink device=/dev/video10 sync=false

Then select “Virtual Camera” in your app.

If you still see GLib/GObject warnings from icamerasrc:
 - Reboot once (ensures new libstdc++ is in every process),
 - And delete your user’s GStreamer cache: rm ~/.cache/gstreamer-1.0/registry.*
EONOTES
}

main "$@"
