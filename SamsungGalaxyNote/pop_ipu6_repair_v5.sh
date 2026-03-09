#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-check}"
ALLOW_THIRD_PARTY="${ALLOW_THIRD_PARTY:-1}"
COMMUNITY_REF="${COMMUNITY_REF:-main}"
COMMUNITY_REPO_TARBALL="${COMMUNITY_REPO_TARBALL:-https://github.com/Andycodeman/samsung-galaxy-book4-linux-fixes/archive/refs/heads/${COMMUNITY_REF}.tar.gz}"

STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/var/tmp/pop-ipu6-repair-v5"
STATE_DIR="${BASE_DIR}/${STAMP}"
LATEST_LINK="${BASE_DIR}/latest"

LOG_FILE="${STATE_DIR}/run.log"
REPORT_FILE="${STATE_DIR}/report.txt"
PKG_BEFORE_FILE="${STATE_DIR}/packages-before.txt"
PKG_AFTER_FILE="${STATE_DIR}/packages-after.txt"
REMOVED_FILE="${STATE_DIR}/removed-packages.txt"
INSTALLED_FILE="${STATE_DIR}/installed-packages.txt"
DISABLED_UNITS_FILE="${STATE_DIR}/disabled-units.txt"
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"
ROLLBACK_SCRIPT="${STATE_DIR}/rollback.sh"

COMMUNITY_ROOT="${STATE_DIR}/samsung-galaxy-book4-linux-fixes"
COMMUNITY_TARBALL="${STATE_DIR}/community.tar.gz"

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
  run_capture "secure boot state" bash -lc 'command -v mokutil >/dev/null && mokutil --sb-state || echo "mokutil not installed"'
  run_capture "dpkg audit" dpkg --audit
  run_capture "dkms status" dkms status
  run_capture "apt broken-check" apt-get -s -o Debug::pkgProblemResolver=yes install -f
  run_capture "ubuntu-drivers list" bash -lc 'command -v ubuntu-drivers >/dev/null && ubuntu-drivers list || echo "ubuntu-drivers not installed"'
  run_capture "v4l2 devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  run_capture "cam list" bash -lc 'command -v cam >/dev/null && cam -l || echo "cam not installed"'
  run_capture "pipewire services" bash -lc 'systemctl --user --no-pager --full status pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true'
  run_capture "lsmod filtered" bash -lc "lsmod | grep -E '(^ipu6|^intel_.*ipu|^intel_vsc|^vsc|ivsc|icvs|usbio|v4l2loopback|samsung_galaxybook)' || true"
  run_capture "sysfs video names" bash -lc 'for f in /sys/class/video4linux/*/name; do [[ -e "$f" ]] && printf "%s: %s\n" "$f" "$(cat "$f")"; done'
  run_capture "sources matching intel ipu" bash -lc "grep -RInE '(ppa\\.launchpadcontent\\.net|launchpadcontent\\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ppa:oem-solutions-group/intel-ipu[67]' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true"
  run_capture "journalctl camera filtered" bash -lc "journalctl -b -k --no-pager | grep -Ei 'ov02c10|ipu6|SAM0430|v4l2|camera|ivsc|intel_vsc|usbio' || true"

  dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null | sort > "$PKG_BEFORE_FILE" || true
  tar -czf "$APT_SOURCES_TAR" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true

  append_text "environment summary" \
    "has-ipu6-controller=$(has_ipu6_controller && echo yes || echo no)" \
    "has-ov02c10-26000000-mismatch=$(has_clock_mismatch_error && echo yes || echo no)" \
    "has-sensor-probe-failure=$(has_failed_sensor_probe && echo yes || echo no)" \
    "has-user-visible-camera=$(has_user_visible_camera && echo yes || echo no)" \
    "community-ref=${COMMUNITY_REF}" \
    "allow-third-party=${ALLOW_THIRD_PARTY}"
}

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

repair_package_state() {
  export DEBIAN_FRONTEND=noninteractive
  dpkg --configure -a
  apt-get -f install -y
  apt-get autoremove --purge -y || true
  apt-get autoclean -y || true
}

install_wrapper_prereqs() {
  local pkg
  local -a base_pkgs=(ca-certificates curl tar git mokutil v4l-utils media-utils libcamera-tools gstreamer1.0-libcamera)
  for pkg in "${base_pkgs[@]}"; do
    if pkg_has_candidate "$pkg" && ! have_pkg_installed "$pkg"; then
      log "Installing prerequisite package: $pkg"
      apt-get install -y --no-install-recommends "$pkg"
      echo "$pkg" >> "$INSTALLED_FILE"
    fi
  done
}

fetch_community_repo() {
  need_cmd curl
  need_cmd tar
  rm -rf "$COMMUNITY_ROOT"
  log "Downloading community Samsung Galaxy Book fix repository (${COMMUNITY_REF})"
  curl -fsSL "$COMMUNITY_REPO_TARBALL" -o "$COMMUNITY_TARBALL"
  tar -xzf "$COMMUNITY_TARBALL" -C "$STATE_DIR"
  local extracted
  extracted="$(find "$STATE_DIR" -maxdepth 1 -mindepth 1 -type d -name 'samsung-galaxy-book4-linux-fixes-*' | head -n1 || true)"
  [[ -n "$extracted" ]] || { err "Could not locate extracted community repository directory."; exit 1; }
  mv "$extracted" "$COMMUNITY_ROOT"
  [[ -d "${COMMUNITY_ROOT}/webcam-fix-libcamera" ]] || { err "Missing webcam-fix-libcamera in downloaded repository."; exit 1; }
}

