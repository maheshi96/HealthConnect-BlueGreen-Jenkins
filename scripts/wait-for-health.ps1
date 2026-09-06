[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('blue', 'green')]
    [string]$Colour,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [int]$Attempts = 30,
    [int]$DelaySeconds = 2
)

$ErrorActionPreference = 'Stop'
$container = "healthconnect-$Colour"

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

for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $healthProbe = Invoke-DockerCommand {
        docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $container
    }
    $health = [string]($healthProbe.Output -join "`n")

    if ($healthProbe.ExitCode -eq 0 -and $health -eq 'healthy') {
        $responseProbe = Invoke-DockerCommand {
            docker exec $container wget -qO- http://127.0.0.1:3000/health
        }
        $response = [string]($responseProbe.Output -join "`n")

        if ($responseProbe.ExitCode -eq 0 -and
            $response -match ('"deployment"\s*:\s*"' + [regex]::Escape($Colour) + '"') -and
            $response -match ('"version"\s*:\s*"' + [regex]::Escape($ExpectedVersion) + '"')) {
            Write-Host "HEALTH CHECK PASSED: $Colour version $ExpectedVersion"
            exit 0
        }
    }

    Write-Host "Health attempt $attempt/$Attempts for $container: $health"
    Start-Sleep -Seconds $DelaySeconds
}

docker logs --tail 100 $container
throw "Health check failed for $container."
