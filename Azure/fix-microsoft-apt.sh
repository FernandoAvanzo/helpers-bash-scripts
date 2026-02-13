#!/usr/bin/env bash
# fix-microsoft-apt.sh
# Standardizes Microsoft APT repo/key on Pop!_OS/Ubuntu 22.04 and verifies the fix.

set -euo pipefail

# --- Config ---
MS_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
MS_KEYRING="/etc/apt/keyrings/microsoft.gpg"
MS_REPO_URL="https://packages.microsoft.com/ubuntu/22.04/prod"
MS_SUITE="jammy"
MS_LIST="/etc/apt/sources.list.d/microsoft-prod.list"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

log() { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARNING] %s\n" "$*" >&2; }
fail() { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    fail "Please run as root: sudo bash $0"
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  cp -a "$f" "${f}.bak.${STAMP}"
}

standardize_keyring() {
  log "Ensuring Microsoft keyring at: $MS_KEYRING"
  mkdir -p /etc/apt/keyrings

  if ! have_cmd gpg; then
    fail "gpg is required to dearmor the key (install gnupg)."
  fi

  # Fetch key using curl or wget
  if have_cmd curl; then
    curl -fsSL "$MS_KEY_URL" | gpg --dearmor -o "$MS_KEYRING"
  elif have_cmd wget; then
    wget -qO- "$MS_KEY_URL" | gpg --dearmor -o "$MS_KEYRING"
  else
    fail "Need curl or wget to fetch the Microsoft key."
  fi

  chmod 0644 "$MS_KEYRING"
}

write_single_repo() {
  log "Writing a single canonical Microsoft repo file: $MS_LIST"
  backup_file "$MS_LIST"

  # Detect host primary architecture (e.g., amd64, arm64)
  local arch
  arch="$(dpkg --print-architecture)"

  cat >"$MS_LIST" <<EOF
deb [arch=${arch} signed-by=${MS_KEYRING}] ${MS_REPO_URL} ${MS_SUITE} main
EOF

  chmod 0644 "$MS_LIST"
}

comment_out_duplicates() {
  log "Commenting out duplicate Microsoft repo entries elsewhere"

  # Iterate over likely source locations
  local files=()
  [[ -f /etc/apt/sources.list ]] && files+=("/etc/apt/sources.list")
  for f in /etc/apt/sources.list.d/*; do
    [[ -e "$f" ]] && files+=("$f")
  done

  for f in "${files[@]}"; do
    # Skip our canonical file
    [[ "$f" == "$MS_LIST" ]] && continue
    # Only act on files that reference packages.microsoft.com
    if grep -qE 'packages\.microsoft\.com' "$f"; then
      backup_file "$f"
      # If it's a deb822 ".sources" file, try to disable stanzas by setting Enabled: no
      if [[ "$f" =~ \.sources$ ]]; then
        # Only touch stanzas that point at packages.microsoft.com
        # If no Enabled field exists in such stanzas, comment matching lines.
        if grep -qE '^Enabled:\s*yes' "$f"; then
          sed -i '/packages\.microsoft\.com/{:a;N;/^\s*$/!ba;s/^Enabled:\s*yes/Enabled: no/}' "$f" || true
        fi
        # Fallback: comment lines referencing the Microsoft URI
        sed -i '/packages\.microsoft\.com/s/^/# [disabled by fix-microsoft-apt] /' "$f" || true
      else
        # Classic sources.list format: comment only the Microsoft lines
        sed -i \
          -e '/packages\.microsoft\.com/ s/^[[:space:]]*deb/# [disabled by fix-microsoft-apt] &/' \
          -e '/packages\.microsoft\.com/ s/^[[:space:]]*deb-src/# [disabled by fix-microsoft-apt] &/' \
          "$f"
      fi
    fi
  done
}

show_ms_refs() {
  printf "\n-- Active Microsoft entries after cleanup --\n"
  # Show only uncommented lines
  grep -R "^[[:space:]]*deb .*packages\.microsoft\.com" \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true
}

apt_refresh_and_verify() {
  log "Cleaning APT cache and refreshing lists"
  apt-get clean
  rm -rf /var/lib/apt/lists/*
  set +e
  apt-get update >"$TMP_OUT" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    log "APT update succeeded ✅"
  else
    warn "APT update returned non-zero (exit $rc). Showing the last lines of output:"
    tail -n 40 "$TMP_OUT" >&2
  fi

  if grep -q 'Conflicting values set for option Signed-By' "$TMP_OUT"; then
    fail "Verification failed: still seeing the Signed-By conflict."
  fi

  # Also verify there is exactly one active Microsoft entry
  local count
  count="$(grep -R "^[[:space:]]*deb .*packages\.microsoft\.com" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" -ne 1 ]]; then
    warn "Expected exactly 1 active Microsoft repo, found: $count"
    warn "You may need to manually inspect files printed above."
  else
    log "Exactly one active Microsoft repo is present ✅"
  fi
}

final_health_suggest() {
  log "Optional health steps (only if you had broken packages)"
  echo "  sudo dpkg --configure -a"
  echo "  sudo apt -f install"
  echo "  sudo apt full-upgrade"
  echo "  sudo apt autoremove --purge"
}

main() {
  require_root
  log "Fixing Microsoft APT configuration (Pop!_OS / Ubuntu 22.04)"
  standardize_keyring
  write_single_repo
  comment_out_duplicates
  show_ms_refs
  apt_refresh_and_verify
  final_health_suggest
  log "Done."
}

main "$@"
