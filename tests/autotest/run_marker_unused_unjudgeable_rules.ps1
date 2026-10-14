<#
  run_marker_unused_unjudgeable_rules.ps1 -- a file-scoped `lint` must not call
  a dl:ok marker unused when the marker's rule is one that run cannot evaluate.

  THE DEFECT (docs\INBOX-lint-file-duplicate-code-marker.md, 2026-10-14):
    `lint <file>` computes duplicate-code WITHIN the file only; the cross-file
    pair is a lint-all answer. A `dl:ok duplicate-code` on a cross-file pair is
    therefore never accounted by the per-file run, and ApplyLineMarkers reported
    it as review-marker-unused -- "remove it" -- while lint-all honoured it.
    Obeying the hint re-opened the finding in lint-all. Same shape for any rule
    the per-file run does not compute: a project rule (unused-public-symbol)
    when no index covers the file, doc-drift without --project-rules, ...

  CHECKS:
    1. KNOWN-FIRING: lint-all reports the cross-file duplicate-code pair, and
       the per-file run does NOT (so the scope difference is real, not assumed).
    2. With a hashed marker on the anchor: lint-all is silent (marker live) AND
       `lint <file> --db` reports no review-marker-unused on it.  <- the defect
    3. `lint <file>` with NO --db: a dl:ok unused-public-symbol marker is not
       reported unused (no index -> the rule never ran).
  POSITIVE CONTROLS:
    4. the per-file run still reports a file-scope marker (self-assignment) on
       an unrelated line as unused -- the reporter is alive in this scope;
    5. lint-all still reports a duplicate-code marker planted on an unrelated
       line as unused -- the rule IS judged where it can be.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-marker-unjudged-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$db  = Join-Path $WorkDir 'probe.sqlite'
$err = Join-Path $WorkDir 'stderr.txt'

