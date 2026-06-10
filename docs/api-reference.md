# Veeam VBR 13 REST API — Automation Endpoint Reference

**Base URL:** `https://<server>:9419/api/v1/automation`

**Auth:** Bearer token from `POST /api/v1/token`

**Required role:** Veeam Backup Administrator

---

## Authentication

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/token` | Obtain bearer token (grant_type=password) |

---

## Export Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/automation/jobs/export` | Export VMware vSphere backup jobs |
| POST | `/api/v1/automation/credentials/export` | Export credential records |
| POST | `/api/v1/automation/cloudcredentials/export` | Export cloud provider credentials |
| POST | `/api/v1/automation/proxies/export` | Export proxy configurations |
| POST | `/api/v1/automation/managedServers/export` | Export managed server definitions |
| POST | `/api/v1/automation/repositories/export` | Export repository configurations |
| POST | `/api/v1/automation/encryptionPasswords/export` | Export encryption password records |

---

## Import Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/automation/jobs/import` | Import VMware vSphere backup jobs |
| POST | `/api/v1/automation/credentials/import` | Import credential records |
| POST | `/api/v1/automation/cloudcredentials/import` | Import cloud provider credentials |
| POST | `/api/v1/automation/proxies/import` | Import proxy configurations |
| POST | `/api/v1/automation/managedServers/import` | Import managed server definitions |
| POST | `/api/v1/automation/repositories/import` | Import repository configurations |
| POST | `/api/v1/automation/encryptionPasswords/import` | Import encryption password records |

---

## Session Management

All export and import operations are asynchronous — they return a session ID
immediately and the operation runs in the background.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/automation/sessions` | List all automation sessions |
| GET | `/api/v1/automation/sessions/{sessionId}` | Get session status and result |
| GET | `/api/v1/automation/sessions/{sessionId}/logs` | Get session log entries |
| POST | `/api/v1/automation/sessions/{sessionId}/stop` | Stop a running session |

**Session states:** `Running`, `Stopped`, `Failed`, `Succeeded`

---

## Notes

- Export endpoints return a session ID. Poll the session until it reaches a
  terminal state, then retrieve the payload from the session result.
- Import endpoints accept the payload from a previous export session.
- Encryption password export does **not** include secret values — only metadata.
  Actual passwords must be re-entered on the target server.
- All requests require `Content-Type: application/json` and
  `Authorization: Bearer <token>` headers.
