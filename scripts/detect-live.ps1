[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$router = 'healthconnect-router'

function Invoke-DockerCommand {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Command 2>$null
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

$routerLookup = Invoke-DockerCommand {
    docker ps -a --filter 'name=^/healthconnect-router$' --format '{{.Names}}'
}
if ($routerLookup.ExitCode -ne 0 -or $routerLookup.Output -notcontains $router) {
    throw 'HealthConnect router is not running.'
}

$versionProbe = Invoke-DockerCommand {
    docker exec $router wget -qO- http://127.0.0.1:8080/version
}
$response = [string]($versionProbe.Output -join "`n")
if ($versionProbe.ExitCode -eq 0) {
    if ($response -match '"deployment"\s*:\s*"blue"') {
        Write-Output 'blue'
        exit 0
    }

    if ($response -match '"deployment"\s*:\s*"green"') {
        Write-Output 'green'
        exit 0
    }
}

# If the active application is unavailable, inspect the router configuration.
$configurationProbe = Invoke-DockerCommand {
    docker exec $router sh -c 'cat /etc/nginx/conf.d/default.conf'
}
$configuration = [string]($configurationProbe.Output -join "`n")
if ($configuration -match 'healthconnect-blue') {
    Write-Output 'blue'
    exit 0
}

if ($configuration -match 'healthconnect-green') {
    Write-Output 'green'
    exit 0
}

throw 'Unable to determine the active HealthConnect environment.'
