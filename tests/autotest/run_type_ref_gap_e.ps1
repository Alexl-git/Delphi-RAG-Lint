<#
  run_type_ref_gap_e.ps1 -- ref-gap E RED test (Task 1).

  GAP: under deep indexing (usage refs on), three type-USE shapes are never
  emitted as refs against the type symbol at all:
    (1) impl-header qualifier   -- `constructor Widget.Create;` /
                                    `procedure Widget.Use(...)` /
                                    `function Widget.Make(...)` -- the
                                    'Widget' qualifier before the dot in an
                                    implementation-section routine header.
    (2) local-var type          -- `Local: Widget;` in a var block.
    (3) is/as operand           -- `if pParam is Widget then ...`.
  (Interface-section decls, param/return type annotations, and constructor-
  call sites ARE already indexed -- those are NOT the gap; do not assert them
  as the teeth here.)

  CONSEQUENCE (Phase 2): because these three shapes are invisible to the ref
  index, the `type-name-prefix` autofix (`lint-all --rule type-name-prefix
  --fix --apply`, which renames a non-prefixed class by adding the 'T'
  prefix) mutates the file based on indexed ref sites only. BEFORE ref-gap E
  this left the impl-header / local-var / is-operand occurrences as STALE
  OLD-NAME TEXT ('Widget') on disk (a silent broken-compile). AFTER ref-gap E
  those sites are indexed as type_use refs, so the rename now rewrites them
  too and the round-trip is clean -- which is exactly what this test asserts
  (Phase 1: the sites ARE indexed; Phase 2: zero stale 'Widget' after the
  rename). (Ref-gap E also RETIRED the type-name-prefix half of the old
  "may leave ... type-annotation references unrenamed" --fix warning; the
  warning now only fires for field-name-prefix's remaining bare-field-read
  gap. This test does not assert on the warning text -- only on the concrete
  round-trip result.)

  WHY 'Widget' (a non-T class name) and NOT 'TMyclass': the type-name-prefix
  detector (StartsWithPrefix in DRagLint.Diagnostics.NamingChecks.pas:106,
  used at :540) treats ANY name that already starts with the class prefix
  ('T') as compliant -- it does NOT require the following letter to be
  uppercase. So a 'TMyclass' fixture produces NO type-name-prefix finding
  and the autofix is a no-op. A non-T name like 'Widget' DOES trip the rule,
  so the REAL `--fix --apply` autofix path (the exact mechanism the --fix
  warning guards, routed through TRenameRefactoring.Build in
  DRagLint.Refactor.NamingFix.pas:456 -- the same builder as the generic
  rename verb) is exercised. Confirmed live during authoring: the autofix
  renames Widget -> TWidget and reports "applied 1 fix(es)".

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-type-ref-gap-e by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-type-ref-gap-e"
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

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1
# and run_naming_prefix_autofix.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$work = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $work | Out-Null
$fixtureFile = Join-Path $work 'TypeRefE.pas'
$db  = Join-Path $WorkDir 'typeRefE.sqlite'
$cfg = Join-Path $WorkDir 'drag-lint-lint.json'

# =============================================================================
# Fixture: class Widget (a non-T name, so type-name-prefix FIRES) referenced
# in EVERY target shape. Line numbers below were confirmed against this EXACT
# text (built once during authoring and checked with a numbered dump) -- do
# not reflow/reformat this here-string without re-confirming the numbers.
# =============================================================================
$Fixture = @'
unit TypeRefE;

interface

type
  Widget = class
  private
    FValue: Integer;
  public
    constructor Create;
    procedure Use(pParam: Widget);
    function Make: Widget;
  end;

implementation

constructor Widget.Create;
begin
end;

procedure Widget.Use(pParam: Widget);
var
  Local: Widget;
begin
  Local := Widget.Create;
  if pParam is Widget then Local.Free;
end;

function Widget.Make: Widget;
begin
  Result := Widget.Create;
end;

end.
'@
Write-Ascii $fixtureFile $Fixture

# Fixture drag-lint-lint.json opting Widget into the type-name-prefix autofix
# (config shape copied EXACTLY from run_naming_prefix_autofix.ps1's CASE 3).
'{ "autofix": ["type-name-prefix"], "naming": { "type_prefix": { "class": "T" } } }' |
  Out-File -FilePath $cfg -Encoding ascii

# The three target shapes' 1-based line numbers, confirmed against the exact
# fixture text above:
#   impl-header qualifiers: 17 (Create), 21 (Use), 29 (Make)
#   local-var type:         23 (Local: Widget;)
#   is-operand:              26 (if pParam is Widget then ...)
$implHeaderLine1 = 17
$implHeaderLine2 = 21
$implHeaderLine3 = 29
$localVarLine    = 23
$isOperandLine   = 26

Write-Host 'PHASE 1: index the fixture, assert the 3 missing shapes are NOT indexed as refs' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db --deep 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

$refs1 = & $Exe query find-callers --name Widget --db $db --json | ConvertFrom-Json
$lines1 = @($refs1 | ForEach-Object { $_.start_line })
Write-Host ("  find-callers --name Widget returned lines: {0}" -f (($lines1 | Sort-Object) -join ', '))

Check "impl-header qualifier 'Widget.Create' indexed as a ref (line $implHeaderLine1)" `
  ($lines1 -contains $implHeaderLine1) `
  "lines=$($lines1 -join ',')"
Check "impl-header qualifier 'Widget.Use' indexed as a ref (line $implHeaderLine2)" `
  ($lines1 -contains $implHeaderLine2) `
  "lines=$($lines1 -join ',')"
Check "impl-header qualifier 'Widget.Make' indexed as a ref (line $implHeaderLine3)" `
  ($lines1 -contains $implHeaderLine3) `
  "lines=$($lines1 -join ',')"
