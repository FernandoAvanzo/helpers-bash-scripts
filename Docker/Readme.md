### About Docker

**Scripts based in the follows Dockers Installations Guides**

- [Install using the apt repository](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
- [Install Docker Desktop on Ubuntu](https://docs.docker.com/desktop/install/ubuntu/)

### Config the default `docker.sock` using Docker desktop

1. Run the command:
    ```bash
      echo $(get-root-psw) | sudo -S ln -sf $MY_CLI/Docker/set-docker-default.sh /usr/bin/set-docker-default
    ```
2. Run the command:
   ```bash
      echo $(get-root-psw) | sudo -S ln -sf $MY_CLI/Docker/init_up_docker.sh /usr/bin/init_up_docker
   ```   

3. Add the new command in the crontab:
    ```bash
    sudo crontab -e
    
    # In the crontab file, add the following line to set Docker default at reboot:
    @reboot init_up_docker
    ```
4. Save the file and restart the system. If everything goes well, the `docker.sock` will be set.
   
### KVM Install Steps   

```bash
    cat /sys/hypervisor/properties/capabilities
```

```bash
    kvm-ok
```

```bash
    INFO: /dev/kvm exists
    KVM acceleration can be used
```

```bash
    egrep -c ' lm ' /proc/cpuinfo
```

```bash
    uname -m
```

```bash
    lsb_release -a
```

```bash
    $ sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
```

```bash
    $ sudo adduser `id -un` libvirtd
    Adding user '<username>' to group 'libvirtd' ...
```


```bash
    $ sudo adduser `id -un` libvirt
    Adding user '<username>' to group 'libvirt' ...
    $ sudo adduser `id -un` kvm
    Adding user '<username>' to group 'kvm' ...
```

```bash
    $ groups
    adm dialout cdrom floppy audio dip video plugdev fuse lpadmin admin sambashare kvm libvirtd
```

```bash
  $ sudo adduser `id -un` kvm
  Adding user '<username>' to group 'kvm' ...
  $ sudo adduser `id -un` libvirtd
  Adding user '<username>' to group 'libvirtd' ...
```

```bash
    $ virsh list --all
    Id Name                 State
    ----------------------------------

    $
```

```bash
    $ sudo ls -la /var/run/libvirt/libvirt-sock
    srwxrwx--- 1 root libvirtd 0 2010-08-24 14:54 /var/run/libvirt/libvirt-sock
```

```bash
     $ ls -l /dev/kvm
    crw-rw----+ 1 root root 10, 232 Jul  8 22:04 /dev/kvm
```

```bash
  sudo chown root:libvirtd /dev/kvm
```

```bash
  rmmod kvm
  modprobe -a kvm
```

### Roadmap
- [ ] Implement a way to get the deb URL of the current version to not change the url each time that a new version is released
- [ ] Improve the KVM Install steps

### Known issues

- **The service does not set the `/run/docker.sock`**
  > Check if the service is set to the correct system user.
  >
  > Use this command to get some service logs:
  >
  > ```bash
  >   sudo journalctl -u docker-up.service --since "today"
  > ```


### References
 - [My Notion Sign in | Docker Docs](https://www.notion.so/fernando-avanzo/Sign-in-Docker-Docs-117b3def3e7c812fb8cdd5509cb8478c?pvs=4)
 - [Config kvm support](https://docs.docker.com/desktop/setup/install/linux/#kvm-virtualization-support)
 - [kvm reference](https://linux-kvm.org/page/Main_Page)
 - [KVM/Installation - Ubuntu](https://help.ubuntu.com/community/KVM/Installation)
