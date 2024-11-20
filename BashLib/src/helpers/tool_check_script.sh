#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./root-password.sh
source "$HELPERS"/root-password.sh

sudo_password="$(getRootPassword)"

function check_and_install_tools() {
    # Check if gh is installed, if not install it
    if ! command -v gh &> /dev/null
    then
        echo "gh could not be found, attempting to install."

        # Installing Homebrew first if not installed already
        if ! command -v brew &> /dev/null
        then
            echo "Homebrew is not installed. To install it, your user password is needed:"
            echo "$sudo_password" | sudo -S /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi

        # Installing gh
        echo "Installing gh..."
        brew install gh
    else
        # If gh was previously installed, check for upgrades
        echo "Gh found. Checking for upgrades..."
        brew upgrade gh
    fi
}

function install_or_upgrade_babashka() {
  # check if `bb` command (babashka) exists
  if command -v bb &> /dev/null
  then
    echo "Babashka is installed, updated to the latest version..."
  else
    echo "Babashka is not installed, installed..."
  fi
  # Download and run a Babashka install script
  bash <(curl -s https://raw.githubusercontent.com/babashka/babashka/master/install)
  # Verify the installation
  bb --version
}


function check_and_install_expect() {
    # Check if expect is installed, if not install it
    if ! command -v expect &> /dev/null
    then
        echo "expect could not be found, attempting to install."
        
        # Update the package list and install expect
	      echo "$sudo_password" | sudo -S apt install -y --fix-broken
        echo "$sudo_password" | sudo -S apt update
	      echo "$sudo_password" | sudo -S apt install -y tcl-expect
        echo "$sudo_password" | sudo -S apt install -y expect
        echo "$sudo_password" | sudo -S apt install -y tk8.6

    else
        echo "expect is already installed."
    fi
}
