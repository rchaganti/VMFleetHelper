#region copy archive functions
Function Copy-ArchiveFromUNC {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String]$Path,

        [Parameter()]
        [String]$Destination,

        [Parameter()]
        [PSCredential]$ShareCredential
    )
    #We have a UNC Path
    $copyArgs = @{
        Path        = $Path
        Destination = $Destination
    }
    
    #If ShareCredentials are specified, add them to parameters
    if ($ShareCredential)
    {
        $copyArgs.Add('Credential',$ShareCredential)
    }

    try
    {
        Write-Verbose -Message 'Copying Archive from the path provided.'
        Copy-Item @copyArgs -Force
    }
    catch
    {
        throw $_
    }
}

Function Copy-ArchiveFromURI {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String]$Source,

        [Parameter()]
        [String]$Destination
    )

        try
        {
            Write-Verbose -Message 'Downloading the Archive from the URI provided.'
            Invoke-WebRequest -Uri $Source -OutFile $Destination
        }
        catch
        {
            throw $_
        }
}

Function Copy-Archive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('Path')]
        [System.Uri]$URI

        [Parameter()]
        [Alias('OutFile')]
        [String]$Destination,

        [Parameter()]
        [PSCredential]$ShareCredential

    )

    if ($URI.IsUnc)
    {
        Copy-ArchiveFromUNC @PSBoundParameters
        
    }
     elseif (($URI.Scheme -eq 'https') -or ($URI.Scheme -eq 'https'))
    {
        Copy-ArchiveFromURI @PSBoundParameters
    }
    else
    {
        throw "copying archive supported from URI or UNC path."
    }
}

#endregion copy archive functions

# return a hashtable of the volume creation params based on the recommendation
Function Get-S2DClusterVolumeCreationParams 
{
    [OutputType([System.Collection.Hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Int] $VmCount=10,

        [Parameter(Mandatory)]
        [String] $VMTemplatePath,

        [Switch]$SkipMRV
    )
    # uses recommendation from here :
    # https://docs.microsoft.com/en-us/windows-server/storage/storage-spaces/create-volumes
    $HashTable = @{
        
    }
    $ClusterNodes = Get-ClusterNode -ErrorAction Stop
    # Below function determines the required size for the CSV volumes based on the number of VMs and
    # the template VHDX size
    $CSVSize = (Get-CSVSize -VMCount $VMCount -VMTemplatePath $VMTemplatePath) * 1GB
    if ($ClusterNodes.Count -le 3 ) 
    {
        # Case with 2 or 3 servers
        @{
            FileSystem = 'CSVFS_ReFS';
            Size = $CSVSize;
        }
    }
    else {
        # Case with 4+ nodes
        # check that MRV is to be created
        if ($SkipMRV.IsPresent)
        {
            @{
                FileSystem = 'CSVFS_ReFS';
                ResiliencySettingName = 'Mirror'; # Create Mirror volume (for performance)
                Size = $CSVSize
            }
        }
        else 
        { # -StorageTierfriendlyNames Performance,Capacity -StorageTierSizes 1TB , 200GB 
            @{
                FileSystem = 'CSVFS_ReFS';
                StorageTierfriendlyNames = @("Performance","Capacity")
                StorageTierSizes = @($CSVSize, 200GB)
            }
        }
        
    }
}


# WIP
Function Get-CSVSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Int] $VmCount,

        [Parameter(Mandatory)]
        [String] $VMTemplatePath,

        [Parameter()]
        [PSCredential]$ShareCredential,

        # Extra buffer space of 10GB added to the Disk
        [Parameter()]
        [Int]$BufferSize = 10

    )
    $Size = 1024 # This is the default size of 1024 GB (1TB)
    Try 
    {
        # Analyze the template VHD
        $FileInfo = Get-Item -Path $VMTemplatePath -Credential $ShareCredential -ErrorAction Stop
        $FileSize = [Math]::Round($($FileInfo.Length / 1GB))

        # Determine the total size requried for the required VMCount
        $Size = ($FileSize * $VMCount) + $BufferSize 

        # send the result back
        Write-Output -InputObject $Size
    }
    Catch 
    {
        Write-Warning -Message "$PSItem.Exception"
        # return default size
        Write-Warning -Message "Using default CSV Size of 1TB"
        Write-Output -InputObject $Size
    }
    
}