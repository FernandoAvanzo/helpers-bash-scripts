#!/usr/bin/env bash
# fix_popos_apt_conflict_v2.sh
#
# This script resolves apt Signed-By conflicts on Pop!_OS 24.04 by
# normalizing all entries pointing at http://apt.pop-os.org/ubuntu to use
# the same key file.  It also disables backup files that apt may
# inadvertently read (e.g. *.bak, *.save) to prevent duplicate repository
# definitions from causing conflicts.
#
# Usage: run as root: sudo ./fix_popos_apt_conflict_v2.sh

set -euo pipefail

# URL of the Pop!_OS Ubuntu mirror whose entries we are normalizing
REPO_URL="http://apt.pop-os.org/ubuntu"
# Canonical key file to use for all Signed-By references
EXPECTED_KEY="/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg"
# Directory containing apt source lists
SRCDIR="/etc/apt/sources.list.d"
# Create a timestamped backup directory
BACKUP_DIR="${SRCDIR}.bak-$(date +%Y%m%d-%H%M%S)"

function require_root() {
  # Ensure the script is executed with root privileges
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

function backup_sources() {
  # Back up the entire sources.list.d directory
  if [[ -d "$SRCDIR" ]]; then
    echo "Backing up $SRCDIR to $BACKUP_DIR"
    cp -a "$SRCDIR" "$BACKUP_DIR"
  else
    echo "Directory $SRCDIR does not exist; nothing to back up." >&2
    exit 1
  fi
}

function normalize_sources() {
  cd "$SRCDIR"
  # Find all files referencing the repository URL
  mapfile -t files < <(grep -Rl "$REPO_URL" . || true)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files referencing $REPO_URL were found."
    return
  fi
  echo "Found ${#files[@]} files referencing $REPO_URL: ${files[*]}"
  for file in "${files[@]}"; do
    # Skip directories
    if [[ -d "$file" ]]; then
      continue
    fi
    # Determine file extension (portion after last dot)
    ext="${file##*.}"
    # Disable backup files (.bak or .save) by renaming them to .disabled
    if [[ "$file" =~ \.bak$ || "$file" =~ \.save$ ]]; then
      new_name="${file}.disabled"
      echo "Disabling backup file $file -> $new_name"
      mv "$file" "$new_name"
      continue
    fi
    # Normalize .sources files
    if [[ "$ext" == "sources" ]]; then
      # Check if Signed-By line exists
      if grep -q '^Signed-By:' "$file"; then
        # Replace existing Signed-By line with expected key
        sed -i.bak "s|^Signed-By:.*|Signed-By: $EXPECTED_KEY|" "$file"
        echo "Updated Signed-By in $file (backup at $file.bak)"
      else
        # Insert Signed-By line after URIs line if missing
        sed -i.bak "/^URIs:/a Signed-By: $EXPECTED_KEY" "$file"
        echo "Added Signed-By line to $file (backup at $file.bak)"
      fi
      continue
    fi
    # Normalize .list files
    if [[ "$ext" == "list" ]]; then
      # Only operate on lines referencing the repository URL
      # Check if [signed-by=] already exists on the line
      if grep -qE "^deb\s+\[.*signed-by=[^]]*\]" "$file"; then
        # Replace existing signed-by value within square brackets
        sed -i.bak "s|\[\([^]]*\)signed-by=[^ ]*|[\1signed-by=$EXPECTED_KEY|" "$file"
        echo "Replaced inline signed-by directive in $file (backup at $file.bak)"
      else
        # Prepend inline signed-by directive after 'deb' on lines with the repo URL
        # This preserves other options (e.g., arch=amd64) within the square bracket if present.
        sed -i.bak "/^deb\s\+\(\[[^]]*\]\s\+\)\?${REPO_URL//\//\/}/ s|^deb\s\+|deb [signed-by=$EXPECTED_KEY] |" "$file"
        echo "Inserted inline signed-by directive in $file (backup at $file.bak)"
      fi
      continue
    fi
    echo "Skipping unrecognized file type $file"
  done
}

function run_apt_update() {
  echo "Running apt update to verify that the conflict has been resolved..."
  if apt-get update; then
    echo "apt update completed successfully. Signed-By conflicts should now be resolved."
  else
    echo "apt update still reports errors. Please review the modified sources files manually." >&2
  fi
}

require_root
backup_sources
normalize_sources
run_apt_update