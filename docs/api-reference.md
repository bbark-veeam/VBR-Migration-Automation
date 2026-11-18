# Veeam VBR 13 REST API — Endpoints Used by This Module

This page lists the REST calls the module makes, as verified against VBR
13.1.2.57. It is not a full API reference; see the
[Veeam VBR REST API reference (1.3-rev2)](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Automation)
for that.

**Base URL:** `https://<server>:9419/api/v1`

**Required role:** Veeam Backup Administrator

---

## Required Headers

Every request, including the token request, carries:

| Header | Value |
|--------|-------|
| `x-api-version` | `1.3-rev2` (override with `Connect-VBRApi -ApiVersion`) |

All requests after authentication also carry:

| Header | Value |
|--------|-------|
| `Authorization` | `Bearer <access_token>` |
| `Content-Type` | `application/json` |
| `Accept` | `application/json` |

---

## Authentication

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/oauth2/token` | Obtain a bearer token. Form-encoded body: `grant_type=password`, `username`, `password` |

Note that the token path sits outside `/api/v1`.

---

## Export Endpoints (Automation)

Export calls are **synchronous**: the POST response body *is* the exported
data. Each response is written as-is to a JSON file in the export folder.

| Method | Path | Output file |
|--------|------|-------------|
| POST | `/automation/credentials/export` | `Credentials.json` |
| POST | `/automation/cloudcredentials/export` | `CloudCredentials.json` |
| POST | `/automation/encryptionPasswords/export` | `EncryptionPasswords.json` |
| POST | `/automation/managedServers/export` | `ManagedServers.json` |
| POST | `/automation/repositories/export` | `Repositories.json` |
| POST | `/automation/proxies/export` | `Proxies.json` |
| POST | `/automation/jobs/export` | `Jobs.json` |

What the exports leave out:

- Credential, cloud credential and encryption password exports contain **no
  secret values**, only metadata and IDs. Passwords are prompted for on import;
  encryption passwords must be re-entered on the target by hand.
- Job exports carry **no job ID**. Each imported job is created with a new ID,
  so existing backups are not linked to it (see the README).

---

## Import Endpoints

Automation import calls are **asynchronous**: they return a session object
straight away, and the module polls it until it finishes (see
[Sessions](#sessions)).

| Method | Path | Used for |
|--------|------|----------|
| POST | `/automation/managedServers/import` | Managed servers, including hosts referenced only by repositories (e.g. the source VBR) |
| POST | `/automation/repositories/import` | Non-cloud repositories |
| POST | `/automation/proxies/import` | Proxies |
| POST | `/automation/jobs/import` | VMware vSphere backup jobs |

Some objects are created through the regular endpoints instead:

| Method | Path | Used for |
|--------|------|----------|
| POST | `/credentials` | Credentials, created one by one with the source `uniqueId` preserved |
| POST | `/cloudCredentials` | Cloud credentials, with the source `uniqueId` preserved |
| POST | `/backupInfrastructure/repositories?overwriteOwner=true` | Cloud (object storage) repositories |

Encryption passwords are **not imported**; the import only reports how many
need re-entering.

An imported repository gets **a new ID on the target**. Automation job import
resolves the repository by name, but agent jobs created through `POST /jobs`
need the target ID, so the module maps each `backupRepositoryId` from source ID
→ repository name → target ID.

---

## Agent Objects

| Method | Path | Used for |
|--------|------|----------|
| GET | `/agents/protectionGroups` | Export protection groups; check for existing ones on import |
| POST | `/agents/protectionGroups` | Create a protection group |
| PUT | `/agents/protectionGroups/{id}` | Apply the full configuration to a newly created protection group |
| POST | `/agents/protectionGroups/{id}/rescan` | Rescan a protection group so its computers are discovered |
| GET | `/agents/protectionGroups/{id}/discoveredEntities` | Resolve discovered computers for agent jobs |
| GET | `/adDomains` | Resolve Active Directory domains for protection groups |
| GET | `/jobs` | Export agent jobs (filtered by type); check for existing jobs on import |
| POST | `/jobs` | Create agent backup jobs |

---

## Lookups on the Target

Read-only calls used to skip objects that already exist and to resolve
references:

| Method | Path | Used for |
|--------|------|----------|
| GET | `/credentials` | Existing credentials (skip by `uniqueId`) |
| GET | `/cloudCredentials` | Existing cloud credentials (skip by `uniqueId`) |
| GET | `/backupInfrastructure/managedServers` | Existing managed servers (skip by name); the target VBR's own entry |
| GET | `/backupInfrastructure/repositories` | Existing repositories (skip by name); repositories created by this import |
| GET | `/backupInfrastructure/proxies` | Existing proxies (skip by host) |
| GET | `/jobs` | Existing jobs (skip by name) |
| GET | `/inventory/vmware/hosts` | Host names as the target's inventory reports them; job host references are aligned to this casing |

---

## Other Operations

| Method | Path | Used for |
|--------|------|----------|
| POST | `/configBackup/backup` | Optional configuration backup of the target before import |
| POST | `/backupInfrastructure/repositories/rescan` | Optional rescan of repositories created by the import. Body: `{ "repositoryIds": ["<uuid>", ...] }` |

---

## Sessions

Asynchronous calls return a session object (`id`, `sessionType`, `state`,
`result`, ...). The module polls it every 5 seconds:

| Session type | Polled at |
|--------------|-----------|
| `Automation` | GET `/automation/sessions/{id}` |
| Anything else (e.g. `ConfigurationBackup`, `ConfigurationResynchronize`) | GET `/sessions/{id}` |

GET `/automation/sessions` is also called once before an export or import to
check that the Automation API is available.

**Reading the outcome:**

- `state` is `Working` while the session runs and `Stopped` when it ends,
  **whatever the outcome**.
- The outcome is in `result.result`: `Success`, `Warning` or `Failed`.
  `result.message` gives counts such as
  `Result: Success 2, Warning 0, Failed 0`.
- When an automation session fails, GET `/automation/sessions/{id}/logs` returns
  the per-object records (`status`, `title`, `description`), and the module
  includes them in its error message.
