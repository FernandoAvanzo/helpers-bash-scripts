# Additive Technical Report — DKMS `system76_acpi` Repair Script v2

Date: 2026-08-28  
System context provided by user: Pop!_OS 24.04 LTS on Samsung 960XGL, kernel update target `7.1.5-76070105-generic`.

## 1. What went wrong after running v1

The first run of `pop_system76_acpi_dkms_repair.sh` was a dry run and made no changes. The second run used:

```bash
./pop_system76_acpi_dkms_repair.sh --apply --mode purge-dkms
```

The script correctly removed the real DKMS module version:

```text
system76_acpi/1.0.2~1784652717~24.04~add8f71
```

It restored the original in-tree `system76_acpi.ko.zst` modules for older kernels and then deleted that real DKMS version from the DKMS tree.

The failure happened immediately after that, when v1 tried to run:

```bash
dkms remove -m system76_acpi -v original_module --all
```

DKMS returned:

```text
Error! The module/version combo: system76_acpi/original_module is not located in the DKMS tree.
```

That command is invalid because `original_module` is not a DKMS module version. It is an internal DKMS storage area used to keep copies of kernel modules that existed before DKMS overrode them.

## 2. Root cause

There were two defects in v1.

### 2.1 DKMS discovery bug

v1 discovered candidate versions by listing every directory under:

```text
/var/lib/dkms/system76_acpi/
```

That list can include DKMS metadata/internal directories, especially:

```text
original_module
```

v1 treated `original_module` as if it were a real DKMS version, then passed it to `dkms remove -v`.

### 2.2 Non-fatal wrapper bug

v1 intended `dkms remove` cleanup failures to be non-fatal. However, the wrapper executed commands through a pipeline using `tee` while the script had strict Bash mode enabled:

```bash
set -Eeuo pipefail
```

With strict mode and `pipefail`, a non-zero command in a logging pipeline can still trigger the global `ERR` trap. That is why the error line showed:

```text
ERROR: command failed with exit code 3: tee -a "$LOG"
```

The true failing command was the invalid `dkms remove ... -v original_module --all`, but the trap reported the logging pipeline.

## 3. Current system state after the failed v1 run

The system is probably in a partially improved but incomplete state:

1. The real DKMS registration for `system76_acpi/1.0.2~1784652717~24.04~add8f71` was removed.
2. The original kernel modules were restored for the older kernels shown in your log.
3. The script stopped before purging the Debian package `system76-acpi-dkms`.
4. The original package-manager error can still return if `system76-acpi-dkms` remains installed and DKMS is invoked by `dpkg --configure -a` or a kernel post-install hook.

This is recoverable. The v2 script is idempotent and is designed to continue safely from this half-completed state.

## 4. What changed in v2

The new script is:

```text
pop_system76_acpi_dkms_repair_v2.sh
```

### 4.1 Filters DKMS internal directories

v2 ignores:

```text
original_module
source
build
collisions
kernel-*
hidden dot directories
```

It only treats a directory as a removable DKMS version if it looks like a real DKMS version directory, for example if it has a `source` link, `dkms.conf`, or a `build` directory.

### 4.2 Makes optional cleanup truly optional

v2 replaces the old `cmd | tee -a "$LOG"` pattern with a safer command runner:

1. run command into a temporary command log file;
2. capture the real command exit status;
3. append output to the main log;
4. print output to terminal;
5. only abort when the command is marked fatal.

This avoids the misleading `tee -a "$LOG"` failure report.

### 4.3 Handles half-completed v1 runs

If the real DKMS version was already removed, v2 logs:

```text
No valid system76_acpi DKMS version directories found. This is OK after a partial previous cleanup.
```

Then it continues to purge `system76-acpi-dkms` and repair package configuration.

### 4.4 Quarantines stale DKMS metadata

After the package is purged, if `/var/lib/dkms/system76_acpi` still exists but contains no valid DKMS versions, v2 moves it into the savepoint under:

```text
/var/backups/pop-dkms-repair-v2/<timestamp>/quarantine/system76_acpi
```

This keeps a recoverable copy while preventing stale DKMS metadata from interfering with future `dkms autoinstall` runs.

### 4.5 Keeps the original package-manager repair flow

v2 still follows the same repair sequence:

```bash
apt-get clean
apt-get update -m
dpkg --configure -a
apt-get -f install -y
dpkg --configure -a
apt-get full-upgrade -y
apt-get autoremove --purge -y
apt-get clean
```

The second `dpkg --configure -a` is intentional. It catches packages unpacked or fixed by `apt-get -f install`.

## 5. Recommended command sequence

Run dry-run first:

```bash
chmod +x ./pop_system76_acpi_dkms_repair_v2.sh
./pop_system76_acpi_dkms_repair_v2.sh
```

Apply the fix:

```bash
./pop_system76_acpi_dkms_repair_v2.sh --apply --mode purge-dkms
```

To skip Flatpak maintenance while focusing only on apt/dpkg/DKMS:

```bash
./pop_system76_acpi_dkms_repair_v2.sh --apply --mode purge-dkms --no-flatpak
```

## 6. Verification after v2

Run:

```bash
sudo dpkg --audit
dkms status
uname -r
modinfo system76_acpi | sed -n '1,120p'
apt-get -s full-upgrade
```

Expected results:

1. `sudo dpkg --audit` should return no output.
2. `dkms status` should no longer show `system76_acpi` as a DKMS-managed module in purge mode.
3. `modinfo system76_acpi` should still find the kernel-provided module if the running kernel provides it.
4. `apt-get -s full-upgrade` should not report the same five unconfigured kernel packages.

## 7. Rollback notes

Each v2 run creates a savepoint under:

```text
/var/backups/pop-dkms-repair-v2/<timestamp>/
```

The savepoint contains:

- package state;
- DKMS status;
- apt source listings;
- selected `/etc` and package-manager backups;
- command logs;
- `rollback.sh`.

The rollback helper is not a full filesystem snapshot. Prefer Timeshift, Btrfs/ZFS snapshots, or a full system backup for complete rollback. The helper is intended to restore selected saved files and attempt package-level recovery.

## 8. Why purge mode remains the recommended path

The original failure was caused by DKMS attempting to install a duplicate `system76_acpi` module where the kernel already had an in-tree module. Purge mode removes the DKMS copy and keeps the kernel-provided module, preventing future kernel post-install hooks from repeating the same DKMS collision.

Force mode remains available, but it is a fallback. It tells DKMS to overwrite the in-tree module, which is less conservative and usually unnecessary on a kernel that already ships `system76_acpi`.
