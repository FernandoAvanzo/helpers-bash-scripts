#!/bin/bash
set -euo pipefail

# ipu6_install_v49.sh — robust nspawn Noble userspace for IPU6 on Pop!/Ubuntu 22.04 hosts

MACHINE=ipu6-noble
ROOT=/var/lib/machines/${MACHINE}
LOG=/var/log/ipu6_install_v49.$(date +%Y%m%d-%H%M%S).log

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ echo "[$(date +'%F %T')] $*" | tee -a "$LOG"; }
warn(){ echo "[$(date +'%F %T')] [WARN] $*" | tee -a "$LOG"; }
die(){  echo "[$(date +'%F %T')] [FATAL] $*" | tee -a "$LOG" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

# ---- host preflight ----
bold "Preflight (host)…"
for c in systemd-nspawn debootstrap curl gpg; do
  command -v "$c" >/dev/null 2>&1 || die "Missing $c"
done
if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
  die "cgroup v2 required (kernel param: systemd.unified_cgroup_hierarchy=1)"
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >>"$LOG" 2>&1 || true
apt-get install -y -qq systemd-container linux-firmware v4l-utils ca-certificates >>"$LOG" 2>&1 || true

# ---- ensure clean resolvability bindings for the container ----
install -d "$ROOT"

# Create a minimal .nspawn file to force networking + resolver behavior
NSPAWN_FILE=/etc/systemd/nspawn/${MACHINE}.nspawn
install -d /etc/systemd/nspawn
cat > "$NSPAWN_FILE" <<'EOF'
[Exec]
PrivateUsers=no
Personality=x86-64

[Files]
Bind=/etc/hosts
Bind=/etc/nsswitch.conf

[Network]
VirtualEthernet=yes
EOF

# ---- create or repair rootfs ----
bootstrap_rootfs(){
  bold "Bootstrapping Noble rootfs…"
  rm -rf "$ROOT"
  debootstrap --arch=amd64 noble "$ROOT" http://archive.ubuntu.com/ubuntu >>"$LOG" 2>&1 || die "debootstrap failed"
  systemd-machine-id-setup --root="$ROOT"
}

if [[ ! -f "$ROOT/etc/os-release" ]]; then
  bootstrap_rootfs
else
  info "Rootfs exists, verifying apt health…"
fi

# Always ensure valid apt sources and keyrings
install -d "$ROOT/etc/apt/keyrings" "$ROOT/etc/apt/sources.list.d"

cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF

# Helper to run inside container with stable networking and tty-less setup
nspawn_exec(){
  systemd-nspawn \
    -M "$MACHINE" \
    -D "$ROOT" \
    --as-pid2 \
    --register=no \
    --resolv-conf=copy-host \
    --console=pipe \
    --capability=CAP_NET_ADMIN \
    /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive bash -lc "$*"
}

# Minimal fixups before apt: ensure resolv.conf exists inside root
if [[ ! -L "$ROOT/etc/resolv.conf" && ! -s "$ROOT/etc/resolv.conf" ]]; then
  ln -sf /run/systemd/resolve/resolv.conf "$ROOT/etc/resolv.conf" 2>>"$LOG" || \
    printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > "$ROOT/etc/resolv.conf"
fi

# Initial apt core
bold "Priming apt inside container…"
set +e
nspawn_exec "apt-get update" >>"$LOG" 2>&1
APT_OK=$?
set -e
if [[ $APT_OK -ne 0 ]]; then
  warn "apt update failed; repairing base and trying again…"
  # Install minimal tools that help apt/keyrings
  chroot "$ROOT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin bash -lc 'apt-get update || true'
  # If still broken, rebuild rootfs
  if ! chroot "$ROOT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin bash -lc 'apt-get update'; then
    warn "Recreating rootfs due to persistent apt failure"
    bootstrap_rootfs
  fi
fi

# Install base tools
bold "Installing base tools (ca-certificates, gnupg)…"
nspawn_exec "apt-get update && apt-get install -y --no-install-recommends ca-certificates gnupg wget curl software-properties-common systemd dbus sudo" >>"$LOG" 2>&1 || die "base install failed"

# Add Intel IPU6 PPA with proper Signed-By (no apt-key)
bold "Adding Intel IPU6 PPA key…"
TMPKEY=$(mktemp)
# Two common keys for that PPA. If second not found, proceed with one.
set +e
nspawn_exec "gpg --keyserver keyserver.ubuntu.com --recv-keys A630CA96910990FF B52B913A41086767" >>"$LOG" 2>&1
nspawn_exec "gpg --export A630CA96910990FF B52B913A41086767" > "$TMPKEY" 2>>"$LOG"
set -e
gpg --dearmor < "$TMPKEY" > "$ROOT/etc/apt/keyrings/ipu6-ppa.gpg" 2>>"$LOG" || die "key dearmor failed"
rm -f "$TMPKEY"

cat > "$ROOT/etc/apt/sources.list.d/intel-ipu6.sources" <<'EOF'
Types: deb
URIs: https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu
Suites: noble
Components: main
Signed-By: /etc/apt/keyrings/ipu6-ppa.gpg
EOF

bold "Updating apt and installing IPU6 userspace…"
nspawn_exec "apt-get update" >>"$LOG" 2>&1 || die "apt update failed (container)"
nspawn_exec "apt-get install -y --no-install-recommends ipu6-camera-bins ipu6-camera-hal v4l-utils \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good libcamera-tools gstreamer1.0-libcamera" >>"$LOG" 2>&1 || die "IPU6 userspace install failed"

# ---- host wrappers (reuse what worked) ----
install -d /usr/local/bin

cat > /usr/local/bin/ipu6-nspawn <<EOF
#!/bin/bash
exec systemd-nspawn -M "$MACHINE" -D "$ROOT" --register=no --resolv-conf=copy-host --console=interactive /bin/bash
EOF
chmod +x /usr/local/bin/ipu6-nspawn

cat > /usr/local/bin/ipu6-test <<'EOF'
#!/bin/bash
set -euo pipefail
ROOT="/var/lib/machines/ipu6-noble"
MACHINE="ipu6-noble"
binds=()
for p in /dev/video* /dev/media* /dev/dri ; do [[ -e "$p" ]] && binds+=( "--bind=$p" ); done
exec systemd-nspawn -M "$MACHINE" -D "$ROOT" --register=no --resolv-conf=copy-host --console=pipe \
  "${binds[@]}" \
  /usr/bin/env bash -lc 'libcamera-hello --list-cameras || cam --list || true; gst-inspect-1.0 libcamerasrc || gst-inspect-1.0 icamerasrc || true'
EOF
chmod +x /usr/local/bin/ipu6-test

cat > /usr/local/bin/ipu6-v4l2-relay <<'EOF'
#!/bin/bash
set -euo pipefail
# Create /dev/video20 via v4l2loopback and stream to it from container
modprobe v4l2loopback devices=1 video_nr=20 card_label="IPU6 Relay Camera" exclusive_caps=0 || true
ROOT="/var/lib/machines/ipu6-noble"
MACHINE="ipu6-noble"
binds=( "--bind=/dev/video20" )
for p in /dev/video* /dev/media* /dev/dri ; do [[ -e "$p" ]] && binds+=( "--bind=$p" ); done
exec systemd-nspawn -M "$MACHINE" -D "$ROOT" --register=no --resolv-conf=copy-host --console=pipe \
  "${binds[@]}" \
  /usr/bin/env bash -lc 'gst-launch-1.0 libcamerasrc ! videoconvert ! v4l2sink device=/dev/video20 sync=false'
EOF
chmod +x /usr/local/bin/ipu6-v4l2-relay

bold "Smoke test (container):"
if nspawn_exec "libcamera-hello --version" >>"$LOG" 2>&1; then
  info "libcamera present in container"
else
  warn "libcamera check failed (see $LOG)"
fi

bold "Done."
echo "Wrappers:"
echo "  sudo ipu6-nspawn     # shell inside container"
echo "  sudo ipu6-test       # basic userspace probe"
echo "  sudo ipu6-v4l2-relay # stream into /dev/video20 for legacy apps"
echo "Logs: $LOG"
