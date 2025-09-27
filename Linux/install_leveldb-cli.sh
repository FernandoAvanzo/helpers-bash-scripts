#!/usr/bin/env bash
# install_leveldb-cli.sh – Pop!_OS 22.04

set -euo pipefail

echo "==> Installing prerequisites (Go toolchain)…"
if ! command -v go >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y git build-essential
fi

# Remove old Go version and install newer one
echo "==> Removing old Go installation and installing Go 1.23…"
sudo apt remove -y golang-go golang-1.18-go golang-1.18-src golang-src 2>/dev/null || true

# Download and install Go 1.23
cd /tmp
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
rm go1.23.4.linux-amd64.tar.gz

echo "==> Setting GOPATH and PATH (idempotent)…"
# Update PATH to include /usr/local/go/bin
grep -q 'export PATH.*:/usr/local/go/bin' ~/.zshrc || {
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc
}

grep -q 'export GOPATH=' ~/.zshrc || {
  echo 'export GOPATH=$HOME/go' >> ~/.zshrc
  echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.zshrc
}

# Set environment variables for current session
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

echo "==> Verifying Go installation…"
go version

echo "==> Fetching latest leveldb-cli…"
go install github.com/cions/leveldb-cli/cmd/leveldb@latest

echo "==> Linking into /usr/local/bin (sudo)…"
sudo ln -sf "$GOPATH/bin/leveldb" /usr/local/bin/leveldb

echo "✅ leveldb-cli installed: $(leveldb --version 2>/dev/null || true)"