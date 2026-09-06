[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZapImage,

    [int]$Attempts = 3
)

$ErrorActionPreference = 'Stop'
$baseImage = 'zaproxy/zap-stable:latest'
$configPath = Join-Path $PSScriptRoot '../security/zap-baseline.conf'

# ZAP requires three TAB-separated columns for every non-comment baseline rule.
# Validate locally before pulling or building the scanner image so formatting
# mistakes fail quickly and identify the exact source line that must be fixed.
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "ZAP baseline configuration was not found: $configPath"
}

$lineNumber = 0
foreach ($line in Get-Content -LiteralPath $configPath) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
        continue
    }

    $columns = $line -split "`t", 3
    if ($columns.Count -ne 3 -or
        $columns[0] -notmatch '^(?:\*|\d+)$' -or
        $columns[1] -notin @('IGNORE', 'WARN', 'FAIL', 'OUTOFSCOPE') -or
        [string]::IsNullOrWhiteSpace($columns[2])) {
        throw "Invalid ZAP baseline rule on line $lineNumber. Use: rule-id<TAB>action<TAB>description."
    }
}

Write-Host 'ZAP baseline configuration format is valid.'

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
