<#
  run_closure_cache.ps1 -- `index --project` keeps what the compile-closure walk
  read out of each unit (closure_cache), reuses it while the unit's stamp and the
  define profile match, and reads a unit again when it changes (2026-10-14).

  WHY THIS EXISTS. The closure walk read and preprocessed every unit of the
  project on every run to learn uses clauses that almost never change: ~3 s of
  each incremental index of the 2,222-file TestCopy ProjectA project, 1.3 s
  with the cache (the stat of each unit stays). A cache that answers from a
  stale row is worse than none -- the closure, and with it the whole index,
  would silently miss a unit -- so the edit case below is the point.

  Checks:
    1. the first run records one row per unit it read, under the profile's
       fingerprint (RED on the exe before the change: there is no table);
    2. a second run lists the same closure (the cached path agrees with the
       cold one), and so does a run with DRAGLINT_NO_CLOSURE_CACHE=1;
    3. editing a unit's uses clause brings the newly used unit into the index
       on the next run -- the changed stamp invalidates that unit's row;
    4. a cache recorded under another fingerprint is not used: the run
       rewrites the fingerprint and the rows.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_closure_cache_$PID"
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$proj = Join-Path $scratch 'proj'
New-Item -ItemType Directory -Path $proj | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $proj 'App.dpr') @'
program App;

uses
  UA in 'UA.pas';

begin
  UA.Go;
end.
'@
Write-Ascii (Join-Path $proj 'App.dproj') @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>App.dpr</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
        <Config Condition="'$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="App.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <DCCReference Include="UA.pas"/>
    </ItemGroup>
</Project>
'@
function Write-UA([string]$Uses) {
  Write-Ascii (Join-Path $proj 'UA.pas') @"
unit UA;

interface

uses
  $Uses;

procedure Go;

implementation

procedure Go;
begin
end;

end.
"@
}
Write-UA 'UB'
foreach ($n in 'UB', 'UC') {
Write-Ascii (Join-Path $proj "$n.pas") @"
unit $n;

interface

procedure Help$n;

implementation

procedure Help$n;
begin
end;

end.
"@
}

$py = @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[2])
if sys.argv[1] == 'state':
    rows = c.execute('SELECT path FROM closure_cache ORDER BY path').fetchall()
    fp = c.execute("SELECT value FROM schema_meta WHERE key = 'closure_cache_fp'").fetchone()
    print('ROWS=%d' % len(rows))
    print('FP=%s' % (fp[0] if fp else ''))
    for r in rows: print('ROW=' + r[0].rsplit(chr(92), 1)[-1])
elif sys.argv[1] == 'files':
    for r in c.execute('SELECT path FROM files ORDER BY path'): print('FILE=' + r[0].rsplit(chr(92), 1)[-1])
elif sys.argv[1] == 'stale':
    c.execute("UPDATE schema_meta SET value = 'stale' WHERE key = 'closure_cache_fp'"); c.commit()
'@
$pyf = Join-Path $scratch 'q.py'
Write-Ascii $pyf $py
function Q([string]$What, [string]$Db) { return (& python $pyf $What $Db 2>&1 | Out-String) }

$dproj = Join-Path $proj 'App.dproj'
$db    = Join-Path $scratch 'app.sqlite'
function Listing([string]$NoCache) {
  Remove-Item Env:\DRAGLINT_NO_CLOSURE_CACHE -ErrorAction SilentlyContinue
  if ($NoCache) { $env:DRAGLINT_NO_CLOSURE_CACHE = '1' }
  try {
    $out = & $exePath index --project $dproj --db $db --platform Win64 --dry-run 2>&1 | Out-String
    return (($out -split "`r?`n" | Where-Object { $_ -match '\.(pas|dpr|dproj)\s*$' } | ForEach-Object { $_.Trim() }) -join "`n")
  } finally { Remove-Item Env:\DRAGLINT_NO_CLOSURE_CACHE -ErrorAction SilentlyContinue }
}

Push-Location C:\TEMP
try {
  & $exePath index --project $dproj --db $db --platform Win64 --quiet 2>&1 | Out-Null
  Check 'CONTROL: the first index --project exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $s1 = Q 'state' $db
  Check '1: the first run records a row for each unit it read, under a fingerprint' `
        (($s1 -match 'ROW=UA\.pas') -and ($s1 -match 'ROW=UB\.pas') -and ($s1 -match 'FP=\S+\|pp=')) $s1

  $warm = Listing ''
  $cold = Listing '1'
  Check '2: the cached walk lists the same closure as a cold one' (($warm -ne '') -and ($warm -ceq $cold)) "warm:`n$warm`ncold:`n$cold"
  Check 'CONTROL: UC is not in the closure yet' (-not ($warm -match 'UC\.pas')) $warm

  Start-Sleep -Milliseconds 1100   # a new write time even on a 1 s-resolution stamp
  Write-UA 'UB, UC'
  & $exePath index --project $dproj --db $db --platform Win64 --quiet 2>&1 | Out-Null
  $f3 = Q 'files' $db
  Check '3: a unit whose uses clause changed is read again -- UC joins the index' ($f3 -match 'FILE=UC\.pas') $f3

  Q 'stale' $db | Out-Null
  & $exePath index --project $dproj --db $db --platform Win64 --quiet 2>&1 | Out-Null
  $s4 = Q 'state' $db
  Check '4: a cache under another fingerprint is dropped and recorded again' `
        (($s4 -notmatch 'FP=stale') -and ($s4 -match 'ROW=UC\.pas') -and ($s4 -match 'ROW=UA\.pas')) $s4
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_closure_cache_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
