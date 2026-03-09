### Script v42 logs errors

```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v42.sh
[sudo] password for fernandoavanzo: 
[2025-09-29 08:22:46] Kernel: 6.16.3-76061603-generic
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
v4l2loopback-dkms is already the newest version (0.15.1-1pop1~1756123534~22.04~a34615c).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[2025-09-29 08:22:48] Host v4l2loopback ready at /dev/video42
[2025-09-29 08:22:48] Noble rootfs already exists, reusing.
[2025-09-29 08:22:48] Configuring apt sources inside container…
Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease                                                      
Hit:2 http://security.ubuntu.com/ubuntu noble-security InRelease                                            
Hit:3 http://archive.ubuntu.com/ubuntu noble-updates InRelease                                          
Hit:4 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble InRelease
Hit:5 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy InRelease
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ca-certificates is already the newest version (20240203).
curl is already the newest version (8.5.0-2ubuntu10.6).
gnupg is already the newest version (2.4.4-2ubuntu17.3).
0 upgraded, 0 newly installed, 0 to remove and 129 not upgraded.
gpg: directory '/root/.gnupg' created
gpg: keybox '/root/.gnupg/pubring.kbx' created
gpg: /root/.gnupg/trustdb.gpg: trustdb created
gpg: key A630CA96910990FF: public key "Launchpad PPA for OEM Solutions Group" imported
gpg: Total number processed: 1
gpg:               imported: 1
gpg: key B52B913A41086767: public key "Launchpad Private PPA for OEM Solutions Group" imported
gpg: Total number processed: 1
gpg:               imported: 1
install: cannot create regular file '/var/lib/machines/ipu6-noble/etc/apt/keyrings/ipu6-ppa.gpg': No such file or directory
```

### Script v45 logs errors

```bash
➜ SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v45.sh [sudo] password for fernandoavanzo: [2025-09-29 13:19:08] Host preflight checks… [2025-09-29 13:19:08] OK: IPU6 video/media nodes exist. [2025-09-29 13:19:08] OK: cgroup v2 present. [2025-09-29 13:19:15] Host v4l2loopback ready at /dev/video42 [2025-09-29 13:19:15] Noble rootfs already exists, reusing. [2025-09-29 13:19:15] Configuring apt sources inside container… Failed to create /dev/console symlink: File exists Failed to set up /dev/console: File exists Child died too early.
```

### Script v46 logs errors



### Script v47 logs errors



### Script v48 logs errors


### Script v49 logs errors


### Script v50 logs errors



### Script v51 logs errors



### Prompts commands

