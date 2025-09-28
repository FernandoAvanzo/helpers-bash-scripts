#!/usr/bin/env bash
# ipu6_install_v36.sh
# Purpose: Stop chasing overlays. Prove compatibility. If Jammy can't satisfy HAL glibc/GLIBCXX,
# either auto-downgrade to Jammy-compatible HAL (if verifiably available) or tell you to upgrade OS.

set -euo pipefail

log(){ echo "[ipu6_install_v36] $*" ; }
warn(){ echo "[ipu6_install_v36][WARN] $*" >&2 ; }
err(){ echo "[ipu6_install_v36][ERROR] $*" >&2 ; exit 1; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || err "Missing required tool: $1"; }

need_cmd awk; need_cmd sed; need_cmd sort; need_cmd grep; need_cmd objdump; need_cmd strings
need_cmd dpkg; need_cmd apt-get; need_cmd apt-cache; need_cmd ldd

log "Kernel: $(uname -r)"

# 0) Base sanity that we won't change kernel side accidentally
if ls /dev/video* 2>/dev/null | grep -qE '/dev/video[0-9]+' ; then
  log "OK: IPU6 video/media nodes exist."
else
  warn "No /dev/video* found. Kernel/IPU6 might not be up; continuing because earlier runs showed nodes."
fi

# 1) System glibc version (Jammy is 2.35)
sys_glibc="$(ldd --version 2>&1 | awk 'NR==1{print $NF}')"
log "System glibc: ${sys_glibc}"

# 2) Ensure helper tools present (no-op if already installed)
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq binutils gstreamer1.0-tools v4l-utils >/dev/null || true

# 3) Gather HAL/IPA objects to audit
#    We look at the icamerasrc plugin and known HAL plugin and IPA libs if present
declare -a cand
[ -f /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgsticamerasrc.so ] && cand+=("/usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgsticamerasrc.so")
[ -f /usr/lib/libcamhal/plugins/ipu6epmtl.so ] && cand+=("/usr/lib/libcamhal/plugins/ipu6epmtl.so")
# Pull direct deps we care about (libgcss-ipu6*, libbroxton_ia_pal*, libia_*ipu6*)
for so in /lib/libgcss-ipu6*.so.* /lib/libbroxton_ia_pal-*.so.* /lib/libia_*ipu6*.so.* ; do
  [ -f "$so" ] && cand+=("$so")
done

if [ "${#cand[@]}" -eq 0 ]; then
  warn "Could not find HAL/IPA .so files to audit. If you haven't installed them, do so on a compatible OS (24.04 recommended)."
  exit 0
fi

# Helper: highest required GLIBC from a binary
highest_glibc_req(){
  local f="$1"
  # Look for GLIBC_* version tags in the dynsym/versym
  { objdump -T "$f" 2>/dev/null | grep -o 'GLIBC_[0-9]\+\.[0-9]\+' || strings "$f" | grep -o 'GLIBC_[0-9]\+\.[0-9]\+'; } \
    | sed 's/^GLIBC_//' | sort -V | tail -1
}

