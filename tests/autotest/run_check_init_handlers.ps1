<#
  run_check_init_handlers.ps1 -- `check-init` lane HBEVORD (1.52): ordered event handlers (ruling HB5).

  Spec docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.7; unit
  src\query\DRagLint.Query.HappensBefore.Handlers.pas. Fixtures tests\fixtures\happens-before\handlers-*:
    handlers-order  GCfg written in the program block before Application.Run: a button handler of the
                    auto-created form reading it is SET with relied-on-handler-order naming the handler;
                    the same read in FormCreate (OnCreate), in an OnShow handler, in a handler also called
                    from code, and in a form created at run time is MAY-BE-UNSET; GLate (written after
                    Application.Run) read in the button handler is MAY-BE-UNSET with relied-on-handler-order.
    handlers-pump   the prefix calls Application.ProcessMessages before the write: MAY-BE-UNSET.
    handlers-cond   a form created under `if` is MAY-BE-UNSET; a form created inside try..finally is SET.

  Two parts:
    API      tests\fixtures\happens-before\handlers-harness\HandlersHarness.dpr (compiled here with dcc64)
             calls THbHandlerOrderer / HbIsUnorderedEvent / HbIsUnorderedHandlerName directly;
    VERDICT  tests\fixtures\happens-before\solve-driver\SolveDriver.dpr calls CheckInit. Asserted only when
             the solver uses the Handlers unit (the INT handover hook in DRagLint.Query.HappensBefore.pas);
             reported as SKIP while it does not. -RequireHook turns that SKIP into a FAIL.
  Controls:
    * positive: in every fixture that holds a MAY handler use, a twin handler use is SET (the solver CAN
      prove a handler use), and the API part has ordered=1 rows next to the ordered=0 ones;
    * comparator: one flipped expectation must be reported.

  Parameters:
    -Exe          engine used to index the fixtures (default src\cli\Win64\Debug\drag-lint.exe)
    -Repo         repo root (default: two levels above this script)
    -WorkDir      scratch folder (deleted at the end unless HB_KEEP_WORK is set)
    -RequireHook  fail (not skip) when the solver hook is missing
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = $(. "$PSScriptRoot\lib\FreshEngineExe.ps1"; Get-FreshEngineExe),
  [string]$WorkDir = "$env:TEMP\drag-lint-check-init-handlers-$PID",
  [switch]$RequireHook
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
Write-Host '== check-init HANDLERS (ruling HB5) ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$FixRoot = Join-Path $Repo 'tests\fixtures\happens-before'
$Solver = Join-Path $Repo 'src\query\DRagLint.Query.HappensBefore.pas'
$Hooked = @(Select-String -LiteralPath $Solver -SimpleMatch -Pattern 'DRagLint.Query.HappensBefore.Handlers').Count -gt 0

# API cases: handler QName -> expected 'ordered' and a -like pattern on why (ordered=1: why must be empty).
$ApiCases = @(
  @{ Fix = 'handlers-order'; Handler = 'hoMain.TMainForm.btnGoClick';     Ordered = 1; Why = '';                      FiredBy = 'MainForm.btnGo.OnClick'; Create = 'Application.CreateForm(TMainForm'; Run = 'Application.Run;' }
  @{ Fix = 'handlers-order'; Handler = 'hoMain.TMainForm.FormCreate';     Ordered = 0; Why = '*OnCreate*' }
  @{ Fix = 'handlers-order'; Handler = 'hoMain.TMainForm.DoShowWork';     Ordered = 0; Why = '*OnShow*' }
  @{ Fix = 'handlers-order'; Handler = 'hoMain.TMainForm.btnCalledClick'; Ordered = 0; Why = '*referenced from code*' }
  @{ Fix = 'handlers-order'; Handler = 'hoLater.TLaterForm.btnLaterClick'; Ordered = 0; Why = '*TLaterForm is not created by an unconditional Application.CreateForm*' }
  @{ Fix = 'handlers-order'; Handler = 'hoMain.CallTheHandler';           Ordered = 0; Why = '*no DFM binding*' }
  @{ Fix = 'handlers-pump';  Handler = 'hpMain.TPumpForm.btnPumpClick';   Ordered = 0; Why = '*ProcessMessages*' }
  @{ Fix = 'handlers-cond';  Handler = 'hcForms.TBaseForm.btnBaseClick';  Ordered = 1; Why = '';                      FiredBy = 'BaseForm.btnBase.OnClick'; Create = 'Application.CreateForm(TBaseForm'; Run = 'Application.Run;' }
  @{ Fix = 'handlers-cond';  Handler = 'hcCond.TCondForm.btnCondClick';  Ordered = 0; Why = '*TCondForm is not created by an unconditional Application.CreateForm*' }
)
# Name constants: name -> expected unordered.
$EventCases = @{ 'OnCreate' = 1; 'onshow' = 1; 'OnActivate' = 1; 'OnTimer' = 1; 'AfterOpen' = 1; 'BeforeConnect' = 1;
                 'OnAfterScroll' = 1; '?' = 1; 'OnClick' = 0; 'OnChange' = 0; 'OnDblClick' = 0; 'OnExecute' = 0 }
