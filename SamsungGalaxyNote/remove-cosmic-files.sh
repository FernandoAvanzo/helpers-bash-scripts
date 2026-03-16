#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly PKG="cosmic-files"

DRY_RUN=1
ASSUME_YES=0
REMOVE_USER_DATA=0
ALLOW_DESKTOP_IMPACT=0
LOG_FILE="/var/log/remove-${PKG}-$(date +%Y%m%d-%H%M%S).log"

usage() {
  cat <<'EOF'
Usage:
  sudo ./remove-cosmic-files.sh [options]

Options:
  --execute               Actually remove the package. Without this flag, the script
                          performs pre-checks and a full APT simulation only.
  --yes                   Non-interactive confirmation for the real removal step.
  --remove-user-data      Remove per-user leftovers for the invoking sudo user:
                          ~/.config/cosmic-files*
                          ~/.cache/cosmic-files*
                          ~/.local/share/cosmic-files*
                          ~/.local/state/cosmic-files*
  --allow-desktop-impact  Permit removal even if APT would also remove core COSMIC
                          desktop packages such as cosmic-session.
  --log-file PATH         Write the log to PATH.
  -h, --help              Show this help.

Examples:
  sudo ./remove-cosmic-files.sh
  sudo ./remove-cosmic-files.sh --execute
  sudo ./remove-cosmic-files.sh --execute --allow-desktop-impact --yes
EOF
}

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date +'%F %T')" "$level" "$*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR" "$*"
  exit 1
}

warn() {
  log "WARN" "$*"
}

info() {
  log "INFO" "$*"
}

on_error() {
  local exit_code="$1"
  local line_no="$2"
  die "Unexpected failure at line ${line_no} (exit code ${exit_code}). Review ${LOG_FILE}."
}
trap 'on_error $? $LINENO' ERR

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this script with sudo or as root."
}

