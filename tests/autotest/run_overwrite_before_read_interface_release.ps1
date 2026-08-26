<#
  run_overwrite_before_read_interface_release.ps1 -- assigning nil to an
  INTERFACE local is not a dead store; it is the release, and the release is
  frequently the entire point of the line.

  THE DEFECT THIS PINS (INBOX-overwrite-before-read-false-positive-on-interface-nil.md,
  filed 2026-08-25 from the DataCopy mahr-marposs branch, three hits in one new
  test unit and also reproducing in the pre-existing Tests\Test.CSVConfig.pas):

      LCfg := TConfigurationService.Create(IniPath);
      LCfg.SingleFileMode := 'Marposs';
      LCfg := nil;                    <- reported as a dead store
      LCfg := TConfigurationService.Create(IniPath);
      Assert.AreEqual('Marposs', LCfg.SingleFileMode);

  For an interface variable `LCfg := nil` drops the last reference, which runs
  _Release and therefore the destructor -- and TConfigurationService WRITES ITS
  INI FILE in its destructor. Deleting the flagged line does not tidy the code,
  it breaks the test, because the file is never written. Same shape as the
  pre-try guard: the rule was not merely noisy, ITS ADVICE WAS WRONG.

  Liveness is right about the CFG and wrong about Delphi: it models a store as
  producing a value, and for a managed type a store also produces an OBSERVABLE
  SIDE EFFECT that liveness cannot see.

  THE THREE POSITIVE CONTROLS ARE THE POINT OF THIS FILE. The cheap fix is to
  exempt every `:= nil`, and that would silence genuine dead stores wholesale.
  So:
    * ObjectNilDead   -- `:= nil` on a CLASS-typed local. No refcount, no
      destructor, nothing observable. MUST still fire. This is the control that
      separates "assigning nil" from "releasing an interface".
    * IntfNonNilDead  -- an interface local overwritten with another non-nil
      value before any read. MUST still fire; the note asks for exactly this to
      be preserved.
    * GenuineDead     -- an ordinary integer dead store. MUST still fire.

  Without all three, every assertion here would pass with the rule disabled.

  NOTE ON THE RESOLUTION PATH. `lint <file>` runs with no symbol store, so
  IsInterfaceType falls back to its 'I'+uppercase spelling convention. That is
  deliberate coverage: it is the path the per-file CLI and the IDE live-lint
  actually take. The store-backed path (ResolveTypeCategory -> tcInterface) is
  strictly more accurate, so a fixture that passes on the weaker path passes on
  the stronger one.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-obr-intf"
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

$FixtureBody = @'
unit uObrIntf;
interface

type
  IConfigService = interface
    ['{2A1B4C6D-8E9F-4A0B-9C1D-2E3F4A5B6C7D}']
    function GetMode: string;
    procedure SetMode(const AValue: string);
    property Mode: string read GetMode write SetMode;
  end;

procedure ReleaseRoundTrip(const F: string);
procedure ReleaseThenExit(const F: string);
procedure ObjectNilDead(const F: string);
procedure IntfNonNilDead(const F: string);
procedure GenuineDead(const F: string);

implementation
uses System.SysUtils, System.Classes;

function MakeConfig(const APath: string): IConfigService; forward;

{ THE REPORTED SHAPE. The nil store is the release; the destructor is what
  writes the file, and the second read depends on it having run. }
procedure ReleaseRoundTrip(const F: string);
var
  LCfg: IConfigService;
begin
  LCfg := MakeConfig(F);
  LCfg.SetMode('Marposs');
  LCfg := nil;
  LCfg := MakeConfig(F);
  Writeln(LCfg.GetMode);
end;

{ Same release, but the local simply goes out of scope afterwards. Still not a
  dead store: it releases EARLY, before the rest of the routine runs. }
procedure ReleaseThenExit(const F: string);
var
  LCfg: IConfigService;
  LTmp: TStringList;
begin
  LCfg := MakeConfig(F);
  LCfg.SetMode(F);
  LCfg := nil;
  LTmp := TStringList.Create;
  try
    LTmp.Add(F);
  finally
    LTmp.Free;
  end;
  LCfg := MakeConfig(F);
  Writeln(LCfg.GetMode);
end;

{ POSITIVE CONTROL 1 -- a CLASS reference. `:= nil` here is refcount-free and
  runs no destructor, so it IS a dead store. MUST fire. This is the control
  that separates "assigning nil" from "releasing an interface". }
