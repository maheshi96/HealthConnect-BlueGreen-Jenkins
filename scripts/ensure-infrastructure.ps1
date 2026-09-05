[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ImageReference,

    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$env:APP_IMAGE_REF = $ImageReference
$env:APP_VERSION = $Version

docker inspect healthconnect-router *> $null
if ($LASTEXITCODE -eq 0) {
    docker start healthconnect-router *> $null

    for ($attempt = 1; $attempt -le 20; $attempt++) {
        docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/version *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'EXISTING ROUTER READY: current production route is reachable.'
            exit 0
        }

        Start-Sleep -Seconds 2
    }

    throw 'The existing router could not reach its current production environment.'
}

# A blue baseline is created only on the first run. Later runs must not alter live state.
docker inspect healthconnect-blue *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'No blue baseline exists; creating the initial known-good environment.'
    docker compose up -d --no-deps blue
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the blue baseline.' }
}
else {
    docker start healthconnect-blue *> $null
}

& "$PSScriptRoot/wait-for-health.ps1" -Colour blue -ExpectedVersion $Version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Creating the Nginx traffic router with blue as the initial target.'
docker compose up -d --no-deps --build router
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the HealthConnect router.' }

for ($attempt = 1; $attempt -le 20; $attempt++) {
    docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/health *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'BASELINE READY: router and blue environment are reachable.'
        exit 0
    }

    Start-Sleep -Seconds 2
}

throw 'The Nginx router did not become ready.'
