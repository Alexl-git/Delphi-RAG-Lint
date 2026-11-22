<#
  run_v1523_INCR_incremental.ps1 -- an incremental `index --project` must re-parse a file
  whose inputs changed although its own bytes did not, in the three shapes 1.52.2 left out
  (lane v1523 INCR; docs\INBOX-incremental-preproc-inputs.md "Limits"; INCR18 finding 1):
    1. INCRPP-LIMITS near search: an include the host could not resolve appears later in a
       SUBFOLDER of the host's folder (the preprocess's near search finds it there; the
       recorded candidates named only the host folder and the search path);
    2. INCRPP-LIMITS indirect constant: the host's IF reads PP_DEEP of uConstsA, which is
       defined as PP_ROOT of uConstsB; uConstsB changes;
    3. INCR-BASEFIELD: a base class in another file gains a field that a descendant's method
       writes by bare name; the descendant's file is unchanged, and its
       symbol_facts.writes_fields came from the facts-inherited pass of its own parse.
  Per edit: base index, the edit, then
      C  base + incremental index           (the shipped path)
      F  a fresh full index of the edited tree
  and C = F (index_db_diff, 0 differing rows).
  POSITIVE CONTROLS: the edit really changed the full index (F <> base; edit 3 also shows
  Extra in Work's writes_fields in F), and an incremental run with NOTHING changed still
  skips the hosts and leaves the database unchanged -- so re-parsing everything cannot pass.

  RED on an engine without the fix (C keeps the old unit_uses / pp_regions / writes_fields).
  Run from a NEUTRAL CWD (the script pushes C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe = '',
  [switch]$KeepScratch
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$scratch = Join-Path C:\TEMP "draglint_incr1523_$PID"

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
  uN, uIf2, uKid;

procedure Run;
begin
  ValueN;
  ValueIf2;
  DriveKid(nil);
end;

end.
'@
# uN: its include resolves nowhere yet -- not beside it, and no search path.
Write-Ascii (Join-Path $fx 'uN.pas') @'
unit uN;

{$I incnear_opt.inc}

interface

uses
  uBase
  {$IFDEF NEAR_ON}, uNear{$ENDIF}
  ;

function ValueN: Integer;

implementation

function ValueN: Integer;
begin
  Result := BaseValue + 1;
end;

end.
'@
# uIf2: its IF reads PP_DEEP of uConstsA, which is defined through uConstsB's PP_ROOT.
Write-Ascii (Join-Path $fx 'uIf2.pas') @'
unit uIf2;

interface

uses
  uConstsA;

function ValueIf2: Integer;

implementation

{$IF PP_DEEP > 1}
uses
  uIfY;
{$IFEND}

function ValueIf2: Integer;
begin
  Result := PP_DEEP;
end;

end.
'@
Write-Ascii (Join-Path $fx 'uConstsA.pas') @'
unit uConstsA;

interface

uses
  uConstsB;

const
  PP_DEEP = PP_ROOT;

implementation

end.
'@
Write-Ascii (Join-Path $fx 'uConstsB.pas') @'
unit uConstsB;

interface

const
  PP_ROOT = 1;

implementation

end.
'@
# uKid: TKid.Work writes `Extra`, a unit variable today; once TKidBase gains a field
# `Extra` the facts-inherited pass lists it in Work's writes_fields.
Write-Ascii (Join-Path $fx 'uKidBase.pas') @'
unit uKidBase;

interface

type
  TKidBase = class
  protected
    FSeen: Integer;
  public
    function Seen: Integer;
  end;

implementation

function TKidBase.Seen: Integer;
begin
  Result := FSeen;
end;

end.
'@
Write-Ascii (Join-Path $fx 'uKid.pas') @'
unit uKid;

interface

uses
  uKidBase;

type
  TKid = class(TKidBase)
  public
    procedure Work;
  end;

procedure DriveKid(AKid: TKid);

implementation

var
  Extra: Integer;

procedure TKid.Work;
begin
  Extra := 1;
end;

procedure DriveKid(AKid: TKid);
begin
  if AKid <> nil then AKid.Work;
end;

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
foreach ($u in 'uNear', 'uIfY') {
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

# The Work row's writes_fields ('' = no row).
function Get-WorkWrites($db) {
  $o = Invoke-Engine @('sql', '--query', "SELECT ifnull(sf.writes_fields, '') AS w FROM symbol_facts sf JOIN symbols s ON s.id = sf.symbol_id WHERE s.name = 'Work'", '--db', $db, '--json')
  if ($o -match '"rows"\s*:\s*\[\s*\[\s*"([^"]*)"') { return $Matches[1] }
  return ''
}

Push-Location C:\TEMP
try {
  $base = Join-Path $scratch 'base.sqlite'
  Start-Sleep -Milliseconds 1500   # every fixture file older than the base run's parse stamp
  $outBase = Invoke-Engine @('index', '--project', $proj, '--db', $base)
  Check 'the base index ran' ($LastEngineExit -eq 0 -and (Test-Path $base)) (($outBase -split "`n") | Select-Object -Last 6 | Out-String)
  Check 'SANITY: Work does not list Extra as a field before the edit' ((Get-WorkWrites $base) -notmatch 'Extra') "writes_fields='$(Get-WorkWrites $base)'"

  # POSITIVE CONTROL: nothing changed -> the hosts are skipped and the database is unchanged.
  $dbN = Join-Path $scratch 'n.sqlite'
  Copy-Db $base $dbN
  Start-Sleep -Milliseconds 1100
  $outN = Invoke-Engine @('index', '--project', $proj, '--db', $dbN)
  $skipN = Get-UpToDate $outN
  Check "nothing changed: the incremental run skips the unchanged hosts (up-to-date=$skipN)" ($skipN -ge 9) (($outN -split "`n") | Select-String 'Done\.' | Out-String)
  $d = Compare-Db $dbN $base
  Check 'nothing changed: the incremental run leaves the database as it was (0 diff rows)' $d.Same $d.Text
  Remove-Db $dbN

  $edits = @(
    @{ Name = 'INCRPP-LIMITS: the missing include appears in a near-search subfolder'; File = 'sub\incnear_opt.inc'; Text = '{$DEFINE NEAR_ON}' },
    @{ Name = 'INCRPP-LIMITS: a constant read through another unit''s constant changes'; File = 'uConstsB.pas'; Find = 'PP_ROOT = 1;'; Repl = 'PP_ROOT = 2;' },
    @{ Name = 'INCR-BASEFIELD: a base class gains a field a descendant in an unchanged file writes'; File = 'uKidBase.pas'; Find = '    FSeen: Integer;'; Repl = "    FSeen: Integer;`r`n    Extra: Integer;"; Kid = $true }
  )
  foreach ($e in $edits) {
    $file = Join-Path $fx $e.File
    $dir  = Split-Path $file -Parent
    $newDir = -not [System.IO.Directory]::Exists($dir)
    $keep = Join-Path $scratch ((Split-Path $e.File -Leaf) + '.orig')
    $had = [System.IO.File]::Exists($file)
    if ($had) { [System.IO.File]::Copy($file, $keep, $true) }
    try {
      Start-Sleep -Milliseconds 1100   # the edit's mtime is a later second than the base parse
      if ($newDir) { [void][System.IO.Directory]::CreateDirectory($dir) }
      if ($e.Find) { Write-Ascii $file ([System.IO.File]::ReadAllText($file).Replace($e.Find, $e.Repl)) }
      else { Write-Ascii $file ($e.Text + "`r`n") }

      $dbC = Join-Path $scratch 'c.sqlite'; $dbF = Join-Path $scratch 'f.sqlite'
      Copy-Db $base $dbC; Remove-Db $dbF
      $outC = Invoke-Engine @('index', '--project', $proj, '--db', $dbC)
      Invoke-Engine @('index', '--project', $proj, '--db', $dbF) | Out-Null

      $d = Compare-Db $dbF $base
      Check "$($e.Name): POSITIVE CONTROL -- the edit changes the full index" (-not $d.Same -and $d.Code -eq 1) "index_db_diff exit $($d.Code)"
      if ($e.Kid) {
        Check "$($e.Name): POSITIVE CONTROL -- the full index lists Extra in Work's writes_fields" ((Get-WorkWrites $dbF) -match 'Extra') "writes_fields='$(Get-WorkWrites $dbF)'"
      }
      $d = Compare-Db $dbC $dbF
      Check "$($e.Name): incremental = full index (0 diff rows)" $d.Same $d.Text
      $skipC = Get-UpToDate $outC
      Check "$($e.Name): the incremental run still skipped unaffected hosts (up-to-date=$skipC)" ($skipC -ge 6) (($outC -split "`n") | Select-String 'Done\.' | Out-String)
      Remove-Db $dbC; Remove-Db $dbF
    } finally {
      if ($had) { [System.IO.File]::Copy($keep, $file, $true) } else { [System.IO.File]::Delete($file) }
      if ($newDir) { [System.IO.Directory]::Delete($dir, $true) }
    }
  }
} finally {
  Pop-Location
  if (-not $KeepScratch -and (Test-Path $scratch)) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}

if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
