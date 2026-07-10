<#
  run_convert_rules.ps1 -- convert-validate verb headless test (Track 3 Batch 1,
  Task 2). Exercises the reFind-superset conversion-rules DSL parser + the
  index-aware path validator.

  PART (a) PARSE: a rules string covering EVERY directive (adopted reFind lines
    #unuse / #remove / #migrate, plus the drag-lint superset #convert / #link /
    #default / #note, and a raw PCRE ' -> ' escape-hatch line). Via
    convert-validate --rules <f> --print-parsed we assert the parsed rule COUNT
    and a couple of field values (migrate New='TFDTable', unuse UnitName='BDE').
    No trees needed -- parse-only exits 0.

  PART (b) VALIDATE: reuse the PropFix fixture from Task 1 -- unit PropFix;
    TInner(TPersistent) has scalar Shade:Integer; TOuter(TPersistent) has
    class-typed Inner:TInner and scalar Name:string. Index it, then:
      - a rules file with '#link Name <- Inner.Shade' validates OK (both paths
        exist in the --to / --from trees) -> exit 0, output 'OK'.
      - a rules file with '#link Bogus.Path <- Name' yields exit 1 and the error
        text NAMES 'Bogus.Path' (Bogus.Path is not a TOuter property).
      - an UNKNOWN '#directive' line yields exit 1 (captured parse error).
      - a missing --rules file -> exit 2 (bad args); an unreadable path -> exit 2.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-convert-rules by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-rules"
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
# PART (a): PARSE every directive via --print-parsed (no trees needed)
# ---------------------------------------------------------------------------
$RulesAll = @'
// this comment line is ignored
; so is this one
#unuse BDE
#remove SessionName
#remove DFM: Origin
#migrate TTable -> TFDTable, FireDAC.Comp.Client
#convert TTable -> TFDTable, FireDAC.Comp.Client
#link Name <- Inner.Shade
#default Name = 'x'
#note carry this human text
#ignore TabOrder
FindThis -> ReplaceThat
'@
$rulesAllFile = Join-Path $WorkDir 'rules-all.txt'
Write-Ascii $rulesAllFile $RulesAll

Write-Host 'convert-validate --rules rules-all.txt --print-parsed' -ForegroundColor Cyan
$parsedRaw = (& $Exe convert-validate --rules $rulesAllFile --print-parsed) -join "`n"
$parsedExit = $LASTEXITCODE
Check 'parse-only exits 0' ($parsedExit -eq 0) "exit=$parsedExit"
Check 'print-parsed reports 10 rules' ($parsedRaw -match 'parsed 10 rule') "raw=$parsedRaw"
# reFind-adopted directives + field values
Check 'unuse UnitName=BDE'     ($parsedRaw -match 'unuse.*BDE')                 "raw=$parsedRaw"
Check 'remove PropName=SessionName' ($parsedRaw -match 'remove.*SessionName')  "raw=$parsedRaw"
Check 'remove DFM-only Origin' ($parsedRaw -match 'remove.*Origin')            "raw=$parsedRaw"
Check 'migrate New=TFDTable'   ($parsedRaw -match 'migrate.*TFDTable')         "raw=$parsedRaw"
Check 'convert present'        ($parsedRaw -match 'convert.*TTable.*TFDTable')  "raw=$parsedRaw"
Check 'link present'           ($parsedRaw -match 'link.*Name.*Inner\.Shade')  "raw=$parsedRaw"
Check 'default present'        ($parsedRaw -match 'default.*Name')             "raw=$parsedRaw"
Check 'note present'           ($parsedRaw -match 'note')                      "raw=$parsedRaw"
Check 'ignore present'         ($parsedRaw -match 'ignore.*TabOrder')          "raw=$parsedRaw"
Check 'pcre escape-hatch present' ($parsedRaw -match 'pcre.*FindThis.*ReplaceThat') "raw=$parsedRaw"

# ---------------------------------------------------------------------------
# Build + index the PropFix fixture (from Task 1) for path validation
# ---------------------------------------------------------------------------
$PropBody = @'
unit PropFix;

interface

type
  TInner = class(TPersistent)
  private
    FShade: Integer;
  published
    property Shade: Integer read FShade write FShade;
  end;

  TOuter = class(TPersistent)
  private
    FInner: TInner;
    FName: string;
  published
    property Inner: TInner read FInner write FInner;
    property Name: string read FName write FName;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $work 'PropFix.pas') $PropBody

