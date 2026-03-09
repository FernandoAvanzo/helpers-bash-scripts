
The script version 60 run faill, and the webcam is not working yeat. the change made to try to fix the previous issue broke the script.
Bellow are the error logs from the current state of the script.

Script: `ipu6_install_v60.sh` 
```bash
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v60.sh            
[sudo] password for fernandoavanzo: 
[2025-10-05 09:46:17] Host preflight…
[2025-10-05 09:46:22] Host v4l2loopback ready at /dev/video0
[2025-10-05 09:46:22] Noble rootfs present: /var/lib/machines/ipu6-noble
[2025-10-05 09:46:22] Configuring APT sources & keyrings inside container…
curl: (22) The requested URL returned error: 404
gpg: no valid OpenPGP data found.
➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v60.sh
[2025-10-05 09:46:58] Host preflight…
[2025-10-05 09:47:05] Host v4l2loopback ready at /dev/video0
[2025-10-05 09:47:05] Noble rootfs present: /var/lib/machines/ipu6-noble
[2025-10-05 09:47:05] Configuring APT sources & keyrings inside container…
File '/var/lib/machines/ipu6-noble/etc/apt/keyrings/intel-ipu6.gpg' exists. Overwrite? (y/N) curl: (22) The requested URL returned error: 404

Enter new filename: 
gpg: signal 2 caught ... exiting

➜  SamsungGalaxyNote git:(main) ✗ sudo ./ipu6_install_v60.sh
[2025-10-05 09:49:22] Host preflight…
[2025-10-05 09:49:27] Host v4l2loopback ready at /dev/video0
[2025-10-05 09:49:27] Noble rootfs present: /var/lib/machines/ipu6-noble
[2025-10-05 09:49:27] Configuring APT sources & keyrings inside container…
File '/var/lib/machines/ipu6-noble/etc/apt/keyrings/intel-ipu6.gpg' exists. Overwrite? (y/N) curl: (22) The requested URL returned error: 404
y
gpg: no valid OpenPGP data found.
```

Said that, explain why the current version of the script fail and find a fix that solve the problem and keep what work in the previuos version still working. And generate a new version of the script and explain the new approach and why it should work that time. And explain why the previous version fail and why the current version should work. Use websearch and knownledge base to get additional answer and mention all references and sites used to build the answer. Also use all processing power avaiable to build the answer. Do not stop work ultil build a valid answer
