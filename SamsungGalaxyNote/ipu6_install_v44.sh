#!/usr/bin/env bash
set -euo pipefail

log() { printf "[%s] %s\n" "$(date '+%F %T')" "$*"; }
fail() { printf "\n[FATAL] %s\n" "$*" >&2; exit 1; }

MACHINE=ipu6-noble
ROOT=/var/lib/machines/$MACHINE
KEYDIR="$ROOT/etc/apt/keyrings"
NOBLE_SOURCES="$ROOT/etc/apt/sources.list.d/noble-ipu6.list"
PREFS="$ROOT/etc/apt/preferences.d/99-ipu6-pin"
NSPAWN_COMMON=(--machine="$MACHINE" -D "$ROOT" --quiet --register=no --personality=x86-64)
# Bind host devices we need to access the camera stack:
NSPAWN_BINDS=(--bind=/dev/dri --bind=/dev/video0 --bind=/dev/video1 --bind=/dev/video2 --bind=/dev/video10 --bind=/dev/video42 --bind=/run/udev --bind=/sys --bind=/proc)
# We'll choose console based on our action; default interactive for shell/tests.

require_root() { [[ $EUID -eq 0 ]] || fail "Run as root (sudo)."; }
pkg_install() { DEBIAN_FRONTEND=noninteractive apt-get -yq install "$@"; }

require_root
log "Host preflight checks…"

# 1) Make sure IPU6 nodes exist (kernel side OK)
if ! ls /dev/video* 2>/dev/null | grep -qE '/dev/video[0-9]+'; then
  fail "No /dev/video* nodes detected. Ensure IPU6 kernel/firmware is loaded."
fi
log "OK: IPU6 video/media nodes exist."

# 2) Ensure host packages
log "Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…"
apt-get -yq update
pkg_install debootstrap systemd-container gdisk binutils gpg ca-certificates curl wget \
  gstreamer1.0-tools v4l-utils v4l2loopback-dkms || true

# 3) cgroup v2 check
cgfs_type=$(stat -fc %T /sys/fs/cgroup || true)
if [[ "$cgfs_type" != "cgroup2fs" ]]; then
  log "WARN: Host is not using unified cgroup v2 (detected: $cgfs_type)."
  log "      Best: enable unified cgroup hierarchy and reboot:"
  log "      sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"/& systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all/' /etc/default/grub"
  log "      sudo update-grub && sudo reboot"
  log "      Proceeding with a compatibility bind-mount of host /sys/fs/cgroup (reduced features)."
  NSPAWN_CG_FALLBACK=(--bind-ro=/sys/fs/cgroup)
else
  NSPAWN_CG_FALLBACK=()
  log "OK: cgroup v2 present."
fi

# 4) Ensure rootfs exists
if [[ ! -d "$ROOT" ]]; then
  log "Creating Noble rootfs at $ROOT …"
  debootstrap --include=systemd-sysv noble "$ROOT" http://archive.ubuntu.com/ubuntu/ \
    || fail "debootstrap failed"
else
  log "Noble rootfs already exists, reusing."
fi

# 5) Ensure apt keyrings dir
mkdir -p "$KEYDIR"

# 6) Configure apt sources inside container (Ubuntu + IPU6 PPA for noble)
log "Configuring apt sources inside container…"
cat > "$NOBLE_SOURCES" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
# Intel IPU6 (development) PPA for noble & jammy (jammy only as backstop for a few libs if ever needed)
deb https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
deb https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy main
EOF

# 7) Import PPA keys directly into /etc/apt/keyrings (container)
log "Importing Intel IPU6 PPA keys inside container…"
curl -fsSL https://keyserver.ubuntu.com/pks/lookup?op=get\&search=0xA630CA96910990FF \
  | gpg --dearmor > "$KEYDIR/ipu6-ppa.gpg"
curl -fsSL https://keyserver.ubuntu.com/pks/lookup?op=get\&search=0xB52B913A41086767 \
  | gpg --dearmor > "$KEYDIR/ipu6-ppa-private.gpg"

# Wire up signed-by for those PPAs
sed -i 's#^deb https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main#deb [signed-by=/etc/apt/keyrings/ipu6-ppa.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main#' "$NOBLE_SOURCES"
sed -i 's#^deb https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy main#deb [signed-by=/etc/apt/keyrings/ipu6-ppa-private.gpg] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy main#' "$NOBLE_SOURCES"

