#!/bin/bash
export DEV_RCLONE="$MY_CLI/rclone"
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./bin/manage_rclone_service.sh
source "$RCLONE"/bin/manage_rclone_service.sh
# shellcheck source=./bin/rclone_reconnect.sh
source "$RCLONE"/bin/rclone_reconnect.sh

check_and_create_folder
verify_folder_ownership
check_folder_permissions
create_systemd_symlink
verify_avanzo_drive_symlink

if ! rclone ls remote:/BaseDeConhecimento; then
  echo "Reconnect Rclone"
  reset_token
  rclone_reconnect
fi

manage_rclone_service
