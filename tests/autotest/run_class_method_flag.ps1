<#
  run_class_method_flag.ps1 -- the index tells a CLASS constructor / destructor
  (and every other `class` routine) from an instance one.

  THE DEFECT THIS PINS (docs\INBOX-class-ctor-symbol-kind.md, backlog
  CLASSCTOR-KIND). Measured on the 1.39.2 engine with the fixture below:

      class constructor Create   -> kind=method        (not even constructor)
      class destructor  Destroy  -> kind=method
      constructor CreateInst     -> kind=constructor
      class procedure Touch      -> kind=method
      procedure Plain            -> kind=method

  `symbols` had no class-member marker at all, so `class constructor Create`
  and `procedure Create` were the same row. The WalkDeclProc kind switch read
  Child(0), which for a class routine is the `class` keyword, so the
  kConstructor / kDestructor token behind it was never seen.

  THE FIX: symbols.is_class_method (1 = declared with the `class` keyword),
  and a class constructor / destructor carries kind constructor / destructor.
  Class procedures, functions and operators STAY `method` (the
  run_ctor_dtor_kind_guard case C contract).

  Surfaces: query --json is_class_method, outline (json is_class_method, text
  `[class]`), hover (json kind `class constructor`).

  Positive controls: the instance constructor / destructor and the plain
  procedure must read is_class_method=false and must NOT be tagged `[class]`;
  a guard that only looked for `true` would pass with every row flagged.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_class_method_flag_$PID"
)
try {

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host 'run_class_method_flag -- class constructors are class constructors' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$unit = Join-Path $WorkDir 'ClsCtor.pas'
$src = @(
  'unit ClsCtor;'
  ''
  'interface'
  ''
  'type'
  '  TReg = class'
  '  public'
  '    class constructor Create;'
  '    class destructor Destroy;'
  '    constructor CreateInst;'
  '    destructor DestroyInst;'
  '    class function Make: TReg; static;'
  '    class procedure Touch;'
  '    procedure Plain;'
  '  end;'
  ''
  '  TVec = record'
  '    X: Integer;'
  '    class operator Add(const A, B: TVec): TVec;'
  '  end;'
  ''
  'implementation'
  ''
  'class constructor TReg.Create;'
  'begin'
  'end;'
  ''
  'class destructor TReg.Destroy;'
  'begin'
  'end;'
  ''
  'constructor TReg.CreateInst;'
  'begin'
  'end;'
  ''
  'destructor TReg.DestroyInst;'
  'begin'
  'end;'
  ''
  'class function TReg.Make: TReg;'
  'begin'
  '  Result := nil;'
  'end;'
  ''
  'class procedure TReg.Touch;'
  'begin'
  'end;'
  ''
  'procedure TReg.Plain;'
  'begin'
  'end;'
  ''
  'class operator TVec.Add(const A, B: TVec): TVec;'
  'begin'
  '  Result.X := A.X + B.X;'
  'end;'
  ''
  'end.'
) -join "`r`n"
[System.IO.File]::WriteAllText($unit, $src + "`r`n", [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'clsctor.sqlite'
& $Exe index $unit --db $db *> $null
Check 'fixture indexed' (Test-Path $db) $db
if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

function RowOf([string]$name) {
  $j = & $Exe query --name $name --db $db --json 2>$null | Out-String
  $o = $null; try { $o = $j | ConvertFrom-Json } catch { }
  if ($null -eq $o) { return $null }
  return @($o | Where-Object { $_.name -eq $name })[0]
}
function Flag($row) {
  if ($null -eq $row) { return '<not found>' }
  if ($null -eq $row.PSObject.Properties['is_class_method']) { return '<absent>' }
  return [string]$row.is_class_method
}

# ---- CASE A: query --json kind + is_class_method -- the defect -------------
Write-Host ''
Write-Host 'CASE A: class constructor / destructor (query --json)' -ForegroundColor Cyan
$rC = RowOf 'Create'; $rD = RowOf 'Destroy'
Check 'class constructor Create is kind=constructor' ($rC.kind -eq 'constructor') "got: $($rC.kind)"
Check 'class constructor Create is_class_method=True' ((Flag $rC) -eq 'True') "got: $(Flag $rC)"
Check 'class destructor Destroy is kind=destructor'  ($rD.kind -eq 'destructor')  "got: $($rD.kind)"
Check 'class destructor Destroy is_class_method=True' ((Flag $rD) -eq 'True') "got: $(Flag $rD)"

# ---- CASE B: other class routines keep kind method, carry the flag ---------
Write-Host ''
Write-Host 'CASE B: class function / procedure / operator stay method, flagged' -ForegroundColor Cyan
foreach ($n in @('Make', 'Touch', 'Add')) {
  $r = RowOf $n
  Check "class routine $n is kind=method" ($r.kind -eq 'method') "got: $($r.kind)"
  Check "class routine $n is_class_method=True" ((Flag $r) -eq 'True') "got: $(Flag $r)"
}

# ---- CASE C: POSITIVE CONTROL -- instance routines are NOT flagged ---------
Write-Host ''
Write-Host 'CASE C: positive control -- instance routines read is_class_method=False' -ForegroundColor Cyan
$rCI = RowOf 'CreateInst'; $rDI = RowOf 'DestroyInst'; $rP = RowOf 'Plain'
Check 'constructor CreateInst is kind=constructor' ($rCI.kind -eq 'constructor') "got: $($rCI.kind)"
Check 'constructor CreateInst is_class_method=False' ((Flag $rCI) -eq 'False') "got: $(Flag $rCI)"
Check 'destructor DestroyInst is kind=destructor' ($rDI.kind -eq 'destructor') "got: $($rDI.kind)"
Check 'destructor DestroyInst is_class_method=False' ((Flag $rDI) -eq 'False') "got: $(Flag $rDI)"
Check 'procedure Plain is_class_method=False' ((Flag $rP) -eq 'False') "got: $(Flag $rP)"

# ---- CASE D: outline surfaces the flag ------------------------------------
Write-Host ''
Write-Host 'CASE D: outline --json / text' -ForegroundColor Cyan
$oj = @()
try { $oj = @((& $Exe outline --file $unit --db $db --format json 2>$null | Out-String) | ConvertFrom-Json) } catch { }
$oC  = @($oj | Where-Object { $_.qname -eq 'ClsCtor.TReg.Create' })[0]
$oCI = @($oj | Where-Object { $_.qname -eq 'ClsCtor.TReg.CreateInst' })[0]
Check 'outline json: class ctor is_class_method=True' ((Flag $oC) -eq 'True') "got: $(Flag $oC)"
Check 'outline json: instance ctor is_class_method=False' ((Flag $oCI) -eq 'False') "got: $(Flag $oCI)"
$ot = @(& $Exe outline --file $unit --db $db 2>$null)
$tC  = @($ot | Where-Object { $_ -match '\sClsCtor\.TReg\.Create\s' })[0]
$tCI = @($ot | Where-Object { $_ -match '\sClsCtor\.TReg\.CreateInst\s' })[0]
Check 'outline text: class ctor row tagged [class]' ($tC -match '\[class\]') "row: $tC"
Check 'outline text: instance ctor row NOT tagged [class]' (($null -ne $tCI) -and ($tCI -notmatch '\[class\]')) "row: $tCI"

# ---- CASE E: hover names a class constructor -------------------------------
Write-Host ''
Write-Host 'CASE E: hover --format json kind' -ForegroundColor Cyan
$h = $null; try { $h = (& $Exe hover --qname ClsCtor.TReg.Create --db $db --format json 2>$null | Out-String) | ConvertFrom-Json } catch { }
$hi = $null; try { $hi = (& $Exe hover --qname ClsCtor.TReg.CreateInst --db $db --format json 2>$null | Out-String) | ConvertFrom-Json } catch { }
Check 'hover: class ctor kind is "class constructor"' ($h.kind -eq 'class constructor') "got: $($h.kind)"
Check 'hover: instance ctor kind is "constructor"' ($hi.kind -eq 'constructor') "got: $($hi.kind)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\draglint_class_method_flag_$PID")) { if (Test-Path -LiteralPath $d23) { [System.IO.Directory]::Delete($d23, $true) } }
}
