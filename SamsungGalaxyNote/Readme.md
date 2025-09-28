#### Why your internal camera is invisible right now

* Samsung’s Galaxy Book4 Ultra (model **NP960XGL**) uses the **Intel “Meteor Lake” Image Processing Unit (IPU 6E)** instead of a classic USB-UVC webcam.
* The IPU6E driver for Meteor Lake hasn’t reached mainline Linux yet. On kernels ≤ 6.12 the device appears on the PCI bus (usually **0000:00:05.0**) but the probe aborts because the driver and its signed firmware are missing:

````
intel-ipu6 … Direct firmware load for intel/ipu6epmtl_fw.bin failed with error –2
``` :contentReference[oaicite:0]{index=0}  

Intel publishes an out-of-tree driver stack + firmware on GitHub; it already lists **Meteor Lake** as a supported platform :contentReference[oaicite:1]{index=1}, but you have to install it manually.

---

### Quick test before you begin

```bash
# Is the IPU visible?
lspci -nn | grep -i ipu
# Any video nodes at all?
ls -l /dev/video*
# Kernel messages
dmesg | grep -iE 'ipu|video|firmware'
````

If you see the firmware-load error it’s the situation described above.

---

### Fix/Work-around options

| Option                                                             | What to do                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Pros                                                      | Cons                                                                                                                                                    |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. Build Intel’s IPU6 driver stack now**                         | Requires four repos:<br>`bash<br>sudo apt install dkms build-essential git<br>git clone https://github.com/intel/ipu6-drivers.git<br>git clone https://github.com/intel/ipu6-camera-bins.git<br>git clone https://github.com/intel/ipu6-camera-hal.git<br>git clone --branch icamerasrc_slim_api https://github.com/intel/icamerasrc.git<br>`<br>Then:<br>`bash<br># a) kernel modules via DKMS<br>cd ipu6-drivers && sudo ./scripts/dkms-install.sh   # <– see README<br># b) copy firmware<br>sudo mkdir -p /lib/firmware/intel/ipu<br>sudo cp ../ipu6-camera-bins/lib/firmware/intel/ipu/ipu6epmtl_fw.bin /lib/firmware/intel/ipu/<br># c) install HAL + libs (run the commands in the camera-bins README)`<br>Reboot and test:<br>`gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink` | Works today on 6.8-6.12 kernels; no distro upgrade needed | Needs compiler tool-chain; Secure-Boot must be off (or you must sign the DKMS module); stack can break when the kernel updates – repeat the DKMS build. |
| **2. Move to a bleeding-edge kernel (≥ 6.10) once IPU6 is merged** | Mainline patches are under review; Ubuntu 24.10 / Fedora 40 rawhide already ship daily builds you can try                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | No out-of-tree maintenance once it lands                  | You have to run a pre-release kernel now, or wait a few months.                                                                                         |
| **3. Temporary fallback**                                          | Use any external USB-UVC webcam                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Two-minute solution                                       | Extra hardware, no face-unlock, etc.                                                                                                                    |

---

### After installation

1. Verify firmware was found:

```bash
dmesg | grep -i 'ipu6.*firmware'
```

2. Check the media graph:

```bash
sudo apt install media-ctl v4l-utils
media-ctl -p
```

3. Test with Cheese, Zoom, WebRTC, etc.

---

### Things that often trip people up

* **Secure Boot:** Pop!\_OS disables it by default, but if you re-enabled it the DKMS module won’t load unless you sign it.
* **Firmware path:** the driver looks for `/lib/firmware/intel/ipu6epmtl_fw.bin` exactly. The file ships in the *ipu6-camera-bins* repo ([github.com][1]).
* **NVidia driver:** the Book4 Ultra has discrete RTX hardware; it’s unrelated to the camera problem but make sure you’re on System76’s 555.x driver branch if you upgrade kernels.

---

### Summary

Your webcam isn’t broken—the driver simply hasn’t made it into stock kernels yet. Installing Intel’s **ipu6-drivers + firmware** or running a very new kernel (6.10+) brings the camera to life; otherwise an external USB camera is the quick workaround.

[1]: https://github.com/intel/ipu6-camera-bins "GitHub - intel/ipu6-camera-bins"

Below is a **complete walk-through** of “Suggestion 1 – Build Intel IPU 6 driver stack now” followed by two ready-to-run shell scripts:

* **`ipu6_install.sh`** – sets everything up • out-of-tree DKMS kernel module • firmware • user-space HAL • GStreamer source.
* **`ipu6_rollback.sh`** – reverts all changes (removes DKMS module, restores firmware & libraries, refreshes initramfs).

You can copy-paste each script to `/opt/ipu6/` and run with `sudo bash`.

---

## 1  What you are going to build

| Layer                                | What it does                                      | Repo / branch                                                                 |
| ------------------------------------ | ------------------------------------------------- | ----------------------------------------------------------------------------- |
| Kernel module                        | IPU 6/6E PCI + MIPI sensor drivers, DKMS-friendly | **intel/ipu6-drivers** ([raw.githubusercontent.com][1])                       |
| Firmware & proprietary IPC libraries | Signed `.bin` blobs + `libipu*` libs              | **intel/ipu6-camera-bins** ([raw.githubusercontent.com][2])                   |
| HAL (IPC userspace)                  | Converts raw ISP output to V4L2/video             | **intel/ipu6-camera-hal** ([raw.githubusercontent.com][3])                    |
| GStreamer plugin                     | `icamerasrc` for WebRTC/Zoom/etc.                 | **intel/icamerasrc (icamerasrc\_slim\_api)** ([raw.githubusercontent.com][4]) |

The stack already lists **Meteor Lake** as a supported platform, which is the generation inside your Galaxy Book 4 Ultra ([raw.githubusercontent.com][1]).

---

## 2  Prerequisites & caveats

1. **Secure-Boot** must be *disabled* or you will need to sign the DKMS module manually.
2. Pop!\_OS 22.04 headers ≥ 6.12 are fine; keep them up-to-date.
3. The install script uses `/opt/ipu6` and DKMS so upgrades survive kernel changes.
4. Reboot once at the end; first boot will take \~30 s longer while the modules & firmware are picked up.

---

## 3  Installation script (`ipu6_install.sh`)

### How it works

* **DKMS path** mirrors the upstream recipe – it registers the module as
  `ipu6-drivers/0.0.0`, so every new kernel triggers an automatic rebuild
  (no manual patching required) ([raw.githubusercontent.com][1]).
* Firmware blobs go to `/lib/firmware/intel/ipu`, exactly where the kernel
  looks for `ipu6epmtl_fw.bin` ([raw.githubusercontent.com][2]).
* Userspace HAL and `icamerasrc` follow the upstream CMake/Autotools
  instructions ([raw.githubusercontent.com][3], [raw.githubusercontent.com][4]).

---

## 4  Rollback script (`ipu6_rollback.sh`)

The script:

1. Removes the DKMS package and source tree.
2. Deletes installed shared objects and restores your previous firmware.
3. Refreshes module & initramfs caches so the old state boots cleanly.

---

## 5  First-boot validation checklist

```bash
dmesg | grep -iE 'ipu6|intel.*image'
ls /dev/video*          # expect /dev/video0 → ipu6-isys
media-ctl -p            # media graph should enumerate ipu6 pipelines
gst-launch-1.0 icamerasrc ! videoconvert ! ximagesink
```

If you still see `… firmware load failed …`, double-check Secure Boot and that
`ipu6epmtl_fw.bin` is in `/lib/firmware/intel/ipu` (unsigned firmware lives in
the `unsigned/` sub-dir and can be copied instead for engineering samples). ([raw.githubusercontent.com][2])

---

### You’re all set!

With the DKMS package in place your IPU6 webcam will survive future Pop!\_OS
kernel updates automatically; if anything breaks, run
`sudo bash /opt/ipu6/ipu6_rollback.sh` and you’ll be back to the original state
in under a minute.

[1]: https://raw.githubusercontent.com/intel/ipu6-drivers/master/README.md "raw.githubusercontent.com"
[2]: https://raw.githubusercontent.com/intel/ipu6-camera-bins/main/README.md "raw.githubusercontent.com"
[3]: https://raw.githubusercontent.com/intel/ipu6-camera-hal/main/README.md "raw.githubusercontent.com"
[4]: https://raw.githubusercontent.com/intel/icamerasrc/icamerasrc_slim_api/README.md "raw.githubusercontent.com"

---

## Upadte Pop!_OS 22.04 to 6.15.4 with NVIDIA 570 + Secure Boot (MOK auto-sign)

```bash
  chmod +x popos-6154-nvidia570-secureboot.sh
  sudo ./popos-6154-nvidia570-secureboot.sh            # normal run
  sudo ./popos-6154-nvidia570-secureboot.sh --set-default   # also set 6.15.4 as default
        
```

## Troubleshooting
check if the camera is working
```bash
[✓] Done. If the camera still doesn’t show up, reboot, then run:
    cam --list   # from libcamera-tools
    gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink   # from gstreamer1.0-plugins-base
```

Errors in scripts run
```bash
Some packages could not be installed. This may mean that you have
requested an impossible situation or if you are using the unstable
distribution that some required packages have not yet been created
or been moved out of Incoming.
The following information may help to resolve the situation:

The following packages have unmet dependencies:
 libcamera-v4l2 : Breaks: libcamera0 (< 0.0.3-1~) but 0~git20200629+e7aa92a-9 is to be installed
 libcamera0.5 : Breaks: libcamera0 (< 0.0.3-1~) but 0~git20200629+e7aa92a-9 is to be installed
                Recommends: libcamera-ipa (= 0.5.2-2~22.04.sav0) but it is not going to be installed
 libspa-0.2-libcamera : Depends: libspa-0.2-modules (= 1.4.8-1~22.04.sav1) but 1.0.2~1707732619~22.04~b8b871b is to be installed
E: Unable to correct problems, you have held broken packages.
```

Errors triggered by running the commands after installation
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink
[sudo] password for fernandoavanzo: 
Setting pipeline to PAUSED ...
Pipeline is live and does not need PREROLL ...
Pipeline is PREROLLED ...
Setting pipeline to PLAYING ...
New clock: GstSystemClock
ERROR: from element /GstPipeline:pipeline0/GstV4l2Src:v4l2src0: Device '/dev/video0' does not support 2:0:0:0 colorimetry
Additional debug info:
../sys/v4l2/gstv4l2object.c(4374): gst_v4l2_object_set_format_full (): /GstPipeline:pipeline0/GstV4l2Src:v4l2src0:
Device wants 2:0:0:0 colorimetry
Execution ended after 0:00:00.003163722
Setting pipeline to NULL ...
ERROR: from element /GstPipeline:pipeline0/GstV4l2Src:v4l2src0: Internal data stream error.
Additional debug info:
../libs/gst/base/gstbasesrc.c(3177): gst_base_src_loop (): /GstPipeline:pipeline0/GstV4l2Src:v4l2src0:
streaming stopped, reason not-negotiated (-4)
Freeing pipeline ...
➜  SamsungGalaxyNote git:(main) ✗ cam --list
zsh: command not found: cam
➜  SamsungGalaxyNote git:(main) ✗ 
```

log from `dmsg` command after script running:
```bash
[   10.407724] BUG: unable to handle page fault for address: 00000000ff78d008
[   10.407730] #PF: supervisor read access in kernel mode
[   10.407731] #PF: error_code(0x0000) - not-present page
[   10.407733] PGD 0 P4D 0 
[   10.407736] Oops: Oops: 0000 [#1] SMP NOPTI
[   10.407739] CPU: 11 UID: 0 PID: 530 Comm: systemd-udevd Tainted: P           OE       6.16.3-76061603-generic #202508231538~1758561135~22.04~171c8de PREEMPT(voluntary) 
[   10.407741] Tainted: [P]=PROPRIETARY_MODULE, [O]=OOT_MODULE, [E]=UNSIGNED_MODULE
[   10.407742] Hardware name: SAMSUNG ELECTRONICS CO., LTD. 960XGL/NP960XGL-XG2BR, BIOS P04ALX.320.240304.04 03/04/2024
[   10.407743] RIP: 0010:ipu6_psys_probe+0x314/0x5b0 [intel_ipu6_psys]
[   10.407751] Code: 20 4c 89 6b 28 49 89 86 30 04 00 00 41 83 ec 01 0f 85 5a ff ff ff 49 8b 87 b0 03 00 00 48 c7 c6 46 4c 95 c1 4c 89 ff 8b 5d c4 <48> 8b 40 08 41 89 46 18 89 c2 e8 fd 30 f8 f3 44 0f b6 25 61 5a 22
[   10.407753] RSP: 0018:ffffd3520105b690 EFLAGS: 00010246
[   10.407754] RAX: 00000000ff78d000 RBX: 0000000000000000 RCX: 0000000000000000
[   10.407755] RDX: ffff8b575e684020 RSI: ffffffffc1954c46 RDI: ffff8b57498db800
[   10.407756] RBP: ffffd3520105b6d8 R08: 0000000000000000 R09: 0000000000000000
[   10.407756] R10: 0000000000000000 R11: 0000000000000000 R12: 0000000000000000
[   10.407757] R13: ffff8b576aedc458 R14: ffff8b576aedc028 R15: ffff8b57498db800
[   10.407758] FS:  00007daa546348c0(0000) GS:ffff8b5ee97ea000(0000) knlGS:0000000000000000
[   10.407759] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
[   10.407760] CR2: 00000000ff78d008 CR3: 0000000104ace003 CR4: 0000000000f70ef0
[   10.407761] PKRU: 55555554
[   10.407761] Call Trace:
[   10.407763]  <TASK>
[   10.407764]  ? __pfx_ipu6_psys_probe+0x10/0x10 [intel_ipu6_psys]
[   10.407769]  auxiliary_bus_probe+0x3e/0xa0
[   10.407773]  really_probe+0xee/0x3b0
[   10.407776]  __driver_probe_device+0x8c/0x180
[   10.407778]  driver_probe_device+0x24/0xd0
[   10.407779]  __driver_attach+0x10b/0x210
[   10.407780]  ? __pfx___driver_attach+0x10/0x10
[   10.407782]  bus_for_each_dev+0x89/0xf0
[   10.407784]  driver_attach+0x1e/0x30
[   10.407785]  bus_add_driver+0x14e/0x290
[   10.407786]  driver_register+0x5e/0x130
[   10.407788]  __auxiliary_driver_register+0x73/0xf0
[   10.407790]  ipu_psys_init+0x54/0xff0 [intel_ipu6_psys]
[   10.407793]  ? __pfx_ipu_psys_init+0x10/0x10 [intel_ipu6_psys]
[   10.407796]  do_one_initcall+0x5a/0x340
[   10.407799]  do_init_module+0x97/0x2c0
[   10.407802]  load_module+0x962/0xa80
[   10.407803]  init_module_from_file+0x95/0x100
[   10.407805]  idempotent_init_module+0x10f/0x300
[   10.407807]  __x64_sys_finit_module+0x73/0xe0
[   10.407808]  x64_sys_call+0x1ecd/0x2550
[   10.407810]  do_syscall_64+0x80/0xcb0
[   10.407815]  ? mmap_region+0x66/0xe0
[   10.407818]  ? sysvec_call_function+0x57/0xc0
[   10.407820]  ? asm_sysvec_call_function+0x1b/0x20
[   10.407823]  ? ksys_mmap_pgoff+0x61/0x240
[   10.407825]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   10.407827]  ? do_syscall_64+0xb6/0xcb0
[   10.407828]  ? ksys_read+0x71/0xf0
[   10.407832]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   10.407833]  ? do_syscall_64+0xb6/0xcb0
[   10.407835]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   10.407836]  ? do_syscall_64+0xb6/0xcb0
[   10.407838]  ? __flush_smp_call_function_queue+0x99/0x440
[   10.407841]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   10.407843]  ? irqentry_exit_to_user_mode+0x2d/0x1d0
[   10.407844]  ? irqentry_exit+0x43/0x50
[   10.407845]  entry_SYSCALL_64_after_hwframe+0x76/0x7e
[   10.407846] RIP: 0033:0x7daa5451e8fd
[   10.407848] Code: 5b 41 5c c3 66 0f 1f 84 00 00 00 00 00 f3 0f 1e fa 48 89 f8 48 89 f7 48 89 d6 48 89 ca 4d 89 c2 4d 89 c8 4c 8b 4c 24 08 0f 05 <48> 3d 01 f0 ff ff 73 01 c3 48 8b 0d 03 b5 0f 00 f7 d8 64 89 01 48
[   10.407849] RSP: 002b:00007ffca016aa08 EFLAGS: 00000246 ORIG_RAX: 0000000000000139
[   10.407851] RAX: ffffffffffffffda RBX: 00005d6404836da0 RCX: 00007daa5451e8fd
[   10.407852] RDX: 0000000000000000 RSI: 00007daa546fb441 RDI: 0000000000000006
[   10.407853] RBP: 0000000000020000 R08: 0000000000000000 R09: 0000000000000002
[   10.407853] R10: 0000000000000006 R11: 0000000000000246 R12: 00007daa546fb441
[   10.407854] R13: 00005d6404839dd0 R14: 00005d6404840050 R15: 00005d640483d3a0
[   10.407856]  </TASK>
[   10.407856] Modules linked in: intel_uncore_frequency_common lz4hc_compress(+) snd_intel_dspcfg nvidia_drm(POE+) lz4_compress snd_intel_sdw_acpi nvidia_modeset(POE) x86_pkg_temp_thermal intel_powerclamp snd_hda_codec intel_ipu6_psys(OE+) snd_hda_core coretemp snd_hwdep mac80211 intel_ipu6_isys snd_pcm videobuf2_dma_sg snd_seq_midi videobuf2_memops kvm_intel binfmt_misc libarc4 snd_seq_midi_event videobuf2_v4l2 videobuf2_common nvidia(POE) dm_crypt snd_rawmidi nls_iso8859_1 iwlwifi snd_seq kvm btusb snd_seq_device btrtl hid_sensor_als snd_timer hid_sensor_trigger processor_thermal_device_pci btintel cmdlinepart processor_thermal_device industrialio_triggered_buffer processor_thermal_wt_hint btbcm kfifo_buf platform_temperature_control mei_gsc_proxy irqbypass btmtk intel_rapl_msr gpio_keys(+) hid_sensor_iio_common snd input_leds(+) rapl processor_thermal_rfim cfg80211 spi_nor mei_me bluetooth processor_thermal_rapl industrialio soundcore mei mtd hid_multitouch(+) intel_rapl_common serio_raw samsung_galaxybook wmi_bmof
[   10.407888]  intel_cstate intel_vpu intel_ipu6 processor_thermal_wt_req firmware_attributes_class processor_thermal_power_floor igen6_edac ipu_bridge processor_thermal_mbox platform_profile ov02c10(OE) v4l2_fwnode intel_pmc_core int3403_thermal v4l2_async int340x_thermal_zone videodev mac_hid mc pmt_telemetry pmt_class int3400_thermal acpi_thermal_rel intel_pmc_ssram_telemetry acpi_pad soc_button_array acpi_tad sch_fq_codel kyber_iosched msr parport_pc ppdev lp parport efi_pstore ip_tables x_tables autofs4 raid10 raid456 async_raid6_recov async_memcpy async_pq async_xor async_tx xor raid6_pq raid1 raid0 linear system76_io(OE) system76_acpi(OE) xe drm_gpuvm drm_gpusvm gpu_sched drm_ttm_helper drm_exec drm_suballoc_helper hid_sensor_custom hid_logitech_hidpp hid_sensor_hub intel_ishtp_hid hid_logitech_dj i915 ucsi_acpi typec_ucsi drm_buddy ttm typec i2c_i801 polyval_clmulni hid_generic i2c_algo_bit ghash_clmulni_intel usbhid nvme sha1_ssse3 drm_display_helper i2c_smbus intel_lpss_pci spi_intel_pci intel_ish_ipc i2c_mux
[   10.407925]  cec thunderbolt intel_lpss spi_intel nvme_core idma64 intel_ishtp rc_core nvme_keyring intel_vsec nvme_auth i2c_hid_acpi i2c_hid hid video wmi pinctrl_meteorlake aesni_intel
[   10.407934] CR2: 00000000ff78d008
[   10.407936] ---[ end trace 0000000000000000 ]---
[   10.631242] pstore: backend (efi_pstore) writing error (-22)
[   10.631253] RIP: 0010:ipu6_psys_probe+0x314/0x5b0 [intel_ipu6_psys]
[   10.631269] Code: 20 4c 89 6b 28 49 89 86 30 04 00 00 41 83 ec 01 0f 85 5a ff ff ff 49 8b 87 b0 03 00 00 48 c7 c6 46 4c 95 c1 4c 89 ff 8b 5d c4 <48> 8b 40 08 41 89 46 18 89 c2 e8 fd 30 f8 f3 44 0f b6 25 61 5a 22
[   10.631270] RSP: 0018:ffffd3520105b690 EFLAGS: 00010246
[   10.631272] RAX: 00000000ff78d000 RBX: 0000000000000000 RCX: 0000000000000000
[   10.631274] RDX: ffff8b575e684020 RSI: ffffffffc1954c46 RDI: ffff8b57498db800
[   10.631275] RBP: ffffd3520105b6d8 R08: 0000000000000000 R09: 0000000000000000
[   10.631276] R10: 0000000000000000 R11: 0000000000000000 R12: 0000000000000000
[   10.631277] R13: ffff8b576aedc458 R14: ffff8b576aedc028 R15: ffff8b57498db800
[   10.631278] FS:  00007daa546348c0(0000) GS:ffff8b5ee97ea000(0000) knlGS:0000000000000000
[   10.631279] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
[   10.631280] CR2: 00000000ff78d008 CR3: 0000000104ace003 CR4: 0000000000f70ef0
[   10.631281] PKRU: 55555554
[   10.631282] note: systemd-udevd[530] exited with irqs disabled


