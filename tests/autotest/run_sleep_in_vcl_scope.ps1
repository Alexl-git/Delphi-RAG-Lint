<#
  run_sleep_in_vcl_scope.ps1 -- `sleep-in-vcl` must fire where a VCL UI can
  exist, and must NOT fire in headless code.

  THE BUG (reported by DataCopy, 2026-08-31)
  ------------------------------------------
  The rule is an external .scm whose entire body is:

      ((exprCall entity: (identifier) @fn) @warn (#eq? @fn "Sleep"))

  It matched ANY `Sleep(` call. The word VCL appeared only in its message. So a
  DUnitX folder-watcher test -- headless, no message loop, a uses clause naming
  no VCL unit -- collected 11 findings that could not be true, and the reviewer
  hand-wrote 11 `dl:ok` markers to argue with them.

  THE FIX
  -------
  Scope declared in the sidecar json as `require_file_text`, ANY-of:
    "vcl."       -- the unit references a VCL unit
    "{$r *.dfm}" -- the unit IS a form/frame/data module, whatever the uses
                    clause style (legacy code says `uses Forms`, not `Vcl.Forms`)

  WHY BOTH DIRECTIONS ARE ASSERTED
  --------------------------------
  A test that only asserted "the false finding is gone" would pass with the rule
  switched off entirely, which is the failure this repo has hit before. Cases 1
  and 2 are the positive control: the rule must still fire on real VCL code, by
  both routes into scope.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-sleep-in-vcl-scope"
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

function WriteFixture([string]$Name, [string]$Body) {
  $p = Join-Path $WorkDir $Name
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($p, $norm, [System.Text.Encoding]::ASCII)
  return $p
}

# 1. In scope by a namespaced VCL uses clause.
$vclUnit = WriteFixture 'SleepVclForm.pas' @"
unit SleepVclForm;

interface

uses
  Vcl.Forms, System.SysUtils;

procedure Wait;

implementation

procedure Wait;
begin
  Sleep(100);
end;

end.
"@

# 2. In scope because the unit IS a form -- legacy, non-namespaced uses clause.
$dfmUnit = WriteFixture 'SleepLegacyForm.pas' @"
unit SleepLegacyForm;

interface

uses
  Forms, Classes;

type
  TfrmLegacy = class(TForm)
  public
    procedure Wait;
  end;

implementation

{`$R *.dfm}

procedure TfrmLegacy.Wait;
begin
  Sleep(250);
end;

end.
"@

# 3. OUT of scope: headless test unit, no VCL anywhere. This is DataCopy's case.
$headlessUnit = WriteFixture 'SleepHeadlessTest.pas' @"
unit SleepHeadlessTest;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWatcherTests = class
  public
    [Test] procedure Watcher_settles;
  end;

implementation

uses
  System.SysUtils, System.Classes;

procedure TWatcherTests.Watcher_settles;
begin
  Sleep(100);
  Sleep(200);
end;

end.
"@

function SleepLines([string]$Path) {
  $out = @()
  foreach ($line in (& $Exe lint $Path 2>$null)) {
    if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+sleep-in-vcl:') { $out += [int]$Matches[1] }
  }
  return @($out | Sort-Object -Unique)
}

$firedVcl      = SleepLines $vclUnit
$firedDfm      = SleepLines $dfmUnit
$firedHeadless = SleepLines $headlessUnit

Write-Host ''
Write-Host 'POSITIVE CONTROL -- the rule must still fire on VCL code' -ForegroundColor Cyan
Check 'namespaced `uses Vcl.Forms` fires' ($firedVcl.Count -eq 1) "lines: $($firedVcl -join ', ')"
Check 'a form unit with {$R *.dfm} fires' ($firedDfm.Count -eq 1) "lines: $($firedDfm -join ', ')"

Write-Host ''
Write-Host 'THE DEFECT -- headless code must be silent' -ForegroundColor Cyan
Check 'headless DUnitX unit fires 0 times' ($firedHeadless.Count -eq 0) "lines: $($firedHeadless -join ', ')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
