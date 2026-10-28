<#
  run_multi_project_rename.ps1 -- a naming fix on a unit compiled by SEVERAL
  project DBs renames it in EVERY owning project, or refuses.

  Spec: docs\superpowers\specs\2026-10-13-multi-project-rename.md, criteria
  1, 2, 6-11, 14, 15, 8d, 8e. Engine: PlanMultiProjectRename
  (DRagLint.Refactor.MultiProjectRename) wired into `lint --fix`.

  FIXTURE (all under $env:TEMP\draglint-mpr-<guid>, NOTHING under C:\Projects):
    shared\uShared.pas  `My_Const = 1;` -- the unit under test
    A\A.dpr             lists uShared (..\shared\) and uA, which reads My_Const
    B\B.dpr             same shape, with uB
    C\C.dproj/C.dpr     lists only uMid, which uses uShared -- the TRANSITIVE
                        owner, reached through DCC_UnitSearchPath=..\shared
    D\D.dpr             its OWN twin\uShared.pas (same unit name, other path):
                        never an owner, never touched
  An engine COPY runs from <work>\eng with the fixture's own drag-lint.json
  beside it, so the real manifest and the real DBs are never read.

  Cases: preview, apply-all, cand-split (+ refusal), batch-drop, stale-owner,
  wrongdb (a DB stamped with another project's tag), member-missing,
  transitive-missing (B-03: a closure unit no project file lists, created after
  indexing -- the apply must rename it too, proven by re-index + dcc64),
  corrupt-db, library-owner, single-project (criterion 15: no rename- lines).

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param([string]$EngineDir = "$PSScriptRoot\..\..\src\cli\Win64\Debug")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
function WriteAscii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
function LastAutofix([string]$Out) { [string]((($Out -split "`r?`n") | Where-Object { $_ -match '^autofix:' }) | Select-Object -Last 1) }
function Lines([string]$Out, [string]$Pattern) { (($Out -split "`r?`n") | Where-Object { $_ -match $Pattern }) -join ' | ' }

$RealDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
$RealDb2 = 'C:\Projects\DB\ORM3\CLIENT\DM\_D-RAG\DMTEST.sqlite'
function RealStamp { (@($RealDb, $RealDb2) | ForEach-Object { if (Test-Path $_) { $i = Get-Item $_; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' } }) -join ',' }
$realBefore = RealStamp

Write-Host '== Multi-project rename: every owning project, or refuse ==' -ForegroundColor Cyan
$EngineDir = (Resolve-Path $EngineDir).Path
$work = Join-Path $env:TEMP ('draglint-mpr-' + [Guid]::NewGuid().ToString('N'))
$eng  = Join-Path $work 'eng'
New-Item -ItemType Directory -Force $eng | Out-Null
# the engine copy: exe + tree-sitter companions + rules\ (what build_draglint_win64.bat stages)
foreach ($f in 'drag-lint.exe', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll', 'casts.castlib') {
  if (Test-Path "$EngineDir\$f") { Copy-Item "$EngineDir\$f" "$eng\$f" }
}
$rulesSrc = if (Test-Path "$EngineDir\rules") { "$EngineDir\rules" } else { Join-Path $PSScriptRoot '..\..\rules' }  # worktree build dir has no staged rules\
Copy-Item $rulesSrc "$eng\rules" -Recurse
$Exe = Join-Path $eng 'drag-lint.exe'  # the COPY; built from $EngineDir above
$script:AllOut = ''

function Run([string[]]$EngArgs) {
  Push-Location $work
  try { $o = (& $Exe @EngArgs 2>&1 | Out-String) } finally { Pop-Location }
  $script:AllOut += $o
  return $o
}

# stdout ONLY (stderr dropped): for --json, whose rename- lines go to stderr
function RunStdout([string[]]$EngArgs) {
  Push-Location $work
  try { $o = (& $Exe @EngArgs 2>$null | Out-String) } finally { Pop-Location }
  $script:AllOut += $o
  return $o
}

function UnitUser([string]$Name, [string]$Expr, [string[]]$Extra = @(), [string[]]$Uses = @('uShared')) {
  $l = @("unit $Name;", '', 'interface', '', 'uses', ('  ' + ($Uses -join ', ') + ';'), '')
  if ($Extra.Count -gt 0) { $l += 'const'; $l += $Extra; $l += '' }
  $l += @('function Get: Integer;', '', 'implementation', '', 'function Get: Integer;', 'begin', "  Result:= $Expr;", 'end;', '', 'end.')
  return $l
}

# Rebuilds the whole fixture from scratch and indexes every project.
function Reset {
  param([string[]]$SharedConsts = @('  My_Const = 1;'), [string]$Expr = 'My_Const',
        [string[]]$BExtra = @(), [string[]]$ConstCase = @(), [switch]$Library, [switch]$NoOptIn, [switch]$Unindexed,
        [string[]]$MidUses = @('uShared'))
  foreach ($d in 'shared', 'twin', 'A', 'B', 'C', 'D') {
    if (Test-Path "$work\$d") { [IO.Directory]::Delete("$work\$d", $true) }
    New-Item -ItemType Directory "$work\$d" | Out-Null
  }
  Get-ChildItem $work -Filter '*.sqlite*' | ForEach-Object { [IO.File]::Delete($_.FullName) }
  if (Test-Path "$work\.drag-lint.json") { [IO.File]::Delete("$work\.drag-lint.json") }
  $shared = @('unit uShared;', '', 'interface', '', 'const') + $SharedConsts + @('', 'implementation', '', 'end.')
  WriteAscii "$work\shared\uShared.pas" $shared
  WriteAscii "$work\twin\uShared.pas"   $shared
  WriteAscii "$work\A\uA.pas" (UnitUser 'uA' $Expr @('  Local_Const = 5;'))
  WriteAscii "$work\B\uB.pas" (UnitUser 'uB' $Expr $BExtra)
  WriteAscii "$work\C\uMid.pas" (UnitUser 'uMid' $Expr @() $MidUses)
  WriteAscii "$work\D\uD.pas" (UnitUser 'uD' $Expr)
  WriteAscii "$work\A\A.dpr" @('program A;', '', 'uses', "  uShared in '..\shared\uShared.pas',", "  uA in 'uA.pas';", '', 'begin', 'end.')
  WriteAscii "$work\B\B.dpr" @('program B;', '', 'uses', "  uShared in '..\shared\uShared.pas',", "  uB in 'uB.pas';", '', 'begin', 'end.')
  WriteAscii "$work\C\C.dpr" @('program C;', '', 'uses', "  uMid in 'uMid.pas';", '', 'begin', 'end.')
  WriteAscii "$work\C\C.dproj" @(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
    '<PropertyGroup>'
    '<MainSource>C.dpr</MainSource>'
    '<DCC_UnitSearchPath>..\shared;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'
    '</PropertyGroup>'
    '</Project>')
  WriteAscii "$work\D\D.dpr" @('program D;', '', 'uses', "  uShared in '..\twin\uShared.pas',", "  uD in 'uD.pas';", '', 'begin', 'end.')
  $j = ($work -replace '\\', '\\')
  $secs = @(
    "  { `"name`": `"A`", `"include`": [`"$j\\A\\A.dpr`"],   `"db`": `"$j\\A.sqlite`" }"
    "  { `"name`": `"B`", `"include`": [`"$j\\B\\B.dpr`"],   `"db`": `"$j\\B.sqlite`" }"
    "  { `"name`": `"C`", `"include`": [`"$j\\C\\C.dproj`"], `"db`": `"$j\\C.sqlite`" }"
    "  { `"name`": `"D`", `"include`": [`"$j\\D\\D.dpr`"],   `"db`": `"$j\\D.sqlite`" }")
  # a configured section whose DB was never built (Ruling 14): no index, not unknown
  if ($Unindexed) { $secs += "  { `"name`": `"E`", `"include`": [`"$j\\D\\D.dpr`"], `"db`": `"$j\\E-never-built.sqlite`" }" }
  if ($Library) { $secs += "  { `"name`": `"LIB`", `"source`": `"registry-libraries`", `"platforms`": [`"Win32`", `"Win64`"], `"db`": `"$j\\LIB.sqlite`" }" }
  WriteAscii "$eng\drag-lint.json" (@('{ "indexes": { "sections": [', ($secs -join ",`r`n"), ']}}'))
  $cfg = if ($NoOptIn) { '{ "autofix_off": ["const-casing"]' } else { '{ "autofix": ["const-casing"]' }   # 1.37.0: default-ON; the legacy key is ignored, kept to prove it
  if ($ConstCase.Count -gt 0) { $cfg += ', "naming": { "const_case": [' + (($ConstCase | ForEach-Object { "`"$_`"" }) -join ', ') + '] }' }
  WriteAscii "$work\drag-lint-lint.json" @($cfg + ' }')
  $ok = $true
  foreach ($p in @(@('A', "$work\A\A.dpr"), @('B', "$work\B\B.dpr"), @('C', "$work\C\C.dproj"), @('D', "$work\D\D.dpr"))) {
    $null = Run @('index', '--project', $p[1], '--db', "$work\$($p[0]).sqlite")
    if ($LASTEXITCODE -ne 0) { $ok = $false }
  }
  if ($Library) { $null = Run @('index', "$work\shared", '--db', "$work\LIB.sqlite"); if ($LASTEXITCODE -ne 0) { $ok = $false } }
  return $ok
}

$Tracked = @('shared\uShared.pas', 'twin\uShared.pas', 'A\uA.pas', 'B\uB.pas', 'C\uMid.pas', 'D\uD.pas')
# size+mtime of a DB and its -wal/-shm companions: "was the index written?"
function DbStamp([string]$Db) {
  ((@($Db, "$Db-wal", "$Db-shm") | ForEach-Object { if (Test-Path $_) { $i = Get-Item $_; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { '-' } }) -join ',')
}
function Hashes { ($Tracked | ForEach-Object { (Get-FileHash "$work\$_" -Algorithm SHA256).Hash }) -join ',' }
function Txt([string]$Rel) { [IO.File]::ReadAllText("$work\$Rel") }
$Shared = "$work\shared\uShared.pas"
function FixShared([int]$Line, [switch]$Apply) {
  $a = @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix', '--fix-line', "$Line", '--fix-rule', 'const-casing')
  if ($Apply) { $a += '--apply' }
  return Run $a
}

try {
  # ---------------------------------------------------------------- fixture
  Check 'F1 fixture indexes (A, B, C via .dproj, D)' (Reset) ''
  $q = Run @('query', '--name', 'uShared', '--exact', '--db', "$work\C.sqlite")
  Check 'F2 C (transitive, via DCC_UnitSearchPath) holds uShared -- else the FIXTURE is wrong' ($q -match 'uShared') (Lines $q 'uShared|no ')
  $lf = Run @('lint', $Shared, '--db', "$work\A.sqlite", '--rule', 'const-casing')
  Check 'F3 premise: My_Const is a const-casing finding on line 6' ($lf -match 'uShared\.pas[:(]6\b') (Lines $lf 'const-casing')

  # ---------------------------------------------------------------- preview
  $h0 = Hashes
  $o = FixShared 6
  Check 'P1 preview: rename-owners: 3 of 4 indexes (8e)' ($o -match '(?m)^rename-owners: 3 of 4 indexes\r?$') (Lines $o '^rename-')
  Check 'P2 preview: rename-project lines for A, B and C, preferred A first (criterion 2, 14)' `
    ($o -match '(?s)rename-project: A index=fresh.*rename-project: B index=fresh.*rename-project: C index=fresh') ''
  Check 'P3 preview: no rename-project line for D (twin, same unit name, other path: 8a)' ($o -notmatch 'rename-project: D') ''
  Check 'P4 preview: the plan names the new name and per-project refs (criterion 11, 14)' `
    ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply A=1 B=1 C=1\r?$') (Lines $o '^rename-target')
  Check 'P5 preview writes nothing' ((Hashes) -eq $h0) ''
  $oj = RunStdout @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix', '--fix-line', '6', '--fix-rule', 'const-casing', '--json')
  $js = $null; try { $js = $oj | ConvertFrom-Json } catch { }
  $el = @($js | Where-Object { $_.line -eq 6 })[0]
  Check 'P6 --json: the finding carries projects[] with name/index/refs (criterion 14)' `
    (($null -ne $el) -and (@($el.projects).Count -eq 3) -and ((@($el.projects) | ForEach-Object { "$($_.name)=$($_.index)=$($_.refs)" }) -join ',') -eq 'A=fresh=1,B=fresh=1,C=fresh=1') `
    ($(if ($el) { $el | ConvertTo-Json -Compress -Depth 4 } else { $oj }))

  # ---------------------------------------------------------------- apply-all
  $twinBefore = (Get-FileHash "$work\twin\uShared.pas").Hash + (Get-FileHash "$work\D\uD.pas").Hash
  $o = FixShared 6 -Apply
  $s = Txt 'shared\uShared.pas'
  Check 'A1 apply: MyConst declared once in uShared, on the declaration line' `
    ((([regex]::Matches($s, 'MyConst')).Count -eq 1) -and ((($s -split "`r`n")[5]) -eq '  MyConst = 1;')) (Lines $o '^(rename-|autofix)')
  Check 'A2 apply: uA, uB and uMid all read MyConst' `
    (((Txt 'A\uA.pas') -match 'Result:= MyConst;') -and ((Txt 'B\uB.pas') -match 'Result:= MyConst;') -and ((Txt 'C\uMid.pas') -match 'Result:= MyConst;')) ''
  Check 'A3 apply: no My_Const left in shared, A, B or C' `
    (-not (((Txt 'shared\uShared.pas') + (Txt 'A\uA.pas') + (Txt 'B\uB.pas') + (Txt 'C\uMid.pas')) -match 'My_Const')) ''
  Check 'A4 apply: twin\uShared.pas and uD byte-identical (Review Focus 2)' `
    (((Get-FileHash "$work\twin\uShared.pas").Hash + (Get-FileHash "$work\D\uD.pas").Hash) -eq $twinBefore) ''
  Check 'A5 apply: rename-target counts match the real references (1 per project)' `
    ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply A=1 B=1 C=1\r?$') (Lines $o '^rename-target')

  # ---------------------------------------------------------------- cand-split
  Check 'S0 reset: uB declares a global MyConst' (Reset -BExtra @('  MyConst = 2;')) ''
  $o = FixShared 6 -Apply
  Check 'S1 the next candidate MY_CONST is chosen for ALL projects (Review Focus 1)' `
    ($o -match '(?m)^rename-target: L6 My_Const -> MY_CONST apply A=1 B=1 C=1\r?$') (Lines $o '^(rename-target|autofix)')
  Check 'S2 ... and written in shared, uA, uB and uMid; uB''s own MyConst kept' `
    (((Txt 'shared\uShared.pas') -cmatch '  MY_CONST = 1;') -and ((Txt 'A\uA.pas') -cmatch 'Result:= MY_CONST;') -and `
     ((Txt 'B\uB.pas') -cmatch 'Result:= MY_CONST;') -and ((Txt 'C\uMid.pas') -cmatch 'Result:= MY_CONST;') -and ((Txt 'B\uB.pas') -cmatch '  MyConst = 2;')) ''
  Check 'S3 reset: uB declares MyConst AND MY_CONST' (Reset -BExtra @('  MyConst = 2;', '  MY_CONST = 3;')) ''
  $h0 = Hashes
  $o = FixShared 6 -Apply
  Check 'S4 single fix with every candidate taken in B writes nothing (criterion 9)' ((Hashes) -eq $h0) (Lines $o '^(rename-|autofix)')
  Check 'S5 ... the LAST autofix line is the refusal and names project B' `
    ((LastAutofix $o) -match '^autofix: rename refused -- .*project B') (Lines $o '^autofix')

  # ---------------------------------------------------------------- batch-drop
  Check 'D0 reset: two consts; OtherConst taken in B; const_case PascalCase only' `
    (Reset -SharedConsts @('  My_Const = 1;', '  Other_Const = 2;') -Expr 'My_Const + Other_Const' -BExtra @('  OtherConst = 3;') -ConstCase @('PascalCase')) ''
  $o = Run @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix', '--apply')
  Check 'D1 batch: the free rename is applied in A, B and C' `
    (((Txt 'shared\uShared.pas') -cmatch '  MyConst = 1;') -and ((Txt 'A\uA.pas') -cmatch 'MyConst \+ Other_Const') -and `
     ((Txt 'B\uB.pas') -cmatch 'MyConst \+ Other_Const') -and ((Txt 'C\uMid.pas') -cmatch 'MyConst \+ Other_Const')) (Lines $o '^(rename-|autofix)')
  Check 'D2 batch: the taken one is left untouched everywhere' `
    (((Txt 'shared\uShared.pas') -cmatch '  Other_Const = 2;') -and -not (((Txt 'shared\uShared.pas') + (Txt 'A\uA.pas') + (Txt 'C\uMid.pas')) -cmatch 'OtherConst')) ''
  Check 'D3 batch: the drop is reported with the project (criterion 10)' ($o -match 'rename-target: L7 Other_Const -> OtherConst dropped project B') (Lines $o '^rename-target')

  # ---------------------------------------------------------------- stale-owner
  Check 'R0 reset' (Reset) ''
  $b = [IO.File]::ReadAllText("$work\B\uB.pas")
  [IO.File]::WriteAllText("$work\B\uB.pas", "// an edit after indexing`r`n" + $b, [Text.Encoding]::ASCII)
  # Ruling 12: the PREVIEW never reindexes -- it reports the stale owner and plans on the index as it is
  $bStamp = DbStamp "$work\B.sqlite"
  $h0 = Hashes
  $o = FixShared 6
  Check 'RP1 preview: a stale owner is reported index=stale with its changed-file count (Ruling 12)' `
    ($o -match '(?m)^rename-project: B index=stale \(1 changed file\(s\)\)\r?$') (Lines $o '^rename-project')
  Check 'RP2 ... the preview did not write B.sqlite (size+mtime, -wal/-shm)' ((DbStamp "$work\B.sqlite") -eq $bStamp) "$bStamp -> $(DbStamp "$work\B.sqlite")"
  Check 'RP3 ... does not block: the target is still planned apply' ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply ') (Lines $o '^(rename-target|autofix)')
  Check 'RP4 ... and writes no source file' ((Hashes) -eq $h0) ''
  $o = FixShared 6 -Apply
  Check 'R1 a stale owner is reindexed (rename-project: B index=reindexed)' ($o -match '(?m)^rename-project: B index=reindexed\r?$') (Lines $o '^rename-project')
  Check 'R2 ... and the apply is correct in uB at its NEW position' `
    (((Txt 'B\uB.pas') -cmatch 'Result:= MyConst;') -and -not ((Txt 'B\uB.pas') -match 'My_Const') -and ((Txt 'B\uB.pas') -match '^// an edit after indexing')) (Lines $o '^(rename-target|autofix)')

  # ---------------------------------------------------------------- wrongdb (T1)
  # INBOX rename-owner-without-target-reports-fresh: C's DB is really project A's closure. Every row in it is
  # fresh, so per-row freshness said "fresh" and the plan counted C=0 -- a rename that breaks C. The stamped
  # project_tag names A, not C: C is unverified (never reindexed: an incremental run keeps A's rows), and the
  # rename is refused.
  Check 'WD0 reset, then C.sqlite indexed from project A' (Reset) ''
  # --rebuild: since 1.31.2 an incremental project scan into a DB tagged for another project is refused;
  # a rebuild replaces it wholesale, which is exactly the 'C's DB is A's closure' shape this case needs.
  $null = Run @('index', '--project', "$work\A\A.dpr", '--db', "$work\C.sqlite", '--rebuild')
  $cDproj = "$work\C\C.dproj"
  $o = FixShared 6
  Check 'WD1 preview: C is unverified, the reason names the tag and the rebuild' `
    ($o -match ('(?m)^rename-project: C index=unverified \(' + [regex]::Escape("index was built from project A, not C.dproj -- rebuild it: drag-lint index --project $cDproj --db $work\C.sqlite --rebuild") + '\)\r?$')) (Lines $o '^rename-project')
  Check 'WD2 ... and the target is dropped for project C: unverified' ($o -match '(?m)^rename-target: L6 My_Const -> \S+ dropped project C: unverified') (Lines $o '^rename-target')
  $h0 = Hashes
  $cStamp = DbStamp "$work\C.sqlite"
  $o = FixShared 6 -Apply
  Check 'WD3 --apply writes nothing' ((Hashes) -eq $h0) (Lines $o '^(rename-|autofix)')
  Check 'WD4 ... the last autofix line is the refusal naming project C' ((LastAutofix $o) -match '^autofix: rename refused -- .*project C') (LastAutofix $o)
  Check 'WD5 ... and C.sqlite was not reindexed (size+mtime, -wal/-shm)' ((DbStamp "$work\C.sqlite") -eq $cStamp) "$cStamp -> $(DbStamp "$work\C.sqlite")"

  # ---------------------------------------------------------------- member-missing (T2)
  # a member added to C.dproj (only there, not in C.dpr) after C was indexed: no files row, so no per-row check can see it
  Check 'MM0 reset' (Reset) ''
  $late = "$work\C\uLate.pas"
  WriteAscii $late (UnitUser 'uLate' 'My_Const')
  WriteAscii $cDproj @(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
    '<PropertyGroup>'
    '<MainSource>C.dpr</MainSource>'
    '<DCC_UnitSearchPath>..\shared;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'
    '</PropertyGroup>'
    '<ItemGroup>'
    '<DCCReference Include="uLate.pas"/>'
    '</ItemGroup>'
    '</Project>')
  $h0 = (Hashes) + (Get-FileHash $late).Hash
  $cStamp = DbStamp "$work\C.sqlite"
  $o = FixShared 6
  Check 'MM1 preview: C is stale and names the member the index lacks (Ruling 12)' `
    ($o -match ('(?m)^rename-project: C index=stale \(1 project member\(s\) not in the index: ' + [regex]::Escape($late) + '\)\r?$')) (Lines $o '^rename-project')
  Check 'MM2 ... does not block: the target is still planned apply' ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply ') (Lines $o '^rename-target')
  Check 'MM3 ... and writes nothing: no source, not C.sqlite' ((((Hashes) + (Get-FileHash $late).Hash) -eq $h0) -and ((DbStamp "$work\C.sqlite") -eq $cStamp)) ''
  $o = FixShared 6 -Apply
  Check 'MM4 apply: C is reindexed' ($o -match '(?m)^rename-project: C index=reindexed\r?$') (Lines $o '^rename-project')
  Check 'MM5 ... uLate is rewritten' (((Txt 'C\uLate.pas') -cmatch 'Result:= MyConst;') -and ((Txt 'C\uLate.pas') -notmatch 'My_Const')) (Lines $o '^(rename-|autofix)')
  Check 'MM6 ... and C counts both of its references' ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply A=1 B=1 C=2\r?$') (Lines $o '^rename-target')

  # ---------------------------------------------------------------- transitive-missing (B-03)
  # INBOX rename-owner-transitive-members-unchecked: uMid's uses names uExtra, which C.dpr/C.dproj never list and
  # which did not exist when C was indexed. Created afterwards, no indexed file changed, so per-row freshness and
  # the declared-member check (T2) both read "fresh" -- and the apply left shared\uExtra.pas reading My_Const:
  # project C no longer compiled. The owner check must cover the CLOSURE.
  Check 'TM0 reset with uMid using uShared AND uExtra (absent at index time)' (Reset -MidUses @('uShared', 'uExtra')) ''
  $extra = "$work\shared\uExtra.pas"
  WriteAscii $extra (UnitUser 'uExtra' 'My_Const')
  $h0 = (Hashes) + (Get-FileHash $extra).Hash
  $cStamp = DbStamp "$work\C.sqlite"
  $o = FixShared 6
  Check 'TM1 preview: C is stale and names the transitive unit the index lacks (Ruling 12)' `
    ($o -match ('(?m)^rename-project: C index=stale \(1 project member\(s\) not in the index: ' + [regex]::Escape($extra) + '\)\r?$')) (Lines $o '^rename-project')
  Check 'TM2 ... and writes nothing: no source, not C.sqlite' ((((Hashes) + (Get-FileHash $extra).Hash) -eq $h0) -and ((DbStamp "$work\C.sqlite") -eq $cStamp)) ''
  $o = FixShared 6 -Apply
  Check 'TM3 apply: C is reindexed' ($o -match '(?m)^rename-project: C index=reindexed\r?$') (Lines $o '^rename-project')
  Check 'TM4 ... uExtra is rewritten; no My_Const left in uMid or uExtra' `
    (((Txt 'shared\uExtra.pas') -cmatch 'Result:= MyConst;') -and -not (((Txt 'shared\uExtra.pas') + (Txt 'C\uMid.pas')) -match 'My_Const')) (Lines $o '^(rename-|autofix)')
  Check 'TM5 ... and C counts both of its references' ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply A=1 B=1 C=2\r?$') (Lines $o '^rename-target')
  # the bytes, not the plan: C's index after a fresh incremental run holds no My_Const, and dcc64 compiles C
  $null = Run @('index', '--project', $cDproj, '--db', "$work\C.sqlite")
  # symbols AND refs: the declaration is renamed in every case; a reference left behind in uExtra is a refs row
  $sq = RunStdout @('sql', '--query', "select (select count(*) from symbols where name = 'My_Const') + (select count(*) from refs where name_text = 'My_Const')", '--db', "$work\C.sqlite", '--json')
  $left = try { [string](($sq | ConvertFrom-Json).rows[0][0]) } catch { "unparsed: $sq" }
  Check 'TM6 ... re-indexed C holds no My_Const symbol or reference' ($left -eq '0') "got: $left"
  $cOut = "$work\C\out"
  New-Item -ItemType Directory -Force $cOut | Out-Null
  WriteAscii "$work\C\build_c.bat" @('@echo off', 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"', "cd /d `"$work\C`"", "dcc64 -U`"..\shared`" -E`"$cOut`" -N0`"$cOut`" C.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%')
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$work\C\build_c.bat`"" -RedirectStandardOutput "$work\C\build_c.log" -RedirectStandardError "$work\C\build_c.err" -NoNewWindow -Wait -PassThru
  $cLog = Get-Content "$work\C\build_c.log" -Raw -ErrorAction SilentlyContinue
  Check 'TM7 ... and project C COMPILES after the apply (dcc64, C.exe produced)' (($cLog -match 'BUILD_EXITCODE=0') -and (Test-Path "$cOut\C.exe")) (Lines $cLog 'Error|Fatal|BUILD_EXITCODE')
  # ---------------------------------------------------------------- unindexed (Ruling 14)
  # a configured section whose DB FILE does not exist is "no index": not an owner, not unknown, not blocking
  Check 'W0 reset with a section E whose DB was never built' (Reset -Unindexed) ''
  $eDb = "$work\E-never-built.sqlite"
  $o = Run @('lint', '--file', "$work\A\uA.pas", '--db', "$work\A.sqlite", '--fix', '--fix-line', '9', '--fix-rule', 'const-casing', '--apply')
  Check 'W1 a single-project unit still fixes (no refusal)' `
    (((Txt 'A\uA.pas') -notmatch 'Local_Const') -and ((LastAutofix $o) -notmatch 'refused')) (Lines $o '^(rename-|autofix)')
  Check 'W2 ... and names the project with no index: rename-unindexed: E (<db>)' `
    ($o -match ('(?m)^rename-unindexed: E \(' + [regex]::Escape($eDb) + '\)\r?$')) (Lines $o '^rename-')
  Check 'W3 ... and is not rename-unknown' ($o -notmatch '(?m)^rename-unknown:') (Lines $o '^rename-unknown')
  $o = FixShared 6 -Apply
  Check 'W4 a shared unit: the rename still applies in A, B and C' `
    (((Txt 'A\uA.pas') -match 'Result:= MyConst;') -and ((Txt 'B\uB.pas') -match 'Result:= MyConst;') -and ((Txt 'C\uMid.pas') -match 'Result:= MyConst;')) (Lines $o '^(rename-|autofix)')
  Check 'W5 ... rename-owners counts only real indexes (3 of 4)' ($o -match '(?m)^rename-owners: 3 of 4 indexes\r?$') (Lines $o '^rename-owners')
  Check 'W6 ... and the missing DB was not created' (-not (Test-Path $eDb)) ''

  # ---------------------------------------------------------------- corrupt-db
  Check 'X0 reset' (Reset) ''
  Copy-Item "$work\B.sqlite" "$work\B.keep"
  [IO.File]::WriteAllBytes("$work\B.sqlite", [byte[]](,0x5A * 4096))
  $h0 = Hashes
  $o = FixShared 6 -Apply
  Check 'X1 an unreadable DB: nothing written (Review Focus 3)' ((Hashes) -eq $h0) (Lines $o '^(rename-|autofix)')
  Check 'X2 ... rename-unknown names B.sqlite' ($o -match ('(?m)^rename-unknown: ' + [regex]::Escape("$work\B.sqlite") + ': ')) (Lines $o '^rename-unknown')
  Check 'X3 ... and the refusal is the last autofix line' `
    ((LastAutofix $o) -match '^autofix: rename refused -- ') (Lines $o '^autofix')
  [IO.File]::Delete("$work\B.sqlite"); Move-Item "$work\B.keep" "$work\B.sqlite"

  # ---------------------------------------------------------------- library-owner
  Check 'L0 reset with a library section over shared\' (Reset -Library) ''
  $h0 = Hashes
  $o = FixShared 6 -Apply
  Check 'L1 a library owner refuses the rename, nothing written (8d)' ((Hashes) -eq $h0) (Lines $o '^(rename-|autofix)')
  Check 'L2 ... and the reason names the library' `
    ((LastAutofix $o) -match '^autofix: rename refused -- .*library LIB') (Lines $o '^autofix')

  # ---------------------------------------------------------------- fix round 1: manifest that did not fully load (I1)
  # The engine manifest lists only A; a LOCAL manifest beside the cwd would add B and C but is truncated
  # mid-section, so TManifestIO.Load keeps A and records LoadError. Discovery then sees ONE owner --
  # and before the fix the single-store path renamed A only: a confident half-rename.
  Check 'M0 reset' (Reset) ''
  $j = ($work -replace '\\', '\\')
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [', "  { `"name`": `"A`", `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" }", ']}}')
  WriteAscii "$work\.drag-lint.json" @('{ "indexes": { "sections": [', "  { `"name`": `"B`", `"include`": [`"$j\\B\\B.dpr`"], `"db`": `"$j\\B.sqlite`" },", "  { `"name`": `"C`", `"include`": [`"$j\\C")
  $h0 = Hashes
  $o = FixShared 6 -Apply
  Check 'M1 a manifest that did not fully load: single fix writes nothing (8b, 9)' ((Hashes) -eq $h0) (Lines $o '^(rename-|autofix)')
  Check 'M2 ... and the refusal names the manifest problem' ((LastAutofix $o) -match '^autofix: rename refused -- .*manifest') (LastAutofix $o)
  [IO.File]::Delete("$work\.drag-lint.json")

  # ---------------------------------------------------------------- fix round 1: no usable owner store (I2)
  # (i) two owners, BOTH unverified: folder DBs over shared\ (no project file to reindex), made stale.
  Check 'V0 reset' (Reset) ''
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [',
    "  { `"name`": `"FA`", `"include`": [`"$j\\shared`"], `"db`": `"$j\\FA.sqlite`" },",
    "  { `"name`": `"FB`", `"include`": [`"$j\\shared`"], `"db`": `"$j\\FB.sqlite`" }", ']}}')
  $null = Run @('index', "$work\shared", '--db', "$work\FA.sqlite")
  $null = Run @('index', "$work\shared", '--db', "$work\FB.sqlite")
  [IO.File]::AppendAllText($Shared, "// edited after indexing`r`n", [Text.Encoding]::ASCII)
  $h0 = Hashes
  $o = FixShared 6 -Apply
  Check 'V1 two owners, both unverified: single fix writes nothing (criterion 9)' ((Hashes) -eq $h0) (Lines $o '^(rename-|autofix)')
  Check 'V2 ... the target is reported dropped, not silently gone' ($o -match '(?m)^rename-target: L6 My_Const -> \S+ dropped .*unverified') (Lines $o '^rename-target')
  Check 'V3 ... and the last autofix line is the refusal' ((LastAutofix $o) -match '^autofix: rename refused -- .*unverified') (LastAutofix $o)
  $o = Run @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix', '--apply')
  Check 'V4 batch: the same target is listed dropped (criterion 10), nothing written' `
    (($o -match '(?m)^rename-target: L6 My_Const -> \S+ dropped ') -and ((Hashes) -eq $h0)) (Lines $o '^(rename-target|autofix)')

  # (ii) NO owner at all, one DB that cannot be read.
  Check 'K0 reset' (Reset) ''
  [IO.File]::WriteAllBytes("$work\BAD.sqlite", [byte[]](,0x5A * 4096))
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [',
    "  { `"name`": `"D`", `"include`": [`"$j\\D\\D.dpr`"], `"db`": `"$j\\D.sqlite`" },",
    "  { `"name`": `"BAD`", `"include`": [`"$j\\B\\B.dpr`"], `"db`": `"$j\\BAD.sqlite`" }", ']}}')
  $h0 = Hashes
  $o = FixShared 6 -Apply
  Check 'K1 0 owners + an unreadable DB: single fix writes nothing (8c, 9)' ((Hashes) -eq $h0) (Lines $o '^(rename-|autofix)')
  Check 'K2 ... rename-unknown names BAD.sqlite and the refusal says ownership unknown' `
    (($o -match ('(?m)^rename-unknown: ' + [regex]::Escape("$work\BAD.sqlite"))) -and ((LastAutofix $o) -match '^autofix: rename refused -- ownership unknown')) (LastAutofix $o)

  # ---------------------------------------------------------------- default-ON (lane A7, 1.37.0)
  # Every fix is ON by default: a BATCH run plans the multi-project rename with no
  # config key and no --fix-naming. The only brake is "autofix_off".
  Check 'N0 reset: default config (no brake)' (Reset) ''
  $h0 = Hashes
  $o = Run @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix')
  Check 'N1 batch preview with NO flag prints the plan for A, B and C' `
    (($o -match '(?m)^rename-owners: 3 of 4 indexes\r?$') -and ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply A=1 B=1 C=1\r?$')) (Lines $o '^rename-')
  Check 'N2 ... no opt-out note, the preview writes nothing, and it says what it will rename' `
    (($o -notmatch 'NOT opted in') -and ((Hashes) -eq $h0) -and ($o -match '(?m)^rename: 1 symbol\(s\) across 3 project\(s\)\r?$')) (Lines $o '^(rename|NOT)')
  $o = Run @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix', '--fix-naming')
  Check 'N3 --fix-naming is a no-op: the same plan' `
    (($o -match '(?m)^rename-owners: 3 of 4 indexes\r?$') -and ($o -match '(?m)^rename-target: L6 My_Const -> MyConst apply A=1 B=1 C=1\r?$')) (Lines $o '^rename-')
  Check 'N4 reset (autofix_off lists const-casing)' (Reset -NoOptIn) ''
  $o = Run @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix', '--apply')
  Check 'N4b the brake: the note names autofix_off, no rename plan, nothing renamed' `
    (($o -match 'autofix_off') -and ($o -notmatch '(?m)^rename-') -and ((Hashes) -eq $h0)) (Lines $o '^(rename|autofix|drag-lint: note)')
  Check 'N4c reset (default)' (Reset) ''
  $o = Run @('lint', '--file', $Shared, '--db', "$work\A.sqlite", '--fix', '--apply')
  Check 'N5 batch --fix --apply (no flag) renames in shared, uA, uB and uMid' `
    (((Txt 'shared\uShared.pas') -cmatch '  MyConst = 1;') -and ((Txt 'A\uA.pas') -match 'Result:= MyConst;') -and `
     ((Txt 'B\uB.pas') -match 'Result:= MyConst;') -and ((Txt 'C\uMid.pas') -match 'Result:= MyConst;')) (Lines $o '^(rename-|autofix)')
  Check 'N6 reset (default)' (Reset) ''
  $o = Run @('lint', '--file', "$work\A\uA.pas", '--db', "$work\A.sqlite", '--fix', '--fix-naming')
  Check 'N7 single-project batch with --fix-naming: rename-local: 1 (the IDE''s single-project confirm count)' `
    ($o -match '(?m)^rename-local: 1\r?$') (Lines $o '^(rename-|autofix)')
  $o = Run @('lint', '--file', "$work\A\uA.pas", '--db', "$work\A.sqlite", '--fix')
  Check 'N8 ... and no rename-local line without --fix-naming (criterion 15)' ($o -notmatch '(?m)^rename-') (Lines $o '^rename-')

  # ---------------------------------------------------------------- single-project
  Check 'U0 reset' (Reset) ''
  $o = Run @('lint', '--file', "$work\A\uA.pas", '--db', "$work\A.sqlite", '--fix', '--fix-line', '9', '--fix-rule', 'const-casing')
  Check 'U1 single-project unit: NO rename- lines (criterion 15)' ($o -notmatch '(?m)^rename-') (Lines $o '^rename-')
  Check 'U2 ... and today''s autofix line shape' ($o -match '(?m)^autofix: 1 fixable finding\(s\) -- pass --apply to write\r?$') (Lines $o '^autofix')

  Check 'Z1 the engine copy never loaded C:\Projects\.drag-lint.json' ($script:AllOut -notmatch [regex]::Escape('C:\Projects\.drag-lint.json')) ''
} finally {
  Get-Process drag-lint -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force -ErrorAction SilentlyContinue
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (could not delete $work)" }
}
$realAfter = RealStamp
Check 'Z2 the real Micronite2027.sqlite and DMTEST.sqlite were not touched (size+mtime)' ($realBefore -eq $realAfter) "$realBefore -> $realAfter"
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
