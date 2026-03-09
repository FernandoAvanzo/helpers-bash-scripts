#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-check}"

STAMP="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="/var/tmp/pop-ipu6-repair"
STATE_DIR="${BASE_DIR}/${STAMP}"
LATEST_LINK="${BASE_DIR}/latest"

LOG_FILE="${STATE_DIR}/run.log"
REPORT_FILE="${STATE_DIR}/report.txt"
PKG_BEFORE_FILE="${STATE_DIR}/packages-before.txt"
PKG_AFTER_FILE="${STATE_DIR}/packages-after.txt"
REMOVED_FILE="${STATE_DIR}/removed-packages.txt"
ROLLBACK_SCRIPT="${STATE_DIR}/rollback.sh"
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"

declare -a REMOVED_PKGS=()

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
  command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 1; }
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
  ln -sfn "$STATE_DIR" "$LATEST_LINK"
  : > "$LOG_FILE"
  : > "$REPORT_FILE"
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

save_basic_state() {
  log "Collecting pre-change diagnostics in ${STATE_DIR}"

  append_report "date" date
  append_report "os-release" cat /etc/os-release
  append_report "uname" uname -a
  append_report "hostnamectl" hostnamectl
  append_report "kernel cmdline" cat /proc/cmdline
  append_report "dpkg audit" dpkg --audit
  append_report "dkms status" dkms status
  append_report "apt broken-check" apt-get -s -o Debug::pkgProblemResolver=yes install -f
  append_report "ubuntu-drivers list" bash -lc 'command -v ubuntu-drivers >/dev/null && ubuntu-drivers list || echo "ubuntu-drivers not installed"'
  append_report "v4l2-ctl devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  append_report "libcamera cameras" bash -lc 'command -v libcamera-hello >/dev/null && libcamera-hello --list-cameras || echo "libcamera-hello not installed"'
  append_report "lsmod filtered" bash -lc "lsmod | grep -E '(^ipu6|usbio|ivsc|icvs|v4l2loopback|intel_vision)' || true"
  append_report "lspci filtered" bash -lc "lspci -nnk | grep -Ei 'camera|image|ipu|multimedia|intel' -A3 || true"
  append_report "lsusb" lsusb
  append_report "journalctl filtered" bash -lc "journalctl -b -k --no-pager | grep -Ei 'ipu|usbio|ivsc|icvs|camera|v4l2|intel.*ipu' || true"

  dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null \
    | sort > "$PKG_BEFORE_FILE" || true

  tar -czf "$APT_SOURCES_TAR" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true

  append_text "state dir" "$STATE_DIR"
}

detect_risk_profile() {
  local kernel distro id_like
  kernel="$(uname -r)"
  distro="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
  id_like="$(. /etc/os-release && printf '%s %s' "${ID:-}" "${ID_LIKE:-}")"

  append_text "environment summary" \
    "distro=${distro}" \
    "kernel=${kernel}" \
    "id/id_like=${id_like}"

  if [[ "$kernel" =~ 7606|surface|liquorix|zen ]]; then
    append_text "important warning" \
      "This kernel does not look like the stock Ubuntu HWE/OEM kernel family expected by Canonical's IPU6 packaging." \
      "On Pop!_OS, the Additional Drivers UI can still offer packages, but intel-ipu6-dkms may fail because the module stack is kernel-specific."
  fi
}

remove_repo_if_present() {
  local pattern="$1"
  if grep -Rqs "$pattern" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    warn "Found APT source matching: $pattern"
    if command -v add-apt-repository >/dev/null 2>&1; then
      if [[ "$pattern" == *"intel-ipu6"* ]]; then
        add-apt-repository -y --remove ppa:oem-solutions-group/intel-ipu6 || true
      elif [[ "$pattern" == *"intel-ipu7"* ]]; then
        add-apt-repository -y --remove ppa:oem-solutions-group/intel-ipu7 || true
      fi
    fi
  fi
}

installed_pkgs_matching() {
  dpkg-query -W -f='${binary:Package}\n' 2>/dev/null \
    | grep -E "$1" || true
}

purge_candidates() {
  installed_pkgs_matching '^(intel-ipu6-dkms|intel-usbio-dkms|ipu6-camera-bins|ipu7-camera-bins|ipu6-camera-hal|ipu7-camera-hal|gstreamer1\.0-icamera|v4l2-relayd|v4l2loopback-dkms|libcamhal|libia-|libgcss|libipu|oem-.*-meta)$' \
    | sort -u
}

