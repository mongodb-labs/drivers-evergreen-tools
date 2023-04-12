Scripts in this directory can be used to run driver CSFLE tests on a remote Azure Virtual Machine.

Use create-and-setup-vm.sh to create the remote Azure Virtual Machine.
Use delete-vm.sh to delete the remote Azure Virtual Machine.
The distro used must have the Azure Command-Line Interface (`az`) version 2.25.0 or higher installed. At time of writing, distros with `az` installed include:
- debian10
- debian11
- ubuntu1804
- ubuntu2004
- ubuntu2204
If another distro is required, consider filing a BUILD ticket similar to [BUILD-16836](https://jira.mongodb.org/browse/BUILD-16836).

The image of the remote Virtual Machine defaults to the URN `Debian:debian-11:11:0.20221020.1174`. It may be overridden with the environment variable `AZUREKMS_IMAGE` set to the value of `--image` in `az vm create`. See [Azure documentation](https://learn.microsoft.com/en-us/cli/azure/vm?view=azure-cli-latest#az-vm-create) for valid values.

The list of images may be determined with `az vm image --list`. The following script can get the latest version of the `debian-11` image:
```
LATEST_DEBIAN_URN=$(az vm image list -p Debian -s 11 --all --query "[?offer=='debian-11'].urn" -o tsv | sort -u | tail -n 1)
echo "LATEST_DEBIAN_URN=$LATEST_DEBIAN_URN"
```
The URN may be passed as `AZUREKMS_IMAGE`.
