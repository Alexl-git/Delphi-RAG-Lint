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
# 'Continue' not 'Stop': the native drag-lint exe prints a '(loaded defaults)' note
# to stderr, which under 'Stop' PowerShell turns into a terminating error mid-run.
# Pass/fail here is driven by explicit Check() calls + the final exit code, not exceptions.
$ErrorActionPreference = 'Continue'
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
# PART (a2): #use / #useswap unit-replacement directives (parse-only)
# These must be RECOGNISED (not unknown-directive parse errors), so parse-only
# exits 0 and the count includes them -- what keeps the editor's Save-validate
# green once it emits unit rules.
# ---------------------------------------------------------------------------
$RulesUnits = @'
#use imcFOLDERS
#useswap FOLDERDEF -> imcFOLDERS
#useswap ovcTable -> cxGrid, cxGridDBTableView
'@
$rulesUnitsFile = Join-Path $WorkDir 'rules-units.txt'
Write-Ascii $rulesUnitsFile $RulesUnits

Write-Host ''
Write-Host 'convert-validate --rules rules-units.txt --print-parsed' -ForegroundColor Cyan
$unitsRaw = (& $Exe convert-validate --rules $rulesUnitsFile --print-parsed) -join "`n"
$unitsExit = $LASTEXITCODE
Check 'unit-rules parse-only exits 0' ($unitsExit -eq 0)          "exit=$unitsExit; raw=$unitsRaw"
Check 'unit-rules parsed 3 rules'     ($unitsRaw -match 'parsed 3 rule') "raw=$unitsRaw"
Check 'use rule present'    ($unitsRaw -match 'use imcFOLDERS')   "raw=$unitsRaw"
Check 'useswap rule present' ($unitsRaw -match 'useswap FOLDERDEF') "raw=$unitsRaw"
Check 'useswap multi units' ($unitsRaw -match 'cxGridDBTableView') "raw=$unitsRaw"

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
# #mapping / #apply -- RECOGNISED AND SKIPPED, never a parse error.
#
# INBOX-converter-editor-phase-g-engine-findings, the one concrete ask in it.
# The converter editor authors these directives; the engine cannot yet EVALUATE
# them (conditional per-instance application, spec G6.1) and deliberately still
# does not. But it used to REJECT them --
#     line 1: unknown directive: #mapping
# -- so every save of a well-formed rule book surfaced a validation error and
# made the feature look broken. Authoring is now decoupled from application:
# accept as well-formed, do nothing, do not error.
#
# The '#frobnicate' check directly above is the positive control that keeps this
# honest: if unknown-directive detection were simply switched off to make these
# pass, that assertion fails.
# ---------------------------------------------------------------------------
$mapRules = @(
  '#mapping XYZStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton'
  '#mapping XYZStyle #when Style = stOK -> Default = True, ModalResult = mrOk'
  '#mapping XYZStyle #else -> ModalResult = mrNone'
  '#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton'
  '  #apply XYZStyle'
) -join "`r`n"
$mapFile = Join-Path $WorkDir 'rules-mapping.txt'
Write-Ascii $mapFile ($mapRules + "`r`n")
Write-Host ''
Write-Host 'convert-validate #mapping / #apply (recognised, not applied)' -ForegroundColor Cyan
$mapOut  = (& $Exe convert-validate --rules $mapFile --print-parsed) -join "`n"
$mapExit = $LASTEXITCODE
Check '#mapping/#apply parse exit 0'           ($mapExit -eq 0)                          "exit=$mapExit; out=$mapOut"
Check '#mapping is not an unknown directive'   ($mapOut -notmatch 'unknown directive: #mapping') "out=$mapOut"
Check '#apply is not an unknown directive'     ($mapOut -notmatch 'unknown directive: #apply')   "out=$mapOut"
# The #convert on line 4 is a REAL rule and must still be parsed -- proves the
# new branches skip only their own lines and do not swallow the rest of the file.
Check '#convert alongside #mapping still parsed' ($mapOut -match 'TXYZToggleButton')     "out=$mapOut"

