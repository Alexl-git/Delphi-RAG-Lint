<#
  run_find_callees_sites.ps1 -- find-callees says WHERE each call is and WHERE
  it goes, and a wrong qname gets a suggestion (Gitea drag-lint#37, 2026-10-15).

  Checks:
    S1  text: every callee line carries `at <file>:<line>` (the call site) and
        `-> <file>:<line>` (the callee), still one line per edge
    S2  --json: each row carries line, call_site and target_where
    S3  a qname naming a free routine as a method answers exit 1 with
        `did you mean: <the routine>`

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_callee_sites_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Write-Ascii (Join-Path $WorkDir 'uLib.pas') @'
unit uLib;

interface

type
  TWorker = class
  public
    procedure Step;
  end;

procedure Helper;

implementation

procedure TWorker.Step;
begin
end;

procedure Helper;
begin
end;

end.
'@
Write-Ascii (Join-Path $WorkDir 'uMain.pas') @'
unit uMain;

interface

procedure Drive;

implementation

uses
  uLib;

procedure Drive;
var
  W: TWorker;
begin
  W:= TWorker.Create;
  W.Step;
  Helper;
end;

end.
'@
Write-Ascii (Join-Path $WorkDir 'P.dpr') "program P;`n`nuses`n  uLib in 'uLib.pas',`n  uMain in 'uMain.pas';`n`nbegin`nend.`n"
$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_RULE_CACHE = '0'
$idx = & $exePath index --project (Join-Path $WorkDir 'P.dpr') --db $db 2>&1 | Out-String
$env:DRAGLINT_RULE_CACHE = $null
Check 'SANITY: fixture indexed' ($LASTEXITCODE -eq 0) $idx

$txt = @(& $exePath find-callees --qname uMain.Drive --db $db 2>&1 | Where-Object { "$_" -match '\[' })
$step   = @($txt | Where-Object { "$_" -match 'uLib\.TWorker\.Step' })
$helper = @($txt | Where-Object { "$_" -match 'uLib\.Helper' })
Check 'S1 the Step call names its site and the callee' (($step.Count -eq 1) -and ($step[0] -match 'at uMain\.pas:17\s+-> uLib\.pas:\d+')) ($txt -join ' | ')
Check 'S1 the Helper call names its site and the callee' (($helper.Count -eq 1) -and ($helper[0] -match 'at uMain\.pas:18\s+-> uLib\.pas:\d+')) ($txt -join ' | ')

$json = (& $exePath find-callees --qname uMain.Drive --db $db --json 2>$null | Out-String)
$rows = @(try { $json | ConvertFrom-Json } catch { @() })
$j = @($rows | Where-Object { $_.target_qname -eq 'uLib.Helper' })
Check 'S2 --json carries line, call_site and target_where' (($j.Count -eq 1) -and ($j[0].line -eq 18) -and ($j[0].call_site -eq 'uMain.pas:18') -and ($j[0].target_where -match '^uLib\.pas:\d+$')) $json

$miss = (& $exePath find-callees --qname uMain.TMain.Drive --db $db 2>&1 | Out-String)
Check 'S3 a method-style qname for a free routine suggests it (exit 1)' (($LASTEXITCODE -eq 1) -and ($miss -match 'did you mean: uMain\.Drive')) $miss
}
finally {
  $env:DRAGLINT_RULE_CACHE = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
