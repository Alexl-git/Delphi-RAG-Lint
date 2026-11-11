#Requires -Version 7
<#
  hover-cost.ps1 -- LSP textDocument/hover cost per hover, A/B between two engines on ONE DB copy.
  Origin: wave 149 LX item 5 (D1P-149 iii); fixed and moved here by wave 150 LX2 item 3.

  Method: per arm, a session with 1 hover (startup + first-hover context) and a session with N hovers;
  ms per hover = (T_N - T_1) / (N - 1), min over R repeats. Positions: routine names on their
  declaring lines (symbols.start_line), files whose path matches -PathLike, that exist on disk.

  It ASSERTS AN ANSWER BEFORE IT TIMES ANYTHING (lane rule after the 149 run printed 0.0 ms over empty
  answers): every hover id must come back with a non-null result and non-empty markdown, else the arm
  is FAIL and the script exits 1. The 149 script's defect: the repeat loop variable `$r` IS the
  parameter `$R` (PowerShell names are case-insensitive), so `for ($r = 0; $r -lt $R; ...)` reset R to
  0, the loop never ran, nothing was launched, and the "result" was [double]::MaxValue - MaxValue = 0.

  Read-only on -DbPath (lsp opens it; nothing indexes). Use a COPY, never a live project DB.
  Exit: 0 = every arm answered every hover; 1 = an arm had a missing or empty answer, or (with
  -RequireIdentical, 151 CF) an answer differed between A and B; 2 = setup error.
  Positive control of -RequireIdentical: -ExeA X -ExeB X -ExtraB --no-exception-facts -> IDENTITY FAIL (2/100 on CLIENT).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$DbPath,
  [Parameter(Mandatory)] [string]$ExeA,
  [Parameter(Mandatory)] [string]$ExeB,
  [string]$Out      = (Join-Path (Get-Location) 'hover-cost.txt'),
  [string]$PathLike = '%',
  [int]$N       = 100,
  [int]$Repeats = 2,
  [string[]]$ExtraB = @(),
  # A second store passed to BOTH arms (lsp --db A --db B): exercises the 149 LX extra-stores path
  # (HoverExtraStores = the other project stores that own the hovered file). '' = one store.
  [string]$SecondDb = '',
  # 151 CF: fail unless every hover answer is BYTE-IDENTICAL between arm A and arm B (an identity
  # acceptance: a speed fix must not change one byte of what the user reads). Off by default, so an
  # A/B of two versions that are MEANT to render differently still measures.
  [switch]$RequireIdentical
)
$ErrorActionPreference = 'Stop'
foreach ($p in @($DbPath, $ExeA, $ExeB)) { if (-not (Test-Path $p)) { Write-Host "FATAL: not found: $p" -ForegroundColor Red; exit 2 } }
if ($N -lt 2 -or $Repeats -lt 1) { Write-Host 'FATAL: -N >= 2 and -Repeats >= 1' -ForegroundColor Red; exit 2 }
$work = Split-Path -Parent ([IO.Path]::GetFullPath($Out))
function Frame($o) { $j = $o | ConvertTo-Json -Compress -Depth 10; "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j" }

$q = "SELECT f.path, s.start_line, s.name FROM symbols s JOIN files f ON f.id = s.file_id " +
     "WHERE s.kind IN ('method','function','procedure') AND f.path LIKE '$PathLike' AND s.start_line > 0 ORDER BY s.id LIMIT $(4 * $N)"
$raw = (& $ExeA sql --query $q --db $DbPath --json 2>$null) -join "`n"
$j = $raw | ConvertFrom-Json
$cache = @{}; $pos = [System.Collections.Generic.List[object]]::new()
foreach ($row in $j.rows) {
  $path = [string]$row[0]; $ln = [int]$row[1] - 1; $name = [string]$row[2]
  if (-not (Test-Path $path)) { continue }
  if (-not $cache.ContainsKey($path)) { $cache[$path] = [IO.File]::ReadAllLines($path) }
  $lines = $cache[$path]
  if ($ln -ge $lines.Count) { continue }
  $c = $lines[$ln].IndexOf($name)
  if ($c -lt 0) { continue }
  $pos.Add(@{ uri = 'file:///' + ($path -replace '\\', '/'); line = $ln; character = $c + 1 })
  if ($pos.Count -ge $N) { break }
}
"hover-cost $(Get-Date -Format s)  db=$DbPath  positions=$($pos.Count) in $($cache.Count) files (N=$N, repeats=$Repeats, second db=$SecondDb)" | Set-Content -Path $Out -Encoding ascii
if ($pos.Count -lt $N) { "FAIL: only $($pos.Count) of $N positions found (PathLike=$PathLike)" | Tee-Object -FilePath $Out -Append; exit 1 }

