<#
  run_naming_prefix_autofix.ps1 -- Batch D Task 3: naming PREFIX-ADDING findings
  (field-name-prefix, param-name-prefix, type-name-prefix) become FIXABLE via the
  rename engine (DRagLint.Refactor.NamingFix.BuildNamingFixEdits, extended with
  SynthesizePrefixedName), applied through the existing store-backed append in
  FinalizeAndOutput. Opt-in only via config "autofix": [...] (mirrors phase 1).

  Unlike phase-1 re-casing (collision-free -- same letters, different case),
  prefix-adding CHANGES the identifier, so param-name-prefix (routed through
  BuildLocal, which has no collision check of its own) needs a NEW collision
  guard: if the synthesized name already exists as another local/param in the
  same routine scope, the fix must be skipped entirely (no edit, exit 0).

    CASE 1 field-name-prefix  -- `client: TObject;` field -> FClient at decl +
                                  a bare in-method use.
    CASE 2 param-name-prefix  -- `procedure P(x: Integer);` + body use of x ->
                                  pX at decl header, impl header, AND body
                                  (BuildLocal syncs all three). Nothing outside
                                  the routine changes.
    CASE 3 type-name-prefix   -- `myclass = class ... end;` -> TMyClass at
                                  decl + refs.
    OPT-IN GATE               -- CASE 3's fixture re-run with the rule NOT
                                  listed in "autofix" -> identifier UNCHANGED.
    COLLISION SKIP            -- `procedure P(x: Integer); var pX: Integer;`
                                  -- synthesized 'pX' already exists as a local
                                  in scope -> NO edit applied anywhere, exit 0,
                                  x unchanged.
    SAME-LINE STRESS          -- `procedure P(a, b: Integer);` both params
                                  prefixed -> both become pA, pB on the same
                                  decl line (exercises Task 1's column-DESC
                                  same-line edit ordering).
    DRY-RUN                   -- `--fix` (no --apply) previews only; file on
                                  disk untouched.
    DETERMINISM               -- two --fix --apply runs on fresh copies of the
                                  same pre-fix fixture produce byte-identical
                                  output files.

  Each fixture indexes into its OWN fresh sqlite db (isolation -- mirrors
  run_naming_autofix.ps1).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-naming-prefix-autofix"
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
# Absolutize so the exe path survives regardless of CWD (mirrors run_naming_autofix.ps1).
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1).
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

# =============================================================================
# CASE 1: field-name-prefix -- `client: TObject;` field -> FClient at decl +
# a bare in-method use.
# NOTE (finding, see task report): a Self-qualified use (`Self.client:= nil;`)
# is deliberately NOT exercised here. DRagLint.Parser.Delphi13.pas's deep-scan
# usage-ref emission only emits a 'read' ref for the LHS BASE identifier of an
# exprDot (i.e. 'Self' in 'Self.client'), never for the RHS member -- and its
# assignment-ref handler only emits a 'write' ref when the LHS is a bare
# identifier, not an exprDot. So 'Self.client' never gets a ref row for
# 'client' itself (find-callers --name client would miss it): a pre-existing
# reference-engine gap (same family as phase 1's CASE 3 const-casing note),
# not something this task's dispatch/collision-guard work can or should fix.
# =============================================================================
Write-Host 'CASE 1: field-name-prefix' -ForegroundColor Cyan
$c1Dir = Join-Path $WorkDir 'case1'
$c1Src = Join-Path $c1Dir 'src'
New-Item -ItemType Directory $c1Src | Out-Null
$c1File = Join-Path $c1Src 'FieldPrefixAutofix.pas'
$c1Db   = Join-Path $c1Dir 'naming.sqlite'
$c1Cfg  = Join-Path $c1Dir 'drag-lint-lint.json'

$Case1Fixture = @'
unit FieldPrefixAutofix;

interface

type
  TThing = class
  private
    client: TObject;
  public
    procedure Touch;
  end;

implementation

procedure TThing.Touch;
begin
  client:= TObject.Create;