$NameCases  = @{ 'FormCreate' = 1; 'formshow' = 1; 'DataModuleCreate' = 1; 'btnGoClick' = 0; 'FormClose' = 0 }

# VERDICT cases: '<file>#<marker>=<VERDICT>|<reasons -like>|<why -like>'
$Cases = @(
  @{ Name = 'button handler after prefix write'; Fix = 'handlers-order'; Target = 'hoData.GCfg'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'hoMain.pas#USE-CLICK=SET|relied-on-handler-order|*hoMain.TMainForm.btnGoClick*MainForm.btnGo.OnClick*HandlersOrder*',
      'hoMain.pas#USE-CREATE=MAY-BE-UNSET|unordered-root|*OnCreate*',
      'hoMain.pas#USE-SHOW=MAY-BE-UNSET|unordered-root|*OnShow*',
      'hoMain.pas#USE-CALLED=MAY-BE-UNSET|unordered-root|*referenced from code*',
      'hoLater.pas#USE-LATER=MAY-BE-UNSET|unordered-root|*TLaterForm is not created*') }
  @{ Name = 'prefix lacks the write';            Fix = 'handlers-order'; Target = 'hoData.GLate'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'hoMain.pas#USE-CLICK-LATE=MAY-BE-UNSET|relied-on-handler-order|*hoMain.TMainForm.btnGoClick*prefix*does not write*') }
  @{ Name = 'pump in prefix';                    Fix = 'handlers-pump';  Target = 'hpData.GPump'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'hpMain.pas#USE-PUMP=MAY-BE-UNSET|unordered-root|*ProcessMessages*') }
  @{ Name = 'conditional CreateForm';            Fix = 'handlers-cond';  Target = 'hcData.GCond'; Verdict = 'MAY-BE-UNSET'; Exit = 1; Uses = @(
      'hcForms.pas#USE-BASE=SET|relied-on-handler-order|*hcForms.TBaseForm.btnBaseClick*',
      'hcCond.pas#USE-COND=MAY-BE-UNSET|unordered-root|*TCondForm is not created*') }
)

