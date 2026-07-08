<#
  run_naming_autofix.ps1 -- Batch C Task 6/7: naming re-casing findings
  (method-pascalcase, local-var-casing, const-casing) become FIXABLE via the
  rename engine (DRagLint.Refactor.NamingFix.BuildNamingFixEdits), applied
  through the existing store-backed append in FinalizeAndOutput (mirrors the
  doc-drift/missing-doc pattern), opt-in only via config "autofix": [...].

  Task 6 owned the MINIMAL RED->GREEN skeleton (one rule: method-pascalcase,
  opted in via AutoFixIds, `lint-all --fix --apply` rewrites the decl AND
  every call site) -- CASE 1 below, kept verbatim (still the same fixture +
  assertions). Task 7 expands this into the full per-rule battery:
    CASE 1 method-pascalcase   -- decl + both call sites renamed.
    CASE 2 local-var-casing    -- BuildLocal rewrites decl + both uses inside
                                   the owning routine; nothing outside changes.
    CASE 3 const-casing        -- unit-level const renamed at decl + use;
                                   naming.const_case:["UPPER_CASE"] so the
                                   synthesizer picks UPPER_CASE (ConstCase[0]),
                                   not the default ['PascalCase','UPPER_CASE']
                                   (which would pick PascalCase as [0] and
                                   produce a no-op rename).
    OPT-IN GATE                -- CASE 3's fixture re-run with "autofix" NOT
                                   listing const-casing -> registered-fixable
                                   (rules --json) but not permitted -> no edit.
    CONFLICT SKIP              -- a class with mis-cased doThing AND an
                                   existing correctly-cased sibling DoThing ->
                                   TRenameRefactoring.ConflictReason fires ->
                                   BuildNamingFixEdits skips the finding ->
                                   doThing stays unchanged, exit still 0.
    DRY-RUN                    -- `lint --fix` (no --apply) previews only;
                                   file on disk is untouched.
    DETERMINISM                -- two --fix --apply runs on fresh copies of
                                   the same pre-fix fixture produce byte-
                                   identical output files.
    SAME-LINE STRESS           -- two mis-cased locals declared on ONE line
                                   (`var myFirst, mySecond: Integer;`) so
                                   BuildNamingFixEdits emits two
                                   tekReplaceInLine edits on the same decl
                                   line at different columns. TTextEditApplier
                                   sorts same-file edits by line ONLY (no
                                   column tiebreak, unlike TRenameRefactoring's
                                   own FilePath/Line DESC/Col DESC sort) --
                                   this fixture exercises that latent gap.
                                   Assert the result is NOT corrupted (both
                                   idents correctly renamed, no interleaved/
                                   truncated text); if it IS corrupted, that is
                                   a real bug to report, not to fix here (the
                                   applier is out of scope for this task).

  Each fixture indexes into its OWN fresh sqlite db (isolation -- avoids
  cross-fixture symbol-name collisions in FindChildSymbolByName/
  FindCallersByName, which match by bare short name across the whole store).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-naming-autofix"
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
# Absolutize so the exe path survives regardless of CWD (mirrors run_doc_drift_typedecl.ps1).
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
# CASE 1: method-pascalcase (Task 6's original fixture, kept verbatim)
# =============================================================================
Write-Host 'CASE 1: method-pascalcase' -ForegroundColor Cyan
$c1Dir = Join-Path $WorkDir 'case1'
$c1Src = Join-Path $c1Dir 'src'
New-Item -ItemType Directory $c1Src | Out-Null
$c1File = Join-Path $c1Src 'NamingAutofix.pas'
$c1Db   = Join-Path $c1Dir 'naming.sqlite'
$c1Cfg  = Join-Path $c1Dir 'drag-lint-lint.json'

$Case1Fixture = @'
unit NamingAutofix;

interface

type
  TThing = class
  public
    procedure doSomething;
  end;

procedure RunIt;

implementation

procedure TThing.doSomething;
begin
end;

procedure RunIt;
var
  Thing: TThing;
begin
  Thing:= TThing.Create;
  try
    Thing.doSomething;
  finally
    Thing.Free;
  end;
end;

