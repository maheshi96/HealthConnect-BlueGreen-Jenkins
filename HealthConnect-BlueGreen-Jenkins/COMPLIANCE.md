# HealthConnect security and compliance notes

## Implemented controls

| Risk | Implemented control | Evidence source |
|---|---|---|
| Defective release affects patients | Candidate runs in the idle colour and is tested before Nginx cutover | Jenkins stage log and `/version` output |
| Unauthorised record access | `/records` requires a secret injected by Jenkins; comparison is constant-time | Unit, integration, and security tests |
| Automated abuse | Per-process rate limiting on the medical-record route | Application code and integration test environment |
| Browser attacks and information disclosure | Helmet headers, hidden framework header, generic errors | Security-test JUnit and ZAP report |
| Caching of health information | `Cache-Control: no-store` | Unit and security tests |
| Secret exposure in Git | Token is stored as Jenkins Secret Text and injected at runtime | Credential ID reference; secret itself must not be captured |
| Excess container privilege | Non-root app process, read-only app filesystem, dropped capabilities, no-new-privileges | Dockerfile and Compose file |
| Slow manual recovery | Post-cutover failures automatically restore the last known-good colour | Rollback log and controlled rollback run |
| Missing change evidence | Immutable build-number tags plus Jenkins/JUnit/ZAP artifacts | Jenkins artifacts and image list |
| URL/metadata exposure in router logs | Nginx access logging is disabled for the lab | `nginx/nginx.conf` |

## Healthcare compliance interpretation

These controls support HIPAA Security Rule themes such as access control, integrity, auditability, and contingency planning, and GDPR principles such as security, data minimisation, and accountability. They do not by themselves make the lab compliant. The repository deliberately contains synthetic records only.

For production, add TLS at the router, enterprise identity and MFA, least-privilege roles, per-patient authorisation checks, encryption at rest, central tamper-resistant audit logging, retention rules, key and secret rotation, vulnerability-management SLAs, incident response, backup/recovery testing, and documented data-processing governance.

## Important local-lab limitation

The router publishes HTTP on `localhost:5000` for observable classroom testing. Real health data must not be sent through this endpoint. Production traffic must use HTTPS with approved certificates and secure network boundaries.
