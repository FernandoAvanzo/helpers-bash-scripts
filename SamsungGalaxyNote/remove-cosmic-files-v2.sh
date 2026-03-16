#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly TARGET_PKG="cosmic-files"
readonly APP_ID="com.system76.CosmicFiles"

DRY_RUN=1
ASSUME_YES=0
REMOVE_USER_DATA=0
ALLOW_DESKTOP_IMPACT=0
REPAIR_APT=0
ALLOW_CHANGE_HELD=0
LOG_FILE="/var/log/remove-${TARGET_PKG}-$(date +%Y%m%d-%H%M%S).log"

declare -a PLAN_PKGS=()
declare -a SIM_REMOVED_PKGS=()
declare -a HELD_PKGS=()
declare -A SEEN_PKGS=()

usage() {
  cat <<'EOF'
Usage:
  sudo ./remove-cosmic-files-v2.sh [options]

Options:
  --execute               Actually apply changes. Without this flag the script only
                          runs checks and a full APT simulation.
  --yes                   Non-interactive execution.
  --remove-user-data      Remove per-user leftovers for the invoking sudo user.
  --allow-desktop-impact  Allow removal of COSMIC session / Pop desktop metapackages
                          if they are in the reverse-dependency chain.
  --repair-apt            If APT health checks fail, run a conservative repair pass:
                          apt clean, apt update, dpkg --configure -a, apt install -f
  --allow-change-held     Allow APT to change/remove held packages when required.
  --log-file PATH         Write the log to PATH.
  -h, --help              Show this help.

Examples:
  sudo ./remove-cosmic-files-v2.sh
  sudo ./remove-cosmic-files-v2.sh --execute
  sudo ./remove-cosmic-files-v2.sh --execute --allow-desktop-impact --yes
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

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this script with sudo or as root."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
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
      --repair-apt)
        REPAIR_APT=1
        ;;
      --allow-change-held)
        ALLOW_CHANGE_HELD=1
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
  elif [[ "${NAME:-}" == *"Pop!_OS"* ]]; then
    is_pop=1
  fi

  (( is_pop == 1 )) || die "This script is intended for Pop!_OS systems."
  info "Detected operating system: ${PRETTY_NAME:-unknown}"
}

package_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -q '^install ok installed$'
}

package_version() {
  local pkg="$1"
  dpkg-query -W -f='${Version}\n' "$pkg" 2>/dev/null || true
}

warn_if_current_session_is_cosmic() {
  local current_desktop="${XDG_CURRENT_DESKTOP:-}"
  local desktop_session="${DESKTOP_SESSION:-}"
  if [[ "$current_desktop" == *COSMIC* || "$desktop_session" == *cosmic* ]]; then
    warn "You appear to be running this from a COSMIC session. Removing ${TARGET_PKG} can destabilize the running session. A TTY or another desktop session is safer."
  fi
}

