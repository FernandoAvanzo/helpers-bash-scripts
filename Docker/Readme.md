### About Docker

**Scripts based in the follows Dockers Installations Guides**

- [Install using the apt repository](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
- [Install Docker Desktop on Ubuntu](https://docs.docker.com/desktop/install/ubuntu/)

### Create the command `set-default-docker` and adjust the cron

1. Run the command:
    ```bash
    echo $(get-root-psw) | sudo -S ln -sf $MY_CLI/Docker/set-docker-default.sh /usr/bin/set-docker-default
    ```
2. Add the new command in the crontab:
    ```bash
    sudo crontab -e
    
    # In the crontab file, add the following line to set Docker default at reboot:
    @reboot set-docker-default
    ```
3. Save the file and restart the system. If everything goes well, the `docker.sock` will be set.
   
   

### Roadmap
- [ ] Implement a way to get the deb URL of the current version to not change the url each time that a new version is released

### References
 - [My Notion Sign in | Docker Docs](https://www.notion.so/fernando-avanzo/Sign-in-Docker-Docs-117b3def3e7c812fb8cdd5509cb8478c?pvs=4)
