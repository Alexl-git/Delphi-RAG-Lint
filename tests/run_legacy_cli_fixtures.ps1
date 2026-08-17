<#
  run_legacy_cli_fixtures.ps1 -- the legacy .bat fixtures that NO driver ever
  called, now that each has been verified individually.

  BACKGROUND. 68 .bat tests lived under tests\ and run_battery.ps1 could not see
  any of them (it globs run_*.ps1). run_doctests_v021.ps1 now covers the 22 that
  the v021 driver stitches together. THESE 18 were never in any driver at all --
  not orphaned later, never wired up in the first place -- so nothing had ever
  run them.

  WHAT RUNNING THEM FOUND. 15 passed immediately. The other three were each a
  real defect, and only one was in a test:

    T38_doc_stub   -- a GENUINE ENGINE REGRESSION. `generate-docs` emitted no
                      <returns>/@returns for any class function, because
                      SignatureHasReturn tests for a leading `function` keyword
                      that an INDEXED signature does not carry, and the kind
                      fallback beside it never fires for a method (indexed as
                      skMethod). DRagLint.Doc.Document and .Drift both already
                      documented and worked around this exact trap; the stub
                      generator was the one consumer that never did. Fixed by
                      SignatureDeclaresReturn.
    T44_lint_pack  -- an OBSOLETE ASSERTION. It demanded
                      `string-equality-comparison` fire; that rule was narrowed
                      and defaulted OFF for being over-eager (it fired on any
                      `=` expression), and RuleTest.pas contains no string
                      comparison at all. The assertion was removed, not the rule
                      re-enabled.
    T31_hoverform  -- THREE layered SCRIPT bugs, none of them the IDE dependency
                      it looked like: a nested `cmd /c "call ""..."""` that never
                      reached the compiler; then the Windows trap where a
                      TRAILING BACKSLASH before a closing quote escapes it, so
                      "-E%HERE%" swallowed the following arguments and dcc64 read
                      `Files` (from "Program Files") as its project; then a
                      missing src\core on the unit path.

  WHY A SEPARATE RUNNER FROM run_doctests_v021.ps1. That one drives a single
  .bat chain and reports one exit code; these are independent fixtures with no
  ordering between them, so each gets its own timeout and its own line. A hang
  in one must not take the rest down -- T37 speaks MCP over stdin and is exactly
  the shape that can block.

  T31 COMPILES with dcc64 and needs RAD Studio present. That is not new for this
  battery (the .dpr suites compile the engine from source), but it is the one
  fixture here that is not pure CLI.

  Usage: pwsh -File tests/run_legacy_cli_fixtures.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\third_party\dll-win64\drag-lint.exe",
  [int]   $PerFixtureTimeoutSec = 120
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

# Pinned, not discovered. Discovery would silently shrink to zero if the folder
# were emptied or renamed, and a zero-length run reports success -- the exact
# failure mode that let this whole .bat suite rot unnoticed.
$Fixtures = @(
  'T31_hoverform', 'T35_rename_dry', 'T36_rename_apply', 'T37_mcp_rename',
  'T38_doc_stub', 'T39_deadcode', 'T41_test_stub', 'T42_format', 'T42_outline',
  'T43_scanfilter', 'T44_lint_pack', 'T44_usages', 'T53_parser_error',
  'T56_lint_rules_v032', 'T60_workspace_index', 'T61_hovertracker',
  'T62_lint_rules_v035', 'T_resolve_uses'
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixDir   = Join-Path $PSScriptRoot 'fixtures'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$env:EXE = (Resolve-Path $Exe).Path   # every fixture defers to a pre-set EXE

$ran = 0
foreach ($name in $Fixtures) {
  $bat = Join-Path $fixDir "$name.bat"
  if (-not (Test-Path $bat)) { Check $name $false 'fixture file missing'; continue }
  $lg = Join-Path $env:TEMP ("drag-lint-legacy-{0}-{1}.log" -f $name, $PID)
  $p  = Start-Process cmd.exe -ArgumentList '/c', $bat -WorkingDirectory $repoRoot `
                      -PassThru -NoNewWindow -RedirectStandardOutput $lg -RedirectStandardError "$lg.err"
  if (-not $p.WaitForExit($PerFixtureTimeoutSec * 1000)) {
    try { $p.Kill() } catch { }
    Check $name $false ("TIMEOUT after {0}s" -f $PerFixtureTimeoutSec)
  }
  else {
    $txt    = if (Test-Path $lg) { Get-Content $lg -Raw } else { '' }
    $first  = ([regex]::Matches($txt, '(?m)^FAIL[^\r\n]*') | ForEach-Object { $_.Value } | Select-Object -First 1)
    Check $name ($p.ExitCode -eq 0) $(if ($first) { $first } else { "exit=$($p.ExitCode)" })
  }
  $ran++
  foreach ($f in @($lg, "$lg.err")) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
}
Remove-Item Env:\EXE -ErrorAction SilentlyContinue

# POSITIVE CONTROL: an empty or truncated list would otherwise report a clean run.
Check ("POSITIVE CONTROL: all {0} fixtures were attempted" -f $Fixtures.Count) `
  ($ran -eq $Fixtures.Count) ("attempted={0} want={1}" -f $ran, $Fixtures.Count)

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
