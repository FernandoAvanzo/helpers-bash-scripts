# Technical Report — Pop!_OS kernel update failure: `system76_acpi` DKMS conflict

## Executive summary

The update failure is caused by a DKMS post-install hook during configuration of the new Pop!_OS kernel packages. The package manager is trying to finish installing/configuring `linux-headers-7.1.5-76070105-generic` and `linux-image-7.1.5-76070105-generic`, but DKMS aborts while installing the `system76_acpi` module because the new kernel already contains a `system76_acpi.ko.zst` module.

This leaves five packages unconfigured:

- `linux-headers-7.1.5-76070105-generic`
- `linux-image-7.1.5-76070105-generic`
- `linux-headers-generic`
- `linux-generic`
- `linux-system76`

The running system shown in the screenshot is Pop!_OS 24.04 LTS on Samsung hardware model `960XGL`, currently booted on kernel `7.0.11-76070011-generic`. The failed packages are for the newer kernel `7.1.5-76070105-generic`.

## Evidence from the provided log

Primary failure:

```text
Autoinstall of module system76_acpi/1.0.2~1784652717~24.04~add8f71 for kernel 7.1.5-76070105-generic (x86_64)
Module /lib/modules/7.1.5-76070105-generic/kernel/drivers/platform/x86/system76_acpi.ko.zst already installed (unversioned module), override by specifying --force
Error! Installation aborted.
```

Then DKMS reports that other modules succeeded, while only `system76_acpi` failed:

```text
Autoinstall on 7.1.5-76070105-generic succeeded for module(s) ipu-bridge-fix max98390-hda nvidia ov02c10 system76 system76-io v4l2loopback.
Autoinstall on 7.1.5-76070105-generic failed for module(s) system76_acpi(6).
```

That DKMS error makes both kernel post-install hooks fail:

```text
run-parts: /etc/kernel/header_postinst.d/dkms exited with return code 1
run-parts: /etc/kernel/postinst.d/dkms exited with return code 1
```

The dependency chain then breaks:

```text
linux-headers-generic depends on linux-headers-7.1.5-76070105-generic
linux-generic depends on linux-headers-generic
linux-system76 depends on linux-generic
```

## Root cause

DKMS refuses to replace an already-present unversioned module named `system76_acpi` in the target kernel tree. The new kernel already has:

```text
/lib/modules/7.1.5-76070105-generic/kernel/drivers/platform/x86/system76_acpi.ko.zst
```

but the installed `system76-acpi-dkms` package is also trying to install a DKMS-built module with the same module name. The external DKMS package therefore conflicts with the in-tree module for this kernel.

The System76 `system76-acpi-dkms` repository describes the package as providing the `system76_acpi` in-tree driver for systems that are missing it. For a kernel that already contains the module, keeping the in-kernel module and removing the duplicate DKMS package is generally safer than forcing DKMS to overwrite it, especially on this Samsung non-System76 laptop.

## Impact

- APT/dpkg is stuck with partially configured kernel packages.
- Future package installs/upgrades may fail until `dpkg --configure -a` completes.
- The old running kernel is still booted, so the machine is not necessarily broken now, but the new kernel may not be cleanly installed.
- Repeating the current update script repeats the same DKMS failure.

## Custom script review

Current script:

```bash
password="$(getRootPassword)"
echo "$password" | sudo -S apt update -y
echo "$password" | sudo -S apt upgrade -y --allow-downgrades
echo "$password" | sudo -S apt upgrade -y
echo "$password" | sudo -S apt autoremove -y
echo "$password" | sudo -S apt clean -y
flatpak update -y
```

Issues:

1. It stores and pipes the sudo password. Prefer `sudo -v` once or run the script through sudo.
2. It runs `apt upgrade` twice.
3. `--allow-downgrades` is unsafe as a default update behavior.
4. It does not repair interrupted dpkg state before attempting upgrades.
5. It does not create logs/savepoints.
6. It does not check DKMS state or kernel post-install failures.
7. It runs Flatpak maintenance after a failed APT run without explicitly reporting the APT failure as fatal.

## Recommended fix path

Recommended mode for this laptop:

```bash
sudo apt-get update -m
sudo dkms status
sudo apt-get -s purge system76-acpi-dkms
```

If the simulation does **not** remove critical Pop/kernel/NVIDIA packages:

```bash
sudo dkms remove -m system76_acpi -v 1.0.2~1784652717~24.04~add8f71 --all
sudo apt-get purge -y system76-acpi-dkms
sudo dpkg --configure -a
sudo apt-get -f install -y
sudo apt-get full-upgrade -y
sudo apt-get autoremove --purge -y
sudo apt-get clean
sudo reboot
```

Fallback if purge would remove critical packages, or if you intentionally want the DKMS module to override the in-tree module:

```bash
sudo dkms install -m system76_acpi -v 1.0.2~1784652717~24.04~add8f71 -k 7.1.5-76070105-generic --force
sudo dpkg --configure -a
sudo apt-get -f install -y
sudo apt-get full-upgrade -y
sudo reboot
```

## Verification after reboot

```bash
uname -r
dpkg --audit
dkms status
apt list --upgradable
lsmod | grep -E '^system76_acpi|^system76'
modinfo system76_acpi | sed -n '1,80p'
```

Expected:

- `dpkg --audit` prints nothing.
- `uname -r` shows the new kernel if booted successfully.
- `dkms status` has no failed `system76_acpi` entry.
- `apt list --upgradable` is either empty or only shows unrelated packages.

## Flatpak warning

The log also shows an end-of-life Flatpak runtime warning for KDE Platform/SDK 6.8, used by `io.github.congard.qnvsm`. This is unrelated to the kernel/DKMS failure. After the APT repair, update or replace that Flatpak application/runtime:

```bash
flatpak update
flatpak uninstall --unused
flatpak info io.github.congard.qnvsm
```

## References

- System76 Package Manager Issues for Pop!_OS: recommends repair flow including `apt clean`, `apt update -m`, `dpkg --configure -a`, `apt install -f`, `apt full-upgrade`, and `apt autoremove --purge`.
- System76 application management documentation: recommends terminal updates with `apt update`, `apt full-upgrade`, `apt autoremove --purge`, and warns about third-party repositories.
- Ubuntu DKMS man page: documents that `dkms install --force` is used when a module is already installed, and describes DKMS original module handling.
- Pop!_OS ISO configuration: includes `linux-system76` and installs `system76-acpi-dkms` on amd64 images.
- System76 `system76-acpi-dkms` repository: describes the package as providing the `system76_acpi` in-tree driver for systems missing it.
