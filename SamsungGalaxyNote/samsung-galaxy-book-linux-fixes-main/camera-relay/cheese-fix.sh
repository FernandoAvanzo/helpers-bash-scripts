#!/bin/bash
# cheese-fix.sh — Standalone installer for the Cheese CameraBin crash fix
#
# Cheese (GNOME webcam app) crashes with SIGSEGV in CameraBin's videoconvert
# due to a buffer use-after-free, and also fails with EBUSY when CameraBin
# creates two pipewiresrc instances for the same single-client camera.
#
# This fix uses LD_PRELOAD to:
#   1. Replace CameraBin's videoconvert with a two-stage NV12 copy (fixes crash)
#   2. Replace pipewiresrc with v4l2src on the camera relay loopback (fixes EBUSY)
#
# Prerequisites: camera-relay must be installed and running for Cheese to work.
#
# Usage: ./cheese-fix.sh         # Install
#        ./cheese-fix-uninstall.sh  # Uninstall

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  Cheese CameraBin Crash Fix"
echo "=============================================="
echo ""

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Don't run this as root. The script will use sudo where needed."
    exit 1
fi

# Check prerequisites
if ! command -v gcc >/dev/null 2>&1; then
    echo "ERROR: gcc is required to compile the fix."
    echo "  Ubuntu: sudo apt install gcc"
    echo "  Fedora: sudo dnf install gcc"
    echo "  Arch:   sudo pacman -S gcc"
    exit 1
fi

if ! command -v cheese >/dev/null 2>&1; then
    echo "WARNING: Cheese does not appear to be installed."
    echo "  The fix will be installed anyway, but you'll need Cheese to use it."
    echo ""
fi

# Build the LD_PRELOAD shared library
echo "[1/3] Building cheese-camerabin-fix.so..."
CHEESE_FIX_SRC="$SCRIPT_DIR/cheese-camerabin-fix.c"
if [[ ! -f "$CHEESE_FIX_SRC" ]]; then
    echo "ERROR: cheese-camerabin-fix.c not found in $SCRIPT_DIR"
    exit 1
fi

if gcc -shared -fPIC -o /tmp/cheese-camerabin-fix.so "$CHEESE_FIX_SRC" -ldl; then
    sudo cp /tmp/cheese-camerabin-fix.so /usr/local/lib/cheese-camerabin-fix.so
    sudo chmod 644 /usr/local/lib/cheese-camerabin-fix.so
    rm -f /tmp/cheese-camerabin-fix.so
    echo "  ✓ Installed /usr/local/lib/cheese-camerabin-fix.so"
else
    echo "ERROR: Failed to compile cheese-camerabin-fix.so"
    exit 1
fi

# Install wrapper script
echo ""
echo "[2/3] Installing wrapper script..."
sudo tee /usr/local/bin/cheese > /dev/null << 'CHEESE_WRAPPER'
#!/bin/sh
# Pre-start camera relay so v4l2loopback has frames, then launch Cheese
# with LD_PRELOAD fix (swaps pipewiresrc→v4l2src + videoconvert buffer fix)
camera-relay start 2>/dev/null &
sleep 3
LD_PRELOAD=/usr/local/lib/cheese-camerabin-fix.so /usr/bin/cheese "$@"
CHEESE_WRAPPER
sudo chmod 755 /usr/local/bin/cheese
echo "  ✓ Installed /usr/local/bin/cheese (wrapper)"

# Install .desktop override
echo ""
echo "[3/3] Installing .desktop override..."
CHEESE_DESKTOP=$(find /usr/share/applications -name "*heese*.desktop" -o -name "*cheese*.desktop" 2>/dev/null | head -1)
if [[ -n "$CHEESE_DESKTOP" ]]; then
    sudo mkdir -p /usr/local/share/applications
    sed -e 's|^Exec=.*|Exec=/usr/local/bin/cheese|' \
        -e 's|^DBusActivatable=true|DBusActivatable=false|' "$CHEESE_DESKTOP" | \
        sudo tee /usr/local/share/applications/$(basename "$CHEESE_DESKTOP") > /dev/null
    echo "  ✓ Installed .desktop override"
else
    sudo mkdir -p /usr/local/share/applications
    sudo tee /usr/local/share/applications/org.gnome.Cheese.desktop > /dev/null << 'CHEESE_DESKTOP_EOF'
[Desktop Entry]
Name=Cheese
Comment=Take photos and videos with your webcam, with fun graphical effects
Exec=/usr/local/bin/cheese
Icon=org.gnome.Cheese
Terminal=false
Type=Application
Categories=GNOME;AudioVideo;Video;
StartupNotify=true
CHEESE_DESKTOP_EOF
    echo "  ✓ Installed .desktop file"
fi

echo ""
echo "=============================================="
echo "  Cheese fix installed!"
echo "=============================================="
echo ""
echo "  Cheese should now work when launched from the app menu or terminal."
echo "  The camera relay will auto-start when Cheese opens."
echo ""
echo "  Prerequisites:"
echo "    - camera-relay must be installed (included in webcam-fix-libcamera"
echo "      and webcam-fix-book5 installers)"
echo ""
echo "  To uninstall: ./cheese-fix-uninstall.sh"
echo "=============================================="
