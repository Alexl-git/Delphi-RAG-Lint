<#
  run_allow_doc_comment_anchor.ps1 -- `allow` on a finding anchored to a `///` doc-comment line.

  doc-drift anchors its finding on the FIRST line of the DocInsight block, a `///` line. `allow`
  refused that line ("carries no code"), and a marker written by hand on the declaration below did
  not suppress either: the marker span was the finding's own StartLine..EndLine (the `///` line
  only) and the hash was taken there. So a doc-drift finding could not be reviewed at all.

  H2 (2026-10-25): a `///` block belongs to the declaration that follows it, so the marker for a
  finding anchored inside the block lives on that declaration line. `allow` writes it there (the
  doc-comment stays byte-identical), and the suppression span and expected hash
  (MarkerExpectedHash / DocCommentMarkerLine) reach the same line, in lint-all and lint alike.

  Asserts, on a scratch fixture written here:
    SANITY  lint-all reports doc-drift on Wrong and Wrong2 at their `///` lines.
    A  allow --fix-line <Wrong's /// line> --fix-rule doc-drift --apply exits 0.
    B  the doc-comment lines are byte-identical; the marker is on the declaration line.
    C  lint-all: no doc-drift on Wrong; no review-marker-* finding.
    D  POSITIVE CONTROL: Wrong2 (same shape, not allowed) still reports doc-drift.
    E  lint <file> --project-rules: same answer as lint-all (Wrong 0, Wrong2 >= 1).
    F  CONTROL: a blank line is still refused (exit 1), and the file is untouched.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-allow-doc-anchor-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$src = Join-Path $WorkDir 'allowdoc.pas'
$db  = Join-Path $WorkDir 'allowdoc.sqlite'
$lines = @(
  'unit allowdoc;', '', 'interface', '', 'uses', '  System.SysUtils;', '', 'type', '  ENever = class(Exception);', '',
  '/// <summary>Documents a class nothing raises.</summary>',          # 11
  '/// <exception cref="ENever">Never raised.</exception>',            # 12
  'procedure Wrong;',                                                  # 13
  '',                                                                  # 14
  '/// <summary>Same shape, not reviewed: the positive control.</summary>', # 15
  '/// <exception cref="ENever">Never raised.</exception>',            # 16
  'procedure Wrong2;',                                                 # 17
  '', 'implementation', '',
  'procedure Wrong;', 'begin', '  Sleep(1);', 'end;', '',
  'procedure Wrong2;', 'begin', '  Sleep(2);', 'end;', '', 'end.')
[IO.File]::WriteAllText($src, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

function LintAll {
  $o = (& $Exe lint-all --db $db --json --library-db none 2>$null | Out-String)
  $r = @(); try { $r = @($o | ConvertFrom-Json) } catch { $r = @() }
  return @{ Out = $o; Rows = $r }
}
function DriftAt($rows, [int]$line) { @($rows | Where-Object { $_.rule -eq 'doc-drift' -and $_.start_line -eq $line }) }

Push-Location $WorkDir
try {
  & $Exe index $WorkDir --db $db --library-db none 2>&1 | Out-Null
  $before = LintAll
  Check 'SANITY: lint-all reports doc-drift on Wrong at its /// line 11' ((DriftAt $before.Rows 11).Count -ge 1) $before.Out
  Check 'SANITY: lint-all reports doc-drift on Wrong2 at its /// line 15' ((DriftAt $before.Rows 15).Count -ge 1) $before.Out

  $al = & $Exe allow $src --fix-line 11 --fix-rule doc-drift --apply --db $db --library-db none 2>&1 | Out-String
  Check 'A: allow on the /// line exits 0' ($LASTEXITCODE -eq 0) $al
  $after = [IO.File]::ReadAllLines($src)
  Check 'B: doc-comment line 11 byte-identical' ($after[10] -ceq $lines[10]) $after[10]
  Check 'B: doc-comment line 12 byte-identical' ($after[11] -ceq $lines[11]) $after[11]
  Check 'B: the marker is on the declaration line 13' ($after[12] -match '^procedure Wrong;\s+// dl:ok doc-drift@[0-9a-f]{4}') $after[12]
  Check 'B: nothing else changed (line count)' ($after.Count -eq $lines.Count) "lines: $($after.Count)"

  $r = LintAll
  Check 'C: lint-all: no doc-drift left on Wrong' ((DriftAt $r.Rows 11).Count -eq 0) $r.Out
  Check 'C: lint-all: the marker is neither unused nor stale' (@($r.Rows | Where-Object { $_.rule -like 'review-marker-*' }).Count -eq 0) $r.Out
  Check 'D: POSITIVE CONTROL Wrong2 still reports doc-drift at line 15' ((DriftAt $r.Rows 15).Count -ge 1) $r.Out

  $lo = (& $Exe lint $src --db $db --project-rules --format json --library-db none 2>$null | Out-String)
  $lr = @(); try { $lr = @($lo | ConvertFrom-Json) } catch { $lr = @() }
  Check 'E: lint <file> --project-rules: no doc-drift on Wrong' ((DriftAt $lr 11).Count -eq 0) $lo
  Check 'E: lint <file> --project-rules: Wrong2 still reports' ((DriftAt $lr 15).Count -ge 1) $lo

  $snap = [IO.File]::ReadAllText($src)
  $bl = & $Exe allow $src --fix-line 14 --fix-rule doc-drift --apply --db $db --library-db none 2>&1 | Out-String
  Check 'F: CONTROL a blank line is still refused (exit 1)' ($LASTEXITCODE -eq 1) $bl
  Check 'F: ... and the file is untouched' ([IO.File]::ReadAllText($src) -ceq $snap) ''
} finally {
  Pop-Location
}
Write-Host ("{0} PASS" -f $script:Passed)
if (-not $script:Failed -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
