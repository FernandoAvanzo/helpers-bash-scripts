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
