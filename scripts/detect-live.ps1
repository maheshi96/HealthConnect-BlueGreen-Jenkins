[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$router = 'healthconnect-router'

docker inspect $router *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'HealthConnect router is not running.'
}

$response = docker exec $router wget -qO- http://127.0.0.1:8080/version 2>$null
if ($LASTEXITCODE -eq 0) {
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
$configuration = docker exec $router sh -c 'cat /etc/nginx/conf.d/default.conf' 2>$null
if ($configuration -match 'healthconnect-blue') {
    Write-Output 'blue'
    exit 0
}

if ($configuration -match 'healthconnect-green') {
    Write-Output 'green'
    exit 0
}

throw 'Unable to determine the active HealthConnect environment.'
