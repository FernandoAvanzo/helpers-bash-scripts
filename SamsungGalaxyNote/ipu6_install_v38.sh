#!/usr/bin/env bash
set -euo pipefail

LOGTAG="[ipu6_install_v38]"
ROOT=/opt/ipu6-noble
MACHINE=ipu6-noble
PPA_URL="https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu"
PPA_DIST="jammy"   # we only use it as a download source
HOST_LOOPBACK="/dev/video10"

say(){ echo "${LOGTAG} $*"; }
die(){ echo "${LOGTAG}[FATAL] $*" >&2; exit 1; }

# 0) Preconditions on host
say "Kernel: $(uname -r)"
say "Checking IPU6 nodes (kernel side)…"
ls /dev/video* /dev/media* >/dev/null 2>&1 || die "No /dev/video* or /dev/media* nodes found."

say "Ensuring v4l2loopback-dkms & tools exist on host…"
DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  v4l2loopback-dkms v4l-utils gstreamer1.0-tools >/dev/null

# Make sure loopback exists
if ! v4l2-ctl --list-devices 2>/dev/null | grep -q "Virtual Camera"; then
  modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Virtual Camera" || true
fi
[ -e "$HOST_LOOPBACK" ] || die "Expected $HOST_LOOPBACK not present. Load v4l2loopback?"

# 1) Create minimal Noble rootfs once
say "Installing debootstrap & systemd-container on host…"
DEBIAN_FRONTEND=noninteractive apt-get install -y debootstrap systemd-container ca-certificates curl wget >/dev/null

if [ ! -d "$ROOT" ]; then
  say "Bootstrapping Ubuntu 24.04 (Noble) rootfs at $ROOT …"
  debootstrap --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu >/dev/null
fi

# 2) Prepare container apt & basics
say "Configuring apt sources inside container…"
cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main universe multiverse
EOF

# Add the IPU6 dev PPA as a *download source* for jammy; we won't rely on apt resolver.
mkdir -p "$ROOT/etc/apt/sources.list.d"
cat > "$ROOT/etc/apt/sources.list.d/intel-ipu6-jammy.list" <<EOF
deb [trusted=yes] ${PPA_URL} ${PPA_DIST} main
EOF

cp /etc/resolv.conf "$ROOT/etc/resolv.conf" || true

say "Installing base runtime inside container…"
systemd-nspawn -D "$ROOT" --machine="$MACHINE" --quiet bash -c "
  set -e
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    gstreamer1.0-tools gstreamer1.0-plugins-base \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
    libdrm2 libexpat1 libv4l-0 libstdc++6 libgcc-s1 ca-certificates wget curl
"

# 3) Download the Intel IPU6 userspace *debs* from the PPA (jammy) and install them with dpkg
#    We avoid apt's resolver here to bypass transient PPA dependency issues.
say "Fetching IPU6 HAL, bins, and icamerasrc debs from the PPA…"
TMP=/tmp/ipu6-debs.$$; mkdir -p "$TMP"
# Core packages we need (HAL + icamerasrc + the proprietary 'bins')
PKGS=(
  gstreamer1.0-icamera
  libcamhal-ipu6ep0
  libcamhal0
  libcamhal-common
  # Proprietary bins, big dependency fan-out but still self-contained as debs:
  libbroxton-ia-pal0
  libgcss0
  libia-aiq0
  libia-aiqb-parser0
  libia-aiq-file-debug0
  libia-bcomp0
  libia-cca0
  libia-ccat0
  libia-dvs0
  libia-emd-decoder0
  libia-exc0
  libia-lard0
  libia-log0
  libia-ltm0
  libia-mkn0
  libia-nvm0
  libia-cmc-parser0i
  libia-coordinate0i
  libia-isp-bxt0i
)

# Use the jammy PPA in sources to apt-get download, but do NOT apt install from it.
systemd-nspawn -D "$ROOT" --machine="$MACHINE" --bind="$TMP":/hostdl --quiet bash -c "
  set -e
  apt-get update
  cd /hostdl
  for p in ${PKGS[@]}; do
    echo \"[download] \$p\"
    apt-get download \$p || true
  done
  ls -l
"

# 4) Install the downloaded debs with dpkg -i; fix generic deps via Noble repos
say "Installing downloaded IPU6 debs inside container with dpkg…"
systemd-nspawn -D "$ROOT" --machine="$MACHINE" --bind="$TMP":/hostdl --quiet bash -c "
  set -e
  cd /hostdl
  if ! ls *.deb >/dev/null 2>&1; then
    echo 'No debs were downloaded from the PPA. The PPA may be in flux.' >&2
    exit 11
  fi
  dpkg -i ./*.deb || true
  apt-get -f install -y
  dpkg -l | egrep 'icamera|libcamhal|libia_|libgcss|broxton' || true
"

# 5) Make an easy runner that bridges the Noble userspace to host loopback
WRAP=/usr/local/bin/ipu6-webcam-run
say "Writing runner $WRAP …"
cat > "$WRAP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT=/opt/ipu6-noble
MACHINE=ipu6-noble
DEVICE=${DEVICE:-/dev/video10}
FR=${FR:-30}
W=${W:-1280}
H=${H:-720}
GST_DEBUG="${GST_DEBUG:-1}"

echo "[ipu6-webcam-run] Using $DEVICE (v4l2loopback on host), caps ${W}x${H}@${FR}"
# We bind host /dev so the container can open the real IPU6 nodes AND the loopback.
exec systemd-nspawn -D "$ROOT" --machine="$MACHINE" \
  --bind=/dev --bind=/run/udev --bind=/sys --bind=/proc \
  /usr/bin/env GST_DEBUG=$GST_DEBUG \
  gst-launch-1.0 icamerasrc ! video/x-raw,format=NV12,width=$W,height=$H,framerate=$FR/1 ! \
    v4l2sink device=$DEVICE -v
EOF
chmod +x "$WRAP"

say "All set. Try:"
echo "  sudo ipu6-webcam-run"
echo "If you see frames going into $HOST_LOOPBACK, open it in apps/browsers."
