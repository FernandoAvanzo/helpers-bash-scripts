# Pop!_OS NVIDIA driver mismatch: diagnosis and repair guide

**System reported:** Pop!_OS 24.04 LTS, x86-64, kernel `7.1.5-76070105-generic`, Samsung 960XGL, NVIDIA GeForce RTX 4050 (reported in earlier context).  
**Observed on:** 2026-10-14, based on the pasted logs.  
**Primary symptom:** `nvidia-smi` fails with `Failed to initialize NVML: Driver/library version mismatch`.

## Diagnosis

The NVIDIA user-space components and the kernel module are from different driver builds:

| Component | Version in the logs |
|---|---:|
| `nvidia-settings` / `nvidia-smi` client and NVML library | `595.104.02` / `595.104` |
| Loaded NVIDIA kernel module | `595.99.02` |

The NVIDIA driver has kernel-side and user-space components that must match. A package update may have replaced the libraries on disk while the older module remained loaded in memory. This commonly happens when the system has not rebooted since a driver update, or when a partial/failed package update left mixed versions. Since the mismatch is still reported repeatedly, rebooting is the simplest first test; if it remains after reboot, repair packages through Pop!_OS's APT repositories.

The other messages are secondary:

- **ACPI `FAN0._FST` / `AE_AML_OPERAND_TYPE`:** firmware/ACPI fan-status evaluation failed. The log shows an ACPI method error and the fan driver cannot retrieve a status value. This is separate from NVML. Check real fan operation and temperatures; firmware updates may improve ACPI behavior, but do not edit ACPI tables or disable thermal protections as a driver fix.
- **`kauditd_printk_skb` callbacks suppressed:** audit messages were rate-limited; not evidence of an NVIDIA fault.
- **Bluetooth keyboard HID, XFRM, AppArmor profile load:** ordinary subsystem initialization in this excerpt.
- **Wireless extensions warning and `/proc/cgroups` note:** compatibility/informational messages, unrelated to NVIDIA version alignment.

## Recommended recovery sequence

### 1. Save work and reboot once

If an NVIDIA driver update was recently installed, reboot first:

```bash
sudo reboot
```

After logging in, check:

```bash
nvidia-smi
cat /proc/driver/nvidia/version
modinfo -F version nvidia
```

If `nvidia-smi` reports a working GPU and versions align, no package repair is needed.

### 2. Collect state if the mismatch remains

```bash
uname -r
cat /etc/os-release
nvidia-smi
cat /proc/driver/nvidia/version 2>&1
modinfo -F version nvidia 2>&1
dpkg -l | grep -E 'nvidia|system76-driver'
apt policy system76-driver-nvidia nvidia-driver-595
mokutil --sb-state 2>/dev/null || true
```

The package version may include Pop!_OS-specific suffixes. Compare the driver branch/version from APT with the module version; do not assume `595` is the right branch indefinitely. The current logs establish that the loaded `595.99.02` and installed libraries `595.104.02` disagree.

### 3. Bring packages into a consistent state

Use the Pop!_OS repository-managed driver packages. First inspect and simulate the package changes:

```bash
sudo dpkg --configure -a
sudo apt --fix-broken install
sudo apt update
sudo apt -s full-upgrade
```

Review the simulation. If it proposes removing desktop, kernel, or NVIDIA driver packages unexpectedly, stop and investigate the APT sources/pinning before proceeding. Otherwise run:

```bash
sudo apt full-upgrade
sudo apt install --reinstall system76-driver-nvidia
```

The full upgrade can update packages beyond NVIDIA, so review APT's proposed changes. Do not mix the NVIDIA `.run` installer with Pop!_OS packages, and do not add an Ubuntu PPA or manually force a driver version as the first fix.

### 4. Reboot to load the installed module

```bash
sudo reboot
```

Then verify:

```bash
nvidia-smi
cat /proc/driver/nvidia/version
modinfo -F version nvidia
```

A successful `nvidia-smi` should show the RTX 4050 and a driver version consistent with the loaded module. If it still fails, collect the diagnostic output from step 2 along with:

```bash
journalctl -k -b | grep -Ei 'NVRM|nvidia|nouveau|secure boot|module'
dpkg --audit
apt-mark showhold
```

At that point, check Secure Boot/module signing, held packages, repository priorities, DKMS/build errors, and whether the running kernel has a matching NVIDIA module. Do not purge all NVIDIA packages blindly; that can remove the working graphical stack.

## Optional repair script

Save the companion `repair-nvidia-driver.sh` file and run it from a terminal. By default, it only diagnoses the system. To allow package changes, pass `--repair`; the script shows an APT simulation and asks before applying changes. It never reboots automatically.

```bash
chmod +x repair-nvidia-driver.sh
./repair-nvidia-driver.sh
./repair-nvidia-driver.sh --repair
```

Run it from a normal desktop session with a working network connection. The script uses APT's configured Pop!_OS repositories and the `system76-driver-nvidia` metapackage. Read the proposed APT transaction before confirming.

## Sources

- System76, [Install the System76 Driver](https://support.system76.com/articles/system76-driver/): Pop!_OS repository-managed driver packages and NVIDIA support.
- System76, [Graphics Switching](https://support.system76.com/articles/graphics-switch-pop/): Pop!_OS graphics modes and NVIDIA GPU usage.
- System76, [Package Manager Issues](https://support.system76.com/articles/package-manager-pop/): troubleshooting APT/package-manager state.
- NVIDIA, [Frequently Asked Questions — NVIDIA Driver Installation Guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/frequently-asked-questions.html): version mismatch and module rebuild/update considerations.
- NVIDIA, [Pre-installation Actions](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/pre-installation-actions.html): kernel headers and driver module build prerequisites.
- Pop!_OS, [24.04 ISO package configuration](https://github.com/pop-os/iso/blob/master/config/pop-os/24.04.mk): NVIDIA driver package integration in Pop!_OS 24.04. Exact repository package versions can change over time; use `apt policy` on the workstation.

## Evidence limits

This report is based on the log and `hostnamectl` text in the request. The attached images and PDFs were not available to inspect, so they did not inform the diagnosis.
