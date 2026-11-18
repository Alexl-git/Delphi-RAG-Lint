<#
  run_check_init_fields.ps1 -- `check-init` lane HBFIELDS (1.52): instance fields by the constructor model.

  Plan: docs\superpowers\plans\2026-11-17-happens-before-phase1.md, lane FIELDS; spec
  docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.5, 6.4, 6.5.

  Each fixture tests\fixtures\happens-before\fields-*\ is one small program, indexed into a private DB.
  Per case the runner asserts EXACTLY: the headline verdict, the exit code, `scope` = instance, the
  limits it names, and per judged use (found by its `// USE-...` marker line) the verdict, the sorted
  reason codes and the witness (hop routines, root first). Every MAY case has a SET twin that differs
  by one line, one receiver or one class (spec 6.5):
    fields-ctor            FList (every constructor) / FHalf (CreateFor misses it); TPeer (Self write) /
                           TPeerBad (write through another object); TEarly (read before the write) /
                           TEarly2 (write first)
    fields-initrun         TRunner.Init not called by any constructor / TRunner2.Create calls Init;
                           TRunner2.Reset writes nil (named on the limits line); TRunner2.Destroy
    fields-virtual-in-ctor TBase.Create calls the virtual Setup / TBase2.Create does not
    fields-subclass        TGood.Create chains to TParent.Create / TSkip.CreateSkip does not
    fields-noctor          TPlain declares no constructor / TPlain2 does; FNever has no writer
    fields-escape          Self handed out before the write / after it; an `overload` constructor
                           (inherited constructor stays callable) / the same without overload

  Answers come from tests\fixtures\happens-before\solve-driver\SolveDriver.dpr (lane HBSOLVER's driver,
  compiled here with dcc64): it calls DRagLint.Query.HappensBefore.CheckInit, which delegates instance
  fields to DRagLint.Query.HappensBefore.Fields.CheckInstanceField. -Mode driver | cli | auto as in
  run_check_init_verdicts.ps1 (auto: driver asserted, the CLI answer compared once the verb is wired).
  Controls: determinism (two driver runs byte-identical); comparator (a flipped verdict is reported).

  Parameters: -Exe (engine that indexes the fixtures), -Repo, -WorkDir, -Mode, -SkipBuild.
