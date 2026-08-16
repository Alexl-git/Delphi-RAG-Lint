# Guard: a command that could not do what was asked must SAY SO and exit non-zero.
#
# The INBOX sweep of 2026-08-16 found four notes describing one defect wearing
# four names: a command narrows its work and then reports success for the
# narrowed set as if it were the whole one. This runner is the shared home for
# that family, so the next instance is added here rather than filed separately.
#
# Covered so far:
#   * `index --all --only <name>` where <name> matches no section
#     (docs\INBOX-index-only-nonmatching-section-is-a-silent-noop.md)
#
# Deliberately still open, and NOT asserted here because they are unfixed --
# add arms as each lands, do not delete this list:
#   * `lint <file>` reports 0 findings for whole-run rules that lint-all reports
#   * `lint-all` never scans .dpr bodies and still says "N file(s) scanned"
#   * `lint-all --project` ignores drag-lint-lint.json sitting beside the .dproj
#
# Usage: pwsh -File tests/autotest/run_cli_narrowing_is_reported.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }

# --dry-run throughout except the positive control, so this runner never rebuilds
# a real index as a side effect of asserting an error path.

# --- 1. a selector matching nothing -----------------------------------------
$o = & $Exe index --all --only 'NoSuchSectionXYZ' --dry-run 2>&1 | Out-String
$e = $LASTEXITCODE
Check 'a non-matching --only exits non-zero' ($e -ne 0) "exit=$e"
Check 'it names the selector that matched nothing' ($o -match 'NoSuchSectionXYZ')
Check 'it lists what IS selectable' ($o -match 'selectable for this platform \(\d+\)')
Check 'it states that nothing was indexed' ($o -match 'nothing was indexed')

# --- 2. one valid selector + one typo ---------------------------------------
# The case a bare "did anything match?" check cannot catch: the valid name
# satisfies it while the typo is silently dropped. This is the arm that forces
# per-selector reporting.
$o2 = & $Exe index --all --only 'DragLint-Cli,NoSuchSectionXYZ' --dry-run 2>&1 | Out-String
$e2 = $LASTEXITCODE
Check 'a partially-matching --only still exits non-zero' ($e2 -ne 0) "exit=$e2"
Check 'it names the typo' ($o2 -match 'NoSuchSectionXYZ')
Check 'it does NOT accuse the valid selector' (-not ($o2 -match 'section:[^\r\n]*DragLint-Cli'))

# --- 3. POSITIVE CONTROL ----------------------------------------------------
# Without this, "always exit non-zero on --only" would pass every arm above.
$o3 = & $Exe index --all --only 'DragLint-Cli' --dry-run 2>&1 | Out-String
$e3 = $LASTEXITCODE
Check 'a VALID --only still exits 0' ($e3 -eq 0) "exit=$e3"
Check 'a valid --only reports no error' (-not ($o3 -match 'matched no configured section'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
