#!/bin/bash
# cheese-fix-uninstall.sh — Remove the Cheese CameraBin crash fix
#
# Removes the LD_PRELOAD library, wrapper script, and .desktop override
# installed by cheese-fix.sh. The original Cheese binary is not affected.

set -e

echo "=============================================="
echo "  Cheese CameraBin Fix — Uninstaller"
echo "=============================================="
echo ""

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Don't run this as root. The script will use sudo where needed."
    exit 1
fi

echo "Removing Cheese CameraBin fix..."

sudo rm -f /usr/local/lib/cheese-camerabin-fix.so
echo "  ✓ Removed /usr/local/lib/cheese-camerabin-fix.so"

sudo rm -f /usr/local/bin/cheese
echo "  ✓ Removed /usr/local/bin/cheese (wrapper)"

for f in /usr/local/share/applications/*heese*.desktop /usr/local/share/applications/*cheese*.desktop; do
    if [[ -f "$f" ]]; then
        sudo rm -f "$f"
        echo "  ✓ Removed $f"
    fi
done

echo ""
echo "=============================================="
echo "  Cheese fix removed."
echo ""
echo "  Cheese will now use its default settings (which may crash"
echo "  with the IPU6/IPU7 camera). To reinstall: ./cheese-fix.sh"
echo "=============================================="
