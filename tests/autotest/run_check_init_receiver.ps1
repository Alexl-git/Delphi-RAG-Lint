<#
  run_check_init_receiver.ps1 -- `check-init` lane HBRECV (1.52): receiver-aware order (spec 5.6, ruling HB3).

  Spec docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 1a (Q3 / HB3) and 5.6.

  Init / Run on the SAME object: an instance field F written by a method W (Init) and used in a method U
  (Run) is SET when every call site of U runs W on the same receiver first -- a local, a value
  parameter, Self, or a field of Self that every constructor of its owner sets and initializes -- with
  no re-assignment and no escape of the receiver in between. Any unproven call site keeps MAY-BE-UNSET
  and adds `receiver-unproven` naming the site (the 1.52 cut line).

  Each fixture tests\fixtures\happens-before\recv-*\ is one small program, indexed into a private DB.
  Per case the runner asserts EXACTLY: the headline verdict, the exit code, `scope` = instance, and per
  judged use (found by its `// USE-...` marker line) the verdict, the sorted reason codes and the `why`
  text (a -like pattern; `{SITE-X}` stands for <file>:<line> of the `// SITE-X` marker). Every MAY case
  has a SET twin that differs by one line or one receiver:
    recv-local  TLocal (X := T.Create; X.Init; X.Run)   / TTwo (Init on A, Run on B; twin TTwoOk)
                TEsc (X handed to a var parameter between Init and Run) / TEscOk (another variable)
                TCond (Init under `if`) / TCondOk (Run under `if`)
                TReas (X re-assigned after Init) / TReasOk (re-assigned before Init)
                TParam (value parameter) / TParamVar (var parameter)
                TSelfy (Go: Init; Run) / TSelfyBad (Go: Run; Init)
                TVirt (an override of Init does not write F) / TVirt2 (the override calls inherited)
                TClos (Run inside an anonymous method) / TClosOk (Run after it)
                TNoCall (Run has no caller: an unordered root)
    recv-field  TFw (owner's constructor: FW := TFw.Create; FW.Init; Go: FW.Run)
                TFwB (no Init) / TFwR (FW re-assigned outside the constructor) /
                TFwC (Go is called from the constructor before the Init)

  Answers come from tests\fixtures\happens-before\recv-driver\RecvDriver.dpr (compiled here with dcc64):
  CheckInit, then DRagLint.Query.HappensBefore.Receiver.ApplyReceiverProof (idempotent; INT wires the
  same call into CheckInit, handover H-RECV1). -Mode driver | cli | auto as in run_check_init_fields.ps1
  (auto: driver asserted, the CLI answer compared once check-init carries the receiver proof).
  Controls: determinism (two driver runs byte-identical); idempotence (the proof applied twice changes
  nothing -- the driver output equals itself after INT wiring); comparator (a flipped verdict and a
  dropped receiver-unproven are both reported).

  Parameters: -Exe (engine that indexes the fixtures), -Repo, -WorkDir, -Mode, -SkipBuild.
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-check-init-receiver-$PID",
  [ValidateSet('auto', 'driver', 'cli')][string]$Mode = 'auto',
  [switch]$SkipBuild
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Failed = $true; $script:Fail++ }
}
Write-Host "== check-init RECEIVER verdicts (mode $Mode) ==" -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$FixRoot = Join-Path $Repo 'tests\fixtures\happens-before'

