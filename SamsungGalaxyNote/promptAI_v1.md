
The script version 57 run without fail, but the webcam is not working yeat. 
the firmware is working fine and the drivers are installed like can be seeded in the output of the `dmsg` command.
and the `systemd-containers` are installed and the dependecies are installed. But some thing are impedding the 
container to work properly as the logs from the command `journalctl -u ipu6-relay -b --no-pager` and  
`systemctl status ipu6-relay --no-pager` and `journalctl -u ipu6-relay -b --no-pager` show.
The approach of the `systemd-container` is the right approach, because it isolates the conflicting dependencies 
in the container keep in the host only what is needed. Bellow are the logs from the commands given the current state of the script.

Output of the version 57 of the script: `sudo ./ipu6_install_v57.sh`
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v57.sh            
[sudo] password for fernandoavanzo: 
[2025-10-04 12:00:53] Host preflight…
[2025-10-04 12:00:53] Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…
Get:1 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Hit:2 https://dl.google.com/linux/chrome/deb stable InRelease                                                                                                                                                                                                                                   
Hit:3 https://download.docker.com/linux/ubuntu jammy InRelease                                                                                                                                                                                                                                  
Hit:4 http://archive.ubuntu.com/ubuntu jammy-updates InRelease                                                                                                                                                                                                           
Hit:5 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease                                                                                                                                                                                    
Hit:6 https://downloads.1password.com/linux/debian/amd64 stable InRelease                                                                                               
Hit:7 http://apt.pop-os.org/proprietary jammy InRelease                                                                      
Ign:8 https://apt.fury.io/notion-repackaged  InRelease                                                 
Hit:9 http://apt.pop-os.org/release jammy InRelease                 
Ign:10 https://apt.fury.io/notion-repackaged  Release               
Hit:11 http://apt.pop-os.org/ubuntu jammy InRelease                 
Ign:12 https://apt.fury.io/notion-repackaged  Packages
Hit:13 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy InRelease
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US     
Hit:15 http://apt.pop-os.org/ubuntu jammy-security InRelease        
Hit:16 https://ppa.launchpadcontent.net/ubuntu-toolchain-r/test/ubuntu jammy InRelease
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
Fetched 5,194 B in 4s (1,373 B/s)
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
0 upgraded, 0 newly installed, 0 to remove and 6 not upgraded.
[2025-10-04 12:00:59] Loading v4l2loopback (1 device) at /dev/video0…
[2025-10-04 12:00:59] Host v4l2loopback ready at /dev/video0
[2025-10-04 12:00:59] Noble rootfs already exists, reusing.
[2025-10-04 12:00:59] Configuring APT sources & keyrings inside container…
[2025-10-04 12:00:59] Updating APT metadata inside container…
Console mode 'pipe' selected, but standard input/output are connected to an interactive TTY. Most likely you want to use 'interactive' console mode for proper interactivity and shell job control. Proceeding anyway.
Get:1 http://security.ubuntu.com/ubuntu noble-security InRelease [126 kB]                                                                
Hit:2 http://archive.ubuntu.com/ubuntu noble InRelease                                                                                   
Hit:3 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble InRelease                          
Get:4 http://archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]        
Get:5 http://archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages [1484 kB]
Get:6 http://archive.ubuntu.com/ubuntu noble-updates/universe amd64 Packages [1486 kB]
Fetched 3222 kB in 5s (707 kB/s)   
Reading package lists... Done
[2025-10-04 12:01:04] Installing IPU6 HAL + platform plugin + icamerasrc + tools inside container…
Console mode 'pipe' selected, but standard input/output are connected to an interactive TTY. Most likely you want to use 'interactive' console mode for proper interactivity and shell job control. Proceeding anyway.
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ca-certificates is already the newest version (20240203).
gnupg is already the newest version (2.4.4-2ubuntu17.3).
curl is already the newest version (8.5.0-2ubuntu10.6).
gstreamer1.0-tools is already the newest version (1.24.2-1ubuntu0.1).
v4l-utils is already the newest version (1.26.1-4build3).
libcamhal0 is already the newest version (0~git202506270118.c933525~ubuntu24.04.3).
libcamhal-ipu6epmtl is already the newest version (0~git202506270118.c933525~ubuntu24.04.3).
gstreamer1.0-icamera is already the newest version (0~git202509260937.4fb31db~ubuntu24.04.3).
0 upgraded, 0 newly installed, 0 to remove and 130 not upgraded.
Console mode 'pipe' selected, but standard input/output are connected to an interactive TTY. Most likely you want to use 'interactive' console mode for proper interactivity and shell job control. Proceeding anyway.
Console mode 'pipe' selected, but standard input/output are connected to an interactive TTY. Most likely you want to use 'interactive' console mode for proper interactivity and shell job control. Proceeding anyway.
[2025-10-04 12:01:04] Installing host wrapper and systemd service…
[2025-10-04 12:01:04] Done. Verify with: v4l2-ctl --list-devices (look for "Intel MIPI Virtual Camera" at /dev/video0)
```

Output pf the command: `v4l2-ctl --list-devices`
```bash
➜  SamsungGalaxyNote git:(main) ✗ v4l2-ctl --list-devices
ipu6 (PCI:0000:00:05.0):
        /dev/video1
        /dev/video2
        /dev/video3
        /dev/video4
        /dev/video5
        /dev/video6
        /dev/video7
        /dev/video8
        /dev/video9
        /dev/video11
        /dev/video12
        /dev/video13
        /dev/video14
        /dev/video15
        /dev/video16
        /dev/video17
        /dev/video18
        /dev/video19
        /dev/video20
        /dev/video21
        /dev/video22
        /dev/video23
        /dev/video24
        /dev/video25
        /dev/video26
        /dev/video27
        /dev/video28
        /dev/video29
        /dev/video30
        /dev/video31
        /dev/video32
        /dev/video33
        /dev/video34
        /dev/video35
        /dev/video36
        /dev/video37
        /dev/video38
        /dev/video39
        /dev/video40
        /dev/video41
        /dev/video42
        /dev/video43
        /dev/video44
        /dev/video45
        /dev/video46
        /dev/video47
        /dev/video48
        /dev/video49
        /dev/media0