write_rollback_script() {
  cat > "$ROLLBACK_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${1:-}"
if [[ -z "$STATE_DIR" || ! -d "$STATE_DIR" ]]; then
  echo "Usage: sudo bash rollback.sh /var/tmp/pop-ipu6-repair/<timestamp>" >&2
  exit 1
fi

REMOVED_FILE="${STATE_DIR}/removed-packages.txt"
APT_SOURCES_TAR="${STATE_DIR}/apt-sources.tar.gz"

if [[ -f "$APT_SOURCES_TAR" ]]; then
  echo "[INFO] Restoring saved APT source files"
  tar -xzf "$APT_SOURCES_TAR" -C / || true
fi

apt-get update

if [[ -s "$REMOVED_FILE" ]]; then
  echo "[INFO] Reinstalling removed packages with currently available versions"
  mapfile -t pkgs < "$REMOVED_FILE"
  apt-get install -y "${pkgs[@]}"
else
  echo "[INFO] No removed package list found."
fi

echo "[INFO] Rollback attempt completed."
EOF
  chmod +x "$ROLLBACK_SCRIPT"
}

repair_system() {
  require_root

  log "Starting repair mode"
  remove_repo_if_present 'ppa:oem-solutions-group/intel-ipu6'
  remove_repo_if_present 'ppa:oem-solutions-group/intel-ipu7'

  export DEBIAN_FRONTEND=noninteractive
  apt-get update

  mapfile -t purge_list < <(purge_candidates)
  if ((${#purge_list[@]} > 0)); then
    printf '%s\n' "${purge_list[@]}" | tee "$REMOVED_FILE" >/dev/null
    REMOVED_PKGS=("${purge_list[@]}")
    warn "Purging IPU6/IPU7 camera stack packages that are likely mismatched with this kernel:"
    printf '  %s\n' "${purge_list[@]}" | tee -a "$LOG_FILE" >&2
    apt-get purge -y "${purge_list[@]}"
  else
    : > "$REMOVED_FILE"
    log "No installed IPU6/IPU7 stack packages matched purge criteria."
  fi

  apt-get autoremove --purge -y || true
  dpkg --configure -a
  apt-get -f install -y
  apt-get autoremove --purge -y || true
  apt-get autoclean -y || true

  write_rollback_script

  warn "No automatic reinstall is attempted on Pop!_OS custom kernels."
  warn "This repair focuses on removing the broken Ubuntu IPU6 DKMS attempt and returning APT/DKMS to a healthy state."
}

post_checks() {
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' 2>/dev/null \
    | sort > "$PKG_AFTER_FILE" || true

  append_report "post dpkg audit" dpkg --audit
  append_report "post dkms status" dkms status
  append_report "post apt broken-check" apt-get -s -o Debug::pkgProblemResolver=yes install -f
  append_report "post lsmod filtered" bash -lc "lsmod | grep -E '(^ipu6|usbio|ivsc|icvs|v4l2loopback|intel_vision)' || true"
  append_report "post /dev/video" bash -lc "ls -l /dev/video* 2>/dev/null || echo 'no /dev/video devices present'"
  append_report "post v4l2-ctl devices" bash -lc 'command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices || echo "v4l2-ctl not installed"'
  append_report "post libcamera cameras" bash -lc 'command -v libcamera-hello >/dev/null && libcamera-hello --list-cameras || echo "libcamera-hello not installed"'
}

print_summary() {
  echo
  echo "State directory: $STATE_DIR"
  echo "Main report:     $REPORT_FILE"
  echo "Main log:        $LOG_FILE"
  echo
  if [[ "$MODE" == "repair" ]]; then
    if [[ -s "$REMOVED_FILE" ]]; then
      echo "Removed packages:"
      sed 's/^/  - /' "$REMOVED_FILE"
    else
      echo "Removed packages: none"
    fi
    echo
    echo "Rollback helper:"
    echo "  sudo bash $ROLLBACK_SCRIPT $STATE_DIR"
  fi
  echo
  echo "Suggested next checks:"
  echo "  1) sudo apt update && sudo apt -f install"
  echo "  2) dkms status"
  echo "  3) v4l2-ctl --list-devices"
  echo "  4) libcamera-hello --list-cameras"
}

main() {
  need_cmd bash
  need_cmd uname
  need_cmd dpkg-query
  need_cmd dpkg
  need_cmd apt-get
  need_cmd journalctl

  case "$MODE" in
    check|repair) ;;
    *)
      echo "Usage: $SCRIPT_NAME [check|repair]" >&2
      exit 1
      ;;
  esac

  ensure_state_dir
  save_basic_state
  detect_risk_profile

  if [[ "$MODE" == "repair" ]]; then
    repair_system
  fi

  post_checks
  print_summary
}

main "$@"
