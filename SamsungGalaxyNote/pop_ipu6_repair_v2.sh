#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-check}"
ALLOW_DEV_PPA="${ALLOW_DEV_PPA:-0}"

STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/var/tmp/pop-ipu6-repair-v2"
STATE_DIR="${BASE_DIR}/${STAMP}"
LATEST_LINK="${BASE_DIR}/latest"

LOG_FILE="${STATE_DIR}/run.log"
REPORT_FILE="${STATE_DIR}/report.txt"
PKG_BEFORE_FILE="${STATE_DIR}/packages-before.txt"
PKG_AFTER_FILE="${STATE_DIR}/packages-after.txt"
REMOVED_FILE="${STATE_DIR}/removed-packages.txt"
INSTALLED_FILE="${STATE_DIR}/installed-packages.txt"
ROLLBACK_SCRIPT="${STATE_DIR}/rollback.sh"
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"
APT_SOURCE_BACKUP_DIR="${STATE_DIR}/apt-source-backups"
DISABLED_UNITS_FILE="${STATE_DIR}/disabled-units.txt"

declare -a REMOVED_PKGS=()
declare -a INSTALLED_PKGS=()
declare -a DISABLED_UNITS=()

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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR" "$APT_SOURCE_BACKUP_DIR"
  ln -sfn "$STATE_DIR" "$LATEST_LINK"
  : > "$LOG_FILE"
  : > "$REPORT_FILE"
  : > "$REMOVED_FILE"
  : > "$INSTALLED_FILE"
  : > "$DISABLED_UNITS_FILE"
}

is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

require_root() {
  if ! is_root; then
    err "This mode requires root. Re-run with sudo."
    exit 1
  fi
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

run_capture() {
  local title="$1"
  shift
  append_report "$title" "$@"
}

have_pkg_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" 2>/dev/null | grep -q '^ii'
}

installed_pkgs_matching() {
  dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | grep -E "$1" || true
}

recommended_hal_pkg() {
  if command -v ubuntu-drivers >/dev/null 2>&1; then
    ubuntu-drivers list 2>/dev/null | awk '/^libcamhal-/ {print; exit}'
  fi
}

has_ipu6_kernel_stack() {
  if dmesg 2>/dev/null | grep -q 'intel-ipu6 .*Connected [1-9][0-9]* cameras'; then
    return 0
  fi
  if command -v v4l2-ctl >/dev/null 2>&1; then
    v4l2-ctl --list-devices 2>/dev/null | grep -q '^ipu6 '
    return $?
  fi
  return 1
}

dev_ppa_enabled() {
  grep -RqsE '(ppa\.launchpadcontent\.net|launchpadcontent\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ppa:oem-solutions-group/intel-ipu[67]' \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
}

pkg_candidate_is_dev_ppa() {
  local pkg="$1"
  apt-cache policy "$pkg" 2>/dev/null \
    | grep -Eq '(ppa\.launchpadcontent\.net|launchpadcontent\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ubuntu22\.04'
}

pkg_has_candidate() {
  apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: '
  ! apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: (none)'
}

