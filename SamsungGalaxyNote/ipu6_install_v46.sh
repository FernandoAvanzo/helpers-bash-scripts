#!/usr/bin/env bash
set -euo pipefail

# ipu6_install_v46.sh
# Containerized IPU6 userspace on a Noble (24.04) rootfs using systemd-nspawn.
# Host remains Jammy (22.04), avoiding GLIBC mismatch on the host.

MACHINE=ipu6-noble
ROOT=/var/lib/machines/${MACHINE}
LOG=/var/log/ipu6_install_v46.$(date +%Y%m%d-%H%M%S).log

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { echo "[$(date +%F\ %T)] $*"; }
die()  { echo "[$(date +%F\ %T)] [FATAL] $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

# ---------- Host preflight ----------
bold "Host preflight checks…"
require_cmd systemd-nspawn
require_cmd debootstrap || true

# cgroup v2 check
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
  info "OK: cgroup v2 present."
else
  echo "[WARN] cgroup v2 not detected. nspawn works best with unified cgroups."
  echo "      On systemd hosts, enable with kernel param: systemd.unified_cgroup_hierarchy=1"
fi

# IPU6 nodes sanity
if compgen -G "/dev/video*" >/dev/null && compgen -G "/dev/media*" >/dev/null; then
  info "OK: IPU6 video/media nodes exist."
else
  echo "[WARN] IPU6 nodes not visible on host. Kernel side may be missing; camera test will fail."
fi

# host deps
info "Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >>"$LOG" 2>&1 || true
apt-get install -y -qq \
  debootstrap systemd-container binutils curl wget gpg ca-certificates \
  v4l2loopback-dkms v4l-utils gstreamer1.0-tools >>"$LOG" 2>&1

# loopback node (non-fatal if exists)
modprobe v4l2loopback exclusive_caps=1 devices=1 card_label="IPU6 Loopback" >>"$LOG" 2>&1 || true
LOOP_NODE=$(v4l2-ctl --list-devices 2>/dev/null | awk 'BEGIN{d=""} /^IPU6 Loopback/ {getline; print $1}')
if [[ -n "${LOOP_NODE:-}" ]]; then
  info "Host v4l2loopback ready at ${LOOP_NODE}"
else
  echo "[WARN] v4l2loopback loaded but could not detect node (continuing)."
fi

# ---------- Create Noble rootfs if needed ----------
if [[ ! -d "$ROOT" || ! -f "$ROOT/etc/os-release" ]]; then
  bold "Creating Noble rootfs at $ROOT …"
  debootstrap --arch=amd64 noble "$ROOT" http://archive.ubuntu.com/ubuntu >>"$LOG" 2>&1 \
    || die "debootstrap failed (see $LOG)"
else
  info "Noble rootfs already exists, reusing."
fi

# ---------- Helpers to run commands inside the container ----------
# Provisioning: no /dev binds, avoid console clash, copy host DNS
nspawn_exec() {
  systemd-nspawn \
    -D "$ROOT" \
    --machine="$MACHINE" \
    --resolv-conf=copy-host \
    --console=pipe \
    --as-pid2 \
    /usr/bin/env bash -lc "$*"
}

# Runtime camera: bind only the needed device nodes
nspawn_cam() {
  local binds=()
  # collect relevant device paths present on host
  for p in /dev/video* /dev/media* /dev/dri /dev/ipu* /dev/mei* /dev/ivsc* ; do
    [[ -e "$p" ]] && binds+=( "--bind=${p}" )
  done
  systemd-nspawn \
    -D "$ROOT" \
    --machine="$MACHINE" \
    --resolv-conf=copy-host \
    --console=interactive \
    "${binds[@]}" \
    /usr/bin/env bash -lc "$*"
}

bold "Configuring apt sources inside container…"
# Base Ubuntu sources
install -d "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/keyrings"
cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF

# Single keyring for the IPU6 PPA (dearmored)
# Two keys are commonly used by Launchpad for that PPA; we combine them into one keyring.
TMPKEY=$(mktemp)
gpg --batch --keyserver keyserver.ubuntu.com --recv-keys A630CA96910990FF B52B913A41086767 >>"$LOG" 2>&1 \
  || die "Failed to receive IPU6 PPA keys"
gpg --batch --export A630CA96910990FF B52B913A41086767 > "$TMPKEY"
gpg --dearmor < "$TMPKEY" > "$ROOT/etc/apt/keyrings/ipu6-ppa.gpg"
rm -f "$TMPKEY"

# Single .sources entry (Noble only), one Signed-By
cat > "$ROOT/etc/apt/sources.list.d/ipu6-ppa.sources" <<'EOF'
Types: deb
URIs: https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu
Suites: noble
Components: main
Signed-By: /etc/apt/keyrings/ipu6-ppa.gpg
EOF

# Make sure any old jammy file from prior attempts is gone
rm -f "$ROOT/etc/apt/sources.list.d/"*intel-ipu6*.list "$ROOT/etc/apt/sources.list.d/"*intel-ipu6*-jammy*.sources

bold "Running apt-get update inside container…"
nspawn_exec "apt-get update -y" >>"$LOG" 2>&1 || die "apt update failed inside container"

bold "Installing base runtime (gstreamer, v4l utils) inside container…"
nspawn_exec "DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 gstreamer1.0-tools \
  v4l-utils libdrm2 libexpat1 curl wget ca-certificates" >>"$LOG" 2>&1

bold "Installing Intel IPU6 userspace & GStreamer inside container…"
# IMPORTANT: install by source package names used in the PPA’s noble series
nspawn_exec "DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ipu6-camera-bins ipu6-camera-hal gst-plugins-icamera" >>"$LOG" 2>&1 \
  || die "IPU6 userspace installation failed (see $LOG)"

# Create helper wrappers on the host
BIN_DIR=/usr/local/bin
install -d "$BIN_DIR"

# Shell into the container for debugging
cat > "$BIN_DIR/ipu6-nspawn" <<EOF
#!/usr/bin/env bash
set -e
# Interactive shell with no device binds (useful for debugging)
exec systemd-nspawn -D "$ROOT" --machine="$MACHINE" --resolv-conf=copy-host --console=interactive /bin/bash
EOF
chmod +x "$BIN_DIR/ipu6-nspawn"

# Quick camera test (binds only the needed device nodes)
cat > "$BIN_DIR/ipu6-test" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="/var/lib/machines/ipu6-noble"
MACHINE="ipu6-noble"
binds=()
for p in /dev/video* /dev/media* /dev/dri /dev/ipu* /dev/mei* /dev/ivsc* ; do
  [[ -e "$p" ]] && binds+=( "--bind=${p}" )
done
# Use fakesink to avoid needing a GUI inside the container
exec systemd-nspawn -D "$ROOT" --machine="$MACHINE" --resolv-conf=copy-host --console=interactive \
  "${binds[@]}" \
  /usr/bin/env bash -lc 'gst-inspect-1.0 icamerasrc && gst-launch-1.0 icamerasrc ! fakesink -v'
EOF
chmod +x "$BIN_DIR/ipu6-test"

bold "Smoke test: gst-inspect icamerasrc (no devices bound, only checks plugin can load)…"
if nspawn_exec "gst-inspect-1.0 icamerasrc" >>"$LOG" 2>&1 ; then
  info "OK: icamerasrc plugin loads in the container."
else
  echo "[WARN] icamerasrc failed to load; see $LOG (but device test may still work if deps are present)."
fi

bold "Done."
echo "Log saved to $LOG"
echo "Use:  sudo ipu6-nspawn     # interactive shell inside the container"
echo "      sudo ipu6-test       # runs gst-inspect + a fakesink pipeline with proper device binds"
