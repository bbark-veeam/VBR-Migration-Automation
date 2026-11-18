# Changelog

All notable changes to **VbrMigrationAutomation** are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this
project follows [Semantic Versioning](https://semver.org/).

**Version source of truth:** `ModuleVersion` in
`VbrMigrationAutomation/VbrMigrationAutomation.psd1`. Bump it and add an entry
here in the same change.

**Pre-1.0 (in testing):** breaking changes are expected. While `0.x`, use
`0.MINOR.PATCH` — **MINOR** for new capabilities, **PATCH** for fixes. `1.0.0`
will mark the first version considered stable / ready to be public-facing.

## [Unreleased]
### Added
- After the main import, an optional rescan of the repositories created in
  that run (`Rescan imported repositories now? [y/N]`, default No), so their
  existing backups appear under Disk (Imported). The Automation repository
  import doesn't import backups on its own. Repositories from the export that
  were already on the target are not offered, only listed, so a re-run after
  an interrupted import shows which ones to rescan from the console. A failed
  rescan only warns.
- Job import aligns vSphere host names and URNs with the target's inventory
  before submitting. Job validation is case-sensitive, and a target that has
  registered a host before keeps its own casing (e.g. `esxi-01` on the source
  vs `ESXi-01` on the target), which failed the import.
- Pre-check before import: certificate-paired appliances (Linux hosts with no
  credentials or SSH fingerprint in the export, e.g. a hardened repository VIA)
  that are missing on the target are listed with their repositories, and the
  import waits before changing anything: pair them with the target, press Enter
  to re-check, or type Q to abort. Previously the managed-server import failed
  halfway with HTTP 400.
- VSA targets: Windows hosts whose credential isn't in FQDN\user or UPN form
  (which a VSA can't use: "Failed to discover server packages") are found
  before import. If no accepted credential exists in the export or on the
  target, the import offers, before changing anything else: [1] add one now
  (format checked, password hidden, created on the target), [2] add it in the
  VSA console and re-check, or [Q] abort. You then choose one per host at the
  managed-server step (and when adding the Source Veeam Server to a VSA): an
  existing accepted credential, [N] a new one created now, [M] one added in the
  VSA console (list refreshed), or [Q] abort. The source-server step lists only
  accepted credentials for Windows hosts on a VSA. The target platform comes from
  `GET /serverInfo` (`platform`).
### Changed
- **Breaking:** every request now sends `x-api-version: 1.3-rev2` (REST API
  for VBR 13.x), as the API requires. VBR 12.x is no longer supported (end of
  life February 2027). `Connect-VBRApi -ApiVersion` overrides the value.
- Exports now write to a new folder per run by default:
  `output\<source-server>_<yyyy-MM-dd_HHmmss>` (was a shared `output\` folder
  that each run overwrote).
- Imports without `-InputPath` (`Invoke-VBRMigrationImport`,
  `Import-VBRMigration`, `Import-VBRAgentMigration`) now find the export folders
  under `output\`: one is used directly, several are listed newest first
  (source server + export time) and you pick one by number, and none stops the
  import with an error. The wrapper asks once and passes the choice to both
  phases. A legacy flat `output\` export is still picked up.
### Fixed
- The Source Veeam Server is added to the target as a managed server only when
  a repository that is actually being imported is hosted on it. Repositories
  skipped by name, and mount servers on the source (moved to the target), no
  longer cause it. Being managed by another VBR stops the source's local console
  from connecting to it (web and remote consoles still work); the import now
  warns when it adds the source.
- Every list lookup on the target now reads all pages, not just the first: the
  skip-if-exists checks (credentials, cloud credentials, managed servers,
  proxies, repositories), credential pickers, agent-job computer resolution and
  the vSphere inventory read. On a large target an existing object could
  previously be missed and imported twice. The paging helper also stops on an
  empty page.
- Agent jobs that target an imported repository failed with "Backup repository
  with id '…' was not found": an imported repository gets a new ID on the target,
  and agent jobs are created through `/jobs` with the source ID. Each
  `backupRepositoryId` in an agent job (including a policy's
  `storage.destination`) is now mapped to the same-named repository on the
  target. A job whose repository isn't on the target is skipped with a warning.
- Re-running an import no longer fails at the source-server step with "Managed
  host already exists": hosts referenced by repositories (such as the Source
  Veeam Server) that are already managed servers on the target are skipped.
- Repository mount-server and gateway remapping to the target VBR now uses the
  name the target reports for itself, not `-Server` as typed. A VSA lists
  itself in lower case (`vbr.hackshack.local`), and mount server names are
  validated case-sensitively ("Mount host [VBR.HackShack.local] is not found").
- README: "Known Gaps" replaced by a fuller **Known Limitations** section
  (versions, unlinked backups and manual mapping, schedules, job types,
  skip-not-merge, first-page existence checks, interactive prompts, source
  infrastructure); the "What Gets Migrated" table no longer implies backups or
  job IDs carry over.
- `docs/api-reference.md` rewritten from the calls the module actually makes:
  the token endpoint is `/api/oauth2/token` (not `/api/v1/token`), exports are
  synchronous, sessions end in `Stopped` with the outcome in `result.result`,
  the required `x-api-version` header is listed, and the non-Automation
  endpoints used (credentials, agents, lookups, rescan) are included.
### Security

## [0.1.0] - 2026-06-10
Initial tracked baseline (pre-release).

### Added
- Proper PowerShell module layout (`Public/`, `Private/`, `.psd1`/`.psm1`, Pester
  tests) restructured from the earlier loose-script version.
- Export/Import of VBR configuration via the Veeam REST API Automation endpoints:
  credentials, cloud credentials, encryption-password metadata, managed servers,
  repositories, proxies, jobs, agent protection groups, and agent backup jobs.
- Orchestrators `Invoke-VBRMigrationExport` / `Invoke-VBRMigrationImport`,
  `Connect-VBRApi`, and source-server reference re-pointing on import.
- Internals: redaction helper, paginated data retrieval, automation-session
  wrapper, and a config-backup trigger.
- Repository hygiene: hardened `.gitignore`, CI (gitleaks full-history,
  PSScriptAnalyzer, Pester), `SECURITY.md`.