end.
'@
Write-Ascii $c1File $Case1Fixture
'{ "autofix": ["method-pascalcase"] }' | Out-File -FilePath $c1Cfg -Encoding ascii

& $Exe index $c1Src --db $c1Db 2>&1 | Out-Null
Check 'CASE1: index exits 0' ($LASTEXITCODE -eq 0)
Check 'CASE1: db built' (Test-Path $c1Db)

$out = & $Exe lint-all --db $c1Db --config $c1Cfg --rule method-pascalcase --fix --apply --quiet 2>&1
Write-Host ($out -join "`n")

$after = Get-Content -Raw $c1File
# -cmatch/-cnotmatch: CASE-SENSITIVE (PowerShell's plain -match is case-insensitive
# by default, which would silently pass on a still-mis-cased "doSomething").
Check 'CASE1: interface declaration renamed to DoSomething'      ($after -cmatch 'procedure\s+DoSomething;')
Check 'CASE1: implementation header renamed to TThing.DoSomething' ($after -cmatch 'procedure\s+TThing\.DoSomething;')
Check 'CASE1: call site renamed to Thing.DoSomething'             ($after -cmatch 'Thing\.DoSomething;')
Check 'CASE1: no stale lower-case doSomething interface decl remains' (-not ($after -cmatch 'procedure\s+doSomething;'))
Check 'CASE1: no stale lower-case TThing.doSomething impl header remains' (-not ($after -cmatch 'TThing\.doSomething;'))
Check 'CASE1: no stale lower-case doSomething call site remains'  (-not ($after -cmatch 'Thing\.doSomething;'))

# =============================================================================
# CASE 2: local-var-casing -- BuildLocal rewrites decl + both uses; nothing
# outside the routine changes. Second unrelated routine (OtherRoutine, with
# its own unrelated local) is the negative-scope witness.
# =============================================================================
Write-Host ''
Write-Host 'CASE 2: local-var-casing' -ForegroundColor Cyan
$c2Dir = Join-Path $WorkDir 'case2'
$c2Src = Join-Path $c2Dir 'src'
New-Item -ItemType Directory $c2Src | Out-Null
$c2File = Join-Path $c2Src 'LocalVarAutofix.pas'
$c2Db   = Join-Path $c2Dir 'naming.sqlite'
$c2Cfg  = Join-Path $c2Dir 'drag-lint-lint.json'

$Case2Fixture = @'
unit LocalVarAutofix;

interface

procedure RunLocal;
procedure OtherRoutine;

implementation

procedure RunLocal;
var
  myLocal: Integer;
begin
  myLocal:= 1;
  myLocal:= myLocal + 1;
end;

procedure OtherRoutine;
var
  Untouched: Integer;
begin
  Untouched:= 5;
end;

end.
'@
Write-Ascii $c2File $Case2Fixture
'{ "autofix": ["local-var-casing"] }' | Out-File -FilePath $c2Cfg -Encoding ascii

& $Exe index $c2Src --db $c2Db 2>&1 | Out-Null
Check 'CASE2: index exits 0' ($LASTEXITCODE -eq 0)

$out2 = & $Exe lint-all --db $c2Db --config $c2Cfg --rule local-var-casing --fix --apply --quiet 2>&1
Write-Host ($out2 -join "`n")

$after2 = Get-Content -Raw $c2File
# Assert decl + both uses renamed (3 occurrences of MyLocal), and no stale
# lower-case myLocal survives anywhere in the file.
$declRenamed  = $after2 -cmatch 'MyLocal\s*:\s*Integer;'
$use1Renamed  = $after2 -cmatch 'MyLocal\s*:=\s*1;'
$use2Renamed  = $after2 -cmatch 'MyLocal\s*:=\s*MyLocal\s*\+\s*1;'
$noStaleLower = -not ($after2 -cmatch 'myLocal')
$otherUntouched = $after2 -cmatch 'Untouched\s*:\s*Integer;' -and $after2 -cmatch 'Untouched\s*:=\s*5;'
Check 'CASE2: local decl renamed to MyLocal'          $declRenamed  $after2
Check 'CASE2: first use renamed to MyLocal := 1'      $use1Renamed  $after2
Check 'CASE2: second use renamed to MyLocal := MyLocal + 1' $use2Renamed $after2
Check 'CASE2: no stale lower-case myLocal remains anywhere' $noStaleLower $after2
Check 'CASE2: unrelated OtherRoutine local (Untouched) unchanged' $otherUntouched $after2

