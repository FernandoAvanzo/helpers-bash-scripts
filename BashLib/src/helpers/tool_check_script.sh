#!/bin/bash

function check_and_install_tools() {
    # Check if gh is installed, if not install it
    if ! command -v gh &> /dev/null
    then
        echo "gh could not be found, attempting to install."

        # Installing Homebrew first if not installed already
        if ! command -v brew &> /dev/null
        then
            echo "Homebrew is not installed. To install it, your user password is needed:"
            sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
