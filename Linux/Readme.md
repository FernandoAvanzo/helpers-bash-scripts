# Linux Scripts

### Install Linux tools Ubuntu
```bash
    echo "$(get-root-psw)" | sudo -S apt install -y fdutils linux-tools-realtime linux-tools-virtual-hwe-24.04-edge linux-tools-virtual-hwe-24.04 linux-tools-virtual linux-tools-oracle linux-tools-lowlatency linux-tools-generic-hwe-24.04-edge linux-tools-generic-hwe-24.04 linux-tools-generic linux-tools-gcp  linux-tools-azure linux-tools-aws floppyd
```

### Install Linux tools PopOs
```bash
    echo "$(get-root-psw)" | sudo -S apt install -y fdutils linux-tools-realtime linux-tools-virtual linux-tools-oracle linux-tools-lowlatency linux-tools-generic linux-tools-gcp  linux-tools-azure linux-tools-aws floppyd
```

### References

- [Cleaning Ubuntu](https://github.com/polkaulfield/ubuntu-debullshit)