# =============================================================================
# CASE 3: const-casing -- unit-level const 'maxItems' with const_case:
# ["UPPER_CASE"] (single-entry, so SynthesizeCasedName picks UPPER_CASE, not
# PascalCase which is ConstCase[0] under the default two-entry list) becomes
# MAXITEMS at decl + use.
# =============================================================================
Write-Host ''
Write-Host 'CASE 3: const-casing' -ForegroundColor Cyan
$c3Dir = Join-Path $WorkDir 'case3'
$c3Src = Join-Path $c3Dir 'src'
New-Item -ItemType Directory $c3Src | Out-Null
$c3File = Join-Path $c3Src 'ConstAutofix.pas'
$c3Db   = Join-Path $c3Dir 'naming.sqlite'
$c3Cfg  = Join-Path $c3Dir 'drag-lint-lint.json'

# NOTE (finding, see task report): the const is used as a CALL ARGUMENT
# (`SetLimit(maxItems)`), not as a bare RHS of an assignment. Verified via
# research + a failed first attempt: DRagLint.Parser.Delphi13.pas's deep-scan
# usage-ref emission (the 'EmitUsageRefs' Walk block, ~line 1343) only emits a
# 'read' reference for a bare identifier in an exprDot base, an exprArgs call
# argument, or an attribute -- NOT for a bare identifier as the RHS value of an
# assignment (`Result:= maxItems;` recurses generically and the leaf identifier
# matches none of the four handled shapes, so no ref row is ever written for
# it, even with --deep, which is the index default here). That is a real,
# pre-existing gap in the reference engine (not something Task 6/7 introduced),
# so TRenameRefactoring.Build's FindCallersByName('maxItems') finds nothing to
# rename at a bare-assignment use site. A call-argument use IS covered by the
# exprArgs handler, so it is the shape used here to exercise "decl + use" for
# real, within the engine's current capability.
$Case3Fixture = @'
unit ConstAutofix;

interface

const
  maxItems = 10;

procedure SetLimit(ALimit: Integer);
procedure ApplyDefaultLimit;

implementation

procedure SetLimit(ALimit: Integer);
begin
end;

procedure ApplyDefaultLimit;
begin
  SetLimit(maxItems);
end;

end.
'@
Write-Ascii $c3File $Case3Fixture
'{ "autofix": ["const-casing"], "naming": { "const_case": ["UPPER_CASE"] } }' | Out-File -FilePath $c3Cfg -Encoding ascii

& $Exe index $c3Src --db $c3Db 2>&1 | Out-Null
Check 'CASE3: index exits 0' ($LASTEXITCODE -eq 0)

$out3 = & $Exe lint-all --db $c3Db --config $c3Cfg --rule const-casing --fix --apply --quiet 2>&1
Write-Host ($out3 -join "`n")

$after3 = Get-Content -Raw $c3File
$c3DeclRenamed = $after3 -cmatch 'MAXITEMS\s*=\s*10;'
$c3UseRenamed  = $after3 -cmatch 'SetLimit\(MAXITEMS\);'
$c3NoStale     = -not ($after3 -cmatch 'maxItems')
Check 'CASE3: const decl renamed to MAXITEMS' $c3DeclRenamed $after3
Check 'CASE3: call-argument use renamed to SetLimit(MAXITEMS)' $c3UseRenamed $after3
Check 'CASE3: no stale lower-camel maxItems remains' $c3NoStale $after3

# =============================================================================
# OPT-IN GATE: same const-casing fixture, but "autofix" does NOT list
# const-casing -> registered-fixable (rules --json) but not permitted ->
# identifier UNCHANGED.
# =============================================================================
Write-Host ''
Write-Host 'OPT-IN GATE: const-casing not opted in via AutoFixIds' -ForegroundColor Cyan
$gateDir = Join-Path $WorkDir 'gate'
$gateSrc = Join-Path $gateDir 'src'
New-Item -ItemType Directory $gateSrc | Out-Null
$gateFile = Join-Path $gateSrc 'ConstAutofix.pas'
$gateDb   = Join-Path $gateDir 'naming.sqlite'
$gateCfg  = Join-Path $gateDir 'drag-lint-lint.json'