# ---------------------------------------------------------------------------
# Bad-args / missing-file exit codes
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-validate (no --rules)' -ForegroundColor Cyan
$noRulesOut = ((& $Exe convert-validate 2>&1) -join "`n")
$noRulesExit = $LASTEXITCODE
Check 'missing --rules exit 2' ($noRulesExit -eq 2) "exit=$noRulesExit"

# ---------------------------------------------------------------------------
# #mapping / #apply parsing (B1) and validation (B2).
#
# These were RECOGNISED AND SKIPPED -- accepted so they stopped reporting
# 'unknown directive', but emitting no rule at all. A rule book asking for a
# mapping therefore got a clean exit 0 and no mapping, silently: the repro in
# docs\INBOX-URGENT-engine-cannot-apply-mapping.md parsed 2 of its 6 directives.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '#mapping / #apply' -ForegroundColor Cyan

# The INBOX repro book, verbatim: 6 directives, 3 of them #mapping, 1 #apply.
$mapRules = "#mapping FontStyleMap from Vcl.Graphics.TFontStyle to Vcl.Graphics.TFont`r`n" +
            "#mapping FontStyleMap #when Style = fsBold -> Height = 12`r`n" +
            "#mapping FontStyleMap #else                -> Height = 8`r`n" +
            "`r`n" +
            "#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont`r`n" +
            "  #apply FontStyleMap`r`n" +
            "#link Color <- Color`r`n"
$mapFile = Join-Path $WorkDir 'mapping-repro.rules'
Write-Ascii $mapFile $mapRules
$mapOut = (& $Exe convert-validate --rules $mapFile --print-parsed) -join "`n"
Check 'mapping repro parses all 6 rules' ($mapOut -match 'parsed 6 rule\(s\)') "out=$mapOut"
Check 'mapping declaration keeps its from/to types' `
  ($mapOut -match 'mapping FontStyleMap from Vcl\.Graphics\.TFontStyle to Vcl\.Graphics\.TFont') "out=$mapOut"
Check 'mapping #when keeps its condition AND its set list' `
  ($mapOut -match 'mapping FontStyleMap #when Style = fsBold -> Height = 12') "out=$mapOut"
Check 'mapping #else keeps its set list' `
  ($mapOut -match 'mapping FontStyleMap #else -> Height = 8') "out=$mapOut"
Check 'apply is parsed as its own rule' ($mapOut -match 'apply FontStyleMap') "out=$mapOut"

# GRAMMAR PARITY WITH THE EDITOR. ConvRules.Model.pas accepts all four tolerant
# forms below and RE-EMITS every line it parsed. If the engine were stricter,
# the editor's save-validate would fail and RULES WOULD BE SILENTLY LOST. So
# these must parse as rules, and must NOT become parse errors.
$tolRules = "#mapping BareName`r`n" +
            "#mapping NoArrow #when Style = fsBold`r`n" +
            "#mapping NoArrowElse #else`r`n" +
            "#mapping NoTo from Vcl.Graphics.TFontStyle`r`n"
$tolFile = Join-Path $WorkDir 'mapping-tolerant.rules'
Write-Ascii $tolFile $tolRules
$tolOut = (& $Exe convert-validate --rules $tolFile --print-parsed) -join "`n"
$tolExit = $LASTEXITCODE
Check 'tolerant mapping forms all parse (4 rules)' ($tolOut -match 'parsed 4 rule\(s\)') "out=$tolOut"
Check 'tolerant mapping forms are not errors (exit 0)' ($tolExit -eq 0) "exit=$tolExit; out=$tolOut"
Check 'tolerant: bare #mapping Name keeps its name' ($tolOut -match 'mapping BareName') "out=$tolOut"
Check 'tolerant: #when with no arrow KEEPS its condition' `
  ($tolOut -match 'mapping NoArrow #when Style = fsBold') "out=$tolOut"

# The '<' in a generic target is an opener, so a comma inside it must NOT split
# the target list. Written WITHOUT a space after the comma on purpose: a wrong
# split would rejoin with ', ' and INSERT one, which is the only way to tell the
# two apart in this output.
$genRules = "#mapping G1 from U.TEnum to U.TList<A,B>`r`n" +
            "#mapping G2 from U.TEnum to U.TList<A,B>,U.TOther`r`n"
$genFile = Join-Path $WorkDir 'mapping-generic.rules'
Write-Ascii $genFile $genRules
$genOut = (& $Exe convert-validate --rules $genFile --print-parsed) -join "`n"
Check 'generic target stays ONE entry (no space re-inserted)' `
  ($genOut -match 'mapping G1 from U\.TEnum to U\.TList<A,B>(\r|\n|$)') "out=$genOut"
Check 'generic target + sibling splits at the TOP-LEVEL comma only' `
  ($genOut -match 'mapping G2 from U\.TEnum to U\.TList<A,B>, U\.TOther') "out=$genOut"