procedure ObjectNilDead(const F: string);
var
  LObj: TStringList;
begin
  LObj := TStringList.Create;
  LObj.Add(F);
  LObj.Free;
  LObj := nil;
  LObj := TStringList.Create;
  Writeln(LObj.Count);
  LObj.Free;
end;

{ POSITIVE CONTROL 2 -- an interface local overwritten with another NON-NIL
  value before any read. A genuine dead store of an interface value. MUST fire. }
procedure IntfNonNilDead(const F: string);
var
  LCfg: IConfigService;
begin
  LCfg := MakeConfig(F);
  LCfg := MakeConfig(F + '2');
  Writeln(LCfg.GetMode);
end;

{ POSITIVE CONTROL 3 -- an ordinary integer dead store. MUST fire. }
procedure GenuineDead(const F: string);
var
  N: Integer;
begin
  N := 1;
  N := Length(F);
  Writeln(N);
end;

function MakeConfig(const APath: string): IConfigService;
begin
  Result := nil;
  Writeln(APath);
end;

end.
'@
$file = Join-Path $WorkDir 'uObrIntf.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

# LAST match: every routine is named twice (interface + implementation), and
# -First would put every anchor in the interface section, attributing every
# finding to the final routine.
$src = Get-Content $file
function Impl-Row([string]$Name) {
  ($src | Select-String -Pattern ("procedure {0}(const F: string);" -f $Name) -SimpleMatch | Select-Object -Last 1).LineNumber
}
$names = @('ReleaseRoundTrip','ReleaseThenExit','ObjectNilDead','IntfNonNilDead','GenuineDead')
$rows = [ordered]@{}
foreach ($n in $names) { $rows[$n] = Impl-Row $n }
if (@($rows.Values | Sort-Object -Unique).Count -ne $names.Count) {
  Write-Host "FATAL: anchors collapsed: $($rows.Values -join ',')" -ForegroundColor Red; exit 2
}
Write-Host ("  anchors: " + (($rows.Keys | ForEach-Object { "$_=$($rows[$_])" }) -join ' ')) -ForegroundColor DarkGray

$out  = & $Exe lint $file 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'uObrIntf\.pas:(\d+):\d+\s+\[\w+\]\s+overwrite-before-read') |
          ForEach-Object { [int]$_.Groups[1].Value })
function Proc-Of([int]$Row) {
  $best = '(none)'
  foreach ($n in $rows.Keys) { if ($Row -ge $rows[$n]) { $best = $n } }
  $best
}
function Rows-In([string]$P) { ($hits | Where-Object { (Proc-Of $_) -eq $P }) -join ',' }
Write-Host ("  overwrite-before-read at rows: " + (($hits -join ',') -replace '^$','(none)')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Releasing an interface reference is not a dead store' -ForegroundColor Cyan
Check 'ReleaseRoundTrip: LCfg := nil between two uses is NOT reported' `
  ((Rows-In 'ReleaseRoundTrip') -eq '') "rows=$(Rows-In 'ReleaseRoundTrip')"
Check 'ReleaseThenExit: an early release is NOT reported' `
  ((Rows-In 'ReleaseThenExit') -eq '') "rows=$(Rows-In 'ReleaseThenExit')"

Write-Host ''
Write-Host 'POSITIVE CONTROLS -- the rule must still work' -ForegroundColor Cyan
Check 'ObjectNilDead: := nil on a CLASS local STILL fires' `
  ((Rows-In 'ObjectNilDead') -ne '') "rows=$(Rows-In 'ObjectNilDead')"
Check 'IntfNonNilDead: a non-nil interface dead store STILL fires' `
  ((Rows-In 'IntfNonNilDead') -ne '') "rows=$(Rows-In 'IntfNonNilDead')"
Check 'GenuineDead: an ordinary dead store STILL fires' `
  ((Rows-In 'GenuineDead') -ne '') "rows=$(Rows-In 'GenuineDead')"

if ((Rows-In 'ObjectNilDead') -eq '' -or (Rows-In 'IntfNonNilDead') -eq '' -or
    (Rows-In 'GenuineDead') -eq '') {
  Write-Host '  !! A control failed. The two assertions above prove NOTHING -- they' -ForegroundColor Yellow
  Write-Host '  !! would pass with the rule switched off, and with the cheap fix' -ForegroundColor Yellow
  Write-Host '  !! (exempt every := nil) that this guard exists to reject.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