$NDC = 'no-declared-ctor,receiver-unproven'
# Case table. Uses: '<file>#<marker>=<VERDICT>|<reasons, sorted by code order>|<why -like pattern>'
# ('*' in the reasons slot = not asserted). Summary is a -like pattern.
$Cases = @(
  @{ Name = 'local X.Init; X.Run SET';      Fix = 'recv-local'; Target = 'rlWork.TLocal.FData';    Verdict = 'SET';          Exit = 0;
     Summary = '(receiver-proven:*'; Uses = @('rlWork.pas#USE-LOCAL=SET||SET by receiver: *rlWork.TLocal.Init*') }
  @{ Name = 'two objects MAY';              Fix = 'recv-local'; Target = 'rlWork.TTwo.FData';      Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-TWO=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-TWO}*no writer method*") }
  @{ Name = 'two objects twin SET';         Fix = 'recv-local'; Target = 'rlWork.TTwoOk.FData';    Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-TWOOK=SET||SET by receiver: *') }
  @{ Name = 'escape between MAY';           Fix = 'recv-local'; Target = 'rlWork.TEsc.FData';      Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-ESC=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-ESC}*escapes*") }
  @{ Name = 'escape of another var SET';    Fix = 'recv-local'; Target = 'rlWork.TEscOk.FData';    Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-ESCOK=SET||SET by receiver: *') }
  @{ Name = 'conditional Init MAY';         Fix = 'recv-local'; Target = 'rlWork.TCond.FData';     Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-COND=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-COND}*every path*") }
  @{ Name = 'conditional Run SET';          Fix = 'recv-local'; Target = 'rlWork.TCondOk.FData';   Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-CONDOK=SET||SET by receiver: *') }
  @{ Name = 're-assigned after Init MAY';   Fix = 'recv-local'; Target = 'rlWork.TReas.FData';     Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-REAS=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-REAS}*re-assigned*") }
  @{ Name = 're-assigned before Init SET';  Fix = 'recv-local'; Target = 'rlWork.TReasOk.FData';   Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-REASOK=SET||SET by receiver: *') }
  @{ Name = 'value parameter SET';          Fix = 'recv-local'; Target = 'rlWork.TParam.FData';    Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-PARAM=SET||SET by receiver: *pX*') }
  @{ Name = 'var parameter MAY';            Fix = 'recv-local'; Target = 'rlWork.TParamVar.FData'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-PARAMVAR=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-PARAMVAR}*var*parameter*") }
  @{ Name = 'Self Init; Run SET';           Fix = 'recv-local'; Target = 'rlWork.TSelfy.FData';    Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-SELFY=SET||SET by receiver: *Self*') }
  @{ Name = 'Self Run; Init MAY';           Fix = 'recv-local'; Target = 'rlWork.TSelfyBad.FData'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-SELFYBAD=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-SELFYBAD}*") }
  @{ Name = 'override skips write MAY';     Fix = 'recv-local'; Target = 'rlWork.TVirt.FData';     Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-VIRT=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-VIRT}*no writer method*") }
  @{ Name = 'override calls inherited SET'; Fix = 'recv-local'; Target = 'rlWork.TVirt2.FData';    Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-VIRT2=SET||SET by receiver: *') }
  @{ Name = 'Run in a closure MAY';         Fix = 'recv-local'; Target = 'rlWork.TClos.FData';     Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-CLOS=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-CLOS}*anonymous method*") }
  @{ Name = 'Run after a closure SET';      Fix = 'recv-local'; Target = 'rlWork.TClosOk.FData';   Verdict = 'SET';          Exit = 0;
     Uses = @('rlWork.pas#USE-CLOSOK=SET||SET by receiver: *') }
  @{ Name = 'Run never called MAY';         Fix = 'recv-local'; Target = 'rlWork.TNoCall.FData';   Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rlWork.pas#USE-NOCALL=MAY-BE-UNSET|$NDC|*receiver-unproven: *unordered root*") }
  @{ Name = 'field receiver ctor SET';      Fix = 'recv-field'; Target = 'rfOwner.TFw.FData';      Verdict = 'SET';          Exit = 0;
     Summary = '(receiver-proven:*'; Uses = @('rfOwner.pas#USE-FW=SET||SET by receiver: *rfOwner.TOwner.FW*') }
  @{ Name = 'field receiver no Init MAY';   Fix = 'recv-field'; Target = 'rfOwner.TFwB.FData';     Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rfOwner.pas#USE-FWB=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-FWB}*does not call a writer method*") }
  @{ Name = 'field re-assigned MAY';        Fix = 'recv-field'; Target = 'rfOwner.TFwR.FData';     Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rfOwner.pas#USE-FWR=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-FWR}*outside*constructor*") }
  @{ Name = 'field used in ctor MAY';       Fix = 'recv-field'; Target = 'rfOwner.TFwC.FData';     Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @("rfOwner.pas#USE-FWC=MAY-BE-UNSET|$NDC|*receiver-unproven: {SITE-FWC}*constructor*") }
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
  if ($Case.Summary -and -not ($Json.summary -like $Case.Summary)) { $bad += "summary [$($Json.summary)]" }
  if (@($Json.uses).Count -ne $Case.Uses.Count) { $bad += "uses expected $($Case.Uses.Count) got $(@($Json.uses).Count)" }
  foreach ($u in $Case.Uses) {
    if ($u -notmatch '^([^#]+)#([^=]+)=([^|]+)\|([^|]*)\|(.*)$') { $bad += "bad expectation $u"; continue }
    $file = $Matches[1]; $marker = $Matches[2]; $verdict = $Matches[3]; $reasons = $Matches[4]; $why = $Matches[5]
    $line = MarkerLine $Dir $file $marker
    foreach ($sm in [regex]::Matches($why, '\{(SITE-[A-Z0-9]+)\}')) {
      $why = $why.Replace($sm.Value, ('{0}:{1}' -f $file, (MarkerLine $Dir $file $sm.Groups[1].Value)))
    }
    $hit = @(@($Json.uses) | Where-Object { ((Split-Path $_.file -Leaf) -ieq $file) -and ([int]$_.line -eq $line) })
    if ($hit.Count -ne 1) { $bad += "$file#$marker (line $line): $($hit.Count) judged uses"; continue }
    $h = $hit[0]
    if ($h.verdict -cne $verdict) { $bad += "$file#$marker verdict expected $verdict got $($h.verdict)" }
    $gotR = (@($h.reasons) -join ',')
    if ($reasons -ne '*' -and -not ($gotR -ceq $reasons)) { $bad += "$file#$marker reasons expected [$reasons] got [$gotR]" }
    if (-not ("$($h.why)" -like $why)) { $bad += "$file#$marker why expected [$why] got [$($h.why)]" }
  }
  return ,$bad
}

try {
  if ((Test-Path -LiteralPath $WorkDir) -and -not $SkipBuild) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  $driverExe = Join-Path $WorkDir 'RecvDriver.exe'
  if (($Mode -ne 'cli') -and -not $SkipBuild) {
    $src = Join-Path $Repo 'src'
    $dirs = 'preprocess','core','context','diagnostics','doc','forms','index','lint','lsp','mcp','output','parser',
            'project','query','refactor','report','resolver','sql','storage','workspace','analysis','cli','charts'
    $paths = (@($dirs | ForEach-Object { Join-Path $src $_ }) + (Join-Path $Repo 'third_party\delphi-tree-sitter')) -join ';'
    $dpr = Join-Path $FixRoot 'recv-driver\RecvDriver.dpr'
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
      Write-Host "CHECK-INIT RECEIVER: FAIL -- the driver did not build (log: $blog)" -ForegroundColor Red
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
    $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db 2>&1 | ForEach-Object { "$_" } }
    Check "index $fx (exit 0)" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $dbs[$fx] = $db; $dirsOf[$fx] = $d
  }

  function Invoke-Answer($Case, [string]$Source) {
    $db = $dbs[$Case.Fix]
    if ($Source -eq 'cli') { $raw = & { $ErrorActionPreference = 'Continue'; & $Exe check-init $Case.Target --db $db --json 2>$null } }
    else { $raw = & { $ErrorActionPreference = 'Continue'; & $driverExe --db $db --target $Case.Target --stable 2>$null } }
    $code = $LASTEXITCODE
    $text = (@($raw) -join "`n").Trim()
    $json = $null
    try { $json = $text | ConvertFrom-Json | ForEach-Object { $_ } } catch { $json = $null }
    return @{ Text = $text; Json = $json; Code = $code }
  }

  $src0 = if ($Mode -eq 'cli') { 'cli' } else { 'driver' }
  $printed = $false
  $cliWired = $null
  $firstSet = $null; $firstMay = $null
  foreach ($c in $Cases) {
    $a = Invoke-Answer $c $src0
    if (-not $printed) { Write-Host '  -- raw answer (first case) --'; Write-Host "    $($a.Text)"; $printed = $true }
    if (($null -eq $firstSet) -and ($c.Verdict -eq 'SET')) { $firstSet = @{ Case = $c; Json = $a.Json } }
    if (($null -eq $firstMay) -and ($c.Verdict -ne 'SET')) { $firstMay = @{ Case = $c; Json = $a.Json } }
    $mis = Compare-Case $c $a.Json $dirsOf[$c.Fix]
    foreach ($m in $mis) { Check "$($c.Name)" $false $m }
    Check "$($c.Name): $($c.Target) exact" ($mis.Count -eq 0) "mismatches=$($mis.Count)"
    Check "$($c.Name): exit $($c.Exit)" ($a.Code -eq $c.Exit) "exit=$($a.Code)"
    if ($Mode -ne 'cli') {
      $b = Invoke-Answer $c 'driver'
      Check "$($c.Name): byte-identical JSON on a second run" ($a.Text -ceq $b.Text) ''
      if ($Mode -eq 'auto') {
        $cl = Invoke-Answer $c 'cli'
        if ($null -eq $cliWired) {
          # wired = the CLI carries the receiver proof (a SET case answers SET through the CLI too)
          $cliWired = ($null -ne $cl.Json) -and ($c.Verdict -ne 'SET' -or $cl.Json.verdict -eq 'SET')
          if ($c.Verdict -ne 'SET') { $cliWired = $null }
        }
        if ($cliWired) {
          $norm = { param($t) $t -replace '"ms":\d+', '"ms":0' }
          Check "$($c.Name): CLI check-init --json equals the driver" ((& $norm $cl.Text) -ceq $a.Text) ''
          Check "$($c.Name): CLI exit equals the driver" ($cl.Code -eq $a.Code) "cli=$($cl.Code) driver=$($a.Code)"
        }
      }
    }
  }
  if (($Mode -eq 'auto') -and -not $cliWired) {
    Write-Host '  [SKIP] CLI form: check-init does not carry the receiver proof yet (INT handover H-RECV1)' -ForegroundColor Yellow
  }

  # Comparator controls: a flipped verdict and a dropped receiver-unproven must be reported.
  $flip = @{} + $firstSet.Case
  $flip.Verdict = 'MAY-BE-UNSET'
  $fm = Compare-Case $flip $firstSet.Json $dirsOf[$firstSet.Case.Fix]
  Check 'comparator control: a flipped verdict is reported' ($fm.Count -ge 1) "mismatches=$($fm.Count)"
  $drop = @{} + $firstMay.Case
  $drop.Uses = @($firstMay.Case.Uses | ForEach-Object { $_ -replace ',receiver-unproven', '' })
  $dm = Compare-Case $drop $firstMay.Json $dirsOf[$firstMay.Case.Fix]
  Check 'comparator control: a missing receiver-unproven is reported' ($dm.Count -ge 1) "mismatches=$($dm.Count)"

  Write-Host ("  totals: {0} pass / {1} fail" -f $script:Pass, $script:Fail)
  if ($script:Failed) { Write-Host 'CHECK-INIT RECEIVER: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'CHECK-INIT RECEIVER: PASS' -ForegroundColor Green
  exit 0
} finally {
  if ((-not $SkipBuild) -and (Test-Path -LiteralPath $WorkDir) -and (-not $env:HB_KEEP_WORK)) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
  }
}
