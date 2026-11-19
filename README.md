# VBR Migration Automation
## Export and Import Automation via Veeam RESTful API

**License:** MIT — see [LICENSE](LICENSE).

---

> ## ⚠️ Disclaimer — Not an Official Veeam Product
>
> This project is a **personal, community-contributed tool**. It is **not an
> official Veeam product**, is not part of any Veeam product roadmap, and is
> **not supported, endorsed, or maintained by Veeam Software**.
>
> Although the author is a Veeam employee, this tool represents the author's
> views only — not the position, strategy, or commitment of Veeam Software.
>
> - **Veeam Support cannot assist** with issues encountered while using this
>   tool. Do not open Veeam Support tickets for problems with these scripts.
> - **File issues, bug reports, and feature requests** against this repository
>   directly.
> - **Use at your own risk.** Always test in a non-production environment
>   first, and always have a verified Veeam configuration backup (or VM
>   snapshot) of the target server before running any import.

---

> ## 🧪 Project Status — Pre-release (v0.x)
>
> This tool is **pre-release and only partially validated**. It targets
> **VBR 13.x** (REST API `1.3-rev2`) on both source and target; VBR 12.x is not
> supported. Two migration paths have been run end to end with the current
> module on 13.1.2.57: **Windows VBR → Windows VBR** and **Windows VBR → VSA**.
> Both used one source server and small object counts, importing into a target
> that already had its own configuration. The VSA-source paths in
> [Supported Migration Scenarios](#supported-migration-scenarios) are
> **untested** on 13.x.
>
> Treat any other path as experimental. Run it in a lab first, and only
> after taking a configuration backup or snapshot of the target.

---

## Overview

This project automates the full export of a Veeam Backup & Replication server
configuration and the import of that configuration into a new or replacement
server. It uses the Veeam VBR REST API Automation endpoints
(`/api/v1/automation/`) which are specifically designed for this migration use
case, called via `Invoke-RestMethod` in PowerShell 7.

Scripts run from any machine with network access to the VBR server — they do
not need to be executed on the VBR host itself.

Every request sends `x-api-version: 1.3-rev2`. Both servers must run a VBR 13
build that supports that API revision (tested on 13.1.2.57).

**Reference:** [Veeam VBR REST API — Automation](https://helpcenter.veeam.com/references/vbr/13/rest/1.3-rev2/tag/Automation)

---

## Terminology

Throughout this documentation:

- **Source Veeam Server** — the existing Veeam Backup & Replication server that
  configuration data is **exported from**.
- **Target Veeam Server** — the new or replacement Veeam Backup & Replication
  server that configuration data is **imported to**.

---

## Supported Migration Scenarios

The tool is designed for the migration patterns below. The **Tested** column
shows what has actually been run end to end. The tool migrates
**one source server per run**. The target may already have its own
configuration, but any object whose name already exists there is **skipped, not
merged**. Check for name collisions before importing several sources into one
target.

| Scenario | Source | Target | Tested | Notes |
|----------|--------|--------|--------|-------|
| Migration off VSA | Linux VSA VBR | Windows VBR | ❌ **No** | Objects that depend on the source VSA are left behind; see the VSA-source note below. |
| Windows VBR refresh / consolidation | Windows VBR | Windows VBR | ✅ **Yes** — 13.1.2.57, single source, small object counts, into a target with existing configuration | Configuration Backup/Restore is the preferred method for a like-for-like refresh; see the note below. |
| Modernization to VSA / consolidation onto a VSA | Windows VBR | Linux VSA VBR | ✅ **Yes** — 13.1.2.57, single source, small object counts, into a VSA with existing configuration, including a hardened repository (Veeam Infrastructure Appliance) and Veeam Agent jobs | For a like-for-like move onto a **blank** VSA, Veeam's own supported Windows → VSA migration is the recommended path. This tool fits merging a Windows VBR into a VSA that is already in use. Needs: appliances paired with the VSA first, and FQDN\user or UPN credentials for Windows servers (both handled interactively). Imported backups mapped to their jobs continued as incrementals with CBT. |
| VSA refresh | Linux VSA VBR | Linux VSA VBR | ❌ **No** | The VSA-source limitation below applies. |

> **Note on Windows → Windows migrations:** Veeam's built-in **Configuration
> Backup and Restore** feature is the **preferred and officially supported**
> method when both source and target are Windows VBR servers. It captures the
> full configuration database and is the recommended approach in the Veeam
> documentation.
>
> This tool is for situations where Configuration Backup/Restore is not a
> viable option, including:
> - Major version differences between source and target
> - Source database is corrupt and cannot be backed up cleanly
> - Selective migration (importing only specific components, not the whole config)
> - Licensing or build mismatches that prevent restore on the target
>
> If none of those apply, use Configuration Backup/Restore instead.

### Note on VSA-as-source migrations (applies to both VSA → VSA and VSA → Windows VBR)

A VSA cannot be added as a managed server inside another Veeam installation —
this is an architectural limitation of the appliance. Each VSA is a
self-contained unit, and its local storage is not reachable from another
Veeam server (regardless of whether that other server is Windows or another
VSA).

Any object on the source VSA that depends on the VSA itself acting as a
managed server **must be excluded** before import:

- **Linux Hardened Repositories hosted on the VSA's local disk** — the data
  lives on appliance storage that no other Veeam server can mount.
- **Repositories using the VSA as their mount/gateway server** — the reference
  cannot be re-pointed automatically.
- **Proxies running on the VSA appliance** — appliance-bound, not relocatable.
- **Anything else with `hostName` or `managedServerId` pointing at the source VSA**.

What **does** migrate cleanly in VSA-source scenarios:

- Credentials and cloud credentials (passwords/secrets re-entered interactively)
- Encryption password records (re-entered manually after import)
- Cloud repositories (Wasabi, S3, Azure Blob, etc.) — gateway server reference
  may need to be remapped to a target-side server post-import
- Backup jobs that don't reference VSA-hosted repositories or proxies

In practice, VSA-source migrations typically mean carrying credential and
cloud storage configuration forward while leaving on-appliance storage
behind. The new target (whether VSA or Windows) will host its own local
repositories. Plan accordingly.

---

## What Gets Migrated

| Component | Export | Import | Notes |
|-----------|--------|--------|-------|
| Encryption passwords | ✅ | ⚠️ | Metadata only — secret values must be re-entered manually |
| Credentials | ✅ | ✅ | Passwords are not stored in exports; you will be prompted for each on import |
| Cloud credentials | ✅ | ✅ | Secret keys are not stored in exports; you will be prompted for each on import |
| Managed servers | ✅ | ✅ | |
| Repositories | ✅ | ✅ | Backups already in them are not imported; an optional rescan at the end of the import makes them available. Host references to the Source Veeam Server are remapped or added as managed servers |
| Proxies | ✅ | ✅ | Proxies on hosts the target doesn't manage (e.g. the source's default proxies) are skipped |
| VMware vSphere backup jobs | ✅ | ✅ | Created with a **new job ID**; existing backups are not linked to them (see [Known Limitations](#known-limitations)) |
| Veeam Agent protection groups and jobs | ✅ | ✅ | The default *Manually Added* group is skipped |

---

## How It Works

**Export** — each export endpoint returns data synchronously in the POST
response body. Scripts write each component to a JSON file in the export folder
(`output\<source-server>_<timestamp>\` by default).

**Import** — each import endpoint accepts the exported JSON and processes it
asynchronously, returning a session object. Scripts poll the session until it
reaches the terminal state `Stopped`, then read the outcome from
`result.result` (`Success`, `Warning`, or `Failed`) before proceeding to the
next component.

**Empty collections** — if a component has no records (e.g. no backup jobs
configured), the import script skips it automatically rather than sending an
empty payload to the API.

---

## Import Dependency Order

Components must be imported in this order — later components reference earlier
ones by ID:

```
1. Encryption Passwords   ← required by credentials
2. Credentials            ← required by servers, repositories
3. Cloud Credentials      ← required by cloud repositories
4. Managed Servers        ← required by repositories, proxies
5. Repositories           ← required by jobs
6. Proxies                ← required by jobs
7. Jobs                   ← depends on all of the above
```

`Import-VBRMigration` enforces this order and halts on failure.

---

## Repository Structure

```
.
├── README.md
├── LICENSE
├── .gitignore
│
├── VbrMigrationAutomation/                       ← The PowerShell module
│   ├── VbrMigrationAutomation.psd1               ← Manifest (version, exports, requirements)
│   ├── VbrMigrationAutomation.psm1               ← Loader — discovers Public/Private files
│   ├── Public/                                    ← Exported functions (user-callable)
│   │   ├── Connect-VBRApi.ps1
│   │   ├── Invoke-VBRMigrationExport.ps1          ← Wrapper: full export in one command
│   │   ├── Invoke-VBRMigrationImport.ps1          ← Wrapper: full import in one command
│   │   ├── Export-VBRMigration.ps1                ← Orchestrator: main export
│   │   ├── Import-VBRMigration.ps1                ← Orchestrator: main import
│   │   ├── Export-VBRAgentMigration.ps1           ← Orchestrator: agent export
│   │   ├── Import-VBRAgentMigration.ps1           ← Orchestrator: agent import
│   │   └── Export-VBRCredential.ps1, Import-VBRRepository.ps1, ... (per-component)
│   └── Private/                                   ← Internal helpers (not exported)
│       ├── Connect-VBRApi.ps1 dependencies
│       ├── Format-RedactedJson.ps1
│       ├── Get-VBRDefaultExportPath.ps1
│       ├── Get-VBRPaginatedData.ps1
│       ├── Invoke-AutomationSession.ps1
│       ├── Invoke-VBRConfigBackup.ps1
│       ├── Invoke-VBRRepositoryRescan.ps1
│       ├── Resolve-VBRImportPath.ps1
│       └── Sync-VBRJobHostName.ps1
│
├── output/                                        ← Export artefacts, one folder per export (git-ignored)
│
├── tests/                                         ← Pester tests (see tests/README.md)
│   ├── Module.Tests.ps1                            ← Load + export-surface smoke tests
│   └── Format-RedactedJson.Tests.ps1               ← Unit tests for the log redactor
│
└── docs/
    └── api-reference.md                           ← Endpoint reference and payload notes
```

---

## Authentication

Authentication uses OAuth2 bearer tokens from `POST /api/oauth2/token`.
`Connect-VBRApi` handles authentication and returns a connection object that
the rest of the module uses for subsequent API calls.

Required role: **Veeam Backup Administrator**

---

## Usage

The module is loaded with `Import-Module`. From the project root:

```powershell
Import-Module .\VbrMigrationAutomation
```

Once loaded, you have 26 exported commands. The two highest-level ones are
the all-in-one wrappers — these are the typical entry points:

```powershell
# Full export (main configuration + agent objects) in one command
Invoke-VBRMigrationExport -Server "<source-veeam-server-fqdn>"

# Full import (main configuration + agent objects) in one command
Invoke-VBRMigrationImport -Server "<target-veeam-server-fqdn>"
```

The wrappers prompt for credentials once and for the configuration-backup
decision once, then run both the main and agent phases in sequence.

### Running a single scope

If you only need part of the migration, the scope-level orchestrators run a
single phase:

```powershell
Export-VBRMigration       -Server "<source>"   # main export only
Import-VBRMigration       -Server "<target>"   # main import only
Export-VBRAgentMigration  -Server "<source>"   # agent export only
Import-VBRAgentMigration  -Server "<target>"   # agent import only
```

### Running a single component

Every component-level function (`Export-VBRRepository`, `Import-VBRCredential`,
etc.) is also exported and can be called directly:

```powershell
$conn = Connect-VBRApi -Server "<source>" -Credential (Get-Credential)
Export-VBRRepository -Connection $conn -OutputPath .\output
```

### Optional path arguments

By default, each export writes to a new folder named after the source server
and the export time, `output\<source-server>_<yyyy-MM-dd_HHmmss>` under the
current directory. Every run therefore keeps its own artefacts, and exports from
several source servers stay apart. The export prints the folder path when it
finishes. Override it with `-OutputPath`.

Without `-InputPath`, an import looks for export folders (folders holding a
`_metadata.json`) under `output\`:

- **One export:** it is used, and its path is printed.
- **Several exports:** they are listed newest first, with source server and
  export time, and you pick one by number (`1`-`N`).
- **None:** the import stops and asks for `-InputPath`.

```powershell
Invoke-VBRMigrationExport -Server "<source>"    # -> output\<source>_2026-11-18_080235
Invoke-VBRMigrationImport -Server "<target>"    # picks the export (prompts if several)
Invoke-VBRMigrationImport -Server "<target>" -InputPath ".\output\<source>_2026-11-18_080235"

Invoke-VBRMigrationExport -Server "<source>" -OutputPath "C:\migration\acme"
```

Run `Invoke-VBRMigrationExport` rather than `Export-VBRMigration` followed by
`Export-VBRAgentMigration` when you want both phases in one folder. Run on their
own, each one creates its own timestamped folder.

Port defaults to `9419` and can be overridden with `-Port`.

### Discovering commands

```powershell
Get-Command -Module VbrMigrationAutomation | Sort-Object Name
Get-Help Invoke-VBRMigrationImport -Detailed
```

### Running the tests

A small Pester 5 suite under [`tests/`](tests/) covers module load, the
exported function surface, and the log redactor. No live VBR server is
required. See [tests/README.md](tests/README.md) for scope and details.

```powershell
# One-time: install Pester 5+
Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck

# From the repo root
Invoke-Pester ./tests -Output Detailed
```

---

## Rollback / Pre-Import Safety

Before any import operation runs, the import orchestrators (`Import-VBRMigration`
and `Import-VBRAgentMigration`, and the wrapper `Invoke-VBRMigrationImport`)
prompt:

```
Create a Veeam configuration backup before importing? [Y/n]
```

Accepting (default) triggers `POST /api/v1/configBackup/backup` on the
Target Veeam Server, producing a config backup file at the standard location:

```
C:\ProgramData\Veeam\Backup\VeeamConfigBackup
```

**To restore** that backup if the import goes wrong: this **cannot** be
automated via REST. Use the Veeam console wizard
(`Configuration > Configuration Backup > Restore`) on the Target Veeam Server
with VBR services stopped. Plan for ~5–10 minutes of downtime during restore.

### Alternative: VM Snapshot

If the Target Veeam Server is virtualized, a hypervisor-level snapshot is
faster to take and revert than a config backup, and captures full system state
(services, registry, in-memory state). Useful during testing iteration.

> **WARNING — do not leave snapshots running on production Veeam servers.**
> Veeam services interact heavily with disk state, and long-lived snapshots can
> cause:
> - Unbounded snapshot file growth filling the datastore
> - I/O performance degradation (chain of redo logs)
> - Database corruption if snapshot consolidation fails
> - Unexpected behavior with backup repositories on the same datastore
>
> Snapshots are appropriate for short-lived test cycles only. Always
> consolidate immediately after testing completes.

---

## Security Considerations

This tool handles credential passwords (Veeam admin login, account passwords,
cloud secret keys, AD bind credentials). Below is what's stored, what's not,
and how to handle the artifacts it produces.

### What is and isn't stored on disk

| Artifact | Contains secrets? |
|----------|-------------------|
| `output/Credentials.json` | **No.** Veeam's export omits password values by design. Only metadata, usernames, and UUIDs. |
| `output/CloudCredentials.json` | **No.** Secret keys / shared keys are blank in exports. |
| `output/EncryptionPasswords.json` | **No.** Metadata only — actual passwords never leave the source server. |
| `output/_metadata.json` | **No.** Contains source server FQDN and the IsVSA flag — environment-specific but not secret. |
| `output/_Repositories.posted.json`, `output/_Repositories.cloud.*.posted.json` | **No.** Diagnostic dumps of import payloads. Contain UUIDs and structural references but no plaintext secrets. |

Passwords entered interactively during import (for `Import-VBRCredential`,
`Import-VBRCloudCredential`, the `Import-VBRAgentMigration` credential-creation
prompt, etc.) are read as `SecureString`, converted to plaintext **only at the
moment of building the HTTP request body**, and never written to disk.

### Console output redaction

Error handlers across the module wrap response bodies through the private
`Format-RedactedJson` helper before logging. The redactor scrubs the
following JSON field values:

- `password`, `secretKey`, `sharedKey`
- `bearer`, `apiKey`
- `access_token`, `refreshToken`

This is defense-in-depth — the Veeam REST API does not normally echo secrets
back in error responses, but if it ever did, redaction would prevent the
secret reaching the user's terminal, transcript, or PowerShell host history.

### Repository hygiene

The project root contains a `.gitignore` that excludes:

- The entire `output/` folder
- All `_*.posted.json` and `_metadata.json` diagnostic files
- PowerShell transcripts (`*.transcript`) and logs (`*.log`)
- Editor and OS-specific local artifacts

If you fork this project or add it to a git repository, **do not commit the
`output/` folder under any circumstances.** Even though it does not contain
plaintext secrets, it does contain environment-specific data (server FQDNs,
internal UUIDs) that may be considered sensitive in your organization.

### Operational guidance

- **PowerShell transcripts**: if `Start-Transcript` is enabled in your
  environment, console output is captured to a file. The script does not
  echo plaintext passwords to console, but if you customize it, audit any new
  `Write-Host` / `Write-Error` calls accordingly.
- **Run-as account**: scripts must run as a user with administrative access
  to the target VBR server (Veeam Backup Administrator role). Avoid running
  on shared workstations where credentials prompts could be observed.
- **Credential lifecycle**: passwords entered during import are passed to the
  target VBR's REST API and not retained anywhere by this script. The target
  server stores them encrypted in its own configuration database.

---

## After Import

Some components require follow-up steps on the Target Veeam Server:

1. **Encryption passwords** — not automated. Re-enter all encryption passwords
   manually via the Veeam console under **Configuration > Encryption Passwords**.
2. **Credential passwords** — entered interactively during import. If any were
   skipped, update them in the Veeam console.
3. **Cloud credential secret keys** — entered interactively during import. If
   any were skipped (e.g. AzureCompute, GoogleService), recreate them manually.
4. **Repository host references** — a mount or gateway server on the Source
   Veeam Server is moved to the Target Veeam Server automatically. A repository
   hosted **on** the Source Veeam Server makes the import add the source as a
   managed server of the target (see the Known Limitations note on its local
   console).

### Backups in Imported Repositories

Importing a repository creates it on the target but does **not** import the
backups already stored in it. At the end of the main import, the tool lists the
repositories created in that run and asks:

```
Rescan imported repositories now? [y/N]
```

- **y:** the repositories are rescanned and their backups appear under
  **Backups > Disk (Imported)**, ready for restore.
- **N (default):** the repositories are left as they are. This suits large
  repositories holding data that is due to be retired: rescan later from the
  console only if a restore is needed.

Repositories from the export that were already on the target when the run
started are not offered, so repeated imports don't ask about them again. They
are listed instead (`Not offered for rescan (already on the target when this
run started): ...`). These are usually the target's own (such as its *Default
Backup Repository*) or ones created by an earlier import that was interrupted
before reaching the rescan question. Rescan the latter from the console.

Rescanned backups are not attached to the imported jobs: VBR offers no API
for that, and an imported job gets a new ID. Where an imported job should
continue an existing chain, map it to the backup from the console (Edit job >
Storage > Map backup). Its next run then continues the chain as an incremental.

Background retention does not apply to imported backups of regular backup
jobs, so they are never aged out on their own. To retire one, either:

- **Delete it by hand** from **Backups > Disk (Imported)** once it is no longer
  needed, or
- **Map it to a job, then delete that job.** The backup becomes orphaned, and
  background retention then removes it using the job's retention settings.

### Cleanup of Source-Referencing Objects

The migration imports the Source Veeam Server's full configuration. If any
imported repository is hosted on the Source Veeam Server, the **Target Veeam
Server will also manage the Source Veeam Server itself**, along with the
repositories, proxies or other components hosted on it. Mount and gateway
servers on the source are moved to the target and don't cause this.

Once the migration has been validated and you are confident the Target Veeam
Server is the authoritative production server, **it is recommended to remove
the Source Veeam Server and its dependent components** from the Target Veeam
Server's inventory:

1. Backup jobs that previously ran on the Source — verify they have been
   reassigned to Target-side proxies/repositories.
2. Repositories hosted on the Source — relocate backups to Target-side storage,
   then remove the Source-hosted repositories.
3. Proxies on the Source — remove from the managed proxy list.
4. The Source Veeam Server itself — remove from **Managed Servers**. This
   uninstalls Veeam components from it. If the source stays in use, repair it
   afterwards (see [Infrastructure](#infrastructure) under Known Limitations).

Leaving these in place causes:
- Failed jobs/health checks that try to contact the decommissioned Source
- Confusing console state for administrators
- Potential security exposure if Source credentials remain referenced

Perform this cleanup only after a successful test backup/restore cycle on the
Target Veeam Server confirms the migration is complete.

---

## Known Limitations

### Versions and testing

- **VBR 13.x only.** Every request asks for REST API revision `1.3-rev2`. A
  server that doesn't support that revision (12.x, and possibly early 13.0
  builds) rejects it. `Connect-VBRApi -ApiVersion` can request another revision,
  but only `1.3-rev2` has been tested.
- **Only Windows VBR → Windows VBR and Windows VBR → VSA have been tested**
  (13.1.2.57). The VSA-source scenarios in
  [Supported Migration Scenarios](#supported-migration-scenarios) are untested.

### Backups and jobs

- **Imported jobs are not linked to existing backups.** The export carries no
  job ID, so each job is created on the target with a new ID. VBR offers no
  REST or PowerShell way to point a backup job at an existing backup chain.
  After a rescan, the backups sit under **Disk (Imported)**. Map each job to its
  backup in the console (Edit job > Storage > Map backup) if it should continue
  the chain; its next run is then an incremental. This is a product limitation,
  not a gap in this tool.
- **Repository import does not import backups.** Answer `y` to the rescan
  prompt at the end of the import, or rescan from the console later.
- **Imported jobs keep the schedule from the export.** If the source VBR is still
  running, both servers may back up the same workloads. Disable the jobs on one
  side until the cut-over.
- **Only VMware vSphere backup jobs and Veeam Agent jobs are migrated.**
  Hyper-V, backup copy, replication, NAS, CDP, SureBackup and tape jobs must be
  recreated by hand.

### Merging into an existing target

- **One source server per run.** You can run the tool again to import another
  source into the same target.
- **Existing objects are skipped, not merged or renamed.** Managed servers,
  repositories and jobs are matched by name; credentials and cloud credentials
  by ID. If the target already has a job called *Daily Backup*, the source's
  *Daily Backup* is skipped, not imported under another name. Check for name
  collisions before importing.

### Credentials and secrets

- **The import is interactive.** It prompts for each credential and cloud
  credential password, and for choices such as which credential to use for an
  added host. It cannot run unattended.
- **Encryption passwords are not imported.** Re-enter them on the target
  (Configuration > Encryption Passwords).

### Infrastructure

- **The Source Veeam Server is added to the target as a managed server** only
  when a repository being imported is hosted on it, for example a local disk
  repository on the source that the target doesn't already have. Mount and
  gateway servers on the source are moved to the target instead.
- **Removing the Source Veeam Server from the target's managed servers
  uninstalls Veeam components from it.** Its local console then sees a version
  mismatch and can't connect; the web console still works. To repair it, open
  the source's web console, open the properties of its own managed server
  (*This Server*) and click through the wizard to the end. That reinstalls the
  missing components, and the local console connects again. The import warns
  before adding the source.
  Remove it from the target's managed servers once the migration is validated
  (see [Cleanup of Source-Referencing Objects](#cleanup-of-source-referencing-objects)).
- **Infrastructure hosted on the Source Veeam Server is not carried over.** Its
  default proxies are skipped. A repository with the same name as one on the
  target (such as *Default Backup Repository*) is skipped.
- **Certificate-paired appliances can't be imported.** A Veeam Infrastructure
  Appliance (for example a hardened repository) added by pairing has no
  credentials or SSH fingerprint in the export, and the import API rejects it.
  Before changing anything, the import lists any that are missing on the
  target and **waits**. Pair each appliance with the target from its Host
  Management Console, **using the same name the source used**, then press
  Enter: the import re-checks and continues once they're all there (or type
  `Q` to abort). The host is then skipped as already present, its
  repositories import, and jobs that target them are pointed at the imported
  repositories. An appliance can be paired with only one VBR at a time, so pairing
  it with the target removes it from the source.
- **A VSA target needs FQDN\user or UPN credentials for Windows servers.** A
  Veeam Software Appliance can't add a Windows server with a credential in
  `NETBIOS\user`, `HOST\user` or bare-name form; VBR reports "Failed to discover
  server packages". When the target is a VSA (detected from `/serverInfo`), the
  import checks the Windows hosts first, before changing anything. If no
  credential in `domain.fqdn\user` or `user@domain.fqdn` form exists in the
  export or on the target, it offers to add one now (user name checked for
  form, password hidden), to wait while you add it in the VSA console, or to
  abort. When managed servers are imported, it asks you to choose a credential
  for each affected host. You can pick an existing accepted credential, add a new
  one there and then (for example, a service account for the environment being
  imported), add one in the VSA console and refresh the list, or abort. The same
  choice is offered when the Source Veeam Server is added to a VSA.
- **VSA sources** have further limits; see
  [Note on VSA-as-source migrations](#note-on-vsa-as-source-migrations-applies-to-both-vsa--vsa-and-vsa--windows-vbr).

### Not covered by the Automation API

- **Scale-out repositories** — may require manual reconfiguration if extent
  paths differ between source and target.
- **Tape infrastructure.**
- **Global settings** — notification settings, global exclusions, and
  server-level configuration.
