#!/usr/bin/env bash
set -euo pipefail

# ----------- Config ----------- #
MACHINE_NAME="ipu6-noble"
ROOTFS="/var/lib/machines/$MACHINE_NAME"
PPA_BASE="https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu"
KEY_PUBLIC="A630CA96910990FF"   # "Launchpad PPA for OEM Solutions Group"
KEY_PRIVATE="B52B913A41086767"  # "Launchpad Private PPA for OEM Solutions Group"
HOST_V4L_NODE="${HOST_V4L_NODE:-/dev/video42}"  # v4l2loopback target on host

# Base packages we need inside container to exercise the camera stack
BASE_RUNTIME_PKGS=(
  ca-certificates curl wget gpg dirmngr gnupg
  libdrm2 libexpat1 libv4l-0 gstreamer1.0-tools
  gstreamer1.0-plugins-base libgstreamer1.0-0 libgstreamer-plugins-base1.0-0
  v4l-utils
)

# IPU6 userspace (HAL/IPA/icamerasrc) – install as a coherent set
IPU6_PKGS=(
  gstreamer1.0-icamera
  libcamhal-ipu6ep0 libcamhal0 libcamhal-common
  libipu6
  libbroxton-ia-pal0 libgcss0
  libia-aiqb-parser0 libia-aiq-file-debug0 libia-aiq0
  libia-bcomp0 libia-cca0 libia-ccat0 libia-dvs0
  libia-emd-decoder0 libia-exc0 libia-lard0 libia-log0
  libia-ltm0 libia-mkn0 libia-nvm0
)

