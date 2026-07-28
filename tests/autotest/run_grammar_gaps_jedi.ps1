<#
  run_grammar_gaps_jedi.ps1 -- the three JEDI/JVCL grammar gaps must stay parseable.

  WHY THIS EXISTS
  ---------------
  docs/INBOX-tree-sitter-jedi-jvcl-grammar-fixes.md (2026-07-17) reported three
  constructs that dcc32 compiles but the delphi13 tree-sitter grammar rejected.
  Upstream fixed all three in commit e531000 and asked drag-lint to rebuild its
  production DLL. Task 4c measured that the shipped DLLs ALREADY contained the
  fixes -- so no rebuild happened, and the whole outcome of that task was a
  claim ("these three parse now") with nothing asserting it.

  That claim is exactly the kind that decays silently. The DLL is a vendored
  binary under third_party\, which run_encoding_guard.ps1 deliberately excludes;
  nothing else in tests\ pins tree-sitter parse behaviour (measured 2026-07-28:
  `grep -rln "syntax-error\|parser-error" tests\ --include=*.ps1` matched ONE
  file, tests\lint\run_lint_tests.ps1, and only inside a comment). So a future
  DLL swap that rolls the grammar backwards would be invisible to the battery.
  This runner is the assertion.

  Worse, the DLL's grammar version is NOT observable: `drag-lint info` prints
  `tree-sitter: delphi13 14`, and that 14 is the tree-sitter ABI number, not a
  grammar version -- `dfm` prints 14 too, and it does not move as the DLL ages.
  Upstream traced a six-week drift and an entire false bug report to reading
  that number as a grammar stamp. Parsing the constructs is the only evidence
  there is, which is why this test parses them instead of checking a version.

  THE THREE CONSTRUCTS
  --------------------
    1. subrange bound = nested const-expr call -- `2..Succ(High(TDigitValue))`
       (JCL JclSysUtils.pas)
    2. the `at` soft keyword as an INHERITED method name -- `inherited At(x)`
       (JCL JclCLR.pas). `Obj.At(x)`, `At(x)` and a field named `At` always
       worked; only the inherited slot lost it.
    3. `Operator:` as a class/record FIELD name (JVCL JvXmlDatabase.pas)

  WHY THE NEGATIVE CONTROL IS LOAD-BEARING
  ----------------------------------------
  Every gap assertion here is "zero syntax findings", and zero is also what a
  broken detector reports. If `lint` stopped emitting syntax-error/parser-error
  at all -- a swallowed exception, a renamed rule, a lint invocation that
  silently no-ops on a path it cannot read -- all three gap checks would go
  green while measuring nothing. Fixture9KnownBad is genuinely invalid Delphi
  and MUST produce findings. It is the proof the mechanism is reachable, and
  without it the other four checks are decoration.

  Fixture0Control (ordinary valid Delphi, zero findings) is the other half:
  it rules out a detector that reports errors on everything.

  Verified during authoring against three different delphi13 DLLs, same exe:
    tools\corpusscan\...\tree-sitter-delphi13.dll.bak-jul16 (pre-e531000)
        -> all three gap fixtures FAIL (4 / 3 / 4 findings). This test goes RED
           on that binary, which is what makes it a test and not a tautology.
    third_party\dll-win64\tree-sitter-delphi13.dll (shipped) -> all pass.
    tools\corpusscan\...\tree-sitter-delphi13.dll (upstream's own rebuild)
        -> all pass.

  Runs against the PRODUCTION exe path (third_party\dll-win64), which is the
  dominant convention in tests\ and, more to the point, is the DLL this test is
  about -- src\cli\Win64\Debug carries its own copy.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-grammar-gaps-jedi"
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

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

# Fixture bodies. Written with -Encoding ascii and explicit CRLF joins so the
# files match the repo's .pas rule (strict 7-bit ASCII, CRLF, no BOM) even
# though they live under $env:TEMP -- a fixture that differs in encoding from
# real source is testing a different input than the one that ships.
$fixtures = [ordered]@{

  'Fixture0Control' = @(
    'unit Fixture0Control;'
    'interface'
    'type'
    '  TControl1 = class'
    '    Field: string;'
    '    function Plain(pIndex: Integer): Integer;'
    '  end;'
    'implementation'
    'function TControl1.Plain(pIndex: Integer): Integer;'
    'begin'
    '  Result := pIndex;'
    'end;'
    'end.'
  )

  'Fixture1Subrange' = @(
    'unit Fixture1Subrange;'
    'interface'
    'type'
    '  TDigitValue = -1..35;'
    '  TDigitCount = 2..Succ(High(TDigitValue));'
    'var'
    '  GCount: TDigitCount;'
    'implementation'
    'end.'
  )

  'Fixture2InheritedAt' = @(
    'unit Fixture2InheritedAt;'
    'interface'
    'type'
    '  TBase = class'
    '    function At(pIndex: Integer): Integer; virtual;'
    '  end;'
    '  TDerived = class(TBase)'
    '    function At(pIndex: Integer): Integer; override;'
    '  end;'
    'implementation'
    'function TBase.At(pIndex: Integer): Integer;'
    'begin'
    '  Result := pIndex;'
    'end;'
    'function TDerived.At(pIndex: Integer): Integer;'
    'begin'
    '  Result := inherited At(pIndex);'
    'end;'
    'end.'
  )

  'Fixture3OperatorField' = @(
    'unit Fixture3OperatorField;'
    'interface'
    'type'
    '  TJvXmlSQLOperator = (xoEqual, xoLess, xoGreater);'
    '  TJvXmlCriteria = class'
    '    Field: string;'
    '    Operator: TJvXmlSQLOperator;'
    '    Value: string;'
    '  end;'
    'implementation'
    'end.'
  )

  # Genuinely invalid Delphi. Never make this parse.
  'Fixture9KnownBad' = @(
    'unit Fixture9KnownBad;'
    'interface'
    'type'
    '  TBroken = class'
    '    procedure Oops(;'
    '  end'
    'implementation'
    'begin end end.'
  )
}

foreach ($name in $fixtures.Keys) {
  $path = Join-Path $WorkDir "$name.pas"
  [System.IO.File]::WriteAllText($path, (($fixtures[$name] -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
}

# Count only the parse-level diagnostics. Other rules (e.g. inherited-bare, an
# [info] that fires on ANY qualified `inherited Foo(x)` -- confirmed by running
# the same shape with an ordinary method name) are unrelated to grammar
# coverage and must not be allowed to turn this test red.
function SyntaxFindings([string]$pas) {
  $out = & $Exe lint $pas 2>&1 | Out-String
  $lines = @($out -split "`r?`n" | Where-Object { $_ -match '\[error\]\s+(syntax-error|parser-error)' })
  return , $lines
}

Write-Host ''
Write-Host "exe: $Exe"
Write-Host ''

# --- 1. Mechanism reachable: invalid Delphi still reports ------------------
# This runs FIRST deliberately. If it fails, the four zero-finding checks below
# carry no information and their PASS lines should not be believed.
$bad = SyntaxFindings (Join-Path $WorkDir 'Fixture9KnownBad.pas')
Check 'NEGATIVE CONTROL: invalid Delphi still reports syntax/parser errors' `
  ($bad.Count -ge 1) "findings=$($bad.Count)"

# --- 2. Ordinary valid Delphi is clean -------------------------------------
$ctl = SyntaxFindings (Join-Path $WorkDir 'Fixture0Control.pas')
Check 'CONTROL: ordinary valid Delphi parses clean' `
  ($ctl.Count -eq 0) "findings=$($ctl.Count); $($ctl -join ' | ')"

# --- 3. The three JEDI/JVCL gaps -------------------------------------------
$g1 = SyntaxFindings (Join-Path $WorkDir 'Fixture1Subrange.pas')
Check 'GAP 1: subrange bound `2..Succ(High(TDigitValue))` parses (JCL JclSysUtils)' `
  ($g1.Count -eq 0) "findings=$($g1.Count); $($g1 -join ' | ')"

$g2 = SyntaxFindings (Join-Path $WorkDir 'Fixture2InheritedAt.pas')
Check 'GAP 2: `inherited At(x)` -- at-soft-keyword as inherited method parses (JCL JclCLR)' `
  ($g2.Count -eq 0) "findings=$($g2.Count); $($g2 -join ' | ')"

$g3 = SyntaxFindings (Join-Path $WorkDir 'Fixture3OperatorField.pas')
Check 'GAP 3: `Operator:` as a class field name parses (JVCL JvXmlDatabase)' `
  ($g3.Count -eq 0) "findings=$($g3.Count); $($g3 -join ' | ')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
