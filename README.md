# HealthConnect Blue-Green Deployment

This project implements the CYB204 Week 7 HealthConnect scenario with two complete application environments, an Nginx traffic router, automated quality gates, and rollback after a post-cutover failure.

The root `Jenkinsfile` is prepared for the native Windows Jenkins installation used in this lab. `Jenkinsfile.linux-container` is included only as an alternative for Jenkins running in a Linux container.

## Pipeline behaviour

1. Check out the exact Git commit.
2. Build an immutable application image tagged with the Jenkins build number.
3. Run ESLint security rules and block high/critical findings in production dependencies.
4. Run unit tests and enforce 80% global coverage thresholds.
5. Detect which colour Nginx is actually serving.
6. Deploy the immutable image only to the idle colour.
7. Require Docker health, integration, application-security, and OWASP ZAP gates.
8. Switch Nginx only after every pre-cutover gate passes.
9. Run a smoke test through the public router.
10. Automatically restore the previous colour if a failure occurs after cutover.

Pre-cutover failures do not invoke rollback because production traffic was never changed.

## Project structure

```text
app/                     Express application
tests/unit/              Isolated unit/API tests and coverage
tests/integration/       Tests against the idle Docker container
tests/security/          Authentication, caching, headers, and error tests
nginx/                   Router image and blue/green configurations
security/                OWASP ZAP image and baseline policy
scripts/*.ps1            Native Windows Jenkins automation
scripts/*.sh             Linux-container Jenkins alternative
docker-compose.yml       Blue, green, router, and stable private network
Jenkinsfile              Native Windows Jenkins pipeline
Jenkinsfile.linux-container  Optional Linux Jenkins pipeline
```

## Prerequisites for the Windows Jenkins pipeline

- Docker Desktop is running.
- `docker version` and `docker compose version` work from PowerShell.
- Git is installed and configured in Jenkins.
- Jenkins has the Pipeline, Git, Credentials Binding, JUnit, and Artifact Manager functionality.
- Port `5000` is available for the Nginx router.

Check Docker and the port before the first build:

```powershell
docker version
docker compose version
docker ps --filter "publish=5000"
```

Remove only obsolete containers from earlier copies of this lab if they occupy port 5000:

```powershell
docker rm -f week7-test week7-blue week7-green 2>$null
```

Do not remove `healthconnect-blue`, `healthconnect-green`, or `healthconnect-router` between normal pipeline runs; preserving them is part of the blue-green design.

## Required Jenkins credential

Create a secure token in PowerShell:

```powershell
$tokenBytes = New-Object byte[] 32
$tokenGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
$tokenGenerator.GetBytes($tokenBytes)
[Convert]::ToBase64String($tokenBytes)
$tokenGenerator.Dispose()
```

In Jenkins, go to **Manage Jenkins > Credentials > System > Global credentials > Add Credentials** and set:

| Field | Value |
|---|---|
| Kind | Secret text |
| Secret | Generated value |
| ID | `healthconnect-api-token` |
| Description | HealthConnect API token |

Never commit the secret or add it to screenshots.

## Jenkins job configuration

Create or configure a Pipeline job:

| Field | Value |
|---|---|
| Definition | Pipeline script from SCM |
| SCM | Git |
| Repository URL | Your HealthConnect GitHub repository |
| Branch Specifier | `*/main` |
| Script Path | `Jenkinsfile` |

The Script Path is the filename `Jenkinsfile`, not the repository URL.

## Run the pipeline

For the successful deployment evidence, choose:

```text
SIMULATE_POST_CUTOVER_FAILURE = false
```

Expected final output includes:

```text
TRAFFIC SWITCH SUCCESSFUL: green is active.
POST-DEPLOYMENT SMOKE TEST PASSED
Finished: SUCCESS
```

The active colour alternates on later builds because the pipeline detects current state instead of assuming blue is always live.

Verify the routed application from PowerShell:

```powershell
Invoke-RestMethod http://localhost:5000/version
Invoke-RestMethod http://localhost:5000/health
```

To demonstrate automatic rollback, run a separate build with:

```text
SIMULATE_POST_CUTOVER_FAILURE = true
```

The pipeline deliberately stops the newly live container after a genuine cutover. The smoke test then fails and the `post { unsuccessful { ... } }` logic restores the previous colour. This demonstration build ends as `FAILURE` by design, while the previous environment remains available.

Verify the rollback:

```powershell
Invoke-RestMethod http://localhost:5000/version
Get-Content .\reports\rollback.log
```

## Manual local cycle

Use this only as a pre-Jenkins check. Set a temporary token in the current PowerShell session:

```powershell
$env:HEALTHCONNECT_API_TOKEN = "replace-with-a-random-test-token"
$env:APP_IMAGE_REF = "healthconnect:local"
$env:APP_VERSION = "local"

docker build --target production -t healthconnect:local .
docker compose up -d --build blue green router

./scripts/wait-for-health.ps1 -Colour blue -ExpectedVersion local
./scripts/wait-for-health.ps1 -Colour green -ExpectedVersion local
./scripts/switch-traffic.ps1 -TargetColour green
Invoke-RestMethod http://localhost:5000/version
./scripts/switch-traffic.ps1 -TargetColour blue
Invoke-RestMethod http://localhost:5000/version
```

## First-run Jenkins behaviour

On the first build, `healthconnect-router` and `healthconnect-blue` do not exist yet. This is expected. The Windows scripts query `docker ps -a` and use explicit Docker exit codes so Jenkins does not misinterpret a normal "no such object" probe as a terminating `NativeCommandError`. If an interrupted earlier build left a stale blue container but no working router, the bootstrap safely recreates blue from the current immutable image. A successful bootstrap prints:

```text
No working router exists; recreating blue from healthconnect-app:<build-number>.
HEALTH CHECK PASSED: blue version <build-number>
BASELINE READY: router and blue environment are reachable.
```

## Security and compliance boundary

The application uses synthetic records, secret injection, constant-time token comparison, rate limiting, security headers, no-store responses, generic errors, non-root containers, read-only application filesystems, and disabled Nginx access logs. These are demonstrable controls, but this local HTTP lab is not a production HIPAA environment. Production also requires TLS, a real identity provider with MFA, role-based authorisation, encrypted storage, protected audit logs, secret rotation, monitoring, backup/recovery, and a formal risk assessment.

## Evidence rules

Submit only evidence produced by your own Jenkins and Docker execution. The pipeline archives JUnit XML, coverage, ZAP HTML/JSON, and rollback logs under `reports/`. Capture the stage view, Console Output, routed `/version` response, and the separate rollback run. Do not invent build numbers, commit hashes, container IDs, or test output.