save_basic_state() {
  log "Collecting diagnostics in ${STATE_DIR}"

  run_capture "date" date
  run_capture "os-release" cat /etc/os-release
  run_capture "uname" uname -a
  run_capture "hostnamectl" hostnamectl
  run_capture "kernel cmdline" cat /proc/cmdline
  run_capture "dpkg audit" dpkg --audit
  run_capture "dkms status" dkms status
  run_capture "apt broken-check" apt-get -s -o Debug::pkgProblemResolver=yes install -f
  run_capture "ubuntu-drivers list" bash -lc 'command -v ubuntu-drivers >/dev/null && ubuntu-drivers list || echo "ubuntu-drivers not installed"'
  run_capture "apt policy intel-ipu6-dkms" apt-cache policy intel-ipu6-dkms
  run_capture "apt policy libcamera-tools" apt-cache policy libcamera-tools
  run_capture "apt policy recommended hal" bash -lc 'pkg="$(command -v ubuntu-drivers >/dev/null 2>&1 && ubuntu-drivers list 2>/dev/null | awk "/^libcamhal-/ {print; exit}")"; if [[ -n "$pkg" ]]; then apt-cache policy "$pkg"; else echo "no recommended libcamhal package reported"; fi'
  run_capture "v4l2 devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  run_capture "cam list" bash -lc 'command -v cam >/dev/null && cam -l || echo "cam not installed"'
  run_capture "qcam help" bash -lc 'command -v qcam >/dev/null && qcam --help | head -n 3 || echo "qcam not installed"'
  run_capture "lsmod filtered" bash -lc "lsmod | grep -E '(^ipu6|^intel_.*ipu|usbio|ivsc|icvs|v4l2loopback|intel_vision)' || true"
  run_capture "lspci filtered" bash -lc "lspci -nnk | grep -Ei 'camera|image|ipu|multimedia|intel' -A3 || true"
  run_capture "lsusb" lsusb
  run_capture "sysfs video names" bash -lc 'for f in /sys/class/video4linux/*/name; do [[ -e "$f" ]] && printf "%s: %s\n" "$f" "$(cat "$f")"; done'
  run_capture "systemd unit ipu6-relay" bash -lc 'systemctl cat ipu6-relay.service 2>/dev/null || echo "ipu6-relay.service not found"'
  run_capture "systemd unit v4l2-relayd" bash -lc 'systemctl cat v4l2-relayd.service 2>/dev/null || echo "v4l2-relayd.service not found"'
  run_capture "systemd status ipu6-relay" bash -lc 'systemctl --no-pager --full status ipu6-relay.service 2>/dev/null || true'
  run_capture "systemd status v4l2-relayd" bash -lc 'systemctl --no-pager --full status v4l2-relayd.service 2>/dev/null || true'
  run_capture "sources matching intel ipu" bash -lc "grep -RInE '(ppa\\.launchpadcontent\\.net|launchpadcontent\\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ppa:oem-solutions-group/intel-ipu[67]' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true"
  run_capture "journalctl filtered" bash -lc "journalctl -b -k --no-pager | grep -Ei 'ipu|usbio|ivsc|icvs|camera|v4l2|intel.*ipu|SAM0430' || true"

  dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null | sort > "$PKG_BEFORE_FILE" || true
  tar -czf "$APT_SOURCES_TAR" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true

  append_text "environment summary" \
    "kernel=$(uname -r)" \
    "recommended-hal=$(recommended_hal_pkg || true)" \
    "ipu6-kernel-stack=$(has_ipu6_kernel_stack && echo yes || echo no)" \
    "dev-ppa-enabled=$(dev_ppa_enabled && echo yes || echo no)" \
    "allow-dev-ppa=${ALLOW_DEV_PPA}"
}

disable_custom_broken_relay_unit() {
  local unit_path="/etc/systemd/system/ipu6-relay.service"
  if [[ -f "$unit_path" ]]; then
    if grep -q 'StartLimitIntervalSec' "$unit_path"; then
      warn "Disabling custom broken relay unit: $unit_path"
      cp -a "$unit_path" "${APT_SOURCE_BACKUP_DIR}/ipu6-relay.service.bak"
      systemctl disable --now ipu6-relay.service >/dev/null 2>&1 || true
      mv -f "$unit_path" "${unit_path}.disabled.${STAMP}"
      echo "ipu6-relay.service" >> "$DISABLED_UNITS_FILE"
      DISABLED_UNITS+=("ipu6-relay.service")
      systemctl daemon-reload
    fi
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
      cp -a "$file" "$APT_SOURCE_BACKUP_DIR/"
      warn "Disabling IPU development source in: $file"
      sed -i -E 's@^deb @# disabled-by-pop-ipu6-repair deb @g' "$file" || true
      sed -i -E 's@^URIs: https?://ppa\.launchpadcontent\.net/oem-solutions-group/intel-ipu[67]/ubuntu@# disabled-by-pop-ipu6-repair &@g' "$file" || true
    fi
  done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null)

  if grep -qE '(ppa\.launchpadcontent\.net|launchpadcontent\.net)/oem-solutions-group/intel-ipu[67]/ubuntu|ppa:oem-solutions-group/intel-ipu[67]' /etc/apt/sources.list 2>/dev/null; then
    matched=1
    cp -a /etc/apt/sources.list "$APT_SOURCE_BACKUP_DIR/sources.list.bak"
    sed -i -E 's@^deb .*oem-solutions-group/intel-ipu[67].*$@# disabled-by-pop-ipu6-repair &@g' /etc/apt/sources.list || true
  fi

  (( matched == 1 )) && systemctl daemon-reload || true
}