function MarkerLine([string]$Dir, [string]$File, [string]$Marker) {
  $m = @(Select-String -LiteralPath (Join-Path $Dir $File) -SimpleMatch -Pattern "// $Marker")
  $m = @($m | Where-Object { $_.Line -match ("// " + [regex]::Escape($Marker) + '\s*$') })
  if ($m.Count -ne 1) { throw "marker '$Marker' in $File found $($m.Count) times" }
  return [int]$m[0].LineNumber
}
function TextLine([string]$Dir, [string]$File, [string]$Text) {
  $m = @(Select-String -LiteralPath (Join-Path $Dir $File) -SimpleMatch -Pattern $Text)
  if ($m.Count -ne 1) { throw "text '$Text' in $File found $($m.Count) times" }
  return [int]$m[0].LineNumber
}
function Compare-Case($Case, $Json, [string]$Dir) {
  $bad = @()
  if ($null -eq $Json) { return ,@('no JSON answer') }
  if ($Json.verdict -cne $Case.Verdict) { $bad += "verdict expected $($Case.Verdict) got $($Json.verdict)" }
  if (@($Json.uses).Count -ne $Case.Uses.Count) { $bad += "uses expected $($Case.Uses.Count) got $(@($Json.uses).Count)" }
  foreach ($u in $Case.Uses) {
    if ($u -notmatch '^([^#]+)#([^=]+)=([^|]+)\|([^|]*)\|(.*)$') { $bad += "bad expectation $u"; continue }
    $file = $Matches[1]; $marker = $Matches[2]; $verdict = $Matches[3]; $reasons = $Matches[4]; $why = $Matches[5]
    $line = MarkerLine $Dir $file $marker
    $hit = @(@($Json.uses) | Where-Object { ((Split-Path $_.file -Leaf) -ieq $file) -and ([int]$_.line -eq $line) })
    if ($hit.Count -ne 1) { $bad += "$file#$marker (line $line): $($hit.Count) judged uses"; continue }
    $h = $hit[0]
    if ($h.verdict -cne $verdict) { $bad += "$file#$marker verdict expected $verdict got $($h.verdict)" }
    $gotR = (@($h.reasons) -join ',')
    if ($gotR -cne $reasons) { $bad += "$file#$marker reasons expected [$reasons] got [$gotR]" }
    if (-not ($h.why -like $why)) { $bad += "$file#$marker why expected [$why] got [$($h.why)]" }
  }
  return ,$bad
}
function Build-Dpr([string]$Dpr, [string]$Tag) {
  $src = Join-Path $Repo 'src'
  $dirs = 'preprocess','core','context','diagnostics','doc','forms','index','lint','lsp','mcp','output','parser',
          'project','query','refactor','report','resolver','sql','storage','workspace','analysis','cli','charts'
  $paths = (@($dirs | ForEach-Object { Join-Path $src $_ }) + (Join-Path $Repo 'third_party\delphi-tree-sitter')) -join ';'
  $dcu = Join-Path $WorkDir "dcu-$Tag"
  New-Item -ItemType Directory -Path $dcu -Force | Out-Null
  $bat = Join-Path $WorkDir "b-$Tag.bat"
  $blog = Join-Path $WorkDir "build-$Tag.log"
  $q = [char]34
  $batText = "@echo off`r`ncall ${q}C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat${q}`r`n" +
    "cd /D ${q}$WorkDir${q}`r`n" +
    "dcc64 -B -Q -NU${q}$dcu${q} -E${q}$WorkDir${q} -U${q}$paths${q} -I${q}$paths${q} " +
    "-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win " +
    "${q}$Dpr${q}`r`necho BUILD_EXITCODE=%errorlevel%`r`n"
  [IO.File]::WriteAllText($bat, $batText, [Text.Encoding]::ASCII)
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ' + $q + $q + $bat + $q + ' > ' + $q + $blog + $q + ' 2>&1' + $q) -Wait -NoNewWindow
  $bl = Get-Content -LiteralPath $blog -Raw
  $ok = ($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: |Fatal: ')
  if (-not $ok) { Select-String -LiteralPath $blog -Pattern 'Error: |Fatal: ' | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red } }
  Check "build $Tag" $ok "(log: $blog)"
  return $ok
}
try {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  if (-not (Build-Dpr (Join-Path $FixRoot 'handlers-harness\HandlersHarness.dpr') 'harness')) { Write-Host 'CHECK-INIT HANDLERS: FAIL -- the harness did not build' -ForegroundColor Red; exit 1 }
  $built = $true
  if ($Hooked) { $built = Build-Dpr (Join-Path $FixRoot 'solve-driver\SolveDriver.dpr') 'driver' }
  foreach ($dll in 'sqlite3.dll','tree-sitter.dll','tree-sitter-delphi13.dll','tree-sitter-dfm.dll') {
    $from = Join-Path (Split-Path $Exe) $dll
    if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $WorkDir -Force }
  }
  $harness = Join-Path $WorkDir 'HandlersHarness.exe'
  $driver = Join-Path $WorkDir 'SolveDriver.exe'
  # Index a private copy of every fixture (never a real project DB).
  $dbs = @{}; $dirsOf = @{}
  foreach ($fx in 'handlers-order','handlers-pump','handlers-cond') {
    $d = Join-Path $WorkDir "fx\$fx"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Copy-Item -Path (Join-Path $FixRoot "$fx\*") -Destination $d -Force
    $db = Join-Path $WorkDir "$fx.sqlite"
    $null = & $Exe index $d --db $db 2>&1
    Check "index $fx (exit 0)" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $dbs[$fx] = $db; $dirsOf[$fx] = $d
  }

  Write-Host '-- API (HandlersHarness) --' -ForegroundColor Cyan
  $printed = $false
  $orderedSeen = 0; $unorderedSeen = 0
  foreach ($c in $ApiCases) {
    $raw = @(& $harness --db $dbs[$c.Fix] --handler $c.Handler 2>&1)
    if (-not $printed) { Write-Host '  -- raw harness output (first case) --'; $raw | ForEach-Object { Write-Host "    $_" }; $printed = $true }
    $rows = @($raw | Where-Object { $_ -like 'order *' })
    Check "$($c.Handler): one program row" ($rows.Count -eq 1) "rows=$($rows.Count)"
    if ($rows.Count -ne 1) { continue }
    $r = $rows[0]
    $ord = if ($r -match ' ordered=(\d) ') { [int]$Matches[1] } else { -1 }
    $why = if ($r -match ' why=(.*)$') { $Matches[1] } else { '<none>' }
    if ($ord -eq 1) { $orderedSeen++ } elseif ($ord -eq 0) { $unorderedSeen++ }
    Check "$($c.Handler): ordered=$($c.Ordered)" ($ord -eq $c.Ordered) "got ordered=$ord why=[$why]"
    if ($c.Ordered -eq 1) {
      Check "$($c.Handler): why empty" ($why -eq '') "why=[$why]"
      Check "$($c.Handler): fired_by $($c.FiredBy)" ($r -match (' fired_by=' + [regex]::Escape($c.FiredBy) + ' ')) $r
      $dpr = @(Get-ChildItem -LiteralPath $dirsOf[$c.Fix] -Filter *.dpr)[0].Name
      $cl = TextLine $dirsOf[$c.Fix] $dpr $c.Create
      $rl = TextLine $dirsOf[$c.Fix] $dpr $c.Run
      Check "$($c.Handler): create=$cl run=$rl" ($r -match " create=$cl run=$rl ") $r
      $rel = @($raw | Where-Object { $_ -like 'relied=*' })
      Check "$($c.Handler): relied text names handler, binding and heuristic" (($rel.Count -eq 1) -and
        ($rel[0] -like "*$($c.Handler)*$($c.FiredBy)*Application.Run at $dpr`:$rl*name heuristic*")) "$rel"
    } else {
      Check "$($c.Handler): why like $($c.Why)" ($why -like $c.Why) "why=[$why]"
    }
  }
  Check 'positive control: the API orders some handlers and refuses others' (($orderedSeen -ge 2) -and ($unorderedSeen -ge 5)) "ordered=$orderedSeen unordered=$unorderedSeen"
  foreach ($k in $EventCases.Keys | Sort-Object) {
    $o = @(& $harness --event $k 2>&1) -join ''
    Check "event $k unordered=$($EventCases[$k])" ($o -eq "event=$k unordered=$($EventCases[$k])") $o
  }
  foreach ($k in $NameCases.Keys | Sort-Object) {
    $o = @(& $harness --name $k 2>&1) -join ''
    Check "name $k unordered=$($NameCases[$k])" ($o -eq "name=$k unordered=$($NameCases[$k])") $o
  }

  Write-Host '-- VERDICT (SolveDriver -> CheckInit) --' -ForegroundColor Cyan
  if (-not $Hooked) {
    if ($RequireHook) { Check 'solver hook present (DRagLint.Query.HappensBefore uses ...Handlers)' $false 'HANDOVER not applied' }
    else { Write-Host '  [SKIP] verdict part: the solver does not use DRagLint.Query.HappensBefore.Handlers yet (HANDOVER H-EVORD to DRagLint.Query.HappensBefore.pas)' -ForegroundColor Yellow }
  } elseif ($built) {
    $first = $null; $setSeen = 0; $maySeen = 0
    foreach ($c in $Cases) {
      $raw = & $driver --db $dbs[$c.Fix] --target $c.Target --stable 2>$null
      $code = $LASTEXITCODE
      $text = (@($raw) -join "`n").Trim()
      if ($null -eq $first) { Write-Host '  -- raw answer (first case) --'; Write-Host "    $text" }
      $json = $null; try { $json = $text | ConvertFrom-Json } catch { $json = $null }
      if ($null -eq $first) { $first = @{ Case = $c; Json = $json } }
      $mis = Compare-Case $c $json $dirsOf[$c.Fix]
      foreach ($m in $mis) { Check "$($c.Name)" $false $m }
      Check "$($c.Name): $($c.Target) exact" ($mis.Count -eq 0) "mismatches=$($mis.Count)"
      Check "$($c.Name): exit $($c.Exit)" ($code -eq $c.Exit) "exit=$code"
      foreach ($u in @($json.uses)) { if ($u.verdict -eq 'SET') { $setSeen++ } else { $maySeen++ } }
      if (@($json.uses | Where-Object { @($_.reasons) -contains 'relied-on-handler-order' }).Count -gt 0) {
        Check "$($c.Name): answer reasons carry relied-on-handler-order" (@($json.reasons) -contains 'relied-on-handler-order') "[$(@($json.reasons) -join ',')]"
      }
    }
    Check 'positive control: some handler uses are SET, some MAY' (($setSeen -ge 2) -and ($maySeen -ge 6)) "set=$setSeen may=$maySeen"
    $flip = @{} + $first.Case
    $flip.Verdict = if ($first.Case.Verdict -eq 'SET') { 'MAY-BE-UNSET' } else { 'SET' }
    $fm = Compare-Case $flip $first.Json $dirsOf[$first.Case.Fix]
    Check 'comparator control: a flipped verdict is reported' ($fm.Count -ge 1) "mismatches=$($fm.Count)"
  }
  if ($script:Failed) { Write-Host 'CHECK-INIT HANDLERS: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'CHECK-INIT HANDLERS: PASS' -ForegroundColor Green
  exit 0
} finally {
  if ((Test-Path -LiteralPath $WorkDir) -and (-not $env:HB_KEEP_WORK)) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
  }
}
