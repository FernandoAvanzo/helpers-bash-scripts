
The script version 59 run without fail, but the webcam is not working yeat.
the firmware is working fine and the drivers are installed like can be seeded in the output of the `dmsg` command.
and the `systemd-containers` are installed and the dependecies are installed. But some thing are impedding the
webcam configed in container to work properly as the logs from the command `journalctl -u ipu6-relay -b --no-pager` and  
`systemctl status ipu6-relay --no-pager` and `journalctl -u ipu6-relay -b --no-pager` show.
The approach of the `systemd-container` is the right approach, because it isolates the conflicting dependencies
in the container keep in the host only what is needed. Looking for the logs of the container and the host it appears that the
the hardware cam from the host still are not be linked with the container, and the exposed container device are working in the host.
in the command `dmsg` are show the phisical webcam device listed in the host, as can be see in the this snippet log 
`[    9.686749] input: Samsung Galaxy Book Camera Lens Cover as /devices/platform/SAM0430:00/input/input26` from `dmsg`.
but the snippet log `ERROR: pipeline could not be constructed: could not set property "device-name" in element "icamerasrc" to "OVTI02C1:00"`
from `journalctl -u ipu6-relay -b --no-pager` show that the container is not able to find the device what let me think if are still missing some 
fine configuration in the container. The reason to use `systemd-container` is that some dependencies necessary for the phisical webcam 
to work can not be installed directlly in the system host because of it version, and the container approach is a workaround to solve this.
Validate it hypothesis, and  if it are right fix. if not suggest a valid solution.
Bellow are the logs from the commands given the current state of the script. Also are attached the prints showing that the webcam is not working.

command: `machinectl shell ipu6-noble /bin/bash -lc 'gst-launch-1.0 -v icamerasrc ! fakesink num-buffers=1'`
```bash
➜  SamsungGalaxyNote git:(main) ✗ machinectl shell ipu6-noble /bin/bash -lc 'gst-launch-1.0 -v icamerasrc ! fakesink num-buffers=1'
Failed to get shell PTY: No machine 'ipu6-noble' known
```
command: `systemctl status ipu6-relay --no-pager`
```bash
➜  SamsungGalaxyNote git:(main) ✗ systemctl status ipu6-relay --no-pager
○ ipu6-relay.service - Intel IPU6 webcam relay (containerized) -> /dev/video0
     Loaded: loaded (/etc/systemd/system/ipu6-relay.service; enabled; vendor preset: enabled)
     Active: inactive (dead) since Sun 2025-10-05 08:58:38 -03; 10min ago
   Main PID: 4182 (code=exited, status=0/SUCCESS)
        CPU: 14ms

Oct 05 08:58:38 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: ERROR: pipeline could not be constructed: could not set property "device-name" in element "icamerasrc" to "OVTI02C1:00".
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os systemd[1]: ipu6-relay.service: Deactivated successfully.
```
command: `journalctl -u ipu6-relay -b --no-pager`
```bash
➜  SamsungGalaxyNote git:(main) ✗ journalctl -u ipu6-relay -b --no-pager
Oct 05 08:58:38 pop-os systemd[1]: Started Intel IPU6 webcam relay (containerized) -> /dev/video0.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: ERROR: pipeline could not be constructed: could not set property "device-name" in element "icamerasrc" to "OVTI02C1:00".
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os ipu6-relay-run[4195]: [10-05 08:58:38.231] CamHAL[ERR] readlink sysName /sys/dev/char/0:0 failed ret -1.
Oct 05 08:58:38 pop-os systemd[1]: ipu6-relay.service: Deactivated successfully.
```
command: `v4l2-ctl --list-devices`
```bash
➜  SamsungGalaxyNote git:(main) ✗ v4l2-ctl --list-devices
ipu6 (PCI:0000:00:05.0):
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
        /dev/video50
        /dev/video51
        /dev/media1

Intel MIPI Camera Front (platform:v4l2loopback-000):
        /dev/video0

Virtual Camera (platform:v4l2loopback-010):
        /dev/video10

```
command: `lsmod`
```bash
➜  SamsungGalaxyNote git:(main) ✗ lsmod | grep -E 'intel_ipu6|ivsc'
intel_ipu6_isys       122880  0
videobuf2_dma_sg       20480  1 intel_ipu6_isys
videobuf2_v4l2         36864  2 intel_ipu6_isys,uvcvideo
videobuf2_common       86016  6 videobuf2_vmalloc,videobuf2_v4l2,intel_ipu6_isys,uvcvideo,videobuf2_dma_sg,videobuf2_memops
intel_ipu6             73728  1 intel_ipu6_isys
ipu_bridge             20480  2 intel_ipu6,intel_ipu6_isys
v4l2_fwnode            40960  2 ov02c10,intel_ipu6_isys
v4l2_async             28672  3 v4l2_fwnode,ov02c10,intel_ipu6_isys
videodev              368640  7 v4l2_async,v4l2_fwnode,videobuf2_v4l2,ov02c10,v4l2loopback,intel_ipu6_isys,uvcvideo
mc                     81920  8 v4l2_async,videodev,snd_usb_audio,videobuf2_v4l2,ov02c10,intel_ipu6_isys,uvcvideo,videobuf2_common
```

