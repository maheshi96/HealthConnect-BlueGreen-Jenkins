[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('blue', 'green')]
    [string]$TargetColour
)

$ErrorActionPreference = 'Stop'
$router = 'healthconnect-router'
$target = "healthconnect-$TargetColour"
$backup = Join-Path ([System.IO.Path]::GetTempPath()) "healthconnect-nginx-$([guid]::NewGuid()).conf"

try {
    $health = docker inspect --format '{{.State.Health.Status}}' $target 2>$null
    if ($LASTEXITCODE -ne 0 -or $health -ne 'healthy') {
        throw "Refusing cutover because $target is not healthy."
    }

    docker exec $target wget -qO- http://127.0.0.1:3000/health *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Refusing cutover because $target did not answer its health endpoint."
    }

    docker cp "${router}:/etc/nginx/conf.d/default.conf" $backup
    if ($LASTEXITCODE -ne 0) { throw 'Could not back up the current Nginx configuration.' }

    docker cp "nginx/$TargetColour.conf" "${router}:/etc/nginx/conf.d/default.conf"
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the candidate Nginx configuration.' }

    docker exec $router nginx -t
    if ($LASTEXITCODE -ne 0) {
        docker cp $backup "${router}:/etc/nginx/conf.d/default.conf" *> $null
        throw 'Candidate Nginx configuration is invalid; the previous configuration was restored.'
    }

    docker kill --signal HUP $router *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Nginx reload failed.' }

    for ($attempt = 1; $attempt -le 15; $attempt++) {
        $response = docker exec $router wget -qO- http://127.0.0.1:8080/version 2>$null
        if ($LASTEXITCODE -eq 0 -and $response -match ('"deployment"\s*:\s*"' + $TargetColour + '"')) {
            Write-Host "TRAFFIC SWITCH SUCCESSFUL: $TargetColour is active."
            exit 0
        }

        Start-Sleep -Seconds 1
    }

    docker cp $backup "${router}:/etc/nginx/conf.d/default.conf" *> $null
    docker kill --signal HUP $router *> $null
    throw 'Traffic confirmation failed; the previous Nginx configuration was restored.'
}
finally {
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
}
