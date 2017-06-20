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
The below example downloads VMFleet framework and diskspd.exe from the sources provided in the script. This example assumes that the VMFleet VMs need to be created and the CSVs required for that will be provisioned as well.

```powershell
    $secpasswd = ConvertTo-SecureString 'Dell1234' -AsPlainText -Force
    $vmCreds = New-Object System.Management.Automation.PSCredential ('Administrator', $secpasswd)
    $hostConnectCreds = New-Object System.Management.Automation.PSCredential ('cloud\Administrator', $secpasswd)
    $shareCreds = New-Object System.Management.Automation.PSCredential ('cloud\Administrator', $secpasswd)
    
    .\Prepare-VMFleet.ps1 -VMTemplatePath \\100.12.132.21\vmstore\vmfleet.vhdx `
                          -VMAdministratorCredential $vmCreds `
                          -HostConnectCredential $hostConnectCreds `
                          -ShareCredential $shareCreds
```

### Example 2 ###
The below example downloads VMFleet framework and diskspd.exe from the sources provided in the script and updates the existing C:\VMFleet folder with the newly downloaded versions of VMFleet framework and diskspd.

```powershell
    $secpasswd = ConvertTo-SecureString 'Dell1234' -AsPlainText -Force
    $shareCreds = New-Object System.Management.Automation.PSCredential ('cloud\Administrator', $secpasswd)
    
    .\Prepare-VMFleet.ps1 -SkipVMCreation `
                          -SkipCSVCreation `
                          -ShareCredential $shareCreds
```

### Example 3 ###
The below example copies the VMFleet framework and diskspd archives from the UNC path and updates the existing C:\VMFleet folder.

```powershell
    $secpasswd = ConvertTo-SecureString 'Dell1234' -AsPlainText -Force
    $shareCreds = New-Object System.Management.Automation.PSCredential ('cloud\Administrator', $secpasswd)
    
    .\Prepare-VMFleet.ps1 -SkipVMCreation `
                          -SkipCSVCreation `
                          -ShareCredential $shareCreds `
                          -VMFleetArchive \\100.98.22.8\d$\vmfleet.zip `
                          -diskSpdArchive \\100.98.22.8\d$\diskspd.zip
```

## Run-RandomTemplate ##
The [Run-RandomTemplate.ps1](https://raw.githubusercontent.com/rchaganti/VMFleetHelper/master/Run-RandomTemplate.ps1) script is designed run vmfleet based on a random template selected from a list of available run templates.

### Parameters ###
| Parameter Name  | Description | Default Value | Is Mandatory? |
| -------------   | ------------- | ------------- | ------------- |
| NumberOfIterations | Specifies the number of vmfleet iterations.| 100 | No|
PauseBetweenIterationInSeconds | Specifies how long to pause between iterations. | 30 seconds | No|
|DeleteResultXml| Specifies if the result XML files should be deleted after each iteration. | False | No |
|FixedDuration| Specifies the fixed duration for each iteration. Valid range is 60-3600 seconds | - | No |
|BaseResultFolderName|Specifies the base folder name for storing the result xml for each iteration.|VmFleetTests|No|

### Example 1 ###
This example shows using Run-RandomTemplate.ps1 with fixed duration.

```powershell
    .\Run-RandomTemplate.ps1 -FixedDuration 120 -Verbose
```

### Example 2 ###
This example shows using Run-RandomTemplate.ps1 with fixed duration and less number of iterations.

```powershell
    .\Run-RandomTemplate.ps1 -NumberOfIterations 5 -FixedDuration 120 -Verbose
```
