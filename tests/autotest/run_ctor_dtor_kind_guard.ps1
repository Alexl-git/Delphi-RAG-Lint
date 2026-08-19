<#
  run_ctor_dtor_kind_guard.ps1 -- a constructor declared inside a class must be
  indexed as `constructor`, and a destructor as `destructor`.

  THE DEFECT THIS PINS (owner, 2026-08-19, live IDE). Hovering
  TEurekaExceptionInfo.Create showed "Create method" in plain text where RAD
  Studio's own Help Insight showed a CONSTRUCTOR in the keyword colour. The
  popup was faithfully rendering a wrong stored fact.

  MEASURED before the fix, on library-Win64.sqlite:

      symbols named `Create` : 18,630
      kind = method          : 18,616
      kind = constructor     :      2   <- both UNIT-LEVEL, not class members
      kind = destructor      :      0

  Root cause: the extractor took `if AAsMethod then Kind := skMethod` and only
  inspected the kConstructor / kDestructor token on the FREE-routine branch. So
  the kind was correct exactly when the routine was not a class member, which
  is the rare case. That is why the two survivors are unit-level -- and why a
  fixture with a free-standing constructor would pass against the broken build.
  Case A therefore uses CLASS MEMBERS, which is where it fails.

  Case C is the positive control: a class procedure and a class function must
  STILL be `method`. Rules, queries and the structure view across the product
  test class members for skMethod, so a "fix" that split those out would break
  far more than it repaired -- and would satisfy cases A and B while doing it.

  RED PROOF (recorded 2026-08-19): run with
  -Exe third_party\dll-win64\drag-lint.exe (the pre-fix engine); both members
  in case A come back as `method`.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_ctor_kind_guard"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host 'run_ctor_dtor_kind_guard -- constructors are constructors, not methods' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$unit = Join-Path $WorkDir 'CtorKinds.pas'
$src = @(
  'unit CtorKinds;'
  ''
  'interface'
  ''
  'type'
  '  TWidget = class'
  '    public'
  '      constructor Create(const AName: string);'
  '      destructor  Destroy; override;'
  '      procedure   Reset;'
  '      function    Describe: string;'
  '  end;'
  ''
  'constructor MakeLoose(AValue: Integer);'
  ''
  'implementation'
  ''
  'constructor TWidget.Create(const AName: string);'
  'begin'
  'end;'
  ''
  'destructor TWidget.Destroy;'
  'begin'
  '  inherited;'
  'end;'
  ''
  'procedure TWidget.Reset;'
  'begin'
  'end;'
  ''
  'function TWidget.Describe: string;'
  'begin'
  '  Result := '''';'
  'end;'
  ''
  'constructor MakeLoose(AValue: Integer);'
  'begin'
  'end;'
  ''
  'end.'
) -join "`r`n"
[System.IO.File]::WriteAllText($unit, $src + "`r`n", [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'ctorkinds.sqlite'
& $Exe index $unit --db $db *> $null
Check 'fixture indexed' (Test-Path $db) $db
if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

function KindOf([string]$name) {
  $j = & $Exe query --name $name --db $db --json 2>$null | Out-String
  $o = $null; try { $o = $j | ConvertFrom-Json } catch { }
  if ($null -eq $o) { return '<no json>' }
  $rows = @($o | Where-Object { $_.name -eq $name })
  if ($rows.Count -eq 0) { return '<not found>' }
  return $rows[0].kind
}

# ---- CASE A: class members -- the defect ----------------------------------
Write-Host ''
Write-Host 'CASE A: a constructor and destructor declared INSIDE a class' -ForegroundColor Cyan
$kCreate  = KindOf 'Create'
$kDestroy = KindOf 'Destroy'
Check 'TWidget.Create is kind=constructor' ($kCreate  -eq 'constructor') "got: $kCreate"
Check 'TWidget.Destroy is kind=destructor' ($kDestroy -eq 'destructor')  "got: $kDestroy"

# ---- CASE B: the unit-level form must not regress -------------------------
Write-Host ''
Write-Host 'CASE B: a unit-level constructor (this already worked)' -ForegroundColor Cyan
$kLoose = KindOf 'MakeLoose'
Check 'MakeLoose is kind=constructor' ($kLoose -eq 'constructor') "got: $kLoose"

# ---- CASE C: POSITIVE CONTROL ---------------------------------------------
Write-Host ''
Write-Host 'CASE C: positive control -- ordinary class members stay `method`' -ForegroundColor Cyan
$kReset    = KindOf 'Reset'
$kDescribe = KindOf 'Describe'
Check 'a class procedure is still kind=method' ($kReset    -eq 'method') "got: $kReset"
Check 'a class function  is still kind=method' ($kDescribe -eq 'method') "got: $kDescribe"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
