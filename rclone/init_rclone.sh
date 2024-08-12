#!/bin/bash
#dev
export DEV_RCLONE="$HOME/Projects/helpers-bash-scripts/rclone"
#prod
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./bin/manage_rclone_service.sh
source "$RCLONE"/bin/manage_rclone_service.sh

# shellcheck source=./bin/rclone_reconnect.sh
source "$RCLONE"/bin/rclone_reconnect.sh

if ! rclone ls remote:/BaseDeConhecimento; then
  echo "Reconnect Rclone"
  rclone_reconnect
fi

manage_rclone_service