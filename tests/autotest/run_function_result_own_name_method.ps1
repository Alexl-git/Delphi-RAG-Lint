<#
  run_function_result_own_name_method.ps1 -- `function-result-not-set` must
  accept a METHOD assigning its own name (`Bar := 1` inside TFoo.Bar) as
  setting Result, exactly as it already does for a free function.

  THE BUG (D21, 2026-09-24)
  -------------------------
  DRagLint.Analysis.Flow.Lattices BuildVarTable aliases the routine's own name
  to the `result` slot using the header's `name` field. The grammar's
  declProc.name is identifier | genericDot | genericTpl, so for
  `function TFoo.Bar: Integer;` the alias was registered as `tfoo.bar` and the
  body's `Bar := 1` looked up `bar` -- not a variable -- so Result was never
  must-assigned and the rule warned on a correct method. The free-function
  form worked because its name is a bare identifier.

  Cases (each routine owns the lines from its header to the next header)
    1. TFoo.Bar assigns `Bar := 1`            MUST NOT fire (red before the fix)
    2. TFoo.Baz never assigns                 MUST fire     (positive control)
    3. TBox<T>.Get assigns `Get := Default(T)` MUST NOT fire (generic owner)
    4. free F assigns `F := 1`                MUST NOT fire (existing alias)
  Asserted on `lint --json` (a bare array), filtered by `rule` and bucketed by
  `start_line` into the routine spans.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fres-own-name-$PID"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
try {
  $fixture = Join-Path $WorkDir 'OwnNameMethod.pas'
  $body = @"
unit OwnNameMethod;

interface

type
  TFoo = class
    function Bar: Integer;
    function Baz: Integer;
  end;

  TBox<T> = class
    function Get: T;
  end;

function F: Integer;

implementation

function TFoo.Bar: Integer;
begin
  Bar := 1;
end;

function TFoo.Baz: Integer;
begin
  Writeln('none');
end;

function TBox<T>.Get: T;
begin
  Get := Default(T);
end;

function F: Integer;
begin
  F := 1;
end;

end.
"@
  $norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

  # Resolve routine spans from the fixture, so edits cannot decouple them.
  $lines = [System.IO.File]::ReadAllLines($fixture)
  function LineOf([string]$Needle) {
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
    return -1
  }
  $lnBar = LineOf 'function TFoo.Bar: Integer;'
  $lnBaz = LineOf 'function TFoo.Baz: Integer;'
  $lnGet = LineOf 'function TBox<T>.Get: T;'
  # The interface also declares `function F: Integer;`; the implementation one is the LAST.
  $lnF = -1
  for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i].Trim() -eq 'function F: Integer;') { $lnF = $i + 1; break } }
  $lnEnd = $lines.Count
  Check 'all four routine headers located' (@($lnBar, $lnBaz, $lnGet, $lnF) -notcontains -1)
  $spans = [ordered]@{
    'TFoo.Bar'    = @($lnBar, ($lnBaz - 1))
    'TFoo.Baz'    = @($lnBaz, ($lnGet - 1))
    'TBox<T>.Get' = @($lnGet, ($lnF - 1))
    'F'           = @($lnF, $lnEnd)
  }

  $raw = (& $Exe lint $fixture --rule function-result-not-set --json 2>$null) -join "`n"
  $all = if ($raw.Trim()) { @($raw | ConvertFrom-Json) } else { @() }
  $hits = @($all | Where-Object { $_.rule -eq 'function-result-not-set' })
  Write-Host ("  function-result-not-set fired on lines: {0}" -f (($hits | ForEach-Object { $_.start_line }) -join ', ')) -ForegroundColor DarkGray
  function CountIn([string]$Routine) {
    $sp = $spans[$Routine]
    return @($hits | Where-Object { [int]$_.start_line -ge $sp[0] -and [int]$_.start_line -le $sp[1] }).Count
  }

  Write-Host ''
  Write-Host 'Positive control' -ForegroundColor Cyan
  Check 'TFoo.Baz never assigns Result -> fires' ((CountIn 'TFoo.Baz') -ge 1)
  Check 'every finding carries a start_line (shape check)' (
    @($hits | Where-Object { $null -eq $_.start_line }).Count -eq 0)

  Write-Host ''
  Write-Host 'Own-name assignment sets Result -> MUST NOT fire' -ForegroundColor Cyan
  Check 'TFoo.Bar: Bar := 1' ((CountIn 'TFoo.Bar') -eq 0)
  Check 'TBox<T>.Get: Get := Default(T)' ((CountIn 'TBox<T>.Get') -eq 0)
  Check 'free F: F := 1 (existing alias)' ((CountIn 'F') -eq 0)
}
finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
