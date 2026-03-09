#!/usr/bin/env bash
# Samsung Galaxy Book4 Ultra IPU6 Webcam – containerized userspace (Ubuntu 24.04 Noble) – v50

set -Eeuo pipefail

ME=$(basename "$0")
TS() { printf '[%(%F %T)T] ' -1; }
fatal() { TS; echo "[FATAL] $*" >&2; exit 1; }
warn()  { TS; echo "[WARN]  $*" >&2; }
info()  { TS; echo "$*"; }

# -------- host preflight --------
[[ -n "${BASH_VERSION:-}" ]] || { echo "Please run with bash"; exit 1; }

# Require systemd-nspawn & debootstrap & v4l2loopback
need_host_pkgs=(debootstrap systemd-container gpg curl ca-certificates v4l2loopback-dkms v4l-utils gstreamer1.0-tools)
apt-get update -y >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y "${need_host_pkgs[@]}" || fatal "failed installing host packages"

# cgroup v2 check
if ! mount | grep -q 'type cgroup2'; then
  warn "cgroup v2 not mounted; enabling unified hierarchy is recommended for nspawn"
fi

# IPU6 device nodes present?
if ! ls /dev/video* /dev/media* /dev/v4l-subdev* >/dev/null 2>&1; then
  warn "No video/media/v4l-subdev nodes found. Kernel IPU6/sensors may not be up. Continuing."
fi

# optional: ensure one v4l2loopback node to mirror into if user wants
if ! ls /dev/video* 2>/dev/null | grep -q 'video42'; then
  modprobe v4l2loopback devices=1 video_nr=42 card_label="ipu6-loopback" exclusive_caps=1 || warn "v4l2loopback modprobe failed"
fi

ROOT=/var/lib/machines/ipu6-noble
MACH=ipu6-noble

# -------- create noble rootfs if missing --------
if [[ ! -f "$ROOT/etc/os-release" ]]; then
  info "Creating Noble rootfs at $ROOT ..."
  debootstrap --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu || fatal "debootstrap noble failed"
else
  info "Noble rootfs already exists, reusing."
fi

# Helper to run a command inside the container non-interactively (good for scripts)
nspawn_run() {
  # Use pipe console for scripts; copy host DNS; private network not required
  systemd-nspawn \
    --quiet \
    --machine="$MACH" \
    --directory="$ROOT" \
    --resolv-conf=copy-host \
    --console=pipe \
    --capability=CAP_SYS_ADMIN \
    --setenv=DEBIAN_FRONTEND=noninteractive \
    --as-pid2 \
    -- "$@"
}

# -------- apt sources & keyrings inside container --------
info "Configuring apt sources & keyrings inside container…"

# ensure keyrings dir
install -d -m 0755 "$ROOT/etc/apt/keyrings"

# Import Launchpad PPA keys into ONE keyring file (avoid Signed-By conflicts)
# Keys: A630CA96910990FF (OEM Solutions Group) and B52B913A41086767 (Private PPA)
cat > "$ROOT/tmp/ipu6.keys" <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----
mQINBFbKFZYBEAD... (placeholder)
-----END PGP PUBLIC KEY BLOCK-----
-----BEGIN PGP PUBLIC KEY BLOCK-----
mQINBGQz... (placeholder)
-----END PGP PUBLIC KEY BLOCK-----
EOF
# NOTE: we fetch keys online in case placeholders are stale:
nspawn_run sh -exc '
  set -e
  apt-get update -y || true
  apt-get install -y --no-install-recommends ca-certificates gnupg curl
  install -d -m 0755 /etc/apt/keyrings
  # Import both Launchpad keys directly (authoritative endpoints)
  curl -fsSL https://keyserver.ubuntu.com/pks/lookup?op=get\&search=0xA630CA96910990FF | gpg --dearmor -o /etc/apt/keyrings/ipu6-ppa.gpg
  curl -fsSL https://keyserver.ubuntu.com/pks/lookup?op=get\&search=0xB52B913A41086767 | gpg --dearmor -o /etc/apt/keyrings/ipu6-ppa-private.gpg
  # Merge into one keyring to avoid Signed-By conflicts
  cat /etc/apt/keyrings/ipu6-ppa.gpg /etc/apt/keyrings/ipu6-ppa-private.gpg > /etc/apt/keyrings/ipu6-combined.gpg
  chmod 0644 /etc/apt/keyrings/ipu6-combined.gpg