Write-Ascii $gateFile $Case3Fixture
# Snapshot the on-disk bytes right after Write-Ascii (before indexing/fixing)
# so the byte-identity check below compares disk-to-disk, not disk-to-a-
# reconstructed-here-string (whose CRLF/trailing-newline shape need not match
# what Write-Ascii actually wrote).
$gateBefore = Get-Content -Raw $gateFile
# "autofix" deliberately omits const-casing (opts in an UNRELATED rule instead,
# so the config isn't simply "no autofix at all" but a real not-in-the-list case).
'{ "autofix": ["method-pascalcase"], "naming": { "const_case": ["UPPER_CASE"] } }' | Out-File -FilePath $gateCfg -Encoding ascii

& $Exe index $gateSrc --db $gateDb 2>&1 | Out-Null
Check 'GATE: index exits 0' ($LASTEXITCODE -eq 0)

$gateOut = & $Exe lint-all --db $gateDb --config $gateCfg --rule const-casing --fix --apply --quiet 2>&1
$gateExit = $LASTEXITCODE
Write-Host ($gateOut -join "`n")

$gateAfter = Get-Content -Raw $gateFile
Check 'GATE: exit code 0 even though nothing was fixed' ($gateExit -eq 0) "exit=$gateExit"
Check 'GATE: const decl UNCHANGED (still maxItems, registered-fixable but not opted in)' `
  ($gateAfter -cmatch 'maxItems\s*=\s*10;') $gateAfter
Check 'GATE: call-argument use site UNCHANGED (still SetLimit(maxItems))' `
  ($gateAfter -cmatch 'SetLimit\(maxItems\);') $gateAfter
Check 'GATE: file is byte-identical to the pre-fix fixture (no edit applied at all)' `
  ($gateAfter -ceq $gateBefore) 'gate file drifted from source fixture'

# =============================================================================
# CONFLICT SKIP: TConflict has a mis-cased method doThing AND an existing
# correctly-cased sibling method DoThing already declared on the SAME class ->
# TRenameRefactoring.ConflictReason (sibling-name collision under the same
# parent) fires -> BuildNamingFixEdits skips the finding -> doThing stays
# unchanged, exit code still 0.
# =============================================================================
Write-Host ''
Write-Host 'CONFLICT SKIP: synthesized name collides with an existing sibling' -ForegroundColor Cyan
$confDir = Join-Path $WorkDir 'conflict'
$confSrc = Join-Path $confDir 'src'
New-Item -ItemType Directory $confSrc | Out-Null
$confFile = Join-Path $confSrc 'ConflictAutofix.pas'
$confDb   = Join-Path $confDir 'naming.sqlite'
$confCfg  = Join-Path $confDir 'drag-lint-lint.json'

$ConflictFixture = @'
unit ConflictAutofix;

interface

type
  TConflict = class
  public
    procedure doThing;
    procedure DoThing;
  end;

implementation

procedure TConflict.doThing;
begin
end;

procedure TConflict.DoThing;
begin
end;

end.
'@
Write-Ascii $confFile $ConflictFixture
'{ "autofix": ["method-pascalcase"] }' | Out-File -FilePath $confCfg -Encoding ascii

& $Exe index $confSrc --db $confDb 2>&1 | Out-Null
Check 'CONFLICT: index exits 0' ($LASTEXITCODE -eq 0)

$confOut = & $Exe lint-all --db $confDb --config $confCfg --rule method-pascalcase --fix --apply --quiet 2>&1
$confExit = $LASTEXITCODE
Write-Host ($confOut -join "`n")

$confAfter = Get-Content -Raw $confFile
Check 'CONFLICT: exit code still 0' ($confExit -eq 0) "exit=$confExit"
Check 'CONFLICT: doThing decl UNCHANGED (conflict with sibling DoThing)' `
  ($confAfter -cmatch 'procedure\s+doThing;') $confAfter
Check 'CONFLICT: doThing impl header UNCHANGED' `
  ($confAfter -cmatch 'procedure\s+TConflict\.doThing;') $confAfter
