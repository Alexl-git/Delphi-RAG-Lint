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

  THIRD TIER 2026-09-02 -- NO SINK IS NOW `info`, NOT SILENCE (owner ruling 2)
  ---------------------------------------------------------------------------
    "a path literal reaching NO sink becomes info, not silence."

  The standing engineering recommendation was to DROP this, on the measurement
  that it re-admits roughly DataCopy's original 73 literals one severity lower
  -- the very flood B7 existed to remove. The owner was shown that and ruled for
  the tier. It is implemented, and the cost is recorded HERE rather than argued
  again: cases 5, 6, 7 and 11 below flipped from silent to firing, and they are
  the same three shapes (domain helper, search needle, IniFile default) that
  opened the redesign, plus a dead store.

  What keeps it honest is the SEVERITY SPLIT and the wording. The backstop has
  established nothing about how the literal is used, so it reports at `info` and
  its message says "for REVIEW", never "reaches X and will break". A warning
  asserts a fact; this tier has no fact to assert.

  And it is BOUNDED: IsPathPortion still requires a drive letter or a UNC lead,
  so ruling (a) survives -- cases 2 and 10 (relative path, bare filename) remain
  silent, and they are the controls that would catch a backstop widened to every
  string literal.

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

// ---- MUST STAY SILENT: a leading slash PAIR is not automatically a UNC -----

procedure Case15_CommentMarkerIsNotAPath;
var
  S: string;
begin
  S := '//';
  Writeln(S);
end;

procedure Case16_RegexFragmentIsNotAPath;
var
  S: string;
begin
  S := '//\s*(TODO|FIXME|HACK)\b';
  Writeln(S);
end;

procedure Case17_DocMarkerIsNotAPath;
var
  S: string;
begin
  S := '// ---';
  Writeln(S);
end;

procedure Case18_DocPrefixDigitIsNotAPath;
var
  S: string;
begin
  S := '//1';
  Writeln(S);
end;

// ---- MUST FIRE: an IP-addressed UNC share is still a path -----------------

procedure Case19_IpAddressedUncShare;
var
  S: string;
