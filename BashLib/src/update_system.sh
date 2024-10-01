#!/bin/bash

password="$(op item get Galaxy-Book_4-Ultra --format human-readable --fields password --reveal)"
echo "$password" | sudo -S apt update
echo "$password" | sudo -S apt upgrade
flatpak update -y