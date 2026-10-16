<#
  run_resolver_file_cache_bound.ps1 -- the call resolver's per-file caches are
  BOUNDED (#23, 2026-10-15) and the bound changes no edge.

  WHY. LoadFileRows kept every symbol row, and LinesOf the source text, of every
  file a whole-DB pass touched, until the end of the pass: +9% peak memory on
  ProjectA, about +1 GB extrapolated to a 2.24 M-symbol library index. Now the
  pass drops the oldest files beyond a cap (TrimFileCaches, between two refs).
  A dropped file is read again on its next ref, so the database must come out
  IDENTICAL whatever the cap.

  Checks:
    F1  with DRAGLINT_RESOLVER_FILE_CACHE=2 the calls stage reports its file
        cache (DRAGLINT_PROFILE): files were dropped, and never more than 3 held --
        the cap, plus the file of the ref being resolved, read before the trim
    F2  the same project indexed with cap 2 and with cap 10000 gives IDENTICAL
        databases (tools\measure\index_db_diff.py)
    F3  CONTROL: the fixture really makes cross-file calls (find-callers finds them)

  Needs python on PATH for F2 (SKIP 77 otherwise). Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_file_cache_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$diffPy  = (Resolve-Path "$PSScriptRoot\..\..\tools\measure\index_db_diff.py").Path
$python  = Get-Command python -ErrorAction SilentlyContinue
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory -Path $proj -Force | Out-Null

# Six units in a chain, each calling the next one's routine and a method of a
# class declared one unit further: every file's refs need other files' rows.
$names = @('uA', 'uB', 'uC', 'uD', 'uE', 'uF')
for ($i = 0; $i -lt $names.Count; $i++) {
  $u = $names[$i]
  $next = if ($i + 1 -lt $names.Count) { $names[$i + 1] } else { '' }
  $uses = if ($next) { "uses`r`n  $next;`r`n" } else { '' }
  $body = if ($next) { "  Result:= Go$next + T$next.Create.Twice(1);" } else { "  Result:= 1;" }
  Write-Ascii (Join-Path $proj "$u.pas") @"
unit $u;

interface

$uses
type
  T$u = class
  public
    function Twice(pN: Integer): Integer;
  end;

function Go${u}: Integer;

implementation

function T$u.Twice(pN: Integer): Integer;
begin
  Result:= pN * 2;
end;

function Go${u}: Integer;
begin
$body
end;

end.
"@
}
Write-Ascii (Join-Path $proj 'Chain.dpr') @"
program Chain;

uses
  $(($names | ForEach-Object { $_ }) -join ', ');

begin
  GouA;
end.
"@
$dpr = Join-Path $proj 'Chain.dpr'

function IndexWithCap([string]$Cap, [string]$Db) {
  $env:DRAGLINT_RESOLVER_FILE_CACHE = $Cap
  $env:DRAGLINT_PROFILE = '1'
  $env:DRAGLINT_RULE_CACHE = '0'
  try { $o = & $exePath index --project $dpr --db $Db 2>&1 | Out-String }
  finally { $env:DRAGLINT_RESOLVER_FILE_CACHE = $null; $env:DRAGLINT_PROFILE = $null; $env:DRAGLINT_RULE_CACHE = $null }
  [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}

$dbSmall = Join-Path $WorkDir 'cap2.sqlite'
$dbLarge = Join-Path $WorkDir 'cap10000.sqlite'
$small = IndexWithCap '2' $dbSmall
$large = IndexWithCap '10000' $dbLarge
Check 'SANITY: both indexes built' (($small.Code -eq 0) -and ($large.Code -eq 0)) ($small.Out + $large.Out)

# --- F1 ---------------------------------------------------------------------------
$line = (($small.Out -split "`n") | Where-Object { $_ -match 'file cache: cap' } | Select-Object -First 1)
$ok1 = $false
if ($line -match 'cap (\d+) file\(s\), (\d+) read\(s\), (\d+) dropped, peak (\d+)') {
  $ok1 = ([int]$Matches[1] -eq 2) -and ([int]$Matches[3] -gt 0) -and ([int]$Matches[4] -le 3)
}
Check 'F1 cap 2: files were dropped and never more than cap + 1 held' $ok1 "line: $line"

# --- F3 control ------------------------------------------------------------------------
$callers = & $exePath query find-callers --name Twice --db $dbSmall 2>&1 | Out-String
Check 'F3 CONTROL: cross-file method calls are resolved (find-callers Twice)' ($callers -match 'uA\.pas' -and $callers -match 'uE\.pas') $callers

# --- F2 --------------------------------------------------------------------------------
if (-not $python) {
  Write-Host 'SKIP: python not on PATH -- F2 (index_db_diff) not run' -ForegroundColor Yellow
  if (-not $fail) { exit 77 }
} else {
  $diff = & $python.Source -I $diffPy $dbSmall $dbLarge 2>&1 | Out-String
  Check 'F2 cap 2 and cap 10000 give IDENTICAL databases' ($diff -match 'IDENTICAL' -and $diff -notmatch 'DIFFER') $diff
}
}
finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