```markdown
My system have the config bellow:
```bash
➜  ~ cat /etc/os-release | grep PRETTY
PRETTY_NAME="Pop!_OS 22.04 LTS"
➜  ~ hostnamectl
Static hostname: pop-os
Icon name: computer-laptop
Chassis: laptop
Machine ID: 8328871196c857387d7234d366b2592f
Boot ID: 446d44ee5ad042ccaac7639f6e3f1a1b
Operating System: Pop!_OS 22.04 LTS               
Kernel: Linux 6.16.3-76061603-generic
Architecture: x86-64
Hardware Vendor: SAMSUNG ELECTRONICS CO., LTD.
Hardware Model: 960XGL
➜  ~
and currentlly after run the command dmsg i get the error bellow:
text
[    9.846091] intel-ipu6 0000:00:05.0: error -ENOENT: Requesting signed firmware intel/ipu/ipu6epmtl_fw.bin failed
[    9.846097] intel-ipu6 0000:00:05.0: probe with driver intel-ipu6 failed with error -2
```
and the web can of my system does not work, are like if the driver was not installed. EXplain if the boths things are related and use the web search to find simmilar cases. Also suggested a fix and generate a bash script that automatize the suggested solution. Also use the Knowledge base to get additional context
the
The firmware side of the problem are alaready fix in the versions 7, 16, and 41. And the `dmsg` command logs bellow show it evidence.
```bash
[    9.799655] intel-ipu6 0000:00:05.0: enabling device (0000 -> 0002)
[    9.801324] intel_vpu 0000:00:0b.0: enabling device (0000 -> 0002)
[    9.803549] intel_pmc_core INT33A1:00: Assuming a default substate order for this platform
[    9.803667] intel_pmc_core INT33A1:00:  initialized
[    9.827247] intel_vpu 0000:00:0b.0: [drm] Firmware: intel/vpu/vpu_37xx_v1.bin, version: 20250115*MTL_CLIENT_SILICON-release*1905*ci_tag_ud202504_vpu_rc_20250115_1905*ae83b65d01c
[    9.827256] intel_vpu 0000:00:0b.0: [drm] Scheduler mode: HW
[    9.833021] intel-ipu6 0000:00:05.0: Found supported sensor OVTI02C1:00
[    9.833099] intel-ipu6 0000:00:05.0: Connected 1 cameras
[    9.835981] intel-ipu6 0000:00:05.0: Sending BOOT_LOAD to CSE
[    9.843202] RAPL PMU: API unit is 2^-32 Joules, 3 fixed counters, 655360 ms ovfl timer
[    9.843206] RAPL PMU: hw unit of domain pp0-core 2^-14 Joules
[    9.843207] RAPL PMU: hw unit of domain package 2^-14 Joules
[    9.843207] RAPL PMU: hw unit of domain pp1-gpu 2^-14 Joules
[    9.844298] spi-nor spi0.0: supply vcc not found, using dummy regulator
[    9.845187] ACPI: battery: new hook: Samsung Galaxy Book Battery Extension
[    9.863285] input: Samsung Galaxy Book Camera Lens Cover as /devices/platform/SAM0430:00/input/input26
```


Im a previous chat are be generate 51 versions of the script and the and each one falied in some steps and  I am atach the last 6 versions and logs to we keep going for that point.
and the webcam still not work and the version 46, 47, 48, 49, 50, 51, 52  of the script attached also fail. The systemd-container is the right way, but are happens some issues in the configurations of the container. Bellow are the logs of the current version:

Version 46
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v46.sh
[sudo] password for fernandoavanzo: 
Host preflight checks…
[2025-09-29 13:37:30] OK: cgroup v2 present.
[2025-09-29 13:37:30] OK: IPU6 video/media nodes exist.
[2025-09-29 13:37:30] Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…
[WARN] v4l2loopback loaded but could not detect node (continuing).
[2025-09-29 13:37:36] Noble rootfs already exists, reusing.
Configuring apt sources inside container…
Running apt-get update inside container…
[2025-09-29 13:37:49] [FATAL] apt update failed inside container
```

Version 47
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v47.sh
[sudo] password for fernandoavanzo: 
./ipu6_install_v47.sh: 3: set: Illegal option -o pipefail
```

Version 48
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v48.sh
Samsung Galaxy Book4 Ultra IPU6 Webcam Fix v48
[2025-09-29 14:11:06] Real user: fernandoavanzo (UID: 1000)
[2025-09-29 14:11:06] Kernel: 6.16.3-76061603-generic
Checking host prerequisites...
[2025-09-29 14:11:07] [WARN] IPU6 device not detected in lspci output
[2025-09-29 14:11:07] Continuing anyway - device might be present but not visible
[2025-09-29 14:11:07] Installing host dependencies...
[2025-09-29 14:11:24] cgroup v2 detected
[2025-09-29 14:11:24] Noble container exists, reusing
Configuring container software repositories...
[2025-09-29 14:11:24] Installing base packages in container...
[2025-09-29 14:11:24] [FATAL] Base package installation failed

```

