<#
  run_fix_project.ps1 -- TDD harness for the WHOLE-PROJECT fix path (Task 5).

  Proves `lint-all --db <index> --fix [--apply]` fixes EVERY fixable finding
  across ALL indexed units of a project -- not just one file. The whole-project
  fix is hosted by the `lint-all` verb: it enumerates every indexed .pas file,
  runs the per-file linter (which produces the 3 fixable rules), accumulates the
  findings tree-wide, then routes through the shared FinalizeAndOutput --fix
  block (Task 3) whose BuildAutofixEdits groups edits by file and whose
  TTextEditApplier applies + counts distinct files. lint-project is NOT the host
  -- its rules (interface-reference-cycle / layering-violation /
  unit-not-in-project) are none of them fixable.

  Fixture (fixtures\proj\) = two minimal compilable units, each carrying ONE
  fixable finding of a DIFFERENT rule in a DIFFERENT file:
    unita.pas line 7: "X := ((A + B));" -> redundant-parentheses
    unitb.pas line 7: "Y := Y;"         -> self-assignment
  (confirmed via `lint-all` -- exactly these 2, nothing else.)

  Copies the fixture dir to a scratch dir under C:\TEMP (kept the unit names so
  unit-name-matches-file stays quiet), indexes it to a scratch db, then:
    1) preview (--fix, no --apply): text summary reports
       "autofix: 2 fixable finding(s) -- pass --apply to write"; the dry-run
       names BOTH files; both units on disk are BYTE-IDENTICAL to the fixture;
       no .bak is written.
    2) apply (--fix --apply): text summary reports
       "autofix: applied 2 fix(es) across 2 file(s) (.bak written)"; unita's
       outer parens are stripped AND unitb's self-assignment line is deleted;
       a .bak exists beside EACH fixed unit holding its original source.
    3) json (--fix --json, no --apply): emits an array with one object PER FILE
       (unita+unitb), each fixable=true / applied=false / preview=true; files
       untouched.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.

  ADF Task 9 (guardrail): the fixture units are undocumented, so the doc rules
  would fire on their public decls -- doc-drift is ON by default; missing-doc is
  OFF by default (ADF Task 13 -- the measured 1302-finding first-run wave), so it
  no longer fires on a bare lint-all. Either would add non-fixable findings to
  lint-all's output and break the "--fix --json returns exactly 2" assertion below.
  This suite tests AUTOFIX behavior, not the doc rules (those have their own
  coverage in tests\autodoc\run_missing_doc.ps1 / run_doc_drift_rule.ps1), so we
  scope every lint-all --fix invocation with --disable missing-doc,doc-drift.
  The --disable doc-drift is load-bearing (ON by default); --disable missing-doc
  is now belt-and-braces (OFF by default) but stays for clarity + defence in depth.
  The count is then GENUINELY 2 (the 2 fixable autofix edits), not a loosened
  assertion. Disabled findings are dropped by FinalizeAndOutput's ShouldKeep
  filter BEFORE the --fix block builds edits, so the fixable set is unaffected.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath  = (Resolve-Path $Exe).Path
$fixDir   = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\proj')).Path
$fixA     = Join-Path $fixDir 'unita.pas'
$fixB     = Join-Path $fixDir 'unitb.pas'

# Fresh scratch dir; keep the unit names so unit-name-matches-file stays quiet.
$scratch  = Join-Path C:\TEMP 'draglint_fixproj'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$targetA  = Join-Path $scratch 'unita.pas'
$targetB  = Join-Path $scratch 'unitb.pas'
$bakA     = "$targetA.bak"
$bakB     = "$targetB.bak"
$db       = Join-Path $scratch 'proj.sqlite'
$report   = Join-Path $scratch 'lint-report.txt'

# Copies both fixture units fresh into the scratch dir and clears any prior
# .bak; then (re)indexes the scratch dir to the scratch db so lint-all sees the
# just-copied sources.
function Reset-Fixture {
  Copy-Item $fixA $targetA -Force
  Copy-Item $fixB $targetB -Force
  if (Test-Path $bakA) { Remove-Item $bakA -Force }
  if (Test-Path $bakB) { Remove-Item $bakB -Force }
  if (Test-Path $db)   { Remove-Item $db   -Force }
  & $exePath index $scratch --db $db 2>$null | Out-Null
}

