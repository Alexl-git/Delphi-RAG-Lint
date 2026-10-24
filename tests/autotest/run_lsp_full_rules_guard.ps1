<#
  run_lsp_full_rules_guard.ps1 -- C1: `lsp --full-rules` (OPT-IN, default OFF).

  The LSP's publish on didOpen/didSave runs a SUBSET of the built-ins
  (BuildDiagnostics). With --full-rules the server runs `lint <file> --json`
  out-of-process (budget LSP_FULL_RULES_TIMEOUT_MS = 8000), publishes that set
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
  [string]$WorkDir     = "$env:TEMP\drag-lint-lsp-full-rules-$PID"
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
Check 'flag OFF: no full-rules cost line on stderr' ($off.Err -notmatch 'full-rules') ''

$on = RunLsp $Exe $DirtyF @('--full-rules') 'on'
Check 'flag ON: missing-inherited-ctor IS published' ($on.Codes -contains 'missing-inherited-ctor') ''
Check 'flag ON: code-after-exit IS published' ($on.Codes -contains 'code-after-exit') ''
Check 'flag ON: source is drag-lint' ($on.Out -match '"source":"drag-lint"') ''
$m = [regex]::Match($on.Err, 'drag-lint lsp: full-rules (.+) (\d+) ms (\d+) findings')
Check 'flag ON: stderr carries the cost line with numeric ms and count' $m.Success ("[" + $m.Value + "]")
Check 'flag ON: reported finding count equals the published diagnostic count' `
  ($m.Success -and ([int]$m.Groups[3].Value) -eq @([regex]::Matches($on.Out, '"source":"')).Count) ''

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

# ---- I2 (fix round 1): OFF-path byte identity is NEVER silently skipped ------
function NormOff([string]$s) {
  $w = $WorkDir -replace '\\', '/'
  $n = (($s -replace [regex]::Escape($WorkDir), '<W>') -replace [regex]::Escape($w), '<W>')
  # the engine version (and so the frame length) moves with every release; neither is the OFF-path contract
  return (($n -replace '"version":"[^"]*"', '"version":"<V>"') -replace 'Content-Length: \d+', 'Content-Length: <N>')
}
$offNorm = NormOff $off.Out
if ($CaptureOffBaseline) {
  [IO.File]::WriteAllText($OffBaseline, $offNorm, (New-Object Text.UTF8Encoding($false)))
  Write-Host "  captured OFF-path baseline -> $OffBaseline" -ForegroundColor Yellow
} elseif ($BaselineExe -and (Test-Path $BaselineExe)) {
  $base = RunLsp ((Resolve-Path $BaselineExe).Path) $DirtyF @() 'base'
  Check 'flag OFF: publish stdout is byte-identical to the pre-change engine (-BaselineExe)' ($base.Out -ceq $off.Out) ("len " + $base.Out.Length + " vs " + $off.Out.Length)
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
