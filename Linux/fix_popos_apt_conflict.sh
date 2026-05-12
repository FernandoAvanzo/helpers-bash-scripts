#!/usr/bin/env bash
# fix_popos_apt_conflict_v4.sh
#
# This script resolves apt Signed-By conflicts on Pop!_OS 24.04 by
# ensuring that each repository definition for http://apt.pop-os.org/ubuntu
# uses a consistent GPG key and by disabling extraneous backup files.
# It rebuilds matching one-line .list entries from their logical parts so
# malformed leftovers such as two option blocks before the URI are repaired.
#
# Usage: run as root: sudo ./fix_popos_apt_conflict.sh

set -euo pipefail

# URL of the Pop!_OS Ubuntu mirror whose entries we are normalizing
REPO_URL="http://apt.pop-os.org/ubuntu"
# Canonical key file to use for all Signed-By references
EXPECTED_KEY="/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg"
# Directory containing apt source lists
SRCDIR="/etc/apt/sources.list.d"
# Timestamped backup directory
BACKUP_DIR="${SRCDIR}.bak-$(date +%Y%m%d-%H%M%S)"

require_root() {
  # Ensure the script is executed with root privileges
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

backup_sources() {
  # Back up the entire sources.list.d directory
  if [[ -d "$SRCDIR" ]]; then
    echo "Backing up $SRCDIR to $BACKUP_DIR"
    cp -a "$SRCDIR" "$BACKUP_DIR"
  else
    echo "Directory $SRCDIR does not exist; nothing to back up." >&2
    exit 1
  fi
}

replace_file_with_tmp() {
  local tmpfile="$1"
  local file="$2"
  local owner
  local group
  local mode

  owner=$(stat -c '%u' "$file")
  group=$(stat -c '%g' "$file")
  mode=$(stat -c '%a' "$file")
  install -o "$owner" -g "$group" -m "$mode" "$tmpfile" "$file"
  rm -f "$tmpfile"
}

disable_source_file() {
  local file="$1"
  local new_name="${file}.disabled"

  echo "Disabling $file -> $new_name"
  mv -f -- "$file" "$new_name"
}

move_invalid_disabled_artifact() {
  local file="$1"
  local rel_file="${file#$SRCDIR/}"
  local artifact_dir="$BACKUP_DIR/disabled-artifacts"

  mkdir -p "$artifact_dir"
  echo "Moving invalid disabled artifact $rel_file -> $artifact_dir/$rel_file"
  mv -f -- "$file" "$artifact_dir/$rel_file"
}

normalize_deb822_sources_file() {
  local file="$1"
  local tmpfile

  tmpfile=$(mktemp)
  awk -v repo="$REPO_URL" -v key="$EXPECTED_KEY" '
    function flush_stanza(    i, has_repo, has_signed_by) {
      if (count == 0) {
        return
      }

      has_repo = 0
      has_signed_by = 0

      for (i = 1; i <= count; i++) {
        if (lines[i] ~ /^URIs:/ && index(lines[i], repo) > 0) {
          has_repo = 1
        }
        if (lines[i] ~ /^Signed-By:/) {
          has_signed_by = 1
        }
      }

      for (i = 1; i <= count; i++) {
        if (has_repo && lines[i] ~ /^Signed-By:/) {
          print "Signed-By: " key
        } else {
          print lines[i]
        }

        if (has_repo && !has_signed_by && lines[i] ~ /^URIs:/) {
          print "Signed-By: " key
          has_signed_by = 1
        }
      }

      count = 0
      for (i in lines) {
        delete lines[i]
      }
    }

    /^$/ {
      flush_stanza()
      print
      next
    }

    {
      lines[++count] = $0
    }

    END {
      flush_stanza()
    }
  ' "$file" > "$tmpfile"

  replace_file_with_tmp "$tmpfile" "$file"
  echo "Normalized Signed-By in $file"
}

append_unique_option() {
  local option="$1"
  local existing

  for existing in "${options[@]}"; do
    if [[ "$existing" == "$option" ]]; then
      return
    fi
  done

  options+=("$option")
}

normalize_list_line() {
  local line="$1"
  local indent
  local source_type
  local before_uri
  local rest
  local option_area
  local cleaned_options
  local option
  local options=()

  if [[ "$line" != *"$REPO_URL"* ]]; then
    printf '%s\n' "$line"
    return
  fi

  if [[ ! "$line" =~ ^([[:space:]]*)(deb|deb-src)[[:space:]]+ ]]; then
    printf '%s\n' "$line"
    return
  fi

  indent="${BASH_REMATCH[1]}"
  source_type="${BASH_REMATCH[2]}"
  before_uri="${line%%"$REPO_URL"*}"
  rest="${REPO_URL}${line#*"$REPO_URL"}"

  if [[ "$before_uri" =~ ^[[:space:]]*(deb|deb-src)[[:space:]]*(.*)$ ]]; then
    option_area="${BASH_REMATCH[2]}"
  else
    option_area=""
  fi

  cleaned_options="${option_area//[/ }"
  cleaned_options="${cleaned_options//]/ }"

  for option in $cleaned_options; do
    if [[ "$option" == signed-by=* ]]; then
      continue
    fi
    if [[ "$option" == *=* ]]; then
      append_unique_option "$option"
    fi
  done

  append_unique_option "signed-by=$EXPECTED_KEY"

  printf '%s%s [%s] %s\n' "$indent" "$source_type" "${options[*]}" "$rest"
}

normalize_list_file() {
  local file="$1"
  local tmpfile
  local line

  tmpfile=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    normalize_list_line "$line" >> "$tmpfile"
  done < "$file"

  replace_file_with_tmp "$tmpfile" "$file"
  echo "Normalized inline signed-by directives in $file"
}

normalize_sources() {
  local files=()
  local active_list_files=()
  local file
  local rel_file

  # Find source-list files in the apt source directory that reference the URL.
  while IFS= read -r -d '' file; do
    if grep -qF -- "$REPO_URL" "$file"; then
      files+=("$file")
    fi
  done < <(find "$SRCDIR" -maxdepth 1 -type f -print0)

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files referencing $REPO_URL were found."
    return
  fi

  printf 'Found %s files referencing %s:' "${#files[@]}" "$REPO_URL"
  for file in "${files[@]}"; do
    printf ' %s' "${file#$SRCDIR/}"
  done
  printf '\n'

  for file in "${files[@]}"; do
    rel_file="${file#$SRCDIR/}"

    if [[ "$rel_file" == *.disabled ]]; then
      echo "Skipping already-disabled file $rel_file"
      continue
    fi

    if [[ "$rel_file" == *.disabled.* ]]; then
      move_invalid_disabled_artifact "$file"
      continue
    fi

    if [[ "$rel_file" =~ \.(bak|save)(\.|$) ]]; then
      disable_source_file "$file"
      continue
    fi

    if [[ "$rel_file" == *.sources ]]; then
      normalize_deb822_sources_file "$file"
      continue
    fi

    if [[ "$rel_file" == *.list ]]; then
      normalize_list_file "$file"
      active_list_files+=("$file")
      continue
    fi

    echo "Skipping unrecognized file type $rel_file"
  done

  if [[ -f "$SRCDIR/system.sources" ]] && grep -qF -- "$REPO_URL" "$SRCDIR/system.sources"; then
    for file in "${active_list_files[@]}"; do
      if [[ -f "$file" ]]; then
        echo "Disabling redundant legacy list file ${file#$SRCDIR/}; system.sources already defines $REPO_URL"
        disable_source_file "$file"
      fi
    done
  fi
}

run_apt_update() {
  echo "Running apt update to verify that the conflict has been resolved..."
  if apt-get update; then
    echo "apt update completed successfully. Signed-By conflicts should now be resolved."
  else
    echo "apt update still reports errors. Please review the modified sources files manually." >&2
    return 1
  fi
}

require_root
backup_sources
normalize_sources
run_apt_update
