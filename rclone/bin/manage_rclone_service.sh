#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

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
  local symlink_path="/home/$USER/avanzo-drive"

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
  local service_file="$HOME/.Library/rclone/rclone-mount.service"
  local placeholder="<USER>"
  
  if [ -f "$service_file" ]; then
    sed -i "s/User=$placeholder/User=$USER/" "$service_file"
    if [ $? -eq 0 ]; then
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