#!/usr/bin/env bash
# install_leveldb.sh
# Install LevelDB on Pop!_OS 22.04 (Ubuntu 22.04 base)
# Usage: sudo ./install_leveldb.sh [--source]
#   --source   Build and install LevelDB from the latest upstream source instead of using APT packages.
#
# The script is idempotent and safe to re‑run.
# ------------------------------------------------------------
set -euo pipefail

#---------------------------
# Helper functions
#---------------------------
log() { printf "\033[1;32m[LevelDB] %s\033[0m\n" "$1"; }
err() { printf "\033[1;31m[LevelDB] ERROR: %s\033[0m\n" "$1" >&2; }
need_root() {
  if [[ $EUID -ne 0 ]]; then err "Please run as root (e.g. with sudo)."; exit 1; fi
}
command_exists() { command -v "$1" &>/dev/null; }

#---------------------------
# APT install a path
#---------------------------
install_via_apt() {
  log "Installing LevelDB via APT (libleveldb-dev, libleveldb1d)…"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y libleveldb-dev libleveldb1d
  log "APT installation complete. Version: $(pkg-config --modversion leveldb || echo 'unknown')"
}

#---------------------------
# Source build path
#---------------------------
install_from_source() {
  log "Installing build dependencies…"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y git build-essential cmake ninja-build libsnappy-dev libgtest-dev pkg-config

  local BUILD_DIR
  BUILD_DIR="${TMPDIR:-/tmp}/leveldb-build-$(date +%s)"
  mkdir -p "$BUILD_DIR"
  log "Cloning LevelDB into $BUILD_DIR…"
  git clone --depth 1 https://github.com/google/leveldb.git "$BUILD_DIR/leveldb"

  log "Building LevelDB…"
  cd "$BUILD_DIR/leveldb"
  mkdir build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ..
  ninja
  log "Running minimal tests…"
  ctest --output-on-failure

  log "Installing to system (\"/usr/local\")…"
  ninja install
  ldconfig

  log "Source installation complete. Version: $(pkg-config --modversion leveldb || echo 'unknown')"
}

#---------------------------
# Main
#---------------------------
need_root
MODE="apt"
[[ ${1:-} == "--source" ]] && MODE="source"

case $MODE in
  apt) install_via_apt ;;
  source) install_from_source ;;
  *) err "Unknown mode: $MODE" ; exit 1 ;;
esac

log "Verification: $(ldconfig -p | grep -o 'libleveldb.so.[0-9]*' | head -n1 || echo 'not found in ldconfig')"

log "Done. Happy hacking!"