run_community_installer() {
  local subdir="$1"
  local target_dir="${COMMUNITY_ROOT}/${subdir}"
  [[ "$ALLOW_THIRD_PARTY" == "1" ]] || { err "Refusing to run a third-party installer because ALLOW_THIRD_PARTY is not 1."; exit 1; }
  [[ -d "$target_dir" ]] || { err "Installer directory not found: $target_dir"; exit 1; }
  [[ -x "$target_dir/install.sh" ]] || chmod +x "$target_dir/install.sh" || true
  [[ -x "$target_dir/install.sh" ]] || { err "Installer not executable: $target_dir/install.sh"; exit 1; }
  log "Running third-party installer: ${subdir}/install.sh"
  ( cd "$target_dir" && ./install.sh )
}

write_rollback_script() {
  cat > "$ROLLBACK_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="${1:-}"
if [[ -z "$STATE_DIR" || ! -d "$STATE_DIR" ]]; then
  echo "Usage: sudo bash rollback.sh /var/tmp/pop-ipu6-repair-v5/<timestamp>" >&2
  exit 1
fi
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"
INSTALLED_FILE="${STATE_DIR}/installed-packages.txt"
COMMUNITY_ROOT="${STATE_DIR}/samsung-galaxy-book4-linux-fixes"

[[ -f "$APT_SOURCES_TAR" ]] && { echo "[INFO] Restoring saved APT source files"; tar -xzf "$APT_SOURCES_TAR" -C / || true; }

if [[ -x "${COMMUNITY_ROOT}/webcam-fix-libcamera/uninstall.sh" ]]; then
  echo "[INFO] Running community webcam uninstall"
  ( cd "${COMMUNITY_ROOT}/webcam-fix-libcamera" && sudo ./uninstall.sh || true )
fi

if [[ -x "${COMMUNITY_ROOT}/mic-fix/uninstall.sh" ]]; then
  echo "[INFO] Running community mic uninstall"
  ( cd "${COMMUNITY_ROOT}/mic-fix" && sudo ./uninstall.sh || true )
fi

if [[ -s "$INSTALLED_FILE" ]]; then
  echo "[INFO] Removing packages that v5 installed"
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
  run_capture "post secure boot state" bash -lc 'command -v mokutil >/dev/null && mokutil --sb-state || echo "mokutil not installed"'
  run_capture "post dkms status" dkms status
  run_capture "post cam list" bash -lc 'command -v cam >/dev/null && cam -l || echo "cam not installed"'
  run_capture "post v4l2 devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  run_capture "post pipewire services" bash -lc 'systemctl --user --no-pager --full status pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true'
  run_capture "post journalctl camera filtered" bash -lc "journalctl -b -k --no-pager | grep -Ei 'ov02c10|ipu6|SAM0430|v4l2|camera|ivsc|intel_vsc|usbio' || true"
}

print_summary() {
  echo
  echo "State directory: $STATE_DIR"
  echo "Main report:     $REPORT_FILE"
  echo "Main log:        $LOG_FILE"
  echo "Rollback helper: sudo bash $ROLLBACK_SCRIPT $STATE_DIR"
  echo
  echo "Suggested next checks:"
  echo "  1) sudo reboot"
  echo "  2) cam -l"
  echo "  3) v4l2-ctl --list-devices"
  echo "  4) sudo journalctl -b -k | grep -Ei 'ov02c10|ipu6|camera'"
  echo "  5) test in Firefox and Chrome/Chromium"
}

mode_check() { save_basic_state; post_checks; write_rollback_script; }

mode_safe_fix() {
  require_root
  save_basic_state
  log "Starting safe fix mode"
  disable_broken_custom_units
  remove_dev_ppa_sources
  apt-get update
  remove_stale_ipu_userspace
  repair_package_state
  install_wrapper_prereqs
  post_checks
  write_rollback_script
}

mode_community_webcam_fix() {
  require_root
  save_basic_state
  log "Starting community webcam fix mode"
  disable_broken_custom_units
  remove_dev_ppa_sources
  apt-get update
  remove_stale_ipu_userspace
  repair_package_state
  install_wrapper_prereqs
  fetch_community_repo
  run_community_installer "webcam-fix-libcamera"
  post_checks
  write_rollback_script
  warn "Community webcam fix installed. Reboot is strongly recommended."
}

mode_community_full_stack() {
  require_root
  save_basic_state
  log "Starting community full stack mode (webcam + mic)"
  disable_broken_custom_units
  remove_dev_ppa_sources
  apt-get update
  remove_stale_ipu_userspace
  repair_package_state
  install_wrapper_prereqs
  fetch_community_repo
  run_community_installer "webcam-fix-libcamera"
  run_community_installer "mic-fix"
  post_checks
  write_rollback_script
  warn "Community webcam+mic fix installed. Reboot is strongly recommended."
}

main() {
  need_cmd bash; need_cmd uname; need_cmd dpkg-query; need_cmd dpkg; need_cmd apt-get; need_cmd journalctl
  ensure_state_dir
  case "$MODE" in
    check) mode_check ;;
    safe-fix) mode_safe_fix ;;
    community-webcam-fix) mode_community_webcam_fix ;;
    community-full-stack) mode_community_full_stack ;;
    *)
      cat >&2 <<EOF
Usage: $SCRIPT_NAME [check|safe-fix|community-webcam-fix|community-full-stack]

Modes:
  check                 Collect diagnostics only.
  safe-fix              Remove broken Intel IPU dev packaging and install local test tools.
  community-webcam-fix  Run the current community Book3/Book4 webcam installer.
  community-full-stack  Run the community webcam installer and the optional mic fix.

Environment:
  ALLOW_THIRD_PARTY=1   Required to run the third-party community installer (default: 1).
  COMMUNITY_REF=<ref>   GitHub ref/branch for samsung-galaxy-book4-linux-fixes (default: main).
EOF
      exit 1
      ;;
  esac
  print_summary
}

main "$@"
