<#
  run_hardcoded_path_sink.ps1 -- `hardcoded-absolute-path` must flag a path
  PORTION that reaches a filesystem SINK, and stay silent otherwise.

  THE REDESIGN (owner spec, 2026-08-31)
  -------------------------------------
  The old rule was one predicate -- any string literal starting with a drive
  letter, anywhere, regardless of what the program did with it:

      ((literalString) @warn (#match? @warn "^'[A-Za-z]:"))

  73 findings on DataCopy, 55% of their test report, and the failures were all
  literals passed to things that touch no filesystem: a domain helper, `Pos`
  as a search needle, and an IniFile default -- that last one advising the
  author to do exactly what the line already does.

  The owner's specification, in his words:
    * "if we see any specific hardcoded part of location - doesn't have to be
      a complete address we put this message"
    * "The pure file name and extension can be hardcoded, but the path to it
      not. Be it partial or complete path."
    * "BUT if it is computed and not from string const, but from some
      environment, like form field or INI file, then it is OK."
    * "propagate back say up to 4 steps ... if none of them is a text const we
      consider it not hard coded"

  So: anchor on a sink, walk backwards up to 4 steps, classify the leaves.
  A string literal contributing a path PORTION is the finding; anything
  computed -- config, environment, UI, parameter, function result -- is clean,
  and so is anything unresolved (this rule over-reports today, so silence is
  the safe failure direction).

  THIS ALSO FIXES A FALSE NEGATIVE. The old pattern was drive-letter anchored,
  so `'\\server\share\x'` was missed entirely. Case 3 is that.

  NARROWED 2026-09-01 -- A RELATIVE PORTION IS NOW ALLOWED (owner ruling)
  ----------------------------------------------------------------------
    "a hardcoded relative portion should be allowed. Not a risk. We can also
     flag hard paths with drives included."

  Case 2 therefore INVERTS: it reaches a real sink and must now stay SILENT.
  Only an absolute ROOT -- a drive letter or a UNC lead -- is a finding, because
  only those name a location on one machine. Measured against drag-lint's own
  source, the separator-based predicate produced 4 findings and every one was a
  fixed remainder under a COMPUTED base, e.g.

      TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules\builtin.txt')

  which is the shape you want, not a defect. The expected finding count moves
  4 -> 3 for that reason and not because a case was deleted.

  WHY BOTH POLARITIES ARE ASSERTED
  --------------------------------
  A suite asserting only "the false findings are gone" passes with the rule
  switched off. Cases 1-4 are the positive controls: they must fire, and case
  1 is specifically the true positive that the tempting cheap fix ("only flag
  a literal that IS a direct argument to a file API") would have lost.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hardcoded-path-sink"
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
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory $WorkDir | Out-Null }

$fixture = Join-Path $WorkDir 'HardcodedPathSink.pas'
$body = @'
unit HardcodedPathSink;

interface

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.IniFiles;

function FolderInUse(const ALabel, APath: string): Boolean; forward;
function ReadCfg(const AKey: string): string; forward;

function FolderInUse(const ALabel, APath: string): Boolean;
begin
  Result := (ALabel <> '') and (APath <> '');
end;

function ReadCfg(const AKey: string): string;
begin
  Result := AKey;
end;

// ---- MUST FIRE -------------------------------------------------------------

procedure Case1_LocalThenSink;
var
  LPath: string;
begin
  LPath := 'C:\out\report.csv';
  TFile.WriteAllText(LPath, 'x');
end;

procedure Case2_RelativePath;
var
  F: TextFile;
begin
  AssignFile(F, 'subdir\data.csv');
end;

procedure Case3_UncPath;
var
  S: TFileStream;
begin
  S := TFileStream.Create('\\server\share\x.dat', fmOpenRead);
  S.Free;
end;

procedure Case4_ConcatPortion(const AName: string);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  SL.LoadFromFile('C:\cfg\' + AName);
  SL.Free;
end;

// ---- MUST STAY SILENT ------------------------------------------------------

procedure Case5_NonSinkCall;
begin
  FolderInUse('Copy from folder', 'C:\FROM');
end;

procedure Case6_SearchNeedle(const AMess: string);
var
  N: Integer;
begin
  N := Pos('C:\FROM', AMess);
  if N > 0 then Exit;
end;

procedure Case7_IniDefault(const AIni: TIniFile);
var
  S: string;
begin
  S := AIni.ReadString('General', 'EdtFrom', 'C:\');
  if S = '' then Exit;
end;

procedure Case8_EnvironmentLeaf(const AText: string);
begin
  TFile.WriteAllText(AText, 'x');
end;

procedure Case9_ComputedOneStepBack;
var
  LPath: string;
begin
  LPath := ReadCfg('EdtFrom');
  TFile.WriteAllText(LPath, 'x');
end;

procedure Case10_BareFilename;
begin
  TFile.WriteAllText('report.csv', 'x');
end;

procedure Case11_AssignedTwice;
var
  LPath: string;
begin
  LPath := 'C:\dead\store.csv';
  LPath := ReadCfg('EdtFrom');
  TFile.WriteAllText(LPath, 'x');
end;

// ---- MUST FIRE: a live hardcoded DEFAULT (owner ruling 2026-09-01) ---------

procedure Case12_EnvThenHardcodedFallback;
var
  BdsDir, LibRelease: string;
begin
  BdsDir := ReadCfg('BDS');
  if BdsDir = '' then BdsDir := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';
  LibRelease := TPath.Combine(BdsDir, 'lib\release');
  if TDirectory.Exists(LibRelease) then Exit;
end;

procedure Case13_HardcodedDefaultThenConditional(const AFlag: Boolean);
var
  LPath: string;
begin
  LPath := 'C:\fallback\out.txt';
  if AFlag then LPath := ReadCfg('EdtFrom');
  TFile.WriteAllText(LPath, 'x');
end;

procedure Case14_DirectoryExistsSink;
begin
  if DirectoryExists('C:\ProgramData\IsThisTheTestBox') then Exit;
end;

end.
'@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

$lines = [System.IO.File]::ReadAllLines($fixture)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$ln1  = LineOf "LPath := 'C:\out\report.csv';"
$ln2  = LineOf "AssignFile(F, 'subdir\data.csv');"
$ln3  = LineOf "S := TFileStream.Create('\\server\share\x.dat', fmOpenRead);"
$ln4  = LineOf "SL.LoadFromFile('C:\cfg\' + AName);"
$ln5  = LineOf "FolderInUse('Copy from folder', 'C:\FROM');"
$ln6  = LineOf "N := Pos('C:\FROM', AMess);"
$ln7  = LineOf "S := AIni.ReadString('General', 'EdtFrom', 'C:\');"
$ln10 = LineOf "TFile.WriteAllText('report.csv', 'x');"
# A DISTINCT literal on purpose: Case1 uses the identical statement text, and
# LineOf returns the FIRST match, so sharing it silently pointed this assertion
# at Case1's line -- where a finding is REQUIRED -- and it failed against a
# correct build.
$ln11 = LineOf "LPath := 'C:\dead\store.csv';"
$ln12 = LineOf "if BdsDir = '' then BdsDir := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';"
$ln13 = LineOf "LPath := 'C:\fallback\out.txt';"
$ln14 = LineOf "if DirectoryExists('C:\ProgramData\IsThisTheTestBox') then Exit;"
Check 'fixture lines located' (@($ln1,$ln2,$ln3,$ln4,$ln5,$ln6,$ln7,$ln10) -notcontains -1) `
  "fire: $ln1,$ln2,$ln3,$ln4  silent: $ln5,$ln6,$ln7,$ln10"

$fired = @()
foreach ($line in (& $Exe lint $fixture 2>$null)) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+hardcoded-absolute-path:') { $fired += [int]$Matches[1] }
}
$fired = @($fired | Sort-Object -Unique)
Write-Host ("  fired on lines: {0}" -f ($fired -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'POSITIVE CONTROLS -- an ABSOLUTE ROOT reaching a sink MUST fire' -ForegroundColor Cyan
Check "1  local literal -> TFile.WriteAllText      (line $ln1)"  ($fired -contains $ln1)
Check "3  UNC path -> TFileStream.Create           (line $ln3)"  ($fired -contains $ln3)
Check "4  portion on one side of a concat          (line $ln4)"  ($fired -contains $ln4)

Write-Host ''
Write-Host 'THE DEFECT -- literals that reach no sink MUST stay silent' -ForegroundColor Cyan
Check "5  non-sink domain call                     (line $ln5)"  (-not ($fired -contains $ln5))
Check "6  search needle, not a path                (line $ln6)"  (-not ($fired -contains $ln6))
Check "7  IniFile default value                    (line $ln7)"  (-not ($fired -contains $ln7))
Check "10 bare filename, allowed by spec           (line $ln10)" (-not ($fired -contains $ln10))

Write-Host ''
Write-Host 'RELATIVE PATHS ARE ALLOWED -- owner ruling 2026-09-01' -ForegroundColor Cyan
# THIS ASSERTION IS INVERTED FROM ITS ORIGINAL. Case 2 reaches a real sink
# (AssignFile) and still must NOT fire: it carries no drive and no UNC lead, so
# it names no location on any one machine. "a hardcoded relative portion should
# be allowed. Not a risk. We can also flag hard paths with drives included."
# Kept as a live assertion rather than deleted, because the FIRING direction is
# what regressed drag-lint's own source (4 false positives, all of them a fixed
# remainder under a computed base).
Check "2  relative path -> AssignFile, now SILENT  (line $ln2)"  (-not ($fired -contains $ln2))

Write-Host ''
Write-Host 'REACHING DEFINITIONS -- a LIVE hardcoded default MUST fire' -ForegroundColor Cyan
# Owner ruling 2026-09-01: "Even in case of hardcoded default; if X then
# <computed> we also should issue because the default is a possible outcome."
# Both directions of the idiom are asserted, because they are mirror images and
# a fix for one can easily miss the other:
#   12 = env first, hardcoded fallback second (the CLI.pas:16844 shape)
#   13 = hardcoded default first, conditional computed overwrite second
# 12 also proves the walk still crosses TPath.Combine and a second local.
Check "12 env, then hardcoded fallback         (line $ln12)" ($fired -contains $ln12)
Check "13 hardcoded default, cond. overwrite   (line $ln13)" ($fired -contains $ln13)

Write-Host ''
Write-Host 'SINK TABLE -- DirectoryExists is a sink (owner idiom)' -ForegroundColor Cyan
# "to figure out if the software is running on a test computer or customer, to
# check for existence of some folder. I don't open any files, just check."
# That idiom was INVISIBLE until 2026-09-01: DirectoryExists was missing from
# SinkOf, and a missing sink is a false negative that looks like health.
Check "14 DirectoryExists is a sink            (line $ln14)" ($fired -contains $ln14)

Write-Host ''
Write-Host 'DEAD STORE -- an UNCONDITIONAL overwrite still kills it' -ForegroundColor Cyan
# The limit of the ruling, and the reason this is reaching-definitions rather
# than "any assignment taints": here the hardcoded value can NEVER reach the
# sink, so it cannot break on any machine. The owner's own test for firing is
# that the default "is a possible outcome" -- this one is not.
Check "11 dead store before the sink, SILENT   (line $ln11)" (-not ($fired -contains $ln11))

Write-Host ''
Write-Host 'COMPUTED SOURCES -- environment/config leaves MUST stay silent' -ForegroundColor Cyan
Check '8  parameter leaf (form field idiom)'  ($fired.Count -eq 6)  "expected exactly 6 findings, got $($fired.Count)"

Write-Host ''
Write-Host 'SEVERITY TIERS -- a COMPLETE path is a warning, not info' -ForegroundColor Cyan
# Owner ruling: "issue a stronger message when we see any complete path
# including drive letter."
$sev = @{}
foreach ($line in (& $Exe lint $fixture 2>$null)) {
  if ("$line" -match ':(\d+):\d+\s+\[(\w+)\]\s+hardcoded-absolute-path:') { $sev[[int]$Matches[1]] = $Matches[2] }
}
Check "1  'C:\out\report.csv' is warning"      ($sev[$ln1]  -eq 'warning') "got '$($sev[$ln1])'"
Check "3  UNC share is warning"                ($sev[$ln3]  -eq 'warning') "got '$($sev[$ln3])'"
Check "12 drive-rooted fallback is warning"    ($sev[$ln12] -eq 'warning') "got '$($sev[$ln12])'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
