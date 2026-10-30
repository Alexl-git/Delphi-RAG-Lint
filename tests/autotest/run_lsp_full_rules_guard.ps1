#Requires -Version 7
<#
  run_lsp_full_rules_guard.ps1 -- C1: `lsp --full-rules` (OPT-IN, default OFF).

  The LSP's publish on didOpen/didSave runs a SUBSET of the built-ins
  (BuildDiagnostics). With --full-rules the server runs `lint <file> --json`
  out-of-process (budget DRagLint.Core.LintBudget.LINT_CHILD_TIMEOUT_MS = 8000), publishes that set
  instead of the lint subset, keeps the compiler findings, and writes the
  measured cost to stderr: `drag-lint lsp: full-rules <file> <ms> ms <n> findings`.

  Positive controls (a silence-only assertion passes with the feature off):
    * `lint --json` itself reports missing-inherited-ctor on the fixture;
    * a rule id the subset lacks is published WITH the flag and absent WITHOUT;
    * a clean fixture publishes `"diagnostics":[]` with the flag on;
    * WITHOUT the flag the stdout is byte-identical to the pre-change engine
      (-BaselineExe; skipped with a notice when not given) and has no cost line.
  The per-save ms of two runs is printed (CPU is shared: read both).
#>
[CmdletBinding()]
param(
  [string]$Exe         = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$BaselineExe = '',
  [string]$OffBaseline = "$PSScriptRoot\fixtures\lsp\c1-off-baseline.txt",
  [switch]$CaptureOffBaseline,
  [switch]$AllowChildExeSkip, # only for an OLD engine (pre lane S): one that ignores DRAGLINT_FULLRULES_CHILD_EXE SKIPs instead of FAILing
  [string]$WorkDir     = "$env:TEMP\drag-lint-lsp-fr-$PID"
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
New-Item -ItemType Directory -Force $WorkDir | Out-Null
# LSP-1 CORE: hover/notice text never depends on the user's real defaults. The defaults file is
# the guard's OWN and names a tiny private Win64 library DB: without it the library comes from
# resolve-dbs, i.e. from whichever drag-lint.json manifest sits beside the exe under test, and
# the OFF-path frames (a "no library index" showMessage + context notice) differed between a
# deployed exe (manifest -> library found) and a build-dir exe (none) -- 1174 vs 1638 bytes.
$LibSrc = Join-Path $WorkDir 'libsrc'; New-Item -ItemType Directory -Force $LibSrc | Out-Null
[IO.File]::WriteAllText((Join-Path $LibSrc 'FxLib.pas'), "unit FxLib;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
$LibDb = Join-Path $WorkDir 'library-Win64.sqlite'
& $Exe index $LibSrc --db $LibDb 2>&1 | Out-Null
if (-not (Test-Path $LibDb)) { Write-Host 'FATAL: index produced no library DB' -ForegroundColor Red; exit 2 }
$env:DRAGLINT_CONTEXT_DEFAULTS = Join-Path $WorkDir 'context-defaults.json'
[IO.File]::WriteAllText($env:DRAGLINT_CONTEXT_DEFAULTS, (@{ libraries = @{ Win64 = @{ libraryDb = $LibDb } } } | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))

# Fixture: missing-inherited-ctor and code-after-exit are built-in rules ON by default
# that BuildDiagnostics does not run. The clean one has neither.
$dirty = @(
  'unit FxDirty;', '', 'interface', '', 'type', '  TA = class', '    constructor Create;', '  end;', '',
  'implementation', '', 'constructor TA.Create;', 'begin', '  Writeln(1);', 'end;', '',
  'procedure Go(const S: string);', 'begin', '  Exit;', '  Writeln(S);', 'end;', '', 'end.') -join "`r`n"
$clean = @('unit FxClean;', '', 'interface', '', 'implementation', '', 'end.') -join "`r`n"
$DirtyF = Join-Path $WorkDir 'FxDirty.pas'
$CleanF = Join-Path $WorkDir 'FxClean.pas'
[IO.File]::WriteAllText($DirtyF, $dirty + "`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($CleanF, $clean + "`r`n", [Text.Encoding]::ASCII)

function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function RunLsp([string]$Engine, [string]$PasFile, [string[]]$Flags, [string]$Tag) {
  $uri = 'file:///' + ($PasFile -replace '\\', '/')
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didSave'; params=@{ textDocument=@{ uri=$uri } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $dir = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $dir | Out-Null
  $in = Join-Path $dir 'in.txt'; $so = Join-Path $dir 'out.txt'; $se = Join-Path $dir 'err.txt'
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object Text.UTF8Encoding($false)))
  $a = @('lsp') + $Flags
  $p = Start-Process $Engine -ArgumentList $a -WorkingDirectory $WorkDir `
         -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait -PassThru
  $out = if (Test-Path $so) { [IO.File]::ReadAllText($so) } else { '' }
  $err = if (Test-Path $se) { [IO.File]::ReadAllText($se) } else { '' }
  $codes = @([regex]::Matches($out, '"code":"([a-z0-9\-]+)"') | ForEach-Object { $_.Groups[1].Value })
  Write-Host ("  ({0}) exit={1} published: {2}" -f $Tag, $p.ExitCode, $(if ($codes.Count) { ($codes | Sort-Object -Unique) -join ', ' } else { '<none>' })) -ForegroundColor DarkGray
  return @{ Out = $out; Err = $err; Codes = $codes }
}

Write-Host 'LSP --full-rules (opt-in, out-of-process, cost on stderr)' -ForegroundColor Cyan
$cli = (& $Exe lint $DirtyF --json 2>&1) -join "`n"
Check 'CONTROL: `lint --json` reports missing-inherited-ctor on the fixture' ($cli -match '"missing-inherited-ctor"') ''

$off = RunLsp $Exe $DirtyF @() 'off'
Check 'flag OFF: missing-inherited-ctor is NOT published (baseline shape)' ($off.Codes -notcontains 'missing-inherited-ctor') ''
Check 'flag OFF: no full-rules cost line on stderr' ($off.Err -notmatch 'drag-lint lsp: full-rules .+ \d+ ms \d+ findings') ''

$on = RunLsp $Exe $DirtyF @('--full-rules') 'on'
Check 'flag ON: missing-inherited-ctor IS published' ($on.Codes -contains 'missing-inherited-ctor') ''
Check 'flag ON: code-after-exit IS published' ($on.Codes -contains 'code-after-exit') ''
# The fixture is in no --db, so the file is unowned: its source carries the unowned label (run_lsp_unowned_label_guard.ps1).
Check 'flag ON: source is drag-lint (unowned)' ($on.Out -match '"source":"drag-lint \(unowned\)"') ''
$m = [regex]::Match($on.Err, 'drag-lint lsp: full-rules (.+) (\d+) ms (\d+) findings')
Check 'flag ON: stderr carries the cost line with numeric ms and count' $m.Success ("[" + $m.Value + "]")
Check 'flag ON: reported finding count equals the published diagnostic count' `
  ($m.Success -and ([int]$m.Groups[3].Value) -eq @([regex]::Matches($on.Out, '"source":"drag-lint')).Count) ''
# ("source":"drag-lint, not "source":" -- the draglint/context frame (LSP-1 CORE 5ba03b06) carries
#  "source":"placeholder", which is not a diagnostic.)

$on2 = RunLsp $Exe $DirtyF @('--full-rules') 'on2'
$m2 = [regex]::Match($on2.Err, 'full-rules (.+) (\d+) ms (\d+) findings')
Write-Host ("  MEASURED per-save cost (fixture FxDirty.pas, {0} findings): run1={1} ms, run2={2} ms" -f $m.Groups[3].Value, $m.Groups[2].Value, $m2.Groups[2].Value) -ForegroundColor Yellow

$cl = RunLsp $Exe $CleanF @('--full-rules') 'clean'
Check 'flag ON, clean fixture: publishes an empty diagnostics array' ($cl.Out -match '"diagnostics":\[\]') ''
$mc = [regex]::Match($cl.Err, 'full-rules (.+) (\d+) ms (\d+) findings')
Check 'flag ON, clean fixture: cost line reports 0 findings' ($mc.Success -and $mc.Groups[3].Value -eq '0') ("[" + $mc.Value + "]")

$gone = RunLsp $Exe (Join-Path $WorkDir 'Nope.pas') @('--full-rules') 'gone'
Check 'flag ON, missing file: server survives and publishes an empty set' ($gone.Out -match '"diagnostics":\[\]') ''

# ---- I1 (fix round 1): the child must get the server's own --db list ----------
# used-unit-not-resolvable / unused-unit-in-uses need the index; `lint --json` with
# no --db reports neither. The fixture unit is INDEXED in $dbDir, so the result
# depends on the DB reaching the child.
Write-Host 'LSP --full-rules passes the server --db list to the child lint' -ForegroundColor Cyan
$dbDir = Join-Path $WorkDir 'dbsrc'
New-Item -ItemType Directory -Force $dbDir | Out-Null
[IO.File]::WriteAllText((Join-Path $dbDir 'FxBase.pas'), (@('unit FxBase;','','interface','','type','  TBase = class','  end;','','implementation','','end.') -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
$UsesF = Join-Path $dbDir 'FxUses.pas'
[IO.File]::WriteAllText($UsesF, (@('unit FxUses;','','interface','','implementation','','uses FxBase, NoSuchUnitAnywhere;','','end.') -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
$dbFile = Join-Path $WorkDir 'fx.sqlite'
$null = & $Exe index $dbDir --db $dbFile 2>&1
$cliNoDb = (& $Exe lint $UsesF --json 2>&1) -join "`n"
$cliDb   = (& $Exe lint $UsesF --db $dbFile --json 2>&1) -join "`n"
Check 'CONTROL: lint --json WITHOUT --db lacks used-unit-not-resolvable' ($cliNoDb -notmatch '"used-unit-not-resolvable"') ''
Check 'CONTROL: lint --json WITH --db reports used-unit-not-resolvable' ($cliDb -match '"used-unit-not-resolvable"') ''
$dbOn = RunLsp $Exe $UsesF @('--db', $dbFile, '--full-rules') 'dbon'
Check 'flag ON with --db: the DB-dependent finding used-unit-not-resolvable IS published' ($dbOn.Codes -contains 'used-unit-not-resolvable') ''

# ---- T1 (group-4 lane T): timeout + invalid-JSON fallback via a substitute child ----
# DRAGLINT_FULLRULES_CHILD_EXE (test-only, read by RunFullRulesLint) replaces the child exe.
# An engine that ignores it (lane S not merged yet) runs the REAL lint instead, so the stub
# never runs: the probe below detects that with a marker file and the cases are SKIPped
# LOUDLY -- never a silent pass. The marker also is the positive control that the stub ran.
Write-Host 'LSP --full-rules fallback: child timeout / invalid JSON (DRAGLINT_FULLRULES_CHILD_EXE)' -ForegroundColor Cyan
$script:Skipped = 0
function Skip($n, $why) { $script:Skipped++; Write-Host ("  [SKIP] {0} -- {1}" -f $n, $why) -ForegroundColor Yellow }
$csc = @('Framework64', 'Framework') | ForEach-Object { Join-Path $env:WINDIR "Microsoft.NET\$_\v4.0.30319\csc.exe" } | Where-Object { Test-Path $_ } | Select-Object -First 1
$stubDir = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory -Force $stubDir | Out-Null
$stubExe = Join-Path $stubDir 'FullRulesChildStub.exe'
$stubOk = $false
if ($csc) {
  $null = & $csc /nologo /out:$stubExe (Join-Path $PSScriptRoot 'fixtures\lsp\FullRulesChildStub.cs') 2>&1
  $stubOk = Test-Path $stubExe
}
# The wait budget is a CONSTANT in the engine (LINT_CHILD_TIMEOUT_MS in DRagLint.Core.LintBudget since C13, then LSP_FULL_RULES_REAP_MS to reap the
# killed child) -- derive the window from it so a budget change cannot silently make the bound wrong.
$srvPas = Join-Path $PSScriptRoot '..\..\src\lsp\DRagLint.LSP.Server.pas'
$srvTxt = if (Test-Path $srvPas) { [IO.File]::ReadAllText($srvPas) } else { '' }
$budPas = Join-Path $PSScriptRoot '..\..\src\core\DRagLint.Core.LintBudget.pas'
$budTxt = if (Test-Path $budPas) { [IO.File]::ReadAllText($budPas) } else { '' }
$mB = [regex]::Match($budTxt, 'LINT_CHILD_TIMEOUT_MS\s*=\s*(\d+)')
$mR = [regex]::Match($srvTxt, 'LSP_FULL_RULES_REAP_MS\s*=\s*(\d+)')
Check 'T1 the timeout budget constants were read (LintBudget.pas + Server.pas)' ($mB.Success -and $mR.Success) ($budPas + ' ; ' + $srvPas)
$budgetS = if ($mB.Success) { [int]$mB.Groups[1].Value / 1000 } else { 8 }
$reapS   = if ($mR.Success) { [int]$mR.Groups[1].Value / 1000 } else { 2 }
$winLo   = $budgetS - 1                  # waited (almost) the whole budget
$winHi   = $budgetS + $reapS + 25        # budget + reap + process-start slack; the stub sleeps 60 s, so a hang is still caught
function RunStub([string]$Mode, [string]$Tag) {
  $marker = Join-Path $stubDir "$Tag.marker"
  $env:DRAGLINT_FULLRULES_CHILD_EXE = $stubExe
  $env:STUB_MODE = $Mode
  $env:STUB_MARKER = $marker
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = RunLsp $Exe $DirtyF @('--full-rules') $Tag
    $sw.Stop()
  } finally {
    Remove-Item Env:DRAGLINT_FULLRULES_CHILD_EXE, Env:STUB_MODE, Env:STUB_MARKER, Env:STUB_JSON_FILE -ErrorAction SilentlyContinue
  }
  $r.Marker  = Test-Path $marker
  $r.Seconds = $sw.Elapsed.TotalSeconds
  return $r
}
if (-not $stubOk) {
  # the stub is part of the guard, not of the engine: no compiler or a compile failure is a FAIL, never a SKIP
  Check 'T1 the stub child compiled (csc.exe found and FullRulesChildStub.cs built)' $false ('csc=' + $csc)
} else {
  # emit mode: the stub returns a lint array whose rule id is synthetic, so a published
  # zz-stub-rule can only come from the substituted child.
  $emitF = Join-Path $stubDir 'emit.json'
  # $cli merges stderr (a loaded-defaults note), so cut the array out of it.
  $arr = $cli.Substring($cli.IndexOf([char]91), $cli.LastIndexOf([char]93) - $cli.IndexOf([char]91) + 1)
  [IO.File]::WriteAllText($emitF, ($arr -replace 'missing-inherited-ctor', 'zz-stub-rule'), [Text.Encoding]::ASCII)
  $env:STUB_JSON_FILE = $emitF
  $probe = RunStub 'emit' 'stub-emit'
  if (-not $probe.Marker) {
    if ($AllowChildExeSkip) { Skip 'T1 timeout / invalid-JSON cases' 'this engine ignores DRAGLINT_FULLRULES_CHILD_EXE (the stub never ran) -- -AllowChildExeSkip given' }
    else { Check 'T1 engine honours DRAGLINT_FULLRULES_CHILD_EXE' $false 'the stub never ran (pass -AllowChildExeSkip only for a pre lane S engine)' }
  } else {
    Check 'T1 CONTROL: substitute child is used (synthetic rule id published)' ($probe.Codes -contains 'zz-stub-rule') ''
    Check 'T1 CONTROL: the real rule id is not published when the stub answered' ($probe.Codes -notcontains 'missing-inherited-ctor') ''

    $to = RunStub 'sleep' 'stub-sleep'
    Check 'T1 timeout: the child ran' $to.Marker ''
    Check 'T1 timeout: server waited out the budget (>= budget-1 s), then gave up well before the 60 s stub sleep' ($to.Seconds -ge $winLo -and $to.Seconds -lt $winHi) ("{0:N1} s, window {1}..{2} s from LINT_CHILD_TIMEOUT_MS" -f $to.Seconds, $winLo, $winHi)
    Check 'T1 timeout: stderr reports the fallback to the subset' ($to.Err -match 'full-rules fallback to the subset') ''
    Check 'T1 timeout: a publishDiagnostics frame is still sent (subset)' ($to.Out -match '"diagnostics":\[') ''
    Check 'T1 timeout: no full-rules-only rule id is published' (($to.Codes -notcontains 'missing-inherited-ctor') -and ($to.Codes -notcontains 'zz-stub-rule')) ''
    Check 'T1 timeout: the timed-out child was terminated (no orphan stub)' (-not (Get-Process -Name FullRulesChildStub -ErrorAction SilentlyContinue)) ''

    $bj = RunStub 'badjson' 'stub-badjson'
    Check 'T1 invalid JSON: the child ran' $bj.Marker ''
    Check 'T1 invalid JSON: stderr reports the fallback to the subset' ($bj.Err -match 'full-rules fallback to the subset') ''
    Check 'T1 invalid JSON: a publishDiagnostics frame is still sent' ($bj.Out -match '"diagnostics":\[') ''
    Check 'T1 invalid JSON: nothing from the bad child is published' ($bj.Codes -notcontains 'missing-inherited-ctor') ''
    Check 'T1 CONTROL: emit-mode run did NOT fall back (the fallback line is not unconditional)' ($probe.Err -notmatch 'full-rules fallback to the subset') ''
  }
}
if ($script:Skipped -gt 0) { Write-Host ("  {0} case group(s) SKIPPED -- see [SKIP] lines above" -f $script:Skipped) -ForegroundColor Yellow }

# ---- I2 (fix round 1): OFF-path byte identity is NEVER silently skipped ------
function NormOff([string]$s) {
  $w = $WorkDir -replace '\\', '/'
  $n = (($s -replace [regex]::Escape($WorkDir), '<W>') -replace [regex]::Escape($w), '<W>')
  # the engine version (and so the frame length) moves with every release; neither is the OFF-path contract
  $n = (($n -replace '"version":"[^"]*"', '"version":"<V>"') -replace 'Content-Length: \d+', 'Content-Length: <N>')
  # the initialize `capabilities` object grows with every new provider (C1 -> B1..B6 -> A3..A5); it is not the
  # OFF-path publish contract either, so it is masked. The publishDiagnostics frames stay byte-compared.
  $k = $n.IndexOf('"capabilities":{')
  if ($k -ge 0) {
    $start = $k + '"capabilities":'.Length
    $depth = 0; $end = -1
    for ($i = $start; $i -lt $n.Length; $i++) {
      $c = $n[$i]
      if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
    }
    if ($end -ge 0) { $n = $n.Substring(0, $start) + '"<CAPS>"' + $n.Substring($end + 1) }
  }
  return $n
}
$offNorm = NormOff $off.Out
if ($CaptureOffBaseline) {
  [IO.File]::WriteAllText($OffBaseline, $offNorm, (New-Object Text.UTF8Encoding($false)))
  Write-Host "  captured OFF-path baseline -> $OffBaseline" -ForegroundColor Yellow
} elseif ($BaselineExe -and (Test-Path $BaselineExe)) {
  $base = RunLsp ((Resolve-Path $BaselineExe).Path) $DirtyF @() 'base'
  Check 'flag OFF: publish stdout is byte-identical to the pre-change engine (-BaselineExe)' ((NormOff $base.Out) -ceq $offNorm) ("len " + (NormOff $base.Out).Length + " vs " + $offNorm.Length)
  # Non-vacuous: FxDirty publishes `"diagnostics":[]` with the flag off, so the compare above pins no finding.
  # Repeat it on a unit that DOES publish a subset finding (empty-except, an .scm rule in the lint subset), and prove the compare
  # can fail by flipping one byte of a diagnostic.
  $SubF = Join-Path $WorkDir 'FxSub.pas'
  [IO.File]::WriteAllText($SubF, ((@('unit FxSub;','','interface','','implementation','','procedure Go;','var','  A: Integer;','begin','  try','    A := 1;','  except','  end;','  Writeln(A);','end;','','end.') -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $offU  = RunLsp $Exe $SubF @() 'offu'
  $baseU = RunLsp ((Resolve-Path $BaselineExe).Path) $SubF @() 'baseu'
  $nU = NormOff $offU.Out
  $bU = NormOff $baseU.Out
  Check 'baseline compare control: both outputs carry publishDiagnostics and capabilities' (($offU.Out -match 'publishDiagnostics') -and ($baseU.Out -match 'publishDiagnostics') -and ($offU.Out -match 'capabilities') -and ($baseU.Out -match 'capabilities')) ''
  Check 'baseline compare control: the baseline output holds at least one finding' ($baseU.Out -match '"diagnostics":\[\s*\{') ''
  Check 'flag OFF with findings: publish stdout is byte-identical to the pre-change engine (-BaselineExe)' ($bU -ceq $nU) ("len " + $bU.Length + " vs " + $nU.Length)
  $mut = ([regex]'("message":")(.)').Replace($baseU.Out, { param($m) $m.Groups[1].Value + $(if ($m.Groups[2].Value -ceq 'Z') { 'Y' } else { 'Z' }) }, 1)
  Check 'baseline compare control: a one-byte mutation of a diagnostic is DETECTED (compare can fail)' ((NormOff $mut) -cne $nU) ''
} elseif (Test-Path $OffBaseline) {
  $rec = [IO.File]::ReadAllText($OffBaseline)
  Check 'flag OFF: publish stdout is byte-identical to the recorded baseline fixture' ($offNorm -ceq $rec) ("len " + $rec.Length + " vs " + $offNorm.Length)
  Check 'flag OFF: the recorded baseline is not vacuous (initialize result + publishDiagnostics)' (($rec -match 'publishDiagnostics') -and ($rec -match 'capabilities')) ''
} else {
  Check 'flag OFF: byte-identity baseline present (-BaselineExe or fixtures\lsp\c1-off-baseline.txt)' $false 'absent -- refusing to skip silently'
}
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
