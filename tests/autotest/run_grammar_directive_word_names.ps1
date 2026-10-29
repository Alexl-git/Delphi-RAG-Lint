<#
  run_grammar_directive_word_names.ps1 -- Delphi directive words used as
  identifiers (field / var / const / local-var names) must parse clean, and real
  hint / directive parsing must stay intact.

  WHY THIS EXISTS
  ---------------
  The LSP team logged (stats\draglint-gaps.log, 2026-10-28) that
      type TProjectContext = record Platform, Config: string; end;
  yields 6 parser-errors + 2 syntax-errors and NO field symbols -- lint and the
  index were blind to the record. `platform` is a directive word, legal as an
  identifier. The grammar uses tree-sitter keyword extraction: a word lexes as
  the keyword token whenever that keyword is VALID in the current parse state.
  Three grammar shapes made directive keywords valid exactly where a NAME starts:
    1. `record` accepted no body, so `record` + type-level hint was a live parse
       (and `record abstract|sealed`) -> first field named Platform/Abstract/...
    2. declVar / declConst ended with the FULL procAttribute set after `;`, so
       `var A: Integer; Static: Integer;` lexed Static as a directive.
    3. declField / declVar carry a post-`;` calling-convention slot, so a next
       field named Stdcall/Cdecl/... lexed as the callconv.
  Fixed in tree-sitter-delphi13 branch gaps/ext-dirword (2026-10-28).

  THE CHECKS
  ----------
  NEGATIVE CONTROL first: genuinely invalid Delphi must still report syntax /
  parser errors, else every zero below measures nothing.
  POSITIVE CONTROLS: real hints and directives (`platform;`, `deprecated 'x'`,
  `library`, callconv tails, class modifiers, record helpers) parse clean, and a
  capitalised hint `Platform` is still a KEYWORD -- reserved-word-casing fires on
  it -- while a field named `Platform` is an identifier (the rule stays silent).
  SYMBOLS: indexing the repro emits the Platform field.
  KNOWN GAPS (printed, never fail): callconv words as names; Config (2nd name).

  Runs against the PRODUCTION exe path by default (third_party\dll-win64), the
  DLL this test is about; pass -Exe to test a staged engine copy.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-grammar-dirword-$PID"
)
try {
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

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
$SymDir = Join-Path $WorkDir 'sym'
New-Item -ItemType Directory -Path $SymDir | Out-Null

function Unit([string]$name, [string[]]$intf, [string[]]$impl = @()) {
  return @("unit $name;", 'interface') + $intf + @('implementation') + $impl + @('end.')
}

$hintWords  = @('Platform','Deprecated','Experimental','Library','Abstract','Sealed','Helper')
$tailWords  = @('Abstract','Assembler','Dynamic','Export','External','Far','Near','Library',
                'Nodefault','Overload','Override','Reintroduce','Static','Virtual','Final',
                'Local','Dispid','Message','Default','Index','Name','Read','Write')
$ccWords    = @('Stdcall','Cdecl','Safecall','Pascal','Winapi','Inline','Varargs','Register')

$fixtures = [ordered]@{}
$fixtures['Fx0Control'] = Unit 'Fx0Control' @('type', '  TC = class', '    Field: string;', '  end;')
$fixtures['Fx1Repro']   = Unit 'Fx1Repro' @('type', '  TProjectContext = record Platform, Config: string; end;')
$fixtures['Fx2RecordFirst'] = Unit 'Fx2RecordFirst' (@('type') + ($hintWords | % { "  TR$_ = record $_`: Integer; B: string; end;" }))
$fixtures['Fx3ClassFirst']  = Unit 'Fx3ClassFirst'  (@('type') + ($hintWords | % { "  TC$_ = class $_`: Integer; end;" }) + ($hintWords | % { "  TD$_ = class(TObject) $_`: Integer; end;" }))
$fixtures['Fx4VarLater']    = Unit 'Fx4VarLater'    (@('var', '  A0: Integer;') + ($tailWords | % { "  $_`: Integer;" }))
$fixtures['Fx5ConstLater']  = Unit 'Fx5ConstLater'  (@('const', '  Operator = 0;', '  A0 = 1;') + ($tailWords | % { "  $_ = 2;" }))
$fixtures['Fx6LocalVar']    = Unit 'Fx6LocalVar' @() (@('procedure Q;', 'var', '  A0: Integer;') + ($tailWords | % { "  $_`: Integer;" }) + @('begin', '  A0 := Static + Far;', 'end;'))
$fixtures['Fx8FieldNoSemi'] = Unit 'Fx8FieldNoSemi' (@('type') + ((@('Register', 'Operator') + $hintWords) | % { "  TN$_ = record A0: Integer; $_`: Integer end;" }))
# KNOWN GAPS (reported, not asserted): calling-convention words as field / var
# names after a prior declaration. The grammar's post-`;` callconv slot makes
# them keywords there; aliasing them as names ("variant C") blew up parser
# generation time. Follow-up in tree-sitter-delphi13. A known gap that starts
# to parse clean prints PROMOTE -- move it into $fixtures then.
$knownGaps = [ordered]@{}
$knownGaps['Gx1CallConvNames'] = Unit 'Gx1CallConvNames' (@('type', '  TR = record', '    A0: Integer;') + ($ccWords | % { "    $_`: Integer;" }) + @('  end;', 'var', '  V0: Integer;') + ($ccWords | % { "  V$_, $_`: Integer;" }))
$knownGaps['Gx2FieldNoSemiCallConv'] = Unit 'Gx2FieldNoSemiCallConv' (@('type') + (($ccWords | Where-Object { $_ -ne 'Register' }) | % { "  TN$_ = record A0: Integer; $_`: Integer end;" }))
# Positive controls: real hints and directives.
$fixtures['Fx9Hints'] = Unit 'Fx9Hints' @(
  'const X1 = 1 platform; X2 = 2 deprecated ''use Z''; X3 = 3 library; X4 = 4 experimental;'
  'type'
  '  TR1 = record A: Integer platform; B: Integer deprecated ''x''; C: Integer experimental; end;'
  '  TR2 = record A: Integer; end deprecated ''x'';'
  '  TR3 = record A: Integer; end platform;'
  '  T1 = Integer platform;'
  '  TF1 = procedure(A: Integer); cdecl;'
  '  TF2 = function: Integer of object; stdcall;'
  '  TH = record helper for Integer function F: Integer; end;'
  '  TC1 = class(TObject) private FA: Integer; protected procedure A; virtual; abstract; public procedure B; dynamic; procedure D; overload; property P: Integer read FA write FA default 0; property Q: Integer index 1 read FA stored False; end;'
  '  TC2 = class sealed end;'
  '  TC3 = class abstract end;'
  '  TC4 = class;'
  '  TI1 = interface;'
  '  TRef = reference to procedure(A: Integer);'
  'var'
  '  V1: Integer platform;'
  '  V2: Integer deprecated ''x'';'
  '  VP: procedure(A: Integer); stdcall;'
  '  VQ: function: Integer; cdecl varargs;'
  '  VA: Integer;'
  '  VB: Cardinal absolute VA;'
  'procedure P1; platform;'
  'procedure P2; deprecated ''x'';'
  'procedure P3; library;'
  'procedure P4; stdcall; overload;'
)
# A capitalised hint must stay a KEYWORD (reserved-word-casing fires on it).
$fixtures['FxAHintKeyword'] = Unit 'FxAHintKeyword' @('const X1 = 1 Platform;')
# Genuinely invalid Delphi. Never make this parse.
$fixtures['FxZKnownBad'] = Unit 'FxZKnownBad' @('type', '  TBroken = class', '    procedure Oops(;', '  end') @('begin end end')

foreach ($set in @($fixtures, $knownGaps)) {
  foreach ($name in $set.Keys) {
    $path = Join-Path $WorkDir "$name.pas"
    [System.IO.File]::WriteAllText($path, (($set[$name] -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
  }
}
[System.IO.File]::WriteAllText((Join-Path $SymDir 'Fx1Repro.pas'), (($fixtures['Fx1Repro'] -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

function LintOut([string]$pas) { return (& $Exe lint $pas 2>&1 | Out-String) }
function SyntaxFindings([string]$out) {
  return , @($out -split "`r?`n" | Where-Object { $_ -match '\[error\]\s+(syntax-error|parser-error)' })
}

Write-Host ''
Write-Host "exe: $Exe"
Write-Host ''

# --- 1. Mechanism reachable --------------------------------------------------
$bad = SyntaxFindings (LintOut (Join-Path $WorkDir 'FxZKnownBad.pas'))
Check 'NEGATIVE CONTROL: invalid Delphi still reports syntax/parser errors' ($bad.Count -ge 1) "findings=$($bad.Count)"

# --- 2. Every fixture except the known-bad parses clean -----------------------
foreach ($name in $fixtures.Keys) {
  if ($name -eq 'FxZKnownBad') { continue }
  $out = LintOut (Join-Path $WorkDir "$name.pas")
  $f = SyntaxFindings $out
  Check "$name parses clean" ($f.Count -eq 0) "findings=$($f.Count); $(($f | Select-Object -First 3) -join ' | ')"
  if ($name -eq 'Fx1Repro') {
    $rw = @($out -split "`r?`n" | Where-Object { $_ -match 'reserved-word-casing' })
    Check 'Fx1Repro: field `Platform` is an identifier (no reserved-word-casing)' ($rw.Count -eq 0) "$($rw -join ' | ')"
  }
  if ($name -eq 'FxAHintKeyword') {
    $rw = @($out -split "`r?`n" | Where-Object { $_ -match 'reserved-word-casing' -and $_ -match '"Platform"' })
    Check 'POSITIVE CONTROL: hint `Platform` is still a keyword (reserved-word-casing fires)' ($rw.Count -ge 1) "findings=$($rw.Count)"
  }
}

# --- 2b. Known gaps: reported, never fail the run -----------------------------
foreach ($name in $knownGaps.Keys) {
  $f = SyntaxFindings (LintOut (Join-Path $WorkDir "$name.pas"))
  $state = if ($f.Count -eq 0) { 'PROMOTE (now parses clean)' } else { "still open, findings=$($f.Count)" }
  Write-Host ("  [KNOWN-GAP] {0}: {1}" -f $name, $state) -ForegroundColor Yellow
}

# --- 3. Symbols: the repro's first field is emitted ---------------------------
# Only the FIRST name of a multi-name field list (`Platform, Config: string`) is
# emitted as a symbol today -- an extractor limitation that predates this fix
# (old engine drops `Beta` in `record Alpha, Beta: string; end;` too). Config is
# therefore a reported known gap, not an assertion.
$db = Join-Path $WorkDir 'sym.sqlite'
& $Exe index $SymDir --db $db 2>&1 | Out-Null
function FieldRows([string]$fld) {
  $j = (& $Exe query --name $fld --db $db --json 2>$null | Out-String)
  $rows = @()
  try { $rows = @($j | ConvertFrom-Json) } catch { $rows = @() }
  return , @($rows | Where-Object { $_ -and ("$($_.qualified_name)" -match "TProjectContext\.$fld$") })
}
$hit = FieldRows 'Platform'
Check 'SYMBOL: TProjectContext.Platform is indexed' ($hit.Count -ge 1) "rows=$($hit.Count)"
$cfg = FieldRows 'Config'
$state = if ($cfg.Count -ge 1) { 'PROMOTE (now indexed)' } else { 'still open (multi-name field: only the first name is emitted)' }
Write-Host ("  [KNOWN-GAP] SYMBOL TProjectContext.Config: {0}" -f $state) -ForegroundColor Yellow

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-grammar-dirword-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
