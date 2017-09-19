[CmdletBinding()]
param (
    [Parameter()]
    [int] $NumberOfIterations = 100,

    [Parameter()]
    [ValidateRange(30,300)]
    [int] $PauseBetweenIterationInSeconds = 30,

    [Parameter()]
    [Switch] $DeleteResultXml = $false,

    [Parameter()]
    [ValidateRange(60,3600)]
    [Int] $FixedDuration,

    [Parameter()]
    [String] $BaseResultFolderName = 'VmFleetTests'
)

if ($FixedDuration)
{
    Write-Verbose -Message "Setting test run duration to a fixed value: ${FixedDuration}."
}
else
{
    Write-Verbose -Message 'Each test run will have a random duration determined at run time.'
}

$RunTemplates = @()
Foreach ($file in (Get-ChildItem -Path $PSScriptRoot\Templates\*.psd1 -ErrorAction SilentlyContinue)){
    $RunTemplates += Import-PowerShellDataFile -Path $File.Fullname
}

for ($i = 1; $i -le $NumberOfIterations; $i++)
{
    Write-Verbose -Message "[Iteration : ${i}] Starting VM Fleet ..."
    .\Start-VMFleet.ps1

    Write-Verbose -Message "[Iteration : ${i}] Sleeping for 30 seconds ..."
    Start-Sleep -Seconds 30

    Write-Verbose -Message "[Iteration : ${i}] Starting Sweep ..."
    $randomTemplate = $RunTemplates | Get-Random
    Write-Verbose -Message "[Iteration : ${i}] Selected template $($randomTemplate | Out-String)"
    if ($FixedDuration) 
    {
        Set-TemplateDuration -InputObject $RandomTemplate -Key d -Value $FixedDuration
    }
    else
    {
        Set-TemplateDuration -InputObject $RandomTemplate -Key d -Value $(Get-Random -Minimum 300 -Maximum 3600)
    }
    Write-Verbose -Message 
    .\Start-Sweep.ps1 @randomTemplate

    Write-Verbose -Message "[Iteration : ${i}] Sleeping for 30 seconds ..."
    Start-Sleep -Seconds 30

    if (-not ($DeleteResultXml))
    {
       Write-Verbose -Message "[Iteration : ${i}] Moving result XML files to run folder ..."
       $null = mkdir "C:\ClusterStorage\Collect\Control\Result\${BaseResultFolderName}\Run-${i}" -Force
       Move-Item 'C:\ClusterStorage\Collect\Control\Result\*.xml' "C:\ClusterStorage\Collect\Control\Result\${BaseResultFolderName}\Run-${i}"
    }
    else
    {
        Write-Verbose -Message "[Iteration : ${i}] Discarding all result XML files ..."
        Remove-Item 'C:\ClusterStorage\Collect\Control\Result\*.xml'
    }

    Write-Verbose -Message "[Iteration : ${i}] Setting pause on VMs ..."
    .\Set-Pause.ps1

    Write-Verbose -Message "[Iteration : ${i}] Checking pause and stopping VM fleet ..."
    if (.\check-pause.ps1 -isactive)
    {
        .\Stop-VMFleet.ps1
    }
    else
    {
        throw 'Unable set pause ...'
    }

    Write-Verbose -Message "[Iteration : ${i}] Sleeping for ${PauseBetweenIterationInSeconds} seconds ..."
    Start-Sleep -Seconds 30
}