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

try {
    $healthProbe = Invoke-DockerCommand {
        docker inspect --format '{{.State.Health.Status}}' $target
    }
    $health = [string]($healthProbe.Output -join "`n")
    if ($healthProbe.ExitCode -ne 0 -or $health -ne 'healthy') {
        throw "Refusing cutover because $target is not healthy."
    }

    $targetProbe = Invoke-DockerCommand {
        docker exec $target wget -qO- http://127.0.0.1:3000/health
    }
    if ($targetProbe.ExitCode -ne 0) {
        throw "Refusing cutover because $target did not answer its health endpoint."
    }

    $backupResult = Invoke-DockerCommand {
        docker cp "${router}:/etc/nginx/conf.d/default.conf" $backup
    }
    if ($backupResult.ExitCode -ne 0) { throw 'Could not back up the current Nginx configuration.' }

    $copyResult = Invoke-DockerCommand {
        docker cp "nginx/$TargetColour.conf" "${router}:/etc/nginx/conf.d/default.conf"
    }
    if ($copyResult.ExitCode -ne 0) { throw 'Could not copy the candidate Nginx configuration.' }

    $nginxTest = Invoke-DockerCommand { docker exec $router nginx -t }
    if ($nginxTest.Output) { $nginxTest.Output | Write-Host }
    if ($nginxTest.ExitCode -ne 0) {
        $null = Invoke-DockerCommand {
            docker cp $backup "${router}:/etc/nginx/conf.d/default.conf"
        }
        throw 'Candidate Nginx configuration is invalid; the previous configuration was restored.'
    }

    $reloadResult = Invoke-DockerCommand { docker kill --signal HUP $router }
    if ($reloadResult.ExitCode -ne 0) { throw 'Nginx reload failed.' }

    for ($attempt = 1; $attempt -le 15; $attempt++) {
        $routeProbe = Invoke-DockerCommand {
            docker exec $router wget -qO- http://127.0.0.1:8080/version
        }
        $response = [string]($routeProbe.Output -join "`n")
        if ($routeProbe.ExitCode -eq 0 -and $response -match ('"deployment"\s*:\s*"' + $TargetColour + '"')) {
            Write-Host "TRAFFIC SWITCH SUCCESSFUL: $TargetColour is active."
            exit 0
        }

        Start-Sleep -Seconds 1
    }

    $null = Invoke-DockerCommand {
        docker cp $backup "${router}:/etc/nginx/conf.d/default.conf"
    }
    $null = Invoke-DockerCommand { docker kill --signal HUP $router }
    throw 'Traffic confirmation failed; the previous Nginx configuration was restored.'
}
finally {
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
}
