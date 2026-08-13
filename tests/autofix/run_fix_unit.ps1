<#
  run_fix_unit.ps1 -- TDD harness for the WHOLE-UNIT fix path (Task 4).

  Proves `lint <F> --fix [--apply]` with NO targeting flags (--fix-line /
  --fix-rule) fixes ALL fixable findings in a unit, not just one. The fixture
  (fixtures\multi.pas) carries TWO fixable findings of DIFFERENT rules on
  DIFFERENT lines:
    line 7: "X := ((A + B));"  -> redundant-parentheses
    line 8: "X := X;"          -> self-assignment
  (confirmed via `lint fixtures\multi.pas` -- exactly these 2, nothing else).

  Copies the fixture to a scratch file under C:\TEMP (kept named multi.pas so
  the unit name still matches the file, quieting unit-name-matches-file), then:
    1) preview (--fix, no --apply): text summary reports
       "autofix: 2 fixable finding(s) -- pass --apply to write" and the file
       on disk is BYTE-IDENTICAL to the fixture; no .bak is written.
    2) apply (--fix --apply): text summary reports
       "autofix: applied 2 edit(s) across 1 file(s) (.bak written)"; the
       noun is EDITS, not fixes, as of 2026-08-13 -- one finding can emit
       several edits (a doc repair emits a delete+insert pair; a rename emits
       one per reference site), so counting findings printed "applied 11
       fix(es) across 0 file(s)" on a run that wrote nothing at all. Here the
       two numbers coincide: 2 findings, 1 edit each. The
       resulting file has BOTH fixes -- line 7's outer parens stripped AND
       line 8 (the self-assignment statement) deleted; a .bak exists holding
       the original two-finding source.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\multi.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_fixunit'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'multi.pas'
$bak    = "$target.bak"

Push-Location C:\TEMP
try {
  # --- 1) PREVIEW (--fix, no --apply): 2 fixable findings reported, file untouched ---
  Copy-Item $fixture $target -Force
  if (Test-Path $bak) { Remove-Item $bak -Force }
  $beforeBytes = [IO.File]::ReadAllBytes($target)
  $pv = & $exePath lint $target --fix 2>$null | Out-String

  Check 'preview: summary reports 2 fixable finding(s)' ($pv -match 'autofix: 2 fixable finding\(s\) -- pass --apply to write')
  Check 'preview: dry-run mentions delete lines 8..8'    ($pv -match 'delete lines 8\.\.8')
  Check 'preview: dry-run mentions replace on L7'        ($pv -match 'replace L7:')
  $afterBytes = [IO.File]::ReadAllBytes($target)
  Check 'preview: file NOT modified on disk' ( [System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeBytes, [byte[]]$afterBytes) )
  Check 'preview: NO .bak written'           (-not (Test-Path $bak))

  # --- 2) APPLY (--fix --apply): BOTH fixes applied, N=2, .bak holds the original ---
  Copy-Item $fixture $target -Force
  if (Test-Path $bak) { Remove-Item $bak -Force }
  $ap = & $exePath lint $target --fix --apply 2>$null | Out-String

  Check 'apply: summary reports applied 2 edit(s) across 1 file(s)' ($ap -match 'autofix: applied 2 edit\(s\) across 1 file\(s\) \(\.bak written\)')

  $lines = [IO.File]::ReadAllLines($target)
  Check 'apply: line 7 parens stripped ("  X := (A + B);")' ($lines.Count -ge 7 -and $lines[6].Trim() -eq 'X := (A + B);')
  Check 'apply: self-assignment line removed (no "X := X;" survives)' (-not ($lines -match '^\s*X := X;\s*$'))
  Check 'apply: file line count shrank by 1 (11 lines -> 10)' ($lines.Count -eq 10)

  Check 'apply: .bak written' (Test-Path $bak)
  if (Test-Path $bak) {
    $bakText = [IO.File]::ReadAllText($bak)
    Check 'apply: .bak holds the ORIGINAL "((A + B))"' ($bakText.Contains('((A + B))'))
    Check 'apply: .bak holds the ORIGINAL "X := X;"'   ($bakText.Contains('X := X;'))
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