Version 49
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v49.sh
Preflight (host)…
[2025-09-29 14:25:12] Rootfs exists, verifying apt health…
Priming apt inside container…
[2025-09-29 14:25:12] [WARN] apt update failed; repairing base and trying again…
E: Conflicting values set for option Signed-By regarding source https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu/ jammy: /etc/apt/trusted.gpg.d/ipu6-ppa.gpg != /etc/apt/keyrings/ipu6-ppa-private.gpg
E: The list of sources could not be read.
E: Conflicting values set for option Signed-By regarding source https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu/ jammy: /etc/apt/trusted.gpg.d/ipu6-ppa.gpg != /etc/apt/keyrings/ipu6-ppa-private.gpg
E: The list of sources could not be read.
[2025-09-29 14:25:12] [WARN] Recreating rootfs due to persistent apt failure
Bootstrapping Noble rootfs…
Installing base tools (ca-certificates, gnupg)…
[2025-09-29 14:31:51] [FATAL] base install failed
```

Version 50
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v50.sh                   
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ca-certificates is already the newest version (20240203~22.04.1).
curl is already the newest version (7.81.0-1ubuntu1.21).
debootstrap is already the newest version (1.0.126+nmu1ubuntu0.8).
gpg is already the newest version (2.2.27-3ubuntu2.4).
systemd-container is already the newest version (249.11-0ubuntu3.16pop0~1749652895~22.04~34f0ce1).
v4l2loopback-dkms is already the newest version (0.15.1-1pop1~1756123534~22.04~a34615c).
gstreamer1.0-tools is already the newest version (1.24.13-0ubuntu1~22.04.sav0).
v4l-utils is already the newest version (1.26.1-2~22.04.sav0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[2025-10-02 13:51:52] [WARN]  No video/media/v4l-subdev nodes found. Kernel IPU6/sensors may not be up. Continuing.
[2025-10-02 13:51:52] Noble rootfs already exists, reusing.
[2025-10-02 13:51:52] Configuring apt sources & keyrings inside container…
+ set -e
+ apt-get update -y
Ign:1 http://archive.ubuntu.com/ubuntu noble InRelease
Ign:1 http://archive.ubuntu.com/ubuntu noble InRelease
Ign:1 http://archive.ubuntu.com/ubuntu noble InRelease
Err:1 http://archive.ubuntu.com/ubuntu noble InRelease
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Reading package lists... Done
W: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/noble/InRelease  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
W: Some index files failed to download. They have been ignored, or old ones used instead.
+ apt-get install -y --no-install-recommends ca-certificates gnupg curl
Reading package lists... Done
Building dependency tree... Done
ca-certificates is already the newest version (20240203).
The following additional packages will be installed:
  dirmngr gnupg-utils gpg gpg-agent gpgconf gpgsm keyboxd libbrotli1 libcurl4t64 libksba8 libldap2 libnghttp2-14 libpsl5t64 librtmp1 libsasl2-2
  libsasl2-modules-db libssh-4 pinentry-curses
Suggested packages:
  pinentry-gnome3 tor parcimonie xloadimage gpg-wks-server scdaemon pinentry-doc
Recommended packages:
  gnupg-l10n gpg-wks-client libldap-common publicsuffix libsasl2-modules
The following NEW packages will be installed:
  curl dirmngr gnupg gnupg-utils gpg gpg-agent gpgconf gpgsm keyboxd libbrotli1 libcurl4t64 libksba8 libldap2 libnghttp2-14 libpsl5t64 librtmp1
  libsasl2-2 libsasl2-modules-db libssh-4 pinentry-curses
0 upgraded, 20 newly installed, 0 to remove and 0 not upgraded.
Need to get 3695 kB of archives.
After this operation, 8983 kB of additional disk space will be used.
Ign:1 http://archive.ubuntu.com/ubuntu noble/main amd64 libnghttp2-14 amd64 1.59.0-1build4
Ign:2 http://archive.ubuntu.com/ubuntu noble/main amd64 libpsl5t64 amd64 0.21.2-1.1build1
Ign:3 http://archive.ubuntu.com/ubuntu noble/main amd64 libbrotli1 amd64 1.1.0-2build2
Ign:4 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-modules-db amd64 2.1.28+dfsg1-5ubuntu3
Ign:5 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-2 amd64 2.1.28+dfsg1-5ubuntu3
Ign:6 http://archive.ubuntu.com/ubuntu noble/main amd64 libldap2 amd64 2.6.7+dfsg-1~exp1ubuntu8
Ign:7 http://archive.ubuntu.com/ubuntu noble/main amd64 librtmp1 amd64 2.4+20151223.gitfa8646d.1-2build7
Ign:8 http://archive.ubuntu.com/ubuntu noble/main amd64 libssh-4 amd64 0.10.6-2build2
Ign:9 http://archive.ubuntu.com/ubuntu noble/main amd64 libcurl4t64 amd64 8.5.0-2ubuntu10
Ign:10 http://archive.ubuntu.com/ubuntu noble/main amd64 curl amd64 8.5.0-2ubuntu10
Ign:11 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgconf amd64 2.4.4-2ubuntu17
Ign:12 http://archive.ubuntu.com/ubuntu noble/main amd64 libksba8 amd64 1.6.6-1build1
Ign:13 http://archive.ubuntu.com/ubuntu noble/main amd64 dirmngr amd64 2.4.4-2ubuntu17
Ign:14 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg-utils amd64 2.4.4-2ubuntu17
Ign:15 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg amd64 2.4.4-2ubuntu17
Ign:16 http://archive.ubuntu.com/ubuntu noble/main amd64 pinentry-curses amd64 1.2.1-3ubuntu5
Ign:17 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg-agent amd64 2.4.4-2ubuntu17
Ign:18 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgsm amd64 2.4.4-2ubuntu17
Ign:19 http://archive.ubuntu.com/ubuntu noble/main amd64 keyboxd amd64 2.4.4-2ubuntu17
Ign:20 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg all 2.4.4-2ubuntu17
Ign:1 http://archive.ubuntu.com/ubuntu noble/main amd64 libnghttp2-14 amd64 1.59.0-1build4
Ign:2 http://archive.ubuntu.com/ubuntu noble/main amd64 libpsl5t64 amd64 0.21.2-1.1build1
Ign:3 http://archive.ubuntu.com/ubuntu noble/main amd64 libbrotli1 amd64 1.1.0-2build2
Ign:4 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-modules-db amd64 2.1.28+dfsg1-5ubuntu3
Ign:5 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-2 amd64 2.1.28+dfsg1-5ubuntu3
Ign:6 http://archive.ubuntu.com/ubuntu noble/main amd64 libldap2 amd64 2.6.7+dfsg-1~exp1ubuntu8
Ign:7 http://archive.ubuntu.com/ubuntu noble/main amd64 librtmp1 amd64 2.4+20151223.gitfa8646d.1-2build7
Ign:8 http://archive.ubuntu.com/ubuntu noble/main amd64 libssh-4 amd64 0.10.6-2build2
Ign:9 http://archive.ubuntu.com/ubuntu noble/main amd64 libcurl4t64 amd64 8.5.0-2ubuntu10
Ign:10 http://archive.ubuntu.com/ubuntu noble/main amd64 curl amd64 8.5.0-2ubuntu10
Ign:11 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgconf amd64 2.4.4-2ubuntu17
Ign:12 http://archive.ubuntu.com/ubuntu noble/main amd64 libksba8 amd64 1.6.6-1build1
Ign:13 http://archive.ubuntu.com/ubuntu noble/main amd64 dirmngr amd64 2.4.4-2ubuntu17
Ign:14 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg-utils amd64 2.4.4-2ubuntu17
Ign:15 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg amd64 2.4.4-2ubuntu17
Ign:16 http://archive.ubuntu.com/ubuntu noble/main amd64 pinentry-curses amd64 1.2.1-3ubuntu5
Ign:17 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg-agent amd64 2.4.4-2ubuntu17
Ign:18 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgsm amd64 2.4.4-2ubuntu17
Ign:19 http://archive.ubuntu.com/ubuntu noble/main amd64 keyboxd amd64 2.4.4-2ubuntu17
Ign:20 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg all 2.4.4-2ubuntu17
Ign:1 http://archive.ubuntu.com/ubuntu noble/main amd64 libnghttp2-14 amd64 1.59.0-1build4
Ign:2 http://archive.ubuntu.com/ubuntu noble/main amd64 libpsl5t64 amd64 0.21.2-1.1build1
Ign:3 http://archive.ubuntu.com/ubuntu noble/main amd64 libbrotli1 amd64 1.1.0-2build2
Ign:4 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-modules-db amd64 2.1.28+dfsg1-5ubuntu3
Ign:5 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-2 amd64 2.1.28+dfsg1-5ubuntu3
Ign:6 http://archive.ubuntu.com/ubuntu noble/main amd64 libldap2 amd64 2.6.7+dfsg-1~exp1ubuntu8
Ign:7 http://archive.ubuntu.com/ubuntu noble/main amd64 librtmp1 amd64 2.4+20151223.gitfa8646d.1-2build7
Ign:8 http://archive.ubuntu.com/ubuntu noble/main amd64 libssh-4 amd64 0.10.6-2build2
Ign:9 http://archive.ubuntu.com/ubuntu noble/main amd64 libcurl4t64 amd64 8.5.0-2ubuntu10
Ign:10 http://archive.ubuntu.com/ubuntu noble/main amd64 curl amd64 8.5.0-2ubuntu10
Ign:11 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgconf amd64 2.4.4-2ubuntu17
Ign:12 http://archive.ubuntu.com/ubuntu noble/main amd64 libksba8 amd64 1.6.6-1build1
Ign:13 http://archive.ubuntu.com/ubuntu noble/main amd64 dirmngr amd64 2.4.4-2ubuntu17
Ign:14 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg-utils amd64 2.4.4-2ubuntu17
Ign:15 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg amd64 2.4.4-2ubuntu17
Ign:16 http://archive.ubuntu.com/ubuntu noble/main amd64 pinentry-curses amd64 1.2.1-3ubuntu5
Ign:17 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg-agent amd64 2.4.4-2ubuntu17
Ign:18 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgsm amd64 2.4.4-2ubuntu17
Ign:19 http://archive.ubuntu.com/ubuntu noble/main amd64 keyboxd amd64 2.4.4-2ubuntu17
Ign:20 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg all 2.4.4-2ubuntu17
Err:1 http://archive.ubuntu.com/ubuntu noble/main amd64 libnghttp2-14 amd64 1.59.0-1build4
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:2 http://archive.ubuntu.com/ubuntu noble/main amd64 libpsl5t64 amd64 0.21.2-1.1build1
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:3 http://archive.ubuntu.com/ubuntu noble/main amd64 libbrotli1 amd64 1.1.0-2build2
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:4 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-modules-db amd64 2.1.28+dfsg1-5ubuntu3
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:5 http://archive.ubuntu.com/ubuntu noble/main amd64 libsasl2-2 amd64 2.1.28+dfsg1-5ubuntu3
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:6 http://archive.ubuntu.com/ubuntu noble/main amd64 libldap2 amd64 2.6.7+dfsg-1~exp1ubuntu8
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:7 http://archive.ubuntu.com/ubuntu noble/main amd64 librtmp1 amd64 2.4+20151223.gitfa8646d.1-2build7
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:8 http://archive.ubuntu.com/ubuntu noble/main amd64 libssh-4 amd64 0.10.6-2build2
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:9 http://archive.ubuntu.com/ubuntu noble/main amd64 libcurl4t64 amd64 8.5.0-2ubuntu10
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:10 http://archive.ubuntu.com/ubuntu noble/main amd64 curl amd64 8.5.0-2ubuntu10
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:11 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgconf amd64 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:12 http://archive.ubuntu.com/ubuntu noble/main amd64 libksba8 amd64 1.6.6-1build1
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:13 http://archive.ubuntu.com/ubuntu noble/main amd64 dirmngr amd64 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:14 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg-utils amd64 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:15 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg amd64 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:16 http://archive.ubuntu.com/ubuntu noble/main amd64 pinentry-curses amd64 1.2.1-3ubuntu5
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:17 http://archive.ubuntu.com/ubuntu noble/main amd64 gpg-agent amd64 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:18 http://archive.ubuntu.com/ubuntu noble/main amd64 gpgsm amd64 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:19 http://archive.ubuntu.com/ubuntu noble/main amd64 keyboxd amd64 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
Err:20 http://archive.ubuntu.com/ubuntu noble/main amd64 gnupg all 2.4.4-2ubuntu17
  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/n/nghttp2/libnghttp2-14_1.59.0-1build4_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/libp/libpsl/libpsl5t64_0.21.2-1.1build1_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/b/brotli/libbrotli1_1.1.0-2build2_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/c/cyrus-sasl2/libsasl2-modules-db_2.1.28%2bdfsg1-5ubuntu3_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/c/cyrus-sasl2/libsasl2-2_2.1.28%2bdfsg1-5ubuntu3_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/o/openldap/libldap2_2.6.7%2bdfsg-1%7eexp1ubuntu8_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/r/rtmpdump/librtmp1_2.4%2b20151223.gitfa8646d.1-2build7_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/libs/libssh/libssh-4_0.10.6-2build2_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/c/curl/libcurl4t64_8.5.0-2ubuntu10_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/c/curl/curl_8.5.0-2ubuntu10_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gpgconf_2.4.4-2ubuntu17_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/libk/libksba/libksba8_1.6.6-1build1_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/dirmngr_2.4.4-2ubuntu17_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gnupg-utils_2.4.4-2ubuntu17_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gpg_2.4.4-2ubuntu17_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/p/pinentry/pinentry-curses_1.2.1-3ubuntu5_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gpg-agent_2.4.4-2ubuntu17_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gpgsm_2.4.4-2ubuntu17_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/keyboxd_2.4.4-2ubuntu17_amd64.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gnupg_2.4.4-2ubuntu17_all.deb  System error resolving 'archive.ubuntu.com:http' - getaddrinfo (16: Device or resource busy)
E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
```

