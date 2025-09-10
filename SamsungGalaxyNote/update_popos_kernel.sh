#!/usr/bin/env bash
# Pop!_OS 22.04 → Linux 6.15.4 with NVIDIA 570 + Secure Boot (MOK auto-sign)
# - Installs mainline 6.15.4 + headers
# - Ensures NVIDIA 570 is installed at the newest PPA version (>= 570.169)
# - Generates & enrolls a MOK, configures DKMS to sign modules automatically
# - Signs NVIDIA modules for the target kernel, updates initramfs & kernelstub
# - NEW: --set-default  → make 6.15.4 the default boot entry via kernelstub
set -euo pipefail

# --- Versions & constants -------------------------------------------------------
KVER_MAJOR="6.15.4"
KVER_TAG="6.15.4-061504"                 # Ubuntu mainline build tag
KVER_FULL="${KVER_TAG}-generic"
NV_MIN="570.169"                         # first 570 known good with 6.15
MAINLINE_PPA="ppa:cappelikan/ppa"
GFX_PPA="ppa:graphics-drivers/ppa"
BLACKLIST_FILE="/etc/modprobe.d/99-nvidia-vs-nova.conf"
DKMS_CONF="/etc/dkms/framework.conf"
DKMS_CONF_D="/etc/dkms/framework.conf.d"
MOK_DIR="/root/secureboot/mok"
MOK_KEY="${MOK_DIR}/MOK.priv"
MOK_CRT_DER="${MOK_DIR}/MOK.der"
MOK_SUBJ="/CN=Pop!_OS SecureBoot MOK/"
POSTINST_HOOK="/etc/kernel/postinst.d/zz-sign-nvidia"
DKMS_POSTBUILD="/etc/dkms/post-build.d/zz-sign-with-mok"
SIGN_HELPER="/usr/local/sbin/sign-with-mok"
HASH_ALGO="sha256"
SET_DEFAULT=0

# --- Arg parsing ----------------------------------------------------------------
for a in "$@"; do
  case "$a" in
  --set-default) SET_DEFAULT=1 ;;
  -h|--help)
    cat <<EOF
Usage: sudo $0 [--set-default]
  --set-default   After install/signing, make ${KVER_MAJOR} the default via kernelstub
EOF
    exit 0 ;;
  *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done

# --- UI helpers -----------------------------------------------------------------
say()   { printf "\033[1;37m»\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m✔\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m⚠\033[0m %s\n" "$*"; }
die()   { printf "\033[1;31m✘ %s\033[0m\n" "$*"; exit 1; }
ver_ge(){ dpkg --compare-versions "$1" ge "$2"; }  # 0 if $1 >= $2

need_root() { [[ $(id -u) -eq 0 ]] || die "Run this script with sudo/root."; }
check_pop() {
  grep -q '^NAME="Pop!_OS"' /etc/os-release || die "Not Pop!_OS."
  grep -q '^VERSION_ID="22.04"' /etc/os-release || die "This script targets Pop!_OS 22.04."
}

secure_boot_state() {
  if command -v mokutil >/dev/null 2>&1; then
    mokutil --sb-state 2>/dev/null | grep -qi enabled  && { echo enabled; return; }
    mokutil --sb-state 2>/dev/null | grep -qi disabled && { echo disabled; return; }
  fi
  if [[ -d /sys/firmware/efi/efivars ]]; then
    local f; f=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null || true)
    if [[ -n "$f" ]]; then
      local b; b=$(hexdump -v -e '1/1 "%d"' "$f" | head -c1)
      [[ "$b" == "1" ]] && { echo enabled; return; } || { echo disabled; return; }
    fi
  fi
  echo unknown
}

# --- Start ----------------------------------------------------------------------
need_root
check_pop

say "Installing prerequisites..."
apt-get update -y >/dev/null
apt-get install -y software-properties-common curl dkms build-essential mokutil openssl >/dev/null
ok "Prereqs installed."

say "Adding repositories (Mainline helper + Graphics Drivers PPA)..."
add-apt-repository -y "$MAINLINE_PPA" >/dev/null
add-apt-repository -y "$GFX_PPA" >/dev/null
apt-get update -y >/dev/null
ok "PPAs ready."

# --- NVIDIA: install/upgrade to newest available 570 (>= NV_MIN) ----------------
say "Checking NVIDIA 570 packages..."
installed_ver=$(dpkg-query -W -f='${Version}' nvidia-driver-570 2>/dev/null || echo "none")
candidate_ver=$(apt-cache policy nvidia-driver-570 | awk '/Candidate:/ {print $2}')

if [[ "$installed_ver" == "none" && "$candidate_ver" != "(none)" ]]; then
  say "Installing nvidia-driver-570 ${candidate_ver} from PPA..."
  apt-get install -y nvidia-driver-570 nvidia-dkms-570 >/dev/null
  installed_ver=$(dpkg-query -W -f='${Version}' nvidia-driver-570)
