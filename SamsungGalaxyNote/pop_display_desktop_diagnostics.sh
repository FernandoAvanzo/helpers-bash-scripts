#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME=${0##*/}
readonly VERSION="1.0.0"

usage() {
  cat <<'EOF'
Collect Pop!_OS display, desktop, and screen diagnostics into a timestamped directory.

Usage:
  pop_display_desktop_diagnostics.sh [--output-dir DIR] [--no-archive] [--help]

Options:
  --output-dir DIR   Write results into DIR instead of the default timestamped folder.
  --no-archive       Skip creation of the .tar.xz archive.
  -h, --help         Show this help message.

Notes:
  - The script never prompts for sudo.
  - If passwordless sudo is already available, it uses it for protected logs.
  - If not, it still collects all user-readable diagnostics.
EOF
}

log()  { printf '[INFO] %s\n' "$*" >&2; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

have() {
  command -v "$1" >/dev/null 2>&1
}

quote_cmd() {
  printf '$'
  local arg
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

run_cmd() {
  local outfile=$1
  shift
  local -a cmd=("$@")

  {
    quote_cmd "${cmd[@]}"
    printf '\n'
    "${cmd[@]}"
  } >"$outfile" 2>&1 || {
    local status=$?
    printf '\n[exit_status]=%s\n' "$status" >>"$outfile"
    return 0
  }
}

run_bash() {
  local outfile=$1
  shift
  local script=$1
  shift
  local -a prefix=("$@")
  local -a cmd=("${prefix[@]}" bash -lc "$script")

  {
    quote_cmd "${cmd[@]}"
    printf '\n'
    "${cmd[@]}"
  } >"$outfile" 2>&1 || {
    local status=$?
    printf '\n[exit_status]=%s\n' "$status" >>"$outfile"
    return 0
  }
}

copy_if_readable() {
  local src=$1
  local dest=$2

  if [[ -r "$src" && ! -d "$src" ]]; then
    cp -a -- "$src" "$dest"
    return 0
  fi

  if [[ -d "$src" && -r "$src" ]]; then
    mkdir -p "$dest"
    cp -a -- "$src"/. "$dest"/ 2>/dev/null || true
    return 0
  fi

  printf 'missing-or-unreadable: %s\n' "$src" >"${dest}.missing.txt"
}

write_text() {
  local outfile=$1
  shift
  cat >"$outfile" <<EOF
$*
EOF
}

make_section_dirs() {
  mkdir -p \
    "$OUTDIR/system" \
    "$OUTDIR/session" \
    "$OUTDIR/graphics" \
    "$OUTDIR/journal" \
    "$OUTDIR/user-session" \
    "$OUTDIR/files"
}

collect_basic_info() {
  log 'Collecting system metadata'
  run_cmd "$OUTDIR/system/date.txt" date --iso-8601=seconds
  run_cmd "$OUTDIR/system/hostnamectl.txt" hostnamectl
  run_cmd "$OUTDIR/system/uname.txt" uname -a
  run_cmd "$OUTDIR/system/os-release.txt" cat /etc/os-release
  run_cmd "$OUTDIR/system/bash-version.txt" bash --version
  run_cmd "$OUTDIR/system/locale.txt" locale

  if have systemctl; then
    run_cmd "$OUTDIR/system/systemd-version.txt" systemctl --version
  fi
}

collect_session_info() {
  log 'Collecting session and desktop stack information'

  run_bash "$OUTDIR/session/environment.txt" \
    'printf "USER=%s\nHOME=%s\nXDG_SESSION_ID=%s\nXDG_SESSION_TYPE=%s\nXDG_CURRENT_DESKTOP=%s\nXDG_SESSION_DESKTOP=%s\nDESKTOP_SESSION=%s\nWAYLAND_DISPLAY=%s\nDISPLAY=%s\n" \
      "${USER:-}" "${HOME:-}" "${XDG_SESSION_ID:-}" "${XDG_SESSION_TYPE:-}" "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}" "${DESKTOP_SESSION:-}" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}"'

  run_bash "$OUTDIR/session/printenv-sorted.txt" 'printenv | sort'

  if have loginctl; then
    run_cmd "$OUTDIR/session/logind-list-sessions.txt" loginctl list-sessions
    run_cmd "$OUTDIR/session/logind-seat0.txt" loginctl seat-status seat0

    run_bash "$OUTDIR/session/logind-current-session.txt" \
      'if [[ -n "${XDG_SESSION_ID:-}" ]]; then
         loginctl show-session "$XDG_SESSION_ID" -p Id -p Name -p User -p Type -p Class -p State -p Remote -p Desktop -p Service -p Leader;
       else
         printf "XDG_SESSION_ID is not set.\n";
       fi'
  fi

  if have systemctl; then
    run_cmd "$OUTDIR/session/system-services-display-managers.txt" \
      systemctl --no-pager --full status greetd gdm gdm3
    run_bash "$OUTDIR/session/user-services-desktop-related.txt" \
      'systemctl --user --type=service --no-pager --all | grep -Ei "cosmic|gnome|mutter|xwayland|portal|greetd" || true'
  fi

  run_bash "$OUTDIR/session/processes-desktop-related.txt" \
    'ps -ef | grep -Ei "cosmic-comp|cosmic-session|cosmic-greeter|greetd|gnome-shell|mutter|gdm|gdm3|Xorg|Xwayland" | grep -Ev "grep|rg" || true'
}

collect_graphics_info() {
  log 'Collecting graphics, monitor, and display details'

  run_cmd "$OUTDIR/graphics/proc-cmdline.txt" cat /proc/cmdline

  if have lspci; then
    run_bash "$OUTDIR/graphics/lspci-gpu.txt" \
      'lspci -nnk | grep -EA4 "(VGA compatible controller|3D controller|Display controller)" || true'
  fi

  if have lsmod; then
    run_bash "$OUTDIR/graphics/lsmod-graphics.txt" \
      'lsmod | grep -Ei "i915|xe|amdgpu|nouveau|nvidia|drm|kms|video" || true'
  fi

  if have xrandr; then
    run_cmd "$OUTDIR/graphics/xrandr-verbose.txt" xrandr --verbose
  else
    write_text "$OUTDIR/graphics/xrandr-verbose.txt" 'xrandr not available in PATH.'
  fi

  if have wayland-info; then
    run_cmd "$OUTDIR/graphics/wayland-info.txt" wayland-info
  else
    write_text "$OUTDIR/graphics/wayland-info.txt" 'wayland-info not available in PATH.'
  fi
}

collect_system_journal() {
  log 'Collecting system journal excerpts'

  run_cmd "$OUTDIR/journal/journal-boot-kernel.txt" "${PRIV[@]}" journalctl -b -k --no-pager

  run_bash "$OUTDIR/journal/journal-boot-kernel-display-filtered.txt" \
    'journalctl -b -k --no-pager | grep -Ei "drm|kms|edid|i915|xe|amdgpu|nouveau|nvidia|typec|thunderbolt|display|connector|hdmi|dp-|eDP" || true' \
    "${PRIV[@]}"

  run_cmd "$OUTDIR/journal/journal-boot-warnings-errors.txt" "${PRIV[@]}" \
    journalctl -b --priority=warning --no-pager

  run_cmd "$OUTDIR/journal/journal-greetd.txt" "${PRIV[@]}" \
    journalctl -b -u greetd --no-pager

  run_cmd "$OUTDIR/journal/journal-gdm.txt" "${PRIV[@]}" \
    journalctl -b -u gdm --no-pager

  run_cmd "$OUTDIR/journal/journal-gdm3.txt" "${PRIV[@]}" \
    journalctl -b -u gdm3 --no-pager
}

collect_user_journal() {
  log 'Collecting user-session journal excerpts'

  run_bash "$OUTDIR/user-session/journal-user-full.txt" \
    'journalctl --user -b --no-pager' \
    "${USER_RUN[@]}"

  run_bash "$OUTDIR/user-session/journal-user-desktop-filtered.txt" \
    'journalctl --user -b --no-pager | grep -Ei "cosmic|gnome-shell|mutter|xwayland|wayland|portal" || true' \
    "${USER_RUN[@]}"

  run_bash "$OUTDIR/user-session/journal-user-cosmic-comp.txt" \
    'journalctl --user -b _COMM=cosmic-comp --no-pager' \
    "${USER_RUN[@]}"

  run_bash "$OUTDIR/user-session/journal-user-cosmic-session.txt" \
    'journalctl --user -b _COMM=cosmic-session --no-pager' \
    "${USER_RUN[@]}"

  run_bash "$OUTDIR/user-session/journal-user-gnome-shell.txt" \
    'journalctl --user -b _COMM=gnome-shell --no-pager' \
    "${USER_RUN[@]}"

  run_bash "$OUTDIR/user-session/journal-user-mutter.txt" \
    'journalctl --user -b _COMM=mutter --no-pager' \
    "${USER_RUN[@]}"
}

collect_relevant_files() {
  log 'Collecting relevant configuration, state, and Xorg files'

  copy_if_readable '/etc/greetd/config.toml' "$OUTDIR/files/greetd-config.toml"
  copy_if_readable '/etc/X11/xorg.conf' "$OUTDIR/files/xorg.conf"
  copy_if_readable '/etc/X11/xorg.conf.d' "$OUTDIR/files/xorg.conf.d"
  copy_if_readable '/var/log/Xorg.0.log' "$OUTDIR/files/Xorg.0.log"
  copy_if_readable "$TARGET_HOME/.local/share/xorg/Xorg.0.log" "$OUTDIR/files/user-Xorg.0.log"
  copy_if_readable "$TARGET_HOME/.local/state/cosmic-comp/outputs.ron" "$OUTDIR/files/cosmic-outputs.ron"
  copy_if_readable "$TARGET_HOME/.config/monitors.xml" "$OUTDIR/files/monitors.xml"

  local envfile="$OUTDIR/files/relevant-paths.txt"
  {
    printf 'TARGET_USER=%s\n' "$TARGET_USER"
    printf 'TARGET_HOME=%s\n\n' "$TARGET_HOME"
    ls -ld /etc/greetd /etc/X11 /var/log \
      "$TARGET_HOME/.config" \
      "$TARGET_HOME/.local/state" \
      "$TARGET_HOME/.local/share/xorg" 2>/dev/null || true
  } >"$envfile" 2>&1
}

write_summary() {
  local priv_mode='no-elevated-access'
  if (( EUID == 0 )); then
    priv_mode='root'
  elif (( ${#PRIV[@]} > 0 )); then
    priv_mode='passwordless-sudo'
  fi

  cat >"$OUTDIR/SUMMARY.txt" <<EOF
Display/Desktop diagnostics collection completed.

Script:   $SCRIPT_NAME
Version:  $VERSION
Created:  $(date --iso-8601=seconds)
Host:     $HOST_SHORT
User:     $CURRENT_USER
Target:   $TARGET_USER
Home:     $TARGET_HOME
Output:   $OUTDIR
Archive:  ${ARCHIVE:-not-created}
Access:   $priv_mode

Most useful files for display and screen issues:
- journal/journal-boot-kernel-display-filtered.txt
- journal/journal-greetd.txt
- journal/journal-gdm.txt
- user-session/journal-user-desktop-filtered.txt
- user-session/journal-user-cosmic-comp.txt
- user-session/journal-user-gnome-shell.txt
- graphics/xrandr-verbose.txt
- graphics/wayland-info.txt
- files/cosmic-outputs.ron
- files/monitors.xml
- files/Xorg.0.log
- files/user-Xorg.0.log

If you ran this script directly as root, user-session logs may refer to root's user journal
instead of the desktop user journal. Running it as your normal desktop user is preferred.
EOF
}

archive_results() {
  if (( MAKE_ARCHIVE == 0 )); then
    ARCHIVE=''
    log 'Skipping archive creation (--no-archive)'
    return 0
  fi

  if have tar; then
    log 'Creating tar.xz archive'
    tar -C "$(dirname "$OUTDIR")" -cJf "$ARCHIVE" "$(basename "$OUTDIR")"
  else
    warn 'tar not found; archive not created'
    ARCHIVE=''
  fi
}

parse_args() {
  MAKE_ARCHIVE=1
  OUTDIR=''

  while (($#)); do
    case "$1" in
      --output-dir)
        shift
        (($#)) || die '--output-dir requires a directory path'
        OUTDIR=$1
        ;;
      --no-archive)
        MAKE_ARCHIVE=0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

init_context() {
  readonly HOST_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-host')"
  readonly CURRENT_USER="$(id -un)"
  readonly TARGET_USER="${SUDO_USER:-$CURRENT_USER}"

  local passwd_home=''
  if have getent; then
    passwd_home="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
  fi
  readonly TARGET_HOME="${passwd_home:-${HOME:-}}"

  if [[ -z "$OUTDIR" ]]; then
    readonly OUTDIR="$PWD/${HOST_SHORT}-display-desktop-diagnostics-$(date +%Y%m%d-%H%M%S)"
  else
    readonly OUTDIR
  fi

  ARCHIVE="${OUTDIR}.tar.xz"

  if (( EUID == 0 )); then
    PRIV=()
  elif have sudo && sudo -n true 2>/dev/null; then
    PRIV=(sudo -n)
  else
    PRIV=()
  fi

  if (( EUID == 0 )) && [[ -n "${SUDO_USER:-}" ]]; then
    USER_RUN=(sudo -n -u "$SUDO_USER")
  else
    USER_RUN=()
  fi
}

main() {
  parse_args "$@"
  init_context
  trap 'status=$?; printf "[ERROR] Script aborted with status %s. Partial results remain in %s\n" "$status" "$OUTDIR" >&2; exit "$status"' ERR

  make_section_dirs

  cat >"$OUTDIR/NOTES.txt" <<EOF
This bundle was generated by $SCRIPT_NAME $VERSION.

What it collects:
- System identity and OS metadata
- Login/session manager state
- Desktop/compositor process inventory
- Kernel graphics and display journal entries
- Greeter/display-manager journal entries
- User-session journal entries for COSMIC/GNOME/XWayland
- Xorg logs if present
- Relevant display state/config files

Privilege behavior:
- The script never prompts for sudo.
- If passwordless sudo is available, system logs are collected with it.
- If not, unreadable files are recorded as missing-or-unreadable.

Preferred usage:
- Run this as your regular desktop user, not via sudo.
EOF

  if (( EUID == 0 )) && [[ -z "${SUDO_USER:-}" ]]; then
    warn 'Running directly as root; user-session logs may not represent the desktop user.'
  fi

  collect_basic_info
  collect_session_info
  collect_graphics_info
  collect_system_journal
  collect_user_journal
  collect_relevant_files
  write_summary
  archive_results

  printf '\n'
  log "Done. Results directory: $OUTDIR"
  if [[ -n "${ARCHIVE:-}" ]]; then
    log "Archive: $ARCHIVE"
  fi
}

declare -a PRIV=()
declare -a USER_RUN=()
MAKE_ARCHIVE=1
OUTDIR=''
ARCHIVE=''

main "$@"
