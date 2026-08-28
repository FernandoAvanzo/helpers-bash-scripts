# Technical report — system76_acpi DKMS repair

Date: 2026-08-28

## Result

The repair script was corrected for the supplied apply log:

- APT simulation now detects purge cascades containing Purg, not only Remv.
- apt-get autoremove --purge is no longer automatic; it requires --autoremove.
- Optional command failures no longer trigger the global Bash ERR trap.
- Flatpak repair uses supported syntax and is isolated from APT/DKMS repair.

The modified script is pop_system76_acpi_dkms_repair.sh.

## Incident and root cause

The target kernel already contains:

    /lib/modules/7.1.5-76070105-generic/kernel/drivers/platform/x86/system76_acpi.ko.zst

The installed system76-acpi-dkms package independently tries to install a DKMS module with the same name. DKMS refuses to replace the unversioned in-tree module unless forced, so kernel post-install hooks fail and leave kernel packages unconfigured.

The v2 logic correctly chose purge mode and stopped treating DKMS's original_module directory as a version. The apply log exposed three further defects.

### APT guard defect

The simulation contained Purg system76-driver-nvidia and Purg system76-driver. The guard matched only ^Remv, so the dependency cascade passed. The new guard matches both Remv and Purg and stops unless --allow-critical-removal is explicitly supplied.

### Uncontrolled autoremove

After the driver metapackages were purged, APT marked 33 packages unused. Unconditional autoremove removed about 710 MB, including NVIDIA and System76 firmware/display packages. This was not required for the DKMS repair. It is now opt-in with --autoremove.

### Flatpak and ERR trap defect

The log ended at flatpak repair --user -y. flatpak repair has no -y option. Bash ERR traps can also run when errexit is temporarily disabled, so the old optional wrapper could still abort the script.

run_optional now temporarily disables and restores the ERR trap. The command is now flatpak repair --user; failure is logged but does not invalidate successful APT/DKMS repair.

## Changes made

- Critical removal detection changed from only ^Remv to ^(Remv|Purg).
- Added --autoremove, default off, to prevent unrelated package deletion.
- Hardened run_optional so expected DKMS/Flatpak failures remain non-fatal.
- Removed unsupported -y from flatpak repair.
- Updated usage/header references to the actual script filename.

## Correct execution procedure

### 1. Dry-run

    chmod +x ./pop_system76_acpi_dkms_repair.sh
    sudo ./pop_system76_acpi_dkms_repair.sh --mode purge-dkms --no-flatpak

Review the savepoint. If simulation reports removal of linux-*, pop-desktop, NVIDIA, or System76 driver packages, do not use --allow-critical-removal without reviewing the cause.

### 2. Apply focused repair

    sudo ./pop_system76_acpi_dkms_repair.sh --apply --mode purge-dkms --no-flatpak

This removes the duplicate DKMS package, keeps the kernel in-tree module, quarantines only stale DKMS metadata, and repairs interrupted package configuration.

### 3. Verify

    sudo dpkg --audit
    dkms status
    uname -r
    modinfo system76_acpi | sed -n '1,120p'
    apt-get -s full-upgrade

Expected: no dpkg --audit output, no failed system76_acpi DKMS entry, and no recurrence of the five unconfigured kernel packages.

### 4. Run Flatpak separately

    flatpak repair --user
    flatpak update -y
    flatpak uninstall --unused -y

## Consequence of the prior apply run

The prior run already removed NVIDIA and related orphan packages. The corrected script prevents another cascade but cannot infer which removed packages should be restored. Inspect first:

    apt-mark showmanual
    dpkg -l | grep -E 'nvidia|system76-(firmware|oled|wallpapers)|firmware-manager'

Restore only packages required by the machine using the appropriate Pop!_OS/NVIDIA package set.

## Validation

The modified script passes bash -n and help output includes --autoremove. A privileged full dry run could not be executed in this non-interactive workspace because sudo requires the operator's password and a terminal. Run the dry-run command above on the affected machine before applying.

