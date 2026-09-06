[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('blue', 'green')]
    [string]$TargetColour,

    [Parameter(Mandatory = $true)]
    [string]$ZapImage
)

$ErrorActionPreference = 'Stop'
$container = "healthconnect-zap-$env:BUILD_NUMBER"

function Invoke-DockerCommand {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Command 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

$null = Invoke-DockerCommand { docker rm -f $container }

$createResult = Invoke-DockerCommand {
    docker create --name $container `
        --label "healthconnect.ci.build=$env:BUILD_NUMBER" `
        --network healthconnect_net `
        $ZapImage `
        zap-baseline.py `
        -t "http://healthconnect-${TargetColour}:3000" `
        -c zap-baseline.conf `
        -r zap-report.html `
        -J zap-report.json
}

if ($createResult.ExitCode -ne 0) {
    throw 'Unable to create the OWASP ZAP container.'
}

$scanResult = Invoke-DockerCommand { docker start -a $container }
$zapExitCode = $scanResult.ExitCode
foreach ($line in @($scanResult.Output)) {
    Write-Host ([string]$line)
}

New-Item -ItemType Directory -Path reports -Force | Out-Null
$htmlCopy = Invoke-DockerCommand {
    docker cp "${container}:/zap/wrk/zap-report.html" reports/zap-report.html
}
$jsonCopy = Invoke-DockerCommand {
    docker cp "${container}:/zap/wrk/zap-report.json" reports/zap-report.json
}
$null = Invoke-DockerCommand { docker rm -f $container }

# ZAP baseline: 0 = pass, 1 = policy FAIL, 2 = warnings only, 3 = scan error.
if ($zapExitCode -eq 1 -or $zapExitCode -eq 3) {
    throw "OWASP ZAP failed with exit code $zapExitCode."
}

if ($htmlCopy.ExitCode -ne 0 -or $jsonCopy.ExitCode -ne 0) {
    throw 'OWASP ZAP completed but its HTML or JSON report could not be collected.'
}

if ($zapExitCode -eq 2) {
    Write-Host 'OWASP ZAP completed with reviewed warnings and no blocking failures.'
}
else {
    Write-Host 'OWASP ZAP baseline passed.'
}
