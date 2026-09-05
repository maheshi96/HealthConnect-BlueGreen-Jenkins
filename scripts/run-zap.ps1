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

docker rm -f $container *> $null

docker create --name $container `
    --label "healthconnect.ci.build=$env:BUILD_NUMBER" `
    --network healthconnect_net `
    $ZapImage `
    zap-baseline.py `
    -t "http://healthconnect-${TargetColour}:3000" `
    -c zap-baseline.conf `
    -r zap-report.html `
    -J zap-report.json | Out-Null

if ($LASTEXITCODE -ne 0) { throw 'Unable to create the OWASP ZAP container.' }

docker start -a $container
$zapExitCode = $LASTEXITCODE

New-Item -ItemType Directory -Path reports -Force | Out-Null
docker cp "${container}:/zap/wrk/zap-report.html" reports/zap-report.html
docker cp "${container}:/zap/wrk/zap-report.json" reports/zap-report.json
docker rm -f $container *> $null

# ZAP baseline: 0 = pass, 1 = warnings, 2/3 = release-blocking failure/error.
if ($zapExitCode -gt 1) {
    throw "OWASP ZAP failed with exit code $zapExitCode."
}

if ($zapExitCode -eq 1) {
    Write-Host 'OWASP ZAP completed with reviewed warnings and no blocking failures.'
}
else {
    Write-Host 'OWASP ZAP baseline passed.'
}