Version 51
```bash
[2025-10-02 14:05:27] Ensuring host packages are present…
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ca-certificates is already the newest version (20240203~22.04.1).
curl is already the newest version (7.81.0-1ubuntu1.21).
debootstrap is already the newest version (1.0.126+nmu1ubuntu0.8).
gpg is already the newest version (2.2.27-3ubuntu2.4).
systemd-container is already the newest version (249.11-0ubuntu3.16pop0~1749652895~22.04~34f0ce1).
v4l2loopback-dkms is already the newest version (0.15.1-1pop1~1756123534~22.04~a34615c).
gstreamer1.0-tools is already the newest version (1.24.13-0ubuntu1~22.04.sav0).
v4l-utils is already the newest version (1.26.1-2~22.04.sav0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[2025-10-02 14:05:36] OK: cgroup v2 present.
[2025-10-02 14:05:36] Host v4l2loopback ready at /dev/video42
[2025-10-02 14:05:36] Noble rootfs already exists, reusing.
[2025-10-02 14:05:36] Configuring apt sources & keyring inside container…
Failed to mount /etc/resolv.conf (type n/a) on /var/lib/machines/ipu6-noble/run/systemd/resolve/stub-resolv.conf (MS_BIND ""): No such file or directory
Failed to create /dev/console symlink: File exists
Failed to set up /dev/console: File exists
Child died too early.
```
 Version 52
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v52.sh    
[sudo] password for fernandoavanzo: 
[2025-10-02 15:06:01] Host preflight…
[2025-10-02 15:06:07] Rootfs exists, reusing: /var/lib/machines/ipu6-noble
[2025-10-02 15:06:07] Configuring Intel IPU6 PPA (edge/dev; keep other packages from official archive)…
curl: (22) The requested URL returned error: 404
gpg: no valid OpenPGP data found
```

Version 53
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v53.sh
[2025-10-02 15:21:10] Host preflight…
Get:1 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Hit:2 https://dl.google.com/linux/chrome/deb stable InRelease                                                                                                                                                                       
Hit:3 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease                                                                                                                                                                                                                        
Get:4 https://download.docker.com/linux/ubuntu jammy InRelease [48.8 kB]                                                                                                                                                                                                                   
Hit:5 http://archive.ubuntu.com/ubuntu jammy-updates InRelease                                                                                                                                                                                        
Hit:6 https://downloads.1password.com/linux/debian/amd64 stable InRelease                                                                                               
Hit:7 http://apt.pop-os.org/proprietary jammy InRelease                                                                                           
Ign:8 https://apt.fury.io/notion-repackaged  InRelease              
Hit:9 http://apt.pop-os.org/release jammy InRelease                 
Ign:10 https://apt.fury.io/notion-repackaged  Release               
Hit:11 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy InRelease
Ign:12 https://apt.fury.io/notion-repackaged  Packages
Hit:13 http://apt.pop-os.org/ubuntu jammy InRelease
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US     
Hit:15 https://ppa.launchpadcontent.net/ubuntu-toolchain-r/test/ubuntu jammy InRelease
Hit:16 http://apt.pop-os.org/ubuntu jammy-security InRelease        
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Get:12 https://apt.fury.io/notion-repackaged  Packages [1,572 B]
Hit:18 http://apt.pop-os.org/ubuntu jammy-updates InRelease           
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Hit:19 http://apt.pop-os.org/ubuntu jammy-backports InRelease
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Fetched 54.0 kB in 4s (13.4 kB/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ca-certificates is already the newest version (20240203~22.04.1).
curl is already the newest version (7.81.0-1ubuntu1.21).
debootstrap is already the newest version (1.0.126+nmu1ubuntu0.8).
gpg is already the newest version (2.2.27-3ubuntu2.4).
systemd-container is already the newest version (249.11-0ubuntu3.16pop0~1749652895~22.04~34f0ce1).
v4l2loopback-dkms is already the newest version (0.15.1-1pop1~1756123534~22.04~a34615c).
gstreamer1.0-tools is already the newest version (1.24.13-0ubuntu1~22.04.sav0).
v4l-utils is already the newest version (1.26.1-2~22.04.sav0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[2025-10-02 15:21:15] Rootfs exists, reusing: /var/lib/machines/ipu6-noble
[2025-10-02 15:21:15] Configuring Intel IPU6 userspace PPA in container (Noble only)…
[2025-10-02 15:21:16] Updating APT metadata inside container…
Failed to create /dev/console symlink: File exists
Failed to set up /dev/console: File exists
Child died too early
```

