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

for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $health = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $container 2>$null

    if ($LASTEXITCODE -eq 0 -and $health -eq 'healthy') {
        $response = docker exec $container wget -qO- http://127.0.0.1:3000/health 2>$null

        if ($LASTEXITCODE -eq 0 -and
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