#>
[CmdletBinding()]
param(
  [string]$Repo    = (Resolve-Path "$PSScriptRoot\..\..").Path,
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-check-init-fields-$PID",
  [ValidateSet('auto', 'driver', 'cli')][string]$Mode = 'auto',
  [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
Write-Host "== check-init FIELDS verdicts (mode $Mode) ==" -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$FixRoot = Join-Path $Repo 'tests\fixtures\happens-before'

# Case table. Uses: '<file>#<marker>=<VERDICT>|<reasons, sorted by code order>|<witness routines root first>'
# ('*' in the reasons or witness slot = not asserted). Limit / NoLimit / Summary are -like patterns.
$Cases = @(
  @{ Name = 'ctor all SET';            Fix = 'fields-ctor';    Target = 'fcData.TBoth.FList';     Verdict = 'SET';          Exit = 0; Limit = 'instance-by-constructors'; NoLimit = 'use-after-free-not-judged*';
     Summary = '(every instance: all 3 constructors set it before they return)'; Uses = @(
      'fcData.pas#USE-LIST=SET||') }
  @{ Name = 'ctor half MAY';           Fix = 'fields-ctor';    Target = 'fcData.TBoth.FHalf';     Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'fcData.pas#USE-HALF=MAY-BE-UNSET|ctor-misses-field|fcData.TBoth.CreateFor > fcData.TBoth.Run') }
  @{ Name = 'ctor helper SET';         Fix = 'fields-ctor';    Target = 'fcData.TBoth.FHelped';   Verdict = 'SET';          Exit = 0; Uses = @(
      'fcData.pas#USE-HELPED=SET||') }
  @{ Name = 'receiver Self SET';       Fix = 'fields-ctor';    Target = 'fcData.TPeer.FData';     Verdict = 'SET';          Exit = 0; Uses = @(
      'fcData.pas#USE-PEER=SET||') }
  @{ Name = 'receiver other MAY';      Fix = 'fields-ctor';    Target = 'fcData.TPeerBad.FData';  Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'fcData.pas#USE-PEERBAD=MAY-BE-UNSET|ctor-misses-field|fcData.TPeerBad.Create > fcData.TPeerBad.Show') }
  @{ Name = 'read before write MAY';   Fix = 'fields-ctor';    Target = 'fcData.TEarly.FLog';     Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'fcData.pas#USE-EARLY=MAY-BE-UNSET|writer-after-use-same-routine|fcData.TEarly.Create > fcData.TEarly.Peek') }
  @{ Name = 'write first SET';         Fix = 'fields-ctor';    Target = 'fcData.TEarly2.FLog';    Verdict = 'SET';          Exit = 0; Uses = @(
      'fcData.pas#USE-EARLY2-CTOR=SET||',
      'fcData.pas#USE-EARLY2=SET||') }
  @{ Name = 'init/run MAY';            Fix = 'fields-initrun'; Target = 'fiRunner.TRunner.FQueue'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Summary = '*fiRunner.TRunner.Init (not called by every constructor)*'; Uses = @(
      'fiRunner.pas#USE-RUN=MAY-BE-UNSET|ctor-misses-field|fiRunner.TRunner.Create > fiRunner.TRunner.Run') }
  @{ Name = 'init in ctor SET uses';   Fix = 'fields-initrun'; Target = 'fiRunner.TRunner2.FQueue'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Limit = 'use-after-free-not-judged fiRunner.pas:70';
     Summary = '*fiRunner.TRunner2.Init (called by every constructor)*'; Uses = @(
      'fiRunner.pas#USE-DESTROY=MAY-BE-UNSET|writer-conditional|fiRunner.TRunner2.Destroy',
      'fiRunner.pas#USE-FREE=SET||',
      'fiRunner.pas#USE-RUN2=SET||') }
  @{ Name = 'virtual in ancestor MAY'; Fix = 'fields-virtual-in-ctor'; Target = 'fvShapes.TDerived.FItems'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'fvShapes.pas#USE-VIRT=MAY-BE-UNSET|virtual-call-in-ancestor-ctor|fvShapes.TBase.Create > fvShapes.TDerived.Setup',
      'fvShapes.pas#USE-PLAIN=SET||') }
  @{ Name = 'virtual not called SET';  Fix = 'fields-virtual-in-ctor'; Target = 'fvShapes.TDerived2.FItems'; Verdict = 'SET'; Exit = 0; Uses = @(
      'fvShapes.pas#USE-VIRT2=SET||') }
  @{ Name = 'subclass chains SET';     Fix = 'fields-subclass'; Target = 'fsTree.TParent.FName';  Verdict = 'SET';          Exit = 0; Uses = @(
      'fsTree.pas#USE-GOOD=SET||') }
  @{ Name = 'subclass skips MAY';      Fix = 'fields-subclass'; Target = 'fsTree.TParent2.FName'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'fsTree.pas#USE-SKIP=MAY-BE-UNSET|subclass-ctor-skips|fsTree.TSkip.CreateSkip > fsTree.TParent2.Show') }
  @{ Name = 'no ctor MAY';             Fix = 'fields-noctor';  Target = 'fnPlain.TPlain.FValue';  Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'fnPlain.pas#USE-NOCTOR=MAY-BE-UNSET|no-declared-ctor|fnPlain.TPlain > fnPlain.TPlain.Show') }
  @{ Name = 'no writer NEVER-SET';     Fix = 'fields-noctor';  Target = 'fnPlain.TPlain.FNever';  Verdict = 'NEVER-SET';    Exit = 1; Uses = @(
      'fnPlain.pas#USE-NEVER=NEVER-SET||') }
  @{ Name = 'declared ctor SET';       Fix = 'fields-noctor';  Target = 'fnPlain.TPlain2.FValue'; Verdict = 'SET';          Exit = 0; Uses = @(
      'fnPlain.pas#USE-CTOR=SET||') }
  @{ Name = 'Self escapes MAY';        Fix = 'fields-escape';  Target = 'feEsc.TEsc.FData';       Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'feEsc.pas#USE-ESC=MAY-BE-UNSET|self-escapes-in-ctor|feEsc.TEsc.Create > feEsc.TEsc.Show') }
  @{ Name = 'Self after write SET';    Fix = 'fields-escape';  Target = 'feEsc.TEsc2.FData';      Verdict = 'SET';          Exit = 0; Uses = @(
      'feEsc.pas#USE-ESC2=SET||') }
  @{ Name = 'overload ctor MAY';       Fix = 'fields-escape';  Target = 'feEsc.TOver.FN';         Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'feEsc.pas#USE-OVER=MAY-BE-UNSET|ctor-misses-field|feEsc.TOver.Create > feEsc.TOver.Show') }
  @{ Name = 'no overload SET';         Fix = 'fields-escape';  Target = 'feEsc.TOver2.FN';        Verdict = 'SET';          Exit = 0; Uses = @(
      'feEsc.pas#USE-OVER2=SET||') }
)
function MarkerLine([string]$Dir, [string]$File, [string]$Marker) {
  $m = @(Select-String -LiteralPath (Join-Path $Dir $File) -Pattern ('// ' + [regex]::Escape($Marker) + '(\s|$)'))
  if ($m.Count -ne 1) { throw "marker '$Marker' in $File found $($m.Count) times" }
  return [int]$m[0].LineNumber
}

