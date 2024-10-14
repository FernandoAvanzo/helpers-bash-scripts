#!/bin/bash

extract_user_shell() {
  local shell_path
  local shell_name
  shell_path="$SHELL"
  shell_name=$(basename "$shell_path")
  echo "$shell_name"
}

generate_sha1_checksum() {
  local FILE="$1"

  # Check if the file exists
  if [ ! -f "$FILE" ]; then
    echo "File not found!"
    return 1
  fi

  # Generate SHA-1 checksum
  local SHA1_CHECKSUM
  SHA1_CHECKSUM=$(sha1sum "$FILE" | awk '{ print $1 }')

  # Print the checksum
  echo "SHA-1: $SHA1_CHECKSUM"
}
