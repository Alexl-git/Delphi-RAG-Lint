#Requires -Version 7
<#
  run_lsp_loose_open_scaling_guard.ps1 -- X-23 / INBOX-lsp-ephemeral-index-cost.

  WHAT THIS PINS: opening a LOOSE file (one no --db index owns) costs time
  roughly LINEAR in the file's size. One lsp session per size sends
  initialize, didOpen (with the buffer text, as an editor does), then
  semanticTokens/full (which builds the ephemeral single-unit index), then
  shutdown. The same unit shape is generated at $Small and 4 x $Small lines
  (the INBOX shape: a const array plus one long procedure body of
  `X := X + n; // step` lines) and the process CPU time of the two sessions is
  compared. CPU, not wall: the battery runs beside other lanes on a loaded
  machine, and wall time there measures the neighbours.

  THE DEFECT (measured 2026-10-26): didOpen publishes diagnostics through the
  lint engine, and the pchar-arithmetic rule's `#declared-type?` predicate
  re-scanned every enclosing scope's children for EVERY `X + n` it matched --
  O(statements) per match, so O(n^2) per file: 2k lines 11.7 s CPU, 4k lines
  40.8 s, 10k lines 252 s. The same rule made CLI `lint <file>` quadratic.
  The ephemeral index itself (semanticTokens alone) was linear.

  POSITIVE CONTROLS (a fix that silenced the rule would also be fast):
    - both sizes publish a pchar-arithmetic diagnostic on the ONE real PChar
      step, which sits AFTER the long block -- the declaration lookup has to
      cross the whole block to find it;
    - no pchar-arithmetic diagnostic on the Integer `X + n` lines;
    - semanticTokens returns tokens for both sizes.

  Budgets are generous: linear growth puts the 4x file at about 2-3x the CPU
  of the small one (fixed start-up cost dilutes it); quadratic puts it at 10x+.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-loosescale-$PID",
  [int]$Small      = 2500,
  [double]$MaxRatio = 6.0,
  [int]$MaxLargeCpuMs = 60000,
  [int]$KillAfterMs   = 180000
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
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# A tiny unrelated index, passed as --db: the session has a configured store
# that does NOT own the measured file (so it is loose), and no config lookup
# can widen the run onto a real project DB.
$other = Join-Path $WorkDir 'other'; New-Item -ItemType Directory $other | Out-Null
[IO.File]::WriteAllText((Join-Path $other 'uOther.pas'), "unit uOther;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n", [Text.ASCIIEncoding]::new())
$db = Join-Path $WorkDir 'other.sqlite'
& $Exe index $other --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host 'FATAL: could not build the unrelated index' -ForegroundColor Red; exit 2 }

function Measure-LooseOpen([int]$Lines) {
  $dir = Join-Path $WorkDir "s$Lines"; New-Item -ItemType Directory $dir | Out-Null
  $file = Join-Path $dir 'uBig.pas'
  $na = [int]($Lines / 4); $nb = $Lines - $na
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append("unit uBig;`r`n`r`ninterface`r`n`r`nconst`r`n  CBig: array[0..$($na - 1)] of Integer = (`r`n")
  for ($i = 0; $i -lt $na - 1; $i++) { [void]$sb.Append("    $i,`r`n") }
  [void]$sb.Append("    $($na - 1));`r`n`r`nprocedure Big;`r`n`r`nimplementation`r`n`r`nprocedure Big;`r`nvar`r`n  X: Integer;`r`n  P: PChar;`r`nbegin`r`n  X := 0;`r`n")
  for ($i = 0; $i -lt $nb; $i++) { [void]$sb.Append("  X := X + $i; // step`r`n") }
  [void]$sb.Append("  P := P + 1;`r`nend;`r`n`r`nend.`r`n")
  $text = $sb.ToString()
  [IO.File]::WriteAllText($file, $text, [Text.ASCIIEncoding]::new())
  $pLine = 0; $k = 0
  foreach ($ln in ($text -split "`r`n")) { if ($ln -eq '  P := P + 1;') { $pLine = $k }; $k++ }
  $uri = 'file:///' + ($file -replace '\\', '/')
  $req  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $req += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $req += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } }
  $req += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/semanticTokens/full'; params=@{ textDocument=@{ uri=$uri } } }
  $req += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF = Join-Path $dir 'in.txt'; $outF = Join-Path $dir 'out.txt'
  [IO.File]::WriteAllText($inF, $req, [Text.UTF8Encoding]::new($false))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p = Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $dir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $dir 'err.txt') -NoNewWindow -PassThru
  $null = $p.Handle
  $killed = -not $p.WaitForExit($KillAfterMs)
  if ($killed) { try { $p.Kill() } catch { }; $p.WaitForExit() }
  $sw.Stop()
  $cpu = [int]$p.TotalProcessorTime.TotalMilliseconds
  $pcharLines = @(); $tokCount = 0
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.method -eq 'textDocument/publishDiagnostics' -and $o.params.uri -eq $uri) {
      $pcharLines = @($o.params.diagnostics | Where-Object { $_.code -eq 'pchar-arithmetic' } | ForEach-Object { [int]$_.range.start.line })
    }
    if ($o.id -eq 11 -and $null -ne $o.result) { $tokCount = @($o.result.data).Count }
  }
  return [pscustomobject]@{ Lines=$Lines; CpuMs=$cpu; WallMs=$sw.ElapsedMilliseconds; Killed=$killed;
                            PLine=$pLine; PcharLines=$pcharLines; Tokens=$tokCount }
}

$s = Measure-LooseOpen $Small
$l = Measure-LooseOpen ($Small * 4)
foreach ($r in @($s, $l)) {
  Write-Host ("  {0,6} lines: cpu={1} ms wall={2} ms killed={3}" -f $r.Lines, $r.CpuMs, $r.WallMs, $r.Killed)
  Check "CONTROL ($($r.Lines)): pchar-arithmetic fires on the one PChar step, after the long block" ($r.PcharLines -contains $r.PLine) "want line $($r.PLine), got [$($r.PcharLines -join ',')]"
  Check "CONTROL ($($r.Lines)): no pchar-arithmetic on the Integer steps" ($r.PcharLines.Count -eq 1) "count=$($r.PcharLines.Count)"
  Check "CONTROL ($($r.Lines)): semanticTokens returns tokens" ($r.Tokens -gt 0) "data=$($r.Tokens)"
}
Check "the $($l.Lines)-line open finished (not killed after $KillAfterMs ms)" (-not $l.Killed)
$ratio = if ($s.CpuMs -gt 0) { [math]::Round($l.CpuMs / $s.CpuMs, 2) } else { 999 }
Check "4x the lines costs under $MaxRatio x the CPU (near-linear)" ($ratio -lt $MaxRatio) "ratio=$ratio"
Check "the $($l.Lines)-line open uses under $MaxLargeCpuMs ms CPU" ($l.CpuMs -lt $MaxLargeCpuMs) "cpu=$($l.CpuMs) ms"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
