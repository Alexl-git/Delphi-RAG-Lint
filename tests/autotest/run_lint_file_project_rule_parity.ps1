<#
  run_lint_file_project_rule_parity.ps1 -- docs\PLAN-SESSION-47.md T4
  (docs\INBOX-ide-per-unit-view-omits-79pct-of-lint-all.md)

  Measured against the owner's own DataCopy lint-report-20260828.txt: 207 of 260
  findings (79%) came from rules `lint <file>` never ran -- doc-drift 128 (49%),
  unused-unit-in-uses 66 (25%), review-marker-unused 9, unused-public-symbol 4.
  None of those is genuinely whole-project: the INDEX already holds the
  project-wide state and the two verbs simply never shared it.

  D2 IS THE POINT OF THIS GUARD, IN BOTH DIRECTIONS.

  Forward: every rule id lint-all reports for a file must now be reported by
  `lint <that file> --db`, except the structurally-impossible set named below.

  Reverse: and NOTHING MORE. That direction is not hypothetical -- it is a
  regression this change actually introduced and this guard actually caught.
  The project-level rules ship OFF by default via a list each verb kept by hand;
  lint-all had one, `lint` did not (those rules had never run there), so the
  moment they ran per file the per-file verb reported feature-envy and
  missing-doc on a unit where lint-all deliberately says nothing -- 12 rule ids
  against lint-all's 10. The fix was one shared list, and this is what pins it.

  WHAT IS DELIBERATELY EXCLUDED FROM THE EQUALITY, and why each one:
    doc-drift, missing-doc  -- computable per file and CORRECT, but rebuilt PER
                               DECLARATION at ~16 ms each: a 53-decl unit costs
                               0.83 s and a real DataCopy unit reached 8.75 s
                               against the IDE plugin's HARD 8 s timeout, whose
                               failure branch shows NO diagnostics at all.
                               Opt-in via --project-rules; D3 pins that.
    review-marker-unused    -- must see every file to know a marker matches none.
    duplicate-code          -- lint-all does cross-file, per-file does within-file.
    interface-reference-cycle, unit-not-in-dpr -- no per-file answer can be right.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_file_project_parity"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory -Path $proj -Force | Out-Null

# A public routine nothing calls -> unused-public-symbol.
# A documented routine whose doc names a parameter that does not exist -> doc-drift.
$lib = @'
unit uT4Lib;

interface

/// <summary>Adds two numbers.</summary>
/// <param name="pA">first</param>
/// <param name="pGhost">this parameter does not exist -- deliberate doc drift</param>
function AddThem(const pA, pB: Integer): Integer;

procedure PublicNeverCalled;

implementation

function AddThem(const pA, pB: Integer): Integer;
begin
  Result:= pA + pB;
end;

procedure PublicNeverCalled;
begin
end;

end.
'@

# Imports uT4Lib and never references it -> unused-unit-in-uses (the 25%).
$main = @'
unit uT4Main;

interface

uses
  uT4Lib;

procedure DoNothingWithLib;

implementation

procedure DoNothingWithLib;
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'uT4Lib.pas')  $lib
Write-Ascii (Join-Path $proj 'uT4Main.pas') $main
$db = Join-Path $WorkDir 't4.sqlite'

# ABSOLUTE index target: a relative one writes relative rows, the membership
# probe misses, and the store is silently dropped -- which would make every
# assertion below pass for a store-free run.
$idx = & $exePath index $proj --db $db 2>&1 | Out-String
Check 'SANITY: fixture indexed with no errors' `
      ($LASTEXITCODE -eq 0 -and $idx -notmatch '\b[1-9]\d* errors\b') $idx

$mainPas = Join-Path $proj 'uT4Main.pas'
$allOut  = Join-Path $WorkDir 'all.txt'
& $exePath lint-all --db $db --rules-dir $rules --output $allOut 2>&1 | Out-Null
$allTxt  = if (Test-Path $allOut) { Get-Content $allOut -Raw } else { '' }

function IdsFor($text, $fileLeaf) {
  @($text -split "`r?`n" |
      Where-Object { $_ -match [regex]::Escape($fileLeaf) -and $_ -match '\]\s+[a-z0-9-]+:' } |
      ForEach-Object { if ($_ -match '\]\s+([a-z0-9-]+):') { $Matches[1] } }) | Sort-Object -Unique
}
function IdsOf($text) {
  @($text -split "`r?`n" |
      Where-Object { $_ -match '\]\s+[a-z0-9-]+:' } |
      ForEach-Object { if ($_ -match '\]\s+([a-z0-9-]+):') { $Matches[1] } }) | Sort-Object -Unique
}

$perFile = & $exePath lint $mainPas --db $db --rules-dir $rules 2>&1 | Out-String

Check 'D1  the 25% rule -- unused-unit-in-uses is now reported PER FILE' `
      ($perFile -match 'unused-unit-in-uses') `
      "uT4Main imports uT4Lib and never uses it; lint-all reports this and the per-file verb must too"

Check 'D1b CONTROL: lint-all reports it too (the fixture really does trigger it)' `
      ($allTxt -match 'unused-unit-in-uses') `
      "if lint-all does not report it either, the fixture is wrong and D1 proves nothing"

$STRUCTURAL = @('doc-drift','missing-doc','review-marker-unused','review-marker-stale',
                'duplicate-code','interface-reference-cycle','unit-not-in-dpr')

$allIds  = @(IdsFor $allTxt 'uT4Main.pas') | Where-Object { $STRUCTURAL -notcontains $_ }
$fileIds = @(IdsOf  $perFile)              | Where-Object { $STRUCTURAL -notcontains $_ }

$missing = @($allIds  | Where-Object { $fileIds -notcontains $_ })
$extra   = @($fileIds | Where-Object { $allIds  -notcontains $_ })

Check 'D2a FORWARD: every lint-all rule id for this file is reported per-file' `
      ($missing.Count -eq 0) `
      ("missing from the per-file run: " + ($missing -join ', '))

Check 'D2b REVERSE: the per-file run reports NOTHING lint-all does not' `
      ($extra.Count -eq 0) `
      ("extra in the per-file run: " + ($extra -join ', ') + " -- the off-by-default list must be SHARED, not kept per verb")

# --project-rules is the documented escape hatch for the per-decl doc rules.
$withDoc = & $exePath lint (Join-Path $proj 'uT4Lib.pas') --db $db --rules-dir $rules --project-rules 2>&1 | Out-String
$noDoc   = & $exePath lint (Join-Path $proj 'uT4Lib.pas') --db $db --rules-dir $rules 2>&1 | Out-String

# Match a FINDING LINE, not the bare word. The closing stderr note NAMES
# doc-drift as the thing you opt into, so `-match 'doc-drift'` is satisfied by
# the note itself -- which is exactly how this control first failed against a
# correct build. A control that fails on correct code is worse than no control.
function DocDriftFindings($text) {
  @($text -split "`r?`n" | Where-Object { $_ -match '\]\s+doc-drift:' }).Count
}

Check 'D3  --project-rules turns doc-drift ON for the file' `
      ((DocDriftFindings $withDoc) -ge 1) `
      "the doc names a parameter pGhost that does not exist; with the opt-in this must be reported"

Check 'D3b CONTROL: without --project-rules the SAME file does not report it' `
      ((DocDriftFindings $noDoc) -eq 0) `
      "if it reports either way the flag is doing nothing and D3 is vacuous"

Write-Host ''
if ($fail) { Write-Host 'run_lint_file_project_rule_parity: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_file_project_rule_parity: PASS' -ForegroundColor Green
exit 0