get_held_packages() {
  mapfile -t HELD_PKGS < <(apt-mark showhold 2>/dev/null | awk 'NF' | sort -u)
  if ((${#HELD_PKGS[@]} > 0)); then
    info "Held packages detected:"
    printf '  - %s\n' "${HELD_PKGS[@]}" | tee -a "$LOG_FILE"
  else
    info "No held packages detected."
  fi
}

apt_health_check() {
  info "Running APT/dpkg health checks."
  if ! apt-get check >>"$LOG_FILE" 2>&1; then
    warn "apt-get check failed."
    if (( REPAIR_APT == 1 )); then
      repair_apt_state
      apt-get check >>"$LOG_FILE" 2>&1 || die "APT still unhealthy after repair pass."
    else
      die "APT is unhealthy. Re-run with --repair-apt or repair the package state first."
    fi
  fi

  if dpkg --audit | tee -a "$LOG_FILE" | grep -q '.'; then
    if (( REPAIR_APT == 1 )); then
      repair_apt_state
      if dpkg --audit | tee -a "$LOG_FILE" | grep -q '.'; then
        die "dpkg --audit still reports problems after repair pass."
      fi
    else
      die "dpkg --audit reported package problems. Re-run with --repair-apt or repair manually first."
    fi
  fi

  info "APT/dpkg health checks passed."
}

repair_apt_state() {
  info "Running conservative package-manager repair sequence."
  apt-get clean >>"$LOG_FILE" 2>&1
  rm -rf /var/lib/apt/lists/* >>"$LOG_FILE" 2>&1 || true
  apt-get update >>"$LOG_FILE" 2>&1
  dpkg --configure -a >>"$LOG_FILE" 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get -f install -y >>"$LOG_FILE" 2>&1
  info "Repair sequence completed."
}

list_installed_rdepends() {
  local pkg="$1"
  local output dep
  output="$(apt-cache rdepends --installed "$pkg" 2>/dev/null || true)"
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    case "$dep" in
      "$pkg"|Reverse\ Depends:|Reverse\ Recommends:|Reverse\ Suggests:)
        continue
        ;;
    esac
    dep="${dep#"${dep%%[![:space:]]*}"}"
    [[ -n "$dep" ]] || continue
    [[ "$dep" == \<* ]] && continue
    printf '%s\n' "$dep"
  done <<<"$output" | sort -u
}

add_plan_pkg() {
  local pkg="$1"
  [[ -n "$pkg" ]] || return 0
  if [[ -z "${SEEN_PKGS[$pkg]+x}" ]]; then
    SEEN_PKGS["$pkg"]=1
    PLAN_PKGS+=("$pkg")
  fi
}

build_reverse_dependency_closure() {
  local -a queue=("$TARGET_PKG")
  local idx=0 current dep

  add_plan_pkg "$TARGET_PKG"

  while (( idx < ${#queue[@]} )); do
    current="${queue[$idx]}"
    ((idx+=1))

    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      if package_installed "$dep" && [[ -z "${SEEN_PKGS[$dep]+x}" ]]; then
        add_plan_pkg "$dep"
        queue+=("$dep")
      fi
    done < <(list_installed_rdepends "$current")
  done

  # Explicitly include Pop meta packages if they sit above the closure.
  if package_installed "pop-de-cosmic"; then
    for current in "${PLAN_PKGS[@]}"; do
      if list_installed_rdepends "$current" | grep -qx 'pop-de-cosmic'; then
        add_plan_pkg "pop-de-cosmic"
        break
      fi
    done
  fi

  if package_installed "pop-desktop"; then
    if list_installed_rdepends "pop-de-cosmic" | grep -qx 'pop-desktop'; then
      add_plan_pkg "pop-desktop"
    fi
  fi

  info "Planned direct purge set:"
  printf '  - %s\n' "${PLAN_PKGS[@]}" | tee -a "$LOG_FILE"
}

has_pkg_in_list() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

expand_plan_from_simulation_errors() {
  local changed=0 blocker
  # Package names that appear before the first colon in dependency errors are usually blockers.
  while IFS= read -r blocker; do
    [[ -n "$blocker" ]] || continue
    blocker="${blocker%%:*}"
    blocker="${blocker#"${blocker%%[![:space:]]*}"}"
    [[ -n "$blocker" ]] || continue
    if package_installed "$blocker" && ! has_pkg_in_list "$blocker" "${PLAN_PKGS[@]}"; then
      add_plan_pkg "$blocker"
      changed=1
    fi
  done < <(awk '/^[[:alnum:]][[:alnum:]+.-]*: (Pre-Depends|Depends|Breaks):/ {print $1}' <<<"$SIM_OUTPUT" | tr -d ':' | sort -u)

  if (( changed == 1 )); then
    info "Expanded purge set after reading solver output:"
    printf '  - %s\n' "${PLAN_PKGS[@]}" | tee -a "$LOG_FILE"
    return 0
  fi
  return 1
}

simulate_plan() {
  local pass=1
  while (( pass <= 4 )); do
    info "Simulation pass ${pass}: apt-get -s purge ${PLAN_PKGS[*]}"
    SIM_OUTPUT="$(apt-get -s purge "${PLAN_PKGS[@]}" 2>&1)" || true
    printf '%s\n' "$SIM_OUTPUT" >>"$LOG_FILE"

    if grep -q '^The following packages have unmet dependencies:' <<<"$SIM_OUTPUT"; then
      warn "APT reported dependency blockers during simulation."
      if expand_plan_from_simulation_errors; then
        ((pass+=1))
        continue
      fi
      die "APT simulation still reports dependency blockers. Review ${LOG_FILE}."
    fi

    mapfile -t SIM_REMOVED_PKGS < <(awk '/^Remv /{print $2}' <<<"$SIM_OUTPUT" | sort -u)
    if ((${#SIM_REMOVED_PKGS[@]} == 0)); then
      warn "Simulation reported no packages to remove. The package may already be absent or the solver refused the plan."
    else
      info "APT would remove these packages:"
      printf '  - %s\n' "${SIM_REMOVED_PKGS[@]}" | tee -a "$LOG_FILE"
    fi
    return 0
  done

  die "Could not reach a stable purge plan after multiple simulation passes."
}

check_desktop_impact() {
  local pkg impact=0
  for pkg in "${SIM_REMOVED_PKGS[@]:-}"; do
    case "$pkg" in
      cosmic-session|cosmic-comp|cosmic-panel|cosmic-launcher|cosmic-greeter|cosmic-settings-daemon|cosmic-workspaces|pop-de-cosmic|pop-desktop)
        impact=1
        ;;
    esac
  done

  if (( impact == 1 )) && (( ALLOW_DESKTOP_IMPACT == 0 )); then
    die "The removal plan includes COSMIC session / Pop desktop packages. Re-run with --allow-desktop-impact only if you intentionally want to remove the COSMIC desktop stack that depends on ${TARGET_PKG}."
  fi

  if (( impact == 1 )); then
    warn "Desktop-impact override enabled. This plan will remove part of the COSMIC desktop stack."
  fi
}

check_held_package_conflicts() {
  local held affected=0
  for held in "${HELD_PKGS[@]:-}"; do
    if has_pkg_in_list "$held" "${PLAN_PKGS[@]}" || has_pkg_in_list "$held" "${SIM_REMOVED_PKGS[@]}"; then
      warn "Held package is part of the removal path: $held"
      affected=1
    fi
  done

  if (( affected == 1 )) && (( ALLOW_CHANGE_HELD == 0 )); then
    die "Held packages would be changed. Re-run with --allow-change-held if that is intentional."
  fi
}

show_package_facts() {
  info "Detected ${TARGET_PKG} version: $(package_version "$TARGET_PKG")"
  if package_installed "cosmic-session"; then
    info "Detected cosmic-session version: $(package_version "cosmic-session")"
  fi
  if package_installed "pop-de-cosmic"; then
    info "Detected pop-de-cosmic version: $(package_version "pop-de-cosmic")"
  fi
  if package_installed "pop-desktop"; then
    info "Detected pop-desktop version: $(package_version "pop-desktop")"
  fi
}

confirm_execution() {
  (( DRY_RUN == 0 )) || return 0
  (( ASSUME_YES == 1 )) && return 0

  echo
  read -r -p "Proceed with actual purge of ${PLAN_PKGS[*]} ? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES)
      ;;
    *)
      die "Removal canceled by user."
      ;;
  esac
}

execute_plan() {
  local -a apt_opts=("-y")
  (( ALLOW_CHANGE_HELD == 1 )) && apt_opts+=("-o" "APT::Get::allow-change-held-packages=true")

  info "Executing purge plan."
  DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" purge "${PLAN_PKGS[@]}" >>"$LOG_FILE" 2>&1
  info "Primary purge step completed."

  info "Running autoremove --purge to remove now-unused dependencies."
  DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" autoremove --purge >>"$LOG_FILE" 2>&1
  info "Autoremove step completed."
}

remove_user_data() {
  (( REMOVE_USER_DATA == 1 )) || return 0

  local target_user="${SUDO_USER:-}"
  local target_home=""
  [[ -n "$target_user" && "$target_user" != "root" ]] || {
    warn "--remove-user-data requested but no non-root sudo user was detected. Skipping per-user cleanup."
    return 0
  }

  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  [[ -n "$target_home" && -d "$target_home" ]] || {
    warn "Could not determine a valid home directory for ${target_user}. Skipping per-user cleanup."
    return 0
  }

  info "Removing per-user leftovers for ${target_user} in ${target_home}"
  shopt -s nullglob dotglob
  local patterns=(
    "${target_home}/.config/cosmic-files*"
    "${target_home}/.config/${APP_ID}*"
    "${target_home}/.cache/cosmic-files*"
    "${target_home}/.cache/${APP_ID}*"
    "${target_home}/.local/share/cosmic-files*"
    "${target_home}/.local/share/${APP_ID}*"
    "${target_home}/.local/state/cosmic-files*"
    "${target_home}/.local/state/${APP_ID}*"
  )
  local -a matches=()
  local path
  for path in "${patterns[@]}"; do
    matches+=($path)
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
  if package_installed "$TARGET_PKG"; then
    die "${TARGET_PKG} still appears installed after the purge."
  fi

  if command -v "$TARGET_PKG" >/dev/null 2>&1; then
    warn "A ${TARGET_PKG} executable is still present in PATH. It may come from a non-APT source."
  else
    info "No ${TARGET_PKG} executable is present in PATH."
  fi

  apt-get check >>"$LOG_FILE" 2>&1 || die "Post-check failed: apt-get check reported problems."
  if dpkg --audit | tee -a "$LOG_FILE" | grep -q '.'; then
    die "Post-check failed: dpkg --audit reported package problems."
  fi

  info "Post-removal APT/dpkg checks passed."
}

print_summary() {
  echo
  info "Summary"
  info "  Target package : ${TARGET_PKG}"
  info "  Planned purge  : ${PLAN_PKGS[*]}"
  if (( DRY_RUN == 1 )); then
    info "  Mode          : dry-run"
    info "  Next step     : rerun with --execute to apply the removal"
  else
    info "  Mode          : executed"
  fi
  info "  Log file      : ${LOG_FILE}"
}

main() {
  parse_args "$@"
  require_root
  init_logging

  require_command apt-get
  require_command apt-cache
  require_command apt-mark
  require_command dpkg
  require_command dpkg-query
  require_command awk
  require_command grep
  require_command sort
  require_command getent
  require_command tr

  assert_supported_os
  warn_if_current_session_is_cosmic

  if ! package_installed "$TARGET_PKG"; then
    die "${TARGET_PKG} is not installed as an APT package on this system."
  fi

  show_package_facts
  get_held_packages
  apt_health_check
  build_reverse_dependency_closure
  simulate_plan
  check_desktop_impact
  check_held_package_conflicts

  if (( DRY_RUN == 1 )); then
    print_summary
    exit 0
  fi

  confirm_execution
  execute_plan
  remove_user_data
  post_checks
  print_summary
}

main "$@"
