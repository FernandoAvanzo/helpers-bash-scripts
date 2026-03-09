#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-check}"
ALLOW_DEV_PPA="${ALLOW_DEV_PPA:-0}"

STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/var/tmp/pop-ipu6-repair-v3"
STATE_DIR="${BASE_DIR}/${STAMP}"
LATEST_LINK="${BASE_DIR}/latest"

LOG_FILE="${STATE_DIR}/run.log"
REPORT_FILE="${STATE_DIR}/report.txt"
PKG_BEFORE_FILE="${STATE_DIR}/packages-before.txt"
PKG_AFTER_FILE="${STATE_DIR}/packages-after.txt"
REMOVED_FILE="${STATE_DIR}/removed-packages.txt"
INSTALLED_FILE="${STATE_DIR}/installed-packages.txt"
PATCH_FILE="${STATE_DIR}/ov02c10-26mhz.patch"
PATCHED_SOURCE_ARCHIVE="${STATE_DIR}/ov02c10-source-backup.tar.gz"
PATCH_META_FILE="${STATE_DIR}/patch-meta.env"
DISABLED_UNITS_FILE="${STATE_DIR}/disabled-units.txt"
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"
ROLLBACK_SCRIPT="${STATE_DIR}/rollback.sh"

log()  { printf '[INFO] %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
warn() { printf '[WARN] %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
err()  { printf '[ERR ] %s\n' "$*" | tee -a "$LOG_FILE" >&2; }

on_error() {
  local exit_code=$?
  err "Command failed at line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  err "See: ${LOG_FILE}"
  exit "$exit_code"
}
trap on_error ERR

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 1; }; }
is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }
require_root() { is_root || { err "This mode requires root. Re-run with sudo."; exit 1; }; }

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
  ln -sfn "$STATE_DIR" "$LATEST_LINK"
  : > "$LOG_FILE"; : > "$REPORT_FILE"; : > "$REMOVED_FILE"; : > "$INSTALLED_FILE"; : > "$DISABLED_UNITS_FILE"
}

append_report() {
  {
    printf '\n==== %s ====\n' "$1"
    shift
    "$@" 2>&1 || true
  } | tee -a "$REPORT_FILE" >> "$LOG_FILE"
}

append_text() {
  {
    printf '\n==== %s ====\n' "$1"
    shift
    printf '%s\n' "$@"
  } | tee -a "$REPORT_FILE" >> "$LOG_FILE"
}

run_capture() { local title="$1"; shift; append_report "$title" "$@"; }

