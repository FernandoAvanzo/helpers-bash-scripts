#!/usr/bin/env bash
# install_leveldb-cli.sh – Pop!_OS 22.04

set -euo pipefail

echo "==> Installing prerequisites (Go toolchain)…"
if ! command -v go >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y golang-go git build-essential
fi

echo "==> Setting GOPATH and PATH (idempotent)…"
grep -q 'export GOPATH=' ~/.bashrc || {
  echo 'export GOPATH=$HOME/go' >> ~/.bashrc
  echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.bashrc
  export GOPATH=$HOME/go
  export PATH=$PATH:$GOPATH/bin
}

echo "==> Fetching latest leveldb-cli…"
go install github.com/cions/leveldb-cli/cmd/leveldb@latest

echo "==> Linking into /usr/local/bin (sudo)…"
sudo ln -sf "$GOPATH/bin/leveldb" /usr/local/bin/leveldb

echo "✅ leveldb-cli installed: $(leveldb --version 2>/dev/null || true)"
