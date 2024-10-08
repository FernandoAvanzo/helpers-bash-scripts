#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"
export GP_CERTS_FOLDER="$HOME/Applications/paloAlto/GlobalProtect/certificates"
export SYSTEM_CERTS_FOLDER="/usr/local/share/ca-certificates"

# shellcheck source=./../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"

verify_and_remove_old_certificates() {
  if [ -d "$SYSTEM_CERTS_FOLDER" ]; then
    echo "$password" | sudo -S rm -rf "$SYSTEM_CERTS_FOLDER"
  fi
}

verify_and_remove_old_certificates

copy_certificates() {
  local file
  for file in "$GP_CERTS_FOLDER"/*.crt; do
    local filename
    filename=$(basename -- "$file" .crt)
    local new_folder="$SYSTEM_CERTS_FOLDER/$filename"
    echo "$password" | sudo -S mkdir -p "$new_folder"
    echo "$password" | sudo -S cp "$GP_CERTS_FOLDER/$filename.crt" "$new_folder"
  done
}

check_and_change_permissions() {
  local file
  echo "$password" | sudo -S chmod 755 "$SYSTEM_CERTS_FOLDER"
  for file in "$GP_CERTS_FOLDER"/*.crt; do
    local filename
    filename=$(basename -- "$file" .crt)
    local target_folder="$SYSTEM_CERTS_FOLDER/$filename"
    if [ -d "$target_folder" ]; then
      echo "$password" | sudo -S chmod 644 "$target_folder/$filename.crt"
    fi
  done
}

verify_and_remove_old_certificates
copy_certificates
check_and_change_permissions
echo "$password" | sudo -S update-ca-certificates
