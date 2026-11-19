<#
  run_check_init_verdicts.ps1 -- `check-init` lane HBSOLVER (1.52): the cross-routine solve (spec 5.4).

  Plan: docs\superpowers\plans\2026-11-17-happens-before-phase1.md, lane SOLVER; spec
  docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.4, 6.4, 6.5; owner ruling 2026-11-17
  13:56 (unresolved callee -> UNKNOWN-CALLEE warning, read-only RTL routines exempt).

  Each fixture tests\fixtures\happens-before\solve-*\ is one small program, indexed into a private DB.
  Per case the runner asserts EXACTLY: the headline verdict, the exit code, and per judged use (found by
  its `// USE-...` marker line) the verdict, the sorted reason codes and the witness (hop routines,
  root first). Every MAY case has a SET twin that differs by one line or one variable (spec 6.5).

  Answers come from tests\fixtures\happens-before\solve-driver\SolveDriver.dpr (compiled here with
  dcc64): it calls DRagLint.Query.HappensBefore.CheckInit and prints the same HbAnswerJson the verb
  prints. -Mode:
    driver  answers from the driver only;
    cli     answers from `drag-lint check-init <QName> --db <db> --json` (the RED run: the verb still
            returns the scaffold answer until INT wires CheckInit into DRagLint.CLI.CheckInit);
    auto    (default) driver answers are asserted; the CLI answer of every case is compared with the
            driver's (budget.ms masked) once the CLI is wired, and reported as SKIP while it is not.
  Controls:
    * determinism: every case run twice (driver --stable) gives byte-identical JSON;
    * positive control: every `lint-all --rule init-order-hazard` finding on solve-initorder is a
      MAY-BE-UNSET use with writer-later-unit at that read (use line or witness hop); at least one
      finding must exist; the swapped twin has none and answers SET;
    * comparator: one flipped expectation must be reported.

  Parameters:
    -Exe        engine used to index the fixtures and lint (default src\cli\Win64\Debug\drag-lint.exe)
    -Repo       repo root (default: two levels above this script)
    -WorkDir    scratch folder (deleted at the end unless HB_KEEP_WORK is set)
    -Mode       auto | driver | cli
    -SkipBuild  use the driver already in -WorkDir
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-check-init-verdicts-$PID",
  [ValidateSet('auto', 'driver', 'cli')][string]$Mode = 'auto',
  [switch]$SkipBuild
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
Write-Host "== check-init SOLVER verdicts (mode $Mode) ==" -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$FixRoot = Join-Path $Repo 'tests\fixtures\happens-before'

