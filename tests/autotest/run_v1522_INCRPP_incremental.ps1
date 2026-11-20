<#
  run_v1522_INCRPP_incremental.ps1 -- an incremental `index --project` must re-parse a host
  whose PREPROCESSOR INPUTS changed although its own bytes did not
  (docs\INBOX-incremental-preproc-inputs.md, found by INCR18 part 1b).

  Two inputs the up-to-date test did not see:
    1. an include the host could NOT resolve is created later
       (uB.pas: {$I incpp_opt.inc} missing -> created with {$DEFINE OPT_ON} -> uses uOpt);
    2. a constant of ANOTHER unit read by the host's {$IF} changes
       (uIf.pas: {$IF PP_LEVEL > 1} uses uIfX, PP_LEVEL lives in uConsts.pas).
  Per edit: base index, the edit, then
      C  base + incremental index           (the shipped path)
      F  a fresh full index of the edited tree
  and C = F (index_db_diff, 0 differing rows).
  POSITIVE CONTROLS: the edit really changed the full index (F <> base), and an
  incremental run with NOTHING changed still skips the hosts (up-to-date count > 0 and
  the database is unchanged) -- so a fix that simply re-parses everything cannot pass.

  RED on an engine without the fix (C keeps uB / uIf's old unit_uses, pp_regions).
  Run from a NEUTRAL CWD (the script pushes C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe = '',
  [switch]$KeepScratch
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$scratch = Join-Path C:\TEMP "draglint_incrpp_$PID"

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))
}
function Remove-Db($db) { foreach ($s in '', '-wal', '-shm') { if (Test-Path -LiteralPath "$db$s") { [System.IO.File]::Delete("$db$s") } } }
function Copy-Db($from, $to) { Remove-Db $to; Copy-Item -LiteralPath $from -Destination $to }

$exePath = (Resolve-Path $Exe).Path
$diffPy  = Join-Path $Repo 'tools\measure\index_db_diff.py'
$pyExe = 'python'; $pyPre = @()
if (Get-Command py -ErrorAction SilentlyContinue) { $pyExe = 'py'; $pyPre = @('-I') }
$env:DRAGLINT_RULE_CACHE = '0'

function Invoke-Engine([string[]]$ArgList) {
  $out = & { $ErrorActionPreference = 'Continue'; & $exePath @ArgList 2>&1 | ForEach-Object { "$_" } } | Out-String
  $script:LastEngineExit = $LASTEXITCODE
  return $out
}
# index_db_diff: exit 0 = identical, 1 = differences, anything else = could not compare.
function Compare-Db($a, $b) {
  $out = & { $ErrorActionPreference = 'Continue'; & $pyExe @pyPre $diffPy $a $b 2>&1 | ForEach-Object { "$_" } }
  $code = $LASTEXITCODE
  if ($code -ne 0 -and $code -ne 1) { $out = @("index_db_diff exit $code -- NOT a comparison") + $out }
  $tell = @($out | Where-Object { $_ -match 'DIFF|only A|only B|^\s+[AB] |TABLE ONLY|FILE ONLY|index_db_diff|Traceback|Error' } | Select-Object -First 16)
  if ($tell.Count -eq 0) { $tell = @($out | Select-Object -Last 6) }
  return @{ Same = ($code -eq 0); Code = $code; Text = ($tell -join "`n      ") }
}
# N of 'Done. ... skipped N up-to-date' (the clause is absent when nothing was skipped), or -1.
function Get-UpToDate($out) {
  if ($out -match 'skipped (\d+) up-to-date') { return [int]$Matches[1] }
  if ($out -match 'Done\. Files:') { return 0 }
  return -1
}

if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
$fx = Join-Path $scratch 'fx'
New-Item -ItemType Directory -Path $fx | Out-Null
$proj = Join-Path $fx 'Proj.dpr'

Write-Ascii $proj @'
program Proj;

uses
  uMain in 'uMain.pas';

begin
  Run;
end.
'@
Write-Ascii (Join-Path $fx 'uMain.pas') @'
unit uMain;

interface

procedure Run;

implementation

uses
  uB, uIf;

procedure Run;
begin
  ValueB;
  ValueIf;
end;

end.
'@
# uB: its include does not exist yet.
Write-Ascii (Join-Path $fx 'uB.pas') @'
unit uB;

{$I incpp_opt.inc}

interface

uses
  uBase
  {$IFDEF OPT_ON}, uOpt{$ENDIF}
  ;

function ValueB: Integer;

implementation

function ValueB: Integer;
begin
  Result := BaseValue + 1;