```

### Script version 3 Errors

errors running during the new script version execution

```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v3.sh                                                    
[sudo] password for fernandoavanzo: 
[1/8] Detecting conflicting DKMS/IPU6 packages...
  Found: libspa-0.2-libcamera
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
Package 'libspa-0.2-libcamera' is not installed, so not removed
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[2/8] Disabling suspicious camera-related PPAs (if any)...
  ppa-purge on savoury1-ubuntu-multimedia-jammy.list ...
[3/8] Refreshing APT and fixing broken state...
Get:1 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Hit:2 https://dl.google.com/linux/chrome/deb stable InRelease                                                                                                                                                                       
Get:3 http://archive.ubuntu.com/ubuntu jammy-updates InRelease [128 kB]                                                             
Hit:4 http://apt.pop-os.org/proprietary jammy InRelease                                                                                        
Hit:5 https://download.docker.com/linux/ubuntu jammy InRelease                                                                                 
Hit:6 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease                                                                     
Hit:7 http://apt.pop-os.org/release jammy InRelease                                                        
Hit:8 http://apt.pop-os.org/ubuntu jammy InRelease                                                                                          
Hit:9 http://apt.pop-os.org/ubuntu jammy-security InRelease                                                                                
Get:10 http://archive.ubuntu.com/ubuntu jammy-updates/universe amd64 DEP-11 Metadata [359 kB]       
Ign:11 https://apt.fury.io/notion-repackaged  InRelease                                                     
Hit:12 http://apt.pop-os.org/ubuntu jammy-updates InRelease                                                 
Ign:13 https://apt.fury.io/notion-repackaged  Release                                  
Hit:14 https://downloads.1password.com/linux/debian/amd64 stable InRelease             
Ign:15 https://apt.fury.io/notion-repackaged  Packages                                 
Hit:16 http://apt.pop-os.org/ubuntu jammy-backports InRelease                         
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en    
Ign:18 https://apt.fury.io/notion-repackaged  Translation-en_US                
Get:19 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 DEP-11 Metadata [112 kB]
Get:15 https://apt.fury.io/notion-repackaged  Packages [1,572 B]  
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en      
Ign:18 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:18 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:18 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:18 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:18 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:17 https://apt.fury.io/notion-repackaged  Translation-en
Ign:18 https://apt.fury.io/notion-repackaged  Translation-en_US
Fetched 604 kB in 4s (141 kB/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
[4/8] Ensure kernel firmware is current (Meteor Lake IPU6 firmware)...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
linux-firmware is already the newest version (20250317.git1d4c88ee-0ubuntu1+system76~1749060582~22.04~230e2f0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[5/8] Install libcamera userspace + GStreamer plugin...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
E: Unable to locate package libcamera-ipa
E: Unable to locate package gstreamer1.0-libcamera
E: Couldn't find any package by glob 'gstreamer1.0-libcamera'
E: Couldn't find any package by regex 'gstreamer1.0-libcamera'
```


### Script version 4 Errors

error from the script version 4

```bash

➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v4.sh
[0/7] Pre-flight...
Kernel: 6.16.3-76061603-generic
[1/7] Remove conflicting PPAs & packages (savoury1 etc.)...
Hit:1 https://download.docker.com/linux/ubuntu jammy InRelease
Get:2 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Hit:3 https://dl.google.com/linux/chrome/deb stable InRelease
Hit:4 http://archive.ubuntu.com/ubuntu jammy-updates InRelease
Hit:5 http://apt.pop-os.org/proprietary jammy InRelease
Hit:6 https://downloads.1password.com/linux/debian/amd64 stable InRelease
Hit:7 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease
Hit:8 http://apt.pop-os.org/release jammy InRelease
Ign:9 https://apt.fury.io/notion-repackaged  InRelease
Hit:10 http://apt.pop-os.org/ubuntu jammy InRelease
Ign:11 https://apt.fury.io/notion-repackaged  Release
Hit:12 http://apt.pop-os.org/ubuntu jammy-security InRelease
Ign:13 https://apt.fury.io/notion-repackaged  Packages
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en
Hit:15 http://apt.pop-os.org/ubuntu jammy-updates InRelease
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Hit:17 http://apt.pop-os.org/ubuntu jammy-backports InRelease
Get:13 https://apt.fury.io/notion-repackaged  Packages [1,572 B]
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en_US
Fetched 5,194 B in 4s (1,357 B/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
ppa-purge is already the newest version (0.2.8+bzr63-0ubuntu1).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[2/7] Purge out-of-tree IPU6/IVSC/USBIO stacks (if any) and clean leftovers...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
Note, selecting 'linux-modules-ipu6-6.8.0-57-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-59-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-46-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-50-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-50-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.17.0-1031-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-45-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-52-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-41-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-43-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.17.0-1032-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-58-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-45-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1011-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.17.0-1033-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-45-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1012-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-47-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-49-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.17.0-1034-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1007-azure' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1015-azure' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-44-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.17.0-1035-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-1024-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-42-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-1025-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-40-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-35-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-1027-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-32-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.0.0-1020-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-48-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-1028-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-34-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-41-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1020-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-oem-22.04a' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-oem-22.04b' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-oem-22.04c' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-oem-22.04d' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-36-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1012-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.0.0-1021-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1021-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-39-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1013-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1022-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1014-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1007-nvidia' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-31-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1023-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-33-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-25-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1013-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1015-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-35-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-27-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1014-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-37-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1024-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.0.0-1016-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-39-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1015-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-38-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1016-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1033-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1016-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1025-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-26-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.0.0-1017-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1017-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1017-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1034-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1026-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.0.0-1018-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-generic-hwe-22.04-edge' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-azure' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1035-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-generic-hwe-22.04' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-26-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1027-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.0.0-1019-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-28-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-lowlatency-hwe-22.04' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-83-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1019-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1036-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1028-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-15-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-25-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1011-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-17-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1017-azure' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1003-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1020-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.1.0-1029-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-lowlatency-hwe-22.04-edge' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-21-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-oem-22.04' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1004-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1013-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1022-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-84-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1009-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-14-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1014-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1006-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1023-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-18-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1015-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1018-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1007-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1024-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-79-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1016-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1008-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1025-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1009-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-5.19.0-1030-lowlatency' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1018-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1027-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1019-oem' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-78-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-65-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-generic-6.8' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-60-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-64-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.8.0-51-generic' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.2.0-1008-azure' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-6.5.0-1016-azure' for glob 'linux-modules-ipu6*'
Note, selecting 'linux-modules-ipu6-azure-edge' for glob 'linux-modules-ipu6*'
Package 'libspa-0.2-libcamera' is not installed, so not removed
[3/7] Make sure the official firmware & base multimedia stack are in place...
Hit:1 https://download.docker.com/linux/ubuntu jammy InRelease
Get:2 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Hit:3 https://dl.google.com/linux/chrome/deb stable InRelease
Hit:4 http://apt.pop-os.org/proprietary jammy InRelease
Hit:5 http://archive.ubuntu.com/ubuntu jammy-updates InRelease
Hit:6 https://downloads.1password.com/linux/debian/amd64 stable InRelease
Ign:7 https://apt.fury.io/notion-repackaged  InRelease
Hit:8 http://apt.pop-os.org/release jammy InRelease
Hit:9 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease
Ign:10 https://apt.fury.io/notion-repackaged  Release
Hit:11 http://apt.pop-os.org/ubuntu jammy InRelease
Ign:12 https://apt.fury.io/notion-repackaged  Packages
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en_US
Hit:14 http://apt.pop-os.org/ubuntu jammy-security InRelease
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en
Get:12 https://apt.fury.io/notion-repackaged  Packages [1,572 B]
Hit:16 http://apt.pop-os.org/ubuntu jammy-updates InRelease
Hit:17 http://apt.pop-os.org/ubuntu jammy-backports InRelease
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en
Fetched 5,194 B in 4s (1,337 B/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
linux-firmware is already the newest version (20250317.git1d4c88ee-0ubuntu1+system76~1749060582~22.04~230e2f0).
v4l-utils is already the newest version (1.26.1-2~22.04.sav0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
- Found IPU6 MTL firmware: /lib/firmware/intel/ipu/ipu6epmtl_fw.bin
[4/7] Install libcamera tooling from Jammy repos (no PPAs)...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
xdg-desktop-portal is already the newest version (1.14.4-1ubuntu2~22.04.2).
xdg-desktop-portal-gnome is already the newest version (42.1-0ubuntu2).
pipewire is already the newest version (1.0.2~1707732619~22.04~b8b871b).
wireplumber is already the newest version (0.4.17~1701792620~22.04~e8b4d60).
libcamera-tools is already the newest version (0~git20200629+e7aa92a-9).
libcamera0 is already the newest version (0~git20200629+e7aa92a-9).
gstreamer1.0-plugins-bad is already the newest version (1.24.13-0ubuntu1~22.04.sav0.1).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
E: Unable to locate package libcamera-v4l2
[5/7] Ensure we only ever load in-kernel IPU6
update-initramfs: Generating /boot/initrd.img-6.16.3-76061603-generic
kernelstub.Config    : INFO     Looking for configuration...
kernelstub           : INFO     System information:

OS:..................Pop!_OS 22.04
Root partition:....../dev/nvme0n1p1
Root FS UUID:........647e0206-eb25-4d00-a050-d3797e55d5c7
ESP Path:............/boot/efi
ESP Partition:......./dev/nvme0n1p3
ESP Partition #:.....3
NVRAM entry #:.......-1
Boot Variable #:.....0000
Kernel Boot Options:.quiet loglevel=0 systemd.show_status=false splash
Kernel Image Path:.../boot/vmlinuz-6.16.3-76061603-generic
Initrd Image Path:.../boot/initrd.img-6.16.3-76061603-generic
Force-overwrite:.....False

kernelstub.Installer : INFO     Copying Kernel into ESP
kernelstub.Installer : INFO     Copying initrd.img into ESP
kernelstub.Installer : INFO     Setting up loader.conf configuration
kernelstub.Installer : INFO     Making entry file for Pop!_OS
kernelstub.Installer : INFO     Backing up old kernel
kernelstub.Installer : INFO     Making entry file for Pop!_OS
update-initramfs: Generating /boot/initrd.img-6.12.10-76061203-generic
kernelstub.Config    : INFO     Looking for configuration...
kernelstub           : INFO     System information:

OS:..................Pop!_OS 22.04
Root partition:....../dev/nvme0n1p1
Root FS UUID:........647e0206-eb25-4d00-a050-d3797e55d5c7
ESP Path:............/boot/efi
ESP Partition:......./dev/nvme0n1p3
ESP Partition #:.....3
NVRAM entry #:.......-1
Boot Variable #:.....0000
Kernel Boot Options:.quiet loglevel=0 systemd.show_status=false splash
Kernel Image Path:.../boot/vmlinuz-6.16.3-76061603-generic
Initrd Image Path:.../boot/initrd.img-6.16.3-76061603-generic
Force-overwrite:.....False

kernelstub.Installer : INFO     Copying Kernel into ESP
kernelstub.Installer : INFO     Copying initrd.img into ESP
kernelstub.Installer : INFO     Setting up loader.conf configuration
kernelstub.Installer : INFO     Making entry file for Pop!_OS
kernelstub.Installer : INFO     Backing up old kernel
kernelstub.Installer : INFO     Making entry file for Pop!_OS
[6/7] Create a 'libcamerify' helper (V4L2 compatibility via LD_PRELOAD) ...
- libcamerify installed (will no-op if compat lib not present).
[7/7] Restart user services (PipeWire/portal), then quick sanity checks...
Failed to connect to bus: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined (consider using --machine=<user>@.host --user to connect to bus of other user)
Failed to connect to bus: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined (consider using --machine=<user>@.host --user to connect to bus of other user)

Done. Now try:
1) cam -l                      # list detected cameras
2) cam -c 1 --stream           # quick preview from first camera
If your browser/app is V4L2-only, try:
libcamerify cheese             # or: libcamerify firefox

If 'cam -l' shows nothing, run:
journalctl -b -k | egrep -i 'ipu6|ov02c10|ivsc|vsc|intel'

```

command `dmsg` log snippets

```bash
[   13.740917] snd_hda_intel 0000:00:1f.3: Digital mics found on Skylake+ platform, using SOF driver
[   13.744985] Adding 16383480k swap on /dev/mapper/cryptswap.  Priority:-2 extents:1 across:16383480k SS
[   13.764667] audit: type=1400 audit(1758988696.753:2): apparmor="STATUS" operation="profile_load" profile="unconfined" name="libreoffice-xpdfimport" pid=748 comm="apparmor_parser"
[   13.764705] audit: type=1400 audit(1758988696.753:3): apparmor="STATUS" operation="profile_load" profile="unconfined" name="lsb_release" pid=738 comm="apparmor_parser"
[   13.764741] audit: type=1400 audit(1758988696.753:4): apparmor="STATUS" operation="profile_load" profile="unconfined" name="libreoffice-oosplash" pid=745 comm="apparmor_parser"
[   13.764805] audit: type=1400 audit(1758988696.753:5): apparmor="STATUS" operation="profile_load" profile="unconfined" name="nvidia_modprobe" pid=739 comm="apparmor_parser"
[   13.764808] audit: type=1400 audit(1758988696.753:6): apparmor="STATUS" operation="profile_load" profile="unconfined" name="nvidia_modprobe//kmod" pid=739 comm="apparmor_parser"
[   13.764904] audit: type=1400 audit(1758988696.753:7): apparmor="STATUS" operation="profile_load" profile="unconfined" name="libreoffice-senddoc" pid=746 comm="apparmor_parser"
[   13.764927] audit: type=1400 audit(1758988696.753:8): apparmor="STATUS" operation="profile_load" profile="unconfined" name="swtpm" pid=743 comm="apparmor_parser"
[   13.765053] audit: type=1400 audit(1758988696.753:9): apparmor="STATUS" operation="profile_load" profile="unconfined" name="/usr/bin/man" pid=742 comm="apparmor_parser"
[   13.765059] audit: type=1400 audit(1758988696.753:10): apparmor="STATUS" operation="profile_load" profile="unconfined" name="man_filter" pid=742 comm="apparmor_parser"
[   13.765062] audit: type=1400 audit(1758988696.753:11): apparmor="STATUS" operation="profile_load" profile="unconfined" name="man_groff" pid=742 comm="apparmor_parser"
[   13.769320] BUG: unable to handle page fault for address: 00000000ff78d008
[   13.769325] #PF: supervisor read access in kernel mode
[   13.769326] #PF: error_code(0x0000) - not-present page
[   13.769327] PGD 0 P4D 0 
[   13.769329] Oops: Oops: 0000 [#1] SMP NOPTI
[   13.769332] CPU: 0 UID: 0 PID: 555 Comm: systemd-udevd Tainted: P           OE       6.16.3-76061603-generic #202508231538~1758561135~22.04~171c8de PREEMPT(voluntary) 
[   13.769335] Tainted: [P]=PROPRIETARY_MODULE, [O]=OOT_MODULE, [E]=UNSIGNED_MODULE
[   13.769336] Hardware name: SAMSUNG ELECTRONICS CO., LTD. 960XGL/NP960XGL-XG2BR, BIOS P04ALX.320.240304.04 03/04/2024
[   13.769337] RIP: 0010:ipu6_psys_probe+0x314/0x5b0 [intel_ipu6_psys]
[   13.769345] Code: 20 4c 89 6b 28 49 89 86 30 04 00 00 41 83 ec 01 0f 85 5a ff ff ff 49 8b 87 b0 03 00 00 48 c7 c6 46 1c d7 c7 4c 89 ff 8b 5d c4 <48> 8b 40 08 41 89 46 18 89 c2 e8 fd c0 47 f0 44 0f b6 25 61 2a 6b
[   13.769346] RSP: 0018:ffffcafb4235f720 EFLAGS: 00010246
[   13.769348] RAX: 00000000ff78d000 RBX: 0000000000000000 RCX: 0000000000000000
[   13.769349] RDX: ffff8a240941a020 RSI: ffffffffc7d71c46 RDI: ffff8a2407748800
[   13.769350] RBP: ffffcafb4235f768 R08: 0000000000000000 R09: 0000000000000000
[   13.769351] R10: 0000000000000000 R11: 0000000000000000 R12: 0000000000000000
[   13.769351] R13: ffff8a241b680458 R14: ffff8a241b680028 R15: ffff8a2407748800
[   13.769352] FS:  00007bc7b12438c0(0000) GS:ffff8a2ba626a000(0000) knlGS:0000000000000000
[   13.769353] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
[   13.769354] CR2: 00000000ff78d008 CR3: 000000010b646003 CR4: 0000000000f70ef0
[   13.769356] PKRU: 55555554
[   13.769356] Call Trace:
[   13.769358]  <TASK>
[   13.769359]  ? __pfx_ipu6_psys_probe+0x10/0x10 [intel_ipu6_psys]
[   13.769364]  auxiliary_bus_probe+0x3e/0xa0
[   13.769368]  really_probe+0xee/0x3b0
[   13.769371]  __driver_probe_device+0x8c/0x180
[   13.769372]  driver_probe_device+0x24/0xd0
[   13.769374]  __driver_attach+0x10b/0x210
[   13.769375]  ? __pfx___driver_attach+0x10/0x10
[   13.769377]  bus_for_each_dev+0x89/0xf0
[   13.769378]  driver_attach+0x1e/0x30
[   13.769380]  bus_add_driver+0x14e/0x290
[   13.769381]  driver_register+0x5e/0x130
[   13.769383]  __auxiliary_driver_register+0x73/0xf0
[   13.769385]  ipu_psys_init+0x54/0xff0 [intel_ipu6_psys]
[   13.769389]  ? __pfx_ipu_psys_init+0x10/0x10 [intel_ipu6_psys]
[   13.769391]  do_one_initcall+0x5a/0x340
[   13.769395]  do_init_module+0x97/0x2c0
[   13.769397]  load_module+0x962/0xa80
[   13.769399]  init_module_from_file+0x95/0x100
[   13.769401]  idempotent_init_module+0x10f/0x300
[   13.769403]  __x64_sys_finit_module+0x73/0xe0
[   13.769404]  x64_sys_call+0x1ecd/0x2550
[   13.769405]  do_syscall_64+0x80/0xcb0
[   13.769409]  ? mmap_region+0x66/0xe0
[   13.769412]  ? vm_mmap_pgoff+0x157/0x200
[   13.769416]  ? ksys_mmap_pgoff+0x186/0x240
[   13.769418]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   13.769419]  ? do_syscall_64+0xb6/0xcb0
[   13.769421]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   13.769423]  ? do_syscall_64+0xb6/0xcb0
[   13.769425]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   13.769426]  ? do_syscall_64+0xb6/0xcb0
[   13.769428]  ? do_syscall_64+0xb6/0xcb0
[   13.769429]  ? fput_close_sync+0x3d/0xa0
[   13.769432]  ? __x64_sys_close+0x3e/0x90
[   13.769434]  ? arch_exit_to_user_mode_prepare.constprop.0+0xd/0xc0
[   13.769435]  ? do_syscall_64+0xb6/0xcb0
[   13.769437]  ? do_syscall_64+0xb6/0xcb0
[   13.769439]  ? common_interrupt+0x64/0xe0
[   13.769440]  entry_SYSCALL_64_after_hwframe+0x76/0x7e
[   13.769442] RIP: 0033:0x7bc7b111e8fd
[   13.769444] Code: 5b 41 5c c3 66 0f 1f 84 00 00 00 00 00 f3 0f 1e fa 48 89 f8 48 89 f7 48 89 d6 48 89 ca 4d 89 c2 4d 89 c8 4c 8b 4c 24 08 0f 05 <48> 3d 01 f0 ff ff 73 01 c3 48 8b 0d 03 b5 0f 00 f7 d8 64 89 01 48
[   13.769445] RSP: 002b:00007fffb3dbf0d8 EFLAGS: 00000246 ORIG_RAX: 0000000000000139
[   13.769446] RAX: ffffffffffffffda RBX: 0000567d00780390 RCX: 00007bc7b111e8fd
[   13.769447] RDX: 0000000000000000 RSI: 00007bc7b130a441 RDI: 0000000000000006
[   13.769448] RBP: 0000000000020000 R08: 0000000000000000 R09: 0000000000000002
[   13.769450] R10: 0000000000000006 R11: 0000000000000246 R12: 00007bc7b130a441
[   13.769451] R13: 0000567d00794920 R14: 0000567d00791240 R15: 0000567d00785800
[   13.769452]  </TASK>
[   13.769453] Modules linked in: snd_sof(+) snd_sof_utils snd_hda_ext_core snd_soc_acpi_intel_match binfmt_misc snd_soc_acpi_intel_sdca_quirks soundwire_generic_allocation snd_soc_acpi soundwire_bus snd_soc_sdca snd_soc_core intel_ipu6_psys(OE+) snd_compress ac97_bus snd_pcm_dmaengine crc8 snd_hda_intel intel_uncore_frequency snd_intel_dspcfg intel_uncore_frequency_common snd_intel_sdw_acpi iwlmvm(+) x86_pkg_temp_thermal intel_ipu6_isys intel_powerclamp v4l2_fwnode snd_hda_codec videobuf2_dma_sg nvidia_drm(POE+) videobuf2_memops videobuf2_v4l2 nvidia_modeset(POE) coretemp snd_hda_core videobuf2_common snd_hwdep mac80211 v4l2_async snd_pcm videodev kvm_intel mc dm_crypt libarc4 snd_seq_midi snd_seq_midi_event nvidia(POE) kvm nls_iso8859_1 snd_rawmidi iwlwifi btusb snd_seq btrtl btintel snd_seq_device btbcm btmtk snd_timer mei_gsc_proxy processor_thermal_device_pci intel_rapl_msr input_leds cmdlinepart irqbypass hid_sensor_als processor_thermal_device cfg80211 hid_sensor_trigger snd processor_thermal_wt_hint mei_me
[   13.769488]  bluetooth spi_nor platform_temperature_control rapl industrialio_triggered_buffer processor_thermal_rfim kfifo_buf mei soundcore mtd hid_multitouch(+) samsung_galaxybook serio_raw intel_cstate wmi_bmof gpio_keys hid_sensor_iio_common processor_thermal_rapl industrialio intel_rapl_common intel_ipu6 intel_vpu processor_thermal_wt_req processor_thermal_power_floor igen6_edac ipu_bridge processor_thermal_mbox firmware_attributes_class platform_profile intel_pmc_core int3403_thermal int340x_thermal_zone mac_hid pmt_telemetry pmt_class int3400_thermal acpi_thermal_rel intel_pmc_ssram_telemetry acpi_pad soc_button_array acpi_tad sch_fq_codel kyber_iosched msr parport_pc ppdev lp parport efi_pstore ip_tables x_tables autofs4 raid10 raid456 async_raid6_recov async_memcpy async_pq async_xor async_tx xor raid6_pq raid1 raid0 linear system76_io(OE) system76_acpi(OE) xe drm_gpuvm drm_gpusvm gpu_sched drm_ttm_helper drm_exec drm_suballoc_helper hid_sensor_custom hid_sensor_hub intel_ishtp_hid hid_logitech_hidpp i915
[   13.769524]  ucsi_acpi drm_buddy typec_ucsi ttm typec hid_logitech_dj i2c_algo_bit hid_generic drm_display_helper polyval_clmulni nvme ghash_clmulni_intel sha1_ssse3 intel_lpss_pci thunderbolt nvme_core i2c_i801 intel_lpss cec spi_intel_pci i2c_smbus usbhid intel_ish_ipc spi_intel idma64 i2c_mux nvme_keyring intel_ishtp intel_vsec rc_core nvme_auth i2c_hid_acpi i2c_hid hid video wmi pinctrl_meteorlake aesni_intel
[   13.769545] CR2: 00000000ff78d008
[   13.769547] ---[ end trace 0000000000000000 ]---
[   14.018520] RIP: 0010:ipu6_psys_probe+0x314/0x5b0 [intel_ipu6_psys]
[   14.018543] Code: 20 4c 89 6b 28 49 89 86 30 04 00 00 41 83 ec 01 0f 85 5a ff ff ff 49 8b 87 b0 03 00 00 48 c7 c6 46 1c d7 c7 4c 89 ff 8b 5d c4 <48> 8b 40 08 41 89 46 18 89 c2 e8 fd c0 47 f0 44 0f b6 25 61 2a 6b
[   14.018545] RSP: 0018:ffffcafb4235f720 EFLAGS: 00010246
[   14.018548] RAX: 00000000ff78d000 RBX: 0000000000000000 RCX: 0000000000000000
[   14.018549] RDX: ffff8a240941a020 RSI: ffffffffc7d71c46 RDI: ffff8a2407748800
[   14.018550] RBP: ffffcafb4235f768 R08: 0000000000000000 R09: 0000000000000000
[   14.018550] R10: 0000000000000000 R11: 0000000000000000 R12: 0000000000000000
[   14.018551] R13: ffff8a241b680458 R14: ffff8a241b680028 R15: ffff8a2407748800
[   14.018552] FS:  00007bc7b12438c0(0000) GS:ffff8a2ba626a000(0000) knlGS:0000000000000000
[   14.018553] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
[   14.018554] CR2: 00000000ff78d008 CR3: 000000010b646003 CR4: 0000000000f70ef0
[   14.018556] PKRU: 55555554
[   14.018557] note: systemd-udevd[555] exited with irqs disabled
```

```bash
[   21.600189] gst-plugin-scan[3415]: segfault at c ip 0000702371952456 sp 00007ffdc8eae0a0 error 6 in libcamera.so.0.1.0[75456,70237190c000+8b000] likely on CPU 10 (core 28, socket 0)
[   21.600198] Code: 00 00 4d 85 e4 74 0d 48 83 c4 08 4c 89 e0 5b 41 5c c3 66 90 4c 8b 25 c1 4d 07 00 48 89 c3 bf ba 00 00 00 31 c0 e8 9a a9 fb ff <41> 89 44 24 0c 4c 89 e0 4c 89 a3 20 00 00 00 48 83 c4 08 5b 41 5c
[   21.717188] gst-plugin-scan[3429]: segfault at c ip 0000754094d8a456 sp 00007ffc25c36540 error 6 in libcamera.so.0.1.0[75456,754094d44000+8b000] likely on CPU 11 (core 28, socket 0)
[   21.717197] Code: 00 00 4d 85 e4 74 0d 48 83 c4 08 4c 89 e0 5b 41 5c c3 66 90 4c 8b 25 c1 4d 07 00 48 89 c3 bf ba 00 00 00 31 c0 e8 9a a9 fb ff <41> 89 44 24 0c 4c 89 e0 4c 89 a3 20 00 00 00 48 83 c4 08 5b 41 5c
```

### System version

System description
```bash
➜  SamsungGalaxyNote git:(main) ✗ hostnamectl
 Static hostname: pop-os
       Icon name: computer-laptop
         Chassis: laptop
      Machine ID: 8328871196c857387d7234d366b2592f
         Boot ID: ef08c1ebd95741dab6c7aaab63513a88
Operating System: Pop!_OS 22.04 LTS               
          Kernel: Linux 6.16.3-76061603-generic
    Architecture: x86-64
 Hardware Vendor: SAMSUNG ELECTRONICS CO., LTD.
  Hardware Model: 960XGL
```
Services running:
```bash

➜  SamsungGalaxyNote git:(main) ✗ # All processes and services
ps aux && echo "=== SERVICES ===" && systemctl list-units --type=service --state=active
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.2  0.0 168024 13060 ?        Ss   12:58   0:01 /sbin/init splash
root           2  0.0  0.0      0     0 ?        S    12:58   0:00 [kthreadd]
root           3  0.0  0.0      0     0 ?        S    12:58   0:00 [pool_workqueue_release]
root           4  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-rcu_gp]
root           5  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-sync_wq]
root           6  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kvfree_rcu_reclaim]
root           7  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-slub_flushwq]
root           8  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-netns]
root          10  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/0:0H-events_highpri]
root          11  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/0:1-events]
root          12  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u88:0-i915]
root          13  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-mm_percpu_wq]
root          14  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/0]
root          15  0.1  0.0      0     0 ?        I    12:58   0:00 [rcu_preempt]
root          16  0.0  0.0      0     0 ?        S    12:58   0:00 [rcu_exp_par_gp_kthread_worker/1]
root          17  0.0  0.0      0     0 ?        S    12:58   0:00 [rcu_exp_gp_kthread_worker]
root          18  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/0]
root          19  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/0]
root          20  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/0]
root          21  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/1]
root          22  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/1]
root          23  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/1]
root          24  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/1]
root          26  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/1:0H-events_highpri]
root          27  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/3]
root          28  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/3]
root          29  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/3]
root          30  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/3]
root          31  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/3:0-events]
root          32  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/3:0H-events_highpri]
root          33  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/6]
root          34  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/6]
root          35  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/6]
root          36  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/6]
root          38  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/6:0H-events_highpri]
root          39  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/8]
root          40  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/8]
root          41  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/8]
root          42  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/8]
root          43  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/8:0-mm_percpu_wq]
root          44  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/8:0H-events_highpri]
root          45  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/10]
root          46  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/10]
root          47  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/10]
root          48  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/10]
root          49  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/10:0-mm_percpu_wq]
root          50  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/10:0H-events_highpri]
root          51  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/12]
root          52  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/12]
root          53  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/12]
root          54  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/12]
root          55  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/12:0-mm_percpu_wq]
root          56  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/12:0H-events_highpri]
root          57  0.0  0.0      0     0 ?        S    12:58   0:00 [rcu_exp_par_gp_kthread_worker/2]
root          58  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/13]
root          59  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/13]
root          60  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/13]
root          61  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/13]
root          62  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/13:0-mm_percpu_wq]
root          63  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/13:0H-events_highpri]
root          64  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/14]
root          65  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/14]
root          66  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/14]
root          67  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/14]
root          68  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/14:0-mm_percpu_wq]
root          69  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/14:0H-events_highpri]
root          70  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/15]
root          71  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/15]
root          72  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/15]
root          73  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/15]
root          74  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/15:0-cgroup_destroy]
root          75  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/15:0H-events_highpri]
root          76  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/16]
root          77  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/16]
root          78  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/16]
root          79  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/16]
root          80  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/16:0-events]
root          81  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/16:0H-events_highpri]
root          82  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/17]
root          83  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/17]
root          84  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/17]
root          85  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/17]
root          87  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/17:0H-events_highpri]
root          88  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/18]
root          89  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/18]
root          90  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/18]
root          91  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/18]
root          93  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/18:0H-events_highpri]
root          94  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/19]
root          95  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/19]
root          96  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/19]
root          97  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/19]
root          99  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/19:0H-events_highpri]
root         100  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/20]
root         101  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/20]
root         102  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/20]
root         103  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/20]
root         104  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/20:0-mm_percpu_wq]
root         105  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/20:0H-events_highpri]
root         106  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/21]
root         107  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/21]
root         108  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/21]
root         109  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/21]
root         110  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/21:0-events]
root         111  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/21:0H-events_highpri]
root         112  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/2]
root         113  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/2]
root         114  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/2]
root         115  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/2]
root         116  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/2:0-cgwb_release]
root         117  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/2:0H-events_highpri]
root         118  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/4]
root         119  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/4]
root         120  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/4]
root         121  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/4]
root         122  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/4:0-mm_percpu_wq]
root         123  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/4:0H-events_highpri]
root         124  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/5]
root         125  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/5]
root         126  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/5]
root         127  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/5]
root         128  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/5:0-events]
root         129  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/5:0H-events_highpri]
root         130  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/7]
root         131  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/7]
root         132  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/7]
root         133  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/7]
root         135  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/7:0H-events_highpri]
root         136  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/9]
root         137  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/9]
root         138  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/9]
root         139  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/9]
root         140  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/9:0-events]
root         141  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/9:0H-events_highpri]
root         142  0.0  0.0      0     0 ?        S    12:58   0:00 [cpuhp/11]
root         143  0.0  0.0      0     0 ?        S    12:58   0:00 [idle_inject/11]
root         144  0.0  0.0      0     0 ?        S    12:58   0:00 [migration/11]
root         145  0.0  0.0      0     0 ?        S    12:58   0:00 [ksoftirqd/11]
root         147  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/11:0H-events_highpri]
root         148  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u89:0-flush-259:0]
root         150  0.0  0.0      0     0 ?        S    12:58   0:00 [kdevtmpfs]
root         151  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-inet_frag_wq]
root         152  0.0  0.0      0     0 ?        I    12:58   0:00 [rcu_tasks_kthread]
root         153  0.0  0.0      0     0 ?        I    12:58   0:00 [rcu_tasks_rude_kthread]
root         154  0.0  0.0      0     0 ?        I    12:58   0:00 [rcu_tasks_trace_kthread]
root         155  0.0  0.0      0     0 ?        S    12:58   0:00 [kauditd]
root         156  0.0  0.0      0     0 ?        S    12:58   0:00 [khungtaskd]
root         157  0.5  0.0      0     0 ?        I    12:58   0:04 [kworker/u89:1-flush-259:0]
root         158  0.0  0.0      0     0 ?        S    12:58   0:00 [oom_reaper]
root         160  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-writeback]
root         161  0.0  0.0      0     0 ?        S    12:58   0:00 [kcompactd0]
root         162  0.0  0.0      0     0 ?        SN   12:58   0:00 [ksmd]
root         163  0.0  0.0      0     0 ?        SN   12:58   0:00 [khugepaged]
root         164  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kblockd]
root         165  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-blkcg_punt_bio]
root         166  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kintegrityd]
root         167  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/19:1-mm_percpu_wq]
root         168  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/9-acpi]
root         169  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/5:1-events]
root         170  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u88:1-i915]
root         171  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-tpm_dev_wq]
root         172  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-ata_sff]
root         173  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-md]
root         174  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-md_bitmap]
root         175  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-edac-poller]
root         176  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-devfreq_wq]
root         177  0.0  0.0      0     0 ?        S    12:58   0:00 [watchdogd]
root         178  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/19:1H-i915_cleanup]
root         179  0.0  0.0      0     0 ?        S    12:58   0:00 [kswapd0]
root         180  0.0  0.0      0     0 ?        S    12:58   0:00 [ecryptfs-kthread]
root         181  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kthrotld]
root         182  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/124-pciehp]
root         183  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/16:1-mm_percpu_wq]
root         184  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/125-pciehp]
root         186  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-acpi_thermal_pm]
root         187  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/21:1-events]
root         188  0.0  0.0      0     0 ?        S    12:58   0:00 [hwrng]
root         189  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/1:1-events]
root         190  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-hfi-updates]
root         192  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-mld]
root         193  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/3:1H-i915_cleanup]
root         194  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-ipv6_addrconf]
root         198  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/2:1-mm_percpu_wq]
root         200  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/15:3-mm_percpu_wq]
root         205  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/20:1-events]
root         206  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/7:1-mm_percpu_wq]
root         207  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/10:1-mm_percpu_wq]
root         209  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/8:1-events]
root         210  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/11:1-events]
root         211  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/18:1-events]
root         212  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/17:1-cgroup_destroy]
root         214  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/14:1-events]
root         215  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/12:1-events]
root         221  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kstrp]
root         223  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/u91:0-hci0]
root         224  0.3  0.0      0     0 ?        I<   12:58   0:02 [kworker/u92:0-i915_flip]
root         225  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/u93:0-i915_flip]
root         236  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-charger_manager]
root         237  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/15:1H-i915_cleanup]
root         238  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/10:1H-i915_cleanup]
root         259  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/12:1H-i915_cleanup]
root         263  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/1:1H-i915_cleanup]
root         274  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/8:1H-i915_cleanup]
root         275  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/5:1H-i915_cleanup]
root         276  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/6:1H-i915_cleanup]
root         278  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/13:1H-i915_cleanup]
root         279  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/14:1H-i915_cleanup]
root         281  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/17:1H-i915_cleanup]
root         283  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/16:1H-i915_cleanup]
root         288  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/18:1H-i915_cleanup]
root         307  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/4:1H-i915_cleanup]
root         308  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/9:1H-i915_cleanup]
root         309  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/7:1H-i915_cleanup]
root         312  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/11:1H-i915_cleanup]
root         322  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-nvme-wq]
root         324  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-nvme-reset-wq]
root         326  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-nvme-delete-wq]
root         327  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-nvme-auth-wq]
root         338  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/2:1H-kblockd]
root         339  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/0:1H-i915_cleanup]
root         340  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/160-ZNT0001:00]
root         341  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/113-GXTP7936:00]
root         343  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u89:5-events_unbound]
root         345  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/4:2-events]
root         346  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-USBC000:00-con1]
root         347  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-USBC000:00-con2]
root         348  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-ttm]
root         349  0.0  0.0      0     0 ?        S    12:58   0:00 [card1-crtc0]
root         350  0.0  0.0      0     0 ?        S    12:58   0:00 [card1-crtc1]
root         351  0.0  0.0      0     0 ?        S    12:58   0:00 [card1-crtc2]
root         352  0.0  0.0      0     0 ?        S    12:58   0:00 [card1-crtc3]
root         354  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/1:2-events]
root         356  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/3:2-mm_percpu_wq]
root         388  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-raid5wq]
root         431  0.0  0.0      0     0 ?        S    12:58   0:00 [jbd2/nvme0n1p1-8]
root         432  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-ext4-rsv-conversion]
root         482  0.1  0.2 184740 84324 ?        SNs  12:58   0:01 /lib/systemd/systemd-journald
root         518  0.0  0.0  27192  6984 ?        SNs  12:58   0:00 /lib/systemd/systemd-udevd
root         563  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/21:1H-i915_cleanup]
root         565  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/20:1H-i915_cleanup]
root         582  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/19:2-events]
root         613  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/0:2-events]
root         619  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/16-intel-ipu6]
root         622  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/186-mei_me]
root         637  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/17:2-mm_percpu_wq]
root         652  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-cfg80211]
root         656  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/16-processor_thermal_device_pci]
root         659  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/u91:1-hci0]
root         666  0.0  0.0      0     0 ?        S    12:58   0:00 [jbd2/nvme0n1p4-8]
root         668  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-ext4-rsv-conversion]
root         670  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/189-iwlwifi:default_queue]
root         671  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/190-iwlwifi:queue_1]
root         672  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/191-iwlwifi:queue_2]
root         673  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/192-iwlwifi:queue_3]
root         674  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/193-iwlwifi:queue_4]
root         675  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/194-iwlwifi:queue_5]
root         676  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/195-iwlwifi:queue_6]
root         677  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/196-iwlwifi:queue_7]
root         678  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/197-iwlwifi:queue_8]
root         679  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/198-iwlwifi:queue_9]
root         680  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/199-iwlwifi:queue_10]
root         681  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/200-iwlwifi:queue_11]
root         682  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/201-iwlwifi:queue_12]
root         683  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/202-iwlwifi:queue_13]
root         684  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/203-iwlwifi:queue_14]
root         685  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/204-iwlwifi:exception]
root         691  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kdmflush/252:0]
root         694  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kcryptd_io-252:0-1]
root         695  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/R-kcryptd-252:0-1]
root         696  0.0  0.0      0     0 ?        S    12:58   0:00 [dmcrypt_write/252:0]
root         700  0.0  0.0      0     0 ?        S    12:58   0:00 [nv_queue]
root         701  0.0  0.0      0     0 ?        S    12:58   0:00 [nv_queue]
root         702  0.0  0.0      0     0 ?        S    12:58   0:00 [nv_open_q]
root         708  0.0  0.0      0     0 ?        S    12:58   0:00 [nvidia-modeset/kthread_q]
root         709  0.0  0.0      0     0 ?        S    12:58   0:00 [nvidia-modeset/deferred_close_kthread_q]
systemd+     755  0.0  0.0  26688 14660 ?        SNs  12:58   0:00 /lib/systemd/systemd-resolved
root         757  0.0  0.0      0     0 ?        S    12:58   0:00 [psys_sched_cmd]
root         810  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/9:2-events]
message+     813  0.0  0.0  10444  4788 ?        SNs  12:58   0:00 /usr/bin/dbus-broker-launch --scope system --audit
root         815  0.0  0.0      0     0 ?        S    12:58   0:00 [irq/205-AudioDSP]
message+     816  0.1  0.0   9712  7336 ?        S    12:58   0:01 dbus-broker --log 4 --controller 9 --machine-id 8328871196c857387d7234d366b2592f --max-bytes 536870912 --max-fds 4096 --max-matches 131072 --audit
root         818  0.0  0.0 271432 19928 ?        SNsl 12:58   0:00 /usr/sbin/NetworkManager --no-daemon
root         822  0.0  0.0 250816  8672 ?        SNsl 12:58   0:00 /usr/libexec/accounts-daemon
root         823  0.0  0.0   2824  2036 ?        SNs  12:58   0:00 /usr/sbin/acpid
avahi        825  0.0  0.0   7872  4156 ?        SNs  12:58   0:00 avahi-daemon: running [pop-os.local]
root         826  0.0  0.0  10720  5476 ?        SNs  12:58   0:00 /usr/lib/bluetooth/bluetoothd
root         827  0.0  0.0 144144  6344 ?        SNs  12:58   0:00 /usr/bin/system76-power daemon
root         828  0.0  0.0  84244 11292 ?        SNsl 12:58   0:00 /usr/bin/system76-scheduler daemon
root         829  0.0  0.0  19308  2880 ?        SNs  12:58   0:00 /usr/sbin/cron -f -P
root         833  0.0  0.0 246552  6848 ?        SNsl 12:58   0:00 /usr/libexec/iio-sensor-proxy
root         834  0.0  0.0  45360 19608 ?        SNs  12:58   0:00 /usr/bin/python3 /usr/bin/networkd-dispatcher --run-startup-triggers
root         835  0.1  0.2 5665352 70476 ?       SNsl 12:58   0:01 /usr/sbin/nordvpnd
root         836  4.1  0.0 177768  9204 ?        SNsl 12:58   0:33 /usr/bin/nvidia-powerd
root         837  0.0  0.0 237228 10084 ?        SNsl 12:58   0:00 /usr/libexec/polkitd --no-debug
syslog       842  0.0  0.0 222624  6040 ?        SNsl 12:58   0:00 /usr/sbin/rsyslogd -n -iNONE
root         848  0.0  0.0 246304  6456 ?        SNsl 12:58   0:00 /usr/libexec/switcheroo-control
root         853  0.0  0.0  48780  8180 ?        SNs  12:58   0:00 /lib/systemd/systemd-logind
root         855  0.0  0.0  15060  6872 ?        SNs  12:58   0:00 /lib/systemd/systemd-machined
root         859  0.0  0.0 286120 10832 ?        SNsl 12:58   0:00 /usr/sbin/thermald --systemd --dbus-enable --adaptive
root         860  0.0  0.0 332664 14892 ?        SNsl 12:58   0:00 /usr/bin/touchegg --daemon
root         861  0.0  0.0 396424 13228 ?        SNsl 12:58   0:00 /usr/libexec/udisks2/udisksd
root         866  0.0  0.0  18064 11784 ?        SNs  12:58   0:00 /sbin/wpa_supplicant -u -s -O /run/wpa_supplicant
avahi        871  0.0  0.0   7528  1732 ?        SN   12:58   0:00 avahi-daemon: chroot helper
root         881  0.0  0.0 318060 12288 ?        SNsl 12:58   0:00 /usr/sbin/ModemManager
root         884  0.0  0.0 250148  7860 ?        SNsl 12:58   0:00 /usr/libexec/boltd
root         892  0.0  0.0 252332  9264 ?        SNsl 12:58   0:00 /usr/libexec/upowerd
root         894  0.2  0.0      0     0 ?        I<   12:58   0:02 [kworker/u92:1-i915_flip]
root         901  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u90:2-events_unbound]
root         988  0.4  0.6 323784 204432 ?       SN   12:58   0:03 /usr/bin/python3 /usr/sbin/execsnoop-bpfcc
root        1014  0.0  0.0  82928 13720 ?        Ss   12:58   0:00 /usr/sbin/cupsd -l
root        1017  0.0  0.0 1562920 25548 ?       Ssl  12:58   0:00 /usr/sbin/libvirtd
root        1020  0.0  0.1 2468272 46308 ?       Ssl  12:58   0:00 /usr/bin/containerd
_chrony     1038  0.0  0.0  18920  3832 ?        S    12:58   0:00 /usr/sbin/chronyd -F 1
_chrony     1053  0.0  0.0  10724  3092 ?        S    12:58   0:00 /usr/sbin/chronyd -F 1
fernand+    1054  0.0  0.0  18060 10696 ?        Ss   12:58   0:00 /lib/systemd/systemd --user
lp          1062  0.0  0.0  16384  6544 ?        S    12:58   0:00 /usr/lib/cups/notifier/dbus dbus://
fernand+    1077  0.0  0.0 171460  5880 ?        S    12:58   0:00 (sd-pam)
fernand+    1126  0.3  0.0 128980 16252 ?        Ssl  12:58   0:02 /usr/bin/pipewire
fernand+    1128  0.0  0.0 347056 18028 ?        Ssl  12:58   0:00 /usr/bin/wireplumber
fernand+    1129  0.3  0.0 121816 17420 ?        SLsl 12:58   0:02 /usr/bin/pipewire-pulse
fernand+    1134  0.0  0.0   9756  4092 ?        Ss   12:58   0:00 /usr/bin/dbus-broker-launch --scope user
root        1140  0.0  0.1 413040 41888 ?        Ssl  12:58   0:00 /usr/libexec/fwupd/fwupd
fernand+    1148  0.0  0.0   7196  4804 ?        S    12:58   0:00 dbus-broker --log 4 --controller 10 --machine-id 8328871196c857387d7234d366b2592f --max-bytes 100000000000000 --max-fds 25000000000000 --max-matches 5000000000
rtkit       1153  0.0  0.0 154088  3368 ?        SNsl 12:58   0:00 /usr/libexec/rtkit-daemon
root        1166  0.3  0.0      0     0 ?        S    12:58   0:02 [irq/206-nvidia]
root        1167  0.0  0.0      0     0 ?        S    12:58   0:00 [nvidia]
root        1168  0.0  0.0      0     0 ?        S    12:58   0:00 [nv_queue]
root        1172  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u89:6-kvfree_rcu_reclaim]
root        1173  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u89:7-events_unbound]
libvirt+    1382  0.0  0.0  10176  1940 ?        S    12:58   0:00 /usr/sbin/dnsmasq --conf-file=/var/lib/libvirt/dnsmasq/default.conf --leasefile-ro --dhcp-script=/usr/lib/libvirt/libvirt_leaseshelper
root        1383  0.0  0.0  10176  1012 ?        S    12:58   0:00 /usr/sbin/dnsmasq --conf-file=/var/lib/libvirt/dnsmasq/default.conf --leasefile-ro --dhcp-script=/usr/lib/libvirt/libvirt_leaseshelper
root        1461  0.0  0.0      0     0 ?        S    12:58   0:00 [UVM global queue]
root        1462  0.0  0.0      0     0 ?        S    12:58   0:00 [UVM deferred release queue]
root        1463  0.0  0.0      0     0 ?        S    12:58   0:00 [UVM Tools Event Queue]
nvidia-+    1469  0.0  0.0   3432  2144 ?        Ss   12:58   0:00 /usr/bin/nvidia-persistenced --user nvidia-persistenced --no-persistence-mode --verbose
root        1472  0.0  0.0 251128  9636 ?        SNsl 12:58   0:00 /usr/sbin/gdm3
root        1480  0.0  0.0 182072 11236 ?        SNl  12:58   0:00 gdm-session-worker [pam/gdm-autologin]
fernand+    1486  0.0  0.0 398400  8712 ?        SLl  12:58   0:00 /usr/bin/gnome-keyring-daemon --daemonize --login
fernand+    1491  0.0  0.0 172248  6036 tty2     SNsl+ 12:58   0:00 /usr/libexec/gdm-x-session --run-script env GNOME_SHELL_SESSION_MODE=pop /usr/bin/gnome-session --session=pop
fernand+    1493  6.9  1.0 26148244 341212 tty2  R<l+ 12:58   0:57 /usr/lib/xorg/Xorg vt2 -displayfd 3 -auth /run/user/1000/gdm/Xauthority -nolisten tcp -background none -noreset -keeptty -novtswitch -verbose 3
root        1503  0.0  0.0      0     0 ?        S<   12:58   0:00 [krfcommd]
root        1510  0.0  0.0 1571160 9772 ?        SNsl 12:58   0:00 /usr/bin/pop-system-updater
root        1523  0.0  0.0 172180 11244 ?        SNsl 12:58   0:00 /usr/sbin/cups-browsed
root        1524  0.0  0.2 2785976 72784 ?       SNsl 12:58   0:00 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
root        1525  0.0  0.0  81196 15500 ?        SNs  12:58   0:00 /usr/sbin/nmbd --foreground --no-process-group
ollama      1526  0.1  0.4 7363528 155936 ?      SNsl 12:58   0:01 /usr/local/bin/ollama serve
root        1631  0.0  0.0      0     0 ?        S    12:58   0:00 [vidmem lazy free]
root        1633  0.0  0.0  97112 24116 ?        SNs  12:58   0:00 /usr/sbin/smbd --foreground --no-process-group
root        1638  0.0  0.0  93828 11416 ?        SNl  12:58   0:00 /usr/bin/system76-scheduler pipewire
root        1652  0.0  0.0  94972 10028 ?        SN   12:58   0:00 /usr/sbin/smbd --foreground --no-process-group
root        1653  0.0  0.0  94964  7984 ?        SN   12:58   0:00 /usr/sbin/smbd --foreground --no-process-group
root        1656  0.0  0.0      0     0 ?        S    12:58   0:00 [UVM GPU1 BH]
root        1657  0.0  0.0      0     0 ?        S    12:58   0:00 [UVM GPU1 KC]
root        1664  0.0  0.0  97520 20508 ?        SN   12:58   0:00 /usr/lib/x86_64-linux-gnu/samba/samba-bgqd --ready-signal-fd=45 --parent-watch-fd=11 --debuglevel=0 -F
fernand+    2539  0.0  0.0 233556 15832 tty2     SNl+ 12:58   0:00 /usr/libexec/gnome-session-binary --session=pop
fernand+    2547  0.0  0.0 2274512 18916 ?       SNl  12:58   0:00 /usr/lib/nordvpn/norduserd
fernand+    2611  0.0  0.0 309916  8392 ?        SNsl 12:58   0:00 /usr/libexec/at-spi-bus-launcher
fernand+    2616  0.0  0.0   9608  3780 ?        SN   12:58   0:00 /usr/bin/dbus-broker-launch --config-file=/usr/share/defaults/at-spi2/accessibility.conf --scope user
fernand+    2617  0.0  0.0   5036  2648 ?        S    12:58   0:00 dbus-broker --log 4 --controller 9 --machine-id 8328871196c857387d7234d366b2592f --max-bytes 100000000000000 --max-fds 6400000 --max-matches 5000000000
fernand+    2696  0.0  0.0 101804  5484 ?        SNsl 12:58   0:00 /usr/libexec/gnome-session-ctl --monitor
fernand+    2706  0.0  0.0 250508  8008 ?        SNsl 12:58   0:00 /usr/libexec/gvfsd
fernand+    2714  0.0  0.0 380908  6984 ?        SNl  12:58   0:00 /usr/libexec/gvfsd-fuse /run/user/1000/gvfs -f
fernand+    2716  0.0  0.0 530040 17952 ?        SNsl 12:58   0:00 /usr/libexec/gnome-session-binary --systemd-service --session=pop
fernand+    2744  2.4  1.6 5702384 533652 ?      S<sl 12:58   0:20 /usr/bin/gnome-shell
root        2850  0.8  0.1 384252 52164 ?        SNsl 12:58   0:06 /usr/libexec/packagekitd
root        2854  0.0  0.0      0     0 ?        S    12:58   0:00 [nvidia-drm/timeline-1b]
root        3005  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/6:3-events]
fernand+    3015  0.0  0.0 796800 22196 ?        SNsl 12:58   0:00 /usr/libexec/gnome-shell-calendar-server
fernand+    3016  0.0  0.0 245976  6132 ?        SNsl 12:58   0:00 /usr/libexec/xdg-permission-store
fernand+    3025  0.0  0.1 554140 33840 ?        SNsl 12:58   0:00 /usr/libexec/evolution-source-registry
fernand+    3032  0.0  0.2 600604 69564 ?        SNLsl 12:58   0:00 /usr/libexec/goa-daemon
fernand+    3033  0.0  0.0 157480  6480 ?        SNsl 12:58   0:00 /usr/libexec/dconf-service
fernand+    3036  0.0  0.0 174184  7864 ?        SNsl 12:58   0:00 /usr/libexec/gvfsd-metadata
geoclue     3042  0.0  0.0 923848 29432 ?        SNsl 12:58   0:00 /usr/libexec/geoclue
fernand+    3046  0.0  0.0 348608 15448 ?        SNsl 12:58   0:00 /usr/libexec/goa-identity-service
fernand+    3055  0.0  0.0 326020 10408 ?        SNsl 12:58   0:00 /usr/libexec/gvfs-udisks2-volume-monitor
fernand+    3056  0.0  0.1 1223220 46200 ?       SNsl 12:58   0:00 /usr/libexec/evolution-calendar-factory
fernand+    3067  0.0  0.0 247364  7264 ?        SNsl 12:58   0:00 /usr/libexec/gvfs-gphoto2-volume-monitor
fernand+    3071  0.0  0.0 325028  8148 ?        SNsl 12:58   0:00 /usr/libexec/gvfs-afc-volume-monitor
fernand+    3076  0.0  0.0 247064  7632 ?        SNsl 12:58   0:00 /usr/libexec/gvfs-goa-volume-monitor
fernand+    3084  0.0  0.0 246276  6740 ?        SNsl 12:58   0:00 /usr/libexec/gvfs-mtp-volume-monitor
fernand+    3091  0.0  0.0 458052  8800 ?        SNsl 12:58   0:00 /usr/libexec/glib-pacrunner
fernand+    3097  0.0  0.0 682388 29140 ?        SNsl 12:58   0:00 /usr/libexec/evolution-addressbook-factory
fernand+    3129  0.0  0.0 2875580 27984 ?       SNsl 12:58   0:00 /usr/bin/gjs /usr/share/gnome-shell/org.gnome.Shell.Notifications
fernand+    3130  0.0  0.0 162908  7892 ?        SNsl 12:58   0:00 /usr/libexec/at-spi2-registryd --use-gnome-session
fernand+    3146  0.0  0.0   2900  1732 ?        SNs  12:58   0:00 sh -c /usr/bin/ibus-daemon --panel disable $([ "$XDG_SESSION_TYPE" = "x11" ] && echo "--xim")
fernand+    3147  0.0  0.0 320452  7080 ?        SNsl 12:58   0:00 /usr/libexec/gsd-a11y-settings
fernand+    3149  0.0  0.0 487444 30852 ?        SNsl 12:58   0:00 /usr/libexec/gsd-color
fernand+    3152  0.0  0.0 440260 12000 ?        SNsl 12:58   0:00 /usr/libexec/gsd-datetime
fernand+    3153  0.2  0.0 325068 12052 ?        SNl  12:58   0:01 /usr/bin/ibus-daemon --panel disable --xim
fernand+    3154  0.0  0.0 322188  8484 ?        SNsl 12:58   0:00 /usr/libexec/gsd-housekeeping
fernand+    3156  0.0  0.0 354020 26272 ?        SNsl 12:58   0:00 /usr/libexec/gsd-keyboard
fernand+    3157  0.0  0.0 537804 31340 ?        SNsl 12:58   0:00 /usr/libexec/gsd-media-keys
fernand+    3161  0.0  0.0 463984 29472 ?        SNsl 12:58   0:00 /usr/libexec/gsd-power
fernand+    3162  0.0  0.2 1112904 69292 ?       SNl  12:58   0:00 /usr/libexec/evolution-data-server/evolution-alarm-notify
fernand+    3165  0.0  0.0 259776 11372 ?        SNsl 12:58   0:00 /usr/libexec/gsd-print-notifications
fernand+    3166  0.0  0.0 467680  6876 ?        SNsl 12:58   0:00 /usr/libexec/gsd-rfkill
fernand+    3169  0.0  0.0 246112  6216 ?        SNsl 12:58   0:00 /usr/libexec/gsd-screensaver-proxy
fernand+    3171  0.0  0.0 476112 11628 ?        SNsl 12:58   0:00 /usr/libexec/gsd-sharing
fernand+    3174  0.0  0.0 322332  8452 ?        SNsl 12:58   0:00 /usr/libexec/gsd-smartcard
fernand+    3177  0.0  0.0 333580 10080 ?        SNsl 12:58   0:00 /usr/libexec/gsd-sound
fernand+    3181  0.0  0.0 354236 26336 ?        SNsl 12:58   0:00 /usr/libexec/gsd-wacom
fernand+    3183  0.0  0.0 356284 29396 ?        SNsl 12:58   0:00 /usr/libexec/gsd-xsettings
fernand+    3184  0.0  0.0 232284  7384 ?        SNl  12:58   0:00 /usr/libexec/gsd-disk-utility-notify
fernand+    3192  0.0  0.0 193008 14160 ?        SNl  12:58   0:00 touchegg
fernand+    3206  0.0  0.0 263816 20476 ?        SNl  12:58   0:00 /usr/bin/python3 /usr/lib/hidpi-daemon/hidpi-notification
fernand+    3215  0.0  0.1 445264 47032 ?        SNl  12:58   0:00 /usr/bin/python3 /usr/lib/hidpi-daemon/hidpi-daemon
fernand+    3252  0.0  0.0 173300  7352 ?        SNl  12:58   0:00 /usr/libexec/ibus-memconf
fernand+    3253  0.1  0.0 283348 30368 ?        SNl  12:58   0:01 /usr/libexec/ibus-extension-gtk3
fernand+    3255  0.1  0.0 206204 26448 ?        SNl  12:58   0:01 /usr/libexec/ibus-x11 --kill-daemon
fernand+    3260  0.0  0.0 247080  7528 ?        SNsl 12:58   0:00 /usr/libexec/ibus-portal
fernand+    3266  0.0  0.0 352580 14896 ?        SNl  12:58   0:00 /usr/libexec/gsd-printer
fernand+    3285  0.0  0.0 1250668 23556 ?       SNl  12:58   0:00 op daemon
colord      3314  0.0  0.0 255556 13512 ?        SNsl 12:58   0:00 /usr/libexec/colord
fernand+    3390  0.0  0.0 2883764 28120 ?       SNsl 12:58   0:00 /usr/bin/gjs /usr/share/gnome-shell/org.gnome.ScreenSaver
fernand+    3408  0.0  0.0 173300  7476 ?        SNl  12:58   0:00 /usr/libexec/ibus-engine-simple
fernand+    3412  0.0  0.0 648292 32176 ?        DNsl 12:58   0:00 /usr/libexec/tracker-miner-fs-3
root        3449  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/11:2]
root        3478  0.1  0.0      0     0 ?        I<   12:58   0:00 [kworker/u92:2-i915_flip]
root        3480  0.0  0.3 146972 117596 ?       SNs  12:58   0:00 /usr/bin/python3 /usr/lib/pop-transition/service.py
fernand+    3490  0.0  0.1 3048036 56996 ?       SNl  12:58   0:00 gjs /usr/share/gnome-shell/extensions/ding@rastersoft.com/ding.js -E -P /usr/share/gnome-shell/extensions/ding@rastersoft.com -M 1 -D 0:0:3840:2160:1:0:0:0:0:0 -D 3840:360:2880:1800:1:40:0:0:0:1
fernand+    3506  0.0  0.0 324576  8952 ?        SNl  12:58   0:00 /usr/libexec/gvfsd-trash --spawner :1.24 /org/gtk/gvfs/exec_spaw/0
fernand+    3513  0.1  0.0 560252 14524 ?        SNsl 12:58   0:01 /usr/libexec/xdg-desktop-portal
fernand+    3517  0.0  0.0 473068  7528 ?        SNsl 12:58   0:00 /usr/libexec/xdg-document-portal
root        3522  0.0  0.0   2804  1976 ?        SNs  12:58   0:00 fusermount3 -o rw,nosuid,nodev,fsname=portal,auto_unmount,subtype=portal -- /run/user/1000/doc
fernand+    3526  0.1  0.3 738492 113300 ?       SNsl 12:58   0:01 /usr/libexec/xdg-desktop-portal-gnome
fernand+    3544  0.0  0.0 354636 28268 ?        SNsl 12:58   0:00 /usr/libexec/xdg-desktop-portal-gtk
fernand+    3598  0.0  0.0 1570856 9572 ?        SNsl 12:58   0:00 /usr/bin/pop-system-updater
root        3654  0.0  0.0      0     0 ?        I    12:58   0:00 [kworker/u89:9-flush-259:0]
fernand+    3687  3.0  1.6 2138176 531732 ?      SNLl 12:58   0:24 /home/fernandoavanzo/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox --minimize
root        3911  0.0  0.0      0     0 ?        I<   12:58   0:00 [kworker/u93:1-i915_flip]
fernand+    3928  0.0  0.0 444328 25812 ?        SNl  12:58   0:00 /usr/libexec/gvfsd-google --spawner :1.24 /org/gtk/gvfs/exec_spaw/1
fernand+    4007  0.0  0.2 1291292 66068 ?       SNsl 12:58   0:00 /usr/bin/rclone mount remote: /mnt/data/gdrive/avanzo-drive --file-perms 0777 --dir-perms 0777 --vfs-cache-mode full
fernand+    5884  1.3  0.9 2232408 321592 ?      S<Ll 12:59   0:09 obs
root        5899  0.0  0.0      0     0 ?        S    12:59   0:00 [nvidia-drm/timeline-22]
root        5902  0.0  0.0      0     0 ?        S    12:59   0:00 [nvidia-drm/timeline-23]
root        5916  0.0  0.0      0     0 ?        S    12:59   0:00 [nvidia-drm/timeline-24]
fernand+    5950  133 20.3 35177316 6592092 ?    SLl  13:00  15:48 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/bin/idea
fernand+    6105  0.0  0.0   1124   436 ?        S    13:00   0:00 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/bin/fsnotifier
fernand+    6182  0.2  0.3 22308584 106972 ?     Sl   13:00   0:01 CodeStream
fernand+    6203  0.0  0.4 2312108 132840 ?      SLl  13:00   0:00 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/jbr/lib/cef_server --port=6188 --logfile=/home/fernandoavanzo/.cache/JetBrains/IntelliJIdea2025.2/log/jcef_5950.log --loglevel=100 --params=/tmp/cef_server_params.t
fernand+    6206  0.0  0.1 34102848 56464 ?      S    13:00   0:00 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/jbr/lib/cef_server --type=zygote --no-zygote-sandbox --no-sandbox --force-device-scale-factor=1.25 --log-severity=disable --lang=en-US --user-data-dir=/home/fernand
fernand+    6207  0.0  0.1 34102840 56460 ?      S    13:00   0:00 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/jbr/lib/cef_server --type=zygote --no-sandbox --force-device-scale-factor=1.25 --log-severity=disable --lang=en-US --user-data-dir=/home/fernandoavanzo/.cache/JetBr
fernand+    6226  0.0  0.4 34860616 158464 ?     Sl   13:00   0:00 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/jbr/lib/cef_server --type=gpu-process --no-sandbox --log-severity=disable --lang=en-US --user-data-dir=/home/fernandoavanzo/.cache/JetBrains/IntelliJIdea2025.2/jcef
fernand+    6248  0.0  0.1 34398312 36668 ?      Sl   13:00   0:00 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/jbr/lib/cef_server --type=utility --utility-sub-type=storage.mojom.StorageService --lang=en-US --service-sandbox-type=utility --no-sandbox --log-severity=disable --
fernand+    6253  0.0  0.2 876608 74216 ?        Sl   13:00   0:00 /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/jbr/lib/cef_server --type=utility --utility-sub-type=network.mojom.NetworkService --lang=en-US --service-sandbox-type=none --no-sandbox --log-severity=disable --lan
root        6262  0.0  0.0      0     0 ?        S    13:00   0:00 [nvidia-drm/timeline-25]
fernand+    6274  0.0  0.0  25068  8800 pts/0    Ss   13:00   0:00 /usr/bin/zsh -i
fernand+    6778  0.6  0.7 1452676 228944 ?      Sl   13:00   0:04 /home/fernandoavanzo/.nvm/versions/node/v22.13.0/bin/node /home/fernandoavanzo/Applications/jetbrains/toolbox/apps/intellij-idea-ultimate/plugins/tailwindcss/server/tailwindcss-language-server
fernand+    6882  0.1  0.2 2494824 87032 ?       Sl   13:00   0:00 /home/fernandoavanzo/.cache/JetBrains/IntelliJIdea2025.2/semantic-search/server/3.0.169/embeddings-server --model-path /home/fernandoavanzo/.cache/JetBrains/IntelliJIdea2025.2/semantic-search/models/0.0.5/small/dan_100k_optimized.onnx --vocab-p
root        6959  0.0  0.0      0     0 ?        I    13:00   0:00 [kworker/u90:3-flush-259:0]
root        6960  0.0  0.0      0     0 ?        I    13:00   0:00 [kworker/u90:4-flush-259:0]
root       34326  0.0  0.0      0     0 ?        I<   13:03   0:00 [kworker/u92:3-rb_allocator]
root       34489  0.0  0.0      0     0 ?        I    13:04   0:00 [kworker/13:1]
root       34614  0.0  0.0      0     0 ?        I    13:04   0:00 [kworker/7:0]
ollama     34693  9.4  8.1 48826576 2630508 ?    SNl  13:05   0:35 /usr/local/lib/ollama/runners/cuda_v12_avx/ollama_llama_server runner --model /usr/share/ollama/.ollama/models/blobs/sha256-dde5aa3fc5ffc17176b5e8bdc82f587b24b2678c6c66101bf7da77af9f7ccdff --ctx-size 16384 --batch-size 512 --n-gpu-layers 27 --t
root       34705  0.0  0.0      0     0 ?        I    13:05   0:00 [kworker/6:0]
root       36298  0.0  0.0      0     0 ?        I    13:06   0:00 [kworker/18:0-events]
root       38316  0.4  0.0      0     0 ?        I<   13:08   0:00 [kworker/u92:4-i915_flip]
root       38345  0.0  0.0      0     0 ?        I    13:08   0:00 [kworker/u89:2-flush-259:0]
root       38352  0.0  0.0      0     0 ?        I    13:08   0:00 [kworker/u89:3-flush-259:0]
root       38356  0.0  0.0      0     0 ?        I<   13:08   0:00 [kworker/u93:2]
root       38358  0.0  0.0      0     0 ?        I    13:08   0:00 [kworker/3:1]
root       38388  0.0  0.0      0     0 ?        I    13:09   0:00 [kworker/u90:0-flush-259:0]
root       38456  0.0  0.0      0     0 ?        I    13:10   0:00 [kworker/1:0-mm_percpu_wq]
root       38513  0.0  0.0      0     0 ?        I    13:11   0:00 [kworker/9:1-events]
root       38525  0.0  0.0      0     0 ?        I    13:11   0:00 [kworker/18:2-mm_percpu_wq]
fernand+   38555  0.0  0.0  22568  3568 pts/0    R+   13:11   0:00 ps aux
=== SERVICES ===
UNIT                                                             LOAD   ACTIVE SUB     DESCRIPTION
accounts-daemon.service                                          loaded active running Accounts Service
acpid.service                                                    loaded active running ACPI event daemon
alsa-restore.service                                             loaded active exited  Save/Restore Sound Card State
apparmor.service                                                 loaded active exited  Load AppArmor profiles
apport.service                                                   loaded active exited  LSB: automatic crash report generation
avahi-daemon.service                                             loaded active running Avahi mDNS/DNS-SD Stack
binfmt-support.service                                           loaded active exited  Enable support for additional executable binary formats
blk-availability.service                                         loaded active exited  Availability of block devices
bluetooth.service                                                loaded active running Bluetooth service
bolt.service                                                     loaded active running Thunderbolt system service
chrony.service                                                   loaded active running chrony, an NTP client/server
colord.service                                                   loaded active running Manage, Install and Generate Color Profiles
com.system76.PowerDaemon.service                                 loaded active running System76 Power Daemon
com.system76.Scheduler.service                                   loaded active running Automatically configure CPU scheduler for responsiveness on AC
com.system76.SystemUpdater.service                               loaded active running Distribution updater
console-setup.service                                            loaded active exited  Set console font and keymap
lines 1-17...skipping...
UNIT                                                             LOAD   ACTIVE SUB     DESCRIPTION
accounts-daemon.service                                          loaded active running Accounts Service
acpid.service                                                    loaded active running ACPI event daemon
alsa-restore.service                                             loaded active exited  Save/Restore Sound Card State
apparmor.service                                                 loaded active exited  Load AppArmor profiles
apport.service                                                   loaded active exited  LSB: automatic crash report generation
avahi-daemon.service                                             loaded active running Avahi mDNS/DNS-SD Stack
binfmt-support.service                                           loaded active exited  Enable support for additional executable binary formats
blk-availability.service                                         loaded active exited  Availability of block devices
bluetooth.service                                                loaded active running Bluetooth service
bolt.service                                                     loaded active running Thunderbolt system service
chrony.service                                                   loaded active running chrony, an NTP client/server
colord.service                                                   loaded active running Manage, Install and Generate Color Profiles
com.system76.PowerDaemon.service                                 loaded active running System76 Power Daemon
com.system76.Scheduler.service                                   loaded active running Automatically configure CPU scheduler for responsiveness on AC
com.system76.SystemUpdater.service                               loaded active running Distribution updater
console-setup.service                                            loaded active exited  Set console font and keymap
containerd.service                                               loaded active running containerd container runtime
cron.service                                                     loaded active running Regular background program processing daemon
cups-browsed.service                                             loaded active running Make remote CUPS printers available locally
cups.service                                                     loaded active running CUPS Scheduler
dbus-:1.1-org.pop_os.transition_system@0.service                 loaded active running dbus-:1.1-org.pop_os.transition_system@0.service
dbus-broker.service                                              loaded active running D-Bus System Message Bus
docker.service                                                   loaded active running Docker Application Container Engine
finalrd.service                                                  loaded active exited  Create final runtime dir for shutdown pivot root
fwupd.service                                                    loaded active running Firmware update daemon
gdm.service                                                      loaded active running GNOME Display Manager
geoclue.service                                                  loaded active running Location Lookup Service
lines 1-28...skipping...
UNIT                                                             LOAD   ACTIVE SUB     DESCRIPTION
accounts-daemon.service                                          loaded active running Accounts Service
acpid.service                                                    loaded active running ACPI event daemon
alsa-restore.service                                             loaded active exited  Save/Restore Sound Card State
apparmor.service                                                 loaded active exited  Load AppArmor profiles
apport.service                                                   loaded active exited  LSB: automatic crash report generation
avahi-daemon.service                                             loaded active running Avahi mDNS/DNS-SD Stack
binfmt-support.service                                           loaded active exited  Enable support for additional executable binary formats
blk-availability.service                                         loaded active exited  Availability of block devices
bluetooth.service                                                loaded active running Bluetooth service
bolt.service                                                     loaded active running Thunderbolt system service
chrony.service                                                   loaded active running chrony, an NTP client/server
colord.service                                                   loaded active running Manage, Install and Generate Color Profiles
com.system76.PowerDaemon.service                                 loaded active running System76 Power Daemon
com.system76.Scheduler.service                                   loaded active running Automatically configure CPU scheduler for responsiveness on AC
com.system76.SystemUpdater.service                               loaded active running Distribution updater
console-setup.service                                            loaded active exited  Set console font and keymap
containerd.service                                               loaded active running containerd container runtime
cron.service                                                     loaded active running Regular background program processing daemon
cups-browsed.service                                             loaded active running Make remote CUPS printers available locally
cups.service                                                     loaded active running CUPS Scheduler
dbus-:1.1-org.pop_os.transition_system@0.service                 loaded active running dbus-:1.1-org.pop_os.transition_system@0.service
dbus-broker.service                                              loaded active running D-Bus System Message Bus
docker.service                                                   loaded active running Docker Application Container Engine
finalrd.service                                                  loaded active exited  Create final runtime dir for shutdown pivot root
fwupd.service                                                    loaded active running Firmware update daemon
gdm.service                                                      loaded active running GNOME Display Manager
geoclue.service                                                  loaded active running Location Lookup Service
ifupdown-pre.service                                             loaded active exited  Helper to synchronize boot up for ifupdown
iio-sensor-proxy.service                                         loaded active running IIO Sensor Proxy service
keyboard-setup.service                                           loaded active exited  Set the console keyboard layout
kmod-static-nodes.service                                        loaded active exited  Create List of Static Device Nodes
libvirt-guests.service                                           loaded active exited  Suspend/Resume Running libvirt Guests
libvirtd.service                                                 loaded active running Virtualization daemon
lvm2-monitor.service                                             loaded active exited  Monitoring of LVM2 mirrors, snapshots etc. using dmeventd or progress polling
ModemManager.service                                             loaded active running Modem Manager
networkd-dispatcher.service                                      loaded active running Dispatcher daemon for systemd-networkd
networking.service                                               loaded active exited  Raise network interfaces
NetworkManager-wait-online.service                               loaded active exited  Network Manager Wait Online
NetworkManager.service                                           loaded active running Network Manager
nmbd.service                                                     loaded active running Samba NMB Daemon
nordvpnd.service                                                 loaded active running NordVPN Daemon
nvidia-persistenced.service                                      loaded active running NVIDIA Persistence Daemon
nvidia-powerd.service                                            loaded active running nvidia-powerd service
ollama.service                                                   loaded active running Ollama Service
openvpn.service                                                  loaded active exited  OpenVPN service
packagekit.service                                               loaded active running PackageKit Daemon
plymouth-quit-wait.service                                       loaded active exited  Hold until boot process finishes up
plymouth-read-write.service                                      loaded active exited  Tell Plymouth To Write Out Runtime Data
plymouth-start.service                                           loaded active exited  Show Plymouth Boot Screen
polkit.service                                                   loaded active running Authorization Manager
qemu-kvm.service                                                 loaded active exited  QEMU KVM preparation - module, ksm, hugepages
rclone-mount.service                                             loaded active running Rclone service
rsyslog.service                                                  loaded active running System Logging Service
rtkit-daemon.service                                             loaded active running RealtimeKit Scheduling Policy Service
setvtrgb.service                                                 loaded active exited  Set console scheme
smbd.service                                                     loaded active running Samba SMB Daemon
switcheroo-control.service                                       loaded active running Switcheroo Control Proxy service
systemd-backlight@backlight:intel_backlight.service              loaded active exited  Load/Save Screen Backlight Brightness of backlight:intel_backlight
systemd-backlight@leds:samsung-galaxybook::kbd_backlight.service loaded active exited  Load/Save Screen Backlight Brightness of leds:samsung-galaxybook::kbd_backlight
systemd-binfmt.service                                           loaded active exited  Set Up Additional Binary Formats
systemd-cryptsetup@cryptswap.service                             loaded active exited  Cryptography Setup for cryptswap
systemd-journal-flush.service                                    loaded active exited  Flush Journal to Persistent Storage
systemd-journald.service                                         loaded active running Journal Service
systemd-logind.service                                           loaded active running User Login Management
systemd-machined.service                                         loaded active running Virtual Machine and Container Registration Service
systemd-modules-load.service                                     loaded active exited  Load Kernel Modules
systemd-pstore.service                                           loaded active exited  Platform Persistent Storage Archival
systemd-random-seed.service                                      loaded active exited  Load/Save Random Seed
systemd-remount-fs.service                                       loaded active exited  Remount Root and Kernel File Systems
systemd-resolved.service                                         loaded active running Network Name Resolution
systemd-sysctl.service                                           loaded active exited  Apply Kernel Variables
systemd-sysusers.service                                         loaded active exited  Create System Users
systemd-tmpfiles-setup-dev.service                               loaded active exited  Create Static Device Nodes in /dev
systemd-tmpfiles-setup.service                                   loaded active exited  Create Volatile Files and Directories
systemd-udev-trigger.service                                     loaded active exited  Coldplug All udev Devices
systemd-udevd.service                                            loaded active running Rule-based Manager for Device Events and Files
systemd-update-utmp.service                                      loaded active exited  Record System Boot/Shutdown in UTMP
systemd-user-sessions.service                                    loaded active exited  Permit User Sessions
thermald.service                                                 loaded active running Thermal Daemon Service
touchegg.service                                                 loaded active running Touchégg Daemon
udisks2.service                                                  loaded active running Disk Manager
ufw.service                                                      loaded active exited  Uncomplicated firewall
upower.service                                                   loaded active running Daemon for power management
user-runtime-dir@1000.service                                    loaded active exited  User Runtime Directory /run/user/1000
user@1000.service                                                loaded active running User Manager for UID 1000
wpa_supplicant.service                                           loaded active running WPA supplicant

