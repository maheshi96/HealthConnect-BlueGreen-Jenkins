# Evidence checklist

Add only genuine screenshots and exported Jenkins logs from your own run.

1. Jenkins stage view showing every stage and `Finished: SUCCESS`.
2. Immutable image build and image tag containing the Jenkins build number.
3. ESLint/SAST and `npm audit` gate output.
4. Unit-test count and coverage threshold result.
5. Idle-environment health check and integration/security test results.
6. ZAP summary and archived HTML/JSON reports.
7. Traffic switch confirmation plus `http://localhost:5000/version` output.
8. A separate controlled rollback build showing cutover, simulated crash, failed smoke test, and successful restoration of the previous colour.

Redact API tokens, credentials, Jenkins cookies, and any personal or medical data.
