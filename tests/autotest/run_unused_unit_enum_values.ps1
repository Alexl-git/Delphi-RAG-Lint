<#
  run_unused_unit_enum_values.ps1 -- unused-unit-in-uses must count an ENUM
  VALUE as a use of the unit that declares its enum type.

  THE DEFECT THIS PINS (converter report 2026-10-11, INBOX
  ...-converter-to-engine-unused-unit-enum-values):
    ConvRules.WorkListTab.pas uses Vcl.Controls only through enum values --
    `LRow.Align:= alTop;`, `bvNone` -- and the rule called the import dead.
    Removing it fails the build with E2003.

  WHERE THE USE WAS LOST (measured, not assumed): the extractor DOES record a
  ref for every enum value (refs.name_text 'alTop', kind read) -- premise P1
  below asserts it on this fixture. The rule's EXPORT SURFACE was the unit's
  interface-level children by name; an enum value is a child of its ENUM, one
  level further down, so it was never in the set. A read-time fix in the lint
  rule; no extractor or resolver change.

  THE CONTROLS:
    * a unit imported and genuinely unused IS still flagged (the fix must not
      silence the rule);
    * a unit used through a TYPE is still not flagged (the old path still works).

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-uuenum-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== unused-unit-in-uses: enum values are uses of their unit ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$fixDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $fixDir | Out-Null
function W([string]$n, [string]$t) {
  [IO.File]::WriteAllText((Join-Path $fixDir $n), (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}

# uUeEnums: used ONLY through enum values (and one is a typed-const initialiser)
W 'uUeEnums.pas' @'
unit uUeEnums;

interface

type
  TUeAlign = (ueNone, ueTop, ueClient);
  TUeBevel = (ubNone, ubRaised);

implementation

end.
'@
# uUeTypes: used through a TYPE -- the control the old path already handled
W 'uUeTypes.pas' @'
unit uUeTypes;

interface

type
  TUeThing = class
  end;

implementation

end.
'@
# uUeDead: imported and genuinely unused -- must stay flagged
W 'uUeDead.pas' @'
unit uUeDead;

interface

type
  TUeNobody = (unA, unB);

const
  UE_NOBODY = 1;

implementation

end.
'@
W 'uUeConsumer.pas' @'
unit uUeConsumer;

interface

uses
  uUeEnums, uUeTypes, uUeDead;

type
  TUePanel = class
  public
    Align: Integer;
    procedure Run(AThing: TUeThing);
  end;

implementation

procedure TUePanel.Run(AThing: TUeThing);
var
  B: Integer;
begin
  Align:= Ord(ueTop);
  B:= Ord(ubNone);
  if B = Align then Exit;
end;

end.
'@

$db      = Join-Path $WorkDir 'uuenum.sqlite'
$errFile = Join-Path $WorkDir 'stderr.txt'
& $Exe index $fixDir --db $db 2>$errFile | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: indexing the fixture failed ($LASTEXITCODE)" -ForegroundColor Red
  Write-Host (Get-Content -LiteralPath $errFile -Raw)
  exit 1
}

Write-Host ''
Write-Host '-- premise: the EXTRACTOR records the enum-value refs (so the gap is the rule''s)' -ForegroundColor Cyan
$p1 = (& $Exe sql --db $db --query "select count(*) as n from refs where name_text in ('ueTop','ubNone')" 2>$errFile | Out-String)
Check 'P1 refs hold ueTop and ubNone from uUeConsumer' ($p1 -match '(?m)^\s*2\s*$') (($p1 -split "`r?`n" | Where-Object { $_ -match '\S' }) -join ' / ')
$p2 = (& $Exe sql --db $db --query "select count(*) as n from symbols where kind = 'enum_value' and name in ('ueTop','ubNone')" 2>$errFile | Out-String)
Check 'P2 the symbols table holds them as enum_value children' ($p2 -match '(?m)^\s*2\s*$') (($p2 -split "`r?`n" | Where-Object { $_ -match '\S' }) -join ' / ')

Write-Host ''
Write-Host '-- the false positive: a unit used only through enum values' -ForegroundColor Cyan
$out = (& $Exe lint-project --db $db --rule unused-unit-in-uses 2>$errFile | Out-String) -replace "`r`n", "`n"
Write-Host ("  findings:`n    " + (($out -split "`n" | Where-Object { $_ -match 'unused-unit-in-uses' }) -join "`n    ")) -ForegroundColor DarkGray
Check 'E1 a unit used only through ENUM VALUES is not flagged' ($out -notmatch "Unit 'uUeEnums'") ''
Check 'E2 CONTROL: a unit used through a TYPE is not flagged' ($out -notmatch "Unit 'uUeTypes'") ''
Check 'E3 CONTROL: a genuinely unused import IS still flagged (its own enum values do not keep it alive)' `
  ($out -match "Unit 'uUeDead'") ''

$out2 = (& $Exe lint (Join-Path $fixDir 'uUeConsumer.pas') --db $db 2>$errFile | Out-String) -replace "`r`n", "`n"
Check 'E4 the per-file lint agrees (it runs the same project rule narrowed to the file)' `
  (($out2 -notmatch "Unit 'uUeEnums'") -and ($out2 -match "Unit 'uUeDead'")) ''

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