fi

if [[ "$installed_ver" != "none" && "$candidate_ver" != "(none)" ]] && ! ver_ge "$installed_ver" "$candidate_ver"; then
  say "Upgrading nvidia-driver-570 to ${candidate_ver}..."
  apt-get install -y nvidia-driver-570 nvidia-dkms-570 >/dev/null
  installed_ver=$(dpkg-query -W -f='${Version}' nvidia-driver-570)
fi

if [[ "$installed_ver" == "none" ]]; then
  warn "No 570 package in APT. Falling back to NVIDIA .run (570.169) with DKMS registration..."
  tmpd="$(mktemp -d)"
  pushd "$tmpd" >/dev/null
  wget -q https://us.download.nvidia.com/XFree86/Linux-x86_64/570.169/NVIDIA-Linux-x86_64-570.169.run
  sh NVIDIA-Linux-x86_64-570.169.run --silent --dkms
  popd >/dev/null
  rm -rf "$tmpd"
  installed_ver="570.169"
fi

if ! ver_ge "$installed_ver" "$NV_MIN"; then
  warn "Installed NVIDIA is ${installed_ver}, but need ≥ ${NV_MIN} for kernel 6.15.x."
  if [[ "$candidate_ver" != "(none)" ]] && ver_ge "$candidate_ver" "$NV_MIN"; then
    say "Upgrading from PPA to ${candidate_ver}..."
    apt-get install -y nvidia-driver-570 nvidia-dkms-570 >/dev/null
    installed_ver=$(dpkg-query -W -f='${Version}' nvidia-driver-570)
  else
    die "Could not obtain ≥ ${NV_MIN}. Please try again later or provide a newer .run."
  fi
fi
ok "NVIDIA driver installed: ${installed_ver} (OK for 6.15.x)."

# --- Secure Boot: prepare MOK and DKMS auto-signing -----------------------------
SB=$(secure_boot_state)
say "Secure Boot state: ${SB}"

# Create MOK if missing (works for both enabled and disabled SB; enrollment needed if enabled)
if [[ ! -f "$MOK_KEY" || ! -f "$MOK_CRT_DER" ]]; then
  say "Generating a new MOK (10-year self-signed X.509)..."
  install -d -m 0700 "$MOK_DIR"
  openssl req -new -x509 -newkey rsa:2048 -keyout "$MOK_KEY" -outform DER -out "$MOK_CRT_DER" \
    -nodes -days 3650 -subj "$MOK_SUBJ" >/dev/null 2>&1
  chmod 600 "$MOK_KEY"
  ok "MOK created at ${MOK_DIR}"
else
  ok "Existing MOK found at ${MOK_DIR}"
fi

# Configure DKMS to auto-sign with our MOK
mkdir -p "$DKMS_CONF_D"
if ! grep -qs 'mok_signing_key=' "$DKMS_CONF" 2>/dev/null && [[ ! -e "${DKMS_CONF_D}/10-local-mok.conf" ]]; then
  say "Configuring DKMS to auto-sign with MOK..."
  cat > "${DKMS_CONF_D}/10-local-mok.conf" <<EOF
mok_signing_key="${MOK_KEY}"
mok_certificate="${MOK_CRT_DER}"
EOF
  ok "DKMS signing config installed."
fi

# Helper and hooks to ensure signing happens even if DKMS skips it
install -Dm0755 /dev/stdin "$SIGN_HELPER" <<'EOH'
#!/usr/bin/env bash
# Usage: sign-with-mok <kernelversion> <path-to-ko or glob...>
set -euo pipefail
KVER="$1"; shift
KEY="$(awk -F= '/^mok_signing_key=/{gsub(/"/,"",$2);print $2}' /etc/dkms/framework.conf /etc/dkms/framework.conf.d/* 2>/dev/null | tail -n1)"
CRT="$(awk -F= '/^mok_certificate=/{gsub(/"/,"",$2);print $2}' /etc/dkms/framework.conf /etc/dkms/framework.conf.d/* 2>/dev/null | tail -n1)"
[ -z "$KEY" ] && KEY="/root/secureboot/mok/MOK.priv"
[ -z "$CRT" ] && CRT="/root/secureboot/mok/MOK.der"
TOOL="/lib/modules/${KVER}/build/scripts/sign-file"
for m in "$@"; do
  [ -e "$m" ] || continue
  "$TOOL" sha256 "$KEY" "$CRT" "$m" || true
done
EOH

