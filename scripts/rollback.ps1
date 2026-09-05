[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('blue', 'green')]
    [string]$PreviousColour,

    [Parameter(Mandatory = $true)]
    [ValidateSet('blue', 'green')]
    [string]$FailedColour
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path reports -Force | Out-Null
$timestamp = (Get-Date).ToUniversalTime().ToString('o')

"$timestamp ROLLBACK STARTED: $FailedColour -> $PreviousColour" | Tee-Object -FilePath reports/rollback.log -Append

& "$PSScriptRoot/switch-traffic.ps1" -TargetColour $PreviousColour
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

docker stop "healthconnect-$FailedColour" *> $null

$timestamp = (Get-Date).ToUniversalTime().ToString('o')
"$timestamp ROLLBACK SUCCESSFUL: $PreviousColour restored; $FailedColour stopped" | Tee-Object -FilePath reports/rollback.log -Append
