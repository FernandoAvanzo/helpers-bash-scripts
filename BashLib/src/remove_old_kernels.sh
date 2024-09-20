#!/bin/bash
# Get current kernel
current_kernel=$(uname -r)

# Get installed kernels excluding current kernel
installed_kernels=$(dpkg --list | grep linux-image | awk '{print $2}' | grep -v "$current_kernel")

# Removing older kernels
for kernel in $installed_kernels; do
    echo "Removing $kernel"
    sudo apt-get remove --purge -y "$kernel"
done

# Clean up unused dependencies
sudo apt-get autoremove --purge -y

# Update GRUB
sudo update-grub

echo "Unused kernels removed and GRUB updated."