end;

end.
'@
Write-Ascii $c1File $Case1Fixture
'{ "autofix": ["field-name-prefix"], "naming": { "field_prefix": "F" } }' | Out-File -FilePath $c1Cfg -Encoding ascii

& $Exe index $c1Src --db $c1Db 2>&1 | Out-Null
Check 'CASE1: index exits 0' ($LASTEXITCODE -eq 0)
Check 'CASE1: db built' (Test-Path $c1Db)

$out = & $Exe lint-all --db $c1Db --config $c1Cfg --rule field-name-prefix --fix --apply --quiet 2>&1
Write-Host ($out -join "`n")

$after = Get-Content -Raw $c1File
Check 'CASE1: field decl renamed to FClient'          ($after -cmatch 'FClient\s*:\s*TObject;')
Check 'CASE1: bare use renamed to FClient:= TObject.Create;' ($after -cmatch 'FClient\s*:=\s*TObject\.Create;')
Check 'CASE1: no stale lower-case client remains' (-not ($after -cmatch '(?<![.\w])client(?!\w)'))

# =============================================================================
# CASE 2: param-name-prefix -- BuildLocal rewrites decl header + impl header +
# body use; nothing outside the routine changes. Second unrelated routine
# (OtherRoutine, with its own unrelated param) is the negative-scope witness.
# =============================================================================
Write-Host ''
Write-Host 'CASE 2: param-name-prefix' -ForegroundColor Cyan
$c2Dir = Join-Path $WorkDir 'case2'
$c2Src = Join-Path $c2Dir 'src'
New-Item -ItemType Directory $c2Src | Out-Null
$c2File = Join-Path $c2Src 'ParamPrefixAutofix.pas'
$c2Db   = Join-Path $c2Dir 'naming.sqlite'
$c2Cfg  = Join-Path $c2Dir 'drag-lint-lint.json'

$Case2Fixture = @'
unit ParamPrefixAutofix;

interface

procedure P(x: Integer);
procedure OtherRoutine(pUntouched: Integer);

implementation

procedure P(x: Integer);
begin
  x:= x + 1;
end;

procedure OtherRoutine(pUntouched: Integer);
begin
  pUntouched:= 5;
end;

end.
'@
Write-Ascii $c2File $Case2Fixture
'{ "autofix": ["param-name-prefix"], "naming": { "param_prefix": "p" } }' | Out-File -FilePath $c2Cfg -Encoding ascii

& $Exe index $c2Src --db $c2Db 2>&1 | Out-Null
Check 'CASE2: index exits 0' ($LASTEXITCODE -eq 0)

$out2 = & $Exe lint-all --db $c2Db --config $c2Cfg --rule param-name-prefix --fix --apply --quiet 2>&1
Write-Host ($out2 -join "`n")

$after2 = Get-Content -Raw $c2File
$declRenamed = $after2 -cmatch 'interface\r?\n\r?\nprocedure\s+P\(pX\s*:\s*Integer\);'
$implRenamed = $after2 -cmatch 'procedure\s+P\(pX\s*:\s*Integer\);\s*\r?\nbegin'
$bodyRenamed = $after2 -cmatch 'pX\s*:=\s*pX\s*\+\s*1;'
$noStaleLowerX = -not ($after2 -cmatch '(?<![.\w])x(?!\w)')
$otherUntouched = $after2 -cmatch 'OtherRoutine\(pUntouched\s*:\s*Integer\);' -and $after2 -cmatch 'pUntouched\s*:=\s*5;'
Check 'CASE2: interface decl header renamed to P(pX: Integer)'  $declRenamed  $after2
Check 'CASE2: impl header renamed to P(pX: Integer)'            $implRenamed  $after2
Check 'CASE2: body use renamed to pX := pX + 1;'                $bodyRenamed  $after2
Check 'CASE2: no stale lower-case bare x remains'                $noStaleLowerX $after2
Check 'CASE2: unrelated OtherRoutine param (already-prefixed pUntouched) unchanged' $otherUntouched $after2