Check 'CONFLICT: sibling DoThing untouched' `
  ($confAfter -cmatch 'procedure\s+TConflict\.DoThing;') $confAfter

# =============================================================================
# DRY-RUN: `lint --fix` (no --apply) on a fresh copy of CASE 1's fixture ->
# preview text only, file on disk UNCHANGED.
# =============================================================================
Write-Host ''
Write-Host 'DRY-RUN: lint-all --fix (no --apply)' -ForegroundColor Cyan
$dryDir = Join-Path $WorkDir 'dryrun'
$drySrc = Join-Path $dryDir 'src'
New-Item -ItemType Directory $drySrc | Out-Null
$dryFile = Join-Path $drySrc 'NamingAutofix.pas'
$dryDb   = Join-Path $dryDir 'naming.sqlite'
$dryCfg  = Join-Path $dryDir 'drag-lint-lint.json'

Write-Ascii $dryFile $Case1Fixture
'{ "autofix": ["method-pascalcase"] }' | Out-File -FilePath $dryCfg -Encoding ascii

& $Exe index $drySrc --db $dryDb 2>&1 | Out-Null
Check 'DRYRUN: index exits 0' ($LASTEXITCODE -eq 0)

$beforeDry = Get-Content -Raw $dryFile
$dryOut = & $Exe lint-all --db $dryDb --config $dryCfg --rule method-pascalcase --fix --quiet 2>&1
$dryExit = $LASTEXITCODE
Write-Host ($dryOut -join "`n")
$afterDry = Get-Content -Raw $dryFile

Check 'DRYRUN: exit code 0' ($dryExit -eq 0) "exit=$dryExit"
Check 'DRYRUN: file on disk is byte-identical to before (no --apply -> no write)' `
  ($beforeDry -ceq $afterDry) 'dry-run file changed on disk'
Check 'DRYRUN: preview output mentions the fixable finding' `
  (($dryOut -join "`n") -match 'fixable finding' -or ($dryOut -join "`n") -match 'DoSomething') ($dryOut -join "`n")

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

$detAFile = Join-Path $detA 'src\NamingAutofix.pas'
$detBFile = Join-Path $detB 'src\NamingAutofix.pas'
$detACfg  = Join-Path $detA 'drag-lint-lint.json'
$detBCfg  = Join-Path $detB 'drag-lint-lint.json'
$detADb   = Join-Path $detA 'naming.sqlite'
$detBDb   = Join-Path $detB 'naming.sqlite'

Write-Ascii $detAFile $Case1Fixture
Write-Ascii $detBFile $Case1Fixture
'{ "autofix": ["method-pascalcase"] }' | Out-File -FilePath $detACfg -Encoding ascii
'{ "autofix": ["method-pascalcase"] }' | Out-File -FilePath $detBCfg -Encoding ascii

& $Exe index (Join-Path $detA 'src') --db $detADb 2>&1 | Out-Null
& $Exe index (Join-Path $detB 'src') --db $detBDb 2>&1 | Out-Null
& $Exe lint-all --db $detADb --config $detACfg --rule method-pascalcase --fix --apply --quiet 2>&1 | Out-Null
& $Exe lint-all --db $detBDb --config $detBCfg --rule method-pascalcase --fix --apply --quiet 2>&1 | Out-Null

$detAAfter = Get-Content -Raw $detAFile
$detBAfter = Get-Content -Raw $detBFile
Check 'DETERMINISM: run A and run B produce byte-identical files' ($detAAfter -ceq $detBAfter) `
  "lenA=$($detAAfter.Length) lenB=$($detBAfter.Length)"
Check 'DETERMINISM: both runs actually applied the fix (sanity, not a no-op match)' `
  ($detAAfter -cmatch 'procedure\s+DoSomething;') $detAAfter

