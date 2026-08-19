<#
  run_framework_member_scope_guard.ps1 -- a member lookup must not answer from
  the GUI framework the project does not use.

  THE DEFECT THIS PINS (owner, 2026-08-19, live IDE, DataCopy):

      uMainZeissCopy.pas:2305   FRetryTimer.Enabled := False;

  Hovering `Enabled` answered `FMX.Types.TTimer.Enabled` in a VCL project.
  Following the declaration was CORRECT (`FRetryTimer: TTimer` reported VCL) --
  only the member lookup went wrong, which is the dangerous shape: the answer
  names a real type, carries a real signature, and is wrong.

  Cause: both frameworks declare TTimer, both declarations have members, and
  the resolver took "the first candidate with members" in store order. FMX
  sorts before Vcl, so the framework the file does not use won every time.

  TWO RULES NOW DECIDE IT, and this guard exercises both separately:

    CASE A  the hovering file's own `uses` -- a candidate declared in a unit
            the file actually uses wins outright.
    CASE B  the PROJECT's framework, from unit_uses (ISymbolStore.
            GuiFrameworkInUse). Delphi does not mix VCL and FMX in one project,
            so a candidate from the other framework is not a worse answer, it
            is not an answer. This catches the cases rule A cannot see, where
            the type arrives through a form or an ancestor rather than a direct
            `uses` -- so case B's consumer deliberately does NOT name the unit
            declaring TTimer in its own uses clause.

  CASE C is the mirror image: an FMX project must resolve to FMX. Without it a
  "fix" that simply always preferred Vcl would pass A and B and be nonsense.

  RED PROOF (recorded 2026-08-19) against the pre-fix engine, on the owner's
  real file rather than this fixture:

      typeat uMainZeissCopy.pas:2305:19
        old -> Resolved: FMX.Types.TTimer.Enabled
        new -> Resolved: Vcl.ExtCtrls.TTimer.Enabled
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_framework_scope_guard"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function W([string]$path, [string[]]$lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
}

Write-Host 'run_framework_member_scope_guard -- VCL projects get VCL members' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- the two framework units, both declaring TTimer with members ------------
# Real namespace names, because the project-framework rule keys on the Vcl./FMX.
# unit-scope prefixes exactly as the product does.
$lib = Join-Path $WorkDir 'lib'
New-Item -ItemType Directory $lib -Force | Out-Null

W (Join-Path $lib 'Vcl.ExtCtrls.pas') @(
  'unit Vcl.ExtCtrls;', '', 'interface', '', 'type',
  '  TTimer = class', '    public', '      Enabled : Boolean;',
  '      Interval: Integer;', '      procedure Restart;', '  end;', '',
  'implementation', '', 'procedure TTimer.Restart;', 'begin', 'end;', '', 'end.')

W (Join-Path $lib 'FMX.Types.pas') @(
  'unit FMX.Types;', '', 'interface', '', 'type',
  '  TTimer = class', '    public', '      Enabled : Boolean;',
  '      Interval: Integer;', '      procedure Restart;', '  end;', '',
  'implementation', '', 'procedure TTimer.Restart;', 'begin', 'end;', '', 'end.')

$libDb = Join-Path $WorkDir 'lib.sqlite'
& $Exe index $lib --db $libDb *> $null
Check 'library fixture indexed (both TTimer declarations)' (Test-Path $libDb) $libDb

# --- CASE A: the consumer names the unit in its own uses --------------------
$vclDir = Join-Path $WorkDir 'vclapp'
New-Item -ItemType Directory $vclDir -Force | Out-Null
W (Join-Path $vclDir 'VclConsumer.pas') @(
  'unit VclConsumer;', '', 'interface', '', 'uses', '  Vcl.ExtCtrls', '  ;', '',
  'implementation', '', 'procedure Go;', 'var', '  T: TTimer;', 'begin',
  '  T.Enabled := False;', 'end;', '', 'end.')
# A second VCL unit so the PROJECT reads as VCL by unit_uses count.
W (Join-Path $vclDir 'VclOther.pas') @(
  'unit VclOther;', '', 'interface', '', 'uses', '  Vcl.ExtCtrls', '  ;', '',
  'implementation', '', 'end.')
# CASE B's consumer: uses only VclOther, NOT the unit declaring TTimer, so the
# uses rule cannot decide and only the project-framework rule can.
W (Join-Path $vclDir 'VclIndirect.pas') @(
  'unit VclIndirect;', '', 'interface', '', 'uses', '  VclOther', '  ;', '',
  'implementation', '', 'procedure Go2;', 'var', '  T: TTimer;', 'begin',
  '  T.Enabled := False;', 'end;', '', 'end.')

$vclDb = Join-Path $WorkDir 'vclapp.sqlite'
& $Exe index $vclDir --db $vclDb *> $null
Check 'VCL project fixture indexed' (Test-Path $vclDb) $vclDb

function ResolvedAt([string]$file, [int]$line, [int]$col, [string]$projDb) {
  $out = & $Exe typeat "${file}:${line}:${col}" --db $projDb --db $libDb 2>$null | Out-String
  $m = [regex]::Match($out, 'Resolved:\s*(\S+)')
  if ($m.Success) { return $m.Groups[1].Value }
  return "<unresolved> $($out.Trim())"
}

Write-Host ''
Write-Host 'CASE A: the file USES Vcl.ExtCtrls -- that decides it' -ForegroundColor Cyan
$a = ResolvedAt (Join-Path $vclDir 'VclConsumer.pas') 15 8 $vclDb
Check 'Enabled resolves to the VCL TTimer' ($a -like 'Vcl.ExtCtrls.TTimer.Enabled') "got: $a"

Write-Host ''
Write-Host 'CASE B: the file does NOT use the declaring unit -- the PROJECT framework decides' -ForegroundColor Cyan
$b = ResolvedAt (Join-Path $vclDir 'VclIndirect.pas') 15 8 $vclDb
Check 'Enabled still resolves to the VCL TTimer' ($b -like 'Vcl.ExtCtrls.TTimer.Enabled') "got: $b"

# --- CASE C: the mirror image ----------------------------------------------
$fmxDir = Join-Path $WorkDir 'fmxapp'
New-Item -ItemType Directory $fmxDir -Force | Out-Null
W (Join-Path $fmxDir 'FmxConsumer.pas') @(
  'unit FmxConsumer;', '', 'interface', '', 'uses', '  FMX.Types', '  ;', '',
  'implementation', '', 'procedure Go;', 'var', '  T: TTimer;', 'begin',
  '  T.Enabled := False;', 'end;', '', 'end.')
W (Join-Path $fmxDir 'FmxOther.pas') @(
  'unit FmxOther;', '', 'interface', '', 'uses', '  FMX.Types', '  ;', '',
  'implementation', '', 'end.')
$fmxDb = Join-Path $WorkDir 'fmxapp.sqlite'
& $Exe index $fmxDir --db $fmxDb *> $null

Write-Host ''
Write-Host 'CASE C: MIRROR IMAGE -- an FMX project must get FMX' -ForegroundColor Cyan
$c = ResolvedAt (Join-Path $fmxDir 'FmxConsumer.pas') 15 8 $fmxDb
Check 'Enabled resolves to the FMX TTimer' ($c -like 'FMX.Types.TTimer.Enabled') "got: $c"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