# Compares one parsed answer with its case; returns the mismatch descriptions.
function Compare-Case($Case, $Json, [string]$Dir) {
  $bad = @()
  if ($null -eq $Json) { return ,@('no JSON answer') }
  if ($Json.verdict -cne $Case.Verdict) { $bad += "verdict expected $($Case.Verdict) got $($Json.verdict)" }
  if ($Json.scope -cne 'instance') { $bad += "scope expected instance got $($Json.scope)" }
  if ($Case.Limit -and -not (@(@($Json.limits) | Where-Object { $_ -like $Case.Limit }).Count -ge 1)) { $bad += "limits lack $($Case.Limit): [$(@($Json.limits) -join ',')]" }
  if ($Case.NoLimit -and (@(@($Json.limits) | Where-Object { $_ -like $Case.NoLimit }).Count -ge 1)) { $bad += "limits hold $($Case.NoLimit)" }
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
      Write-Host "CHECK-INIT FIELDS: FAIL -- the driver did not build (log: $blog)" -ForegroundColor Red
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
    Copy-Item -Path (Join-Path $FixRoot "$fx\*") -Destination $d -Force
    $db = Join-Path $WorkDir "$fx.sqlite"
    $null = & $Exe index $d --db $db 2>&1
    Check "index $fx (exit 0)" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $dbs[$fx] = $db; $dirsOf[$fx] = $d
  }

  function Invoke-Answer($Case, [string]$Source) {
    $db = $dbs[$Case.Fix]
    $max = if ($Case.Max) { @('--max-routines', "$($Case.Max)") } else { @() }
    if ($Source -eq 'cli') { $raw = & $Exe check-init $Case.Target --db $db --json @max 2>$null }
    else { $raw = & $driverExe --db $db --target $Case.Target @max --stable 2>$null }
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
    Write-Host '  [SKIP] CLI form: check-init still returns the scaffold answer (INT handover H-CLI of lane HBSOLVER)' -ForegroundColor Yellow
  }

  # Comparator control: a flipped expectation must be reported.
  $flip = @{} + $first.Case
  $flip.Verdict = if ($first.Case.Verdict -eq 'SET') { 'MAY-BE-UNSET' } else { 'SET' }
  $fm = Compare-Case $flip $first.Json $dirsOf[$first.Case.Fix]
  Check 'comparator control: a flipped verdict is reported' ($fm.Count -ge 1) "mismatches=$($fm.Count)"

  if ($script:Failed) { Write-Host 'CHECK-INIT FIELDS: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'CHECK-INIT FIELDS: PASS' -ForegroundColor Green
  exit 0
} finally {
  if ((-not $SkipBuild) -and (Test-Path -LiteralPath $WorkDir) -and (-not $env:HB_KEEP_WORK)) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
  }
}
