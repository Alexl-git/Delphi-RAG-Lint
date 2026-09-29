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

  COMPILED FIXTURES ARE JUDGED BY THEIR BUILD LOG, not only by the .bat's exit
  code (see THE COMPILE GUARD below). A dcc64 fixture FAILS when its build log
  has an `Error:` / `Fatal:` line, when the log has no dcc64 `N lines, ...`
  summary (the compiler never received a project -- T61's trailing-backslash
  quote made dcc64 print its usage and exit 0), or when there is no log at all.
  The one exception: no log AND the .bat printed `SKIP:` (rsvars.bat missing,
  no RAD Studio on the box) is reported as a SKIP, not a failure.

  THE OWNER'S IDE SETTINGS ARE GUARDED. T29/T34/T54 (and anything else that
  links DragLint.Plugin.Settings) round-trip SaveSettings and end with
  SaveSettings(DefaultSettings). Their .bats compile with
  -DDRAGLINT_TEST_REGROOT, which points the unit at
  HKCU\Software\drag-lint\DelphiPlugin.Test instead of the live
  ...\DelphiPlugin. This runner snapshots the LIVE key's values before the
  fixtures and fails `owner plugin settings untouched` if any changed, then
  deletes the .Test key (values only, no subkeys: not recursive).

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
  # --- pure CLI ---------------------------------------------------------------
  'T35_rename_dry', 'T36_rename_apply', 'T37_mcp_rename', 'T38_doc_stub',
  'T39_deadcode', 'T41_test_stub', 'T42_format', 'T42_outline',
  'T43_scanfilter', 'T44_lint_pack', 'T44_usages', 'T53_parser_error',
  'T56_lint_rules_v032', 'T60_workspace_index', 'T61_hovertracker',
  'T62_lint_rules_v035', 'T_resolve_uses',
  # --- COMPILE a .dpr with dcc64; eight of them link designide ----------------
  # Every one of these was written from the same broken template and had NEVER
  # run: 14 carried the nested `cmd /c "call ""..."""` that never reached the
  # compiler, 15 carried the trailing-backslash-escapes-the-quote trap, and
  # several had unit paths that went stale when a dependency moved to src\core
  # or src\index. They were not IDE-blocked, as their subject matter suggested --
  # they were simply never executed, so nothing reported any of it.
  'T28_notifier', 'T29_settings', 'T30_keyboard', 'T31_hoverform',
  'T32_completionform', 'T33_signatureform', 'T34_save_setting',
  'T40_compile_parser', 'T43_refactorform', 'T47_regcolors', 'T48_diag_cache',
  'T51_structure', 'T54_settings_scan_libraries', 'T55_codelens_cache',
  'T57_usages_form', 'T58_symbolsearch_form', 'T59_workspace_config',
  'T63_lint_config_roundtrip', 'T64_lint_options_compile', 'T65_profile_apply',
  'T66_open_source_path',
  # --- POSITIVE CONTROL for the compile guard below: must NOT compile ----------
  'T67_compile_fail'
)

# Fixtures that MUST fail, and the detail their failure must start with. The
# Check for one of these passes only when it failed for exactly that reason; a
# pass, or a failure for any other reason, is a FAIL of the guard itself.
$ExpectFail = @{ 'T67_compile_fail' = 'compile failed' }

# THE COMPILE GUARD. A fixture that compiles a .dpr with dcc64 used to be judged
# by its .bat's exit code alone, and every such .bat checks only `if not exist
# <exe>` after the compile. A failed compile leaves the PREVIOUS build's exe in
# place, so the stale exe ran, printed OK, and 8 fixtures stayed green for weeks
# on code that no longer compiled (F2613 on src\core units, E2035 on a changed
# signature). So, centrally, for every .bat that runs dcc64: delete
# fixtures\<name>.exe and the build log BEFORE it runs, and AFTER it runs fail on
# any `Error:` / `Fatal:` line in the build log, whatever the exit code says.
# The build log is the redirect target of the dcc64 line (one level of %VAR%
# indirection, as T40's >"%LOG%" needs); it always lives in tests\fixtures.
function Get-BuildLogPath([string]$BatText) {
  $line = [regex]::Match($BatText, '(?im)^\s*dcc64\b.*$').Value
  $targets = @([regex]::Matches($line, '(?<![0-9])>\s*"?([^"\s|&]+)"?') |
               ForEach-Object { $_.Groups[1].Value })
  if ($targets.Count -eq 0) { return $null }
  $t = $targets[-1]
  $v = [regex]::Match($t, '^%(\w+)%$')
  if ($v.Success) {
    $set = [regex]::Match($BatText, '(?im)^\s*set\s+' + $v.Groups[1].Value + '=(.+)$')
    if (-not $set.Success) { return $null }
    $t = $set.Groups[1].Value.Trim().Trim('"')
  }
  $leaf = ($t -split '[\\%]')[-1]
  if (-not $leaf) { return $null }
  return Join-Path $fixDir $leaf
}

# Drivers that live in tests\ itself rather than tests\fixtures\. run_phase1_e2e
# is a genuine end-to-end smoke test over index / query / find-callers / lint /
# --dry-run / --version and was orphaned the same way everything else here was.
$RootDrivers = @('run_phase1_e2e')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixDir   = Join-Path $PSScriptRoot 'fixtures'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$env:EXE = (Resolve-Path $Exe).Path   # every fixture defers to a pre-set EXE

