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

function Invoke-DockerCommand {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    # Windows PowerShell converts expected native stderr into NativeCommandError.
    # Keep those probe failures non-terminating and make decisions from the exit code.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Command 2>$null
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

$routerLookup = Invoke-DockerCommand {
    docker ps -a --filter 'name=^/healthconnect-router$' --format '{{.Names}}'
}

if ($routerLookup.ExitCode -ne 0) {
    throw 'Unable to query Docker for the HealthConnect router.'
}

if ($routerLookup.Output -contains 'healthconnect-router') {
    $routerStart = Invoke-DockerCommand { docker start healthconnect-router }
    if ($routerStart.ExitCode -ne 0) {
        throw 'The existing HealthConnect router could not be started.'
    }

    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $routerProbe = Invoke-DockerCommand {
            docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/version
        }

        if ($routerProbe.ExitCode -eq 0) {
            Write-Host 'EXISTING ROUTER READY: current production route is reachable.'
            exit 0
        }

        Start-Sleep -Seconds 2
    }

    throw 'The existing router could not reach its current production environment.'
}

# A blue baseline is created only on the first run. Later runs must not alter live state.
$blueLookup = Invoke-DockerCommand {
    docker ps -a --filter 'name=^/healthconnect-blue$' --format '{{.Names}}'
}

if ($blueLookup.ExitCode -ne 0) {
    throw 'Unable to query Docker for the blue baseline.'
}

if ($blueLookup.Output -notcontains 'healthconnect-blue') {
    Write-Host 'No blue baseline exists; creating the initial known-good environment.'
    $blueCreate = Invoke-DockerCommand { docker compose up -d --no-deps blue }
    if ($blueCreate.Output) { $blueCreate.Output | Write-Host }
    if ($blueCreate.ExitCode -ne 0) { throw 'Unable to create the blue baseline.' }
}
else {
    $blueStart = Invoke-DockerCommand { docker start healthconnect-blue }
    if ($blueStart.ExitCode -ne 0) { throw 'Unable to start the existing blue baseline.' }
}

& "$PSScriptRoot/wait-for-health.ps1" -Colour blue -ExpectedVersion $Version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Creating the Nginx traffic router with blue as the initial target.'
$routerCreate = Invoke-DockerCommand { docker compose up -d --no-deps --build router }
if ($routerCreate.Output) { $routerCreate.Output | Write-Host }
if ($routerCreate.ExitCode -ne 0) { throw 'Unable to create the HealthConnect router.' }

for ($attempt = 1; $attempt -le 20; $attempt++) {
    $baselineProbe = Invoke-DockerCommand {
        docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/health
    }

    if ($baselineProbe.ExitCode -eq 0) {
        Write-Host 'BASELINE READY: router and blue environment are reachable.'
        exit 0
    }

    Start-Sleep -Seconds 2
}

throw 'The Nginx router did not become ready.'
