# Rclone Helper Scripts

### Configure the `rclone-mount.service` to run at system startup

1. Run the command:
    ```bash
    sudo crontab -e
    ```
2. Add the following line to the file:
    ```bash
    @reboot init_rclone
    ```
3. To ensure that the service runs flawlessly at system startup, make the following additional changes:
    1. Edit the file `/etc/profile` to add the following environment variables:
       ```bash
         ### Custom Bash Scripts
         export MY_CLI="<absolute path to the local user>/Projects/helpers-bash-scripts"
         
         ### 1Password Token
         export OP_SERVICE_ACCOUNT_TOKEN="<token of 1password service account>"
         
         ### 1Password Secret Item Name
         export ROOT_SECRET_NAME="<name of secret item>" 
       ```   
    2. Edit the file `/etc/bash.bashrc` to add the following environment variables:
       ```bash
         ### Custom Bash Scripts
         export MY_CLI="<absolute path to the local user>/Projects/helpers-bash-scripts"
         
         ### 1Password Token
         export OP_SERVICE_ACCOUNT_TOKEN="<token of 1password service account>"
         
         ### 1Password Secret Item Name
         export ROOT_SECRET_NAME="<name of secret item>" 
       ```      
    3. Create the symbolic link `/root/.config/rclone` by running the command below:
       ```bash
         sudo ln -sf <absolute path to the local user>/.config/rclone /root/.config/rclone
       ```         
   4. Run the command `sudo chmod 777 ./rclone.conf` to ensure that all system user can properlly access the rclone configuration:
      ```bash
        sudo cd <absolute path to the local user>/.config/rclone
        sudo sudo chmod 777 ./rclone.conf
      ```   

4. Save all changes and restart the system. If everything is correct, the service should run at system startup.

### Known issues

- **The service does not mount the remote in the folder**
  > Check if the service is set to the correct system user, and if the mount folder is owned by the appropriate user.
  >
  > Use this command to get some service logs:
  >
  > ```bash
  > sudo journalctl -u rclone-mount.service --since "today"
  > ```

- **The remote folder is mounted but is empty**
  > Probably the Rclone token has expired.
  >
  > To generate a new one, open the terminal and type the following command:
  >
  > ```bash
  > init_rclone
  > ```
  > This command will generate a new token and restart the service. After that, the remote folder should work again.

### Backlog of Improvements

- [ ] Automate the download and installation process of Rclone
- [ ] Automate the creation of the Google Drive remote
- [ ] Automate the version update of Rclone
- [ ] Update the `install.sh` script to better reflect its purpose, possibly renaming it to something like `local-setup`
- [ ] Improve the flags of command `rclone mount` in the service, to improve the cache and sync data

### References
- [myNotion rclone install](https://www.notion.so/fernando-avanzo/doc-Install-e6e7e3635a4044d5ac7644bbc00d50a5?pvs=4)
- [myNotion rclone google drive config](https://www.notion.so/fernando-avanzo/doc-Google-Drive-b8da28324f614fd9a1f849f2df124ef8?pvs=4)
- [myNotion rclone references](https://www.notion.so/fernando-avanzo/stack-Rclone-f025b0d02a5e42c7b8c693d486f5e7d6?pvs=4)
- [myNotion rclone mount](https://www.notion.so/fernando-avanzo/doc-rclone-mount-d04ae044aaee4a439760cb5e42332b3e?pvs=4)

### Dependencies
- [My CLI](https://github.com/FernandoAvanzo/helpers-bash-scripts/tree/main/BashLib)
- [1password](https://releases.1password.com/linux/8.10/#changelog)
- [1password-cli](https://developer.1password.com/docs/cli/get-started/?utm_medium=organic&utm_source=oph&utm_campaign=linux)