stop_relay_services() {
  local unit
  for unit in ipu6-relay.service v4l2-relayd.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
      systemctl stop "$unit" >/dev/null 2>&1 || true
    fi
  done
}

unload_v4l2loopback_if_safe() {
  if lsmod | grep -q '^v4l2loopback'; then
    warn "Attempting to unload active v4l2loopback module to remove stale Virtual Camera"
    stop_relay_services
    modprobe -r v4l2loopback >/dev/null 2>&1 || warn "Could not unload v4l2loopback now; a reboot may still be needed"
  fi
}

repair_package_state() {
  log "Repairing apt/dpkg state"
  export DEBIAN_FRONTEND=noninteractive
  dpkg --configure -a
  apt-get -f install -y
  apt-get autoremove --purge -y || true
  apt-get autoclean -y || true
}

install_test_tools() {
  local pkg
  local -a base_pkgs=(v4l-utils gstreamer1.0-libcamera libcamera-tools)
  for pkg in "${base_pkgs[@]}"; do
    if pkg_has_candidate "$pkg" && ! have_pkg_installed "$pkg"; then
      log "Installing test tool package: $pkg"
      apt-get install -y --no-install-recommends "$pkg"
      echo "$pkg" >> "$INSTALLED_FILE"
      INSTALLED_PKGS+=("$pkg")
    fi
  done
}

maybe_install_safe_hal() {
  local hal_pkg
  hal_pkg="$(recommended_hal_pkg || true)"

  if [[ -z "$hal_pkg" ]]; then
    warn "ubuntu-drivers did not report a libcamhal-* package. Skipping HAL install."
    return 0
  fi

  if have_pkg_installed "$hal_pkg"; then
    log "HAL package already installed: $hal_pkg"
    return 0
  fi

  if ! pkg_has_candidate "$hal_pkg"; then
    warn "No install candidate found for $hal_pkg"
    return 0
  fi

  if pkg_candidate_is_dev_ppa "$hal_pkg" && [[ "$ALLOW_DEV_PPA" != "1" ]]; then
    warn "Skipping $hal_pkg because the candidate appears to come from the Intel development PPA / Ubuntu 22.04 build."
    warn "If you explicitly want to try that risky path, re-run with: sudo ALLOW_DEV_PPA=1 bash $SCRIPT_NAME fix"
    return 0
  fi

  log "Installing HAL package: $hal_pkg"
  apt-get install -y --no-install-recommends "$hal_pkg"
  echo "$hal_pkg" >> "$INSTALLED_FILE"
  INSTALLED_PKGS+=("$hal_pkg")
}

