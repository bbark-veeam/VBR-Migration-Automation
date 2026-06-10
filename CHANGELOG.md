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
### Changed
### Fixed
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
