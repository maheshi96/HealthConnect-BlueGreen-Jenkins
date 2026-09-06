[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZapImage,

    [int]$Attempts = 3
)

$ErrorActionPreference = 'Stop'
$baseImage = 'zaproxy/zap-stable:latest'

function Invoke-DockerCommand {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Command 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

$pulled = $false
for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    Write-Host "Pulling OWASP ZAP base image (attempt $attempt/$Attempts)."
    $pullResult = Invoke-DockerCommand { docker pull --quiet $baseImage }

    if ($pullResult.ExitCode -eq 0) {
        $pulled = $true
        Write-Host 'OWASP ZAP base image is available locally.'
        break
    }

    foreach ($line in @($pullResult.Output)) {
        Write-Warning ([string]$line)
    }

    if ($attempt -lt $Attempts) {
        Start-Sleep -Seconds (10 * $attempt)
    }
}

if (-not $pulled) {
    throw 'Unable to pull the OWASP ZAP image after three attempts. Restart Docker Desktop, confirm free disk space, and rebuild.'
}

$buildResult = Invoke-DockerCommand {
    docker build --file security/Dockerfile.zap --tag $ZapImage security
}
foreach ($line in @($buildResult.Output)) {
    Write-Host ([string]$line)
}

if ($buildResult.ExitCode -ne 0) {
    throw 'Unable to build the HealthConnect OWASP ZAP image.'
}

Write-Host "OWASP ZAP image ready: $ZapImage"
