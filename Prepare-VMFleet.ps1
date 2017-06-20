[CmdletBinding()]
param (
    [Parameter()]
    [ValidateScript({})]
    [String] $vmFleetArchive = 'https://github.com/Microsoft/diskspd/archive/master.zip',

    [Parameter()]
    [String] $diskSpdArchive = 'https://gallery.technet.microsoft.com/DiskSpd-a-robust-storage-6cd2f223/file/152702/1/Diskspd-v2.0.17.zip',

    [Parameter()]
    [Int] $VmCount=10,

    [Parameter()]
    [Int] $VmCpuCount = 2,

    [Parameter()]
    [Long] $VmMemory = 4GB,

    [Parameter(Mandatory)]
    [ValidateScript({$vhdPath = Get-Item -Path $_; ($vhdPath.Extension -eq '.vhd') -or ($vhdPath.Extension -eq '.vhdx')})]
    [String] $VMTemplatePath,

    [Parameter(Mandatory)]
    [pscredential] $VMAdministratorCredential,

    [Parameter(Mandatory)]
    [pscredential] $HostConnectCredential,

    [Parameter()]
    [pscredential] $ShareCredential,

    [Parameter()]
    [Switch] $SkipVMFleetCreation,

    [Parameter()]
    [Switch] $SkipCSVCreation

)

process
{
    #region VMFleet files
    #Check if C:\Vmfleet exists and delete
    if (Test-Path -Path C:\VmFleet)
    {
        Write-Verbose -Message 'C:\VmFleet exists. This will be deleted'
        Remove-Item -Path C:\VMFleet -Recurse -Force
    }
    
    #check if we need to copy or download the VMFleet Archive
    $vmFleet = [System.Uri]$vmFleetArchive
    $vmFleetFileName = $vmFleet.Segments[-1]
    if ($vmFleet.IsUnc)
    {
        #We have a UNC Path
        $copyArgs = @{
            Path        = $vmFleetArchive
            Destination = "${env:TEMP}\${vmFleetFileName}"
        }
        
        #If ShareCredentials are specified, add them to parameters
        if ($ShareCredential)
        {
            $copyArgs.Add('Credential',$ShareCredential)
        }

        try
        {
            Write-Verbose -Message 'Copying VMFleet Archive from the path provided.'
            Copy-Item @copyArgs -Force
        }
        catch
        {
            throw $_
        }
    }
    elseif (($vmFleet.Scheme -eq 'https') -or ($vmFleet.Scheme -eq 'https'))
    {
        #we have a URL
        $downloadArgs = @{
            Uri = $vmFleetArchive
            OutFile = "${env:TEMP}\${vmFleetFileName}"
        }
        
        try
        {
            Write-Verbose -Message 'Downloading the VMFleet Archive from the path provided.'
            Invoke-WebRequest @downloadArgs
        }
        catch
        {
            throw $_
        }
    }

    #Extract the archive
    Write-Verbose -Message 'Unblocking and extracting the VM Fleet archive'
    Unblock-File -Path "${env:TEMP}\${vmFleetFileName}"
    Expand-Archive -Path "${env:TEMP}\${vmFleetFileName}" -DestinationPath $env:TEMP -Force

    #Copy VMFleet folder to C:\ as source for Install-VmFleet.ps1
    copy -Path "${env:Temp}\diskspd-master\Frameworks\VMFleet" -Destination C:\VMFleet -Recurse

    #Clean up Temp
    Remove-Item -Path "${env:TEMP}\${vmFleetFileName}" -Force
    Remove-Item -Path "${env:TEMP}\diskspd-master" -Recurse -Force
    #endregion

    #region diskspd
    #check if we need to copy or download the VMFleet Archive
    $diskSPD = [System.Uri]$diskSpdArchive
    $diskSPDFileName = $diskSPD.Segments[-1]
    if ($diskSPD.IsUnc)
    {
        #We have a UNC Path
        $copyArgs = @{
            Path        = $diskSpdArchive
            Destination = "${env:TEMP}\${diskSPDFileName}"
        }
        
        #If ShareCredentials are specified, add them to parameters
        if ($ShareCredential)
        {
            $copyArgs.Add('Credential',$ShareCredential)
        }

        try
        {
            Write-Verbose -Message 'Copying Diskspd Archive from the path provided.'
            Copy-Item @copyArgs -Force
        }
        catch
        {
            throw $_
        }
    }
    elseif (($diskSPD.Scheme -eq 'https') -or ($diskSPD.Scheme -eq 'https'))
    {
        #we have a URL
        $downloadArgs = @{
            Uri = $diskSpdArchive
            OutFile = "${env:TEMP}\${diskSPDFileName}"
        }
        
        try
        {
            Write-Verbose -Message 'Downloading the Diskspd Archive from the path provided.'
            Invoke-WebRequest @downloadArgs
        }
        catch
        {
            throw $_
        }
    }

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
    if (-not $SkipCSVCreation)
    {
        try
        {
            Write-Verbose -Message 'Creating CSV volumes for VMFleet runs'
            Get-ClusterNode |% { New-Volume -StoragePoolFriendlyName "S2D*" -FriendlyName $_ -FileSystem CSVFS_ReFS -StorageTierfriendlyNames Performance,Capacity -StorageTierSizes 1TB , 200GB }
            New-Volume -StoragePoolFriendlyName "*s2d*" -FriendlyName collect -FileSystem CSVFS_ReFS -StorageTierFriendlyNames Capacity -StorageTierSizes 1TB
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
    if (-not $SkipVMFleetCreation)
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