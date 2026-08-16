<#
  run_object_leak_padded_free.ps1 -- a COLUMN-ALIGNED `X  .Free;` still counts as
  freeing X.

  INBOX-rule-hardening-plan item 2. `FreedInFinallyBlock` matched the literal
  text `<name>.free`, so the aligned style used throughout this codebase --

      Rows        .Free;
      StemToFileId.Free;

  -- did not match for any name that got padding, and the object was reported as
  leaked despite being freed two lines away. The longest name in each aligned
  column is the one that happens to be unpadded, which is why the findings looked
  arbitrary rather than systematic.

  Measured: 9 object-leak findings on the self-index, 7 of them in
  DRagLint.Storage.SQLite.pas. Unpadding one `Rows  .Free;` by hand took that
  file from 7 to 6, removing exactly `rows`. After the fix the self-index reports
  0 object-leak findings.

  THE TRUE-LEAK CASE IS THE POINT OF THIS SUITE. The fix WIDENS a suppression,
  and a suppression that swallows everything is indistinguishable from a fixed
  rule -- "9 findings became 0" is exactly what deleting the rule would also
  produce. So this asserts a genuine leak STILL fires, and that a finally block
  which frees a DIFFERENT (padded) variable does not launder the unfreed one.

    PaddedFree   created, freed as `Obj  .Free;`     -> must be SILENT
    TightFree    created, freed as `Obj.Free;`       -> must be SILENT (control:
                                                        the unpadded case must not
                                                        regress)
    TrueLeak     created, never freed                -> must STILL FIRE
    WrongFree    creates A and B, finally frees only
                 `B  .Free;` (padded)                -> A must STILL FIRE

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_paddedfree'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'padded.pas'

$body = @'
unit padded;

interface

implementation

uses
  System.Classes;

procedure PaddedFree;
var
  Obj: TStringList;
begin
  Obj := TStringList.Create;
  try
    Obj.Add('x');
  finally
    Obj  .Free;
  end;
end;

procedure TightFree;
var
  Obj: TStringList;
begin
  Obj := TStringList.Create;
  try
    Obj.Add('x');
  finally
    Obj.Free;
  end;
end;

procedure TrueLeak;
var
  Obj: TStringList;
begin
  Obj := TStringList.Create;
  Obj.Add('x');
end;

procedure WrongFree;
var
  A: TStringList;
  B: TStringList;
begin
  A := TStringList.Create;
  B := TStringList.Create;
  try
    A.Add('x');
    B.Add('y');
  finally
    B  .Free;
  end;
end;

end.
'@
[System.IO.File]::WriteAllText($target, (($body -replace "`r`n","`n") -replace "`n","`r`n"),
  (New-Object System.Text.UTF8Encoding($false)))

Push-Location C:\TEMP
try {
  $out = & $exePath lint $target 2>&1 | Out-String
  $leaks = ($out -split "`r?`n") | Where-Object { $_ -match 'object-leak' }

  Check 'SANITY: the linter ran and produced output' ($out.Trim().Length -gt 0) $out

  # A finding names the variable in quotes: Object "obj" may be leaked.
  function Leaked($name) {
    foreach ($l in $leaks) { if ($l -match ('"' + $name + '"')) { return $true } }
    return $false
  }

  Check 'POSITIVE CONTROL: TrueLeak still fires (the rule is not switched off)' `
        ($leaks.Count -ge 1) $out
  # A finding carries file:line and the variable name -- never the routine name --
  # so assert on the LINE of each `Create`. (@() matters: a Where-Object that
  # matches nothing yields $null, and $null.Count is $null, not 0.)
  $createLines = @{}
  $srcLines = [System.IO.File]::ReadAllLines($target)
  for ($i = 0; $i -lt $srcLines.Count; $i++) {
    if ($srcLines[$i] -match 'TStringList\.Create') { $createLines[($i+1)] = $true }
  }
  Check 'SANITY: fixture has the 5 expected Create sites' ($createLines.Count -eq 5) ($createLines.Keys -join ',')

  function LeakAtLine($ln) { return (@($leaks | Where-Object { $_ -match ":$ln`:" }).Count -gt 0) }

  # PaddedFree's Create is the FIRST one; TightFree's the second.
  $ordered = $createLines.Keys | Sort-Object
  Check 'padded `Obj  .Free;` is recognised as a free (no leak for PaddedFree)' `
        (-not (LeakAtLine $ordered[0])) ($leaks -join "`n")
  Check 'unpadded `Obj.Free;` still recognised (no regression)' `
        (-not (LeakAtLine $ordered[1])) ($leaks -join "`n")
  Check 'POSITIVE CONTROL: TrueLeak IS reported at its own Create line' `
        (LeakAtLine $ordered[2]) ($leaks -join "`n")
  Check 'POSITIVE CONTROL: WrongFree -- freeing a DIFFERENT padded var does not launder A' `
        (Leaked 'a') ($leaks -join "`n")
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
