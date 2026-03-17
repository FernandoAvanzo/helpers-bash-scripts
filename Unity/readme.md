# Unity on Pop!_OS / Ubuntu-like Linux

This folder contains Bash installers for setting up Unity on Linux. The current recommended script is [`install_unity_popos_lts_v3.sh`](/home/fernandoavanzo/Projects/helpers-bash-scripts/Unity/install_unity_popos_lts_v3.sh).

## What `install_unity_popos_lts_v3.sh` does

This script automates a safer Unity installation flow for Pop!_OS and Ubuntu-like systems by combining Unity Hub installation with headless Unity Hub editor installation.

By default it:

- installs or refreshes Unity Hub only when needed
- installs the latest Unity 6 LTS release visible in branch `6000.3`
- installs the latest Unity 2022 LTS release visible in branch `2022.3`
- installs these modules for each editor:
  - `android`
  - `android-sdk-ndk-tools`
  - `android-open-jdk`
  - `webgl`
  - `linux-il2cpp`
- creates launcher wrappers in `~/.local/bin`:
  - `unity6-lts`
  - `unity2022-lts`

The main safety change versus the older variants is that if a working `unityhub` binary already exists, the script skips `apt` by default. That avoids touching unrelated packages on systems where the package resolver is already in a bad state. Use `--refresh-hub` if you explicitly want the Unity repository reconfigured and `unityhub` reinstalled or upgraded.

## Why this script exists

Unity Hub is the primary supported way to install Unity editors and modules, but Linux support is narrower than many Ubuntu-based distributions suggest.

As of 2026-03-17:

- Unity's Hub manual lists `Ubuntu 24.04` for Hub support on Linux.
- Unity 6 editor system requirements list `Ubuntu 22.04` and `Ubuntu 24.04`, with GNOME on X11 or Wayland as the supported desktop environment baseline.
- Unity Support says Ubuntu is the only officially supported Linux distro for Hub support.
- Unity Support specifically calls out Pop!_OS as unsupported and notes that Hub login issues can occur there.
- Unity's Hub command-line interface is documented as experimental.

That means this script is best understood as:

- a practical automation layer for Pop!_OS and Ubuntu-like systems
- aligned with Unity's official Linux repository flow
- best-effort on Pop!_OS, COSMIC, and other non-Ubuntu environments

## Requirements

- `sudo` or root access
- an `amd64` / `x86_64` machine
- a Pop!_OS, Ubuntu, or other Debian/Ubuntu-like system
- internet access for Unity Hub, editor metadata, and package downloads
- a normal desktop user account that should own the Hub config and editor installs
- a working user session is strongly recommended if Hub needs to talk to the desktop session bus

The script uses `SUDO_USER` by default as the target user. If that is not the correct account, pass `--user USERNAME`.

## What it installs

### Unity Hub

If Unity Hub is not already present, or if you pass `--refresh-hub`, the script uses Unity's official Debian/Ubuntu repository flow:

1. install minimal repo tools: `ca-certificates`, `curl`, `gnupg`
2. create `/etc/apt/keyrings`
3. install Unity's public signing key into `/etc/apt/keyrings/unityhub.gpg`
4. create `/etc/apt/sources.list.d/unityhub.list`
5. run `apt-get update`
6. install `unityhub`

### Unity editors

The script installs editors through the Unity Hub CLI, not by downloading editor tarballs directly.

Default editor branches:

- Unity 6 LTS: `6000.3`
- Unity 2022 LTS: `2022.3`

Resolution behavior:

- If you do not pass an exact version, the script queries `unityhub --headless editors -r` and picks the newest visible version in the requested branch.
- If you pass an exact version and Hub can see it, the script installs that version.
- If you pass an exact version that is not currently visible, you must also pass the matching changeset.

### Default modules

The default module list is:

| Module ID | Meaning |
| --- | --- |
| `android` | Android Build Support |
| `android-sdk-ndk-tools` | Android SDK & NDK Tools |
| `android-open-jdk` | OpenJDK |
| `webgl` | Web Build Support |
| `linux-il2cpp` | Linux Build Support (IL2CPP) |

These are the module IDs the script passes to the Hub CLI by default. They cover the common Android toolchain pieces plus WebGL and Linux IL2CPP support.

## Install path and wrappers

By default, editors are installed under:

```bash
$HOME/Unity/Hub/Editor
```

You can override that with `--editor-path`.

After installation, the script creates wrapper launchers in:

```bash
$HOME/.local/bin
```

Each wrapper:

- searches for the installed editor binary under the expected Hub layout
- raises the file descriptor limit with `ulimit -n 4096 || true`
- launches the editor executable directly

That `ulimit` bump is intentional. Unity's Linux documentation notes that `Pipe error !` issues can require `ulimit -n 4096` before launching the editor.

## Usage

Show help:

```bash
sudo ./install_unity_popos_lts_v3.sh --help
```

List versions currently visible to the Unity Hub CLI:

```bash
sudo ./install_unity_popos_lts_v3.sh --list-releases
```

Install the default setup:

```bash
sudo ./install_unity_popos_lts_v3.sh
```

