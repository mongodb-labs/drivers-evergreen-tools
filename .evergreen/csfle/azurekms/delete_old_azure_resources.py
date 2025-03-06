"""
Delete old Azure Virtual Machines and related orphaned resources.

Run with the shell script: delete_old_azure_resources.sh
"""

import argparse
import datetime
import os

from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.network import NetworkManagementClient


def main():
    # Parse args:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    # Create clients:
    sub_id = os.getenv("AZURE_SUBSCRIPTION_ID")
    resource_group_name = os.getenv("AZURE_RESOURCE_GROUP")
    cmclient = ComputeManagementClient(
        credential=DefaultAzureCredential(), subscription_id=sub_id
    )
    nmclient = NetworkManagementClient(
        credential=DefaultAzureCredential(), subscription_id=sub_id
    )

    # Delete old Virtual Machines:
    vm_names = []
    for vm in cmclient.virtual_machines.list(resource_group_name):
        try:
            now = datetime.datetime.now(tz=datetime.timezone.utc)
            delta = now - vm.time_created
            if delta < datetime.timedelta(hours=2):
                print(
                    f"{vm.name} is less than 2 hours old. Age is: {delta} ... skipping"
                )
                continue
            vm_names.append(vm.name)
        except Exception as e:
            print(f"Exception occurred: {e}")
    print(f"Detected old Virtual Machines: {vm_names}")
    if args.dry_run:
        print("Dry run detected. Not deleting.")
    else:
        for vm_name in vm_names:
            try:
                print(f"Deleting Virtual Machine '{vm_name}' ...")
                cmclient.virtual_machines.begin_delete(
                    resource_group_name, vm_name
                ).result()
                print(f"Deleting Virtual Machine '{vm_name}' ... done")
            except Exception as e:
                print(f"Exception occurred: {e}")

    # Get list of all Virtual Machine names to detect orphaned resources:
    all_vm_names = []  # Example: `vmname-RUBY-10561`
    for vm in cmclient.virtual_machines.list(resource_group_name):
        all_vm_names.append(vm.name)

    # Delete orphaned NSGs:
    orphan_nsg_names = []
    for nsg in nmclient.network_security_groups.list(resource_group_name):
        is_orphan = True
        for vm_name in all_vm_names:
            if vm_name + "-NSG" == nsg.name:
                is_orphan = False
                break
        if is_orphan:
            orphan_nsg_names.append(nsg.name)
    print(f"Detected orphaned NSGs: {orphan_nsg_names}")
    if args.dry_run:
        print("Dry run detected. Not deleting.")
    else:
        for nsg_name in orphan_nsg_names:
            try:
                print(f"Deleting orphaned NSG '{nsg_name}' ...")
                nmclient.network_security_groups.begin_delete(
                    resource_group_name, nsg_name
                ).result()
                print(f"Deleting orphaned NSG '{nsg_name}' ... done")
            except Exception as e:
                print(f"Exception occurred: {e}")

    # Delete orphaned IPs:
    orphan_ip_names = []
    for ip in nmclient.public_ip_addresses.list(resource_group_name):
        is_orphan = True
        for vm_name in all_vm_names:
            if vm_name + "-PUBLIC-IP" == ip.name:
                is_orphan = False
                break
        if is_orphan:
            orphan_ip_names.append(ip.name)
    print(f"Detected orphaned IPs: {orphan_ip_names}")
    if args.dry_run:
        print("Dry run detected. Not deleting.")
    else:
        for ip_name in orphan_ip_names:
            try:
                print(f"Deleting orphaned IP '{ip_name}' ...")
                nmclient.public_ip_addresses.begin_delete(
                    resource_group_name, ip_name
                ).result()
                print(f"Deleting orphaned IP '{ip_name}' ... done")
            except Exception as e:
                print(f"Exception occurred: {e}")


if __name__ == "__main__":
    main()
