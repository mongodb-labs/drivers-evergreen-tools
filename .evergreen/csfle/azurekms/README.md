Scripts in this directory can be used to run driver CSFLE tests on a remote Azure Virtual Machine.

Use create-and-setup-vm.sh to create the remote Azure Virtual Machine.
Use delete-vm.sh to delete the remote Azure Virtual Machine.
The install-az.sh script installs the `az` command-line on the host (not the remote Virtual Machine). The host is assumed to be Ubuntu or Debian versions supported by the [Install the Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt#option-2-step-by-step-installation-instructions) instructions.

The image of the remote Virtual Machine defaults to `Debian`. It may be overridden with the environment variable `AZUREKMS_IMAGE` set to the value of `--image` in `az vm create`. See [Azure documentation](https://learn.microsoft.com/en-us/cli/azure/vm?view=azure-cli-latest#az-vm-create) for valid values (e.g. `UbuntuLTS`).