install -Dm0755 /dev/stdin "$POSTINST_HOOK" <<'EOF'
#!/usr/bin/env bash
# Called as: zz-sign-nvidia <kernel-version> <kernel-image>
KVER="$1"
PAT="/lib/modules/${KVER}/updates/dkms"
if [ -d "$PAT" ]; then
  /usr/local/sbin/sign-with-mok "$KVER" "$PAT"/nvidia*.ko "$PAT"/*nvidia*.ko 2>/dev/null || true
  depmod "$KVER" || true
fi
exit 0
EOF

install -Dm0755 /dev/stdin "$DKMS_POSTBUILD" <<'EOF'
#!/usr/bin/env bash
# DKMS post-build: <module> <module-version> <kernelver> <arch>
MOD="$1"; VER="$2"; KVER="$3"
PAT="/lib/modules/${KVER}/updates/dkms"
if [ -d "$PAT" ]; then
  /usr/local/sbin/sign-with-mok "$KVER" "$PAT"/${MOD}*.ko "$PAT"/*${MOD}*.ko "$PAT"/nvidia*.ko 2>/dev/null || true
  depmod "$KVER" || true
fi
exit 0
EOF

ok "Module signing hooks installed."

# If SB is enabled, request enrollment (one-time at next boot)
if [[ "$SB" == "enabled" ]]; then
  say "Requesting MOK enrollment (you'll create a one-time password now; confirm it at next boot)..."
  mokutil --import "$MOK_CRT_DER" || true
  warn "On next reboot: Blue 'MOK Manager' → Enroll MOK → Continue → Yes → enter the password → Reboot."
fi

# --- Install mainline helper & kernel -------------------------------------------
say "Installing the Ubuntu Mainline helper..."
apt-get install -y mainline >/dev/null
ok "mainline installed."

say "Blacklisting NOVA/Nouveau to avoid conflicts with proprietary NVIDIA..."
install -Dm644 /dev/stdin "$BLACKLIST_FILE" <<'EOF'
blacklist nova_core
blacklist nova_drm
blacklist nouveau
options nouveau modeset=0
EOF
ok "Blacklist written to $BLACKLIST_FILE"

say "Installing Linux ${KVER_MAJOR} (build ${KVER_TAG})..."
if ! dpkg -l | grep -q "linux-image-${KVER_TAG}-generic"; then
  mainline --install "${KVER_MAJOR}"
else
  ok "Kernel ${KVER_TAG} already installed."
fi

# --- Build & sign NVIDIA module for the target kernel ---------------------------
say "Rebuilding NVIDIA DKMS modules for ${KVER_FULL}..."
dkms autoinstall -k "${KVER_FULL}" || true

if dkms status -k "${KVER_FULL}" | grep -Eq 'nvidia/.*/(built|installed)'; then
  ok "NVIDIA DKMS module built for ${KVER_FULL}."
else
  die "NVIDIA DKMS build failed for ${KVER_FULL}. Check /var/lib/dkms/nvidia/*/build/make.log"
fi

say "Signing NVIDIA modules for ${KVER_FULL} with MOK..."
/usr/local/sbin/sign-with-mok "${KVER_FULL}" /lib/modules/"${KVER_FULL}"/updates/dkms/*.ko 2>/dev/null || true
depmod "${KVER_FULL}" || true

# --- Refresh boot files ---------------------------------------------------------
say "Updating initramfs & kernelstub..."
update-initramfs -u -k "${KVER_FULL}" >/dev/null 2>&1 || true
kernelstub --force >/dev/null 2>&1 || true
ok "Boot files refreshed."

# --- Optional: set 6.15.4 as default via kernelstub -----------------------------
if [[ "$SET_DEFAULT" -eq 1 ]]; then
  say "Setting ${KVER_MAJOR} as the default boot entry via kernelstub..."
  KIMG="/boot/vmlinuz-${KVER_FULL}"
  IIMG="/boot/initrd.img-${KVER_FULL}"
  [[ -f "$KIMG" && -f "$IIMG" ]] || die "Kernel image or initrd not found: $KIMG / $IIMG"
  kernelstub -v -k "$KIMG" -i "$IIMG"
  ok "Default boot set to ${KVER_MAJOR}."
fi

# --- Verify & finish ------------------------------------------------------------
SIG="(unsigned)"
if [[ -e "/lib/modules/${KVER_FULL}/updates/dkms/nvidia.ko" ]]; then
  SIG=$(modinfo -F signer /lib/modules/${KVER_FULL}/updates/dkms/nvidia.ko 2>/dev/null || echo "(unsigned)")
fi

echo
ok "DONE: Kernel ${KVER_MAJOR} + NVIDIA ${installed_ver} ready."
say "Module signer (nvidia.ko): ${SIG}"
say "Reboot, press SPACE for the boot menu, and choose the ${KVER_MAJOR} entry."
if [[ "$SB" == "enabled" ]]; then
  warn "Complete the on-boot MOK enrollment so the signed modules can load under Secure Boot."
fi
if [[ "$SET_DEFAULT" -eq 1 ]]; then
  say "This kernel was set as the default boot. You can revert with another kernelstub call."
fi
