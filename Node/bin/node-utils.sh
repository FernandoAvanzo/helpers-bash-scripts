#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS/root-password.sh"
# shellcheck source=./../../BashLib/src/helpers/shell-utils.sh
source "$HELPERS/shell-utils.sh"

password="$(getRootPassword)"

# shellcheck disable=SC1091
purge_all_node_installations() {
    echo "Purging all Node.js installations..."
    echo "$password" |  sudo -S apt remove --purge -y nodejs npm
    if [ -d "$HOME/.nvm" ]; then
          # shellcheck source=./nvm.sh
        . "$HOME/.nvm/nvm.sh"
        nvm deactivate
        nvm uninstall node
        rm -rf "$NVM_DIR"
    fi

    echo "$password" |  sudo -S rm -rf /usr/local/{lib/node{,/.npm,_modules},bin,share/man}/npm*
    echo "$password" |  sudo -S rm -rf /usr/local/bin/node
    
    echo "Node.js installations purged successfully."
}

install_node_dependencies(){
  update_system
  echo "$password" |  sudo -S apt install build-essential -y
  echo "$password" |  sudo -S apt install git -y
  echo "$password" |  sudo -S apt install curl  -y
  echo "$password" |  sudo -S apt install python2.7 -y
  echo "$password" |  sudo -S apt install python-pip -y
  echo "$password" |  sudo -S apt install libusb-1.0-0 -y
  echo "$password" |  sudo -S apt install libusb-1.0-0-dev -y
}

# shellcheck disable=SC1091,SC1090
install_node_8-2-1(){
    local nvm_install_url
    local shellrc
    local nvm_path_install
    shellrc=".$(extract_user_shell)rc"
    nvm_install_url="https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh"
    nvm_path_install="$HOME/.nvm"
    curl -o- $nvm_install_url | bash && source "$HOME"/"$shellrc"
    chmod -R a+x "$nvm_path_install"/versions/node/v8.2.1/bin/
    echo "$password" |  sudo -S sudo cp -r "$nvm_path_install"/versions/node/v8.2.1/{bin,lib,share} /usr/local
    npm install -g bower
}