init_logging() {
  install -d -m 0755 "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  chmod 0600 "$LOG_FILE"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --execute)
        DRY_RUN=0
        ;;
      --yes)
        ASSUME_YES=1
        ;;
      --remove-user-data)
        REMOVE_USER_DATA=1
        ;;
      --allow-desktop-impact)
        ALLOW_DESKTOP_IMPACT=1
        ;;
      --log-file)
        shift
        [[ $# -gt 0 ]] || die "--log-file requires a path argument."
        LOG_FILE="$1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

assert_supported_os() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."
  # shellcheck disable=SC1091
  source /etc/os-release

  local is_pop=0
  if [[ "${ID:-}" == "pop" ]]; then
    is_pop=1
  elif [[ "${ID_LIKE:-}" == *"ubuntu"* ]] && [[ "${NAME:-}" == *"Pop!_OS"* ]]; then
    is_pop=1
  fi

  (( is_pop == 1 )) || die "This script is intended for Pop!_OS systems."
  info "Detected operating system: ${PRETTY_NAME:-unknown}"
}

package_installed() {
  dpkg-query -W -f='${Status}\n' "$PKG" 2>/dev/null | grep -q '^install ok installed$'
}

package_version() {
  dpkg-query -W -f='${Version}\n' "$PKG" 2>/dev/null || true
}

preflight_package_db() {
  info "Running package database health checks."
  if dpkg --audit | tee -a "$LOG_FILE" | grep -q '.'; then
    die "dpkg --audit reported package database problems. Fix those before removing ${PKG}."
  fi

  apt-get check >>"$LOG_FILE" 2>&1 || die "apt-get check failed. Resolve APT issues first."
  info "APT and dpkg pre-checks passed."
}

show_installed_rdepends() {
  local output
  output="$(apt-cache rdepends --installed "$PKG" 2>/dev/null || true)"
  mapfile -t INSTALLED_RDEPENDS < <(
    awk '
      /^Reverse Depends:/ {capture=1; next}
      capture && /^[[:space:]]+/ {
        gsub(/^[[:space:]]+/, "", $0)
        if ($0 != "" && $0 != "'"$PKG"'") print $0
      }
    ' <<<"$output" | sort -u
  )

  if ((${#INSTALLED_RDEPENDS[@]} > 0)); then
    info "Installed reverse dependencies detected:"
    printf '  - %s\n' "${INSTALLED_RDEPENDS[@]}" | tee -a "$LOG_FILE"
  else
    info "No installed reverse dependencies were reported for ${PKG}."
  fi
}

simulate_removal() {
  info "Simulating removal with: apt-get -s autoremove --purge ${PKG}"
  SIM_OUTPUT="$(apt-get -s autoremove --purge "$PKG" 2>&1)" || {
    printf '%s\n' "$SIM_OUTPUT" >>"$LOG_FILE"
    die "APT simulation failed."
  }
  printf '%s\n' "$SIM_OUTPUT" >>"$LOG_FILE"

  mapfile -t SIM_REMOVED_PKGS < <(awk '/^Remv /{print $2}' <<<"$SIM_OUTPUT" | sort -u)

  if ((${#SIM_REMOVED_PKGS[@]} == 0)); then
    warn "Simulation did not report any packages to remove. ${PKG} may already be absent."
  else
    info "APT would remove these packages:"
    printf '  - %s\n' "${SIM_REMOVED_PKGS[@]}" | tee -a "$LOG_FILE"
  fi
}

check_desktop_impact() {
  local critical=0
  local pkg

  for pkg in "${SIM_REMOVED_PKGS[@]:-}"; do
    case "$pkg" in
      cosmic-session|cosmic-comp|cosmic-panel|cosmic-launcher|cosmic-settings-daemon|cosmic-greeter|cosmic-workspaces|pop-desktop|pop-cosmic)
        critical=1
        ;;
    esac
  done

  if (( critical == 1 )) && (( ALLOW_DESKTOP_IMPACT == 0 )); then
    die "Simulation shows that removing ${PKG} would also remove core COSMIC/Pop!_OS desktop packages. Re-run with --allow-desktop-impact only if you explicitly want that."
  fi

  if (( critical == 1 )); then
    warn "Desktop-impact override enabled. This operation may remove parts of the COSMIC desktop and affect future logins."
  fi
}

warn_if_current_session_is_cosmic() {
  local current_desktop="${XDG_CURRENT_DESKTOP:-}"
  local desktop_session="${DESKTOP_SESSION:-}"

  if [[ "$current_desktop" == *COSMIC* || "$desktop_session" == *cosmic* ]]; then
    warn "You appear to be running this from a COSMIC session. Removing ${PKG} may destabilize the current session or the next login."
  fi
}

confirm_execution() {
  (( DRY_RUN == 0 )) || return 0
  (( ASSUME_YES == 1 )) && return 0

  echo
  read -r -p "Proceed with actual removal of ${PKG}? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES)
      ;;
    *)
      die "Removal canceled by user."
      ;;
  esac
}

remove_package() {
  info "Executing removal: apt-get -y autoremove --purge ${PKG}"
  DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge "$PKG" >>"$LOG_FILE" 2>&1
  info "APT removal step completed."
}

remove_user_data() {
  (( REMOVE_USER_DATA == 1 )) || return 0

  local target_user="${SUDO_USER:-}"
  local target_home=""

  if [[ -z "$target_user" || "$target_user" == "root" ]]; then
    warn "--remove-user-data requested, but no non-root sudo user was detected. Skipping per-user cleanup."
    return 0
  fi

  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  [[ -n "$target_home" && -d "$target_home" ]] || {
    warn "Could not determine home directory for ${target_user}. Skipping per-user cleanup."
    return 0
  }

  info "Removing per-user leftovers for ${target_user} in ${target_home}"
  shopt -s nullglob dotglob
  local patterns=(
    "${target_home}/.config/cosmic-files*"
    "${target_home}/.cache/cosmic-files*"
    "${target_home}/.local/share/cosmic-files*"
    "${target_home}/.local/state/cosmic-files*"
  )
  local matches=()
  local pattern
  for pattern in "${patterns[@]}"; do
    # shellcheck disable=SC2206
    matches+=( $pattern )
  done

  if ((${#matches[@]} == 0)); then
    info "No matching per-user leftovers were found."
  else
    printf '  - %s\n' "${matches[@]}" | tee -a "$LOG_FILE"
    rm -rf -- "${matches[@]}"
    info "Per-user cleanup completed."
  fi
  shopt -u nullglob dotglob
}

post_checks() {
  info "Running post-removal verification."
  if package_installed; then
    die "${PKG} still appears to be installed after removal."
  fi

  if command -v "$PKG" >/dev/null 2>&1; then
    warn "A '${PKG}' executable is still present in PATH. It may come from a non-APT source."
  else
    info "No '${PKG}' executable is present in PATH."
  fi

  apt-get check >>"$LOG_FILE" 2>&1 || die "Post-check failed: apt-get check reported problems."
  if dpkg --audit | tee -a "$LOG_FILE" | grep -q '.'; then
    die "Post-check failed: dpkg --audit reported package database problems."
  fi

  info "Post-removal APT/dpkg checks passed."
}

print_summary() {
  echo
  info "Summary"
  info "  Package: ${PKG}"
  if (( DRY_RUN == 1 )); then
    info "  Mode: dry-run only"
    info "  Next step: rerun with --execute to apply the removal."
  else
    info "  Mode: executed"
  fi
  info "  Log file: ${LOG_FILE}"
}

main() {
  parse_args "$@"
  require_root
  init_logging

  require_command apt-get
  require_command apt-cache
  require_command dpkg
  require_command dpkg-query
  require_command awk
  require_command grep
  require_command sort
  require_command getent

  assert_supported_os
  warn_if_current_session_is_cosmic

  if ! package_installed; then
    die "${PKG} is not installed as an APT package on this system."
  fi

  info "Detected ${PKG} version: $(package_version)"
  preflight_package_db
  show_installed_rdepends
  simulate_removal
  check_desktop_impact

  if (( DRY_RUN == 1 )); then
    print_summary
    exit 0
  fi

  confirm_execution
  remove_package
  remove_user_data
  post_checks
  print_summary
}

main "$@"