Refresh Unity Hub through the official repository, then continue:

```bash
sudo ./install_unity_popos_lts_v3.sh --refresh-hub
```

Install Hub only:

```bash
sudo ./install_unity_popos_lts_v3.sh --hub-only
```

Install only Unity 6 LTS:

```bash
sudo ./install_unity_popos_lts_v3.sh --no-2022
```

Install exact editor versions:

```bash
sudo ./install_unity_popos_lts_v3.sh \
  --unity6-version 6000.3.10f1 \
  --unity6-changeset e35f0c77bd8e
```

Install for a specific user and custom editor path:

```bash
sudo ./install_unity_popos_lts_v3.sh \
  --user fernandoavanzo \
  --editor-path /home/fernandoavanzo/Unity/Hub/Editor
```

Use a custom module set:

```bash
sudo ./install_unity_popos_lts_v3.sh \
  --modules android,android-sdk-ndk-tools,android-open-jdk,webgl
```

## Command-line options

| Option | Purpose |
| --- | --- |
| `--hub-only` | Install or refresh Unity Hub only |
| `--list-releases` | Print versions visible to the Hub CLI and exit |
| `--refresh-hub` | Force Unity repo setup and `unityhub` installation even if Hub is already present |
| `--no-unity6` | Skip Unity 6 installation |
| `--no-2022` | Skip Unity 2022 installation |
| `--unity6-branch BRANCH` | Choose a Unity 6 branch, default `6000.3` |
| `--unity2022-branch BRANCH` | Choose a Unity 2022 branch, default `2022.3` |
| `--unity6-version VERSION` | Install an exact Unity 6 version |
| `--unity2022-version VERSION` | Install an exact Unity 2022 version |
| `--unity6-changeset CHANGESET` | Changeset used when an exact Unity 6 version is not visible in Hub |
| `--unity2022-changeset CHANGESET` | Same as above for Unity 2022 |
| `--modules CSV` | Comma-separated Hub module IDs |
| `--editor-path PATH` | Override the editor install root |
| `--user USERNAME` | Override the target desktop user |
| `--interactive-apt` | Do not force `DEBIAN_FRONTEND=noninteractive` |

## How the script works internally

High-level flow:

1. require root
2. resolve the target user, home directory, UID, group, runtime directory, and DBus session bus if available
3. verify OS family and enforce `amd64`
4. prepare the target user's local config and install directories
5. detect whether Unity Hub already exists
6. if needed, configure Unity's apt repository and install `unityhub`
7. detect which Linux Hub CLI syntax works on the installed Hub:
   - `unityhub --headless ...`
   - `unityhub -- --headless ...`
8. query releases with `editors -r`
9. resolve requested branches or exact versions
10. set the editor install path in Hub
11. install editors and modules through the Hub CLI
12. create launch wrappers and print post-install notes

## Post-install steps

After a successful run:

1. log in as the target user
2. start Unity Hub once
3. sign in with your Unity account
4. ensure `~/.local/bin` is in `PATH`
5. launch `unity6-lts` or `unity2022-lts`

Example:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
source ~/.profile
unity6-lts
```

## Troubleshooting

### Hub is installed, but the script still fails

Check whether the Hub CLI responds for the target user:

```bash
sudo -u <username> -H unityhub --headless help
```

If that fails, your Hub build may require the alternate Linux invocation style:

```bash
sudo -u <username> -H unityhub -- --headless help
```

The script auto-detects this, but testing it manually is useful when debugging.

### `--list-releases` returns nothing

Possible causes:

- Hub is not fully installed
- network access is blocked
- the target user has not initialized Hub correctly
- Hub is failing in the current desktop/session environment

Check logs in:

```bash
~/.config/UnityHub/logs
```

### Pop!_OS or COSMIC login issues

This is the main non-script risk area. The installer can complete successfully while Hub login still fails later, because Unity does not officially support Pop!_OS.

If Hub sign-in or startup is unstable:

- update Hub with `--refresh-hub`
- confirm you installed from Unity's repository, not a distro app store build
- check `~/.config/UnityHub/logs`
- test on Ubuntu if you need the most predictable supported setup

### Exact version not visible in Hub

Run:

```bash
sudo ./install_unity_popos_lts_v3.sh --list-releases
```

Then either:

- choose a version currently listed for the branch you want
- or provide both `--unity*-version` and the matching `--unity*-changeset`

## Sources

Official Unity references used for this documentation:

- Unity Hub Linux installation: https://docs.unity3d.com/hub/manual/install-hub-linux.html
- Unity Hub command-line reference: https://docs.unity3d.com/hub/manual/HubCLI.html
- Unity 6 Linux system requirements: https://docs.unity3d.com/6000.0/Documentation/Manual/system-requirements.html
- Unity Android dependency setup: https://docs.unity3d.com/6000.1/Documentation/Manual/android-install-dependencies.html
- Unity Support article on unsupported Linux distros, including Pop!_OS: https://support.unity.com/hc/en-us/articles/37407180230932-Unable-to-log-in-via-The-Hub-on-unsupported-Linux-distros-Steam-OS-Zorin-OS-Pop-OS-Arch-Linux
