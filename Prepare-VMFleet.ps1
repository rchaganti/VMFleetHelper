[CmdletBinding()]
param (
    # Specify the link to the archive housing the VMFleet. Defaults to GitHub repo link
    [Parameter()]
    [ValidateScript({})]
    [String] $vmFleetArchive = 'https://github.com/Microsoft/diskspd/archive/master.zip',

    # Specify the link to the archive housing the DiskSPD. Defaults to Technet download link v2.0.17
    [Parameter()]
    [String] $diskSpdArchive = 'https://gallery.technet.microsoft.com/DiskSpd-a-robust-storage-6cd2f223/file/152702/1/Diskspd-v2.0.17.zip',

    #  the number of vms per node per csv (group) to create 
    [Parameter()]
    [Int] $VmCount=10,

    # Customize the individual VM CPU count
    [Parameter()]
    [Int] $VmCpuCount = 2,

    # Customize the individual VM Memory size
    [Parameter()]
    [Long] $VmMemory = 4GB,

    # Path to the template VHD for the VM creation
    [Parameter(Mandatory)]
    [ValidateScript({$vhdPath = Get-Item -Path $_; ($vhdPath.Extension -eq '.vhd') -or ($vhdPath.Extension -eq '.vhdx')})]
    [String] $VMTemplatePath,

    # password for the VM-local administrative user is only picked. Username is ignored.
    [Parameter(Mandatory)]
    [pscredential] $VMAdministratorCredential,

    # Credentials to establish the loopback connection to the host
    [Parameter(Mandatory)]
    [pscredential] $HostConnectCredential,

    # Specify share credential 
    # This share houses the template VHD or VMFleet/DiskSPD archives.
    [Parameter()]
    [pscredential] $ShareCredential,

    [Parameter()]
    [Switch] $SkipVMFleetCreation,

    [Parameter()]
    [Switch] $SkipCSVCreation,

    # Specify this switch to skip creation of Multi-resilient volumes (less performant as of now)
    [Switch]$SkipMRV

)

process
{
    #region VMFleet files
    #Check if C:\Vmfleet exists and delete
    if (Test-Path -Path C:\VmFleet)
    {
        Write-Warning -Message 'C:\VmFleet exists. This will be deleted'
        Remove-Item -Path C:\VMFleet -Recurse -Force
    }
    
    #check if we need to copy or download the VMFleet Archive
    $vmFleet = [System.Uri]$vmFleetArchive
    $vmFleetFileName = $vmFleet.Segments[-1]
    Copy-Archive -URI $vmFleet -Destination "${env:TEMP}\${vmFleetFileName}" -ShareCredential $ShareCredential
 
    #Extract the archive
    Write-Verbose -Message 'Unblocking and extracting the VM Fleet archive'
    Unblock-File -Path "${env:TEMP}\${vmFleetFileName}"
    Expand-Archive -Path "${env:TEMP}\${vmFleetFileName}" -DestinationPath $env:TEMP -Force

    #Copy VMFleet folder to C:\ as source for Install-VmFleet.ps1
    Copy-Item -Path "${env:Temp}\diskspd-master\Frameworks\VMFleet" -Destination C:\VMFleet -Recurse

    #Clean up Temp
    Remove-Item -Path "${env:TEMP}\${vmFleetFileName}" -Force
    Remove-Item -Path "${env:TEMP}\diskspd-master" -Recurse -Force
    #endregion

    #region diskspd
    #check if we need to copy or download the VMFleet Archive
    $diskSPD = [System.Uri]$diskSpdArchive
    $diskSPDFileName = $diskSPD.Segments[-1]
    Copy-Archive -URI $diskSPD -Destination "${env:TEMP}\${diskSPDFileName}" -ShareCredential $ShareCredential

    #Extract the archive
    Write-Verbose -Message 'Unblocking and extracting the Diskspd archive'
    Unblock-File -Path "${env:TEMP}\${diskSPDFileName}"
    Expand-Archive -Path "${env:TEMP}\${diskSPDFileName}" -DestinationPath "${env:TEMP}\diskspd" -Force

    #Copy diskspd.exe to c:\vmfleet
    Copy-Item -Path "${env:TEMP}\diskspd\amd64fre\diskspd.exe" -Destination C:\VMFleet -Force

    #cleanup diskspd files
    Remove-Item -Path "${env:TEMP}\${diskSPDFileName}" -Force
    Remove-Item -Path "${env:TEMP}\diskspd" -Recurse -Force
    #endregion     

    #region CSV setup
    if (-not $SkipCSVCreation.ISPresent)
    {
        try
        {
            Write-Verbose -Message 'Creating CSV volumes for VMFleet runs'
            $NewVolumeParam = Get-S2DClusterVolumeCreationParam # This is a helper function to generate params automatically for CSV creation below
            Get-ClusterNode |% { New-Volume -StoragePoolFriendlyName "S2D*" -FriendlyName $_ @NewVolumeParam }
            New-Volume -StoragePoolFriendlyName "*s2d*" -FriendlyName collect -FileSystem CSVFS_ReFS -Size 1TB 
        }
        catch
        {
            thorw $_
        }
    }
    #endregion

    #region install-VMFleet
    try
    {
        Write-Verbose -Message 'Copying VM Fleet files'
        Set-Location -Path C:\VMFleet
        .\install-vmfleet.ps1 -source C:\VMFleet

        #Copy diskspd
        Write-Verbose -Message 'Copying diskspd'
        Copy-Item -Path C:\VMFleet\diskspd.exe -Destination C:\ClusterStorage\Collect\Control\Tools -Force
    }
    catch
    {
        throw $_
    }
    #endregion

    #region create VM Fleet
    if (-not $SkipVMFleetCreation.ISPresent)
    {
        #region VM template
        #Verify if template VHD exists or not
        if (Test-Path -Path $VMTemplatePath)
        {
            $vhdName = Split-Path $VMTemplatePath -Leaf
            $vhdCopyArgs = @{
                Path = $VMTemplatePath
                Destination = "C:\ClusterStorage\Collect\${vhdName}"
            }

            if ($ShareCredential)
            {
                Credential = $ShareCredential
            }
        
            try
            {
                Write-Verbose -Message 'Copying VM template VHDX. This may take a while.'
                Copy-Item @vhdCopyArgs -Force
            }
            catch
            {
                throw $_
            }   
        }
        else
        {
            Write-Error -Message "${VMTemplatePath} does not exist"
        }
        #endregion

        #region Update CSV
        Write-Verbose -Message 'updating CSV mount points'
        .\update-csv.ps1 -renamecsvmounts:$true
        #endregion
        Write-Verbose -Message 'Creating VM Fleet'
        .\create-vmfleet.ps1 -BaseVHD "C:\ClusterStorage\Collect\${vhdName}" -VMs $VmCount -AdminPass $VMAdministratorCredential.GetNetworkCredential().Password -ConnectUser $HostConnectCredential.UserName -ConnectPass $HostConnectCredential.GetNetworkCredential().Password
        
        Write-Verbose -Message 'updating VM fleet configuration'
        .\set-vmfleet.ps1 -ProcessorCount $VmCpuCount -MemoryStartupBytes $VmMemory -MemoryMaximumBytes $VmMemory -MemoryMinimumBytes $VmMemory
    }
    #endregion
}