Push-Location C:\TEMP
try {
  # --- 1) PREVIEW (--fix, no --apply): 2 fixable across 2 files, both untouched ---
  Reset-Fixture
  $beforeA = [IO.File]::ReadAllBytes($targetA)
  $beforeB = [IO.File]::ReadAllBytes($targetB)
  $pv = & $exePath lint-all --db $db --fix --disable missing-doc,doc-drift --output $report 2>$null | Out-String

  Check 'preview: summary reports 2 fixable finding(s)' ($pv -match 'autofix: 2 fixable finding\(s\) -- pass --apply to write')
  Check 'preview: dry-run names unita.pas'              ($pv -match 'unita\.pas')
  Check 'preview: dry-run names unitb.pas'              ($pv -match 'unitb\.pas')
  Check 'preview: dry-run mentions replace on L7 (parens)' ($pv -match 'replace L7:')
  Check 'preview: dry-run mentions delete lines 7..7 (self-assign)' ($pv -match 'delete lines 7\.\.7')

  $afterA = [IO.File]::ReadAllBytes($targetA)
  $afterB = [IO.File]::ReadAllBytes($targetB)
  Check 'preview: unita.pas NOT modified on disk' ( [System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeA, [byte[]]$afterA) )
  Check 'preview: unitb.pas NOT modified on disk' ( [System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeB, [byte[]]$afterB) )
  Check 'preview: NO .bak for unita' (-not (Test-Path $bakA))
  Check 'preview: NO .bak for unitb' (-not (Test-Path $bakB))

  # --- 2) JSON preview (--fix --json): one object per file, fixable/preview flags ---
  # lint-all prints a "scanning N .pas file(s)" preamble line to stdout before the
  # JSON (same contract run_store_tests.ps1 relies on), so slice from the first '['.
  Reset-Fixture
  $raw = & $exePath lint-all --db $db --fix --json --disable missing-doc,doc-drift --output $report 2>$null | Out-String
  $arr = $null
  $b = $raw.IndexOf('[')
  if ($b -ge 0) { try { $arr = ($raw.Substring($b) | ConvertFrom-Json) } catch { $arr = $null } }
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }
  Check 'json: parses as a 2-element array' ($null -ne $arr -and $arr.Count -eq 2)
  $ja = if ($null -ne $arr) { $arr | Where-Object { $_.file -match 'unita\.pas' } | Select-Object -First 1 } else { $null }
  $jb = if ($null -ne $arr) { $arr | Where-Object { $_.file -match 'unitb\.pas' } | Select-Object -First 1 } else { $null }
  Check 'json: unita object present (rule=redundant-parentheses)' ($null -ne $ja -and $ja.rule -eq 'redundant-parentheses')
  Check 'json: unitb object present (rule=self-assignment)'       ($null -ne $jb -and $jb.rule -eq 'self-assignment')
  if ($null -ne $ja) {
    Check 'json: unita fixable=true / applied=false / preview=true' ($ja.fixable -eq $true -and $ja.applied -eq $false -and $ja.preview -eq $true)
  }
  if ($null -ne $jb) {
    Check 'json: unitb fixable=true / applied=false / preview=true' ($jb.fixable -eq $true -and $jb.applied -eq $false -and $jb.preview -eq $true)
  }
  Check 'json: unita.pas NOT modified on disk' ([IO.File]::ReadAllText($targetA).Contains('((A + B))'))
  Check 'json: unitb.pas NOT modified on disk' ([IO.File]::ReadAllText($targetB) -match '(?m)^\s*Y := Y;\s*$')

  # --- 3) APPLY (--fix --apply): BOTH units fixed, N=2 across 2 files, .baks written ---
  Reset-Fixture
  $ap = & $exePath lint-all --db $db --fix --apply --disable missing-doc,doc-drift --output $report 2>$null | Out-String

  Check 'apply: summary reports applied 2 fix(es) across 2 file(s)' ($ap -match 'autofix: applied 2 fix\(es\) across 2 file\(s\) \(\.bak written\)')

  $linesA = [IO.File]::ReadAllLines($targetA)
  Check 'apply: unita line 7 parens stripped ("  X := (A + B);")' ($linesA.Count -ge 7 -and $linesA[6].Trim() -eq 'X := (A + B);')
  Check 'apply: unita no "((A + B))" survives' (-not ([IO.File]::ReadAllText($targetA).Contains('((A + B))')))

  $linesB = [IO.File]::ReadAllLines($targetB)
  Check 'apply: unitb self-assignment line removed (no "Y := Y;" survives)' (-not ($linesB -match '^\s*Y := Y;\s*$'))
  Check 'apply: unitb line count shrank by 1 (10 lines -> 9)' ($linesB.Count -eq 9)

  Check 'apply: .bak written beside unita' (Test-Path $bakA)
  Check 'apply: .bak written beside unitb' (Test-Path $bakB)
  if (Test-Path $bakA) {
    Check 'apply: unita.bak holds the ORIGINAL "((A + B))"' ([IO.File]::ReadAllText($bakA).Contains('((A + B))'))
  }
  if (Test-Path $bakB) {
    Check 'apply: unitb.bak holds the ORIGINAL "Y := Y;"' ([IO.File]::ReadAllText($bakB).Contains('Y := Y;'))
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
