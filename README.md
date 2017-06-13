# VMFleetHelper #
Helper scripts for VMFleet runs.

## Prepare-VMFleet ##
The [Prepare-VMFleet.ps1](https://raw.githubusercontent.com/rchaganti/VMFleetHelper/master/Prepare-VMFleet.ps1) script is designed to download VMFleet framework and Diskspd.exe binary or alternatively, copy the archives off a local UNC path and complete the VM fleet setup. This script creates VMFleet VMs as needed. The default VM Count is 10 with each VM having 2 vCPUs and 4GB of startup memory.

This script provisions the necessary CSV volumes for VMFleet runs.

This script should be run on any one of the Storage Spaces Direct cluster node.

### Parameters ###
| Parameter Name  | Description | Default Value | Is Mandatory? |
| -------------   | ------------- | ------------- | ------------- |
| vmFleetArchive  | Path to the VM Fleet download. This should be an archive of the https://github.com/Microsoft/diskspd Github repo and not just a VMFleet framework folder. This can be placed at a UNC path as well. If the UNC path requires authentication, you ca supply that using ShareCredential parameter. | https://github.com/Microsoft/diskspd/archive/master.zip | No |
| diskSpdArchive  |Path to the diskspd download. This can be placed at a UNC path as well. If the UNC path requires authentication, you ca supply that using ShareCredential parameter. |https://gallery.technet.microsoft.com/DiskSpd-a-robust-storage-6cd2f223/file/152702/1/Diskspd-v2.0.17.zip | No |
| VmCount         | Number of VM Fleet VMs to be provisioned. | 10 | No |
| VmCpuCount      | Number of vCPUs per VM in the VM Fleet | 2 | No |
| VmMemory        | Startup memory to be assigned to each VM in VM Fleet | 4GB | No |
| VMTemplatePath  | Path to the VM fleet VM VHD/VHDX template file. If this is at a UNC path, you can use ShareCredential to supply the credentials needed for access.| - | Yes |
| VMAdministratorCredential | Local administrator credentials for the VM fleet VM | - | Yes |
| HostConnectCredential     | Host connection credentials for CSV access from the VM Fleet VM | - | Yes | 
| ShareCredential           | Share credentials to access the UNC path required for VmFleetArchive, DiskSpdArchive, and VMTemplatePath. | - | No |
| SkipVMFleetCreation       | A switch parameter to skip the VM fleet creation. | - | No | 
| SkipCSVCreation           | A switch parameter to skip the CSV creation. | - | No |


### Example 1 ###
The below example downloads VMFleet framework and diskspd.exe from the sources provided in the script.

.\Prepare-VMFleet.ps1 -VMTemplatePath \\100.12.132.21\vmstore\vmfleet.vhdx 