# B2: an #apply naming a mapping that was never declared is an error, and it
# fires WITHOUT any property tree -- the mode the editor's save-validate uses.
# The editor shows only the FIRST non-empty line of engine output on failure,
# so the message must name the mapping there.
$undecFile = Join-Path $WorkDir 'mapping-undeclared.rules'
Write-Ascii $undecFile "#convert A -> B`r`n#apply Nope`r`n"
$undecOut = ((& $Exe convert-validate --rules $undecFile 2>&1) -join "`n")
$undecExit = $LASTEXITCODE
Check 'undeclared #apply exits 1' ($undecExit -eq 1) "exit=$undecExit; out=$undecOut"
Check 'undeclared #apply names the mapping' ($undecOut -match 'Nope') "out=$undecOut"
# The editor shows the FIRST non-empty line of engine output on failure, so the
# message has to be meaningful there. Read STDOUT ONLY: the engine also writes a
# '(loaded defaults from ...)' note to stderr, and a merged capture interleaves
# the two nondeterministically -- asserting against the merge makes this flaky.
$undecStdout = (& $Exe convert-validate --rules $undecFile 2>$null) -join "`n"
Check 'undeclared #apply says what is wrong on the FIRST stdout line' `
  (($undecStdout -split "`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1) -match 'undeclared mapping') `
  "stdout=$undecStdout"

# CONTROL: the same #apply with a declaration present must pass. Without this,
# 'exit 1' above would also be satisfied by the validator rejecting every
# #apply, or by it being broken in some unrelated way.
$decFile = Join-Path $WorkDir 'mapping-declared.rules'
Write-Ascii $decFile "#mapping Nope from U.TE to U.TC`r`n#convert A -> B`r`n#apply Nope`r`n"
$decOut = ((& $Exe convert-validate --rules $decFile 2>&1) -join "`n")
$decExit = $LASTEXITCODE
Check 'declared #apply exits 0 (control)' ($decExit -eq 0) "exit=$decExit; out=$decOut"

# A bare '#mapping Name' counts as a declaration: the editor emits that shape
# while a rule is being authored, and rejecting it would fail the round-trip.
$bareFile = Join-Path $WorkDir 'mapping-baredecl.rules'
Write-Ascii $bareFile "#mapping Nope`r`n#convert A -> B`r`n#apply Nope`r`n"
$bareOut = ((& $Exe convert-validate --rules $bareFile 2>&1) -join "`n")
Check 'bare #mapping Name counts as a declaration' ($LASTEXITCODE -eq 0) "out=$bareOut"

Write-Host 'convert-validate --rules <nonexistent>' -ForegroundColor Cyan
$missOut = ((& $Exe convert-validate --rules (Join-Path $WorkDir 'does-not-exist.txt') 2>&1) -join "`n")
$missExit = $LASTEXITCODE
Check 'unreadable --rules exit 2' ($missExit -eq 2) "exit=$missExit"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