Check "local-var type 'Local: Widget;' indexed as a ref (line $localVarLine)" `
  ($lines1 -contains $localVarLine) `
  "lines=$($lines1 -join ',')"
Check "is-operand 'pParam is Widget' indexed as a ref (line $isOperandLine)" `
  ($lines1 -contains $isOperandLine) `
  "lines=$($lines1 -join ',')"

Write-Host ''
Write-Host 'PHASE 2: type-name-prefix --fix --apply (Widget -> TWidget), reindex, assert zero stale old-name sites' -ForegroundColor Cyan

# Drive the REAL type-name-prefix autofix. Invocation copied verbatim from
# run_naming_prefix_autofix.ps1's CASE 3 (lint-all --rule <id> --fix --apply
# --quiet). Confirmed live during authoring: this renames Widget -> TWidget
# and reports "autofix: applied 1 fix(es)".
$fixOut = & $Exe lint-all --db $db --config $cfg --rule type-name-prefix --fix --apply --quiet 2>&1
$fixExit = $LASTEXITCODE
Write-Host ("  autofix output: {0}" -f ($fixOut -join ' | '))
Check 'type-name-prefix --fix --apply exits 0 and reports an applied fix' `
  ($fixExit -eq 0 -and (($fixOut -join ' ') -match 'applied \d+ fix')) `
  "exit=$fixExit; $($fixOut -join ' | ')"

$afterFix = Get-Content -Raw $fixtureFile

# Sanity: the autofix DID rename the indexed decl site (proves the real
# type-name-prefix path fired, not a no-op).
Check 'autofix renamed the class declaration to TWidget (real autofix fired)' `
  ($afterFix -cmatch 'TWidget\s*=\s*class') `
  'decl not renamed -- autofix did not fire'

# Scoped stale-text witness: assert on the SPECIFIC shape lines rather than a
# blind whole-file grep (guards against 'Widget' being a common English word;
# this fixture uses it only as the class name, but scope-to-line is safer).
$afterLines = $afterFix -split "`r`n|`n"
function StaleOnLine([int]$LineNo) {
  # 1-based -> 0-based; a line still carrying the old bare name 'Widget'
  # (not the new 'TWidget') is stale. Match 'Widget' NOT immediately
  # preceded by 'T' or a word char (so 'TWidget' does not count as stale).
  $t = $afterLines[$LineNo - 1]
  return ($t -cmatch '(?<![.\w])Widget(?!\w)')
}
$staleImpl1 = StaleOnLine $implHeaderLine1
$staleImpl2 = StaleOnLine $implHeaderLine2
$staleImpl3 = StaleOnLine $implHeaderLine3
$staleLocal = StaleOnLine $localVarLine
$staleIs    = StaleOnLine $isOperandLine
Write-Host ("  stale 'Widget' still on shape lines? impl17=$staleImpl1 impl21=$staleImpl2 impl29=$staleImpl3 local23=$staleLocal is26=$staleIs")

Check "impl-header line $implHeaderLine1 has NO stale 'Widget' after autofix (round-trip clean)" `
  (-not $staleImpl1) "line: $($afterLines[$implHeaderLine1 - 1])"
Check "impl-header line $implHeaderLine2 has NO stale 'Widget' after autofix (round-trip clean)" `
  (-not $staleImpl2) "line: $($afterLines[$implHeaderLine2 - 1])"
Check "impl-header line $implHeaderLine3 has NO stale 'Widget' after autofix (round-trip clean)" `
  (-not $staleImpl3) "line: $($afterLines[$implHeaderLine3 - 1])"
Check "local-var line $localVarLine has NO stale 'Widget' after autofix (round-trip clean)" `
  (-not $staleLocal) "line: $($afterLines[$localVarLine - 1])"
Check "is-operand line $isOperandLine has NO stale 'Widget' after autofix (round-trip clean)" `
  (-not $staleIs) "line: $($afterLines[$isOperandLine - 1])"

$reindexOut = & $Exe index $work --db $db --deep 2>&1
$reindexExit = $LASTEXITCODE
Check 'reindex after autofix exits 0' ($reindexExit -eq 0) "exit=$reindexExit; $($reindexOut -join ' | ')"

# Direct symbols/refs table checks (case-sensitive) mirroring
# run_self_field_refs.ps1's python-sqlite3 idiom. NOT `query --name`, which
# resolves case-INsensitively (confirmed live) and so cannot witness a
# stale-vs-renamed distinction.
$py = Join-Path $WorkDir 'q.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
table, col, name = sys.argv[2], sys.argv[3], sys.argv[4]
cur = c.execute(f"SELECT {col} AS v FROM {table} WHERE {col} = ?", (name,))
print(json.dumps([r[0] for r in cur.fetchall()]))
c.close()
'@ | Set-Content $py -Encoding ascii

$staleRefRows = @((python $py $db 'refs' 'name_text' 'Widget') -join "`n" | ConvertFrom-Json)
Check 'direct refs-table query: zero rows with name_text = "Widget" (case-sensitive)' `
  ($staleRefRows.Count -eq 0) "count=$($staleRefRows.Count)"

$oldSym = @((python $py $db 'symbols' 'name' 'Widget') -join "`n" | ConvertFrom-Json)
Check 'zero symbols still named (case-sensitive) "Widget"' `
  ($oldSym.Count -eq 0) "count=$($oldSym.Count)"

$newSym = @((python $py $db 'symbols' 'name' 'TWidget') -join "`n" | ConvertFrom-Json)
Check 'class now resolves under the new name "TWidget" (case-sensitive)' `
  ($newSym.Count -ge 1) "count=$($newSym.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
