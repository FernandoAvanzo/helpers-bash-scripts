#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"

source "$HELPERS"/root-password.sh

password="$(getRootPassword)"

install_linux_dependencies(){
  echo "$password" | sudo -S apt install -y libglib2.0-0
  echo "$password" | sudo -S apt install -y net-tools
  echo "$password" | sudo -S apt install -y dbus
  echo "$password" | sudo -S apt install -y libqt5core5a
  echo "$password" | sudo -S apt install -y libqt5webengine5
  echo "$password" | sudo -S apt install -y libqt5webenginewidgets5
  echo "$password" | sudo -S apt install -y libqt5sql5
  echo "$password" | sudo -S apt install -y libqt5webkit5
  echo "$password" | sudo -S apt install -y libdbus-glib-1-2
  echo "$password" | sudo -S apt install -y libnss3-tools
  echo "$password" | sudo -S apt install -y libnss-resolve
  echo "$password" | sudo -S apt install -y libpcap0.8
  echo "$password" | sudo -S apt install -y curl
  echo "$password" | sudo -S apt install -y jq
  echo "$password" | sudo -S apt install -y systemd-coredump
}
