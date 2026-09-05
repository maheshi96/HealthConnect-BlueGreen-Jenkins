[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('blue', 'green')]
    [string]$ExpectedColour,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'

for ($attempt = 1; $attempt -le 10; $attempt++) {
    $response = docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/version 2>$null

    if ($LASTEXITCODE -eq 0 -and
        $response -match ('"deployment"\s*:\s*"' + [regex]::Escape($ExpectedColour) + '"') -and
        $response -match ('"version"\s*:\s*"' + [regex]::Escape($ExpectedVersion) + '"')) {
        Write-Host "POST-DEPLOYMENT SMOKE TEST PASSED: $ExpectedColour version $ExpectedVersion"
        exit 0
    }

    Start-Sleep -Seconds 1
}

throw "Post-deployment smoke test failed for $ExpectedColour version $ExpectedVersion."