logs version 54
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v54.sh
[2025-10-02 15:43:45] Host preflight…
Get:1 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Get:2 https://download.docker.com/linux/ubuntu jammy InRelease [48.8 kB]                                                                                                                                                                                                                                                 
Hit:3 https://dl.google.com/linux/chrome/deb stable InRelease                                                                                                                                                                                                                                     
Hit:4 http://apt.pop-os.org/proprietary jammy InRelease                                                                                                                                                                                                             
Hit:5 http://archive.ubuntu.com/ubuntu jammy-updates InRelease                                                                                                                                                
Hit:6 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease                                                                                                      
Hit:7 http://apt.pop-os.org/release jammy InRelease                                                                                  
Hit:8 https://downloads.1password.com/linux/debian/amd64 stable InRelease                                      
Hit:9 http://apt.pop-os.org/ubuntu jammy InRelease                                        
Ign:10 https://apt.fury.io/notion-repackaged  InRelease             
Ign:11 https://apt.fury.io/notion-repackaged  Release               
Hit:12 http://apt.pop-os.org/ubuntu jammy-security InRelease        
Ign:13 https://apt.fury.io/notion-repackaged  Packages              
Hit:14 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy InRelease
Hit:15 http://apt.pop-os.org/ubuntu jammy-updates InRelease         
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US     
Hit:17 https://ppa.launchpadcontent.net/ubuntu-toolchain-r/test/ubuntu jammy InRelease
Hit:18 http://apt.pop-os.org/ubuntu jammy-backports InRelease       
Ign:19 https://apt.fury.io/notion-repackaged  Translation-en
Get:13 https://apt.fury.io/notion-repackaged  Packages [1,572 B]
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:19 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:19 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:19 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:19 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:19 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:19 https://apt.fury.io/notion-repackaged  Translation-en
Fetched 54.0 kB in 4s (12.7 kB/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ca-certificates is already the newest version (20240203~22.04.1).
curl is already the newest version (7.81.0-1ubuntu1.21).
debootstrap is already the newest version (1.0.126+nmu1ubuntu0.8).
gpg is already the newest version (2.2.27-3ubuntu2.4).
systemd-container is already the newest version (249.11-0ubuntu3.16pop0~1749652895~22.04~34f0ce1).
v4l2loopback-dkms is already the newest version (0.15.1-1pop1~1756123534~22.04~a34615c).
gstreamer1.0-tools is already the newest version (1.24.13-0ubuntu1~22.04.sav0).
v4l-utils is already the newest version (1.26.1-2~22.04.sav0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[2025-10-02 15:43:51] Rootfs exists, reusing: /var/lib/machines/ipu6-noble
[2025-10-02 15:43:51] Configuring Intel IPU6 userspace PPA in container (Noble only)…
[2025-10-02 15:43:52] Updating APT metadata inside container…
Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease
Hit:2 http://archive.ubuntu.com/ubuntu noble-updates InRelease
Hit:3 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble InRelease
Hit:4 http://archive.ubuntu.com/ubuntu noble-security InRelease
Reading package lists... Done
[2025-10-02 15:43:53] Installing IPU6 HAL + icamerasrc + helpers inside container…
Reading package lists... Done
Building dependency tree... Done
E: Unable to locate package ipu6-camera-hal
E: Unable to locate package ipu6-camera-bins

```

Said that, explain why the current version of the script fail and find a fix that solve the problem and keep what work in the previuos version still working. And generate a new version of the script and explain the new approach and why it should work that time. And explain why the previous version fail and why the current version should work. Use websearch and knownledge base to get additional answer and mention all references and sites used to build the answer. Also use all processing power avaiable to build the answer. Do not stop work ultil build a valid answer

```