log() { printf '[%s] %s\n' "$(date "+%F %T")" "$*" >&2; }
die() { printf '\n[FATAL] %s\n' "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# ----------- Host preflight ----------- #
log "Host preflight checks…"
require_cmd debootstrap
require_cmd systemd-nspawn
require_cmd machinectl

# Check IPU6 kernel side: media/video nodes
if ! ls /dev/video* >/dev/null 2>&1; then
  die "No /dev/video* nodes found. IPU6 kernel side not present."
fi
log "OK: IPU6 video/media nodes exist."

# Ensure cgroup v2 (unified) – required for booted nspawn machines to be happy.
if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
  die "cgroup v2 not mounted. Enable systemd unified cgroups (v2) and reboot."
fi
log "OK: cgroup v2 present."

# v4l2loopback for host virtual sink (non-fatal if already)
apt-get update -qq
apt-get install -y -qq v4l2loopback-dkms v4l2loopback-utils >/dev/null 2>&1 || true

# Create a host loopback node, keep your previous behavior
modprobe v4l2loopback devices=1 video_nr=$(basename "$HOST_V4L_NODE" | tr -dc 0-9) card_label="ipu6-loopback" exclusive_caps=1 || true
if [[ -e "$HOST_V4L_NODE" ]]; then
  log "Host v4l2loopback ready at $HOST_V4L_NODE"
else
  log "WARN: $HOST_V4L_NODE not present; continuing."
fi

# ----------- Bootstrap Noble rootfs (once) ----------- #
if [[ ! -d "$ROOTFS" ]]; then
  log "Creating Noble rootfs at $ROOTFS…"
  debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu
else
  log "Noble rootfs already exists, reusing."
fi

# Helper: run a command in the rootfs without booting (for provisioning)
in_chroot() {
  systemd-nspawn -D "$ROOTFS" --quiet --bind-ro=/dev -q /usr/bin/env bash -lc "$*"
}

# ----------- Configure APT inside container ----------- #
log "Configuring apt sources inside container…"

# Ensure directories
install -d -m 755 "$ROOTFS/etc/apt/sources.list.d"
install -d -m 755 "$ROOTFS/etc/apt/preferences.d"
install -d -m 755 "$ROOTFS/etc/apt/keyrings"

# Clean any stale ipu6 key in trusted.gpg* to avoid Signed-By conflicts
rm -f "$ROOTFS/etc/apt/trusted.gpg.d/"*ipu6*.gpg 2>/dev/null || true
rm -f "$ROOTFS/etc/apt/trusted.gpg" 2>/dev/null || true

# Import keys to /etc/apt/keyrings (dearmored)
in_chroot "set -e;
  export DEBIAN_FRONTEND=noninteractive;
  apt-get -qq update;
  apt-get -y -qq install ca-certificates curl wget gnupg gpg dirmngr;
  gpg --keyserver keyserver.ubuntu.com --recv-keys $KEY_PUBLIC;
  gpg --export $KEY_PUBLIC | gpg --dearmor > /etc/apt/keyrings/ipu6-ppa.gpg;
  gpg --keyserver keyserver.ubuntu.com --recv-keys $KEY_PRIVATE;
  gpg --export $KEY_PRIVATE | gpg --dearmor > /etc/apt/keyrings/ipu6-ppa-private.gpg;
  chmod 0644 /etc/apt/keyrings/ipu6-ppa*.gpg;
"

# Deb822 sources: Ubuntu archive (noble), IPU6 noble, IPU6 jammy (fallback only)
cat >"$ROOTFS/etc/apt/sources.list.d/ubuntu.sources" <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

cat >"$ROOTFS/etc/apt/sources.list.d/ipu6-noble.sources" <<EOF
Types: deb
URIs: $PPA_BASE
Suites: noble
Components: main
Signed-By: /etc/apt/keyrings/ipu6-ppa.gpg
EOF

cat >"$ROOTFS/etc/apt/sources.list.d/ipu6-jammy.sources" <<EOF
Types: deb
URIs: $PPA_BASE
Suites: jammy
Components: main
Signed-By: /etc/apt/keyrings/ipu6-ppa-private.gpg
EOF

# Pin Noble PPA high, Jammy PPA low (fallback)
cat >"$ROOTFS/etc/apt/preferences.d/ipu6-pin" <<'EOF'
Package: *
Pin: release o=LP-PPA-oem-solutions-group-intel-ipu6,n=noble
Pin-Priority: 1001

Package: *
Pin: release o=LP-PPA-oem-solutions-group-intel-ipu6,n=jammy
Pin-Priority: 400
EOF

log "Running apt-get update inside container…"
in_chroot "apt-get update -y"

# ----------- Install base runtime inside the container ----------- #
log "Installing base runtime (gstreamer, v4l utils) inside container…"
in_chroot "export DEBIAN_FRONTEND=noninteractive; apt-get install -y ${BASE_RUNTIME_PKGS[*]}"

# ----------- Install IPU6 userspace (two-pass strategy) ----------- #
try_install_ipu6() {
  local target="$1"   # "noble" or "jammy"
  if [[ "$target" == "noble" ]]; then
    in_chroot "export DEBIAN_FRONTEND=noninteractive; apt-get install -y ${IPU6_PKGS[*]}"
  else
    # Force from jammy suite for consistency
    in_chroot "export DEBIAN_FRONTEND=noninteractive; apt-get -t jammy install -y ${IPU6_PKGS[*]}"
  fi
}

log "Installing Intel IPU6 userspace & GStreamer (prefer noble)…"
if ! try_install_ipu6 noble; then
  log "First attempt failed; retrying with a coherent Jammy fallback set…"
  try_install_ipu6 jammy || die "IPU6 userspace install failed from both noble and jammy."
fi

# ----------- Create helper wrappers on host ----------- #
BIN_DIR="/usr/local/bin"
install -d -m 755 "$BIN_DIR"

# Start/stop the machine cleanly
cat >"$BIN_DIR/ipu6-start" <<EOF
#!/usr/bin/env bash
set -e
machinectl start $MACHINE_NAME || true
sleep 1
echo "[ipu6] machine started: $MACHINE_NAME"
EOF
chmod +x "$BIN_DIR/ipu6-start"

cat >"$BIN_DIR/ipu6-stop" <<EOF
#!/usr/bin/env bash
set -e
machinectl stop $MACHINE_NAME || true
echo "[ipu6] machine stopped: $MACHINE_NAME"
EOF
chmod +x "$BIN_DIR/ipu6-stop"

# Shell into the container
cat >"$BIN_DIR/ipu6-shell" <<EOF
#!/usr/bin/env bash
exec machinectl shell root@$MACHINE_NAME
EOF
chmod +x "$BIN_DIR/ipu6-shell"

# Exec arbitrary commands in the container (non-interactive)
cat >"$BIN_DIR/ipu6-exec" <<'EOF'
#!/usr/bin/env bash
set -e
if [[ $# -lt 1 ]]; then echo "usage: ipu6-exec <command…>"; exit 2; fi
exec machinectl shell root@ipu6-noble -- /bin/bash -lc "$*"
EOF
chmod +x "$BIN_DIR/ipu6-exec"

# Quick test: run gst-inspect & a tiny pipeline inside the container
cat >"$BIN_DIR/ipu6-test" <<'EOF'
#!/usr/bin/env bash
set -e
machinectl start ipu6-noble >/dev/null 2>&1 || true
# Bind /dev and udev info (done by nspawn automatically for machines)
echo "[ipu6] gst-inspect icamerasrc…"
machinectl shell root@ipu6-noble -- /bin/bash -lc 'gst-inspect-1.0 icamerasrc || true'
echo "[ipu6] running probe pipeline (to fakesink)…"
machinectl shell root@ipu6-noble -- /bin/bash -lc 'GST_DEBUG=icamerasrc:3 gst-launch-1.0 icamerasrc ! fakesink -v'
EOF
chmod +x "$BIN_DIR/ipu6-test"

# ----------- Boot the machine now ----------- #
log "Starting the container as a systemd machine…"
machinectl start "$MACHINE_NAME" >/dev/null 2>&1 || true
sleep 1

log "All done. Use:"
echo "  ipu6-start      # start the machine"
echo "  ipu6-shell      # root shell inside container"
echo "  ipu6-test       # run gst-inspect and a probe pipeline"
echo "  ipu6-stop       # stop the machine"