# 8) Pin IPU6 noble higher than anything else so dependencies resolve consistently
log "Pinning IPU6 noble packages higher than jammy/others…"
cat > "$PREFS" <<'EOF'
Package: *
Pin: release o=LP-PPA-oem-solutions-group-intel-ipu6,n=noble
Pin-Priority: 900

Package: *
Pin: release o=LP-PPA-oem-solutions-group-intel-ipu6,n=jammy
Pin-Priority: 400
EOF

# 9) Update inside container
log "Running apt-get update inside container…"
systemd-nspawn "${NSPAWN_COMMON[@]}" "${NSPAWN_CG_FALLBACK[@]}" --console=passive -- \
  bash -lc 'apt-get -yq update' || fail "apt update failed in container"

# 10) Install base runtime (gstreamer, v4l utils) inside container (no-op if there)
log "Installing base runtime inside container…"
systemd-nspawn "${NSPAWN_COMMON[@]}" "${NSPAWN_CG_FALLBACK[@]}" --console=passive -- bash -lc '
  DEBIAN_FRONTEND=noninteractive apt-get -yq install \
    ca-certificates curl wget gpg dirmngr \
    libdrm2 libexpat1 libv4l-0 gstreamer1.0-tools gstreamer1.0-plugins-base \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0
'

# 11) Install Intel IPU6 userspace (HAL + bins + icamerasrc) from noble PPA with consistent versions
log "Installing Intel IPU6 userspace & GStreamer inside the container…"
# Do a policy peek for the resolver to warm caches and show if series are visible
systemd-nspawn "${NSPAWN_COMMON[@]}" "${NSPAWN_CG_FALLBACK[@]}" --console=passive -- bash -lc '
  apt-cache policy libipu6 libbroxton-ia-pal0 libgcss0 gstreamer1.0-icamera libcamhal-ipu6ep0 libcamhal0 libcamhal-common | sed -n "1,200p"
'
# Single transaction install – let noble pins prevail
systemd-nspawn "${NSPAWN_COMMON[@]}" "${NSPAWN_CG_FALLBACK[@]}" --console=passive -- bash -lc '
  set -e
  DEBIAN_FRONTEND=noninteractive apt-get -yq install \
    gstreamer1.0-icamera libcamhal-ipu6ep0 libcamhal0 libcamhal-common libipu6
'

# 12) Create helpers for interactive use & quick tests
log "Creating helper wrappers…"
cat >/usr/local/bin/ipu6-nspawn <<EOF
#!/usr/bin/env bash
exec systemd-nspawn ${NSPAWN_COMMON[*]} ${NSPAWN_CG_FALLBACK[*]} ${NSPAWN_BINDS[*]} --console=interactive --boot=no "\$@"
EOF
chmod +x /usr/local/bin/ipu6-nspawn

cat >/usr/local/bin/ipu6-test <<'EOF'
#!/usr/bin/env bash
set -e
# Run a quick pipeline inside the container with host /dev bindings
systemd-nspawn --machine=ipu6-noble -D /var/lib/machines/ipu6-noble \
  --register=no --quiet --boot=no \
  --bind=/dev/dri --bind=/dev/video0 --bind=/dev/video1 --bind=/dev/video2 --bind=/dev/video10 --bind=/dev/video42 \
  --bind=/run/udev --bind=/sys --bind=/proc \
  --console=interactive -- \
  bash -lc 'GST_DEBUG=icamerasrc:3,DEFAULT:1 gst-launch-1.0 icamerasrc ! fakesink -v'
EOF
chmod +x /usr/local/bin/ipu6-test

# 13) Quick smoke test (non-fatal if you just changed cgroups and didn’t reboot yet)
log "Smoke test: gst-inspect icamerasrc (non-fatal preview)…"
if ! systemd-nspawn "${NSPAWN_COMMON[@]}" "${NSPAWN_CG_FALLBACK[@]}" --console=passive -- \
  bash -lc 'gst-inspect-1.0 icamerasrc 2>&1 | sed -n "1,80p"'; then
  log "WARN: gst-inspect had issues. If host lacks cgroup v2, re-run after enabling it (see preflight hints)."
fi

log "Done. Use:  ipu6-nspawn  (shell in container)"
log "      or:   ipu6-test    (quick pipeline to fakesink)"