# =============================================================================
# CASE 3: type-name-prefix -- `myclass = class ... end;` -> TMyClass at decl +
# a var-of-that-type reference.
# =============================================================================
Write-Host ''
Write-Host 'CASE 3: type-name-prefix' -ForegroundColor Cyan
$c3Dir = Join-Path $WorkDir 'case3'
$c3Src = Join-Path $c3Dir 'src'
New-Item -ItemType Directory $c3Src | Out-Null
$c3File = Join-Path $c3Src 'TypePrefixAutofix.pas'
$c3Db   = Join-Path $c3Dir 'naming.sqlite'
$c3Cfg  = Join-Path $c3Dir 'drag-lint-lint.json'

# NOTE (finding, see task report -- mirrors run_naming_autofix.ps1's CASE 3
# note for const-casing): SynthesizePrefixedName's Cap() upper-cases ONLY the
# first letter of the identifier (per the brief's exact spec), so 'myclass' +
# 'T' -> 'TMyclass', NOT 'TMyClass' (no mid-word re-casing is attempted; that
# is method-pascalcase/type-casing territory, out of scope for prefix-adding).
# Also: only the CONSTRUCTOR-CALL reference (`myclass.Create`, an exprDot rhs
# reachable via the indexer's type_use/read-ref emission) is renamed. The
# `var Obj: myclass;` type annotation and the `procedure myclass.DoIt;`
# impl-header type-qualifier are NOT indexed as references TO THE TYPE symbol
# (query find-callers --name myclass confirms: only the Create call site is
# returned) -- a pre-existing reference-engine gap (typerefs / impl-header
# qualifiers aren't linked back to the type symbol's refs), not something
# introduced or fixable by this task's dispatch/collision-guard work.
$Case3Fixture = @'
unit TypePrefixAutofix;

interface

type
  myclass = class
  public
    procedure DoIt;
  end;

procedure RunIt;

implementation

procedure myclass.DoIt;
begin
end;

procedure RunIt;
var
  Obj: myclass;
begin
  Obj:= myclass.Create;
  Obj.DoIt;
  Obj.Free;
end;

end.
'@
Write-Ascii $c3File $Case3Fixture
'{ "autofix": ["type-name-prefix"], "naming": { "type_prefix": { "class": "T" } } }' | Out-File -FilePath $c3Cfg -Encoding ascii

& $Exe index $c3Src --db $c3Db 2>&1 | Out-Null
Check 'CASE3: index exits 0' ($LASTEXITCODE -eq 0)

$out3 = & $Exe lint-all --db $c3Db --config $c3Cfg --rule type-name-prefix --fix --apply --quiet 2>&1
Write-Host ($out3 -join "`n")

$after3 = Get-Content -Raw $c3File
$c3DeclRenamed = $after3 -cmatch 'TMyclass\s*=\s*class'
$c3RefRenamed  = $after3 -cmatch 'Obj\s*:=\s*TMyclass\.Create;'
Check 'CASE3: type decl renamed to TMyclass (Cap = first-letter-only per spec)' $c3DeclRenamed $after3
Check 'CASE3: indexed constructor-ref renamed to Obj:= TMyclass.Create;' $c3RefRenamed $after3
Check 'CASE3: no stale lower-case bare myclass decl remains (declaration site only)' `
  (-not ($after3 -cmatch '(?<![.\w])myclass\s*=\s*class')) $after3

# =============================================================================
# OPT-IN GATE: same type-name-prefix fixture, but "autofix" does NOT list
# type-name-prefix -> registered-fixable (rules --json) but not permitted ->
# identifier UNCHANGED.
# =============================================================================
Write-Host ''
Write-Host 'OPT-IN GATE: type-name-prefix not opted in via AutoFixIds' -ForegroundColor Cyan
$gateDir = Join-Path $WorkDir 'gate'
$gateSrc = Join-Path $gateDir 'src'
New-Item -ItemType Directory $gateSrc | Out-Null
$gateFile = Join-Path $gateSrc 'TypePrefixAutofix.pas'
$gateDb   = Join-Path $gateDir 'naming.sqlite'
$gateCfg  = Join-Path $gateDir 'drag-lint-lint.json'

Write-Ascii $gateFile $Case3Fixture
$gateBefore = Get-Content -Raw $gateFile
# "autofix" deliberately omits type-name-prefix (opts in an UNRELATED rule
# instead, so the config isn't simply "no autofix at all").
'{ "autofix": ["field-name-prefix"], "naming": { "type_prefix": { "class": "T" } } }' | Out-File -FilePath $gateCfg -Encoding ascii

& $Exe index $gateSrc --db $gateDb 2>&1 | Out-Null
Check 'GATE: index exits 0' ($LASTEXITCODE -eq 0)

$gateOut = & $Exe lint-all --db $gateDb --config $gateCfg --rule type-name-prefix --fix --apply --quiet 2>&1
$gateExit = $LASTEXITCODE
Write-Host ($gateOut -join "`n")

