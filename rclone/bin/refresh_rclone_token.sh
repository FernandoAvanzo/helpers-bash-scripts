#!/bin/bash
export DEV_RCLONE="$MY_CLI/rclone"
export RCLONE="$HOME/.Library/rclone"

source "$RCLONE"/bin/manage_rclone_service.sh

refresh_token_connection


#echo "$(get-root-psw)" | sudo -S ln -sf $RCLONE/bin/refresh_rclone_token.sh /usr/bin/refresh_rclone_token