Intel MIPI Virtual Camera (platform:v4l2loopback-000):
        /dev/video0
```

output of command: `systemctl status ipu6-relay --no-pager`
```bash
➜  SamsungGalaxyNote git:(main) ✗ systemctl status ipu6-relay --no-pager                                                           
× ipu6-relay.service - Intel IPU6 webcam relay (containerized) -> /dev/video0
     Loaded: loaded (/etc/systemd/system/ipu6-relay.service; enabled; vendor preset: enabled)
     Active: failed (Result: exit-code) since Sat 2025-10-04 12:01:11 -03; 9min ago
    Process: 15246 ExecStart=/usr/local/sbin/ipu6-relay-run (code=exited, status=1/FAILURE)
   Main PID: 15246 (code=exited, status=1/FAILURE)
        CPU: 15ms

Oct 04 12:01:11 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 5.
Oct 04 12:01:11 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:11 pop-os systemd[1]: ipu6-relay.service: Start request repeated too quickly.
Oct 04 12:01:11 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 12:01:11 pop-os systemd[1]: Failed to start Intel IPU6 webcam relay (containerized) -> /dev/video0.
```

output of command: `journalctl -u ipu6-relay -b --no-pager`
```bash
➜  SamsungGalaxyNote git:(main) ✗ journalctl -u ipu6-relay -b --no-pager
Oct 04 11:39:36 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:36 pop-os ipu6-relay-run[892]: Failed to copy /etc/resolv.conf to /var/lib/machines/ipu6-noble/etc/resolv.conf, ignoring: No such file or directory
Oct 04 11:39:36 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 11:39:36 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 11:39:37 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 1.
Oct 04 11:39:37 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:37 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:37 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 11:39:37 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 11:39:38 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 2.
Oct 04 11:39:38 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:38 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:38 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 11:39:38 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 11:39:39 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 3.
Oct 04 11:39:39 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:39 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:39 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 11:39:39 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 11:39:40 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 4.
Oct 04 11:39:40 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:40 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:41 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 11:39:41 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 11:39:42 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 5.
Oct 04 11:39:42 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 11:39:42 pop-os systemd[1]: ipu6-relay.service: Start request repeated too quickly.
Oct 04 11:39:42 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 11:39:42 pop-os systemd[1]: Failed to start Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:04 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:05 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 12:01:05 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 12:01:06 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 1.
Oct 04 12:01:06 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:06 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:06 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 12:01:06 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 12:01:07 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 2.
Oct 04 12:01:07 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:07 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:07 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 12:01:07 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 12:01:08 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 3.
Oct 04 12:01:08 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:08 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:08 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 12:01:08 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 12:01:10 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 4.
Oct 04 12:01:10 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:10 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:10 pop-os systemd[1]: ipu6-relay.service: Main process exited, code=exited, status=1/FAILURE
Oct 04 12:01:10 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 12:01:11 pop-os systemd[1]: ipu6-relay.service: Scheduled restart job, restart counter is at 5.
Oct 04 12:01:11 pop-os systemd[1]: Stopped Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 04 12:01:11 pop-os systemd[1]: ipu6-relay.service: Start request repeated too quickly.
Oct 04 12:01:11 pop-os systemd[1]: ipu6-relay.service: Failed with result 'exit-code'.
Oct 04 12:01:11 pop-os systemd[1]: Failed to start Intel IPU6 webcam relay (containerized) -> /dev/video0.
```

output of command: `machinectl shell ipu6-noble /bin/bash -lc 'gst-launch-1.0 -v icamerasrc ! fakesink num-buffers=1'`
```bash
➜  SamsungGalaxyNote git:(main) ✗ machinectl shell ipu6-noble /bin/bash -lc 'gst-launch-1.0 -v icamerasrc ! fakesink num-buffers=1'
Failed to get shell PTY: No machine 'ipu6-noble' known
```

output of command: `dmsg`
```bash
[    9.729566] intel_pmc_core INT33A1:00: Assuming a default substate order for this platform
[    9.729702] intel_pmc_core INT33A1:00:  initialized
[    9.738675] intel_vpu 0000:00:0b.0: enabling device (0000 -> 0002)
[    9.749246] intel_vpu 0000:00:0b.0: [drm] Firmware: intel/vpu/vpu_37xx_v1.bin, version: 20250115*MTL_CLIENT_SILICON-release*1905*ci_tag_ud202504_vpu_rc_20250115_1905*ae83b65d01c
[    9.749251] intel_vpu 0000:00:0b.0: [drm] Scheduler mode: HW
[    9.757914] intel-ipu6 0000:00:05.0: Found supported sensor OVTI02C1:00
[    9.758060] intel-ipu6 0000:00:05.0: Connected 1 cameras
[    9.760760] intel-ipu6 0000:00:05.0: Sending BOOT_LOAD to CSE
[    9.782423] input: Samsung Galaxy Book Camera Lens Cover as /devices/platform/SAM0430:00/input/input26
[    9.792773] input: gpio-keys as /devices/platform/ACPI0011:00/gpio-keys.4.auto/input/input27
```

Said that, explain why the current version of the script fail and find a fix that solve the problem and keep what work in the previuos version still working. And generate a new version of the script and explain the new approach and why it should work that time. And explain why the previous version fail and why the current version should work. Use websearch and knownledge base to get additional answer and mention all references and sites used to build the answer. Also use all processing power avaiable to build the answer. Do not stop work ultil build a valid answer
