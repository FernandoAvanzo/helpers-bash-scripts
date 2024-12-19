#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh
source "$RCLONE"/bin/rclone_reconnect.sh

check_and_create_folder() {
  local folder_path
  local password
  password="$(getRootPassword)"
  folder_path="/mnt/data/gdrive/avanzo-drive"

  if [ ! -d "$folder_path" ]; then
    echo "Folder does not exist. Creating new folder at $folder_path"
    if ! echo "$password" | sudo -S mkdir -p "$folder_path"; then
      echo "Failed to create folder."
      return 1
    fi
  else
    echo "Folder already exists at $folder_path"
  fi

  return 0
}

verify_folder_ownership() {
  local owner
  local password
  local folder_path
  folder_path="/mnt/data/gdrive/avanzo-drive"
  password="$(getRootPassword)"

  if [ -d "$folder_path" ]; then
    owner=$(stat -c '%U' "$folder_path")

    if [ "$owner" != "$USER" ]; then
      echo "Folder is not owned by $USER. Changing ownership."

      if ! echo "$password" | sudo -S chown "$USER":"$USER" "$folder_path"; then
        echo "Failed to change folder ownership."
        return 1
      fi
    else
      echo "Folder is already owned by $USER."
    fi

  else
    echo "Folder $folder_path does not exist."
    return 1
  fi

  return 0
}

check_folder_permissions() {
  local folder_path="/mnt/data/gdrive/avanzo-drive"
  local password
  password="$(getRootPassword)"
  
  if [ -d "$folder_path" ]; then
    local permissions
    permissions=$(stat -c "%a" "$folder_path")
    
    if [ "$permissions" != "777" ]; then
      echo "Folder does not have 777 permissions. Setting permissions to 777 for all files and subdirectories."
      if ! echo "$password" | sudo -S chmod -R 777 "$folder_path"; then
        echo "Failed to set permissions."
        return 1
      fi
    else
      echo "Folder already has 777 permissions."
    fi
  else
    echo "Folder $folder_path does not exist."
    return 1
  fi

  return 0
}

create_systemd_symlink() {
  local password
  password="$(getRootPassword)"

  if [ ! -L "/etc/systemd/system/rclone-mount.service" ]; then
    echo "Symbolic link does not exist. Creating symbolic link."
    if ! echo "$password" | sudo -S ln -sf "$RCLONE"/rclone-mount.service /etc/systemd/system/rclone-mount.service; then
      echo "Failed to create symbolic link."
      return 1
    fi
  else
    echo "Symbolic link already exists."
  fi

  return 0
}

verify_avanzo_drive_symlink() {
  local symlink_path="$HOME/avanzo-drive"

  if [ ! -L "$symlink_path" ]; then
    echo "Symbolic link does not exist. Creating symbolic link."
    if ! ln -sf /mnt/data/gdrive/avanzo-drive "$symlink_path"; then
      echo "Failed to create symbolic link."
      return 1
    fi
  else
    echo "Symbolic link already exists."
  fi

  return 0
}

manage_rclone_service() {
  local password
  password="$(getRootPassword)"

  # Reload the systemd manager configuration
  if ! echo "$password" | sudo -S systemctl daemon-reload; then
    echo "Failed to reload the systemd daemon."
    return 1
  fi

  # Enable the rclone service
  if ! echo "$password" | sudo -S systemctl enable rclone-mount.service; then
    echo "Failed to enable rclone-mount.service."
    return 1
  fi

  # Start the rclone service
  if ! echo "$password" | sudo -S systemctl start rclone-mount.service; then
    echo "Failed to start rclone-mount.service."
    return 1
  fi

  echo "rclone-mount.service successfully reloaded, enabled, and started."
  return 0
}

edit_rclone_service_file() {
  local -r service_file="$HOME/.Library/rclone/rclone-mount.service"
  local -r placeholder="<USER>"
  
  if [ -f "$service_file" ]; then
    if sed -i "s/User=$placeholder/User=$USER/" "$service_file"; then
      echo "Successfully replaced $placeholder with $USER in $service_file."
    else
      echo "Failed to edit the service file."
      return 1
    fi
  else
    echo "Service file $service_file does not exist."
    return 1
  fi

  return 0
}

edit_rclone_desktop_file() {
  local -r rclone_path="$HOME/.Library/rclone"
  local -r desktop_file="$rclone_path/rclone.desktop"
  local -r icon_path="$rclone_path/resource/rclone-icon.png"
  local -r placeholder="<RCLONE_ICON_PATH>"

  if [ -f "$desktop_file" ]; then
    if sed -i "s|Icon=$placeholder|Icon=$icon_path|" "$desktop_file"; then
      echo "Successfully replaced $placeholder with $icon_path in $desktop_file."
    else
      echo "Failed to edit the desktop file."
      return 1
    fi
  else
    echo "Desktop file $desktop_file does not exist."
    return 1
  fi

  return 0
}

is_rclone_mounted() {
    # Define the mount point
    local -r mount_point="/mnt/data/gdrive/avanzo-drive"
    local -r remote="remote:"

    mount | grep "$remote" | grep -q "$mount_point"
}

clean_mount_folder() {
    local -r mount_point="/mnt/data/gdrive/avanzo-drive"

    if ! is_rclone_mounted; then

        if [ "$(ls -A "$mount_point")" ]; then
            echo "$mount_point is not empty. Removing all content inside it."
            if ! echo "$password" | sudo -S rm -rf "$mount_point"/*; then
                echo "Failed to remove content inside $mount_point."
                return 1
            fi
          else
            echo "$mount_point is empty."
        fi
            
    fi
}

refresh_token_connection(){
  if ! rclone ls remote:/; then
    echo "Reconnect Rclone"
    reset_token
    rclone_reconnect
  fi
}