# =============================================================================
# SAME-LINE STRESS: two mis-cased locals declared on ONE line
# (`var myFirst, mySecond: Integer;`) -> BuildNamingFixEdits emits two
# tekReplaceInLine edits on the SAME decl line at different columns.
# TTextEditApplier.Apply sorts same-file edits by EditTopLine (= Line) ONLY --
# no column tiebreak -- unlike TRenameRefactoring's own FilePath/Line DESC/
# Col DESC sort. This stresses that latent gap: assert both idents end up
# correctly renamed and the line is not corrupted (no interleaving/truncation/
# duplication). If corrupted, this is a REAL BUG in TTextEditApplier -- report
# it, do not fix it here (out of scope for this task).
# =============================================================================
Write-Host ''
Write-Host 'SAME-LINE STRESS: two mis-cased locals on one decl line' -ForegroundColor Cyan
$slDir = Join-Path $WorkDir 'sameline'
$slSrc = Join-Path $slDir 'src'
New-Item -ItemType Directory $slSrc | Out-Null
$slFile = Join-Path $slSrc 'SameLineAutofix.pas'
$slDb   = Join-Path $slDir 'naming.sqlite'
$slCfg  = Join-Path $slDir 'drag-lint-lint.json'

$SameLineFixture = @'
unit SameLineAutofix;

interface

procedure RunBoth;

implementation

procedure RunBoth;
var
  myFirst, mySecond: Integer;
begin
  myFirst:= 1;
  mySecond:= 2;
  myFirst:= myFirst + mySecond;
end;

end.
'@
Write-Ascii $slFile $SameLineFixture
'{ "autofix": ["local-var-casing"] }' | Out-File -FilePath $slCfg -Encoding ascii

& $Exe index $slSrc --db $slDb 2>&1 | Out-Null
Check 'SAMELINE: index exits 0' ($LASTEXITCODE -eq 0)

$slOut = & $Exe lint-all --db $slDb --config $slCfg --rule local-var-casing --fix --apply --quiet 2>&1
$slExit = $LASTEXITCODE
Write-Host ($slOut -join "`n")

$slAfter = Get-Content -Raw $slFile
Write-Host '--- SAME-LINE result (for evidence) ---' -ForegroundColor Yellow
Write-Host $slAfter
Write-Host '--- end result ---' -ForegroundColor Yellow

$slDeclLineOk  = $slAfter -cmatch 'MyFirst,\s*MySecond\s*:\s*Integer;'
$slUse1Ok      = $slAfter -cmatch 'MyFirst\s*:=\s*1;'
$slUse2Ok      = $slAfter -cmatch 'MySecond\s*:=\s*2;'
$slUse3Ok      = $slAfter -cmatch 'MyFirst\s*:=\s*MyFirst\s*\+\s*MySecond;'
$slNoStale     = -not ($slAfter -cmatch 'myFirst') -and -not ($slAfter -cmatch 'mySecond')
$slNoGarbage   = -not ($slAfter -cmatch 'MyFirstMySecond') -and -not ($slAfter -cmatch 'MySecondMyFirst')

Check 'SAMELINE: exit code 0' ($slExit -eq 0) "exit=$slExit"
Check 'SAMELINE: decl line correctly shows "MyFirst, MySecond: Integer;" (both renamed, not corrupted)' $slDeclLineOk $slAfter
Check 'SAMELINE: first use renamed (MyFirst := 1)'  $slUse1Ok $slAfter
Check 'SAMELINE: second use renamed (MySecond := 2)' $slUse2Ok $slAfter
Check 'SAMELINE: combined-use line renamed (MyFirst := MyFirst + MySecond)' $slUse3Ok $slAfter
Check 'SAMELINE: no stale lower-case myFirst/mySecond remains' $slNoStale $slAfter
Check 'SAMELINE: no interleaved/concatenated garbage from a same-line ordering bug' $slNoGarbage $slAfter
if (-not ($slDeclLineOk -and $slNoGarbage)) {
  Write-Host '  *** SAME-LINE APPLIER RISK CONFIRMED: TTextEditApplier corrupted a same-line multi-edit. ***' -ForegroundColor Red
} else {
  Write-Host '  Same-line multi-edit applied safely (no column-ordering corruption observed in this fixture).' -ForegroundColor Green
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