function Invoke-HoverSession([string]$Exe, [string[]]$Extra, [int]$Count, [string]$Tag) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  for ($i = 0; $i -lt $Count; $i++) {
    $p = $pos[$i]
    $m += Frame @{ jsonrpc='2.0'; id=(1000 + $i); method='textDocument/hover'; params=@{ textDocument=@{ uri=$p.uri }; position=@{ line=$p.line; character=$p.character } } }
  }
  $m += Frame @{ jsonrpc='2.0'; id=9; method='shutdown'; params=@{} }
  $inF = Join-Path $work "in-$Tag.txt"; $outF = Join-Path $work "out-$Tag.txt"
  [IO.File]::WriteAllText($inF, $m, [Text.Encoding]::ASCII)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Start-Process $Exe -ArgumentList (@('lsp', '--db', $DbPath) + $(if ($SecondDb) { @('--db', $SecondDb) } else { @() }) + $Extra) -WorkingDirectory $work -RedirectStandardInput $inF `
    -RedirectStandardOutput $outF -RedirectStandardError (Join-Path $work "err-$Tag.txt") -NoNewWindow -Wait | Out-Null
  $ms = $sw.Elapsed.TotalMilliseconds
  $answered = 0; $bytes = 0; $vals = @{}
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($null -eq $o.id -or [int]$o.id -lt 1000) { continue }
    $v = if ($null -ne $o.result -and $null -ne $o.result.contents) { [string]$o.result.contents.value } else { '' }
    if ($v.Length -gt 0) { $answered++; $bytes += $v.Length }
    $vals[[int]$o.id] = $v
  }
  return [pscustomobject]@{ Ms = $ms; Answered = $answered; Bytes = $bytes; Values = $vals }
}

$arms = @(
  [pscustomobject]@{ Name = "A $(((& $ExeA --version 2>$null) | Select-Object -Last 1))"; Exe = $ExeA; Extra = @() },
  [pscustomobject]@{ Name = "B $(((& $ExeB --version 2>$null) | Select-Object -Last 1)) $($ExtraB -join ' ')"; Exe = $ExeB; Extra = $ExtraB }
)
$bad = $false
foreach ($arm in $arms) {
  $best1 = [double]::MaxValue; $bestN = [double]::MaxValue; $last = $null; $armBad = $false
  for ($rep = 0; $rep -lt $Repeats; $rep++) {
    $tag = ($arm.Name.Substring(0, 1)) + "-$rep"
    $s1 = Invoke-HoverSession $arm.Exe $arm.Extra 1  "$tag-1"
    $sN = Invoke-HoverSession $arm.Exe $arm.Extra $N "$tag-N"
    if ($s1.Answered -ne 1 -or $sN.Answered -ne $N) { $armBad = $true }
    $best1 = [Math]::Min($best1, $s1.Ms); $bestN = [Math]::Min($bestN, $sN.Ms); $last = $sN
  }
  $per = ($bestN - $best1) / ($N - 1)
  $state = if ($armBad) { 'FAIL (missing/empty answers -- not a measurement)' } else { 'OK' }
  ("{0}: T1={1:N0} ms  T{2}={3:N0} ms  per hover={4:N1} ms  answered={5}/{2}  md bytes={6}  {7}" -f $arm.Name, $best1, $N, $bestN, $per, $last.Answered, $last.Bytes, $state) |
    Tee-Object -FilePath $Out -Append
  if ($armBad) { $bad = $true }
  $arm | Add-Member -NotePropertyName Last -NotePropertyValue $last
}
if ($RequireIdentical) {
  # 151 CF: per hover id, A's markdown vs B's, ordinal (byte) comparison.
  $va = $arms[0].Last.Values; $vb = $arms[1].Last.Values; $diff = 0; $first = $null
  for ($i = 0; $i -lt $N; $i++) {
    $id = 1000 + $i
    if (-not [string]::Equals([string]$va[$id], [string]$vb[$id], [StringComparison]::Ordinal)) { $diff++; if ($null -eq $first) { $first = $i } }
  }
  if ($diff -gt 0) {
    $p0 = $pos[$first]
    ("IDENTITY FAIL: {0} of {1} hover answers differ between A and B (first: {2} line {3} col {4})" -f $diff, $N, $p0.uri, $p0.line, $p0.character) | Tee-Object -FilePath $Out -Append
    $bad = $true
  } else {
    ("IDENTITY OK: all {0} hover answers byte-identical between A and B" -f $N) | Tee-Object -FilePath $Out -Append
  }
}
if ($bad) { exit 1 }
exit 0