LOAD   = Reflects whether the unit definition was properly loaded.
ACTIVE = The high-level unit activation state, i.e. generalization of SUB.
SUB    = The low-level unit activation state, values depend on unit type.
86 loaded units listed.

```

### Script 05 fail logs

```bash

➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v5.sh
[ipu6_install_v5.sh] Preflight checks...
[ipu6_install_v5.sh] Ensuring firmware and headers are installed...
Get:1 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Hit:2 https://dl.google.com/linux/chrome/deb stable InRelease                                                                                                                                                                                                                                                         
Hit:3 https://download.docker.com/linux/ubuntu jammy InRelease                                                                                                                                                                                                                                                        
Hit:4 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease                                                                                                                                                                                                                
Hit:5 http://apt.pop-os.org/proprietary jammy InRelease                                                                                                                                                                                                     
Hit:6 http://apt.pop-os.org/release jammy InRelease                                                                                                                                                                                   
Hit:7 http://archive.ubuntu.com/ubuntu jammy-updates InRelease                                                  
Ign:8 https://apt.fury.io/notion-repackaged  InRelease                                                          
Hit:9 https://downloads.1password.com/linux/debian/amd64 stable InRelease                 
Hit:10 http://apt.pop-os.org/ubuntu jammy InRelease                 
Ign:11 https://apt.fury.io/notion-repackaged  Release               
Hit:12 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy InRelease
Ign:13 https://apt.fury.io/notion-repackaged  Packages              
Hit:14 http://apt.pop-os.org/ubuntu jammy-security InRelease
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en
Hit:17 http://apt.pop-os.org/ubuntu jammy-updates InRelease
Get:13 https://apt.fury.io/notion-repackaged  Packages [1,572 B]
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US       
Hit:18 http://apt.pop-os.org/ubuntu jammy-backports InRelease
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:16 https://apt.fury.io/notion-repackaged  Translation-en
Fetched 5,194 B in 3s (1,808 B/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
git is already the newest version (1:2.34.1-1ubuntu1.15).
linux-firmware is already the newest version (20250317.git1d4c88ee-0ubuntu1+system76~1749060582~22.04~230e2f0).
linux-headers-6.16.3-76061603-generic is already the newest version (6.16.3-76061603.202508231538~1758561135~22.04~171c8de).
build-essential is already the newest version (12.9ubuntu3).
pkg-config is already the newest version (0.29.2-1ubuntu3).
gstreamer1.0-plugins-bad is already the newest version (1.24.13-0ubuntu1~22.04.sav0.1).
gstreamer1.0-plugins-base is already the newest version (1.24.13-0ubuntu1~22.04.sav0).
gstreamer1.0-plugins-good is already the newest version (1.24.13-0ubuntu1~22.04.sav0.1).
gstreamer1.0-tools is already the newest version (1.24.13-0ubuntu1~22.04.sav0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[ipu6_install_v5.sh] Purging likely conflicting DKMS/IPU6 packages (if present)...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
Note, selecting 'linux-modules-ipu6-6.8.0-57-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-59-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-46-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-50-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-50-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1031-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-45-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-52-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-41-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-43-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1032-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-58-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-45-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1011-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1033-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-45-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1012-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-47-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-49-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1034-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1007-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1015-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-44-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1035-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1024-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-42-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1025-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-40-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-35-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1027-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-32-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1020-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-48-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1028-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-34-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-41-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1020-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04a' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04b' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04c' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04d' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-36-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1012-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1021-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1021-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-39-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1013-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1022-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1014-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1007-nvidia' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-31-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1023-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-33-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-25-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1013-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1015-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-35-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-27-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1014-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-37-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1024-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1016-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-39-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1015-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-38-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1016-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1033-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1016-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1025-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-26-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1017-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1017-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1017-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1034-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1026-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1018-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-generic-hwe-22.04-edge' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1035-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-generic-hwe-22.04' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-26-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1027-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1019-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-28-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-lowlatency-hwe-22.04' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-83-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1019-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1036-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1028-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-15-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-25-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1011-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-17-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1017-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1003-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1020-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1029-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-lowlatency-hwe-22.04-edge' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-21-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1004-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1013-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1022-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-84-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1009-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-14-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1014-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1006-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1023-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-18-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1015-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1018-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1007-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1024-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-79-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1016-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1008-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1025-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1009-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1030-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1018-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1027-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1019-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-78-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-65-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-generic-6.8' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-60-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-64-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-51-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1008-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1016-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-azure-edge' for glob 'linux-modules-ipu6-*'
E: Unable to locate package ivsc-driver
E: Unable to locate package ivsc-dkms
E: Unable to locate package intel-ivsc-driver
E: Unable to locate package usbio-driver
E: Unable to locate package usbio-dkms
E: Unable to locate package linux-modules-ipu6-generic-hwe-24.04
E: Couldn't find any package by glob 'linux-modules-ipu6-generic-hwe-24.04'
E: Couldn't find any package by regex 'linux-modules-ipu6-generic-hwe-24.04'
E: Unable to locate package linux-modules-ipu6
[ipu6_install_v5.sh] Scanning /lib/modules/6.16.3-76061603-generic/updates/dkms for OOT IPU6 core modules to quarantine...
[ipu6_install_v5.sh] Loading in-kernel IPU6 core (should NOT be tagged OE in lsmod)...
modprobe: FATAL: Module intel_ipu6_psys not found in directory /lib/modules/6.16.3-76061603-generic
[ipu6_install_v5.sh] Adding Intel IPU6 userspace PPA and installing ipu6-camera-bins...
Hit:1 https://download.docker.com/linux/ubuntu jammy InRelease
Get:2 https://repo.steampowered.com/steam stable InRelease [3,622 B]                                                                                                                                                                                                                                                  
Hit:3 https://dl.google.com/linux/chrome/deb stable InRelease                                                                                                                                                                                                                                                         
Hit:4 http://apt.pop-os.org/proprietary jammy InRelease                                                                                                                                                                                                                          
Hit:5 http://archive.ubuntu.com/ubuntu jammy-updates InRelease                                                                                                           
Hit:6 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease                                                                                
Hit:7 https://downloads.1password.com/linux/debian/amd64 stable InRelease                                                                          
Ign:8 https://apt.fury.io/notion-repackaged  InRelease                                    
Hit:9 http://apt.pop-os.org/release jammy InRelease                 
Ign:10 https://apt.fury.io/notion-repackaged  Release               
Ign:11 https://apt.fury.io/notion-repackaged  Packages              
Hit:12 http://apt.pop-os.org/ubuntu jammy InRelease                 
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en
Hit:14 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy InRelease
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Hit:16 http://apt.pop-os.org/ubuntu jammy-security InRelease
Get:11 https://apt.fury.io/notion-repackaged  Packages [1,572 B]
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en          
Hit:17 http://apt.pop-os.org/ubuntu jammy-updates InRelease
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Hit:18 http://apt.pop-os.org/ubuntu jammy-backports InRelease
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:13 https://apt.fury.io/notion-repackaged  Translation-en
Ign:15 https://apt.fury.io/notion-repackaged  Translation-en_US
Fetched 5,194 B in 3s (1,911 B/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
E: Unable to locate package ipu6-camera-bins

```

### fail from script 6 version

```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v6.sh
[sudo] password for fernandoavanzo: 
[ipu6_install_v6] Preflight...
Get:1 https://repo.steampowered.com/steam stable InRelease [3,622 B]
Hit:2 https://dl.google.com/linux/chrome/deb stable InRelease                                                                                                                                                                                 
Hit:3 https://repo.nordvpn.com//deb/nordvpn/debian stable InRelease                                                                                                                                                                                                                                                   
Hit:4 http://archive.ubuntu.com/ubuntu jammy-updates InRelease                                                                                                                                                                                                                                                        
Hit:5 https://download.docker.com/linux/ubuntu jammy InRelease                                                                                                                                      
Ign:6 https://apt.fury.io/notion-repackaged  InRelease                                                                                                                                              
Ign:7 https://apt.fury.io/notion-repackaged  Release                                                                                       
Hit:8 http://apt.pop-os.org/proprietary jammy InRelease             
Hit:9 https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu jammy InRelease
Ign:10 https://apt.fury.io/notion-repackaged  Packages              
Hit:11 https://downloads.1password.com/linux/debian/amd64 stable InRelease
Ign:12 https://apt.fury.io/notion-repackaged  Translation-en        
Hit:13 http://apt.pop-os.org/release jammy InRelease
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Get:10 https://apt.fury.io/notion-repackaged  Packages [1,572 B]
Ign:12 https://apt.fury.io/notion-repackaged  Translation-en          
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:12 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:12 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Ign:12 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Hit:15 http://apt.pop-os.org/ubuntu jammy InRelease
Ign:12 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Hit:16 http://apt.pop-os.org/ubuntu jammy-security InRelease
Ign:12 https://apt.fury.io/notion-repackaged  Translation-en
Ign:14 https://apt.fury.io/notion-repackaged  Translation-en_US
Hit:17 http://apt.pop-os.org/ubuntu jammy-updates InRelease
Hit:18 http://apt.pop-os.org/ubuntu jammy-backports InRelease
Fetched 5,194 B in 4s (1,459 B/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
apt-transport-https is already the newest version (2.4.14).
ca-certificates is already the newest version (20240203~22.04.1).
curl is already the newest version (7.81.0-1ubuntu1.20).
libglib2.0-0 is already the newest version (2.72.4-0ubuntu2.6).
software-properties-common is already the newest version (0.99.22.9).
wget is already the newest version (1.21.2-2ubuntu1.1).
linux-firmware is already the newest version (20250317.git1d4c88ee-0ubuntu1+system76~1749060582~22.04~230e2f0).
v4l-utils is already the newest version (1.26.1-2~22.04.sav0).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
[ipu6_install_v6] Purging conflicting/out-of-tree IPU6/USBIO/IVSC stacks (ignore 'not installed' msgs)...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
Note, selecting 'ivsc-prebuilt-kernel' for glob 'ivsc-*'
Note, selecting 'ivsc-modules' for glob 'ivsc-*'
Note, selecting 'usbio-prebuilt-kernel' for glob 'usbio-*'
Note, selecting 'usbio-modules' for glob 'usbio-*'
Note, selecting 'linux-modules-usbio-6.8.0-79-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-83-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-78-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-generic-6.8' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-60-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-64-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-generic-hwe-22.04-edge' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-57-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-59-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-65-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-50-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-52-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-generic-hwe-22.04' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-58-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-oem-22.04' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-45-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-47-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-49-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-51-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-40-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1011-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-48-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1020-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-39-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1013-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1022-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1014-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1023-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1015-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1024-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1016-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-38-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1025-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1018-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1027-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-oem-22.04d' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.5.0-1019-oem' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-usbio-6.8.0-84-generic' for glob 'linux-modules-*usbio*'
Note, selecting 'linux-modules-ipu6-6.8.0-57-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-59-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-46-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-50-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-50-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1031-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-45-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-52-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-41-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-43-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1032-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-58-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-45-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1011-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1033-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-45-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1012-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-47-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-49-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1034-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1007-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1015-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-44-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.17.0-1035-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1024-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-42-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1025-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-40-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-35-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1027-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-32-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1020-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-48-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1028-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-34-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-41-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1020-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04a' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04b' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04c' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04d' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-36-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1012-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1021-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1021-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-39-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1013-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1022-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1014-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1007-nvidia' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-31-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1023-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-33-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-25-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1013-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1015-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-35-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-27-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1014-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-37-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1024-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1016-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-39-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1015-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-38-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1016-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1033-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1016-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1025-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-26-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1017-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1017-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1017-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1034-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1026-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1018-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-generic-hwe-22.04-edge' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1035-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-generic-hwe-22.04' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-26-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1027-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.0.0-1019-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-28-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-lowlatency-hwe-22.04' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-83-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1019-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1036-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1028-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-15-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-25-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1011-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-17-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1017-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1003-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1020-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.1.0-1029-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-lowlatency-hwe-22.04-edge' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-21-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-oem-22.04' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1004-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1013-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1022-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-84-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1009-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-14-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1014-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1006-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1023-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-18-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1015-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1018-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1007-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1024-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-79-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1016-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1008-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1025-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1009-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-5.19.0-1030-lowlatency' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1018-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1027-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1019-oem' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-78-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-65-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-generic-6.8' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-60-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-64-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.8.0-51-generic' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.2.0-1008-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-6.5.0-1016-azure' for glob 'linux-modules-ipu6-*'
Note, selecting 'linux-modules-ipu6-azure-edge' for glob 'linux-modules-ipu6-*'
Package 'libspa-0.2-libcamera' is not installed, so not removed
Note, selecting 'libgcss-dev' for glob 'lib*gcss*'
Note, selecting 'libgcss-ipu6-dev' for glob 'lib*gcss*'
Note, selecting 'libgcss-ipu6-0' for glob 'lib*gcss*'
Note, selecting 'libgcss-ipu6epmtl-dev' for glob 'lib*gcss*'
Note, selecting 'libgcss-ipu6epmtl0' for glob 'lib*gcss*'
Note, selecting 'libgcss-ipu60' for glob 'lib*gcss*'
Note, selecting 'libgcss-ipu6ep-dev' for glob 'lib*gcss*'
Note, selecting 'libgcss0' for glob 'lib*gcss*'
Note, selecting 'libgcss-ipu6ep0' for glob 'lib*gcss*'
Note, selecting 'librust-sequoia-sop-0.26.1+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-egl-gbm1' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+default-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop+default-dev' for glob 'lib*ia-*'
Note, selecting 'libdoxia-java-doc' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-440-server' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt-0.24.0-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-390' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-418' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-495' for glob 'lib*ia-*'
Note, selecting 'libia-cca-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-510-server' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-390' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-525' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-575' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-580' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-418' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-495' for glob 'lib*ia-*'
Note, selecting 'libia-p2p-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-515' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-ipu60' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-525' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-575' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-580' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-580-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-525-server' for glob 'lib*ia-*'
Note, selecting 'libia-mkn0' for glob 'lib*ia-*'
Note, selecting 'libia-log-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-550-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-390' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys-0+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-410' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-418' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-495' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-525' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-570-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-575' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-580' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-any' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-450-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-tesla-cuda1' for glob 'lib*ia-*'
Note, selecting 'libghc-cipher-camellia-dev-0.0.2-5bd3f' for glob 'lib*ia-*'
Note, selecting 'libnet-patricia-perl' for glob 'lib*ia-*'
Note, selecting 'libdoxia-core-java' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-565-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-470-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys-0.3.3+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-440-server' for glob 'lib*ia-*'
Note, selecting 'libia-lard-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libtaningia-dev' for glob 'lib*ia-*'
Note, selecting 'libghc-http-media-prof-0.8.0.0-6bfd3' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-495' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-ipu60' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-460-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-525' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-575' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-580' for glob 'lib*ia-*'
Note, selecting 'libia-p2p-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-legacy-390xx-egl-wayland1' for glob 'lib*ia-*'
Note, selecting 'libgl1-nvidia-glx' for glob 'lib*ia-*'
Note, selecting 'libervia-backend' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libia-lard-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-510-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26.1+compression-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libia-ccat0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libia-lard0' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'librust-winapi+ksmedia-dev' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libghc-cipher-camellia-dev' for glob 'lib*ia-*'
Note, selecting 'libghc-cipher-camellia-doc' for glob 'lib*ia-*'
Note, selecting 'libia-log-ipu60' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-580-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-515-server' for glob 'lib*ia-*'
Note, selecting 'libia-cca-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26.1+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libperlio-via-symlink-perl' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys-0.3.3-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-535-server' for glob 'lib*ia-*'
Note, selecting 'libia-cca0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-container1' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-440-server' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-550-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-container1-dbg' for glob 'lib*ia-*'
Note, selecting 'libia-cca-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-460-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-390' for glob 'lib*ia-*'
Note, selecting 'libnvidia-container-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-418' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-570-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-495' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-575-server' for glob 'lib*ia-*'
Note, selecting 'libtrilinos-isorropia-13.2' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-525' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-575' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-580' for glob 'lib*ia-*'
Note, selecting 'libia-cca-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-450-server' for glob 'lib*ia-*'
Note, selecting 'librust-winapi-0+ksmedia-dev' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-470-server' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libghc-http-media-prof' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder0' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng-0-dev' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-525-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-510-server' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-ipu60' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt+default-dev' for glob 'lib*ia-*'
Note, selecting 'libdoxia-sitetools-java' for glob 'lib*ia-*'
Note, selecting 'libghc-http-media-dev-0.8.0.0-6bfd3' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-390' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-418' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-470' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-565-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-550-server' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-418-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-550-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-570-server' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-570-server' for glob 'lib*ia-*'
Note, selecting 'librust-ammonia-3.1-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26.1+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-418-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-0.3.3-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-525-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-log-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp0' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-dev' for glob 'lib*ia-*'
Note, selecting 'libia-exc-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libsofia-sip-ua0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-440-server' for glob 'lib*ia-*'
Note, selecting 'libia-nvm0' for glob 'lib*ia-*'
Note, selecting 'librust-ammonia-3+default-dev' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal0' for glob 'lib*ia-*'
Note, selecting 'libzia-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-460-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-580-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-0+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-495-server' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26+cli-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-ipu60' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-0.3+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-450-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-515-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng-0.1+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-exc-ipu60' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-470-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-535-server' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-550-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-470' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-525' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-575' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26.1+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq-580' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-570-server' for glob 'lib*ia-*'
Note, selecting 'libia-exc-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-575-server' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libmaven-doxia-tools-java' for glob 'lib*ia-*'
Note, selecting 'libia-cca-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-580-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-510-server' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'librust-ammonia-3.1.2+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-390' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-450-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-515-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-418' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-495' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-450-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26.1+cli-dev' for glob 'lib*ia-*'
Note, selecting 'libia-exc-dev' for glob 'lib*ia-*'
Note, selecting 'libia-log-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt0i' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-565-server' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-525' for glob 'lib*ia-*'
Note, selecting 'libia-log-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-575' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-580' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-470-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-535-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-470-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-egl-wayland1' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+flate2-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ml1' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode1' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-575-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-440-server' for glob 'lib*ia-*'
Note, selecting 'libbrasero-media-dev' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt-0-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-418-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-460-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-510-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libia-dvs0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'libia-lard-dev' for glob 'lib*ia-*'
Note, selecting 'libfolia-dev' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-580-server' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26.1-dev' for glob 'lib*ia-*'
Note, selecting 'libmaven-doxia-tools-java-doc' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-515-server' for glob 'lib*ia-*'
Note, selecting 'libia-exc-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-450-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-535-server' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser0i' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-440-server' for glob 'lib*ia-*'
Note, selecting 'libsub-handlesvia-perl' for glob 'lib*ia-*'
Note, selecting 'libghc-cipher-camellia-prof-0.0.2-5bd3f' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-470-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-418-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-460-server' for glob 'lib*ia-*'
Note, selecting 'libervia-pubsub' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-525-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-575-server' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+compression-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-565-server' for glob 'lib*ia-*'
Note, selecting 'libreoffice-avmedia-backend-gstreamer' for glob 'lib*ia-*'
Note, selecting 'libdoxia-sitetools-java-doc' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-510-server' for glob 'lib*ia-*'
Note, selecting 'libsofia-sip-ua-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-dev' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng-0.1.1-dev' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng-0.1.1+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-ltm-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-550-server' for glob 'lib*ia-*'
Note, selecting 'libia-lard-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-exc-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-ipu60' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-570-server' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-log-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0+cli-dev' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-418-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-440-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-515-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-525-server' for glob 'lib*ia-*'
Note, selecting 'libgtk-4-media-ffmpeg' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ml-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-460-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-535-server' for glob 'lib*ia-*'
Note, selecting 'libia-log-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libzinnia-dev' for glob 'lib*ia-*'
Note, selecting 'libzinnia-doc' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-dev' for glob 'lib*ia-*'
Note, selecting 'libmoox-handlesvia-perl' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-575-server' for glob 'lib*ia-*'
Note, selecting 'libwebservice-cia-perl' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'liborcania-dev' for glob 'lib*ia-*'
Note, selecting 'libia-exc0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt-0.24+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libghc-http-media-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-580-server' for glob 'lib*ia-*'
Note, selecting 'libghc-http-media-doc' for glob 'lib*ia-*'
Note, selecting 'libreoffice-avmedia-backend-vlc' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'librust-ammonia-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt-0.24.0+default-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0+compression-dev' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys-0.3-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-565-server' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-cca-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-cca-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-nscq' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libapophenia-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt-0.24-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-container-tools' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-0-dev' for glob 'lib*ia-*'
Note, selecting 'libia-cca-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0-dev' for glob 'lib*ia-*'
Note, selecting 'librust-winapi-0.3.9+ksmedia-dev' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-580-server' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng-0.1-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-418-server' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-dev' for glob 'lib*ia-*'
Note, selecting 'libperlio-via-dynamic-perl' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-525-server' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-aiqb-parser0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ml.so.1' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+flate2-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-ipu60' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-510-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+compression-bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-450-server' for glob 'lib*ia-*'
Note, selecting 'libgraxxia-java' for glob 'lib*ia-*'
Note, selecting 'libia-exc-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libia-p2p-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-565-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-470-server' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-565-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-0.3.3+default-dev' for glob 'lib*ia-*'
Note, selecting 'libvia-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-550-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-515-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+flate2-dev' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-ipu6-dev' for glob 'lib*ia-*'
Note, selecting 'libia-lard-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libwww-wikipedia-perl' for glob 'lib*ia-*'
Note, selecting 'libervia-cli' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-570-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-535-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-dev' for glob 'lib*ia-*'
Note, selecting 'libdoxia-java' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-510-server' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'libcdparanoia-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-575-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-0.3-dev' for glob 'lib*ia-*'
Note, selecting 'libcdio-paranoia-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-390' for glob 'lib*ia-*'
Note, selecting 'libnvidia-egl-wayland-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt-0+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-418' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-495' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-460-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-525' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-575' for glob 'lib*ia-*'
Note, selecting 'libnvidia-cfg1-580' for glob 'lib*ia-*'
Note, selecting 'librust-ammonia-3.1+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-dev' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-ipu60' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-440-server' for glob 'lib*ia-*'
Note, selecting 'libtrilinos-isorropia-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-515-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-460-server' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-535-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-440-server' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+flate2-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq0' for glob 'lib*ia-*'
Note, selecting 'libsofia-sip-ua-glib-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-565-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-390' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26+compression-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-418' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-430' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-435' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-440' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-450' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-455' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-460' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-465' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-470' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-495' for glob 'lib*ia-*'
Note, selecting 'libghc-cipher-camellia-prof' for glob 'lib*ia-*'
Note, selecting 'libnvidia-encode-460-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0.26-dev' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-510' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-515' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-520' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-525' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-530' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-535' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-545' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-550' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-555' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-560' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-565' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-570' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-575' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-580' for glob 'lib*ia-*'
Note, selecting 'libgtk-4-media-gstreamer' for glob 'lib*ia-*'
Note, selecting 'libervia-tui' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-575-server' for glob 'lib*ia-*'
Note, selecting 'librust-ammonia-3-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop+compression-dev' for glob 'lib*ia-*'
Note, selecting 'libia-isp-bxt-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+nettle-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+compression-dev' for glob 'lib*ia-*'
Note, selecting 'libia-lard-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-418-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys-0-dev' for glob 'lib*ia-*'
Note, selecting 'libia-exc-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode-525-server' for glob 'lib*ia-*'
Note, selecting 'libia-log0' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-dev' for glob 'lib*ia-*'
Note, selecting 'libmia-2.2-dev' for glob 'lib*ia-*'
Note, selecting 'libervia-templates' for glob 'lib*ia-*'
Note, selecting 'libmia-2.2-doc' for glob 'lib*ia-*'
Note, selecting 'libnvidia-decode' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop+cli-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1+default-dev' for glob 'lib*ia-*'
Note, selecting 'libia-emd-decoder-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libia-lard-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-450-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+bzip2-dev' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libia-ltm0' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-zircon-sys-0.3+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-550-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7.0+compression-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute' for glob 'lib*ia-*'
Note, selecting 'libnvidia-compute-470-server' for glob 'lib*ia-*'
Note, selecting 'liblivemedia-dev' for glob 'lib*ia-*'
Note, selecting 'libsofia-sip-ua-glib3' for glob 'lib*ia-*'
Note, selecting 'libia-bcomp-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common-570-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-515-server' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-450-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0+compression-deflate-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-535-server' for glob 'lib*ia-*'
Note, selecting 'librust-fuchsia-cprng-0+default-dev' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-418-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-fbc1-525-server' for glob 'lib*ia-*'
Note, selecting 'libnvidia-ifr1-470-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1-dev' for glob 'lib*ia-*'
Note, selecting 'libia-nvm-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libnvidia-gl-580-server' for glob 'lib*ia-*'
Note, selecting 'libperlio-via-timeout-perl' for glob 'lib*ia-*'
Note, selecting 'libia-ccat-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'libmia-2.4-dev' for glob 'lib*ia-*'
Note, selecting 'libmia-2.4-doc' for glob 'lib*ia-*'
Note, selecting 'libia-dvs-ipu60' for glob 'lib*ia-*'
Note, selecting 'libnvidia-extra-575-server' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp-1.7+compression-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop-0-dev' for glob 'lib*ia-*'
Note, selecting 'libbroxton-ia-pal-ipu6epmtl0' for glob 'lib*ia-*'
Note, selecting 'libjulia-openblas64' for glob 'lib*ia-*'
Note, selecting 'librust-ammonia-3.1.2-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-autocrypt-dev' for glob 'lib*ia-*'
Note, selecting 'libia-coordinate0i' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-openpgp+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libia-lard-ipu6ep-dev' for glob 'lib*ia-*'
Note, selecting 'librust-winapi-0.3+ksmedia-dev' for glob 'lib*ia-*'
Note, selecting 'librust-sequoia-sop+crypto-nettle-dev' for glob 'lib*ia-*'
Note, selecting 'libparse-dia-sql-perl' for glob 'lib*ia-*'
Note, selecting 'libnvidia-common' for glob 'lib*ia-*'
Note, selecting 'libia-log-ipu6epmtl-dev' for glob 'lib*ia-*'
Note, selecting 'libia-aiq-file-debug-ipu6-0' for glob 'lib*ia-*'
Note, selecting 'libia-mkn-ipu6ep0' for glob 'lib*ia-*'
Note, selecting 'libia-cmc-parser0' for glob 'lib*ia-*'
Note, selecting 'libmia-2.4-0' for glob 'lib*ia-*'
Note, selecting 'libmia-2.4-4' for glob 'lib*ia-*'
Package 'libnvidia-encode1' is not installed, so not removed
Package 'libnvidia-tesla-cuda1' is not installed, so not removed
Package 'libreoffice-avmedia-backend-vlc' is not installed, so not removed
Note, selecting 'librust-sequoia-openpgp+compression-bzip2-dev' instead of 'librust-sequoia-openpgp-1+compression-bzip2-dev'
Note, selecting 'librust-sequoia-openpgp+compression-deflate-dev' instead of 'librust-sequoia-openpgp-1+compression-deflate-dev'
Note, selecting 'librust-sequoia-openpgp+compression-dev' instead of 'librust-sequoia-openpgp-1+compression-dev'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' instead of 'librust-sequoia-openpgp-1+crypto-nettle-dev'
Note, selecting 'librust-sequoia-openpgp+default-dev' instead of 'librust-sequoia-openpgp-1+default-dev'
Note, selecting 'librust-sequoia-openpgp-dev' instead of 'librust-sequoia-openpgp-1-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop+cli-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop+compression-bzip2-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop+compression-deflate-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop+compression-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop+crypto-nettle-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop+default-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0+cli-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0+compression-bzip2-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0+compression-deflate-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0+compression-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0+crypto-nettle-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0+default-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26+cli-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26+compression-bzip2-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26+compression-deflate-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26+compression-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26+crypto-nettle-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26+default-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26.1+cli-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26.1+compression-bzip2-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26.1+compression-deflate-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26.1+compression-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26.1+crypto-nettle-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26.1+default-dev'
Note, selecting 'librust-sequoia-sop-dev' instead of 'librust-sequoia-sop-0.26.1-dev'
Package 'libgtk-4-media-ffmpeg' is not installed, so not removed
Package 'libnvidia-gl-410' is not installed, so not removed
Package 'libnvidia-legacy-390xx-egl-wayland1' is not installed, so not removed
Package 'libia-cmc-parser0i' is not installed, so not removed
Package 'libia-coordinate0i' is not installed, so not removed
Package 'libia-isp-bxt0i' is not installed, so not removed
Note, selecting 'libapophenia2-dev' instead of 'libapophenia-dev'
Package 'libbrasero-media-dev' is not installed, so not removed
Note, selecting 'libghc-cipher-camellia-dev' instead of 'libghc-cipher-camellia-dev-0.0.2-5bd3f'
Note, selecting 'libghc-cipher-camellia-prof' instead of 'libghc-cipher-camellia-prof-0.0.2-5bd3f'
Note, selecting 'libghc-http-media-dev' instead of 'libghc-http-media-dev-0.8.0.0-6bfd3'
Note, selecting 'libghc-http-media-prof' instead of 'libghc-http-media-prof-0.8.0.0-6bfd3'
Package 'libmia-2.4-0' is not installed, so not removed
Package 'libmia-2.2-dev' is not installed, so not removed
Package 'libmia-2.2-doc' is not installed, so not removed
Note, selecting 'librust-ammonia-dev' instead of 'librust-ammonia-3+default-dev'
Note, selecting 'librust-ammonia-dev' instead of 'librust-ammonia-3-dev'
Note, selecting 'librust-ammonia-dev' instead of 'librust-ammonia-3.1+default-dev'
Note, selecting 'librust-ammonia-dev' instead of 'librust-ammonia-3.1-dev'
Note, selecting 'librust-ammonia-dev' instead of 'librust-ammonia-3.1.2+default-dev'
Note, selecting 'librust-ammonia-dev' instead of 'librust-ammonia-3.1.2-dev'
Note, selecting 'librust-fuchsia-cprng-dev' instead of 'librust-fuchsia-cprng+default-dev'
Note, selecting 'librust-fuchsia-cprng-dev' instead of 'librust-fuchsia-cprng-0+default-dev'
Note, selecting 'librust-fuchsia-cprng-dev' instead of 'librust-fuchsia-cprng-0-dev'
Note, selecting 'librust-fuchsia-cprng-dev' instead of 'librust-fuchsia-cprng-0.1+default-dev'
Note, selecting 'librust-fuchsia-cprng-dev' instead of 'librust-fuchsia-cprng-0.1-dev'
Note, selecting 'librust-fuchsia-cprng-dev' instead of 'librust-fuchsia-cprng-0.1.1+default-dev'
Note, selecting 'librust-fuchsia-cprng-dev' instead of 'librust-fuchsia-cprng-0.1.1-dev'
Note, selecting 'librust-fuchsia-zircon-sys-dev' instead of 'librust-fuchsia-zircon-sys-0.3+default-dev'
Note, selecting 'librust-fuchsia-zircon-dev' instead of 'librust-fuchsia-zircon+default-dev'
Note, selecting 'librust-fuchsia-zircon-dev' instead of 'librust-fuchsia-zircon-0+default-dev'
Note, selecting 'librust-fuchsia-zircon-dev' instead of 'librust-fuchsia-zircon-0-dev'
Note, selecting 'librust-fuchsia-zircon-dev' instead of 'librust-fuchsia-zircon-0.3+default-dev'
Note, selecting 'librust-fuchsia-zircon-dev' instead of 'librust-fuchsia-zircon-0.3-dev'
Note, selecting 'librust-fuchsia-zircon-dev' instead of 'librust-fuchsia-zircon-0.3.3+default-dev'
Note, selecting 'librust-fuchsia-zircon-dev' instead of 'librust-fuchsia-zircon-0.3.3-dev'
Note, selecting 'librust-fuchsia-zircon-sys-dev' instead of 'librust-fuchsia-zircon-sys+default-dev'
Note, selecting 'librust-fuchsia-zircon-sys-dev' instead of 'librust-fuchsia-zircon-sys-0+default-dev'
Note, selecting 'librust-fuchsia-zircon-sys-dev' instead of 'librust-fuchsia-zircon-sys-0-dev'
Note, selecting 'librust-fuchsia-zircon-sys-dev' instead of 'librust-fuchsia-zircon-sys-0.3-dev'
Note, selecting 'librust-fuchsia-zircon-sys-dev' instead of 'librust-fuchsia-zircon-sys-0.3.3+default-dev'
Note, selecting 'librust-fuchsia-zircon-sys-dev' instead of 'librust-fuchsia-zircon-sys-0.3.3-dev'
Note, selecting 'librust-sequoia-autocrypt-dev' instead of 'librust-sequoia-autocrypt+default-dev'
Note, selecting 'librust-sequoia-autocrypt-dev' instead of 'librust-sequoia-autocrypt-0+default-dev'
Note, selecting 'librust-sequoia-autocrypt-dev' instead of 'librust-sequoia-autocrypt-0-dev'
Note, selecting 'librust-sequoia-autocrypt-dev' instead of 'librust-sequoia-autocrypt-0.24+default-dev'
Note, selecting 'librust-sequoia-autocrypt-dev' instead of 'librust-sequoia-autocrypt-0.24-dev'
Note, selecting 'librust-sequoia-autocrypt-dev' instead of 'librust-sequoia-autocrypt-0.24.0+default-dev'
Note, selecting 'librust-sequoia-autocrypt-dev' instead of 'librust-sequoia-autocrypt-0.24.0-dev'
Note, selecting 'librust-sequoia-openpgp+bzip2-dev' instead of 'librust-sequoia-openpgp-1+bzip2-dev'
Note, selecting 'librust-sequoia-openpgp+bzip2-dev' instead of 'librust-sequoia-openpgp-1.7+bzip2-dev'
Note, selecting 'librust-sequoia-openpgp+bzip2-dev' instead of 'librust-sequoia-openpgp-1.7.0+bzip2-dev'
Note, selecting 'librust-sequoia-openpgp+compression-bzip2-dev' instead of 'librust-sequoia-openpgp-1.7+compression-bzip2-dev'
Note, selecting 'librust-sequoia-openpgp+compression-bzip2-dev' instead of 'librust-sequoia-openpgp-1.7.0+compression-bzip2-dev'
Note, selecting 'librust-sequoia-openpgp+compression-deflate-dev' instead of 'librust-sequoia-openpgp-1.7+compression-deflate-dev'
Note, selecting 'librust-sequoia-openpgp+compression-deflate-dev' instead of 'librust-sequoia-openpgp-1.7.0+compression-deflate-dev'
Note, selecting 'librust-sequoia-openpgp+compression-dev' instead of 'librust-sequoia-openpgp-1.7+compression-dev'
Note, selecting 'librust-sequoia-openpgp+compression-dev' instead of 'librust-sequoia-openpgp-1.7.0+compression-dev'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' instead of 'librust-sequoia-openpgp+crypto-nettle-dev'
Note, selecting 'librust-sequoia-openpgp+default-dev' instead of 'librust-sequoia-openpgp-1.7+default-dev'
Note, selecting 'librust-sequoia-openpgp+default-dev' instead of 'librust-sequoia-openpgp-1.7.0+default-dev'
Note, selecting 'librust-sequoia-openpgp+flate2-dev' instead of 'librust-sequoia-openpgp-1+flate2-dev'
Note, selecting 'librust-sequoia-openpgp+flate2-dev' instead of 'librust-sequoia-openpgp-1.7+flate2-dev'
Note, selecting 'librust-sequoia-openpgp+flate2-dev' instead of 'librust-sequoia-openpgp-1.7.0+flate2-dev'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' instead of 'librust-sequoia-openpgp-1+nettle-dev'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' instead of 'librust-sequoia-openpgp-1.7+crypto-nettle-dev'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' instead of 'librust-sequoia-openpgp-1.7+nettle-dev'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' instead of 'librust-sequoia-openpgp-1.7.0+crypto-nettle-dev'
Note, selecting 'librust-sequoia-openpgp+nettle-dev' instead of 'librust-sequoia-openpgp-1.7.0+nettle-dev'
Note, selecting 'librust-sequoia-openpgp-dev' instead of 'librust-sequoia-openpgp-1.7-dev'
Note, selecting 'librust-sequoia-openpgp-dev' instead of 'librust-sequoia-openpgp-1.7.0-dev'
Note, selecting 'librust-winapi-dev' instead of 'librust-winapi+ksmedia-dev'
Note, selecting 'librust-winapi-dev' instead of 'librust-winapi-0+ksmedia-dev'
Note, selecting 'librust-winapi-dev' instead of 'librust-winapi-0.3+ksmedia-dev'
Note, selecting 'librust-winapi-dev' instead of 'librust-winapi-0.3.9+ksmedia-dev'
Package 'libvia-dev' is not installed, so not removed
Package 'liblivemedia-dev' is not installed, so not removed
Package 'libgl1-nvidia-glx' is not installed, so not removed
Package 'libnvidia-compute-495-server' is not installed, so not removed
Note, selecting 'libia-aiq-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-cmc-parser-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-cca-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-cmc-parser-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-p2p-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-cmc-parser-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-log-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-ltm-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-file-debug-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-lard-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiqb-parser-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-ccat-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-nvm-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-p2p-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-mkn-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6ep-common' for glob 'lib*ipu6*'
Note, selecting 'libia-emd-decoder-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-lard-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libbroxton-ia-pal-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-ccat-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-coordinate-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-ccat-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-coordinate-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-bcomp-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-isp-bxt-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-log-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-dvs-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-cca-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-nvm-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-emd-decoder-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libgcss-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-bcomp-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libbroxton-ia-pal-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-cca-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libgcss-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libbroxton-ia-pal-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6ep' for glob 'lib*ipu6*'
Note, selecting 'libia-coordinate-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-bcomp-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libgcss-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-coordinate-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-ltm-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-cmc-parser-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-log-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-exc-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiqb-parser-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-mkn-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-bcomp-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6-common' for glob 'lib*ipu6*'
Note, selecting 'libia-exc-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-dvs-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-nvm-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-dvs-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-exc-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-ltm-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-cca-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-nvm-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-file-debug-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6epmtl-common' for glob 'lib*ipu6*'
Note, selecting 'libia-dvs-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-log-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-ccat-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-log-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-coordinate-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-ltm-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-cmc-parser-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libbroxton-ia-pal-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-mkn-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-cmc-parser-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-mkn-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-emd-decoder-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-exc-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-aiqb-parser-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-ltm-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiqb-parser-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-ltm-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libgcss-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libipu6epmtl' for glob 'lib*ipu6*'
Note, selecting 'libia-dvs-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-ccat-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-ltm-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-lard-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-exc-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-file-debug-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiqb-parser-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libbroxton-ia-pal-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-file-debug-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-nvm-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-file-debug-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiqb-parser-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-log-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-isp-bxt-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-cmc-parser-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libipu6' for glob 'lib*ipu6*'
Note, selecting 'libbroxton-ia-pal-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-coordinate-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-nvm-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-cca-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-cca-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-aiqb-parser-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-cca-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6epmtl' for glob 'lib*ipu6*'
Note, selecting 'libia-emd-decoder-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-isp-bxt-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libgcss-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-isp-bxt-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-isp-bxt-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-isp-bxt-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-exc-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-ccat-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-p2p-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6' for glob 'lib*ipu6*'
Note, selecting 'libia-mkn-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-lard-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libgcss-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-bcomp-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-bcomp-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-dvs-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-emd-decoder-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libia-mkn-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libipu6ep' for glob 'lib*ipu6*'
Note, selecting 'libcamhal-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-isp-bxt-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-emd-decoder-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-lard-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-exc-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-emd-decoder-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-lard-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-coordinate-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-bcomp-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libgcss-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-nvm-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-ccat-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-dvs-ipu60' for glob 'lib*ipu6*'
Note, selecting 'libbroxton-ia-pal-ipu6epmtl0' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-file-debug-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libia-lard-ipu6ep-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-log-ipu6epmtl-dev' for glob 'lib*ipu6*'
Note, selecting 'libia-aiq-file-debug-ipu6-0' for glob 'lib*ipu6*'
Note, selecting 'libia-mkn-ipu6ep0' for glob 'lib*ipu6*'
Note, selecting 'libipu6ep-dev' for regex 'lib*ipu7*'
Note, selecting 'libipu6-dev' for regex 'lib*ipu7*'
Note, selecting 'libipu6epmtl-dev' for regex 'lib*ipu7*'
Note, selecting 'libipu6epmtl' for regex 'lib*ipu7*'
Note, selecting 'libipu6' for regex 'lib*ipu7*'
Note, selecting 'libipu6ep' for regex 'lib*ipu7*'
E: Unable to locate package intel-ivsc-*
E: Couldn't find any package by glob 'intel-ivsc-*'
E: Couldn't find any package by regex 'intel-ivsc-*'
[ipu6_install_v6] Checking IPU6 firmware...
[ipu6_install_v6] Installing Jammy HWE kernel + IPU6 & USBIO module metas...
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
The following additional packages will be installed:
  grub-common grub-gfxpayload-lists grub-pc grub-pc-bin grub2-common linux-headers-6.8.0-84-generic linux-headers-generic-hwe-22.04 linux-hwe-6.8-headers-6.8.0-84 linux-hwe-6.8-tools-6.8.0-84 linux-image-6.8.0-84-generic linux-image-generic-hwe-22.04 linux-modules-6.8.0-84-generic
  linux-modules-extra-6.8.0-84-generic linux-modules-ipu6-6.8.0-84-generic linux-modules-usbio-6.8.0-84-generic linux-tools-6.8.0-84-generic os-prober
Suggested packages:
  multiboot-doc grub-emu xorriso desktop-base linux-hwe-6.8-tools
Recommended packages:
  ubuntu-kernel-accessories
The following NEW packages will be installed:
  grub-common grub-gfxpayload-lists grub-pc grub-pc-bin grub2-common linux-generic-hwe-22.04 linux-headers-6.8.0-84-generic linux-headers-generic-hwe-22.04 linux-hwe-6.8-headers-6.8.0-84 linux-hwe-6.8-tools-6.8.0-84 linux-image-6.8.0-84-generic linux-image-generic-hwe-22.04 linux-modules-6.8.0-84-generic
  linux-modules-extra-6.8.0-84-generic linux-modules-ipu6-6.8.0-84-generic linux-modules-ipu6-generic-hwe-22.04 linux-modules-usbio-6.8.0-84-generic linux-modules-usbio-generic-hwe-22.04 linux-tools-6.8.0-84-generic os-prober
0 upgraded, 20 newly installed, 0 to remove and 0 not upgraded.
Need to get 146 MB of archives.
After this operation, 789 MB of additional disk space will be used.
Get:1 http://apt.pop-os.org/ubuntu jammy/main amd64 grub-gfxpayload-lists amd64 0.7 [3,658 B]
Get:2 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 grub-common amd64 2.06-2ubuntu7.2 [2,214 kB]
Get:3 http://apt.pop-os.org/ubuntu jammy/main amd64 os-prober amd64 1.79ubuntu2 [19.3 kB]
Get:4 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 grub2-common amd64 2.06-2ubuntu7.2 [652 kB]
Get:5 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 grub-pc-bin amd64 2.06-2ubuntu7.2 [1,083 kB]
Get:6 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 grub-pc amd64 2.06-2ubuntu7.2 [132 kB]
Get:7 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-modules-6.8.0-84-generic amd64 6.8.0-84.84~22.04.1 [26.3 MB]
Get:8 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-image-6.8.0-84-generic amd64 6.8.0-84.84~22.04.1 [14.8 MB]
Get:9 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-modules-extra-6.8.0-84-generic amd64 6.8.0-84.84~22.04.1 [79.4 MB]
Get:10 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-image-generic-hwe-22.04 amd64 6.8.0-84.84~22.04.1 [2,496 B]
Get:11 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-hwe-6.8-headers-6.8.0-84 all 6.8.0-84.84~22.04.1 [13.5 MB]
Get:12 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-headers-6.8.0-84-generic amd64 6.8.0-84.84~22.04.1 [3,616 kB]
Get:13 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-headers-generic-hwe-22.04 amd64 6.8.0-84.84~22.04.1 [2,322 B]
Get:14 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-generic-hwe-22.04 amd64 6.8.0-84.84~22.04.1 [1,724 B]
Get:15 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-hwe-6.8-tools-6.8.0-84 amd64 6.8.0-84.84~22.04.1 [4,357 kB]
Get:16 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-modules-ipu6-6.8.0-84-generic amd64 6.8.0-84.84~22.04.1 [271 kB]
Get:17 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-modules-ipu6-generic-hwe-22.04 amd64 6.8.0-84.84~22.04.1 [2,406 B]
Get:18 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-modules-usbio-6.8.0-84-generic amd64 6.8.0-84.84~22.04.1 [71.5 kB]
Get:19 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-modules-usbio-generic-hwe-22.04 amd64 6.8.0-84.84~22.04.1 [2,416 B]
Get:20 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 linux-tools-6.8.0-84-generic amd64 6.8.0-84.84~22.04.1 [1,822 B]
Fetched 146 MB in 6s (24.8 MB/s)                          
Preconfiguring packages ...
Selecting previously unselected package grub-common.
(Reading database ... 281086 files and directories currently installed.)
Preparing to unpack .../00-grub-common_2.06-2ubuntu7.2_amd64.deb ...
Unpacking grub-common (2.06-2ubuntu7.2) ...
Selecting previously unselected package grub2-common.
Preparing to unpack .../01-grub2-common_2.06-2ubuntu7.2_amd64.deb ...
Unpacking grub2-common (2.06-2ubuntu7.2) ...
Selecting previously unselected package grub-pc-bin.
Preparing to unpack .../02-grub-pc-bin_2.06-2ubuntu7.2_amd64.deb ...
Unpacking grub-pc-bin (2.06-2ubuntu7.2) ...
Selecting previously unselected package grub-pc.
Preparing to unpack .../03-grub-pc_2.06-2ubuntu7.2_amd64.deb ...
Unpacking grub-pc (2.06-2ubuntu7.2) ...
Selecting previously unselected package grub-gfxpayload-lists.
Preparing to unpack .../04-grub-gfxpayload-lists_0.7_amd64.deb ...
Unpacking grub-gfxpayload-lists (0.7) ...
Selecting previously unselected package linux-modules-6.8.0-84-generic.
Preparing to unpack .../05-linux-modules-6.8.0-84-generic_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-modules-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-image-6.8.0-84-generic.
Preparing to unpack .../06-linux-image-6.8.0-84-generic_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-image-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-modules-extra-6.8.0-84-generic.
Preparing to unpack .../07-linux-modules-extra-6.8.0-84-generic_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-modules-extra-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-image-generic-hwe-22.04.
Preparing to unpack .../08-linux-image-generic-hwe-22.04_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-image-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-hwe-6.8-headers-6.8.0-84.
Preparing to unpack .../09-linux-hwe-6.8-headers-6.8.0-84_6.8.0-84.84~22.04.1_all.deb ...
Unpacking linux-hwe-6.8-headers-6.8.0-84 (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-headers-6.8.0-84-generic.
Preparing to unpack .../10-linux-headers-6.8.0-84-generic_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-headers-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-headers-generic-hwe-22.04.
Preparing to unpack .../11-linux-headers-generic-hwe-22.04_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-headers-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-generic-hwe-22.04.
Preparing to unpack .../12-linux-generic-hwe-22.04_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-hwe-6.8-tools-6.8.0-84.
Preparing to unpack .../13-linux-hwe-6.8-tools-6.8.0-84_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-hwe-6.8-tools-6.8.0-84 (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-modules-ipu6-6.8.0-84-generic.
Preparing to unpack .../14-linux-modules-ipu6-6.8.0-84-generic_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-modules-ipu6-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-modules-ipu6-generic-hwe-22.04.
Preparing to unpack .../15-linux-modules-ipu6-generic-hwe-22.04_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-modules-ipu6-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-modules-usbio-6.8.0-84-generic.
Preparing to unpack .../16-linux-modules-usbio-6.8.0-84-generic_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-modules-usbio-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-modules-usbio-generic-hwe-22.04.
Preparing to unpack .../17-linux-modules-usbio-generic-hwe-22.04_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-modules-usbio-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package linux-tools-6.8.0-84-generic.
Preparing to unpack .../18-linux-tools-6.8.0-84-generic_6.8.0-84.84~22.04.1_amd64.deb ...
Unpacking linux-tools-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Selecting previously unselected package os-prober.
Preparing to unpack .../19-os-prober_1.79ubuntu2_amd64.deb ...
Unpacking os-prober (1.79ubuntu2) ...
Setting up linux-hwe-6.8-headers-6.8.0-84 (6.8.0-84.84~22.04.1) ...
Setting up linux-headers-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
/etc/kernel/header_postinst.d/dkms:
 * dkms: running auto installation service for kernel 6.8.0-84-generic

Kernel preparation unnecessary for this kernel. Skipping...

Building module:
cleaning build area...
unset ARCH; [ ! -h /usr/bin/cc ] && export CC=/usr/bin/gcc; env NV_VERBOSE=1 'make' -j16 NV_EXCLUDE_BUILD_MODULES='' KERNEL_UNAME=6.8.0-84-generic IGNORE_XEN_PRESENCE=1 IGNORE_CC_MISMATCH=1 SYSSRC=/lib/modules/6.8.0-84-generic/build LD=/usr/bin/ld.bfd CONFIG_X86_KERNEL_IBT= modules..........
cleaning build area...

nvidia.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/kernel/drivers/char/drm/

nvidia-modeset.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/kernel/drivers/char/drm/

nvidia-drm.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/kernel/drivers/char/drm/

nvidia-uvm.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/kernel/drivers/char/drm/

nvidia-peermem.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/kernel/drivers/char/drm/

depmod...

Kernel preparation unnecessary for this kernel. Skipping...

Building module:
cleaning build area...
make -j22 KERNELRELEASE=6.8.0-84-generic -C /lib/modules/6.8.0-84-generic/build M=/var/lib/dkms/system76/1.0.21~1758595259~22.04~d3d9ce2/build...
cleaning build area...

system76.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/updates/dkms/

depmod...

Kernel preparation unnecessary for this kernel. Skipping...

Building module:
cleaning build area...
make -j22 KERNELRELEASE=6.8.0-84-generic -C /lib/modules/6.8.0-84-generic/build M=/var/lib/dkms/system76_acpi/1.0.2~1719257749~22.04~7bae1af/build...
cleaning build area...

system76_acpi.ko:
Running module version sanity check.
 - Original module
   - Found /lib/modules/6.8.0-84-generic/kernel/drivers/platform/x86/system76_acpi.ko
   - Storing in /var/lib/dkms/system76_acpi/original_module/6.8.0-84-generic/x86_64/
   - Archiving for uninstallation purposes
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/updates/dkms/

depmod...

Kernel preparation unnecessary for this kernel. Skipping...

Building module:
cleaning build area...
make -j22 KERNELRELEASE=6.8.0-84-generic -C /lib/modules/6.8.0-84-generic/build M=/var/lib/dkms/system76-io/1.0.4~1732138800~22.04~fc71f15/build...
cleaning build area...

system76-io.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/updates/dkms/

system76-thelio-io.ko:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/6.8.0-84-generic/updates/dkms/

depmod...
   ...done.
Setting up linux-modules-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Setting up grub-common (2.06-2ubuntu7.2) ...
Created symlink /etc/systemd/system/multi-user.target.wants/grub-common.service → /lib/systemd/system/grub-common.service.
Created symlink /etc/systemd/system/sleep.target.wants/grub-common.service → /lib/systemd/system/grub-common.service.
Created symlink /etc/systemd/system/multi-user.target.wants/grub-initrd-fallback.service → /lib/systemd/system/grub-initrd-fallback.service.
Created symlink /etc/systemd/system/rescue.target.wants/grub-initrd-fallback.service → /lib/systemd/system/grub-initrd-fallback.service.
Created symlink /etc/systemd/system/emergency.target.wants/grub-initrd-fallback.service → /lib/systemd/system/grub-initrd-fallback.service.
Created symlink /etc/systemd/system/sleep.target.wants/grub-initrd-fallback.service → /lib/systemd/system/grub-initrd-fallback.service.
update-rc.d: warning: start and stop actions are no longer supported; falling back to defaults
Setting up os-prober (1.79ubuntu2) ...
Setting up linux-image-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
I: /boot/vmlinuz.old is now a symlink to vmlinuz-6.16.3-76061603-generic
I: /boot/initrd.img.old is now a symlink to initrd.img-6.16.3-76061603-generic
I: /boot/vmlinuz is now a symlink to vmlinuz-6.8.0-84-generic
I: /boot/initrd.img is now a symlink to initrd.img-6.8.0-84-generic
Setting up linux-headers-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Setting up linux-modules-extra-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Setting up linux-hwe-6.8-tools-6.8.0-84 (6.8.0-84.84~22.04.1) ...
Setting up linux-image-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Setting up linux-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Setting up grub2-common (2.06-2ubuntu7.2) ...
Setting up linux-modules-ipu6-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Setting up grub-pc-bin (2.06-2ubuntu7.2) ...
Setting up linux-modules-usbio-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Setting up linux-tools-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
Setting up linux-modules-ipu6-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Setting up linux-modules-usbio-generic-hwe-22.04 (6.8.0-84.84~22.04.1) ...
Setting up grub-pc (2.06-2ubuntu7.2) ...

Creating config file /etc/default/grub with new version
Setting up grub-gfxpayload-lists (0.7) ...
Processing triggers for install-info (6.8-4build1) ...
Processing triggers for man-db (2.10.2-1) ...
Processing triggers for linux-image-6.8.0-84-generic (6.8.0-84.84~22.04.1) ...
/etc/kernel/postinst.d/dkms:
 * dkms: running auto installation service for kernel 6.8.0-84-generic
   ...done.
/etc/kernel/postinst.d/initramfs-tools:
update-initramfs: Generating /boot/initrd.img-6.8.0-84-generic
kernelstub.Config    : INFO     Looking for configuration...
kernelstub           : INFO     System information: 

    OS:..................Pop!_OS 22.04
    Root partition:....../dev/nvme0n1p1
    Root FS UUID:........647e0206-eb25-4d00-a050-d3797e55d5c7
    ESP Path:............/boot/efi
    ESP Partition:......./dev/nvme0n1p3
    ESP Partition #:.....3
    NVRAM entry #:.......-1
    Boot Variable #:.....0000
    Kernel Boot Options:.quiet loglevel=0 systemd.show_status=false splash
    Kernel Image Path:.../boot/vmlinuz-6.16.3-76061603-generic
    Initrd Image Path:.../boot/initrd.img-6.16.3-76061603-generic
    Force-overwrite:.....False

kernelstub.Installer : INFO     Copying Kernel into ESP
kernelstub.Installer : INFO     Copying initrd.img into ESP
kernelstub.Installer : INFO     Setting up loader.conf configuration
kernelstub.Installer : INFO     Making entry file for Pop!_OS
kernelstub.Installer : INFO     Backing up old kernel
kernelstub.Installer : INFO     Making entry file for Pop!_OS
/etc/kernel/postinst.d/zz-kernelstub:
kernelstub.Config    : INFO     Looking for configuration...
kernelstub           : INFO     System information: 

    OS:..................Pop!_OS 22.04
    Root partition:....../dev/nvme0n1p1
    Root FS UUID:........647e0206-eb25-4d00-a050-d3797e55d5c7
    ESP Path:............/boot/efi
    ESP Partition:......./dev/nvme0n1p3
    ESP Partition #:.....3
    NVRAM entry #:.......-1
    Boot Variable #:.....0000
    Kernel Boot Options:.quiet loglevel=0 systemd.show_status=false splash
    Kernel Image Path:.../boot/vmlinuz-6.16.3-76061603-generic
    Initrd Image Path:.../boot/initrd.img-6.16.3-76061603-generic
    Force-overwrite:.....False

kernelstub.Installer : INFO     Copying Kernel into ESP
kernelstub.Installer : INFO     Copying initrd.img into ESP
kernelstub.Installer : INFO     Setting up loader.conf configuration
kernelstub.Installer : INFO     Making entry file for Pop!_OS
kernelstub.Installer : INFO     Backing up old kernel
kernelstub.Installer : INFO     Making entry file for Pop!_OS
Could not determine installed HWE kernel version. Abort.

```

### Commands to test after script v7 execition

```bash
➜  helpers-bash-scripts git:(main) ✗ uname -r     
6.16.3-76061603-generic
➜  helpers-bash-scripts git:(main) ✗ lsmod | grep -E 'intel_ipu6|ivsc'
intel_ipu6_isys       122880  0
videobuf2_dma_sg       20480  1 intel_ipu6_isys
videobuf2_v4l2         36864  1 intel_ipu6_isys
videobuf2_common       86016  4 videobuf2_v4l2,intel_ipu6_isys,videobuf2_dma_sg,videobuf2_memops
intel_ipu6             73728  1 intel_ipu6_isys
ipu_bridge             20480  2 intel_ipu6,intel_ipu6_isys
v4l2_fwnode            40960  2 ov02c10,intel_ipu6_isys
v4l2_async             28672  3 v4l2_fwnode,ov02c10,intel_ipu6_isys
videodev              368640  5 v4l2_async,v4l2_fwnode,videobuf2_v4l2,ov02c10,intel_ipu6_isys
mc                     81920  6 v4l2_async,videodev,videobuf2_v4l2,ov02c10,intel_ipu6_isys,videobuf2_common
➜  helpers-bash-scripts git:(main) ✗ v4l2-ctl --list-devices
ipu6 (PCI:0000:00:05.0):
        /dev/video0
        /dev/video1
        /dev/video2
        /dev/video3
        /dev/video4
        /dev/video5
        /dev/video6
        /dev/video7
        /dev/video8
        /dev/video9
        /dev/video10
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
        /dev/media0

➜  helpers-bash-scripts git:(main) ✗ libcamera-hello
zsh: command not found: libcamera-hello
```
Snippet from `dmsg` command showing that the driver looks like installed

```bash
[   13.463003] intel-ipu6 0000:00:05.0: Sending AUTHENTICATE_RUN to CSE
[   13.482221] input: Samsung Galaxy Book Camera Lens Cover as /devices/platform/SAM0430:00/input/input27
```

Snippet from `dmesg` command showing that some configuration still missing
```bash
[  499.434974] gst-plugin-scan[9847]: segfault at c ip 000071626cc45456 sp 00007fff0bfc6a60 error 6 in libcamera.so.0.1.0[75456,71626cbff000+8b000] likely on CPU 2 (core 8, socket 0)                                                                                                                        
[  499.434980] Code: 00 00 4d 85 e4 74 0d 48 83 c4 08 4c 89 e0 5b 41 5c c3 66 90 4c 8b 25 c1 4d 07 00 48 89 c3 bf ba 00 00 00 31 c0 e8 9a a9 fb ff <41> 89 44 24 0c 4c 89 e0 4c 89 a3 20 00 00 00 48 83 c4 08 5b 41 5c
[  499.542965] gst-plugin-scan[9853]: segfault at c ip 0000709983d8a456 sp 00007ffdca4cc9d0 error 6 in libcamera.so.0.1.0[75456,709983d44000+8b000] likely on CPU 1 (core 8, socket 0)                                                                                                                        
[  499.542978] Code: 00 00 4d 85 e4 74 0d 48 83 c4 08 4c 89 e0 5b 41 5c c3 66 90 4c 8b 25 c1 4d 07 00 48 89 c3 bf ba 00 00 00 31 c0 e8 9a a9 fb ff <41> 89 44 24 0c 4c 89 e0 4c 89 a3 20 00 00 00 48 83 c4 08 5b 41 5c
```

### Printscreen svhwing that camera still not working
![img.png](img.png)
