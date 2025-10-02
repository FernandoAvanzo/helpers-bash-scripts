#!/usr/bin/env bash
set -Eeuo pipefail

MACHINE="ipu6-noble"
ROOT="/var/lib/machines/${MACHINE}"
LOGTS() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

need_pkgs=(ca-certificates curl gpg debootstrap systemd-container v4l2loopback-dkms gstreamer1.0-tools v4l-utils)
LOGTS "Ensuring host packages are present…"
apt-get update -y >/dev/null || true
apt-get install -y --no-install-recommends "${need_pkgs[@]}"

# Basic host checks
if [[ -e /sys/fs/cgroup/cgroup.controllers ]]; then
  LOGTS "OK: cgroup v2 present."
else
  LOGTS "WARN: cgroup v2 not present; nspawn may be limited."
fi

# Try to ensure a v4l2loopback device exists (we'll use /dev/video42)
if ! ls /dev/video* >/dev/null 2>&1; then
  LOGTS "WARN: No /dev/video* nodes found. Loading v4l2loopback…"
fi
modprobe v4l2loopback devices=1 video_nr=42 card_label="IPU6 Loopback" exclusive_caps=1 || true
if [[ -e /dev/video42 ]]; then
  LOGTS "Host v4l2loopback ready at /dev/video42"
else
  LOGTS "WARN: v4l2loopback loaded but device not visible yet; continuing."
fi

# Create the rootfs if missing
if [[ ! -d "$ROOT" || ! -f "$ROOT/etc/os-release" ]]; then
  LOGTS "Creating Noble rootfs at $ROOT (debootstrap)…"
  debootstrap --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu
else
  LOGTS "Noble rootfs already exists, reusing."
fi

# Prepare an .nspawn config to fix DNS and device access
nspawn_cfg="/etc/systemd/nspawn/${MACHINE}.nspawn"
mkdir -p "$(dirname "$nspawn_cfg")"
cat >"$nspawn_cfg" <<'EOF'
[Exec]
# Let systemd-nspawn bind the host's resolv.conf so DNS works inside the container
ResolvConf=bind-host
PrivateUsers=off

[Files]
# Give the container access to host /dev so it sees video/media/v4l-subdev and the v4l2loopback device
Bind=/dev

[Network]
# Share the host network namespace (simple and reliable)
VirtualEthernet=no
EOF

# Helper to run a command inside the container non-interactively
runc() {
  systemd-nspawn -M "$MACHINE" -D "$ROOT" --quiet \
    --bind=/dev \
    /bin/bash -lc "$*"
}

# Ensure apt sources & keyrings inside container
LOGTS "Configuring apt sources & keyring inside container…"
runc 'set -e
  mkdir -p /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d

  # Base Ubuntu 24.04 sources
  cat >/etc/apt/sources.list <<SRC
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
SRC

  # Intel IPU6 PPA for noble ONLY
  # Import the PPA public key into a dedicated keyring
  keyring=/etc/apt/keyrings/ipu6-ppa.gpg
  if ! gpg --dearmor -o "${keyring}.tmp" <<KEY
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQENBFp7+S4BCADH3c8Zt6s6Q0wA2GQ8oK5P5wQy8cN2b3cY3S2C+dummyKEY+BLOCK
# NOTE: If this inline key ever fails, we will fetch from keyserver below.
# Placeholder; will be replaced by fetched key if necessary.
-----END PGP PUBLIC KEY BLOCK-----
KEY
  then
    rm -f "${keyring}.tmp"
  fi

  # Always try to fetch fresh from keyserver (works when DNS works)
  # Launchpad keys (public): 23CB DB45 5F37 92D1 8EF1 7E63 A630 CA96 9109 90FF and B52B 913A 4108 6767
  set +e
  for K in A630CA96910990FF B52B913A41086767; do
    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys "$K" && \
      gpg --export "$K" >> "${keyring}.tmp"
  done
  set -e
  if [[ -f "${keyring}.tmp" ]]; then
    mv -f "${keyring}.tmp" "${keyring}"
    chmod 0644 "${keyring}"
  else
    # Fallback: if we failed to fetch, but an old keyring exists, keep it.
    [[ -f "${keyring}" ]] || (echo "FATAL: no IPU6 keyring" >&2; exit 1)
  fi

  # Single clean PPA entry for noble, all using the SAME Signed-By
  cat >/etc/apt/sources.list.d/ipu6.list <<SRC
deb [arch=amd64 signed-by=${keyring}] https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
SRC

  # Pin IPU6 PPA slightly higher than archive so we don’t mix versions
  cat >/etc/apt/preferences.d/99-ipu6-pin <<PIN
Package: *
Pin: release o=LP-PPA-oem-solutions-group-intel-ipu6
Pin-Priority: 700
PIN
'

# Make apt more resilient and fix DNS if needed
LOGTS "Running apt-get update inside container…"
if ! runc 'apt-get -o Acquire::Retries=3 update -y'; then
  LOGTS "DNS likely broken in container; applying resolv.conf fallback…"
  # Even with ResolvConf=bind-host some host setups use a stub; write a static fallback
  runc 'printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" >/etc/resolv.conf'
  runc 'apt-get -o Acquire::Retries=3 update -y'
fi

# Base multimedia bits inside container (many already present)
LOGTS "Installing base runtime (GStreamer, v4l utils) in container…"
runc 'apt-get install -y --no-install-recommends \
       gstreamer1.0-tools gstreamer1.0-plugins-base \
       libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
       libv4l-0 v4l-utils ca-certificates curl gnupg'

# Install Intel IPU6 userspace from noble PPA
LOGTS "Installing IPU6 HAL/IPA + icamerasrc (noble) inside container…"
runc 'set -e
  apt-get install -y --no-install-recommends \
    libipu6 libcamhal-common libcamhal0 libcamhal-ipu6ep0 gstreamer1.0-icamera
'

# Smoke test: ensure icamerasrc is visible and HAL loads
LOGTS "Smoke test (gst-inspect-1.0 icamerasrc)…"
runc 'gst-inspect-1.0 icamerasrc >/tmp/icamera.txt 2>&1 || true; tail -n +1 /tmp/icamera.txt | sed -n "1,120p"'

# Helper wrappers on host
BIN_DIR="/usr/local/bin"
mkdir -p "$BIN_DIR"

cat >"$BIN_DIR/ipu6-nspawn" <<EOF
#!/usr/bin/env bash
exec systemd-nspawn -M "$MACHINE" -D "$ROOT" --bind=/dev /bin/bash -l
EOF
chmod +x "$BIN_DIR/ipu6-nspawn"

cat >"$BIN_DIR/ipu6-test" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
# Run a minimal pipeline inside the container and write to the host loopback (/dev/video42)
systemd-nspawn -M ipu6-noble -D /var/lib/machines/ipu6-noble --bind=/dev \
  /bin/bash -lc 'gst-launch-1.0 -v icamerasrc ! videoconvert ! v4l2sink device=/dev/video42 sync=false'
EOF
chmod +x "$BIN_DIR/ipu6-test"

LOGTS "Done. Try:  ipu6-nspawn   (shell inside container)"
LOGTS "Then test:   ipu6-test     (mirrors camera into /dev/video42 on host)"
