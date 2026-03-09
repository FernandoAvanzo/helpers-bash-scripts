#!/usr/bin/env bash
set -euo pipefail

log(){ echo -e "[ipu6_install_v15] $*"; }
die(){ echo -e "[ipu6_install_v15][ERROR] $*" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------------
KREL="$(uname -r)"
log "Kernel: $KREL"

# Kernel side check (just warn if not present)
if ! lsmod | grep -q '^intel_ipu6_isys'; then
  log "WARNING: intel_ipu6 modules not listed by lsmod. If this kernel normally loads them, continue; else reboot to 6.16 where they load."
fi

# --- Minimal cleanup of previous camera attempts -----------------------------
log "Sanity cleanup (apt state, leftover diversions, stale loopbacks)…"
sudo apt-get -y update
sudo apt-get -y -o Dpkg::Options::="--force-confnew" -f install || true
# remove only obviously conflicting bits from past libcamera builds
sudo rm -f /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so || true

# Remove any partially installed HAL libs from failed runs (no purge if they’re fine)
sudo apt-get -y autoremove || true

# --- Ensure Intel IPU6 edge PPA & pinning -----------------------------------
PPA_LINE="deb [arch=amd64] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy main"
if ! grep -Rqs "oem-solutions-group/intel-ipu6" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
  log "Adding Intel IPU6 edge PPA…"
  sudo apt-get -y install ca-certificates gnupg curl software-properties-common
  sudo add-apt-repository -y ppa:oem-solutions-group/intel-ipu6
fi

# Strong preference for HAL/icu6 packages from that PPA
PIN_FILE="/etc/apt/preferences.d/99-ipu6-oem-pin"
sudo bash -c "cat > $PIN_FILE" <<'PIN'
Package: ipu6-camera-bins ipu6-camera-hal gstreamer1.0-icamera gst-plugins-icamera libcamhal* libipu6* libia-*
Pin: release o=LP-PPA-oem-solutions-group-intel-ipu6
Pin-Priority: 700
PIN

sudo apt-get update -y

# --- Install v4l2loopback (you already built successfully, keep up to date) --
log "Ensuring v4l2loopback-dkms is installed for this kernel…"
sudo apt-get -y install v4l2loopback-dkms

# --- Try normal APT path first ----------------------------------------------
want_pkgs=(ipu6-camera-bins ipu6-camera-hal gst-plugins-icamera)
missing=()
for p in "${want_pkgs[@]}"; do
  if ! apt-cache policy "$p" | grep -q 'Candidate:'; then
    missing+=("$p")
  fi
done

# Some PPAs ship gstreamer plugin as gstreamer1.0-icamera (older naming)
if apt-cache policy gstreamer1.0-icamera | grep -q 'Candidate:'; then
  want_pkgs=(ipu6-camera-bins ipu6-camera-hal gstreamer1.0-icamera)
fi

log "Attempt APT install of: ${want_pkgs[*]}"
if ! sudo apt-get -y install "${want_pkgs[@]}"; then
  log "APT install failed or packages missing. Falling back to pool download…"

  # --- Pool fallback (scrape latest jammy *.deb from PPA pool) --------------
  TMPD="$(mktemp -d)"; pushd "$TMPD" >/dev/null

  base="https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu/pool"
  # helper to fetch latest matching deb from a subdir
  fetch_latest() {
    # $1 = subdir (e.g. main/g/gst-plugins-icamera) ; $2 = package prefix (e.g. gst-plugins-icamera_)
    local sub="$1" pref="$2"
    local url="${base}/${sub}/"
    local deb
    deb="$(wget -qO- "$url" | grep -oE "${pref}[0-9][^\"']+_amd64\.deb" | sort -V | tail -n1 || true)"
    [ -n "$deb" ] || return 1
    wget -q "${url}${deb}"
  }

  # Try both names for the plugin
  fetch_latest "main/g/gst-plugins-icamera" "gst-plugins-icamera_" || true
  fetch_latest "main/g/gstreamer1.0-icamera" "gstreamer1.0-icamera_" || true
  fetch_latest "main/i/ipu6-camera-bins" "ipu6-camera-bins_" || true
  fetch_latest "main/i/ipu6-camera-hal"  "ipu6-camera-hal_"  || true

  ls -1 *.deb || die "Could not fetch required .debs from the PPA pool. The PPA may be in flux."

  log "Installing downloaded .debs (lets apt resolve the matching libia-* set)…"
  sudo apt-get -y install ./*.deb || die "Installing pool .debs failed."

  popd >/dev/null
  rm -rf "$TMPD"
fi

# --- Verify icamerasrc is visible to GStreamer -------------------------------
if ! gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
  die "icamerasrc plugin not registered. Check gstreamer logs or the PPA health."
fi

# --- Configure v4l2-relayd + loopback ---------------------------------------
log "Configuring v4l2loopback to expose /dev/video-ipu6-relay…"
sudo tee /etc/modprobe.d/ipu6-loopback.conf >/dev/null <<'EOF'
options v4l2loopback devices=1 video_nr=55 card_label="Intel IPU6 (relay)" exclusive_caps=1
EOF
sudo depmod -a
sudo modprobe -r v4l2loopback || true
sudo modprobe v4l2loopback || die "Could not load v4l2loopback."

# v4l2-relayd user service
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/v4l2-relayd.service" <<'SVC'
[Unit]
Description=V4L2 relayd from icamerasrc to /dev/video55
After=default.target

[Service]
Type=simple
ExecStart=/bin/sh -lc 'gst-launch-1.0 -q icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! v4l2sink device=/dev/video55 sync=false'
Restart=on-failure

[Install]
WantedBy=default.target
SVC

systemctl --user daemon-reload
systemctl --user enable --now v4l2-relayd.service

log "Done. Test with: v4l2-ctl --all -d /dev/video55 ; and pick \"Intel IPU6 (relay)\" in apps."
echo "[HINT] If your Samsung has a lens cover hotkey, toggle it (the kernel reported 'Samsung Galaxy Book Camera Lens Cover')."
