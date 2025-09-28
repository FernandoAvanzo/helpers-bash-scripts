#!/usr/bin/env bash
# ipu6_install_v21.sh
set -Eeuo pipefail

LOG="/var/log/ipu6_install_v21.$(date +%F_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
log(){ echo "[ipu6_install_v21] $*"; }
die(){ echo "[ipu6_install_v21][ERROR] $*" >&2; exit 1; }

PPA_BASE="https://ppa.launchpadcontent.net/ubuntu-toolchain-r/test/ubuntu"
INDEX_URL="$PPA_BASE/dists/jammy/main/binary-amd64/Packages"
OVERLAY_DIR="/opt/ipu6-stdcpp-overlay"
WRAP="/usr/local/bin/ipu6-env"
CONF="/etc/profile.d/ipu6-stdcpp.sh"

log "Kernel: $(uname -r)"

# 0) Sanity: dpkg/apt OK and base tools (binutils for 'strings')
log "Sanity cleanup (dpkg/apt)…"
apt-get -y -o Dpkg::Options::=--force-confnew update >/dev/null || true
apt-get -y install ca-certificates curl wget gstreamer1.0-tools v4l-utils binutils >/dev/null

# 1) Make sure v4l2loopback is present (safe no-op if already there)
log "Ensuring v4l2loopback-dkms is installed and module present…"
DEBIAN_FRONTEND=noninteractive apt-get -y install v4l2loopback-dkms || true
modprobe v4l2loopback || true

# 2) Leave the Intel HAL and icamerasrc alone if already installed (they are on your box).
log "Leaving Intel HAL/icamerasrc as-is (already installed)."

# 3) Build/refresh a libstdc++ overlay that actually has GLIBCXX_3.4.32
log "Fetching PPA index and selecting the newest Jammy libstdc++6…"
PKGS=$(curl -fsSL "$INDEX_URL") || die "Cannot fetch $INDEX_URL"

# Pull every stanza for Package: libstdc++6 (amd64), keep Version + Filename
BEST_VER=""
BEST_FILE=""
while IFS= read -r stanza; do
  pkg=$(grep -m1 '^Package: ' <<<"$stanza" | awk '{print $2}')
  arch=$(grep -m1 '^Architecture: ' <<<"$stanza" | awk '{print $2}')
  [[ "$pkg" != "libstdc++6" || "$arch" != "amd64" ]] && continue
  ver=$(grep -m1 '^Version: ' <<<"$stanza" | sed 's/^Version: //')
  file=$(grep -m1 '^Filename: ' <<<"$stanza" | sed 's/^Filename: //')
  [[ -z "$ver" || -z "$file" ]] && continue
  if [[ -z "$BEST_VER" ]] || dpkg --compare-versions "$ver" gt "$BEST_VER"; then
    BEST_VER="$ver"
    BEST_FILE="$file"
  fi
done < <(awk 'BEGIN{RS=""; ORS="\n\n"} {print}' <<<"$PKGS")

[[ -n "$BEST_VER" && -n "$BEST_FILE" ]] || die "Could not find libstdc++6 in the PPA for Jammy."

log "Selected libstdc++6 $BEST_VER from PPA."
TMP_DEB="/tmp/libstdcpp6_${BEST_VER//[^0-9A-Za-z.+~-]/_}.deb"
wget -qO "$TMP_DEB" "$PPA_BASE/$BEST_FILE" || die "Download failed: $PPA_BASE/$BEST_FILE"

log "Extracting into overlay: $OVERLAY_DIR"
rm -rf "$OVERLAY_DIR"
mkdir -p "$OVERLAY_DIR"
dpkg-deb -x "$TMP_DEB" "$OVERLAY_DIR"

LIBCXX="$OVERLAY_DIR/usr/lib/x86_64-linux-gnu/libstdc++.so.6"
[[ -f "$LIBCXX" ]] || die "Overlay libstdc++.so.6 not found after extraction."

if strings -a "$LIBCXX" | grep -q 'GLIBCXX_3\.4\.32'; then
  log "Overlay libstdc++ exports GLIBCXX_3.4.32 ✔"
else
  die "Selected libstdc++ ($BEST_VER) still lacks GLIBCXX_3.4.32."
fi

# 4) Session wrapper: point apps at the overlay libstdc++
log "Installing wrapper ($WRAP) and session profile ($CONF)…"
cat >/etc/profile.d/ipu6-stdcpp.sh <<'EOF'
# Prefer the IPU6 libstdc++ overlay when present (keeps system files untouched).
if [ -d /opt/ipu6-stdcpp-overlay/usr/lib/x86_64-linux-gnu ]; then
  export LD_LIBRARY_PATH="/opt/ipu6-stdcpp-overlay/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
fi
EOF

cat >"$WRAP" <<'EOF'
#!/usr/bin/env bash
# Run a command with the IPU6 libstdc++ overlay preloaded.
export LD_LIBRARY_PATH="/opt/ipu6-stdcpp-overlay/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
exec "$@"
EOF
chmod +x "$WRAP"

# 5) Quick health hints (don’t fail the script if these are missing)
log "Kernel devices present:"
ls /dev/video* /dev/media* 2>/dev/null || true

log "Done. Next steps:"
cat <<'EOS'
  • Open a new shell (to pick up /etc/profile.d/ipu6-stdcpp.sh), or use the wrapper:
      ipu6-env gst-inspect-1.0 icamerasrc | head
  • Then try a minimal pipeline:
      ipu6-env gst-launch-1.0 -v icamerasrc ! videoconvert ! autovideosink
  • If a browser needs a /dev/videoX sink, load v4l2loopback first:
      sudo modprobe v4l2loopback exclusive_caps=1 video_nr=10 card_label="Virtual Camera"
EOS
