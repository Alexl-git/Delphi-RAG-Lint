<#
  run_flow_inline_vardef_not_a_read.ps1 -- an inline `var X: T;` declares X;
  it must not be counted as a READ of X (Gitea drag-lint#4).

  THE DEFECT. CollectReadsAndCallDefs (Flow.Lattices.pas) walked the varDef
  node generically, so its identifier counted as a read. The var table keeps
  one slot per NAME, so as soon as the routine had another inline X it knows
  (`for var X in`, `for var X :=`, `var X := e`), the declaration line of the
  `var X: T;` was reported "used before it is assigned" -- [error] when X is
  then assigned directly, [warning] when it is assigned through an out
  argument. dcc32 (Delphi 13) compiles every case below without W1036. Found on
  DRagLint.CLI.pas DoIndexRepo: `var P: TRepoProject;` + `for var P in Todo`.

  WHAT THIS ASSERTS (lint without --db, rule used-before-assignment)
    1. var P: T + out argument + `for var P in`            -> 0 findings  <- THE FIX
    2. var I: Integer; I := N  + `for var I :=`             -> 0           <- THE FIX
    3. var S: string; S := ... + `for var S in`             -> 0           <- THE FIX
    4. var I: Integer; I := N  + `var I := N * 2` (blocks)  -> 0           <- THE FIX
    5. CONTROL: a section-var read before assignment on one path still fires
       on its read line (the rule is not switched off)
    6. CONTROL: an inline `var X := Y` whose initialiser READS an unassigned
       local Y still fires for Y (the initialiser is still walked)

  RED-CHECK: against the pre-fix build 1-4 FAIL; 5 and 6 pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

$work = Join-Path C:\TEMP "draglint_vardef_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

function Ubas([string]$name, [string]$body) {
  $p = Join-Path $work "$name.pas"
  Write-Ascii $p $body
  $out = (& $Exe lint $p --enable used-before-assignment 2>$null) -join "`n"
  return @{ Out = $out; Hits = @($out -split "`n" | Where-Object { $_ -match 'used-before-assignment' }) }
}

$r1 = Ubas 'Fx4' @'
unit Fx4;

interface

type
  TProj = record
    Name: string;
  end;
  TCfg = record
    Items: TArray<TProj>;
    function FindByName(const AName: string; out AProject: TProj): Boolean;
  end;

function Run(const ACfg: TCfg; const Names: TArray<string>): Integer;

implementation

function TCfg.FindByName(const AName: string; out AProject: TProj): Boolean;
begin
  AProject := Default(TProj);
  Result := AName <> '';
end;

function Run(const ACfg: TCfg; const Names: TArray<string>): Integer;
var
  Todo: TArray<TProj>;
begin
  Result := 0;
  for var N in Names do
  begin
    var P: TProj;
    if not ACfg.FindByName(N, P) then Exit(2);
    Todo := Todo + [P];
  end;
  for var P in Todo do
    Inc(Result, Length(P.Name));
end;

end.
'@
Check '1. var P + out arg + for var P in: no finding' ($r1.Hits.Count -eq 0) ($r1.Hits -join ' | ')

$r2 = Ubas 'Fx10' @'
unit Fx10;

interface

function Run(N: Integer): Integer;

implementation

function Run(N: Integer): Integer;
begin
  begin
    var I: Integer;
    I := N;
    Result := I;
  end;
  for var I := 0 to N do
    Result := Result + I;
end;

end.
'@
Check '2. var I + for var I :=: no finding' ($r2.Hits.Count -eq 0) ($r2.Hits -join ' | ')

$r3 = Ubas 'Fx11' @'
unit Fx11;

interface

function Run(const L: TArray<string>): string;

implementation

function Run(const L: TArray<string>): string;
begin
  begin
    var S: string;
    S := 'x';
    Result := S;
  end;
  for var S in L do
    Result := Result + S;
end;

end.
'@
Check '3. var S + for var S in: no finding' ($r3.Hits.Count -eq 0) ($r3.Hits -join ' | ')

$r4 = Ubas 'Fx13' @'
unit Fx13;

interface

function A(const N: Integer): Integer;

implementation

function A(const N: Integer): Integer;
begin
  begin
    var I: Integer;
    I := N;
    Result := I;
  end;
  begin
    var I := N * 2;
    Result := Result + I;
  end;
end;

end.
'@
Check '4. var I + var I := e in another block: no finding' ($r4.Hits.Count -eq 0) ($r4.Hits -join ' | ')

$r5 = Ubas 'FxCtl' @'
unit FxCtl;

interface

function C(const N: Integer): Integer;

implementation

function C(const N: Integer): Integer;
var
  I: Integer;
begin
  if N > 0 then
    I := N;
  Result := I;
end;

end.
'@
Check '5. CONTROL: a section var read on an unassigned path still fires on line 15' `
  (@($r5.Hits | Where-Object { $_ -match ':15:' }).Count -ge 1) ($r5.Out)

$r6 = Ubas 'FxInit' @'
unit FxInit;

interface

function D(const N: Integer): Integer;

implementation

function D(const N: Integer): Integer;
var
  Y: Integer;
begin
  if N > 0 then
    Y := N;
  var X := Y;
  Result := X;
end;

end.
'@
Check '6. CONTROL: an inline initialiser that reads an unassigned local still fires for it' `
  (@($r6.Hits | Where-Object { $_ -match '"y"' }).Count -ge 1) ($r6.Out)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_vardef_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
