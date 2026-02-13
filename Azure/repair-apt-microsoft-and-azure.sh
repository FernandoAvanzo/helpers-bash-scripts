#!/usr/bin/env bash
# repair-apt-microsoft-and-azure.sh
# Fixes Microsoft + Azure CLI APT repo configs on Pop!_OS/Ubuntu 22.04 (jammy).

set -euo pipefail

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TMP_OUT="$(mktemp)"; trap 'rm -f "$TMP_OUT"' EXIT

MS_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
MS_KEYRING="/etc/apt/keyrings/microsoft.gpg"
MS_PROD_LIST="/etc/apt/sources.list.d/microsoft-prod.list"
AZURE_SOURCES="/etc/apt/sources.list.d/azure-cli.sources"

log(){ printf "\n==> %s\n" "$*"; }
warn(){ printf "\n[WARNING] %s\n" "$*" >&2; }
fail(){ printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }
need_root(){ [[ $EUID -eq 0 ]] || fail "Run as root: sudo bash $0"; }
have(){ command -v "$1" >/dev/null 2>&1; }

backup(){ local f="$1"; [[ -e "$f" ]] && cp -a "$f" "${f}.bak.${STAMP}"; }

detect_suite(){
  # Prefer UBUNTU_CODENAME when present (Pop!_OS sets this to jammy on 22.04)
  local suite=""
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    suite="${UBUNTU_CODENAME:-}"
  fi
  [[ -z "$suite" && $(have lsb_release && lsb_release -cs || echo "") ]] && suite="$(lsb_release -cs || true)"
  # Pop!_OS 22.04 -> jammy; fall back to jammy if unsure
  case "${suite,,}" in
  jammy|focal|noble|bullseye|bookworm) : ;;
  *) suite="jammy" ;;
  esac
  echo "$suite"
}

ensure_key(){
  log "Ensuring Microsoft dearmored key at $MS_KEYRING"
  mkdir -p /etc/apt/keyrings
  if have curl; then
    curl -fsSL "$MS_KEY_URL" | gpg --dearmor -o "$MS_KEYRING"
  elif have wget; then
    wget -qO- "$MS_KEY_URL" | gpg --dearmor -o "$MS_KEYRING"
  else
    fail "Need curl or wget to fetch key."
  fi
  chmod 0644 "$MS_KEYRING"
}

write_ms_prod_list(){
  log "Writing canonical Microsoft repo (prod) to $MS_PROD_LIST"
  backup "$MS_PROD_LIST"
  local arch; arch="$(dpkg --print-architecture)"
  cat >"$MS_PROD_LIST" <<EOF
deb [arch=${arch} signed-by=${MS_KEYRING}] https://packages.microsoft.com/ubuntu/22.04/prod jammy main
EOF
  chmod 0644 "$MS_PROD_LIST"
}

write_azure_sources(){
  local suite arch
  suite="$(detect_suite)"
  arch="$(dpkg --print-architecture)"
  log "Repairing Azure CLI deb822 source at $AZURE_SOURCES (Suite: $suite, Arch: $arch)"
  backup "$AZURE_SOURCES"
  cat >"$AZURE_SOURCES" <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${suite}
Components: main
Architectures: ${arch}
Signed-By: ${MS_KEYRING}
EOF
  chmod 0644 "$AZURE_SOURCES"
}

disable_extra_ms_sources(){
  log "Disabling extra Microsoft sources (leaving only microsoft-prod.list and azure-cli.sources)"
  shopt -s nullglob
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    # Skip missing
    [[ -e "$f" ]] || continue
    # Skip our canonical files
    [[ "$f" == "$MS_PROD_LIST" || "$f" == "$AZURE_SOURCES" ]] && continue
    # Skip backups and obviously disabled files
    [[ "$f" == *.bak.* || "$f" == *.disabled* ]] && continue
    if grep -qE 'packages\.microsoft\.com' "$f"; then
      local new="${f}.disabled-${STAMP}"
      log "  -> Moving $f -> $new"
      mv "$f" "$new"
    fi
  done
  shopt -u nullglob
}

show_active_ms(){
  printf "\n-- Active Microsoft entries (real .list/.sources only) --\n"
  # .list one-liners:
  grep -Rhs "^[[:space:]]*deb .*packages\.microsoft\.com" /etc/apt/sources.list /etc/apt/sources.list.d/*.list || true
  # .sources deb822 URIs:
  awk '
    BEGIN{RS="";FS="\n"}
    /packages\.microsoft\.com/ {
      print "File: " FILENAME "\n" $0 "\n---"
    }' /etc/apt/sources.list.d/*.sources 2>/dev/null | sed -n '1,200p' || true
}

apt_refresh_verify(){
  log "Cleaning APT and refreshing lists"
  apt-get clean
  rm -rf /var/lib/apt/lists/*
  set +e
  apt-get update >"$TMP_OUT" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warn "apt-get update exit code: $rc (showing last 50 lines)"
    tail -n 50 "$TMP_OUT" >&2
  fi
  # Fail if typical errors remain
  if grep -q 'Conflicting values set for option Signed-By' "$TMP_OUT"; then
    fail "Still seeing Signed-By conflicts."
  fi
  if grep -q 'Malformed entry .*azure-cli\.sources' "$TMP_OUT"; then
    fail "azure-cli.sources still malformed after repair."
  fi
  log "APT update succeeded ✅"
}

main(){
  need_root
  ensure_key
  write_ms_prod_list
  write_azure_sources
  disable_extra_ms_sources
  show_active_ms
  apt_refresh_verify
  log "Done."
  echo "Tip: if packages were left half-configured, run:"
  echo "  sudo dpkg --configure -a && sudo apt -f install && sudo apt full-upgrade"
}
main "$@"