have_pkg_installed() { dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" 2>/dev/null | grep -q '^ii'; }
pkg_has_candidate() { apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: ' && ! apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: (none)'; }
installed_pkgs_matching() { dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | grep -E "$1" || true; }

dev_ppa_enabled() {
  grep -RqsE '(ppa\.launchpadcontent\.net|launchpadcontent\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ppa:oem-solutions-group/intel-ipu[67]' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
}

pkg_candidate_is_dev_ppa() {
  local pkg="$1"
  apt-cache policy "$pkg" 2>/dev/null | grep -Eq '(ppa\.launchpadcontent\.net|launchpadcontent\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ubuntu22\.04'
}

recommended_hal_pkg() {
  command -v ubuntu-drivers >/dev/null 2>&1 && ubuntu-drivers list 2>/dev/null | awk '/^libcamhal-/ {print; exit}'
}

has_clock_mismatch_error() { dmesg 2>/dev/null | grep -q 'ov02c10 .*external clock 26000000 is not supported'; }
has_failed_sensor_probe() { dmesg 2>/dev/null | grep -q 'ov02c10 .*probe with driver ov02c10 failed with error -22'; }
has_ipu6_controller() { dmesg 2>/dev/null | grep -q 'intel-ipu6 '; }
has_user_visible_camera() { command -v cam >/dev/null 2>&1 && cam -l 2>/dev/null | grep -qE '^[0-9]+:'; }

save_basic_state() {
  log "Collecting diagnostics in ${STATE_DIR}"
  run_capture "date" date
  run_capture "os-release" cat /etc/os-release
  run_capture "uname" uname -a
  run_capture "hostnamectl" hostnamectl
  run_capture "kernel cmdline" cat /proc/cmdline
  run_capture "dpkg audit" dpkg --audit
  run_capture "dkms status" dkms status
  run_capture "ubuntu-drivers list" bash -lc 'command -v ubuntu-drivers >/dev/null && ubuntu-drivers list || echo "ubuntu-drivers not installed"'
  run_capture "apt policy intel-ipu6-dkms" apt-cache policy intel-ipu6-dkms
  run_capture "apt policy libcamera-tools" apt-cache policy libcamera-tools
  run_capture "apt policy recommended hal" bash -lc 'pkg="$(command -v ubuntu-drivers >/dev/null 2>&1 && ubuntu-drivers list 2>/dev/null | awk "/^libcamhal-/ {print; exit}")"; if [[ -n "$pkg" ]]; then apt-cache policy "$pkg"; else echo "no recommended libcamhal package reported"; fi'
  run_capture "v4l2 devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  run_capture "cam list" bash -lc 'command -v cam >/dev/null && cam -l || echo "cam not installed"'
  run_capture "sysfs video names" bash -lc 'for f in /sys/class/video4linux/*/name; do [[ -e "$f" ]] && printf "%s: %s\n" "$f" "$(cat "$f")"; done'
  run_capture "find ov02c10 source" bash -lc "find /usr/src /var/lib/dkms /lib/modules/$(uname -r) -type f -name 'ov02c10.c' 2>/dev/null || true"
  run_capture "find dkms.conf near ov02c10" bash -lc "find /usr/src /var/lib/dkms -type f -name 'dkms.conf' 2>/dev/null | grep -Ei 'ipu|camera|media' || true"
  run_capture "journalctl camera filtered" bash -lc "journalctl -b -k --no-pager | grep -Ei 'ov02c10|ipu6|SAM0430|v4l2|camera' || true"
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null | sort > "$PKG_BEFORE_FILE" || true
  tar -czf "$APT_SOURCES_TAR" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true
  append_text "environment summary"     "kernel=$(uname -r)"     "dev-ppa-enabled=$(dev_ppa_enabled && echo yes || echo no)"     "has-ipu6-controller=$(has_ipu6_controller && echo yes || echo no)"     "has-ov02c10-26000000-mismatch=$(has_clock_mismatch_error && echo yes || echo no)"     "has-sensor-probe-failure=$(has_failed_sensor_probe && echo yes || echo no)"     "has-user-visible-camera=$(has_user_visible_camera && echo yes || echo no)"     "recommended-hal=$(recommended_hal_pkg || true)"
}

stop_relay_services() { local unit; for unit in ipu6-relay.service v4l2-relayd.service; do systemctl stop "$unit" >/dev/null 2>&1 || true; done; }

disable_broken_custom_units() {
  local unit_path="/etc/systemd/system/ipu6-relay.service"
  if [[ -f "$unit_path" ]] && grep -q 'StartLimitIntervalSec' "$unit_path"; then
    warn "Disabling malformed custom relay unit: $unit_path"
    systemctl disable --now ipu6-relay.service >/dev/null 2>&1 || true
    mv -f "$unit_path" "${unit_path}.disabled.${STAMP}"
    echo "ipu6-relay.service" >> "$DISABLED_UNITS_FILE"
    systemctl daemon-reload
  fi
}

remove_dev_ppa_sources() {
  local matched=0
  if command -v add-apt-repository >/dev/null 2>&1; then
    add-apt-repository -y --remove ppa:oem-solutions-group/intel-ipu6 >/dev/null 2>&1 || true
    add-apt-repository -y --remove ppa:oem-solutions-group/intel-ipu7 >/dev/null 2>&1 || true
  fi
  while IFS= read -r -d '' file; do
    if grep -qE '(ppa\.launchpadcontent\.net|launchpadcontent\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ppa:oem-solutions-group/intel-ipu[67]' "$file"; then
      matched=1
      warn "Disabling Intel IPU development source in: $file"
      sed -i -E 's@^deb @# disabled-by-pop-ipu6-repair deb @g' "$file" || true
      sed -i -E 's@^URIs: https?://ppa\.launchpadcontent\.net/oem-solutions-group/intel-ipu[67]/ubuntu@# disabled-by-pop-ipu6-repair &@g' "$file" || true
    fi
  done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null)
  if grep -qE '(ppa\.launchpadcontent\.net|launchpadcontent\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ppa:oem-solutions-group/intel-ipu[67]' /etc/apt/sources.list 2>/dev/null; then
    matched=1
    sed -i -E 's@^deb .*oem-solutions-group/intel-ipu[67].*$@# disabled-by-pop-ipu6-repair &@g' /etc/apt/sources.list || true
  fi
  (( matched == 1 )) && systemctl daemon-reload || true
}

