#!/usr/bin/env bash
# fix_popos_apt_conflict.sh
# Resolve apt Signed-By conflicts on Pop!_OS 24.04
set -euo pipefail

REPO_URL="http://apt.pop-os.org/ubuntu"
EXPECTED_KEY="/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg"
BACKUP_DIR="/etc/apt/sources.list.d.bak-$(date +%Y%m%d-%H%M%S)"

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Backup sources.list.d
if [[ -d /etc/apt/sources.list.d ]]; then
  echo "Backing up /etc/apt/sources.list.d to $BACKUP_DIR"
  cp -a /etc/apt/sources.list.d "$BACKUP_DIR"
fi

cd /etc/apt/sources.list.d || { echo "sources.list.d not found"; exit 1; }

# Find files referencing the repository URL
mapfile -t FILES < <(grep -Rl "$REPO_URL" . || true)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No sources referencing $REPO_URL were found. Exiting."
  exit 0
fi

echo "Found ${#FILES[@]} files referencing $REPO_URL: ${FILES[*]}"

# Normalize Signed-By entries
for file in "${FILES[@]}"; do
  # Determine current Signed-By values in file
  current_keys=$(grep -E "^Signed-By:" "$file" | awk '{print $2}') || true
  if [[ -z "$current_keys" ]]; then
    echo "File $file has no Signed-By field; skipping." >&2
    continue
  fi
  # If the file contains the expected key, leave it untouched
  if echo "$current_keys" | grep -q "$EXPECTED_KEY"; then
    echo "File $file already uses expected key $EXPECTED_KEY, leaving unchanged."
    continue
  fi

  # Attempt to replace conflicting Signed-By line
  echo "Normalizing Signed-By in $file..."
  # Use sed to replace the entire Signed-By line
  sed -i.bak "s|^Signed-By:.*|Signed-By: $EXPECTED_KEY|" "$file"
  echo "Updated $file: changed Signed-By to $EXPECTED_KEY (backup saved as $file.bak)"

done

# Run apt update and report success or failure
if apt-get update; then
  echo "apt update completed successfully. The Signed-By conflict should be resolved."
else
  echo "apt update encountered errors. Please review the sources files manually." >&2
fi
