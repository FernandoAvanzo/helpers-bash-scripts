#!/usr/bin/env bash
# Intel IPU6 Health Check Script
# Validates IPU6 driver stack installation after ipu6_install.sh
# Compatible with Pop!_OS 22.04 and Galaxy Book4 Ultra
set -euo pipefail

# Configuration
SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/ipu6-health-check.log"
IPU_FW_DIR="/lib/firmware/intel/ipu"
STACK_DIR="/opt/ipu6"
HEALTH_CHECK_DIR="/tmp/ipu6-health-check-$(date +%Y%m%d-%H%M%S)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNINGS=0

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Output functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Intel IPU6 Health Check v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    local test_name="$1"
    echo -e "${BLUE}[TEST]${NC} $test_name"
    ((TESTS_TOTAL++))
}

print_pass() {
    local message="$1"
    echo -e "${GREEN}[PASS]${NC} $message"
    log "PASS: $message"
    ((TESTS_PASSED++))
}

print_fail() {
    local message="$1"
    echo -e "${RED}[FAIL]${NC} $message"
    log "FAIL: $message"
    ((TESTS_FAILED++))
}

print_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message"
    log "WARN: $message"
    ((TESTS_WARNINGS++))
}

print_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message"
    log "INFO: $message"
}

# Error handling
die() {
    log "CRITICAL ERROR: $*" >&2
    echo -e "${RED}CRITICAL ERROR: $*${NC}" >&2
    cleanup
    exit 1
}

cleanup() {
    if [[ -d "$HEALTH_CHECK_DIR" ]]; then
        rm -rf "$HEALTH_CHECK_DIR" 2>/dev/null || true
    fi
}

# Set up cleanup on exit
trap cleanup EXIT

# Check if running as root for privileged operations
check_privileges() {
    if [[ $EUID -ne 0 ]] && [[ "${1:-}" == "require_root" ]]; then
        die "This operation requires root privileges. Run with sudo."
    fi
}

# Hardware detection tests
test_hardware_detection() {
    print_test "IPU6 Hardware Detection"
    
    # Check PCI device presence
    if lspci -nn | grep -qi "intel.*image\|ipu"; then
        local pci_info
        pci_info=$(lspci -nn | grep -i "intel.*image\|ipu" | head -1)
        print_pass "IPU6 hardware detected: $pci_info"
    else
        print_fail "No IPU6 hardware found in PCI enumeration"
        return 1
    fi
    
    # Check for Meteor Lake specifically
    if lspci -nn | grep -qi "meteor.*lake\|0x7d19"; then
        print_pass "Meteor Lake IPU6E detected"
    else
        print_warn "Non-Meteor Lake IPU detected - compatibility may vary"
    fi
}

