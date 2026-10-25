<#
  run_index_scaling_guard.ps1 -- indexing ONE file must scale near-linearly
  with its size (X-23, INBOX-lsp-ephemeral-index-cost).

  WHY. An LSP loose-file open runs a full TIndexer.IndexFile (BuildEphemeralStore),
  so the indexer's per-file cost is paid on every open of a file no --db owns.
  Measured 2026-10-24: 30k lines 6.7 s, 40k lines 56.7 s. Profiled 2026-10-25
  (DRAGLINT_PROFILE=1) on the inbox shape: the ONE superlinear phase was
  doc-scan -- TDocCommentScanner.Scan's MergeAdjacentSameKind folded each
  adjacent same-kind comment into its predecessor with a string concat AND a
  TList.Delete, both O(n) per merge, so a run of n trailing `// step` comments
  (each on the line after the last -- a merge chain) cost O(n^2): 0.43 s at 20k
  lines, 4.79 s at 40k (11x for 2x). The other phases were linear; the biggest
  constant was one SQL FindContainingSymbol per literal (~0.4 ms each), now
  answered from an in-memory line map with the SQL kept for ties.

  WHAT IT CHECKS. One unit of N lines `X := X + i; // step` (one routine body,
  every line a literal and a link in one comment-merge chain), indexed at
  N=20000 and N=40000 into a throw-away DB with DRAGLINT_PROFILE=1:
    1. both runs exit 0, write a DB and print a parseable profile
       (positive control for the instrument: a missing profile is a FAIL, never
       a vacuous pass);
    2. doc-scan ratio 40k/20k <= 4.0 (linear = 2), OR the 40k doc-scan is under
       an absolute 0.5 s floor so a phase that has become noise cannot flake.
       POSITIVE CONTROL: the pre-fix engine measures 11x and 4.79 s -> FAIL;
    3. TOTAL ratio 40k/20k <= 3.0 -- a regression budget for every other phase
       (the pre-fix engine measured 2.2 here: its quadratic phase was still a
       minor share of TOTAL at 40k, which is why check 2 isolates it).
  Bounds are generous on purpose: the CPU is shared and a near-linear phase
  wanders by +-30%; a quadratic one at 2x size moves by 4x or more.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. -Exe points at the engine to test.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ('dl-scaling-' + [Guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:fail=$true} }

$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$SmallLines = 20000
$LargeLines = 40000
$DocScanRatioMax = 4.0
$DocScanFloorSec = 0.5
$TotalRatioMax = 3.0

function New-Unit([int]$Lines, [string]$Dir) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("unit uBig;`r`n`r`ninterface`r`n`r`nprocedure Big;`r`n`r`nimplementation`r`n`r`nprocedure Big;`r`nvar`r`n  X: Integer;`r`nbegin`r`n  X := 0;`r`n")
  for ($i = 0; $i -lt $Lines; $i++) { [void]$sb.Append("  X := X + $i; // step`r`n") }
  [void]$sb.Append("end;`r`n`r`nend.`r`n")
  [IO.File]::WriteAllText((Join-Path $Dir 'uBig.pas'), $sb.ToString(), (New-Object System.Text.ASCIIEncoding))
}

function Measure-Index([int]$Lines) {
  $dir = Join-Path $WorkDir "u$Lines"
  New-Unit $Lines $dir
  $db = Join-Path $WorkDir "u$Lines.sqlite"
  $env:DRAGLINT_PROFILE = '1'
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = & $Exe index $dir --db $db 2>&1
    $code = $LASTEXITCODE
    $sw.Stop()
  } finally {
    $env:DRAGLINT_PROFILE = $null
  }
  $phase = @{}
  foreach ($l in $out) { if ("$l" -match '^\s+(\S+)\s+([\d.]+) s$') { $phase[$matches[1]] = [double]$matches[2] } }
  [pscustomobject]@{
    Lines = $Lines; Exit = $code; DbOk = (Test-Path $db) -and ((Get-Item $db).Length -gt 0)
    Wall = $sw.Elapsed.TotalSeconds; DocScan = $phase['doc-scan']; Total = $phase['TOTAL']
  }
}

$small = Measure-Index $SmallLines
$large = Measure-Index $LargeLines
foreach ($r in $small, $large) {
  Write-Host ("  {0,6} lines: wall {1,6:N2} s  TOTAL {2,6:N2} s  doc-scan {3,6:N2} s" -f $r.Lines, $r.Wall, $r.Total, $r.DocScan)
}

$instrOk = ($small.Exit -eq 0) -and ($large.Exit -eq 0) -and $small.DbOk -and $large.DbOk -and
           ($null -ne $small.Total) -and ($null -ne $large.Total) -and ($null -ne $small.DocScan) -and ($null -ne $large.DocScan) -and
           ($small.Total -gt 0) -and ($large.Total -gt 0)
Check 'both runs exit 0, write a DB and print a profile (instrument control)' $instrOk ("exit={0}/{1}" -f $small.Exit, $large.Exit)
if (-not $instrOk) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$docRatio = if ($small.DocScan -gt 0) { $large.DocScan / $small.DocScan } else { [double]::PositiveInfinity }
$docOk = ($large.DocScan -lt $DocScanFloorSec) -or ($docRatio -le $DocScanRatioMax)
Check ("doc-scan near-linear: ratio <= {0} or 40k under {1} s" -f $DocScanRatioMax, $DocScanFloorSec) $docOk ("ratio={0:N2} 40k={1:N2} s" -f $docRatio, $large.DocScan)

$totRatio = $large.Total / $small.Total
Check ("TOTAL near-linear: ratio <= {0}" -f $TotalRatioMax) ($totRatio -le $TotalRatioMax) ("ratio={0:N2}" -f $totRatio)

try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Verbose "scratch kept: $WorkDir" }
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
