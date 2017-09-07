[CmdletBinding()]
param(
    # Specify the cluster name the node will join
    [Parameter(Mandatory)]
    [String]$ClusterName,

    # Specify the name of the new node.
    [Parameter(Mandatory)]
    [Alias('Node','S2DNodeName')]
    [String]$ComputerName,

    # Switch to specify that if the Storage job does not kick off within the threshold time limit
    # then forcefully kick off the Optimize-StoragePool on the Storage spaces direct pool
    [Switch]$KickStartJob
)

Begin {
    Try {
        Import-Module -Name FailoverClusters -ErrorAction Stop
        Import-Module -Name $PSScriptRoot\helpers.psm1 -ErrorAction Stop
        
        # Ensure that this script is run from a cluster 
        $IsNodePartOfCluster = Get-Cluster -ErrorAction SilentlyContinue
        if ($IsNodePartOfCluster.Name -eq $ClusterName) {
            Write-Verbose -Message "$env:COMPUTERNAME is  part of the cluster $ClusterName"
        }
        else {
            throw "$env:COMPUTERNAME is not part of the cluster $ClusterName"
        }
    }
    Catch {
        Write-Warning -Message "Requires FailoverClusters module & needs to be run on one of the existing cluster node."
        $PSCmdlet.ThrowTerminatingError($PSitem)
    }
    $StartTime = Get-Date
}
Process {
        # Ping to see if the node is up
    $NodeUp = Test-Connection -ComputerName $ComputerName -Count 4 -Quiet
    if (-not $NodeUp) {
        # if ping fails, try to port check the WinRM service is up
        $NodeUp = (Test-NetConnection -ComputerName $ComputerName -CommonTCPPort WINRM).TcpTestSucceeded
    }

    if ($NodeUp) {
        Try {
            $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
            $Null = Add-ClusterNode -Name $ComputerName -ErrorAction Stop
            $ClusterNode = Get-ClusterNode -Name $ComputerName -ErrorAction Stop
        }
        Catch{
            # Throw warning and continue
            Write-Warning -Message "$PSitem.Exception"
        }
    }
    else {
        Write-Warning -Message "Node $ComputerName appears to be offline. Skipping adding to the cluster"
    }
}
End {
    if ($ClusterNode.State -eq 'Up') {
        # Check that at least one of the added cluster nodes is up. Otherwise no point in monitoring
        
        Try {
            # Sometime after adding the node to the cluster, the rebalance job kicks a little later
            # Below function monitors the Storage job queue until a new job appears in the queue
            $NewStorageJob = Wait-ForTheNewStorageJob -JobName Rebalance -Verbose -ErrorAction Stop
        }
        Catch {
            if ($KickStartJob) {
                # kick off the job forcefully and then begin monitoring monitor
                Write-Verbose -Message "Kicking off the Optimize job, since KickStartJob switch used."
                $UniqueId = (Get-StoragePool | Where-Object -FilterScript {$_.IsPrimordial -eq $false}).UniqueId
                Start-Job -ScriptBlock { Optimize-StoragePool -UniqueId $Using:UniqueId }
            }
        }
        Finally {
            if (-not $NewStorageJob) {
                $NewStorageJob = Get-StorageJob | 
                                    Where-Object -FilterScript {
                                        ($PSitem.Name -eq 'Rebalance') -and
                                        ($PSitem.JobState -eq 'Running')
                                    }
            }
            Monitor-StorageJob -InputObject $NewStorageJob -Verbose
        }
    }
    else {
        Write-Warning -Message "The cluster node $ComputerName state is not 'Up'. Skipping the monitoring"
    }
    $EndTime = Get-Date
    $TimeSpan = $EndTime - $StartTime
    Write-Host -Foreground Cyan -Object "Summary"
    Write-Host -ForeGround Green -Object "StartTime : $StartTime"
    Write-Host -ForeGround Green -Object "EndTime : $EndTime"
    Write-Host -ForeGround Green -Object "Time taken: $($TimeSpan | Out-String)"
}



# kick off the optimization of the Storage pool
<#
    $UniqueId = (Get-StoragePool | Where {$_.IsPrimordial -eq $false}).UniqueId
    Optimize-StoragePool -UniqueId $UniqueId
#>

