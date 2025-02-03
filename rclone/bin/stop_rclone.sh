#!/bin/bash
export DEV_RCLONE="$MY_CLI/rclone"
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./manage_rclone_service.sh
source "$RCLONE"/bin/manage_rclone_service.sh

stop_rclone_service

#Install command
#echo "$(get-root-psw)" | sudo -S ln -sf $HOME/.Library/rclone/bin/stop_rclone.sh /usr/bin/stop_rclone