# OWNER SETTINGS GUARD (see the header). A snapshot is the sorted list of
# `name=kind:value` strings under the key; a missing key snapshots as empty, so
# missing-before and missing-after compare equal.
$LiveRegKey = 'HKCU:\Software\drag-lint\DelphiPlugin'
$TestRegKey = 'HKCU:\Software\drag-lint\DelphiPlugin.Test'
function Get-RegSnapshot([string]$Path) {
  if (-not (Test-Path $Path)) { return @() }
  $k = Get-Item $Path
  return @($k.GetValueNames() | Sort-Object | ForEach-Object {
    '{0}={1}:{2}' -f $_, $k.GetValueKind($_), (@($k.GetValue($_, $null, 'DoNotExpandEnvironmentNames')) -join '|')
  })
}
function Compare-RegSnapshot([string[]]$Before, [string[]]$After) {
  $b = @($Before | Where-Object { $_ }); $a = @($After | Where-Object { $_ })
  return @(@($b | Where-Object { $a -notcontains $_ } | ForEach-Object { "was $_" }) +
           @($a | Where-Object { $b -notcontains $_ } | ForEach-Object { "now $_" }))
}
# SELF-TEST of the comparison on synthetic snapshots -- the live key is never
# modified to prove the guard can fire.
$stEqual   = Compare-RegSnapshot @('A=String:1', 'B=DWord:0') @('A=String:1', 'B=DWord:0')
$stEmpty   = Compare-RegSnapshot @() @()
$stChanged = Compare-RegSnapshot @('A=String:1', 'B=DWord:0') @('A=String:1', 'B=DWord:1')
$stAdded   = Compare-RegSnapshot @() @('A=String:1')
Check 'SELF-TEST: registry comparison (equal=pass, empty=pass, changed value=fail, added value=fail)' `
  (($stEqual.Count -eq 0) -and ($stEmpty.Count -eq 0) -and ($stChanged.Count -eq 2) -and ($stAdded.Count -eq 1)) `
  ("equal={0} empty={1} changed={2} added={3}" -f $stEqual.Count, $stEmpty.Count, $stChanged.Count, $stAdded.Count)
$liveBefore = Get-RegSnapshot $LiveRegKey

$ran = 0
foreach ($name in ($Fixtures + $RootDrivers)) {
  $bat = if ($RootDrivers -contains $name) { Join-Path $PSScriptRoot "$name.bat" }
         else                              { Join-Path $fixDir      "$name.bat" }
  if (-not (Test-Path $bat)) { Check $name $false 'fixture file missing'; continue }
  $compiles = (Get-Content $bat -Raw) -match '(?im)^\s*dcc64\b'
  $buildLog = $null
  if ($compiles) {
    $buildLog = Get-BuildLogPath (Get-Content $bat -Raw)
    foreach ($stale in @((Join-Path $fixDir "$name.exe"), $buildLog)) {
      if ($stale -and (Test-Path $stale)) { [IO.File]::Delete($stale) }
    }
  }
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
    $ok     = ($p.ExitCode -eq 0)
    $detail = if ($first) { $first } else { "exit=$($p.ExitCode)" }
    $skip   = [regex]::Match($txt, '(?m)^SKIP:[^\r\n]*').Value
    if ($compiles) {
      if (-not $buildLog -or -not (Test-Path $buildLog)) {
        if ($skip) { $detail = $skip }
        else { $ok = $false; $detail = 'compile failed: no build log found for the dcc64 line' }
      }
      else {
        $blText = Get-Content $buildLog -Raw
        $err = [regex]::Match($blText, '(?m)^[^\r\n]*\b(Error|Fatal):[^\r\n]*')
        if ($err.Success) { $ok = $false; $detail = 'compile failed: ' + $err.Value.Trim() }
        elseif ($blText -notmatch '(?m)^\d+ lines, ') {
          $ok = $false; $detail = 'compile failed: build log has no dcc64 "N lines" summary -- no project was compiled'
        }
      }
    }
    if ($ExpectFail.ContainsKey($name)) {
      Check $name ((-not $ok) -and $detail.StartsWith($ExpectFail[$name])) ('EXPECTED FAIL -- ' + $detail)
    }
    else { Check $name $ok $detail }
  }
  $ran++
  foreach ($f in @($lg, "$lg.err")) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
}
Remove-Item Env:\EXE -ErrorAction SilentlyContinue

$liveDiff = Compare-RegSnapshot $liveBefore (Get-RegSnapshot $LiveRegKey)
Check 'owner plugin settings untouched' ($liveDiff.Count -eq 0) ($liveDiff -join '; ')
if (Test-Path $TestRegKey) {
  try   { Remove-Item -Path $TestRegKey -ErrorAction Stop }
  catch { Check 'test settings key removed' $false $_.Exception.Message }
}

# POSITIVE CONTROL: an empty or truncated list would otherwise report a clean run.
$want = $Fixtures.Count + $RootDrivers.Count
Check ("POSITIVE CONTROL: all {0} fixtures were attempted" -f $want) `
  ($ran -eq $want) ("attempted={0} want={1}" -f $ran, $want)

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
