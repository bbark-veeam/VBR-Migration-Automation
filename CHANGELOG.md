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
  import doesn't import backups on its own. A failed rescan only warns.
- Job import aligns vSphere host names and URNs with the target's inventory
  before submitting. Job validation is case-sensitive, and a target that has
  registered a host before keeps its own casing (e.g. `esxi-01` on the source
  vs `ESXi-01` on the target), which failed the import.
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
