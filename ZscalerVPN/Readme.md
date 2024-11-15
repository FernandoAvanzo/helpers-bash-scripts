# Zscaler VPN

### Commands Utils
 - search for remain references of zscaler after remove the client
   ```bash
      sudo find / \( -type f -exec grep -i 'zscaler' {} + \) -o \( -type d -name '*zscaler*' \)
   ```

### References
- [Understanding Zscaler Client Connector App Downloads](https://help.zscaler.com/zscaler-client-connector/understanding-zscaler-client-connector-app-downloads)
- [Installing Prerequisite Dependencies](https://help.zscaler.com/zscaler-client-connector/customizing-zscaler-client-connector-install-options-linux#install-package-dependencies)
- [Installing the Application using the Zscaler Run File](https://help.zscaler.com/zscaler-client-connector/customizing-zscaler-client-connector-install-options-linux#install-application-run)
- [Installing the Application using the Debian Package](https://help.zscaler.com/zscaler-client-connector/customizing-zscaler-client-connector-install-options-linux#install-application-deb)
- [Installing with Command-Line Options using the Zscaler Run File](https://help.zscaler.com/zscaler-client-connector/customizing-zscaler-client-connector-install-options-linux#install-package-command-line)
- [Providing Command-Line Options with the Debian Package](https://help.zscaler.com/zscaler-client-connector/customizing-zscaler-client-connector-install-options-linux#install-package-command-line)