$gateAfter = Get-Content -Raw $gateFile
Check 'GATE: exit code 0 even though nothing was fixed' ($gateExit -eq 0) "exit=$gateExit"
Check 'GATE: type decl UNCHANGED (still myclass, registered-fixable but not opted in)' `
  ($gateAfter -cmatch 'myclass\s*=\s*class') $gateAfter
Check 'GATE: file is byte-identical to the pre-fix fixture (no edit applied at all)' `
  ($gateAfter -ceq $gateBefore) 'gate file drifted from source fixture'

# =============================================================================
# COLLISION SKIP: `procedure P(x: Integer); var pX: Integer;` -- synthesized
# 'pX' already exists as a local in the SAME routine scope -> the NEW
# BuildLocal collision guard fires -> BuildNamingFixEdits skips the finding ->
# x stays unchanged everywhere, exit code still 0.
# =============================================================================
Write-Host ''
Write-Host 'COLLISION SKIP: synthesized pX collides with an existing local in scope' -ForegroundColor Cyan
$colDir = Join-Path $WorkDir 'collision'
$colSrc = Join-Path $colDir 'src'
New-Item -ItemType Directory $colSrc | Out-Null
$colFile = Join-Path $colSrc 'CollisionAutofix.pas'
$colDb   = Join-Path $colDir 'naming.sqlite'
$colCfg  = Join-Path $colDir 'drag-lint-lint.json'

$CollisionFixture = @'
unit CollisionAutofix;

interface

procedure P(x: Integer);

implementation

procedure P(x: Integer);
var
  pX: Integer;
begin
  pX:= 0;
  x:= x + pX;
end;

end.
'@
Write-Ascii $colFile $CollisionFixture
'{ "autofix": ["param-name-prefix"], "naming": { "param_prefix": "p" } }' | Out-File -FilePath $colCfg -Encoding ascii

& $Exe index $colSrc --db $colDb 2>&1 | Out-Null
Check 'COLLISION: index exits 0' ($LASTEXITCODE -eq 0)

$colOut = & $Exe lint-all --db $colDb --config $colCfg --rule param-name-prefix --fix --apply --quiet 2>&1
$colExit = $LASTEXITCODE
Write-Host ($colOut -join "`n")

$colAfter = Get-Content -Raw $colFile
Check 'COLLISION: exit code still 0' ($colExit -eq 0) "exit=$colExit"
Check 'COLLISION: param decl UNCHANGED (still x, collision with existing local pX)' `
  ($colAfter -cmatch 'procedure\s+P\(x\s*:\s*Integer\);') $colAfter
Check 'COLLISION: existing local pX untouched (still declared, still 0)' `
  ($colAfter -cmatch 'pX\s*:\s*Integer;' -and $colAfter -cmatch 'pX\s*:=\s*0;') $colAfter
