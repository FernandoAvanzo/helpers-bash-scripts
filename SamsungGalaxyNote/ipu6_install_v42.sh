#!/usr/bin/env bash
set -Eeuo pipefail

# ---- tiny logger -------------------------------------------------------------
ts() { date +"%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(ts)] $*"; }
fail(){ echo "[$(ts)] [FATAL] $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then fail "Run as root (sudo)."; fi

MACHINE=ipu6-noble
ROOT=/var/lib/machines/$MACHINE

# ---- host checks -------------------------------------------------------------
log "Kernel: $(uname -r)"
if ! command -v systemd-nspawn >/dev/null; then
  apt-get update -y
  apt-get install -y systemd-container debootstrap || fail "install systemd-container failed"
fi
if ! command -v debootstrap >/dev/null; then
  apt-get update -y
  apt-get install -y debootstrap || fail "install debootstrap failed"
fi

# cgroup v2 check (not fatal, but warn)
if [[ "$(stat -fc %T /sys/fs/cgroup || true)" != "cgroup2fs" ]]; then
  echo "[WARN] Host is not on unified cgroup v2. systemd-nspawn works in hybrid,"
  echo "       but you may want to enable cgroup v2 (kernel param: systemd.unified_cgroup_hierarchy=1)."
fi

# base tools helpful on host
apt-get install -y binutils v4l-utils gstreamer1.0-tools >/dev/null

# v4l2loopback on host -> /dev/video42 (stable id for apps)
modprobe v4l2loopback || true
if ! lsmod | grep -q '^v4l2loopback'; then
  apt-get install -y v4l2loopback-dkms || true
  modprobe v4l2loopback || true
fi
if ! [ -e /dev/video42 ]; then
  rmmod v4l2loopback 2>/dev/null || true
  modprobe v4l2loopback video_nr=42 card_label=IPU6Bridge exclusive_caps=1
fi
log "Host v4l2loopback ready at $(ls -1 /dev/video42 2>/dev/null || echo '(missing)')"

# ---- create/reuse container rootfs ------------------------------------------
if ! [ -d "$ROOT" ]; then
  log "Creating Noble rootfs at $ROOT (debootstrap)…"
  debootstrap --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu || fail "debootstrap failed"
else
  log "Noble rootfs already exists, reusing."
fi

# ---- apt sources inside the container (Noble ONLY) --------------------------
log "Configuring apt sources inside container…"
cat >"$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF

install -d -m 0755 "$ROOT/etc/apt/keyrings"
# Intel IPU6 PPA noble — keys (two fingerprints are used by that PPA)
chroot "$ROOT" /bin/bash -c '
set -e
apt-get update -y
apt-get install -y ca-certificates curl gnupg
KEYR=/etc/apt/keyrings/ipu6-ppa.gpg
for K in A630CA96910990FF B52B913A41086767; do
  gpg --keyserver keyserver.ubuntu.com --recv-keys "$K"
done
gpg --export A630CA96910990FF B52B913A41086767 | gpg --dearmor >/tmp/ipu6-ppa.gpg
install -m 0644 /tmp/ipu6-ppa.gpg '"$ROOT"'/etc/apt/keyrings/ipu6-ppa.gpg
'

cat >"$ROOT/etc/apt/sources.list.d/intel-ipu6-ppa.list" <<'EOF'
deb [signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

# IMPORTANT: no jammy entry in the container – prevents version/name mismatch.

# ---- update & dist-upgrade --------------------------------------------------
log "Updating container apt & dist-upgrade (handles t64 transitions)…"
chroot "$ROOT" apt-get update -y
DEBIAN_FRONTEND=noninteractive chroot "$ROOT" apt-get -o Dpkg::Options::=--force-confnew -y dist-upgrade

# ---- base runtime inside container -----------------------------------------
log "Installing runtime tools (GStreamer, V4L) inside container…"
chroot "$ROOT" apt-get install -y \
  libdrm2 libexpat1 libv4l-0t64 v4l-utils \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  libgstreamer1.0-0 libgstreamer-plugins-base1.0-0

# ---- IPU6 userspace from the Noble PPA (renamed packages) ------------------
# We DO NOT use the old meta "libipu6" because its deps reference old names.
log "Installing Intel IPU6 userspace (Noble naming)…"
IPU_PKGS=(
  libcamhal-common
  libcamhal0
  libcamhal-ipu6ep0
  gstreamer1.0-icamera

  # core IPA/AIQ/GCSS PAL etc. (Noble renamed to *-ipu6-*)
  libbroxton-ia-pal-ipu6epmtl0
  libgcss-ipu6-0
  libia-aiqb-parser-ipu6-0
  libia-aiq-file-debug-ipu6-0
  libia-aiq-ipu6-0
  libia-bcomp-ipu6-0
  libia-cca-ipu6-0
  libia-ccat-ipu6-0
  libia-dvs-ipu6-0
  libia-emd-decoder-ipu6-0
  libia-exc-ipu6-0
  libia-isp-bxt-ipu6-0
  libia-lard-ipu6-0
  libia-log-ipu6-0
  libia-ltm-ipu6-0
  libia-mkn-ipu6-0
  libia-nvm-ipu6-0
)
# install in two passes (some PPAs temporarily miss a piece; ignore-missing avoids hard stop)
chroot "$ROOT" apt-get install -y --no-install-recommends "${IPU_PKGS[@]}" || \
  chroot "$ROOT" apt-get -o APT::Get::AllowUnauthenticated=false -o APT::Get::AllowRemoveEssential=false \
    -y --no-install-recommends --ignore-missing "${IPU_PKGS[@]}"

# ---- write an .nspawn unit so we don't bind the entire /dev -----------------
log "Writing /etc/systemd/nspawn/$MACHINE.nspawn…"
NSPAWN="/etc/systemd/nspawn/$MACHINE.nspawn"
install -d -m 0755 /etc/systemd/nspawn

# Collect device nodes to bind (present ones only)
BINDS=()
for p in /dev/video* /dev/media* /dev/v4l-subdev* /dev/dri /lib/firmware; do
  [[ -e "$p" ]] && BINDS+=("$p")
done

{
  echo "[Exec]"
  echo "Boot=yes"
  echo "PrivateUsers=no"
  echo "Console=pipe"       # important to avoid /dev/console conflict
  echo
  echo "[Files]"
  # Bind only what we need (camera + drm + firmware), not the whole /dev
  for b in "${BINDS[@]}"; do
    if [[ "$b" == "/lib/firmware" ]]; then
      echo "BindReadOnly=$b"
    else
      echo "Bind=$b"
    fi
  done
  echo "BindReadOnly=/etc/resolv.conf"
} > "$NSPAWN"

# Make sure resolv.conf exists in container
cp -f /etc/resolv.conf "$ROOT/etc/resolv.conf" || true

# ---- helpers ---------------------------------------------------------------
log "Creating helper wrappers…"
cat >/usr/local/bin/ipu6-nspawn <<EOF
#!/usr/bin/env bash
exec systemd-nspawn -M $MACHINE -D $ROOT --console=pipe "\$@"
EOF
chmod +x /usr/local/bin/ipu6-nspawn

cat >/usr/local/bin/ipu6-test <<'EOF'
#!/usr/bin/env bash
set -e
# Push camera frames from the container into the host v4l2loopback (/dev/video42)
CMD="gst-launch-1.0 \
  icamerasrc isp-mode=0 ! \
  video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
  queue ! videoconvert ! v4l2sink device=/dev/video42"
exec systemd-nspawn -M ipu6-noble -D /var/lib/machines/ipu6-noble --console=pipe /bin/sh -lc "$CMD"
EOF
chmod +x /usr/local/bin/ipu6-test

# ---- smoke tests ------------------------------------------------------------
log "Smoke test: does icamerasrc load in the container?"
if systemd-nspawn -q -M "$MACHINE" -D "$ROOT" --console=pipe /bin/sh -lc 'gst-inspect-1.0 icamerasrc >/dev/null 2>&1'; then
  log "OK: icamerasrc is discoverable."
else
  echo "[WARN] icamerasrc failed to load. Run: ipu6-nspawn /bin/sh -lc 'GST_DEBUG=icamerasrc:4 gst-inspect-1.0 icamerasrc'"
fi

echo
log "All done."
echo "  • Interactive shell in the container:    ipu6-nspawn /bin/bash"
echo "  • Try the camera bridge to /dev/video42: ipu6-test"
echo "  • Select 'IPU6Bridge' camera in apps on the host."