$db = Join-Path $WorkDir 'propfix.sqlite'
Write-Host ''
Write-Host 'Indexing PropFix fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

# ---------------------------------------------------------------------------
# PART (b): VALIDATE against real property trees
# ---------------------------------------------------------------------------
# TOuter is BOTH the --from and --to type here (self-map); TOuter has 'Name'
# and, via its class-typed Inner, the deep path 'Inner.Shade'.
$goodRules = "#link Name <- Inner.Shade`r`n"
$goodFile = Join-Path $WorkDir 'rules-good.txt'
Write-Ascii $goodFile $goodRules

Write-Host ''
Write-Host 'convert-validate GOOD (#link Name <- Inner.Shade)' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $goodOut = (& $Exe convert-validate --rules $goodFile --from 'PropFix.TOuter' --to 'PropFix.TOuter' --db $db) -join "`n"
  $goodExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'good rules exit 0' ($goodExit -eq 0) "exit=$goodExit; out=$goodOut"
Check 'good rules print OK' ($goodOut -match 'OK') "out=$goodOut"

$badRules = "#link Bogus.Path <- Name`r`n"
$badFile = Join-Path $WorkDir 'rules-bad.txt'
Write-Ascii $badFile $badRules

Write-Host ''
Write-Host 'convert-validate BAD (#link Bogus.Path <- Name)' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $badOut = (& $Exe convert-validate --rules $badFile --from 'PropFix.TOuter' --to 'PropFix.TOuter' --db $db) -join "`n"
  $badExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'bad rules exit 1' ($badExit -eq 1) "exit=$badExit; out=$badOut"
Check 'bad rules name Bogus.Path' ($badOut -match 'Bogus\.Path') "out=$badOut"

# ??? stub side must NOT be a hard path error (Task 3 scaffolder emits these)
$stubRules = "#link Name <- ???`r`n"
$stubFile = Join-Path $WorkDir 'rules-stub.txt'
Write-Ascii $stubFile $stubRules
Write-Host ''
Write-Host 'convert-validate STUB (#link Name <- ???)' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $stubOut = (& $Exe convert-validate --rules $stubFile --from 'PropFix.TOuter' --to 'PropFix.TOuter' --db $db) -join "`n"
  $stubExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'stub ??? rules exit 0 (tolerated)' ($stubExit -eq 0) "exit=$stubExit; out=$stubOut"

# UNKNOWN directive -> captured parse error -> exit 1
$unkRules = "#frobnicate whatever`r`n"
$unkFile = Join-Path $WorkDir 'rules-unknown.txt'
Write-Ascii $unkFile $unkRules
Write-Host ''
Write-Host 'convert-validate UNKNOWN (#frobnicate)' -ForegroundColor Cyan
$unkOut = (& $Exe convert-validate --rules $unkFile --print-parsed) -join "`n"
$unkExit = $LASTEXITCODE
Check 'unknown directive exit 1' ($unkExit -eq 1) "exit=$unkExit; out=$unkOut"

# ---------------------------------------------------------------------------
# Bad-args / missing-file exit codes
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-validate (no --rules)' -ForegroundColor Cyan
$noRulesOut = ((& $Exe convert-validate 2>&1) -join "`n")
$noRulesExit = $LASTEXITCODE
Check 'missing --rules exit 2' ($noRulesExit -eq 2) "exit=$noRulesExit"

Write-Host 'convert-validate --rules <nonexistent>' -ForegroundColor Cyan
$missOut = ((& $Exe convert-validate --rules (Join-Path $WorkDir 'does-not-exist.txt') 2>&1) -join "`n")
$missExit = $LASTEXITCODE
Check 'unreadable --rules exit 2' ($missExit -eq 2) "exit=$missExit"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