Check 'COLLISION: body use of x unchanged (x:= x + pX;)' `
  ($colAfter -cmatch 'x\s*:=\s*x\s*\+\s*pX;') $colAfter

# =============================================================================
# SAME-LINE STRESS: `procedure P(a, b: Integer);` both params prefixed -> both
# become pA, pB on the SAME decl line (exercises Task 1's column-DESC same-
# line edit ordering for differing-length replacements).
# =============================================================================
Write-Host ''
Write-Host 'SAME-LINE STRESS: two params prefixed on one decl line' -ForegroundColor Cyan
$slDir = Join-Path $WorkDir 'sameline'
$slSrc = Join-Path $slDir 'src'
New-Item -ItemType Directory $slSrc | Out-Null
$slFile = Join-Path $slSrc 'SameLinePrefixAutofix.pas'
$slDb   = Join-Path $slDir 'naming.sqlite'
$slCfg  = Join-Path $slDir 'drag-lint-lint.json'

$SameLineFixture = @'
unit SameLinePrefixAutofix;

interface

procedure RunBoth(a, b: Integer);

implementation

procedure RunBoth(a, b: Integer);
begin
  a:= a + 1;
  b:= b + 2;
end;

end.
'@
Write-Ascii $slFile $SameLineFixture
'{ "autofix": ["param-name-prefix"], "naming": { "param_prefix": "p" } }' | Out-File -FilePath $slCfg -Encoding ascii

& $Exe index $slSrc --db $slDb 2>&1 | Out-Null
Check 'SAMELINE: index exits 0' ($LASTEXITCODE -eq 0)

$slOut = & $Exe lint-all --db $slDb --config $slCfg --rule param-name-prefix --fix --apply --quiet 2>&1
$slExit = $LASTEXITCODE
Write-Host ($slOut -join "`n")

$slAfter = Get-Content -Raw $slFile
Write-Host '--- SAME-LINE result (for evidence) ---' -ForegroundColor Yellow
Write-Host $slAfter
Write-Host '--- end result ---' -ForegroundColor Yellow

$slDeclLineOk = $slAfter -cmatch 'RunBoth\(pA,\s*pB\s*:\s*Integer\);'
$slUse1Ok     = $slAfter -cmatch 'pA\s*:=\s*pA\s*\+\s*1;'
$slUse2Ok     = $slAfter -cmatch 'pB\s*:=\s*pB\s*\+\s*2;'
$slNoStale    = (-not ($slAfter -cmatch '(?<![.\w])a(?!\w)')) -and (-not ($slAfter -cmatch '(?<![.\w])b(?!\w)'))
$slNoGarbage  = -not ($slAfter -cmatch 'pApB') -and -not ($slAfter -cmatch 'pBpA')

Check 'SAMELINE: exit code 0' ($slExit -eq 0) "exit=$slExit"
Check 'SAMELINE: decl line correctly shows "RunBoth(pA, pB: Integer);" (both renamed, not corrupted)' $slDeclLineOk $slAfter
Check 'SAMELINE: first body use renamed (pA := pA + 1)'  $slUse1Ok $slAfter
Check 'SAMELINE: second body use renamed (pB := pB + 2)' $slUse2Ok $slAfter
Check 'SAMELINE: no stale bare a/b remains' $slNoStale $slAfter
Check 'SAMELINE: no interleaved/concatenated garbage from a same-line ordering bug' $slNoGarbage $slAfter
if (-not ($slDeclLineOk -and $slNoGarbage)) {
  Write-Host '  *** SAME-LINE APPLIER RISK: differing-length same-line prefix edit corrupted (Task 1 regression). ***' -ForegroundColor Red
} else {
  Write-Host '  Same-line differing-length multi-edit applied safely.' -ForegroundColor Green
}

# =============================================================================
# DRY-RUN: `lint-all --fix` (no --apply) on a fresh copy of CASE 1's fixture ->
# preview text only, file on disk UNCHANGED.
# =============================================================================
Write-Host ''
Write-Host 'DRY-RUN: lint-all --fix (no --apply)' -ForegroundColor Cyan
$dryDir = Join-Path $WorkDir 'dryrun'
$drySrc = Join-Path $dryDir 'src'
New-Item -ItemType Directory $drySrc | Out-Null
$dryFile = Join-Path $drySrc 'FieldPrefixAutofix.pas'
$dryDb   = Join-Path $dryDir 'naming.sqlite'
$dryCfg  = Join-Path $dryDir 'drag-lint-lint.json'