command: `dmsg`
```bash
[    9.615422] intel-ipu6 0000:00:05.0: enabling device (0000 -> 0002)
[    9.616520] pci 0000:00:0b.0: Setting to D3hot
[    9.628559] intel_pmc_core INT33A1:00: Assuming a default substate order for this platform
[    9.628665] intel_pmc_core INT33A1:00:  initialized
[    9.662420] intel-ipu6 0000:00:05.0: Found supported sensor OVTI02C1:00
[    9.662550] intel-ipu6 0000:00:05.0: Connected 1 cameras
[    9.669087] intel-ipu6 0000:00:05.0: Sending BOOT_LOAD to CSE
[    9.669766] RAPL PMU: API unit is 2^-32 Joules, 3 fixed counters, 655360 ms ovfl timer
[    9.669768] RAPL PMU: hw unit of domain pp0-core 2^-14 Joules
[    9.669769] RAPL PMU: hw unit of domain package 2^-14 Joules
[    9.669770] RAPL PMU: hw unit of domain pp1-gpu 2^-14 Joules
[    9.672615] ACPI: battery: new hook: Samsung Galaxy Book Battery Extension
[    9.675586] intel_vpu 0000:00:0b.0: enabling device (0000 -> 0002)
[    9.686749] input: Samsung Galaxy Book Camera Lens Cover as /devices/platform/SAM0430:00/input/input26
[    9.690478] intel_vpu 0000:00:0b.0: [drm] Firmware: intel/vpu/vpu_37xx_v1.bin, version: 20250115*MTL_CLIENT_SILICON-release*1905*ci_tag_ud202504_vpu_rc_20250115_1905*ae83b65d01c
[    9.690486] intel_vpu 0000:00:0b.0: [drm] Scheduler mode: HW
[    9.705127] spi-nor spi0.0: supply vcc not found, using dummy regulator
[    9.707521] intel-ipu6 0000:00:05.0: Sending AUTHENTICATE_RUN to CSE
```

command: `hostnamectl`
```bash
➜  SamsungGalaxyNote git:(main) ✗ hostnamectl
 Static hostname: pop-os
       Icon name: computer-laptop
         Chassis: laptop
      Machine ID: 8328871196c857387d7234d366b2592f
         Boot ID: 155bed5dd5af4f69b02ce114cd86d306
Operating System: Pop!_OS 22.04 LTS               
          Kernel: Linux 6.16.3-76061603-generic
    Architecture: x86-64
 Hardware Vendor: SAMSUNG ELECTRONICS CO., LTD.
  Hardware Model: 960XGL
```
Said that, explain why the current version of the script fail and find a fix that solve the problem and keep what work in the previuos version still working. And generate a new version of the script and explain the new approach and why it should work that time. And explain why the previous version fail and why the current version should work. Use websearch and knownledge base to get additional answer and mention all references and sites used to build the answer. Also use all processing power avaiable to build the answer. Do not stop work ultil build a valid answer