# Kernel module tests
test_kernel_modules() {
    print_test "Kernel Module Status"
    
    local modules=("intel_ipu6" "intel_ipu6_isys" "intel_ipu6_psys")
    local loaded_count=0
    
    for module in "${modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            print_pass "Module $module is loaded"
            ((loaded_count++))
        else
            print_fail "Module $module is not loaded"
        fi
    done
    
    if [[ $loaded_count -eq ${#modules[@]} ]]; then
        print_pass "All IPU6 kernel modules are loaded"
    else
        print_fail "$loaded_count/${#modules[@]} IPU6 modules loaded"
        return 1
    fi
}

# DKMS installation test
test_dkms_status() {
    print_test "DKMS Module Status"
    
    if command -v dkms >/dev/null 2>&1; then
        local dkms_status
        dkms_status=$(dkms status ipu6-drivers 2>/dev/null || echo "not found")
        
        if echo "$dkms_status" | grep -q "installed"; then
            print_pass "DKMS module ipu6-drivers is installed"
            print_info "DKMS Status: $dkms_status"
        else
            print_fail "DKMS module ipu6-drivers not properly installed"
            print_info "DKMS Status: $dkms_status"
            return 1
        fi
    else
        print_warn "DKMS not available - manual module loading required"
    fi
}

# Firmware tests
test_firmware() {
    print_test "Firmware Validation"
    
    # Check firmware directory
    if [[ ! -d "$IPU_FW_DIR" ]]; then
        print_fail "Firmware directory $IPU_FW_DIR does not exist"
        return 1
    fi
    
    # Check for required firmware files
    local fw_files=("ipu6epmtl_fw.bin" "ipu6ep_fw.bin" "ipu6_fw.bin")
    local found_fw=false
    
    for fw_file in "${fw_files[@]}"; do
        if [[ -f "$IPU_FW_DIR/$fw_file" ]]; then
            local fw_size
            fw_size=$(stat -c%s "$IPU_FW_DIR/$fw_file")
            print_pass "Firmware $fw_file found (${fw_size} bytes)"
            found_fw=true
        fi
    done
    
    if [[ "$found_fw" == "false" ]]; then
        print_fail "No IPU6 firmware files found in $IPU_FW_DIR"
        return 1
    fi
    
    # Check dmesg for firmware loading success
    if dmesg | grep -i "ipu6.*firmware" | grep -qi "loaded\|success"; then
        print_pass "Firmware loading successful (check dmesg)"
    else
        if dmesg | grep -i "ipu6.*firmware" | grep -qi "failed\|error"; then
            print_fail "Firmware loading failed (check dmesg)"
        else
            print_warn "No firmware loading messages found in dmesg"
        fi
    fi
}

# Video device tests
test_video_devices() {
    print_test "Video Device Detection"
    
    # Check for video devices
    if ls /dev/video* >/dev/null 2>&1; then
        local video_devices
        video_devices=$(ls /dev/video* 2>/dev/null || echo "")
        print_pass "Video devices found: $video_devices"
        
        # Check if video0 is available (primary camera)
        if [[ -c /dev/video0 ]]; then
            print_pass "Primary video device /dev/video0 available"
        else
            print_warn "Primary video device /dev/video0 not found"
        fi
    else
        print_fail "No video devices found in /dev/"
        return 1
    fi
}

# Media controller tests
test_media_controller() {
    print_test "Media Controller Interface"
    
    # Check if media-ctl is available
    if ! command -v media-ctl >/dev/null 2>&1; then
        print_warn "media-ctl not installed - install v4l-utils for detailed testing"
        return 0
    fi
    
    # Test media controller enumeration
    mkdir -p "$HEALTH_CHECK_DIR"
    local media_output="$HEALTH_CHECK_DIR/media-ctl-output.txt"
    
    if media-ctl -p > "$media_output" 2>&1; then
        if grep -qi "ipu" "$media_output"; then
            print_pass "Media controller shows IPU6 pipelines"
            local entity_count
            entity_count=$(grep -c "entity" "$media_output" 2>/dev/null || echo "0")
            print_info "Found $entity_count media entities"
        else
            print_fail "No IPU6 entities found in media controller"
            return 1
        fi
    else
        print_fail "Media controller enumeration failed"
        return 1
    fi
}

# Library tests
test_libraries() {
    print_test "IPU6 Libraries"
    
    local lib_paths=("/usr/lib" "/usr/local/lib")
    local lib_patterns=("libipu*" "libicamera*" "libgstcamerasrc*")
    local found_libs=0
    
    for lib_path in "${lib_paths[@]}"; do
        for pattern in "${lib_patterns[@]}"; do
            if find "$lib_path" -name "$pattern" 2>/dev/null | grep -q .; then
                local libs
                libs=$(find "$lib_path" -name "$pattern" 2>/dev/null | head -3)
                print_pass "Found libraries in $lib_path: $(echo "$libs" | tr '\n' ' ')"
                ((found_libs++))
                break
            fi
        done
    done
    
    if [[ $found_libs -gt 0 ]]; then
        print_pass "IPU6 libraries are installed"
    else
        print_fail "No IPU6 libraries found"
        return 1
    fi
    
    # Check library cache
    if ldconfig -p | grep -qi "ipu\|icamera"; then
        print_pass "IPU6 libraries are in linker cache"
    else
        print_warn "IPU6 libraries may not be in linker cache - run ldconfig"
    fi
}

# GStreamer plugin tests
test_gstreamer_plugin() {
    print_test "GStreamer icamerasrc Plugin"
    
    if ! command -v gst-inspect-1.0 >/dev/null 2>&1; then
        print_warn "gst-inspect-1.0 not available - install gstreamer1.0-tools"
        return 0
    fi
    
    if gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
        print_pass "icamerasrc plugin is available"
        
        # Get plugin version/info
        local plugin_info
        plugin_info=$(gst-inspect-1.0 icamerasrc 2>/dev/null | grep -E "Version|Description" | head -2)
        if [[ -n "$plugin_info" ]]; then
            print_info "Plugin details: $(echo "$plugin_info" | tr '\n' '; ')"
        fi
    else
        print_fail "icamerasrc plugin not found"
        return 1
    fi
}

# Basic functionality test
test_camera_functionality() {
    print_test "Camera Basic Functionality"
    
    if ! command -v gst-launch-1.0 >/dev/null 2>&1; then
        print_warn "gst-launch-1.0 not available - install gstreamer1.0-tools for functionality test"
        return 0
    fi
    
    print_info "Testing camera pipeline (5-second timeout)..."
    
    # Test basic pipeline without display
    local test_output="$HEALTH_CHECK_DIR/camera-test.log"
    
    if timeout 5s gst-launch-1.0 icamerasrc num-buffers=10 ! fakesink > "$test_output" 2>&1; then
        print_pass "Camera pipeline test successful"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            # Timeout - this might be OK if the pipeline started
            if grep -qi "playing" "$test_output" 2>/dev/null; then
                print_pass "Camera pipeline started successfully (timeout expected)"
            else
                print_fail "Camera pipeline failed to start"
                return 1
            fi
        else
            print_fail "Camera pipeline test failed (exit code: $exit_code)"
            if [[ -f "$test_output" ]]; then
                print_info "Error details: $(tail -2 "$test_output" | tr '\n' '; ')"
            fi
            return 1
        fi
    fi
}

# Permission tests
test_permissions() {
    print_test "Device Permissions"
    
    local current_user
    current_user=$(whoami)
    
    # Check video group membership
    if groups "$current_user" | grep -q "video"; then
        print_pass "User $current_user is in video group"
    else
        print_warn "User $current_user is not in video group - may need: sudo usermod -a -G video $current_user"
    fi
    
    # Check device permissions
    if [[ -c /dev/video0 ]]; then
        local perms
        perms=$(ls -l /dev/video0 | cut -d' ' -f1)
        if [[ "$perms" =~ rw.*rw ]]; then
            print_pass "Video device permissions look correct: $perms"
        else
            print_warn "Video device permissions may be restrictive: $perms"
        fi
    fi
}

# System information collection
collect_system_info() {
    print_test "System Information Collection"
    
    local info_file="$HEALTH_CHECK_DIR/system-info.txt"
    
    {
        echo "IPU6 Health Check System Information"
        echo "Generated: $(date)"
        echo "=========================================="
        echo
        echo "Kernel version:"
        uname -a
        echo
        echo "OS information:"
        cat /etc/os-release 2>/dev/null || echo "Not available"
        echo
        echo "PCI devices:"
        lspci -nn | grep -i "intel.*image\|ipu" || echo "No IPU devices found"
        echo
        echo "Video devices:"
        ls -la /dev/video* 2>/dev/null || echo "No video devices"
        echo
        echo "IPU6 kernel modules:"
        lsmod | grep -i ipu || echo "No IPU modules loaded"
        echo
        echo "DKMS status:"
        dkms status ipu6-drivers 2>/dev/null || echo "DKMS not available or no modules"
        echo
        echo "Firmware files:"
        find /lib/firmware -name "*ipu*" -type f 2>/dev/null || echo "No IPU firmware found"
        echo
        echo "Recent dmesg (IPU related):"
        dmesg | grep -i ipu | tail -10 || echo "No IPU messages in dmesg"
    } > "$info_file"
    
    print_pass "System information collected in $info_file"
}

# Generate summary report
generate_summary() {
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Health Check Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    echo -e "${YELLOW}Warnings: ${TESTS_WARNINGS}${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ IPU6 installation appears to be working correctly!${NC}"
        echo "You can test the camera with:"
        echo "  gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink"
    elif [[ $TESTS_FAILED -lt 3 ]]; then
        echo -e "${YELLOW}⚠ IPU6 installation has minor issues but may still work${NC}"
        echo "Review the failed tests above and consider re-running ipu6_install.sh"
    else
        echo -e "${RED}✗ IPU6 installation has significant issues${NC}"
        echo "Consider running ipu6_rollback.sh and reinstalling"
    fi
    
    echo
    echo "Log file: $LOG_FILE"
    echo "Test artifacts: $HEALTH_CHECK_DIR"
}

# Main execution
main() {
    print_header
    log "Starting IPU6 health check v${SCRIPT_VERSION}"
    
    # Create working directory
    mkdir -p "$HEALTH_CHECK_DIR"
    
    # Run all tests
    test_hardware_detection || true
    test_kernel_modules || true
    test_dkms_status || true
    test_firmware || true
    test_video_devices || true
    test_media_controller || true
    test_libraries || true
    test_gstreamer_plugin || true
    test_permissions || true
    test_camera_functionality || true
    collect_system_info || true
    
    # Generate summary
    generate_summary
    
    # Return appropriate exit code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    elif [[ $TESTS_FAILED -lt 3 ]]; then
        exit 1
    else
        exit 2
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