end;

end.
'@
# uIf: an {$IF} on a constant of ANOTHER unit decides its uses clause -- no include involved.
Write-Ascii (Join-Path $fx 'uIf.pas') @'
unit uIf;

interface

uses
  uConsts;

function ValueIf: Integer;

implementation

{$IF PP_LEVEL > 1}
uses
  uIfX;
{$IFEND}

function ValueIf: Integer;
begin
  Result := PP_LEVEL;
end;

end.
'@
Write-Ascii (Join-Path $fx 'uConsts.pas') @'
unit uConsts;

interface

const
  PP_LEVEL = 1;

implementation

end.
'@
Write-Ascii (Join-Path $fx 'uBase.pas') @'
unit uBase;

interface

function BaseValue: Integer;

implementation

function BaseValue: Integer;
begin
  Result := 1;
end;

end.
'@
foreach ($u in 'uOpt', 'uIfX') {
  Write-Ascii (Join-Path $fx "$u.pas") @"
unit $u;

interface

function ${u}Value: Integer;

implementation

function ${u}Value: Integer;
begin
  Result := 7;
end;

end.
"@
}

Push-Location C:\TEMP
try {
  $base = Join-Path $scratch 'base.sqlite'
  Start-Sleep -Milliseconds 1500   # every fixture file older than the base run's parse stamp
  $outBase = Invoke-Engine @('index', '--project', $proj, '--db', $base)
  Check 'the base index ran' ($LastEngineExit -eq 0 -and (Test-Path $base)) (($outBase -split "`n") | Select-Object -Last 6 | Out-String)

  # POSITIVE CONTROL: nothing changed -> the hosts are skipped and the database is unchanged.
  $dbN = Join-Path $scratch 'n.sqlite'
  Copy-Db $base $dbN
  Start-Sleep -Milliseconds 1100
  $outN = Invoke-Engine @('index', '--project', $proj, '--db', $dbN)
  $skipN = Get-UpToDate $outN
  Check "nothing changed: the incremental run skips the unchanged hosts (up-to-date=$skipN)" ($skipN -ge 6) (($outN -split "`n") | Select-String 'Done\.' | Out-String)
  $d = Compare-Db $dbN $base
  Check 'nothing changed: the incremental run leaves the database as it was (0 diff rows)' $d.Same $d.Text

  $edits = @(
    @{ Name = 'create an include the host could not resolve'; File = 'incpp_opt.inc'; Text = '{$DEFINE OPT_ON}' },
    @{ Name = 'edit a constant another unit''s IF reads';      File = 'uConsts.pas';   Find = 'PP_LEVEL = 1;'; Repl = 'PP_LEVEL = 2;' }
  )
  foreach ($e in $edits) {
    $file = Join-Path $fx $e.File
    $keep = Join-Path $scratch ($e.File + '.orig')
    $had = [System.IO.File]::Exists($file)
    if ($had) { [System.IO.File]::Copy($file, $keep, $true) }
    try {
      Start-Sleep -Milliseconds 1100   # the edit's mtime is a later second than the base parse
      if ($e.Find) { Write-Ascii $file ([System.IO.File]::ReadAllText($file).Replace($e.Find, $e.Repl)) }
      else { Write-Ascii $file ($e.Text + "`r`n") }

      $dbC = Join-Path $scratch 'c.sqlite'; $dbF = Join-Path $scratch 'f.sqlite'
      Copy-Db $base $dbC; Remove-Db $dbF
      $outC = Invoke-Engine @('index', '--project', $proj, '--db', $dbC)
      Invoke-Engine @('index', '--project', $proj, '--db', $dbF) | Out-Null

      $d = Compare-Db $dbF $base
      Check "$($e.Name): POSITIVE CONTROL -- the edit changes the full index" (-not $d.Same -and $d.Code -eq 1) "index_db_diff exit $($d.Code)"
      $d = Compare-Db $dbC $dbF
      Check "$($e.Name): incremental = full index (0 diff rows)" $d.Same $d.Text
      $skipC = Get-UpToDate $outC
      Check "$($e.Name): the incremental run still skipped unaffected hosts (up-to-date=$skipC)" ($skipC -ge 4) (($outC -split "`n") | Select-String 'Done\.' | Out-String)
    } finally {
      if ($had) { [System.IO.File]::Copy($keep, $file, $true) } else { [System.IO.File]::Delete($file) }
    }
  }
} finally {
  Pop-Location
  if (-not $KeepScratch -and (Test-Path $scratch)) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}

if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
