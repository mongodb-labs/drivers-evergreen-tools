Scripts in this directory can be used to run driver CSFLE tests on a remote Azure Virtual Machine.

Use create-and-setup-vm.sh to create the remote Azure Virtual Machine.
Use delete-vm.sh to delete the remote Azure Virtual Machine.
The install-az.sh script installs the `az` command-line on the host (not the remote Virtual Machine). The host is assumed to be Ubuntu or Debian versions supported by the [Install the Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt#option-2-step-by-step-installation-instructions) instructions.

The image of the remote Virtual Machine defaults to the URN `Debian:debian-11:11:0.20221020.1174`. It may be overridden with the environment variable `AZUREKMS_IMAGE` set to the value of `--image` in `az vm create`. See [Azure documentation](https://learn.microsoft.com/en-us/cli/azure/vm?view=azure-cli-latest#az-vm-create) for valid values.

The list of images may be determined with `az vm image --list`. The following script can get the latest version of the `debian-11` image:
```
LATEST_DEBIAN_URN=$(az vm image list -p Debian -s 11 --all --query "[?offer=='debian-11'].urn" -o tsv | sort -u | tail -n 1)
echo "LATEST_DEBIAN_URN=$LATEST_DEBIAN_URN"
```
The URN may be passed as `AZUREKMS_IMAGE`.
