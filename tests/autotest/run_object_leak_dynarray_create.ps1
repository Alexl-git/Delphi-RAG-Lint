<#
  run_object_leak_dynarray_create.ps1 -- `TArray<T>.Create(...)` is the dynamic-array
  constructor intrinsic, not an object construction: object-leak must stay silent.

  B-08 (INBOX-object-leak-dynamic-array-create). ExprIsConstructor matched PURELY on
  the member text `create`, so `var Labels:= TArray<string>.Create('a', 'b')` was a
  leak candidate; when Labels was only READ (string concatenation, never passed to a
  call) nothing marked it transferred and it was reported "may be leaked".

  The fix NARROWS the constructor test, and a narrowed test that matches nothing is
  indistinguishable from a fixed rule. So a genuine leak of a GENERIC CLASS
  (`TList<Integer>.Create`, the same `Name<T>.Create` shape) and of a plain class
  must STILL fire.

    InlineLabels   var L:= TArray<string>.Create(..); read only     -> SILENT
    TypedDynArr    L: TArray<Integer>; L:= TArray<Integer>.Create   -> SILENT
    QualDynArr     L:= System.TArray<string>.Create(..)             -> SILENT
    GenericLeak    L:= TList<Integer>.Create; never freed           -> MUST FIRE
    TrueLeak       Obj:= TStringList.Create; never freed            -> MUST FIRE

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_dynarr_$PID"
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'dynarr.pas'

$body = @'
unit dynarr;

interface

implementation

uses
  System.Classes, System.SysUtils, System.Generics.Collections;

function InlineLabels(I: Integer; out pWhy: string): Boolean;
begin
  var Labels:= TArray<string>.Create('explicit path', 'environment variable ' + 'X');
  pWhy:= Labels[I] + ': (not found)';
  Result:= False;
end;

function TypedDynArr: Integer;
var
  L: TArray<Integer>;
begin
  L:= TArray<Integer>.Create(1, 2);
  Result:= L[0] + L[1];
end;

function QualDynArr: string;
var
  L: TArray<string>;
begin
  L:= System.TArray<string>.Create('a');
  Result:= L[0];
end;

function GenericLeak: Integer;
var
  L: TList<Integer>;
begin
  L:= TList<Integer>.Create;
  L.Add(1);
  Result:= L.Count;
end;

procedure TrueLeak;
var
  Obj: TStringList;
begin
  Obj:= TStringList.Create;
  Obj.Add('x');
end;

end.
'@
[System.IO.File]::WriteAllText($target, (($body -replace "`r`n","`n") -replace "`n","`r`n"),
  (New-Object System.Text.UTF8Encoding($false)))

Push-Location C:\TEMP
try {
  $out = & $exePath lint $target 2>&1 | Out-String
  $leaks = @(($out -split "`r?`n") | Where-Object { $_ -match 'object-leak' })
  Check 'SANITY: the linter ran and produced output' ($out.Trim().Length -gt 0) $out

  $srcLines = [System.IO.File]::ReadAllLines($target)
  function LineOf($pat) { for ($i = 0; $i -lt $srcLines.Count; $i++) { if ($srcLines[$i] -match $pat) { return ($i + 1) } }; return -1 }
  function LeakAtLine($ln) { return (@($leaks | Where-Object { $_ -match ":$ln`:" }).Count -gt 0) }

  Check 'POSITIVE CONTROL: TrueLeak (TStringList.Create, never freed) still fires' `
        (LeakAtLine (LineOf 'Obj:= TStringList\.Create')) ($leaks -join "`n")
  Check 'POSITIVE CONTROL: GenericLeak (TList<Integer>.Create, never freed) still fires' `
        (LeakAtLine (LineOf 'L:= TList<Integer>\.Create')) ($leaks -join "`n")
  Check 'B-08: inline `var Labels:= TArray<string>.Create(..)` is not a leak' `
        (-not (LeakAtLine (LineOf 'var Labels:= TArray'))) ($leaks -join "`n")
  Check 'B-08: typed `L:= TArray<Integer>.Create(..)` is not a leak' `
        (-not (LeakAtLine (LineOf 'L:= TArray<Integer>\.Create'))) ($leaks -join "`n")
  Check 'B-08: qualified `System.TArray<string>.Create(..)` is not a leak' `
        (-not (LeakAtLine (LineOf 'L:= System\.TArray<string>\.Create'))) ($leaks -join "`n")
  Check 'exactly the 2 true leaks are reported' ($leaks.Count -eq 2) ($leaks -join "`n")
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_dynarr_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