# Case table. Uses: '<file>#<marker>=<VERDICT>|<reasons, sorted by code order>|<witness routines root first>'
# ('*' in the reasons or witness slot = not asserted).
$Cases = @(
  @{ Name = 'initorder MAY';         Fix = 'solve-initorder';         Target = 'siFirst.GCfg';  Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'siSecond.pas#USE-DIRECT=MAY-BE-UNSET|writer-later-unit|siSecond.initialization > siSecond.initialization',
      'siFirst.pas#USE-CALL=MAY-BE-UNSET|writer-later-unit|siSecond.initialization > siFirst.ReadCfg > siFirst.ReadCfg') }
  @{ Name = 'initorder swapped SET'; Fix = 'solve-initorder-swapped'; Target = 'siFirst.GCfg';  Verdict = 'SET';          Exit = 0; Uses = @(
      'siSecond.pas#USE-DIRECT=SET||',
      'siFirst.pas#USE-CALL=SET||') }
  @{ Name = 'callchain SET';         Fix = 'solve-callchain';         Target = 'scData.GData';  Verdict = 'SET';          Exit = 0; Uses = @(
      'scWork.pas#USE-DEEP=SET||') }
  @{ Name = 'callchain if MAY';      Fix = 'solve-callchain';         Target = 'scData.GDataIf'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'scWork.pas#USE-DEEP=MAY-BE-UNSET|writer-conditional|SolveCallChain > scWork.RunAll > scWork.Level1 > scWork.Level2 > scWork.Level3 > scWork.Level3') }
  @{ Name = 'budget 1 MAY';          Fix = 'solve-callchain';         Target = 'scData.GData';  Verdict = 'MAY-BE-UNSET'; Exit = 1; Max = 1; Exhausted = $true; Uses = @(
      'scWork.pas#USE-DEEP=MAY-BE-UNSET|*budget*|*') }
  @{ Name = 'virtual all SET';       Fix = 'solve-virtual';           Target = 'svShapes.GAll'; Verdict = 'SET';          Exit = 0; Uses = @(
      'svShapes.pas#USE-VIRTUAL=SET||') }
  @{ Name = 'virtual part MAY';      Fix = 'solve-virtual';           Target = 'svShapes.GPart'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'svShapes.pas#USE-VIRTUAL=MAY-BE-UNSET|virtual-fanout|SolveVirtual > svShapes.UseShapes > svShapes.UseShapes') }
  @{ Name = 'indirect MAY';          Fix = 'solve-indirect';          Target = 'sdHooks.GInd';  Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'sdHooks.pas#USE-INDIRECT=MAY-BE-UNSET|escaped-routine,indirect-call|sdHooks.UseViaHook > sdHooks.UseViaHook') }
  @{ Name = 'direct SET';            Fix = 'solve-indirect';          Target = 'sdHooks.GDir';  Verdict = 'SET';          Exit = 0; Uses = @(
      'sdHooks.pas#USE-DIRECT=SET||') }
  @{ Name = 'mainblock SET';         Fix = 'solve-mainblock';         Target = 'smData.GMain';  Verdict = 'SET';          Exit = 0; Uses = @(
      'smData.pas#USE-MAIN=SET||') }
  @{ Name = 'mainblock late MAY';    Fix = 'solve-mainblock';         Target = 'smData.GLate';  Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'smData.pas#USE-LATE=MAY-BE-UNSET|writer-after-use-same-routine|SolveMainBlock > smData.UseLate > smData.UseLate') }
  @{ Name = 'recursion must SET';    Fix = 'solve-recursion';         Target = 'srRec.GRec';    Verdict = 'SET';          Exit = 0; Uses = @(
      'srRec.pas#USE-REC=SET||') }
  @{ Name = 'recursion loop SET';    Fix = 'solve-recursion';         Target = 'srRec.GLoop';   Verdict = 'SET';          Exit = 0; Uses = @(
      'srRec.pas#USE-LOOP=SET||') }
  @{ Name = 'recursion base MAY';    Fix = 'solve-recursion';         Target = 'srRec.GBad';    Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'srRec.pas#USE-BAD=MAY-BE-UNSET|callee-not-must|SolveRecursion > srRec.UseBad > srRec.UseBad') }
  @{ Name = 'unknown callee';        Fix = 'solve-unknown';           Target = 'suData.GUnk';   Verdict = 'UNKNOWN-CALLEE'; Exit = 1; Limit = 'unknown-callee'; Reason = 'unknown-callee';
     Summary = 'FillExternal: source not available -- does it set GUnk (by-ref unknown)?*'; Uses = @(
      'SolveUnknown.dpr#CALL-UNKNOWN=MAY-BE-UNSET|soft-writer|SolveUnknown > SolveUnknown',
      'suData.pas#USE-UNK=MAY-BE-UNSET|soft-writer|SolveUnknown > suData.UseAll > suData.UseAll') }
  @{ Name = 'callee-reads marker';   Fix = 'solve-unknown';           Target = 'suData.GRead';  Verdict = 'NEVER-SET';    Exit = 1; NoLimit = 'unknown-callee'; Uses = @(
      'SolveUnknown.dpr#dl:callee-reads=NEVER-SET||',
      'suData.pas#USE-READ=NEVER-SET||') }
  @{ Name = 'callee-sets marker';    Fix = 'solve-unknown';           Target = 'suData.GSets';  Verdict = 'SET';          Exit = 0; NoLimit = 'unknown-callee'; Uses = @(
      'suData.pas#USE-SETS=SET||') }
  @{ Name = 'RTL exempt';            Fix = 'solve-unknown';           Target = 'suData.GExempt'; Verdict = 'NEVER-SET';   Exit = 1; NoLimit = 'unknown-callee'; Uses = @(
      'SolveUnknown.dpr#USE-EXEMPT=NEVER-SET||') }
  # H-CONFIG: the per-callee answer recorded once per project in _D-RAG\drag-lint-project.json
  # ("checkInit": {"callees": {...}}); the fixture's DB sits in its _D-RAG folder so the anchor is found.
  @{ Name = 'config reads';          Fix = 'solve-config';            Target = 'scfgData.GCfgRead'; Verdict = 'NEVER-SET'; Exit = 1; NoLimit = 'unknown-callee'; NoReason = 'unknown-callee'; Uses = @(
      'SolveConfig.dpr#CALL-READ=NEVER-SET||',
      'scfgData.pas#USE-READ=NEVER-SET||') }
  @{ Name = 'config sets';           Fix = 'solve-config';            Target = 'scfgData.GCfgSet'; Verdict = 'SET';        Exit = 0; NoLimit = 'unknown-callee'; Uses = @(
      'scfgData.pas#USE-SET=SET||') }
  @{ Name = 'config QName key needs the qualifier'; Fix = 'solve-config'; Target = 'scfgData.GCfgNone'; Verdict = 'UNKNOWN-CALLEE'; Exit = 1; Limit = 'unknown-callee'; Reason = 'unknown-callee';
     Summary = 'OtherExternal: source not available -- does it set GCfgNone (by-ref unknown)?*'; Uses = @(
      'SolveConfig.dpr#CALL-NONE=MAY-BE-UNSET|soft-writer|*',
      'scfgData.pas#USE-NONE=MAY-BE-UNSET|soft-writer|*') }
  @{ Name = 'config bad value ignored'; Fix = 'solve-config';         Target = 'scfgData.GCfgBogus'; Verdict = 'UNKNOWN-CALLEE'; Exit = 1; Limit = 'unknown-callee'; Uses = @(
      'SolveConfig.dpr#CALL-BOGUS=MAY-BE-UNSET|soft-writer|*',
      'scfgData.pas#USE-BOGUS=MAY-BE-UNSET|soft-writer|*') }
  @{ Name = 'line marker beats config'; Fix = 'solve-config';         Target = 'scfgData.GCfgMark'; Verdict = 'SET';       Exit = 0; NoLimit = 'unknown-callee'; Uses = @(
      'scfgData.pas#USE-MARK=SET||') }
)

