<#
  run_lsp_caller_counts_perf_guard.ps1 -- `draglint/callerCounts` on a big file
  is bounded, and a hover sent behind it is NOT queued behind it.

  THE DEFECT (docs\INBOX-ide-hang-on-slow-engine.md section 2, 2026-10-29).
  callerCounts for DevExpress dxBar.pas (33k lines, 4,256 routines, answered from
  the platform library index) took 13 MINUTES. ComputeCallerCounts ran
  FindCallersByName ONCE PER ROUTINE -- 2,740 distinct names asked 4,256 times
  (84 `Create`s each re-fetched all 43,001 `Create` refs) -- and then
  GetFilePath ONCE PER RETURNED ROW, a fresh TFDQuery each: 4.25 million rows,
  4.25 million path queries. The LSP loop is serial, so every hover the IDE sent
  meanwhile waited the full 13 minutes.

  WHAT THIS PINS:

    BOUNDED. A fixture with the same shape -- 150 routines sharing one name and
    800 call sites of it, plus 100 distinct routines -- must answer callerCounts
    within a budget over a no-request control session. The old N+1 path spends
    tens of seconds here; the per-name aggregate spends milliseconds.

    STILL RIGHT. Speed by dropping work is not a fix: the counts of a known call
    graph are asserted (R1 = 1, R2 = 0, Run >= 800), so a handler that answered
    zeros fast fails.

    HOVER IS NOT QUEUED. A hover sent AFTER callerCounts must be ANSWERED BEFORE
    it: the server serves pending hover-class requests between callerCounts
    batches. Stdin here is a file, so the hover is always already waiting --
    which makes the reply order deterministic: the old serial loop answers
    2 then 3, the yielding one 3 then 2.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir  = "$env:TEMP\drag-lint-caller-counts-perf-$PID",
  [int]   $BudgetMs = 3000
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
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

# The dxBar shape in miniature: MANY routines sharing ONE name, MANY call sites
# of that name, and enough DISTINCT names to need more than one batch.
$classes = 150; $calls = 800; $distinct = 100
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("unit uPerf;`n`ninterface`n`ntype`n")
for ($i = 1; $i -le $classes; $i++) { [void]$sb.Append("  TC$i = class`n  public`n    procedure Run;`n  end;`n") }
[void]$sb.Append("  TMany = class`n  public`n")
for ($i = 1; $i -le $distinct; $i++) { [void]$sb.Append("    procedure R$i;`n") }
[void]$sb.Append("  end;`n`nprocedure Driver;`n`nimplementation`n`n")
for ($i = 1; $i -le $classes; $i++) { [void]$sb.Append("procedure TC$i.Run;`nbegin`nend;`n`n") }
for ($i = 1; $i -le $distinct; $i++) { [void]$sb.Append("procedure TMany.R$i;`nbegin`nend;`n`n") }
[void]$sb.Append("procedure Driver;`nvar`n  C: TC1;`n  M: TMany;`nbegin`n  M.R1;`n")
for ($i = 1; $i -le $calls; $i++) { [void]$sb.Append("  C.Run;`n") }
[void]$sb.Append("end;`n`nend.`n")
$file = Join-Path $src 'uPerf.pas'
WriteAnsi $file $sb.ToString()

$db = Join-Path $WorkDir 'perf.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$uri   = 'file:///' + ($file -replace '\\', '/')
$lines = [System.IO.File]::ReadAllLines($file)
$runCall = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*C\.Run;') { $runCall = $i; break } }

# One LSP session over a FILE stdin; returns the replies in the order written
# and the wall time. $withWork=$false is the control: same start-up, no request.
function Session([bool]$withWork) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  if ($withWork) {
    $m += Frame @{ jsonrpc='2.0'; id=2; method='draglint/callerCounts'; params=@{ textDocument=@{ uri=$uri } } }
    $m += Frame @{ jsonrpc='2.0'; id=3; method='textDocument/hover'; params=@{ textDocument=@{ uri=$uri }; position=@{ line=$runCall; character=4 } } }
  }
  $m += Frame @{ jsonrpc='2.0'; id=4; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $sw.Stop()
  $replies = @()
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($null -ne $o.id) { $replies += $o }
  }
  return [pscustomobject]@{ Ms = $sw.ElapsedMilliseconds; Replies = $replies }
}

$control = Session $false
$work    = Session $true
$cc    = @($work.Replies | Where-Object { $_.id -eq 2 })
$hover = @($work.Replies | Where-Object { $_.id -eq 3 })
$deltaMs = $work.Ms - $control.Ms

Write-Host ''
Write-Host 'BOUNDED: callerCounts on a many-same-name file' -ForegroundColor Cyan
Check 'callerCounts answered' (($cc.Count -eq 1) -and ($null -ne $cc[0].result)) "replies=$($cc.Count)"
Check "callerCounts + hover cost under $BudgetMs ms over the control session" ($deltaMs -lt $BudgetMs) `
  "session=$($work.Ms) ms control=$($control.Ms) ms delta=$deltaMs ms"

Write-Host ''
Write-Host 'STILL RIGHT: the counts of a known call graph' -ForegroundColor Cyan
$counts = if ($cc.Count -eq 1 -and $null -ne $cc[0].result) { @($cc[0].result.counts) } else { @() }
function CountAt([string]$declPattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $declPattern) {
      $hit = @($counts | Where-Object { $_.line -eq $i })
      if ($hit.Count -eq 1) { return [int]$hit[0].count }
    }
  }
  return -1
}
Check 'R1 (called once) reports 1'  ((CountAt '^\s*procedure R1;') -eq 1) "got=$(CountAt '^\s*procedure R1;')"
Check 'R2 (never called) reports 0' ((CountAt '^\s*procedure R2;') -eq 0) "got=$(CountAt '^\s*procedure R2;')"
$runCount = CountAt '^\s*procedure Run;'
Check "Run reports at least its $calls call sites" ($runCount -ge $calls) "got=$runCount"
Check 'CONTROL: every distinct routine is reported (more than one batch)' `
  ($counts.Count -ge ($classes + $distinct)) "entries=$($counts.Count)"

Write-Host ''
Write-Host 'HOVER IS NOT QUEUED behind callerCounts' -ForegroundColor Cyan
$order = @($work.Replies | ForEach-Object { [int]$_.id })
Check 'hover answered' ($hover.Count -eq 1) "replies=$($hover.Count)"
$i2 = [array]::IndexOf($order, 2); $i3 = [array]::IndexOf($order, 3)
Check 'hover (sent after callerCounts) is answered BEFORE it' (($i3 -ge 0) -and ($i2 -ge 0) -and ($i3 -lt $i2)) `
  "reply order=$($order -join ',')"
Check 'CONTROL: initialize first and shutdown last (non-hover requests keep their order)' `
  (($order.Count -ge 1) -and ($order[0] -eq 1) -and ($order[-1] -eq 4)) "reply order=$($order -join ',')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-caller-counts-perf-$PID")) { if (Test-Path -LiteralPath $d23) { [System.IO.Directory]::Delete($d23, $true) } }
}