remove_stale_ipu_userspace() {
  local -a purge_list=()
  mapfile -t purge_list < <(installed_pkgs_matching '^(intel-ipu6-dkms|intel-usbio-dkms|gstreamer1\.0-icamera|v4l2-relayd|v4l2loopback-dkms)$' | sort -u)
  if ((${#purge_list[@]} > 0)); then
    warn "Purging stale or mismatched bridge/DKMS packages:"
    printf '  %s\n' "${purge_list[@]}" | tee -a "$LOG_FILE" >&2
    printf '%s\n' "${purge_list[@]}" > "$REMOVED_FILE"
    apt-get purge -y "${purge_list[@]}"
  fi
}

install_test_tools() {
  local pkg
  local -a base_pkgs=(v4l-utils media-utils gstreamer1.0-libcamera libcamera-tools)
  for pkg in "${base_pkgs[@]}"; do
    if pkg_has_candidate "$pkg" && ! have_pkg_installed "$pkg"; then
      log "Installing test tool package: $pkg"
      apt-get install -y --no-install-recommends "$pkg"
      echo "$pkg" >> "$INSTALLED_FILE"
    fi
  done
}

maybe_install_hal() {
  local hal_pkg
  hal_pkg="$(recommended_hal_pkg || true)"
  [[ -z "$hal_pkg" ]] && { warn "ubuntu-drivers did not report a libcamhal-* package. Skipping HAL install."; return 0; }
  have_pkg_installed "$hal_pkg" && { log "HAL package already installed: $hal_pkg"; return 0; }
  pkg_has_candidate "$hal_pkg" || { warn "No install candidate found for $hal_pkg"; return 0; }
  if pkg_candidate_is_dev_ppa "$hal_pkg" && [[ "$ALLOW_DEV_PPA" != "1" ]]; then
    warn "Skipping $hal_pkg because the candidate appears to come from a development PPA / foreign release."
    warn "To explicitly allow that risky path: sudo ALLOW_DEV_PPA=1 bash $SCRIPT_NAME safe-fix"
    return 0
  fi
  log "Installing HAL package: $hal_pkg"
  apt-get install -y --no-install-recommends "$hal_pkg"
  echo "$hal_pkg" >> "$INSTALLED_FILE"
}

repair_package_state() { export DEBIAN_FRONTEND=noninteractive; dpkg --configure -a; apt-get -f install -y; apt-get autoremove --purge -y || true; apt-get autoclean -y || true; }

find_ov02c10_source() {
  local p
  for p in /usr/src/*/drivers/media/i2c/ov02c10.c /usr/src/drivers/media/i2c/ov02c10.c /var/lib/dkms/*/*/build/drivers/media/i2c/ov02c10.c /var/lib/dkms/*/*/source/drivers/media/i2c/ov02c10.c; do
    [[ -f "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

find_dkms_conf_for_source() {
  local src="$1" dir
  dir="$(dirname "$src")"
  while [[ "$dir" != "/" && "$dir" != "." ]]; do
    [[ -f "$dir/dkms.conf" ]] && { printf '%s\n' "$dir/dkms.conf"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

extract_dkms_var() {
  local file="$1" key="$2"
  awk -F= -v k="$key" '$1 ~ ("^" k "$") { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^"/, "", $2); gsub(/"$/, "", $2); print $2; exit }' "$file"
}

write_patch_file() {
  cat > "$PATCH_FILE" <<'EOF'
--- ov02c10.c.orig
+++ ov02c10.c
@@
-#define OV02C10_MCLK			19200000
+#define OV02C10_MCLK			26000000
EOF
}

patch_ov02c10_source() {
  local src="$1"
  grep -qE '#define[[:space:]]+OV02C10_MCLK[[:space:]]+26000000' "$src" && { log "ov02c10 source already appears patched for 26 MHz."; return 0; }
  grep -qE '#define[[:space:]]+OV02C10_MCLK[[:space:]]+19200000' "$src" || { err "Could not find the expected OV02C10_MCLK 19200000 define in: $src"; err "Auto-patching is intentionally conservative and refuses to guess."; exit 1; }
  tar -czf "$PATCHED_SOURCE_ARCHIVE" "$src"
  write_patch_file
  cp -a "$src" "${src}.orig.${STAMP}"
  sed -i -E 's@(#define[[:space:]]+OV02C10_MCLK[[:space:]]+)19200000@\126000000@' "$src"
  log "Patched ov02c10 source to 26 MHz: $src"
}

rebuild_dkms_tree() {
  local dkms_conf="$1" src_dir pkg_name pkg_ver current_kernel dkms_status_out
  src_dir="$(dirname "$dkms_conf")"
  pkg_name="$(extract_dkms_var "$dkms_conf" PACKAGE_NAME)"
  pkg_ver="$(extract_dkms_var "$dkms_conf" PACKAGE_VERSION)"
  current_kernel="$(uname -r)"
  [[ -n "$pkg_name" && -n "$pkg_ver" ]] || { err "Could not parse PACKAGE_NAME/PACKAGE_VERSION from $dkms_conf"; exit 1; }
  {
    printf 'OV02C10_SOURCE=%q\n' "$(find_ov02c10_source)"
    printf 'DKMS_CONF=%q\n' "$dkms_conf"
    printf 'DKMS_SRC_DIR=%q\n' "$src_dir"
    printf 'DKMS_PKG_NAME=%q\n' "$pkg_name"
    printf 'DKMS_PKG_VER=%q\n' "$pkg_ver"
    printf 'KERNEL_REL=%q\n' "$current_kernel"
  } > "$PATCH_META_FILE"
  log "Rebuilding DKMS module ${pkg_name}/${pkg_ver} for kernel ${current_kernel}"
  dkms_status_out="$(dkms status -m "$pkg_name" -v "$pkg_ver" 2>/dev/null || true)"
  [[ -z "$dkms_status_out" ]] && dkms add -m "$pkg_name" -v "$pkg_ver" || true
  dkms build -m "$pkg_name" -v "$pkg_ver" -k "$current_kernel" --force
  dkms install -m "$pkg_name" -v "$pkg_ver" -k "$current_kernel" --force
  depmod "$current_kernel"
}

write_rollback_script() {
  cat > "$ROLLBACK_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="${1:-}"
if [[ -z "$STATE_DIR" || ! -d "$STATE_DIR" ]]; then
  echo "Usage: sudo bash rollback.sh /var/tmp/pop-ipu6-repair-v3/<timestamp>" >&2
  exit 1
fi
PATCH_META_FILE="${STATE_DIR}/patch-meta.env"
PATCHED_SOURCE_ARCHIVE="${STATE_DIR}/ov02c10-source-backup.tar.gz"
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"
INSTALLED_FILE="${STATE_DIR}/installed-packages.txt"

[[ -f "$APT_SOURCES_TAR" ]] && { echo "[INFO] Restoring saved APT source files"; tar -xzf "$APT_SOURCES_TAR" -C / || true; }
[[ -f "$PATCHED_SOURCE_ARCHIVE" ]] && { echo "[INFO] Restoring original ov02c10 source file"; tar -xzf "$PATCHED_SOURCE_ARCHIVE" -C / || true; }

if [[ -f "$PATCH_META_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PATCH_META_FILE"
  if [[ -n "${DKMS_PKG_NAME:-}" && -n "${DKMS_PKG_VER:-}" && -n "${KERNEL_REL:-}" ]]; then
    echo "[INFO] Rebuilding original DKMS module ${DKMS_PKG_NAME}/${DKMS_PKG_VER} for ${KERNEL_REL}"
    dkms build -m "$DKMS_PKG_NAME" -v "$DKMS_PKG_VER" -k "$KERNEL_REL" --force || true
    dkms install -m "$DKMS_PKG_NAME" -v "$DKMS_PKG_VER" -k "$KERNEL_REL" --force || true
    depmod "$KERNEL_REL" || true
  fi
fi

if [[ -s "$INSTALLED_FILE" ]]; then
  echo "[INFO] Removing packages that v3 installed"
  mapfile -t pkgs < "$INSTALLED_FILE"
  apt-get purge -y "${pkgs[@]}" || true
fi

apt-get update || true
apt-get -f install -y || true
echo "[INFO] Rollback attempt completed."
echo "[INFO] Reboot is recommended after rollback."
EOF
  chmod +x "$ROLLBACK_SCRIPT"
}

post_checks() {
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null | sort > "$PKG_AFTER_FILE" || true
  run_capture "post dkms status" dkms status
  run_capture "post cam list" bash -lc 'command -v cam >/dev/null && cam -l || echo "cam not installed"'
  run_capture "post v4l2 devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  run_capture "post journalctl camera filtered" bash -lc "journalctl -b -k --no-pager | grep -Ei 'ov02c10|ipu6|SAM0430|v4l2|camera' || true"
}

print_summary() {
  echo
  echo "State directory: $STATE_DIR"
  echo "Main report:     $REPORT_FILE"
  echo "Main log:        $LOG_FILE"
  echo "Rollback helper: sudo bash $ROLLBACK_SCRIPT $STATE_DIR"
  echo
  echo "Suggested next checks:"
  echo "  1) cam -l"
  echo "  2) v4l2-ctl --list-devices"
  echo "  3) sudo journalctl -b -k | grep -Ei 'ov02c10|ipu6|camera'"
  echo "  4) sudo reboot"
  echo "  5) test in Firefox/Chrome afterwards"
}

mode_check() { save_basic_state; post_checks; write_rollback_script; }

mode_safe_fix() {
  require_root
  save_basic_state
  log "Starting safe fix mode"
  disable_broken_custom_units
  stop_relay_services
  remove_dev_ppa_sources
  apt-get update
  remove_stale_ipu_userspace
  repair_package_state
  install_test_tools
  maybe_install_hal
  post_checks
  write_rollback_script
}

mode_experimental_clock_fix() {
  require_root
  save_basic_state
  has_clock_mismatch_error || { warn "The exact ov02c10 26 MHz clock mismatch was not found in dmesg."; warn "This experimental patch is intended only for that specific failure."; exit 1; }
  log "Starting experimental ov02c10 26 MHz patch mode"
  apt-get update
  install_test_tools
  local src dkms_conf
  src="$(find_ov02c10_source || true)"
  [[ -n "$src" ]] || { err "Could not locate ov02c10.c under /usr/src or /var/lib/dkms."; err "Automatic patching is not possible on this system with the currently available local sources."; exit 1; }
  dkms_conf="$(find_dkms_conf_for_source "$src" || true)"
  [[ -n "$dkms_conf" ]] || { err "Found ov02c10.c but no nearby dkms.conf:"; err "  $src"; err "Automatic rebuild is not possible without a DKMS source tree."; exit 1; }
  patch_ov02c10_source "$src"
  rebuild_dkms_tree "$dkms_conf"
  maybe_install_hal
  post_checks
  write_rollback_script
  warn "Experimental patch applied. A reboot is strongly recommended."
}

main() {
  need_cmd bash; need_cmd uname; need_cmd dpkg-query; need_cmd dpkg; need_cmd apt-get; need_cmd journalctl
  ensure_state_dir
  case "$MODE" in
    check) mode_check ;;
    safe-fix) mode_safe_fix ;;
    experimental-ov02c10-26mhz) mode_experimental_clock_fix ;;
    *)
      cat >&2 <<EOF
Usage: $SCRIPT_NAME [check|safe-fix|experimental-ov02c10-26mhz]

Modes:
  check                       Collect diagnostics only.
  safe-fix                    Clean stale IPU6 packages, disable risky PPA/service, install test tools.
  experimental-ov02c10-26mhz Patch ov02c10 from 19.2 MHz to 26 MHz and rebuild via DKMS, only if local source exists.

Environment:
  ALLOW_DEV_PPA=1             Allow HAL install from a risky development PPA / foreign release.
EOF
      exit 1
      ;;
  esac
  print_summary
}

main "$@"
