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
        [System.Uri]$URI,

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


#region Functions for monitoring the S2D expansion scenarios
Function Wait-ForTheNewStorageJob {
    [CmdletBinding()]
    param(

        # Specify the name or pattern of the Job's name to look out for
        # S2D kicks off the job named Optimize or Rebalance when rebalancing the virtual disk
        # across nodes
        [Parameter()]
        [ValidateSet('Rebalance','Optimize')]
        [String]$JobName,

        # Specify the max time in seconds to wait for a new storage job to spin up
        [Parameter()]
        [int]$TotalSecondsToWait =  3600,

        # Specify time interval to wait between checking the Job queue
        [Parameter()]
        [int]$SleepWait
    )
    $StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
    $StopWatch.Start()
    $OriginalJobQueue = Get-StorageJob
    if ($OriginalJobQueue) {
        Write-Warning -Message "StorageJob queue alread has Jobs named > 
            $(($OriginalJobQueue | Select-Object -ExpandProperty Name) -join ';')"
    }

    While ($StopWatch.Elapsed.Seconds -lt $TotalSecondsToWait) 
    {
        $newJobQueue = Get-StorageJob
        $compareQueue = Compare-Object -ReferenceObject $newJobQueue -DifferenceObject $OriginalJobQueue |
                            Where-Object -Property SideIndicator -eq '<='

        if ($compareQueue) 
        {
            Write-Verbose -Message "New jobs found, seeing if the job name matches `*$JobName`* pattern"
            $newJobmatch = $compareQueue.InputObject | Where-Object -Property Name -like "*$JobName*"
            
            if ($newJobmatch) 
            {
                # Job matching the name found. Stop.
                $StopWatch.Stop()
                Write-Verbose -Message "New jobs found matching the pattern found in the storage job queue. Stopping the wait."
                Write-Host -Fore Green "New jobs found. Stop watch metric > $($StopWatch.Elapsed | Out-String)"
                return $newJobmatch # return the JobObject back
            }
            else 
            {
                Write-Verbose -Message "Job matching the $Jobname not found"
            }
            
        }
        Write-Verbose -Message "Sleeping $SleepWait seconds"
        Start-Sleep -Seconds $SleepWait        
    }
    $StopWatch.Stop()
    Write-Host -Foreground Red "No jobs spawned. Stop watch metric > $($StopWatch.Elapsed | Out-String)"
    # if the control reached here that means the new job never spawned in the max time
    throw "No new job spawned in the Storage job queue in time $(TotalSecondsToWait) seconds"
}

Function Monitor-StorageJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,
                    ValueFromPipeline)]
        [ Microsoft.Management.Infrastructure.CimInstance]$InputObject,

        [Parameter()]
        [int]$SleepInterval = 30
    )

    $UniqueJobId = $InputObject.UniqueId
    $Stop = $false
    $StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
    Write-Host -ForeGround Cyan -Object "Starting the monitoring"
    $StopWatch.Start()
    do 
    {
        # verify that there is a Job present. Some jobs e.g. Rebalance get deleted after completion
        $StorageJob = Get-StorageJob -UniqueId $UniqueJobId -ErrorAction SilentlyContinue
        if (-not $StorageJob) 
        {
            Write-Host -ForeGround Red "Job with name $($StorageJob.Name) and UniqueID $UniqueJobId not found."
            $Stop = $True
        }
        Write-Host "Time elapsed:" -ForegroundColor Cyan -NoNewLine
        write-Host "$($StopWatch.Elapsed.Hours) hours and $($StopWatch.Elapsed.Minutes) minutes elapsed since start" -ForegroundColor Cyan
        Write-Host -ForeGround Cyan -Object "====== Storage Job Queue ======"
        Get-StorageJob | Format-Table -AutoSize
        Write-Host -ForeGround Cyan -Object "====== Storage Job Queue ======"
        Write-Verbose -Message "Sleeping for $SleepInterval seconds."
        Start-Sleep -seconds $SleepInterval
    } while ( ($StorageJob.JobState -eq 'Running') -or $Stop)
    
    Write-Host "Stopping StopWatch" -ForegroundColor Cyan
    $StopWatch.Stop()
    Write-Host -ForegroundColor Green -Object "Stop watch metric > $($StopWatch.Elapsed | Out-String)"
    
}

#endregion


#region template functions
Function Set-TemplateArgument {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String]$Key,

        [Parameter()]
        [String]$Value,

        [Parameter()]
        [System.Collections.Hashtable]$InputObject
    )
    $InputObject['DiskSPDArgs'][$Key] = $Value
}
#endregion