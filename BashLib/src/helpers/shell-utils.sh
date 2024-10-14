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

  # Generate SHA-512 checksum
  local SHA512_CHECKSUM
  SHA512_CHECKSUM=$(sha512sum "$FILE" | awk '{ print $1 }')

  # Print the checksum
  echo "$SHA512_CHECKSUM"
}

base64_encrypt() {
  local input="$1"
  local encrypted
  encrypted=$(echo -n "$input" | base64)
  echo "$encrypted"
}
