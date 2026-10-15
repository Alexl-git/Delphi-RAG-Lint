<#
  run_typemap_inline_vars.ps1 -- type-aware rules must not lend an inline
  variable the type of a same-named variable of ANOTHER routine (Gitea
  drag-lint#5).

  THE DEFECT. CheckTypeAware's TypeMap is flat and file-scoped and only saw
  section declarations (declVar/declArg/declField). An inline `for var JP in`
  or `var JP := ...` was invisible, so JP took the type of `JP: TJSONObject`
  declared in another routine, and redundant-cast reported
  "Redundant cast: JP is already of type TJSONObject" four times in
  DRagLint.CLI.pas -- `lint --fix --apply` would have deleted casts the
  compiler needs. Inline declarations now enter the map: typed ones like a
  section declaration, untyped ones as the ambiguity sentinel, so every rule
  reading the map fails safe on that name.

  WHAT THIS ASSERTS (lint without --db, rule redundant-cast)
    1. for var JP in ... TJSONObject(JP) in B: no finding            <- THE FIX
    2. var JP := ... TJSONObject(JP) in C: no finding                <- THE FIX
    3. var JP: TJSONValue := ... TJSONObject(JP) in E: no finding    <- THE FIX
    4. CONTROL: TJSONObject(O) with O: TJSONObject (a parameter, no name clash)
       is still reported

  RED-CHECK: against the pre-fix build 1, 2 and 3 FAIL; 4 passes on both.
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

$work = Join-Path C:\TEMP "draglint_typemap_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

# Line numbers matter: B's cast is on 26, C's on 32, E's on 38, D's on 43.
$unit = Join-Path $work 'Fix5c.pas'
Write-Ascii $unit @'
unit Fix5c;

interface

uses
  System.JSON;

procedure A(AObj: TJSONObject);
procedure B(AArr: TJSONValue);
procedure C(AObj: TJSONObject);
procedure E(AObj: TJSONObject);
function D(O: TJSONObject): Integer;

implementation

procedure A(AObj: TJSONObject);
var
  JP: TJSONObject;
begin
  JP := AObj;
  Writeln(JP.Count);
end;

procedure B(AArr: TJSONValue);
begin
  for var JP in TJSONArray(AArr) do Writeln(TJSONObject(JP).Count);
end;

procedure C(AObj: TJSONObject);
begin
  var JP := AObj.GetValue('x');
  Writeln(TJSONObject(JP).Count);
end;

procedure E(AObj: TJSONObject);
begin
  var JP: TJSONValue := AObj.GetValue('x');
  Writeln(TJSONObject(JP).Count);
end;

function D(O: TJSONObject): Integer;
begin
  Result := TJSONObject(O).Count;
end;

end.
'@
$out = (& $Exe lint $unit --rule redundant-cast 2>$null) -join "`n"
Write-Host $out -ForegroundColor DarkGray
$hits = @($out -split "`n" | Where-Object { $_ -match 'redundant-cast' })
function At([int]$line) { return ,@($hits | Where-Object { $_ -match ":${line}:" }) }

Check '1. for var JP in (B): no redundant-cast' ((At 26).Count -eq 0) ((At 26) -join ' | ')
Check '2. var JP := (C): no redundant-cast' ((At 32).Count -eq 0) ((At 32) -join ' | ')
Check '3. var JP: TJSONValue := (E): no redundant-cast' ((At 38).Count -eq 0) ((At 38) -join ' | ')
Check '4. CONTROL: TJSONObject(O) on a TJSONObject parameter is still reported' ((At 43).Count -ge 1) $out

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_typemap_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