function MarkerLine([string]$Dir, [string]$File, [string]$Marker) {
  $m = @(Select-String -LiteralPath (Join-Path $Dir $File) -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' in $File found $($m.Count) times" }
  return [int]$m[0].LineNumber
}

# Compares one parsed answer with its case; returns the mismatch descriptions.
function Compare-Case($Case, $Json, [string]$Dir) {
  $bad = @()
  if ($null -eq $Json) { return ,@('no JSON answer') }
  if ($Json.verdict -cne $Case.Verdict) { $bad += "verdict expected $($Case.Verdict) got $($Json.verdict)" }
  if ($Case.Limit -and -not (@($Json.limits) -contains $Case.Limit)) { $bad += "limits lack $($Case.Limit): [$(@($Json.limits) -join ',')]" }
  if ($Case.NoLimit -and (@($Json.limits) -contains $Case.NoLimit)) { $bad += "limits hold $($Case.NoLimit)" }
  if ($Case.Reason -and -not (@($Json.reasons) -contains $Case.Reason)) { $bad += "reasons lack $($Case.Reason): [$(@($Json.reasons) -join ',')]" }
  if ($Case.NoReason -and (@($Json.reasons) -contains $Case.NoReason)) { $bad += "reasons hold $($Case.NoReason)" }
  if ($Case.Summary -and -not ($Json.summary -like $Case.Summary)) { $bad += "summary [$($Json.summary)]" }
  if ($Case.Exhausted -and -not $Json.budget.exhausted) { $bad += 'budget.exhausted is false' }
  if (@($Json.uses).Count -ne $Case.Uses.Count) { $bad += "uses expected $($Case.Uses.Count) got $(@($Json.uses).Count)" }
  foreach ($u in $Case.Uses) {
    if ($u -notmatch '^([^#]+)#([^=]+)=([^|]+)\|([^|]*)\|(.*)$') { $bad += "bad expectation $u"; continue }
    $file = $Matches[1]; $marker = $Matches[2]; $verdict = $Matches[3]; $reasons = $Matches[4]; $wit = $Matches[5]
    $line = MarkerLine $Dir $file $marker
    $hit = @(@($Json.uses) | Where-Object { ((Split-Path $_.file -Leaf) -ieq $file) -and ([int]$_.line -eq $line) })
    if ($hit.Count -ne 1) { $bad += "$file#$marker (line $line): $($hit.Count) judged uses"; continue }
    $h = $hit[0]
    if ($h.verdict -cne $verdict) { $bad += "$file#$marker verdict expected $verdict got $($h.verdict)" }
    $gotR = (@($h.reasons) -join ',')
    if ($reasons -ne '*' -and -not ($gotR -like $reasons)) { $bad += "$file#$marker reasons expected [$reasons] got [$gotR]" }
    $gotW = (@($h.witness) | ForEach-Object { $_.routine }) -join ' > '
    if ($wit -ne '*' -and $gotW -cne $wit) { $bad += "$file#$marker witness expected [$wit] got [$gotW]" }
  }
  return ,$bad
}

try {
  if ((Test-Path -LiteralPath $WorkDir) -and -not $SkipBuild) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  $driverExe = Join-Path $WorkDir 'SolveDriver.exe'
  if (($Mode -ne 'cli') -and -not $SkipBuild) {
    $src = Join-Path $Repo 'src'
    $dirs = 'preprocess','core','context','diagnostics','doc','forms','index','lint','lsp','mcp','output','parser',
            'project','query','refactor','report','resolver','sql','storage','workspace','analysis','cli','charts'
    $paths = (@($dirs | ForEach-Object { Join-Path $src $_ }) + (Join-Path $Repo 'third_party\delphi-tree-sitter')) -join ';'
    $dpr = Join-Path $FixRoot 'solve-driver\SolveDriver.dpr'
    $dcu = Join-Path $WorkDir 'dcu'
    New-Item -ItemType Directory -Path $dcu -Force | Out-Null
    $bat = Join-Path $WorkDir 'b.bat'
    $blog = Join-Path $WorkDir 'build.log'
    $q = [char]34
    $batText = "@echo off`r`ncall ${q}C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat${q}`r`n" +
      "cd /D ${q}$WorkDir${q}`r`n" +
      "dcc64 -B -Q -NU${q}$dcu${q} -E${q}$WorkDir${q} -U${q}$paths${q} -I${q}$paths${q} " +
      "-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win " +
      "${q}$dpr${q}`r`necho BUILD_EXITCODE=%errorlevel%`r`n"
    [IO.File]::WriteAllText($bat, $batText, [Text.Encoding]::ASCII)
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ' + $q + $q + $bat + $q + ' > ' + $q + $blog + $q + ' 2>&1' + $q) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match 'Error: |Fatal: ')) {
      Select-String -LiteralPath $blog -Pattern 'Error: |Fatal: ' | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
      Write-Host "CHECK-INIT VERDICTS: FAIL -- the driver did not build (log: $blog)" -ForegroundColor Red
      exit 1
    }
    foreach ($dll in 'sqlite3.dll','tree-sitter.dll','tree-sitter-delphi13.dll','tree-sitter-dfm.dll') {
      $from = Join-Path (Split-Path $Exe) $dll
      if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $WorkDir -Force }
    }
  }
  if (($Mode -ne 'cli') -and -not (Test-Path -LiteralPath $driverExe)) { Write-Host "FATAL: driver not found: $driverExe" -ForegroundColor Red; exit 2 }

  # Index a private copy of every fixture (never a real project DB).
  $dbs = @{}; $dirsOf = @{}
  foreach ($fx in @($Cases | ForEach-Object { $_.Fix } | Sort-Object -Unique)) {
    $d = Join-Path $WorkDir "fx\$fx"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Copy-Item -Path (Join-Path $FixRoot "$fx\*") -Destination $d -Recurse -Force
    # A fixture with a _D-RAG folder (project config) keeps its DB there: the engine finds the anchor by it.
    $db = if (Test-Path -LiteralPath (Join-Path $d '_D-RAG')) { Join-Path $d "_D-RAG\$fx.sqlite" } else { Join-Path $WorkDir "$fx.sqlite" }
    $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db 2>&1 | ForEach-Object { "$_" } }
    Check "index $fx (exit 0)" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $dbs[$fx] = $db; $dirsOf[$fx] = $d
  }

  function Invoke-Answer($Case, [string]$Source) {
    $db = $dbs[$Case.Fix]
    $max = @(if ($Case.Max) { @('--max-routines', "$($Case.Max)") } else { @() })
    if ($Source -eq 'cli') { $raw = & { $ErrorActionPreference = 'Continue'; & $Exe check-init $Case.Target --db $db --json @max 2>$null } }
    else { $raw = & { $ErrorActionPreference = 'Continue'; & $driverExe --db $db --target $Case.Target @max --stable 2>$null } }
    $code = $LASTEXITCODE
    $text = (@($raw) -join "`n").Trim()
    $json = $null
    try { $json = $text | ConvertFrom-Json } catch { $json = $null }
    return @{ Text = $text; Json = $json; Code = $code }
  }

  $src0 = if ($Mode -eq 'cli') { 'cli' } else { 'driver' }
  $printed = $false
  $cliWired = $null
  $first = $null
  foreach ($c in $Cases) {
    $a = Invoke-Answer $c $src0
    if (-not $printed) { Write-Host '  -- raw answer (first case) --'; Write-Host "    $($a.Text)"; $printed = $true }
    if ($null -eq $first) { $first = @{ Case = $c; Json = $a.Json } }
    $mis = Compare-Case $c $a.Json $dirsOf[$c.Fix]
    foreach ($m in $mis) { Check "$($c.Name)" $false $m }
    Check "$($c.Name): $($c.Target) exact" ($mis.Count -eq 0) "mismatches=$($mis.Count)"
    Check "$($c.Name): exit $($c.Exit)" ($a.Code -eq $c.Exit) "exit=$($a.Code)"
    if ($Mode -ne 'cli') {
      $b = Invoke-Answer $c 'driver'
      Check "$($c.Name): byte-identical JSON on a second run" ($a.Text -ceq $b.Text) ''
      if ($Mode -eq 'auto') {
        $cl = Invoke-Answer $c 'cli'
        if ($null -eq $cliWired) { $cliWired = ($null -ne $cl.Json) -and -not (@($cl.Json.limits) -contains 'not-implemented') }
        if ($cliWired) {
          $norm = { param($t) $t -replace '"ms":\d+', '"ms":0' }
          Check "$($c.Name): CLI check-init --json equals the driver" ((& $norm $cl.Text) -ceq $a.Text) ''
          Check "$($c.Name): CLI exit equals the driver" ($cl.Code -eq $a.Code) "cli=$($cl.Code) driver=$($a.Code)"
        }
      }
    }
  }
  if (($Mode -eq 'auto') -and -not $cliWired) {
    Write-Host '  [SKIP] CLI form: check-init still returns the scaffold answer (HANDOVER: wire CheckInit in DRagLint.CLI.CheckInit)' -ForegroundColor Yellow
  }

  # Positive control: init-order-hazard findings on solve-initorder are MAY + writer-later-unit at that read.
  $pcCase = $Cases | Where-Object { $_.Name -eq 'initorder MAY' }
  $pcAns = Invoke-Answer $pcCase $src0
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $dbs['solve-initorder'] --rule init-order-hazard --format json 2>$null }
  $txt = (@($raw) -join "`n"); $bi = $txt.IndexOf('[')
  $finds = @(); if ($bi -ge 0) { try { $finds = @(($txt.Substring($bi) | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { $finds = @() } }
  $finds = @($finds | Where-Object { $_.rule -eq 'init-order-hazard' })
  Write-Host "  -- init-order-hazard findings: $(@($finds | ForEach-Object { '{0}:{1}' -f (Split-Path $_.file_path -Leaf), $_.start_line }) -join ', ')"
  Check 'positive control: init-order-hazard fires on solve-initorder' ($finds.Count -ge 1) "findings=$($finds.Count)"
  foreach ($f in $finds) {
    $leaf = Split-Path $f.file_path -Leaf; $ln = [int]$f.start_line
    $ok = @(@($pcAns.Json.uses) | Where-Object {
      ($_.verdict -eq 'MAY-BE-UNSET') -and (@($_.reasons) -contains 'writer-later-unit') -and (
        (((Split-Path $_.file -Leaf) -ieq $leaf) -and ([int]$_.line -eq $ln)) -or
        (@($_.witness | Where-Object { ((Split-Path $_.file -Leaf) -ieq $leaf) -and ([int]$_.line -eq $ln) }).Count -gt 0)) }).Count -gt 0
    Check "positive control: $leaf`:$ln is MAY-BE-UNSET with writer-later-unit" $ok ''
  }
  $raw2 = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $dbs['solve-initorder-swapped'] --rule init-order-hazard --format json 2>$null }
  $txt2 = (@($raw2) -join "`n"); $bi2 = $txt2.IndexOf('[')
  $f2 = @(); if ($bi2 -ge 0) { try { $f2 = @(($txt2.Substring($bi2) | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { $f2 = @() } }
  Check 'twin: init-order-hazard is silent on solve-initorder-swapped' (@($f2 | Where-Object { $_.rule -eq 'init-order-hazard' }).Count -eq 0) ''

  # Comparator control: a flipped expectation must be reported.
  $flip = @{} + $first.Case
  $flip.Verdict = if ($first.Case.Verdict -eq 'SET') { 'MAY-BE-UNSET' } else { 'SET' }
  $fm = Compare-Case $flip $first.Json $dirsOf[$first.Case.Fix]
  Check 'comparator control: a flipped verdict is reported' ($fm.Count -ge 1) "mismatches=$($fm.Count)"

  if ($script:Failed) { Write-Host 'CHECK-INIT VERDICTS: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'CHECK-INIT VERDICTS: PASS' -ForegroundColor Green
  exit 0
} finally {
  if ((-not $SkipBuild) -and (Test-Path -LiteralPath $WorkDir) -and (-not $env:HB_KEEP_WORK)) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
  }
}
