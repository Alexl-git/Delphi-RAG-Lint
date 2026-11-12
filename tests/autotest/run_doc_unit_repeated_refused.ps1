<#
  run_doc_unit_repeated_refused.ps1 -- 152b DOCU2: `document --unit A --unit B`
  must not document B alone and exit 0.

  THE DEFECT (152b DOCU, FOUND-152b)
  ----------------------------------
  ParseArgs stored --unit in ONE field (DocUnit:= ParamStr(i)), so a second
  --unit REPLACED the first in silence: the run documented only the last unit
  and exited 0, and a user who listed two units believed both were done.
  Chosen fix (smaller than a multi-unit loop, and it keeps DOCU's one-snapshot-
  per-run refusal meaningful): a second, DIFFERENT --unit is refused, exit 2,
  naming both values -- the N-02 pattern `--rule` already follows.

  WHAT IS ASSERTED
  ----------------
    P1  positive control: `document --unit A.pas` alone runs, exit 0, renders
        an edit for A.
    P2  the same --unit given twice (identical value) is not a conflict: exit 0.
    R1  `document --unit A.pas --unit B.pas`: exit 2, the error names both
        units, nothing is rendered. (Base 1.50.0-alpha: exit 0, B only.)
    R2  the same with --apply: exit 2, both files byte-identical.

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_doc_unit_repeated_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'UA.pas') @'
unit UA;

interface

function AddA(const X, Y: Integer): Integer;

implementation

function AddA(const X, Y: Integer): Integer;
begin
  Result := X + Y;
end;

end.
'@
WriteAscii (Join-Path $scratch 'UB.pas') @'
unit UB;

interface

function AddB(const X, Y: Integer): Integer;

implementation

function AddB(const X, Y: Integer): Integer;
begin
  Result := X + Y;
end;

end.
'@
WriteAscii (Join-Path $scratch 'Rp.dpr') @'
program Rp;

uses
  UA in 'UA.pas',
  UB in 'UB.pas';

begin
end.
'@
$db  = Join-Path $scratch 'rp.sqlite'
$dpr = Join-Path $scratch 'Rp.dpr'
$ua  = Join-Path $scratch 'UA.pas'
$ub  = Join-Path $scratch 'UB.pas'

function RunEngine([string[]]$EngineArgs) {
  $out = & $exePath @EngineArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
$ix = RunEngine @('index','--project',$dpr,'--db',$db)
if ($ix.Code -ne 0) { throw "fixture index failed: $($ix.Text)" }

$p1 = RunEngine @('document','--unit',$ua,'--db',$db,'--stubs')
Check 'P1 one --unit: exit 0, renders an edit' (($p1.Code -eq 0) -and ($p1.Text -match 'insert after line')) "exit $($p1.Code)"

$p2 = RunEngine @('document','--unit',$ua,'--unit',$ua,'--db',$db,'--stubs')
Check 'P2 same --unit twice: exit 0' ($p2.Code -eq 0) "exit $($p2.Code)"

$r1 = RunEngine @('document','--unit',$ua,'--unit',$ub,'--db',$db,'--stubs')
Check 'R1 two different --unit: exit 2' ($r1.Code -eq 2) "exit $($r1.Code)"
Check 'R1 error names both units' (($r1.Text -match '--unit given more than once') -and ($r1.Text -match 'UA\.pas') -and ($r1.Text -match 'UB\.pas')) ($r1.Text.Trim() -split "`n" | Select-Object -Last 2)
Check 'R1 nothing rendered' (-not ($r1.Text -match 'insert after line'))

$aBefore = [IO.File]::ReadAllBytes($ua); $bBefore = [IO.File]::ReadAllBytes($ub)
$r2 = RunEngine @('document','--unit',$ua,'--unit',$ub,'--db',$db,'--stubs','--apply','--no-backup')
$same = ([Convert]::ToBase64String($aBefore) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($ua))) -and
        ([Convert]::ToBase64String($bBefore) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($ub)))
Check 'R2 --apply with two --unit: exit 2, both files byte-identical' (($r2.Code -eq 2) -and $same) "exit $($r2.Code)"

if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
if ($fail) { Write-Host 'run_doc_unit_repeated_refused: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_unit_repeated_refused: ALL PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "run_doc_unit_repeated_refused: ERROR $_" -ForegroundColor Red; exit 2 }