begin
  S := '\\192.168.1.10\share\data.csv';
  Writeln(S);
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
$ln15 = LineOf "S := '//';"
$ln16 = LineOf "S := '//\s*(TODO|FIXME|HACK)\b';"
$ln17 = LineOf "S := '// ---';"
$ln18 = LineOf "S := '//1';"
$ln19 = LineOf "S := '\\192.168.1.10\share\data.csv';"
# ln15..ln17 MUST be in this list. A silent-direction assertion reads
# "-not ($fired -contains $lnN)", which is VACUOUSLY TRUE when LineOf returned
# -1 -- so an unlocated line would give three green ticks that assert nothing.
Check 'fixture lines located' (@($ln1,$ln2,$ln3,$ln4,$ln5,$ln6,$ln7,$ln10,$ln15,$ln16,$ln17,$ln18,$ln19) -notcontains -1) `
  "fire: $ln1,$ln2,$ln3,$ln4,$ln19  silent: $ln5,$ln6,$ln7,$ln10,$ln15,$ln16,$ln17,$ln18"

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
Write-Host 'BACKSTOP TIER (owner ruling 2, 2026-09-02) -- NO sink means INFO, not silence' -ForegroundColor Cyan
# THESE THREE ASSERTIONS ARE INVERTED FROM THEIR ORIGINALS, and that inversion
# IS the ruling. They are the exact shapes B7 was built to remove -- a domain
# helper, `Pos` as a search needle, and an IniFile default -- taken from the
# DataCopy corpus where literals like these were 55% of the report. The cost was
# put to the owner before the decision and he chose the tier anyway:
#     "a path literal reaching NO sink becomes info, not silence."
# They are kept as LIVE assertions in the firing direction rather than deleted.
# If the tier is ever dropped, invert these three BACK; do not remove them,
# because the silent direction is what the redesign originally bought and it
# must not be lost by omission.
Check "5  non-sink domain call now fires           (line $ln5)"  ($fired -contains $ln5)
Check "6  search needle now fires                  (line $ln6)"  ($fired -contains $ln6)
Check "7  IniFile default now fires                (line $ln7)"  ($fired -contains $ln7)

Write-Host ''
Write-Host 'THE BACKSTOP IS STILL BOUNDED -- a non-absolute literal stays SILENT' -ForegroundColor Cyan
# The tier did NOT become "any string literal". IsPathPortion still demands a
# drive letter or a UNC lead, so ruling (a) survives it. This is the control
# that catches a backstop accidentally widened to every literal -- the only way
# this rule could reach the thousands the lint-clean standard forbids.
Check "10 bare filename, allowed by spec           (line $ln10)" (-not ($fired -contains $ln10))

Write-Host ''
Write-Host 'A LEADING SLASH PAIR IS NOT AUTOMATICALLY A UNC ROOT' -ForegroundColor Cyan
# REGRESSION CONTROL, and it is not hypothetical: when the backstop first ran it
# produced 68 findings on drag-lint's own source and THIRTY-ONE of them were
# these -- '//', '///', '\\', '// ---', '//\s*(TODO|FIXME)\b' -- string literals
# in the comment-parsing code, classified as UNC roots because IsPathPortion
# tested only for the leading PAIR. The defect predates ruling 2 and was simply
# unreachable while the rule was sink-anchored: no comment marker flows into a
# filesystem call. A server name is now required.
#
# These assertions belong to the SILENT direction permanently. Case 3 above is
# their counterweight -- a real UNC share must still fire -- so a fix that
# silences the markers by breaking UNC support cannot pass both.
Check "15 '//' comment marker                      (line $ln15)" (-not ($fired -contains $ln15))
Check "16 '//\s*(TODO...)' regex fragment          (line $ln16)" (-not ($fired -contains $ln16))
Check "17 '// ---' doc rule                        (line $ln17)" (-not ($fired -contains $ln17))
Check "18 '//1' doc-comment prefix                 (line $ln18)" (-not ($fired -contains $ln18))

Write-Host ''
Write-Host 'BUT AN IP-ADDRESSED UNC SHARE IS STILL A PATH' -ForegroundColor Cyan
# THE COUNTERWEIGHT TO 18, AND THE REASON THE FIX IS NOT "THE HOST MUST START
# WITH A LETTER". '\\192.168.1.10\share' is a legal UNC and the most
# machine-bound path a program can contain -- silencing it to be rid of '//1'
# would trade the noisiest false positive for the most valuable true one.
# What actually separates them is the SHARE separator after the host, and this
# pair of assertions is what holds the implementation to that distinction
# rather than to a cheaper one that happens to pass case 18 alone.
Check "19 IP-addressed UNC share fires             (line $ln19)" ($fired -contains $ln19)

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
Write-Host 'DEAD STORE -- still not a WARNING, but the backstop now sees it' -ForegroundColor Cyan
# The reaching-definitions limit is INTACT and is still what this case tests:
# the hardcoded value can never reach the sink, so it is not a warning. What
# changed on 2026-09-02 is that "not a warning" no longer means "invisible" --
# ruling 2 reports it at info, having established nothing about its use. That
# is precisely the tier's contract, so the case now asserts BOTH halves: it
# fires, AND it fires at info rather than warning. Asserting only "it fires"
# would pass if the dead-store kill regressed and it fired as a warning.
Check "11 dead store fires at the info tier    (line $ln11)" ($fired -contains $ln11)

Write-Host ''
Write-Host 'COMPUTED SOURCES -- environment/config leaves MUST stay silent' -ForegroundColor Cyan
# 6 -> 11 with ruling 2's backstop tier: cases 5, 6, 7 and 11 flipped to firing,
# and case 19 (the IP-addressed UNC share) was added as a firing case. All five
# are asserted individually above; this TOTAL is what catches a TWELFTH
# appearing from nowhere -- e.g. a backstop that stopped honouring Seen and
# double-reported a literal the warning tier already claimed, which is the most
# likely way this tier breaks and the one no individual assertion can see.
Check '8  parameter leaf (form field idiom)'  ($fired.Count -eq 11)  "expected exactly 11 findings, got $($fired.Count)"

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
Write-Host 'BACKSTOP SEVERITY -- an unreached literal is INFO, never warning' -ForegroundColor Cyan
# THIS IS THE ASSERTION THAT MAKES THE TIER MEAN SOMETHING. Ruling 2 buys
# visibility at the price of precision, and the severity is the ONLY thing
# keeping the two apart: a warning says "this reaches a filesystem operation and
# will break on another machine", which the checker has NOT established for any
# of these four. If the backstop ever emitted at warning it would be asserting a
# fact it does not have -- the exact failure this repo has hit repeatedly -- and
# every one of these literals would be indistinguishable from case 1.
Check "5  non-sink domain call is info"        ($sev[$ln5]  -eq 'info')    "got '$($sev[$ln5])'"
Check "6  search needle is info"               ($sev[$ln6]  -eq 'info')    "got '$($sev[$ln6])'"
Check "7  IniFile default is info"             ($sev[$ln7]  -eq 'info')    "got '$($sev[$ln7])'"
Check "11 dead store is info, not warning"     ($sev[$ln11] -eq 'info')    "got '$($sev[$ln11])'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
