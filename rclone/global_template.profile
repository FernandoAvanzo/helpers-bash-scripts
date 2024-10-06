# /etc/profile: system-wide .profile file for the Bourne shell (sh(1))
# and Bourne compatible shells (bash(1), ksh(1), ash(1), ...).

if [ "${PS1-}" ]; then
  if [ "${BASH-}" ] && [ "$BASH" != "/bin/sh" ]; then
    # The file bash.bashrc already sets the default PS1.
    # PS1='\h:\w\$ '
    if [ -f /etc/bash.bashrc ]; then
      . /etc/bash.bashrc
    fi
  else
    if [ "$(id -u)" -eq 0 ]; then
      PS1='# '
    else
      PS1='$ '
    fi
  fi
fi

if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh; do
    if [ -r $i ]; then
      . $i
    fi
  done
  unset i
fi
### Custom Bash Scripts
export MY_CLI="/home/fernandoavanzo/Projects/helpers-bash-scripts"

### 1Password System Vault Name
export OP_SERVICE_ACCOUNT_TOKEN=ops_eyJzaWduSW5BZGRyZXNzIjoibXkuMXBhc3N3b3JkLmNvbSIsInVzZXJBdXRoIjp7Im1ldGhvZCI6IlNSUGctNDA5NiIsImFsZyI6IlBCRVMyZy1IUzI1NiIsIml0ZXJhdGlvbnMiOjY1MDAwMCwic2FsdCI6InE2dE0tYzNtRDhiNUp2OHh1YVZsUmcifSwiZW1haWwiOiJ5Z3hmcm0zb21oY3NtQDFwYXNzd29yZHNlcnZpY2VhY2NvdW50cy5jb20iLCJzcnBYIjoiM2E5NDdhZmZhMDQ5NTAxZjkxYzk5MGFiY2JiYWRlZjFjMjM5Y2Q3YTMxYmI1MmQyZjUzOTA2Y2UxOTA1OTYwYiIsIm11ayI6eyJhbGciOiJBMjU2R0NNIiwiZXh0Ijp0cnVlLCJrIjoiVVpleERsLVgyUWxpa0VqRjVUUjRoODhOd29ZcHRqSHptQmFTdlNrWGZmZyIsImtleV9vcHMiOlsiZW5jcnlwdCIsImRlY3J5cHQiXSwia3R5Ijoib2N0Iiwia2lkIjoibXAifSwic2VjcmV0S2V5IjoiQTMtNDZGUUVNLUVZS1hTQS1NUU0yUy04U0JSUS01QjZGUC1HS1k2ViIsInRocm90dGxlU2VjcmV0Ijp7InNlZWQiOiJjZmU2ZTU0NGUxZTlmY2NmZjJlYjBhYWZmYTEzNjZlMmE2ZmUwZDVlZGI2ZTUzOTVkZTljZmY0NDY3NDUxOGUxIiwidXVpZCI6IjNVMjRMNVdCNkpFQ0pEQlhJNFZOSTRCUzNRIn0sImRldmljZVV1aWQiOiJqaGVlY3F4cm41YTV6ZzRpMnlkbjRqd3U3dSJ9

export ROOT_SECRET_NAME="Galaxy-Book_4-Ultra"
