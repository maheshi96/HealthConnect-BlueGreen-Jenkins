// CYB204 HealthConnect blue-green pipeline for native Windows Jenkins.
// The Jenkins credential ID must be exactly: healthconnect-api-token
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        timestamps()
        timeout(time: 45, unit: 'MINUTES')
    }

    parameters {
        booleanParam(
            name: 'SIMULATE_POST_CUTOVER_FAILURE',
            defaultValue: false,
            description: 'Stops the new live container after cutover to demonstrate automatic rollback.'
        )
    }

    environment {
        // Jenkins runs as a Windows service and may not inherit Docker Desktop's user PATH.
        //  installation uses Docker Desktop's per-user installation mode.
        PATH = "C:\\Users\\DELL\\AppData\\Local\\Programs\\DockerDesktop\\resources\\bin;C:\\Program Files\\Docker\\Docker\\resources\\bin;${env.PATH}"
        DOCKER_CONFIG = "C:\\Users\\DELL\\.docker"
        // A stable Compose project/network lets every build address the same blue/green pair.
        COMPOSE_PROJECT_NAME = 'healthconnect'
        IMAGE_NAME = 'healthconnect-app'
        // Jenkins masks this value in logs and injects it only at runtime.
        HEALTHCONNECT_API_TOKEN = credentials('healthconnect-api-token')
    }

    stages {
        stage('Checkout Source') {
            steps {
                deleteDir()
                checkout scm
                powershell '''
                    New-Item -ItemType Directory -Path reports -Force | Out-Null
                '''
            }
        }

        stage('Validate Docker Agent') {
            steps {
                // Fail early with a clear message if the CLI or Docker Desktop engine is unavailable.
                powershell '''
                    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
                    if (-not $dockerCommand) {
                        throw 'Docker CLI was not found in the configured per-user or all-users Docker Desktop folders.'
                    }

                    Write-Host "Docker CLI: $($dockerCommand.Source)"
                    docker version
                    if ($LASTEXITCODE -ne 0) {
                        throw 'Docker Compose is unavailable to the Jenkins service account.'
                    }
                '''
            }
        }

        stage('Build Immutable Images') {
            steps {
                script {
                    // The build number creates traceable, immutable application and test images.
                    env.IMAGE_REF = "${env.IMAGE_NAME}:${env.BUILD_NUMBER}"
                    env.TEST_IMAGE = "${env.IMAGE_NAME}-tests:${env.BUILD_NUMBER}"
                    env.QUALITY_IMAGE = "${env.IMAGE_NAME}-quality:${env.BUILD_NUMBER}"
                    env.ZAP_IMAGE = "${env.IMAGE_NAME}-zap:${env.BUILD_NUMBER}"
                }
                powershell '''
                    docker build --pull --target production --tag $env:IMAGE_REF .
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

                    docker build --target test-runner --tag $env:TEST_IMAGE .
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Static and Dependency Security Gate') {
            steps {
                // The Docker quality target runs ESLint security rules and npm audit.
                powershell '''
                    docker build --target quality-gate --tag $env:QUALITY_IMAGE .
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Unit Tests and Coverage') {
            steps {
                // Tests execute in a container so Jenkins does not need Node.js installed.
                powershell '''
                    & ./scripts/run-tests.ps1 -Suite unit -TestImage $env:TEST_IMAGE
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/junit-unit.xml'
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'reports/coverage-unit/**'
                }
            }
        }

        stage('Ensure Known-Good Blue Baseline') {
            steps {
                // Only the first run bootstraps blue/router; later runs preserve current live state.
                powershell '''
                    & ./scripts/ensure-infrastructure.ps1 -ImageReference $env:IMAGE_REF -Version $env:BUILD_NUMBER
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Determine Active and Idle Environments') {
            steps {
                script {
                    // Query Nginx on every run instead of assuming which colour is production.
                    def detected = powershell(
                        returnStdout: true,
                        script: '& ./scripts/detect-live.ps1'
                    ).trim()

                    if (!(detected in ['blue', 'green'])) {
                        error("Unexpected active environment: ${detected}")
                    }

                    env.LIVE_ENV = detected
                    env.IDLE_ENV = detected == 'blue' ? 'green' : 'blue'
                    echo "Currently LIVE: ${env.LIVE_ENV}; deployment target: ${env.IDLE_ENV}"
                }
            }
        }

        stage('Deploy Candidate to Idle Environment') {
            steps {
                // Recreate only the idle colour. The live container keeps serving all traffic.
                powershell '''
                    $env:APP_IMAGE_REF = $env:IMAGE_REF
                    $env:APP_VERSION = $env:BUILD_NUMBER

                    docker rm -f "healthconnect-$env:IDLE_ENV" 2>$null | Out-Null
                    docker compose up -d --no-deps $env:IDLE_ENV
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Idle Environment Health Gate') {
            steps {
                // Docker health plus deployment/version assertions prevent stale-image cutover.
                powershell '''
                    & ./scripts/wait-for-health.ps1 -Colour $env:IDLE_ENV -ExpectedVersion $env:BUILD_NUMBER
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Integration Tests') {
            steps {
                // The test container reaches the idle app through the private Docker network.
                powershell '''
                    & ./scripts/run-tests.ps1 -Suite integration -TestImage $env:TEST_IMAGE -TargetColour $env:IDLE_ENV -ExpectedVersion $env:BUILD_NUMBER
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/junit-integration.xml'
                }
            }
        }

        stage('Application Security Tests') {
            steps {
                // Verify authentication, no-store caching, secure headers, and safe error handling.
                powershell '''
                    & ./scripts/run-tests.ps1 -Suite security -TestImage $env:TEST_IMAGE -TargetColour $env:IDLE_ENV -ExpectedVersion $env:BUILD_NUMBER
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/junit-security.xml'
                }
            }
        }

        stage('OWASP ZAP DAST Gate') {
            steps {
                // ZAP probes the idle colour; release-blocking findings stop before cutover.
                powershell '''
                    & ./scripts/build-zap-image.ps1 -ZapImage $env:ZAP_IMAGE
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

                    & ./scripts/run-zap.ps1 -TargetColour $env:IDLE_ENV -ZapImage $env:ZAP_IMAGE
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
            post {
                always {
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'reports/zap-report.*'
                }
            }
        }

        stage('Cut Over Traffic') {
            steps {
                // The switch script validates Nginx, reloads it, and confirms the routed colour.
                powershell '''
                    & ./scripts/switch-traffic.ps1 -TargetColour $env:IDLE_ENV
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
                script {
                    // This flag distinguishes a harmless pre-cutover failure from a rollback event.
                    env.CUTOVER_COMPLETED = 'true'
                }
            }
        }

        stage('Controlled Rollback Demonstration') {
            when {
                expression { params.SIMULATE_POST_CUTOVER_FAILURE }
            }
            steps {
                // This optional failure occurs only after a real cutover, proving rollback semantics.
                powershell '''
                    Write-Host "Simulating a post-cutover crash of healthconnect-$env:IDLE_ENV"
                    docker stop "healthconnect-$env:IDLE_ENV"
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Post-Cutover Smoke Test') {
            steps {
                // Validate through Nginx, which represents the user-facing route.
                powershell '''
                    & ./scripts/smoke-test.ps1 -ExpectedColour $env:IDLE_ENV -ExpectedVersion $env:BUILD_NUMBER
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }
    }

    post {
        unsuccessful {
            script {
                // Roll back only if production traffic was changed. Earlier failures are contained.
                if (env.CUTOVER_COMPLETED == 'true' && env.LIVE_ENV && env.IDLE_ENV) {
                    echo "Post-cutover failure detected; restoring ${env.LIVE_ENV}."
                    powershell '''
                        & ./scripts/rollback.ps1 -PreviousColour $env:LIVE_ENV -FailedColour $env:IDLE_ENV
                        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                    '''
                }
                else {
                    echo 'Failure occurred before cutover; live traffic was not changed, so rollback is unnecessary.'
                }
            }
        }
        always {
            archiveArtifacts allowEmptyArchive: true, artifacts: 'reports/**'
            powershell '''
                if (Get-Command docker -ErrorAction SilentlyContinue) {
                    $ids = docker ps -aq --filter "label=healthconnect.ci.build=$env:BUILD_NUMBER" 2>$null
                    if ($LASTEXITCODE -eq 0 -and $ids) {
                        docker rm -f $ids 2>$null | Out-Null
                    }
                }
                else {
                    Write-Host 'Skipping temporary-container cleanup because Docker CLI is unavailable.'
                }

                # Cleanup must not replace the original pipeline error.
                exit 0
            '''
        }
        success {
            echo 'HealthConnect release passed all gates and is live.'
        }
    }
}
