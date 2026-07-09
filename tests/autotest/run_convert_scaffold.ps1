<#
  run_convert_scaffold.ps1 -- convert-scaffold verb headless test (Track 3
  Batch 1, Task 3). Auto-generates a VALID reFind-superset conversion-rules
  file from the REAL deep-property trees of a From type and a To type (both
  enumerated by Task 1's BuildPropTree), pre-filling the matches it can infer
  and leaving only genuine ambiguities as '???'.

  FIXTURE (ConvFix.pas) is engineered to force all three scaffolder cases:
    * TFrom.Color and TFrom.Sub.Color BOTH have the leaf name 'Color'
      (Integer). TTo.Color (Integer) therefore has MULTIPLE plausible F
      sources -> an AMBIGUOUS '#link Color <- ???' plus a 'candidates:' note.
    * TTo.Caption (string) has NO F source of a compatible leaf/type -> a
      '#default Caption = ???'.
    * TFrom.Gone (Integer) has NO T counterpart -> a 'DROPPED' note.
    * At least one T path matches exactly ONE compatible F path -> a CONCRETE
      '#link X <- Y' with no '???' (here TTo.Sub <- TFrom.Sub, both TSub;
      and the deep leaf TTo.Sub.Color <- TFrom.Sub.Color, unambiguous within
      the Sub subtree by full-path leaf match).

  Then we feed the emitted file back through convert-validate and assert it
  EXITS 0 -- the '???' stubs are tolerated by the validator, and every
  concrete path must exist in the real trees, so a clean round-trip proves the
  scaffolder emits only VALID rules.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-convert-scaffold by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-scaffold"
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

$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ---------------------------------------------------------------------------
# Build + index the ConvFix fixture (F=TFrom, T=TTo)
# ---------------------------------------------------------------------------
$FixBody = @'
unit ConvFix;

interface

type
  TSub = class(TPersistent)
  private
    FColor: Integer;
  published
    property Color: Integer read FColor write FColor;
  end;

  TFrom = class(TPersistent)
  private
    FColor: Integer;
    FSub: TSub;
    FGone: Integer;
  published
    property Color: Integer read FColor write FColor;
    property Sub: TSub read FSub write FSub;
    property Gone: Integer read FGone write FGone;
  end;

  TTo = class(TPersistent)
  private
    FCaption: string;
    FColor: Integer;
    FSub: TSub;
  published
    property Caption: string read FCaption write FCaption;
    property Color: Integer read FColor write FColor;
    property Sub: TSub read FSub write FSub;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $work 'ConvFix.pas') $FixBody

$db = Join-Path $WorkDir 'convfix.sqlite'
Write-Host 'Indexing ConvFix fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

# ---------------------------------------------------------------------------
# convert-scaffold --from ConvFix.TFrom --to ConvFix.TTo -> stdout
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold --from ConvFix.TFrom --to ConvFix.TTo (stdout)' -ForegroundColor Cyan
$scafRaw = (& $Exe convert-scaffold --from 'ConvFix.TFrom' --to 'ConvFix.TTo' --db $db) -join "`n"
$scafExit = $LASTEXITCODE
Check 'scaffold exits 0' ($scafExit -eq 0) "exit=$scafExit"
Write-Host $scafRaw -ForegroundColor DarkGray

# header
Check 'header #convert TFrom -> TTo' ($scafRaw -match '#convert\s+ConvFix\.TFrom\s+->\s+ConvFix\.TTo') "raw=$scafRaw"

# CONCRETE link with no ??? -- Sub <- Sub (or the deep Sub.Color <- Sub.Color).
# Match a '#link <path> <- <path>' whose RHS is NOT '???'.
$concrete = ($scafRaw -split "`n") | Where-Object { $_ -match '^\s*#link\s+\S+\s+<-\s+(?!\?\?\?)\S' }
Check 'at least one CONCRETE #link (no ???)' ($concrete.Count -ge 1) "matches=$($concrete -join ' ; ')"

# AMBIGUOUS link -> '#link Color <- ???' followed by a candidates: note
Check 'ambiguous #link Color <- ???' ($scafRaw -match '#link\s+Color\s+<-\s+\?\?\?') "raw=$scafRaw"
Check 'candidates: note present' ($scafRaw -match '#note\s+candidates:') "raw=$scafRaw"

# DROPPED note for TFrom.Gone (no T target)
Check 'DROPPED note for Gone' ($scafRaw -match '#note\s+DROPPED\s+Gone') "raw=$scafRaw"

# ---------------------------------------------------------------------------
# Round-trip: write the emitted file and validate it -> MUST exit 0
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold --out (write file), then convert-validate round-trip' -ForegroundColor Cyan
$emitted = Join-Path $WorkDir 'emitted-rules.txt'
$outOut = & $Exe convert-scaffold --from 'ConvFix.TFrom' --to 'ConvFix.TTo' --out $emitted --db $db 2>&1
$outExit = $LASTEXITCODE
Check 'scaffold --out exits 0' ($outExit -eq 0) "exit=$outExit; $($outOut -join ' | ')"
Check 'emitted file exists' (Test-Path $emitted) "path=$emitted"

Push-Location $WorkDir
try {
  $valOut = (& $Exe convert-validate --rules $emitted --from 'ConvFix.TFrom' --to 'ConvFix.TTo' --db $db) -join "`n"
  $valExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'round-trip convert-validate exits 0' ($valExit -eq 0) "exit=$valExit; out=$valOut"

# ---------------------------------------------------------------------------
# Bad-args / unresolved-type exit codes
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold (no --from/--to)' -ForegroundColor Cyan
$noArgsOut = ((& $Exe convert-scaffold 2>&1) -join "`n")
$noArgsExit = $LASTEXITCODE
Check 'missing --from/--to exit 2' ($noArgsExit -eq 2) "exit=$noArgsExit"

Write-Host 'convert-scaffold --from <bogus> --to ConvFix.TTo' -ForegroundColor Cyan
$badFromOut = ((& $Exe convert-scaffold --from 'ConvFix.TNope' --to 'ConvFix.TTo' --db $db 2>&1) -join "`n")
$badFromExit = $LASTEXITCODE
Check 'unresolved --from exit 1' ($badFromExit -eq 1) "exit=$badFromExit"
Check 'unresolved --from names the type' ($badFromOut -match 'ConvFix\.TNope') "out=$badFromOut"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