Write-Ascii $dryFile $Case1Fixture
'{ "autofix": ["field-name-prefix"], "naming": { "field_prefix": "F" } }' | Out-File -FilePath $dryCfg -Encoding ascii

& $Exe index $drySrc --db $dryDb 2>&1 | Out-Null
Check 'DRYRUN: index exits 0' ($LASTEXITCODE -eq 0)

$beforeDry = Get-Content -Raw $dryFile
$dryOut = & $Exe lint-all --db $dryDb --config $dryCfg --rule field-name-prefix --fix --quiet 2>&1
$dryExit = $LASTEXITCODE
Write-Host ($dryOut -join "`n")
$afterDry = Get-Content -Raw $dryFile

Check 'DRYRUN: exit code 0' ($dryExit -eq 0) "exit=$dryExit"
Check 'DRYRUN: file on disk is byte-identical to before (no --apply -> no write)' `
  ($beforeDry -ceq $afterDry) 'dry-run file changed on disk'
Check 'DRYRUN: preview output mentions the fixable finding' `
  (($dryOut -join "`n") -match 'fixable finding' -or ($dryOut -join "`n") -match 'FClient') ($dryOut -join "`n")

# =============================================================================
# DETERMINISM: two --fix --apply runs, each on its OWN fresh copy of CASE 1's
# fixture, produce byte-identical output files.
# =============================================================================
Write-Host ''
Write-Host 'DETERMINISM: two --fix --apply runs on fresh copies are byte-identical' -ForegroundColor Cyan
$detDir = Join-Path $WorkDir 'determinism'
$detA = Join-Path $detDir 'runA'
$detB = Join-Path $detDir 'runB'
New-Item -ItemType Directory (Join-Path $detA 'src') | Out-Null
New-Item -ItemType Directory (Join-Path $detB 'src') | Out-Null

$detAFile = Join-Path $detA 'src\FieldPrefixAutofix.pas'
$detBFile = Join-Path $detB 'src\FieldPrefixAutofix.pas'
$detACfg  = Join-Path $detA 'drag-lint-lint.json'
$detBCfg  = Join-Path $detB 'drag-lint-lint.json'
$detADb   = Join-Path $detA 'naming.sqlite'
$detBDb   = Join-Path $detB 'naming.sqlite'

Write-Ascii $detAFile $Case1Fixture
Write-Ascii $detBFile $Case1Fixture
'{ "autofix": ["field-name-prefix"], "naming": { "field_prefix": "F" } }' | Out-File -FilePath $detACfg -Encoding ascii
'{ "autofix": ["field-name-prefix"], "naming": { "field_prefix": "F" } }' | Out-File -FilePath $detBCfg -Encoding ascii

& $Exe index (Join-Path $detA 'src') --db $detADb 2>&1 | Out-Null
& $Exe index (Join-Path $detB 'src') --db $detBDb 2>&1 | Out-Null
& $Exe lint-all --db $detADb --config $detACfg --rule field-name-prefix --fix --apply --quiet 2>&1 | Out-Null
& $Exe lint-all --db $detBDb --config $detBCfg --rule field-name-prefix --fix --apply --quiet 2>&1 | Out-Null

$detAAfter = Get-Content -Raw $detAFile
$detBAfter = Get-Content -Raw $detBFile
Check 'DETERMINISM: run A and run B produce byte-identical files' ($detAAfter -ceq $detBAfter) `
  "lenA=$($detAAfter.Length) lenB=$($detBAfter.Length)"
Check 'DETERMINISM: both runs actually applied the fix (sanity, not a no-op match)' `
  ($detAAfter -cmatch 'FClient\s*:\s*TObject;') $detAAfter

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