# Helper: whether a binary requires GLIBCXX_3.4.32
needs_glibcxx_332(){
  local f="$1"
  { objdump -T "$f" 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32'; } || { strings "$f" | grep -q 'GLIBCXX_3\.4\.32'; }
}

# 4) Audit requirements
need_glibc="0.0"
need_glibcxx332=0
for f in "${cand[@]}"; do
  req="$(highest_glibc_req "$f" || true)"
  [ -n "$req" ] && need_glibc="$(printf '%s\n%s\n' "$need_glibc" "$req" | sort -V | tail -1)"
  if needs_glibcxx_332 "$f"; then need_glibcxx332=1; fi
done

log "Detected highest GLIBC requirement among HAL/IPA: ${need_glibc:-unknown}"
[ $need_glibcxx332 -eq 1 ] && log "Detected GLIBCXX_3.4.32 requirement in HAL/IPA." || log "No GLIBCXX_3.4.32 requirement detected."

# 5) Compare versions using dpkg --compare-versions (lexical, not arithmetic)
version_le(){ dpkg --compare-versions "$1" le "$2"; }
version_gt(){ dpkg --compare-versions "$1" gt "$2"; }

if [ -n "$need_glibc" ] && version_gt "$need_glibc" "$sys_glibc"; then
  warn "HAL/IPA require GLIBC >= ${need_glibc}, but system is ${sys_glibc}. This cannot be fixed with LD_LIBRARY_PATH."
  # Optional: attempt Jammy-compatible rollback if such packages exist and are truly <=2.35
  # Package set taken from your apt errors (libipu6 deps) and HAL bits:
  pkgs=(libcamhal-ipu6ep0 libcamhal-common libcamhal0 gstreamer1.0-icamera \
    libipu6 libbroxton-ia-pal0 libgcss0 libia-aiqb-parser0 libia-aiq-file-debug0 libia-aiq0 \
    libia-bcomp0 libia-cca0 libia-ccat0 libia-dvs0 libia-emd-decoder0 libia-exc0 \
    libia-lard0 libia-log0 libia-ltm0 libia-mkn0 libia-nvm0)

  log "Trying a safe auto-downgrade to Jammy-compatible HAL/IPA (if available in PPA)…"
  apt-get update -qq || true

  # find oldest available versions (most likely to have stayed on Jammy builders)
  declare -a pinned; pinned=()
  for p in "${pkgs[@]}"; do
    # list versions available; pick the oldest one
    v="$(apt-cache madison "$p" | awk '{print $3}' | sort -V | head -1 || true)"
    [ -z "$v" ] && continue
    # fetch the .deb without installing to inspect GLIBC requirement
    tmpd="$(mktemp -d)"; pushd "$tmpd" >/dev/null
    if apt-get download "${p}=${v}" >/dev/null 2>&1; then
      deb="$(ls *.deb 2>/dev/null || true)"
      if [ -n "$deb" ]; then
        mkdir -p x && dpkg-deb -x "$deb" x
        # inspect any .so in x/ (best-effort)
        reqs="$( (find x -type f -name '*.so*' -print0 | xargs -0r objdump -T 2>/dev/null | grep -o 'GLIBC_[0-9]\+\.[0-9]\+' || true) \
          | sed 's/^GLIBC_//' | sort -V | tail -1 )"
        if [ -z "$reqs" ] || version_le "${reqs}" "${sys_glibc}"; then
          pinned+=("${p}=${v}")
        else
          warn "Skipping ${p}=${v} (needs GLIBC ${reqs})."
        fi
      fi
    fi
    popd >/dev/null
    rm -rf "$tmpd"
  done

  if [ "${#pinned[@]}" -eq 0 ]; then
    err "No Jammy-compatible HAL/IPA versions found in PPA. Recommended: upgrade to Pop!_OS/Ubuntu 24.04 (glibc 2.39)."
  fi

  log "Attempting to install Jammy-compatible set: ${pinned[*]}"
  # Install all at once, allow downgrades, keep deps consistent
  if ! apt-get install -y --allow-downgrades --allow-change-held-packages "${pinned[@]}"; then
    err "Downgrade attempt failed. Please upgrade OS to 24.04."
  fi

  # Re-audit after install
  cand_after=()
  [ -f /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgsticamerasrc.so ] && cand_after+=("/usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgsticamerasrc.so")
  [ -f /usr/lib/libcamhal/plugins/ipu6epmtl.so ] && cand_after+=("/usr/lib/libcamhal/plugins/ipu6epmtl.so")
  for so in /lib/libgcss-ipu6*.so.* /lib/libbroxton_ia_pal-*.so.* /lib/libia_*ipu6*.so.* ; do
    [ -f "$so" ] && cand_after+=("$so")
  done

  need_glibc2="0.0"
  need_glibcxx332_after=0
  for f in "${cand_after[@]}"; do
    req="$(highest_glibc_req "$f" || true)"
    [ -n "$req" ] && need_glibc2="$(printf '%s\n%s\n' "$need_glibc2" "$req" | sort -V | tail -1)"
    if needs_glibcxx_332 "$f"; then need_glibcxx332_after=1; fi
  done

  log "After rollback, highest GLIBC required: ${need_glibc2:-unknown}"
  if [ -n "$need_glibc2" ] && version_gt "$need_glibc2" "$sys_glibc"; then
    err "Even the oldest available HAL/IPA still require GLIBC > ${sys_glibc}. Please upgrade to 24.04."
  fi

  if [ $need_glibcxx332_after -eq 1 ]; then
    warn "HAL still needs GLIBCXX_3.4.32; Jammy's stock libstdc++ may not provide it. Checking…"
    if ! strings /usr/lib/x86_64-linux-gnu/libstdc++.so.6 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32'; then
      err "Jammy libstdc++ lacks GLIBCXX_3.4.32. Installing a newer libstdc++ would again pull GLIBC>=2.36 — dead end on 22.04. Please upgrade to 24.04."
    fi
  fi
fi

# If we got here, HAL/IPA GLIBC is compatible with the OS (or we didn't have any GLIBC gating),
# so test plugin load *without* any libc/libstdc++ overlay (to avoid glibc contamination).
log "Running a minimal plugin load test (no overlays):"
if GST_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/gstreamer-1.0 gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
  log "icamerasrc loads. Try: gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink -v"
  exit 0
else
  warn "icamerasrc still failed to load. Check dmesg for IPU6 sensor/firmware lines and re-run on 24.04 if GLIBC was the blocker."
  exit 1
fi
