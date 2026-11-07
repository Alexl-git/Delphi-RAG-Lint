<#
  run_lint_stale_note.ps1 -- E-BIND-STALE-NOTE

  The calls pass clears every edge and WITHHOLDS the re-write for a file whose
  source no longer matches the index, so that file ends with NO call edges until
  a reindex. The effect and caller rules then read a hole. lint-all says so:
    lint-all: N file(s) have no call edges (stale index): reindex before trusting effect / caller rules

  A  fresh DB: edges exist, no note.
  B  touched, no resolve pass yet: edges still there, so the claim would be FALSE: no note.
  C  touched + --resolve-only: A.pas lost its edges (raw sql proves it): note with N=1.
     C.pas is touched too but makes no call: it is not counted.
  D  full reindex: edges back, note gone.
  E  --json: the note is on stderr, stdout still parses.
  POSITIVE CONTROL: C fails on an engine without the note (RED on 1.44.1).

  Usage: pwsh -File tests\autotest\run_lint_stale_note.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lint-stale-note-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function W([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = "$WorkDir\src"
New-Item -ItemType Directory -Force $src | Out-Null
W "$src\UB.pas" "unit UB;`n`ninterface`n`nprocedure Work;`n`nimplementation`n`nprocedure Work;`nbegin`nend;`n`nend.`n"
W "$src\UA.pas" "unit UA;`n`ninterface`n`nprocedure Run;`n`nimplementation`n`nuses`n  UB;`n`nprocedure Run;`nbegin`n  Work;`nend;`n`nend.`n"
W "$src\UC.pas" "unit UC;`n`ninterface`n`nconst`n  K = 1;`n`nimplementation`n`nend.`n"
$db = "$WorkDir\t.sqlite"
Push-Location $WorkDir
try {
  function Note([string[]]$Extra = @()) { (& $Exe lint-all --db $db --output "$WorkDir\rep.txt" @Extra 2>&1 | Out-String) }
  function Edges { $j = & $Exe sql --db $db --query 'select count(*) as n from call_edges' --json 2>$null | Out-String | ConvertFrom-Json; [int]$j.rows[0][0] }
  $phrase = 'have no call edges (stale index)'
  & $Exe index $src --db $db 2>&1 | Out-Null
  $e0 = Edges
  Check 'A0 fixture: the fresh index has a call edge' ($e0 -ge 1) "edges=$e0"
  $o = Note
  Check 'A1 fresh DB: lint-all ran' ($o -match 'scanning') $o
  Check 'A2 fresh DB: no note' (-not $o.Contains($phrase)) $o

  $later = (Get-Date).AddMinutes(5)
  [IO.File]::SetLastWriteTime("$src\UA.pas", $later)
  [IO.File]::SetLastWriteTime("$src\UC.pas", $later)
  $o = Note
  Check 'B1 touched, edges intact' ((Edges) -ge 1) ''
  Check 'B2 touched, edges intact: no false note' (-not $o.Contains($phrase)) $o

  & $Exe index $src --resolve-only --db $db 2>&1 | Out-Null
  Check 'C0 the resolve pass withheld the stale file: 0 edges' ((Edges) -eq 0) "edges=$(Edges)"
  $o = Note
  Check 'C1 the note names exactly one file (UC.pas makes no call)' ($o.Contains("lint-all: 1 file(s) $phrase")) $o
  Check 'C2 the note says what to do' ($o -match 'reindex before trusting effect / caller rules') $o

  $errF = "$WorkDir\err.txt"
  $out = & $Exe lint-all --db $db --json --output "$WorkDir\rep.json" 2>$errF | Out-String
  Check 'E1 --json: the note is on stderr' ((Get-Content $errF -Raw).Contains($phrase)) ''
  Check 'E2 --json: stdout carries no note' (-not $out.Contains($phrase)) $out

  & $Exe index $src --db $db 2>&1 | Out-Null
  $o = Note
  Check 'D1 reindex: edges are back' ((Edges) -ge 1) "edges=$(Edges)"
  Check 'D2 reindex: the note is gone' (-not $o.Contains($phrase)) $o
} finally { Pop-Location }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'run_lint_stale_note: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_stale_note: PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
