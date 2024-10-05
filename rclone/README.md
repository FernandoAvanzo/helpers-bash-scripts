# Rclone Helper Scripts

### Known issues

- **the service do not mount the remote in the folder**
  > Check if the service is set to the right system user, and if the mount folder is owned by the right user.
  >
  > Use this command to get some service log:
  >
  > ```bash
  >      sudo journalctl -u rclone-mount.service --since "today"
  >   ```

### Backlog of Improvements

- [ ] Automate the download and installation process of Rclone
- [ ] Automate the creation of the Google Drive remote
- [ ] Update the `install.sh` script to better reflect its purpose, possibly renaming it to something like `local-setup`

### References
- [myNotion rclone references](https://www.notion.so/fernando-avanzo/stack-Rclone-f025b0d02a5e42c7b8c693d486f5e7d6?pvs=4)
- [myNotion rclone install](https://www.notion.so/fernando-avanzo/doc-Install-e6e7e3635a4044d5ac7644bbc00d50a5?pvs=4)
- [myNotion rclone google drive config](https://www.notion.so/fernando-avanzo/doc-Google-Drive-b8da28324f614fd9a1f849f2df124ef8?pvs=4)

### Dependencies
- [My CLI](https://github.com/FernandoAvanzo/helpers-bash-scripts/tree/main/BashLib)
- [1password](https://releases.1password.com/linux/8.10/#changelog)
- [1password-cli](https://developer.1password.com/docs/cli/get-started/?utm_medium=organic&utm_source=oph&utm_campaign=linux)
