# Tests

Pester tests for the `VbrMigrationAutomation` module.

## Scope

These tests are deliberately narrow. The module spends most of its time
talking to a live Veeam REST API, and most real bugs surface only against a
real VBR server (e.g. `uniqueId` vs `id`, session-type-aware polling,
ownership-takeover edge cases). Mocking `Invoke-RestMethod` to "cover" those
paths gives false confidence — functional smoke tests on a live host catch
them faster and more honestly.

What lives here:

- **`Module.Tests.ps1`** — module load and export-surface smoke tests. Verifies
  the `.psd1` parses, the module imports, all 26 public functions are exposed,
  and no `Private/` helper leaks. Also parses every `.ps1` file under the
  module to catch syntax regressions.
- **`Format-RedactedJson.Tests.ps1`** — unit tests for the private redactor.
  Pure function, no external dependencies. Regressions here would leak
  credentials and tokens to logs/transcripts, so it's worth a real test
  suite.

What is **not** covered (deliberately):

- Mocked REST flows for the orchestrators or per-component imports — these
  are validated end-to-end against a real VBR host instead.
- The gateway remap and discovered-entity-ID remap logic. The current
  implementations live inline inside `Import-VBRRepository` and
  `Import-VBRAgentJob`. They would benefit from being extracted into private
  helpers (`Resolve-VBRGatewayRemap`, `Resolve-VBRDiscoveredEntityMap`) so
  they could be unit-tested with fixture JSON. Future improvement.

## Prerequisites

- PowerShell 7.0 or newer.
- [Pester 5+](https://pester.dev/) (`Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck`).

## Running

From the repository root:

```powershell
Invoke-Pester ./tests
```

For verbose output:

```powershell
Invoke-Pester ./tests -Output Detailed
```

To run a single file:

```powershell
Invoke-Pester ./tests/Format-RedactedJson.Tests.ps1 -Output Detailed
```

## CI

These tests are intended to run in GitHub Actions on push/PR. No live VBR
server is required — they only exercise the module surface and pure
helpers.
