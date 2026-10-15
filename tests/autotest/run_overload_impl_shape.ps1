<#
  run_overload_impl_shape.ps1 -- an overload's implementation body is
  paired with ITS declaration when the two headers' texts differ.

  Delphi lets the declaration carry default values that the implementation
  header leaves out, and the implementation may wrap its parameter list over
  several lines. SetRoutineImplRange compared the two signature TEXTS exactly
  (the ADP1 Bug B fix), so for every such overload pair nothing matched and the
  name-order fallback swapped the bodies. Found on ProjectA: UConfig.SaveResult
  (TConfig overload) carried the TStringList body, so the recursive call inside
  that body had the wrong enclosing routine, could not type its argument, and
  was bound [ambiguous] to the wrong overload.

  Fixture: two free overloads and two method overloads, defaults in the
  declaration only, one implementation header wrapped, implementations in
  declaration order (the order the fallback gets wrong). The TObject body calls
  Save(aList, ...) -- its enclosing routine must be the TObject overload.
  (Which overload the call then BINDS to is the resolver's overload choice by a
  variable argument's declared type, checked where that choice is made.)

  RED on 1.21.1-alpha: impl ranges swapped, the call's enclosing routine the TA
  overload. Needs python on PATH for the direct DB read; SKIP without it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-overload-impl-shape-$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Python = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $Python) {
  Write-Host 'SKIP: python is not on PATH; this runner reads impl_start_line straight from the DB'
  exit 77
}
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uOvShape;

interface

type
  TA = class
  public
    function Calc(A, B: Integer; Scale: Integer = 1): Integer; overload;
    function Calc(const S: string; Trim: Boolean = True): Integer; overload;
  end;

procedure Save(aCfg: TA; const P, Q: string; aRep: Boolean = False); overload;
procedure Save(aList: TObject; P, Q: string; aRep: Boolean = False); overload;

implementation

function TA.Calc(A, B: Integer; Scale: Integer): Integer;
begin
  Result := (A + B) * Scale;
end;

function TA.Calc(const S: string;
  Trim: Boolean): Integer;
begin
  Result := Length(S);
end;

procedure Save(aCfg: TA; const P, Q: string; aRep: Boolean);
begin
  aCfg.Free;
end;

procedure Save(aList: TObject; P, Q: string;
  aRep: Boolean);
begin
  Save(aList, Q, P, aRep);
end;

end.
'@
$dir  = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file = Join-Path $dir 'uOvShape.pas'
$db   = Join-Path $dir 'fx.sqlite'
$norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

Push-Location $WorkDir
try {
  $indexOut = & $Exe index $dir --db $db 2>&1
  $indexExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut | Select-Object -Last 1)"

$chk = Join-Path $WorkDir 'check.py'
Set-Content -Path $chk -Encoding ascii -Value @'
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
for name, s, i, e in c.execute(
    "SELECT name, start_line, impl_start_line, impl_end_line FROM symbols "
    "WHERE name IN ('Calc', 'Save') ORDER BY start_line"):
    print("decl %s %d %d %d" % (name, s, i, e))
for line, conf, target, encl in c.execute(
    "SELECT r.start_line, e.confidence, t.start_line, s.start_line FROM call_edges e "
    "JOIN refs r ON r.id = e.ref_id JOIN symbols t ON t.id = e.target_symbol_id "
    "LEFT JOIN symbols s ON s.id = r.enclosing_symbol_id WHERE t.name = 'Save'"):
    print("edge %d %s %d %d" % (line, conf, target, encl))
c.close()
'@
$rows = & $Python -I $chk $db
Write-Host ("  DB: " + ($rows -join ' | ')) -ForegroundColor DarkGray

$impl = @{}
$edges = @()
foreach ($line in $rows) {
  if ($line -match '^decl (\w+) (\d+) (\d+) (\d+)$') { $impl["$($Matches[1])@$($Matches[2])"] = "$($Matches[3])-$($Matches[4])" }
  elseif ($line -match '^edge (\d+) (\w+) (\d+) (\d+)$') { $edges += [pscustomobject]@{ Line = [int]$Matches[1]; Conf = $Matches[2]; Target = [int]$Matches[3]; Encl = [int]$Matches[4] } }
}

Check 'Calc(A, B: Integer; Scale = 1) gets its own body 17-20' ($impl['Calc@8'] -eq '17-20') "got=$($impl['Calc@8'])"
Check 'Calc(const S; Trim = True) gets its own wrapped body 22-26' ($impl['Calc@9'] -eq '22-26') "got=$($impl['Calc@9'])"
Check 'Save(aCfg: TA; ...) gets its own body 28-31' ($impl['Save@12'] -eq '28-31') "got=$($impl['Save@12'])"
Check 'Save(aList: TObject; ...) gets its own wrapped body 33-37' ($impl['Save@13'] -eq '33-37') "got=$($impl['Save@13'])"

$call = $edges | Where-Object { $_.Line -eq 36 } | Select-Object -First 1
Check 'the call at line 36 has an edge' ($null -ne $call) "edges=$($rows -match '^edge' -join ' | ')"
if ($call) {
  Check 'its enclosing routine is the TObject overload (decl 13)' ($call.Encl -eq 13) "got=$($call.Encl)"
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
