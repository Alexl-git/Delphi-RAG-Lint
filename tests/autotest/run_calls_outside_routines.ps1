<#
  run_calls_outside_routines.ps1 -- a call with no routine around it (a
  program's begin..end. block, a unit's initialization) is a caller like any
  other (Gitea drag-lint#20, resolver 1.20.0-alpha).

  THE DEFECT, two halves.
    (a) TypeReceiver gave up when the ref had no enclosing routine, and the
        unit-level value set never held a .dpr's own var section (the program
        has no symbol, so its vars have no parent). `W.Run` in a program block,
        with `W: TWorker` declared in the program, formed NO edge.
    (b) A bare call there did form an edge, but callgraph, reverse-calltree,
        butterfly and impact follow callers BY ROUTINE and dropped every site
        without one -- the routine looked uncalled from the program.

  WHAT THIS ASSERTS
    1. W.Run in the program block binds: find-callers --resolved lists Fx.dpr  <- (a)
    2. callgraph --direction callers for Helper lists both outside sites
       (Fx.dpr and uW.pas initialization) as leaves                            <- (b)
    3. reverse-calltree json: a leaf node with the site's file and line        <- (b)
    4. impact on Helper: "plus 2 call site(s) outside any routine", json
       outside_routine = 2                                                     <- (b)
    5. CONTROL: a routine called only from another routine -- unchanged
       (one routine caller, no outside line)
    6. CONTROL: a bare call in the program block (no receiver) still binds

  RED-CHECK: against the pre-fix build 1, 2, 3 and 4 FAIL; 5 and 6 pass on both.
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
function Out([string[]]$ArgList) { return ((& $Exe @ArgList 2>$null) -join "`n") }

$work = Join-Path C:\TEMP "draglint_outside_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'uW.pas') @'
unit uW;

interface

type
  TWorker = class
  public
    procedure Run;
  end;

procedure Helper;
procedure OnlyFromRoutine;
procedure Caller;

implementation

procedure TWorker.Run;
begin
end;

procedure Helper;
begin
end;

procedure OnlyFromRoutine;
begin
end;

procedure Caller;
begin
  OnlyFromRoutine;
end;

initialization
  Helper;
end.
'@
Write-Ascii (Join-Path $dir 'Fx.dpr') @'
program Fx;

uses
  uW in 'uW.pas';

var
  W: TWorker;

begin
  W := TWorker.Create;
  W.Run;
  Helper;
end.
'@
$db = Join-Path $work 'f.sqlite'
& $Exe index --project (Join-Path $dir 'Fx.dpr') --db $db *> $null
Check 'seed: index' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

Write-Host ''
Write-Host '=== (a) W.Run in the program block ===' -ForegroundColor Cyan
$fc = Out @('query', 'find-callers', '--name', 'uW.TWorker.Run', '--db', $db, '--resolved')
Write-Host $fc -ForegroundColor DarkGray
Check '1. find-callers --resolved lists the program block call (Fx.dpr:11)' ($fc -match 'Fx\.dpr:11') ''

Write-Host ''
Write-Host '=== (b) callers outside any routine in the graph verbs ===' -ForegroundColor Cyan
$cg = Out @('callgraph', '--qname', 'uW.Helper', '--direction', 'callers', '--depth', '1', '--db', $db)
Write-Host $cg -ForegroundColor DarkGray
Check '2. callgraph lists both outside sites as leaves' `
  (($cg -match '\(outside any routine\) Fx\.dpr:12') -and ($cg -match '\(outside any routine\) uW\.pas:35')) ''
$rj = Out @('reverse-calltree', '--qname', 'uW.Helper', '--direction', 'callers', '--depth', '1', '--format', 'json', '--db', $db)
$tree = $null; try { $tree = $rj | ConvertFrom-Json } catch { }
$leaf = @(); if ($tree) { $leaf = @($tree.root.callers | Where-Object { $_.qname -like '(outside any routine) Fx.dpr:*' }) }
Check '3. reverse-calltree json has a leaf with the site file and line' `
  (($leaf.Count -eq 1) -and ($leaf[0].line -eq 12) -and ($leaf[0].file -like '*Fx.dpr')) "json=$rj"
$im = Out @('impact', '--qname', 'uW.Helper', '--depth', '2', '--db', $db)
$ij = Out @('impact', '--qname', 'uW.Helper', '--depth', '2', '--format', 'json', '--db', $db)
Write-Host $im -ForegroundColor DarkGray
Check '4. impact says 2 call sites outside any routine (text and json)' `
  (($im -match 'plus 2 call site\(s\) outside any routine') -and ($ij -match '"outside_routine":\s*2')) "json=$ij"

Write-Host ''
Write-Host '=== CONTROLS ===' -ForegroundColor Cyan
$c5 = Out @('impact', '--qname', 'uW.OnlyFromRoutine', '--depth', '2', '--db', $db)
$g5 = Out @('callgraph', '--qname', 'uW.OnlyFromRoutine', '--direction', 'callers', '--depth', '1', '--db', $db)
Check '5. CONTROL: routine-only caller unchanged' `
  (($c5 -match 'Total: 1 callers') -and -not ($c5 -match 'outside any routine') -and ($g5 -match 'uW\.Caller') -and -not ($g5 -match 'outside')) "impact=$c5"
$h6 = Out @('query', 'find-callers', '--name', 'uW.Helper', '--db', $db, '--resolved')
Check '6. CONTROL: the bare call in the program block still binds' ($h6 -match 'Fx\.dpr:12') ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_outside_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
