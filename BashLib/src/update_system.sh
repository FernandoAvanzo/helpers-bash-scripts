#!/bin/bash

password="fer010486"
echo $password | sudo -S apt update
echo $password | sudo -S apt upgrade
flatpak update -y