# One routine body, long enough for duplicate-code (90 tokens), copied into two
# units under different routine names.
function UnitSource([string]$Name, [string]$Proc) {
  @(
    "unit $Name;"
    ''
    'interface'
    ''
    "procedure $Proc(var A, B, C: Integer);"
    ''
    'implementation'
    ''
    "procedure $Proc(var A, B, C: Integer);"
    'begin'
    '  A := B + C * 2 - 7;'
    '  B := A - C + 11 * B;'
    '  C := A * B - 13 + C;'
    '  if A > B then A := A - B else B := B - A;'
    '  if B > C then B := B - C else C := C - B;'
    '  if C > A then C := C - A else A := A - C;'
    '  A := A + B + C + 17;'
    '  B := B * 3 + A - C;'
    '  C := C * 5 + B - A;'
    '  if A + B > C * 2 then C := A + B else A := C - B;'
    'end;'
    ''
    'end.'
  ) -join "`r`n"
}
$pasA = Join-Path $WorkDir 'uDupA.pas'
$pasB = Join-Path $WorkDir 'uDupB.pas'
[IO.File]::WriteAllText($pasA, (UnitSource 'uDupA' 'StepA') + "`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($pasB, (UnitSource 'uDupB' 'StepB') + "`r`n", [Text.Encoding]::ASCII)

& $Exe index $WorkDir --db $db *> $null
Check 'fixture indexed' ($LASTEXITCODE -eq 0) ''

function LintAll { ((& $Exe lint-all --db $db 2>$err | Out-String) -replace "`r`n", "`n") }
function LintFile([string]$P, [switch]$NoDb) {
  $o = if ($NoDb) { & $Exe lint $P 2>$err } else { & $Exe lint $P --db $db 2>$err }
  (($o | Out-String) -replace "`r`n", "`n")
}
function Relevant([string]$Out) { (($Out -split "`n" | Where-Object { $_ -match 'review-marker|duplicate-code:|self-assignment:|unused-public-symbol:' }) -join ' || ') }

Write-Host ''
Write-Host '-- 1. KNOWN-FIRING: the cross-file pair is a lint-all answer only' -ForegroundColor Cyan
$all = LintAll
$dupLine = ($all -split "`n" | Where-Object { $_ -match 'duplicate-code:' } | Select-Object -First 1)
Check 'lint-all reports duplicate-code' ([bool]$dupLine) $dupLine
if (-not $dupLine) { Write-Host 'run_marker_unused_unjudgeable_rules: FAIL (no pair to mark)' -ForegroundColor Red; exit 1 }
$m = [regex]::Match($dupLine, '^(.*\.pas):(\d+):')
$anchorFile = $m.Groups[1].Value
$anchorLine = [int]$m.Groups[2].Value
$r = LintFile $anchorFile
Check 'per-file lint does NOT report the cross-file pair' (-not ($r -match 'duplicate-code:')) (Relevant $r)

Write-Host ''
Write-Host '-- 2. a hashed marker on the anchor: live for lint-all, NOT unused per file' -ForegroundColor Cyan
$lines = [IO.File]::ReadAllLines($anchorFile)
$lines[$anchorLine - 1] += '  // dl:ok duplicate-code -- REVIEWED 2026-10-14: fixture pair'
[IO.File]::WriteAllLines($anchorFile, $lines, [Text.Encoding]::ASCII)
$all = LintAll
$hm = [regex]::Match($all, 're-mark it as duplicate-code@([0-9a-f]{4})')
Check 'lint-all names the hash for the hashless marker' $hm.Success (Relevant $all)
$lines = [IO.File]::ReadAllLines($anchorFile)
$lines[$anchorLine - 1] = $lines[$anchorLine - 1].Replace('dl:ok duplicate-code --', "dl:ok duplicate-code@$($hm.Groups[1].Value) --")
[IO.File]::WriteAllLines($anchorFile, $lines, [Text.Encoding]::ASCII)
$all = LintAll
Check 'lint-all: duplicate-code suppressed'           (-not ($all -match 'duplicate-code:')) (Relevant $all)
Check 'lint-all: no review-marker-* on the marker'    (-not ($all -match "review-marker-(unused|stale)")) (Relevant $all)
$r = LintFile $anchorFile
Check "lint <file> --db: NO review-marker-unused on line $anchorLine" (-not ($r -match "review-marker-unused")) (Relevant $r)

Write-Host ''
Write-Host '-- 3. no index: a project-rule marker is not judged by the per-file run' -ForegroundColor Cyan
$lines = [IO.File]::ReadAllLines($pasA)
$lines[4] += '  // dl:ok unused-public-symbol -- REVIEWED 2026-10-14: fixture'
[IO.File]::WriteAllLines($pasA, $lines, [Text.Encoding]::ASCII)
$r = LintFile $pasA -NoDb
Check 'lint <file> (no --db): NO review-marker-unused for unused-public-symbol' (-not ($r -match 'uDupA\.pas:5:.*review-marker-unused')) (Relevant $r)

Write-Host ''
Write-Host '-- 4. POSITIVE CONTROL: a file-scope marker on an unrelated line IS unused per file' -ForegroundColor Cyan
$lines = [IO.File]::ReadAllLines($pasA)
$lines[2] += '  // dl:ok self-assignment -- planted on an unrelated line'
[IO.File]::WriteAllLines($pasA, $lines, [Text.Encoding]::ASCII)
$r = LintFile $pasA
Check 'review-marker-unused fires on uDupA.pas:3' ($r -match 'uDupA\.pas:3:.*review-marker-unused') (Relevant $r)

Write-Host ''
Write-Host '-- 5. POSITIVE CONTROL: lint-all still judges duplicate-code markers' -ForegroundColor Cyan
$lines = [IO.File]::ReadAllLines($pasB)
$lines[0] += '  // dl:ok duplicate-code -- planted on an unrelated line'
[IO.File]::WriteAllLines($pasB, $lines, [Text.Encoding]::ASCII)
$all = LintAll
Check 'lint-all reports the planted duplicate-code marker unused' ($all -match 'uDupB\.pas:1:.*review-marker-unused') (Relevant $all)

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'run_marker_unused_unjudgeable_rules: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_marker_unused_unjudgeable_rules: PASS' -ForegroundColor Green
exit 0
