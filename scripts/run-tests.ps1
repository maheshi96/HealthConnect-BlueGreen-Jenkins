[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('unit', 'integration', 'security')]
    [string]$Suite,

    [Parameter(Mandatory = $true)]
    [string]$TestImage,

    [ValidateSet('blue', 'green')]
    [string]$TargetColour,

    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'
$container = "healthconnect-$Suite-test-$env:BUILD_NUMBER"
$outputName = "junit-$Suite.xml"

docker rm -f $container *> $null

$dockerArguments = @(
    'create', '--name', $container,
    '--label', "healthconnect.ci.build=$env:BUILD_NUMBER",
    '-e', 'JEST_JUNIT_OUTPUT_DIR=/app/reports',
    '-e', "JEST_JUNIT_OUTPUT_NAME=$outputName"
)

if ($Suite -ne 'unit') {
    if (-not $TargetColour -or -not $ExpectedVersion) {
        throw 'TargetColour and ExpectedVersion are required for integration and security tests.'
    }

    $dockerArguments += @(
        '--network', 'healthconnect_net',
        '-e', "TARGET_URL=http://healthconnect-${TargetColour}:3000",
        '-e', "EXPECTED_DEPLOYMENT=$TargetColour",
        '-e', "EXPECTED_VERSION=$ExpectedVersion",
        '-e', "HEALTHCONNECT_API_TOKEN=$env:HEALTHCONNECT_API_TOKEN"
    )
}

$dockerArguments += @($TestImage, 'npm', 'run', "test:$Suite")
& docker @dockerArguments | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to create the $Suite test container." }

docker start -a $container
$testExitCode = $LASTEXITCODE

New-Item -ItemType Directory -Path reports -Force | Out-Null
docker cp "${container}:/app/reports/." reports
$copyExitCode = $LASTEXITCODE
docker rm -f $container *> $null

if ($copyExitCode -ne 0) { throw "Unable to copy the $Suite test reports." }
if ($testExitCode -ne 0) { exit $testExitCode }