remove_stale_ipu_userspace() {
  local -a purge_list=()
  mapfile -t purge_list < <(
    installed_pkgs_matching '^(intel-ipu6-dkms|intel-usbio-dkms|gstreamer1\.0-icamera|v4l2-relayd|v4l2loopback-dkms)$' | sort -u
  )

  if ((${#purge_list[@]} > 0)); then
    warn "Purging stale or mismatched bridge/DKMS packages:"
    printf '  %s\n' "${purge_list[@]}" | tee -a "$LOG_FILE" >&2
    printf '%s\n' "${purge_list[@]}" > "$REMOVED_FILE"
    REMOVED_PKGS=("${purge_list[@]}")
    apt-get purge -y "${purge_list[@]}"
  fi
}

write_rollback_script() {
  cat > "$ROLLBACK_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${1:-}"
if [[ -z "$STATE_DIR" || ! -d "$STATE_DIR" ]]; then
  echo "Usage: sudo bash rollback.sh /var/tmp/pop-ipu6-repair-v2/<timestamp>" >&2
  exit 1
fi

REMOVED_FILE="${STATE_DIR}/removed-packages.txt"
INSTALLED_FILE="${STATE_DIR}/installed-packages.txt"
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"
DISABLED_UNITS_FILE="${STATE_DIR}/disabled-units.txt"

if [[ -f "$APT_SOURCES_TAR" ]]; then
  echo "[INFO] Restoring saved APT source files"
  tar -xzf "$APT_SOURCES_TAR" -C / || true
fi

systemctl daemon-reload || true
apt-get update

if [[ -s "$INSTALLED_FILE" ]]; then
  echo "[INFO] Removing packages that v2 installed"
  mapfile -t pkgs < "$INSTALLED_FILE"
  apt-get purge -y "${pkgs[@]}" || true
fi

if [[ -s "$REMOVED_FILE" ]]; then
  echo "[INFO] Reinstalling packages that v2 removed"
  mapfile -t pkgs < "$REMOVED_FILE"
  apt-get install -y "${pkgs[@]}" || true
fi

if [[ -s "$DISABLED_UNITS_FILE" ]]; then
  echo "[INFO] Note: custom units disabled by the script were backed up in the state directory and may need manual restoration."
fi

apt-get -f install -y || true
echo "[INFO] Rollback attempt completed."
EOF
  chmod +x "$ROLLBACK_SCRIPT"
}

post_checks() {
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null | sort > "$PKG_AFTER_FILE" || true

  run_capture "post dpkg audit" dpkg --audit
  run_capture "post dkms status" dkms status
  run_capture "post apt broken-check" apt-get -s -o Debug::pkgProblemResolver=yes install -f
  run_capture "post v4l2 devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  run_capture "post cam list" bash -lc 'command -v cam >/dev/null && cam -l || echo "cam not installed"'
  run_capture "post sysfs video names" bash -lc 'for f in /sys/class/video4linux/*/name; do [[ -e "$f" ]] && printf "%s: %s\n" "$f" "$(cat "$f")"; done'
  run_capture "post journalctl filtered" bash -lc "journalctl -b -k --no-pager | grep -Ei 'ipu|usbio|ivsc|icvs|camera|v4l2|intel.*ipu|SAM0430' || true"
}

print_summary() {
  echo
  echo "State directory: $STATE_DIR"
  echo "Main report:     $REPORT_FILE"
  echo "Main log:        $LOG_FILE"
  echo

  if [[ -s "$REMOVED_FILE" ]]; then
    echo "Removed packages:"
    sed 's/^/  - /' "$REMOVED_FILE"
    echo
  fi

  if [[ -s "$INSTALLED_FILE" ]]; then
    echo "Installed packages:"
    sed 's/^/  - /' "$INSTALLED_FILE"
    echo
  fi

  if [[ -s "$DISABLED_UNITS_FILE" ]]; then
    echo "Disabled custom units:"
    sed 's/^/  - /' "$DISABLED_UNITS_FILE"
    echo
  fi

  echo "Rollback helper:"
  echo "  sudo bash $ROLLBACK_SCRIPT $STATE_DIR"
  echo

  echo "Suggested next checks:"
  echo "  1) cam -l"
  echo "  2) qcam   # if you have a desktop session and libcamera-tools installed"
  echo "  3) v4l2-ctl --list-devices"
  echo "  4) firefox/chrome -> https://mozilla.github.io/webrtc-landing/gum_test.html"
  echo "  5) sudo reboot   # recommended if Virtual Camera still appears"
}

fix_mode() {
  require_root
  log "Starting safe fix mode"

  disable_custom_broken_relay_unit
  stop_relay_services
  unload_v4l2loopback_if_safe
  remove_dev_ppa_sources

  export DEBIAN_FRONTEND=noninteractive
  apt-get update

  remove_stale_ipu_userspace
  repair_package_state
  install_test_tools

  if has_ipu6_kernel_stack; then
    log "Kernel already reports an IPU6 camera stack. Trying only the userspace HAL path."
    maybe_install_safe_hal
  else
    warn "Kernel does not currently report a working IPU6 stack. This script will not force intel-ipu6-dkms on Pop's custom kernel."
  fi

  repair_package_state
  write_rollback_script
}

main() {
  need_cmd bash
  need_cmd uname
  need_cmd dpkg-query
  need_cmd dpkg
  need_cmd apt-get
  need_cmd journalctl

  case "$MODE" in
    check|fix) ;;
    *)
      echo "Usage: $SCRIPT_NAME [check|fix]" >&2
      echo "Environment variable: ALLOW_DEV_PPA=1   # permit risky libcamhal install from the Intel dev PPA" >&2
      exit 1
      ;;
  esac

  ensure_state_dir
  save_basic_state

  if [[ "$MODE" == "fix" ]]; then
    fix_mode
  fi

  post_checks
  print_summary
}

main "$@"