'

# Write sources: Ubuntu noble + IPU6 PPA noble ONLY (no jammy inside noble)
cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse restricted
deb http://security.ubuntu.com/ubuntu noble-security main universe multiverse restricted
EOF

cat > "$ROOT/etc/apt/sources.list.d/ipu6.list" <<EOF
deb [signed-by=/etc/apt/keyrings/ipu6-combined.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

# clean any old jammy entry that may have been lingering from previous attempts
rm -f "$ROOT/etc/apt/sources.list.d/ipu6-jammy.list" 2>/dev/null || true
# and any other duplicates with a different Signed-By path
find "$ROOT/etc/apt/sources.list.d" -type f -name '*ipu6*' -print0 \
  | xargs -0 sed -n 'p' >/dev/null || true

# Optional pinning (noble only); probably not necessary if jammy is absent
cat > "$ROOT/etc/apt/preferences.d/99-ipu6" <<'EOF'
Package: *
Pin: release o=LP-PPA-oem-solutions-group-intel-ipu6,a=noble
Pin-Priority: 700
EOF

# Update & install the stack
info "Installing IPU6 userspace and GStreamer in container…"
nspawn_run sh -exc '
  set -e
  apt-get update
  apt-get install -y --no-install-recommends \
    libdrm2 libexpat1 libv4l-0 gstreamer1.0-tools gstreamer1.0-plugins-base \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
    libcamhal-common libcamhal-ipu6ep0 libcamhal0 gstreamer1.0-icamera libipu6
'

# Create convenience wrappers on host
BIN=/usr/local/bin
cat > "$BIN/ipu6-nspawn" <<EOF
#!/usr/bin/env bash
# interactive shell inside the container with needed devices bound in
ARGS=()
# bind discovered camera nodes (selective bind to avoid /dev/console conflict)
for d in /dev/video* /dev/media* /dev/v4l-subdev* /dev/dri/*; do
  [[ -e "\$d" ]] && ARGS+=(--bind="\$d")
done
exec systemd-nspawn --machine=$MACH --directory=$ROOT \\
  --resolv-conf=copy-host --console=interactive --as-pid2 \\
  "\${ARGS[@]}" -- /bin/bash
EOF
chmod +x "$BIN/ipu6-nspawn"

cat > "$BIN/ipu6-test" <<'EOF'
#!/usr/bin/env bash
# run a quick GStreamer pipeline inside the container
set -e
ARGS=()
for d in /dev/video* /dev/media* /dev/v4l-subdev* /dev/dri/*; do
  [[ -e "$d" ]] && ARGS+=(--bind="$d")
done
CMD="gst-launch-1.0 icamerasrc ! videoconvert ! fakesink -v"
exec systemd-nspawn --machine=ipu6-noble --directory=/var/lib/machines/ipu6-noble \
  --resolv-conf=copy-host --console=pipe --as-pid2 "${ARGS[@]}" -- sh -c "$CMD"
EOF
chmod +x "$BIN/ipu6-test"

info "Smoke test: listing icamerasrc…"
if ! nspawn_run gst-inspect-1.0 icamerasrc >/tmp/icamera.inspect 2>&1; then
  warn "icamerasrc failed to load; check /tmp/icamera.inspect on host after bind-running with devices."
else
  info "icamerasrc appears present."
fi

info "Done. Use:  ipu6-nspawn   (interactive shell in container)"
info "      or:   ipu6-test     (quick pipeline to fakesink)"
