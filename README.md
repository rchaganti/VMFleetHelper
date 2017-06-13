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
| diskSpdArchive  | 
| VmCount         |
| VmCpuCount      |
| VmMemory        |
| VMTemplatePath  | 
| VMAdministratorCredential |
| HostConnectCredential     |
| ShareCredential           | 
| SkipVMFleetCreation       | 
| SkipCSVCreation           |


### Example 1 ###
The below example downloads VMFleet framework and diskspd.exe from the sources provided in the script.

.\Prepare-VMFleet.ps1 -VMTemplatePath \\100.12.132.21\vmstore\vmfleet.vhdx 



