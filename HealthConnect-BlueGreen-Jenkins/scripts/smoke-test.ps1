[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('blue', 'green')]
    [string]$ExpectedColour,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'

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

for ($attempt = 1; $attempt -le 10; $attempt++) {
    $smokeProbe = Invoke-DockerCommand {
        docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/version
    }
    $response = [string]($smokeProbe.Output -join "`n")

    if ($smokeProbe.ExitCode -eq 0 -and
        $response -match ('"deployment"\s*:\s*"' + [regex]::Escape($ExpectedColour) + '"') -and
        $response -match ('"version"\s*:\s*"' + [regex]::Escape($ExpectedVersion) + '"')) {
        Write-Host "POST-DEPLOYMENT SMOKE TEST PASSED: $ExpectedColour version $ExpectedVersion"
        exit 0
    }

    Start-Sleep -Seconds 1
}

throw "Post-deployment smoke test failed for $ExpectedColour version $ExpectedVersion."
