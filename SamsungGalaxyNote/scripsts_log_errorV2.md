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
