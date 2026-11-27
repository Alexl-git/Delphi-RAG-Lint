<#
  run_v156_QE2.ps1 -- `drag-lint compare` reads a snapshot written BEFORE 1.56 and one written BY 1.56,
  in each of the three snapshot formats (.txt report, .csv forms map, graph = .dot / bundle folder).

  1.56 prints ONE command grammar, CLI style: `COMMAND who-writes --target "T" --cap 1` and the note
  `(--cap 1; raise --cap to see them)`. 1.55 and earlier wrote `-Target "T" -Cap 1` and
  `(-Cap 1; raise -Cap to see them)`. A forms CSV and a chart's DOT name no flag at all, so for those two
  formats old and new are one format; their cases pin that an old file still compares and that the
  --command naming the question may be written in either style.

  Each format: old -> new with NO change is exit 0, old -> new with ONE known change (Reset starts
  writing TFoo.FName) is exit 1 with exactly the difference the 1.56-style old side gives.

    Q2-TXT-SAME    1.55-style report, nothing changed      -> exit 0, no differences, no WARNING
    Q2-TXT-DIFF    1.55-style report, Reset now a writer   -> exit 1, the same +/- lines as the 1.56-style old side
    Q2-TXT-CMD     --command in the 1.55 style             -> same question: no warning; a real --cap change is
                                                              named as the flag (--cap: 1 vs 2)
    Q2-TXT-TWO     1.55-style file against 1.56-style file -> exit 0 (two files, nothing rerun)
    Q2-CSV-SAME    a forms CSV against itself with another provenance footer -> exit 0
    Q2-CSV-DIFF    fixture a.csv -> b.csv                  -> exit 1, one row replaced
    Q2-GRAPH-SAME  the old bundle, --command in either style, nothing changed -> exit 0
    Q2-GRAPH-DIFF  the old bundle and its bare .dot, Reset now a writer -> exit 1, the same node / edge counts
                                                              whichever style --command is written in

  The fixture project is copied to a temp folder and indexed into a PRIVATE temp DB (--db on every run).
  Run from any CWD, pwsh 7:  pwsh -File tests\autotest\run_v156_QE2.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe  = '',
  [string]$Repo = ''
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $Repo) { $Repo = "$PSScriptRoot\..\.." }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:fail = $false
$script:checks = 0
function Check($n,$ok,$d=''){
  $script:checks++
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path $Repo).Path
$Fix  = Join-Path $Repo 'tests\charts\fixtures'
$Proj0 = Join-Path $Repo 'tests\fixtures\compare-verb'
if (-not (Test-Path (Join-Path $Proj0 'Cmp.dproj'))) { Check 'fixture tests\fixtures\compare-verb\Cmp.dproj present' $false; exit 1 }
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-qe2-' + [guid]::NewGuid().ToString('N'))
$PDir = Join-Path $Work 'proj'
[void][IO.Directory]::CreateDirectory($PDir)
Copy-Item (Join-Path $Proj0 '*') $PDir
$Proj   = Join-Path $PDir 'Cmp.dproj'
$Db     = Join-Path $Work 'cmp.sqlite'
$PasU   = Join-Path $PDir 'Unit1.pas'
$Target = 'Unit1.TFoo.FName'
$Utf8   = [Text.UTF8Encoding]::new($false)

function Invoke-Engine([string[]]$ArgList) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $psi.Environment['DRAGLINT_ASK_REPORT'] = (Join-Path $Work 'no-such-Ask-Report.ps1')
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
function Update-Index {
  $r = Invoke-Engine @('index','--project',$Proj,'--db',$Db)
  Check 'setup: index the fixture into the temp DB' ($r.Code -eq 0 -and (Test-Path $Db)) "exit=$($r.Code) err=$($r.Err)"
}
# The +/- lines of a text compare, sorted: what the diff SAYS, whatever order the hunks print in.
function Get-DiffLines([string]$Out) {
  ,@(@($Out -split "`r?`n") | Where-Object { $_ -match '^[+-] ' } | Sort-Object)
}
# The five spellings a who-writes answer of this fixture can hold, 1.56 -> 1.55.
function ConvertTo-OldStyle([string]$Text) {
  $t = $Text
  foreach ($pair in @(@('--target ','-Target '), @('--project ','-Project '), @('--depth ','-Depth '), @('--cap ','-Cap '), @('--max-rows ','-MaxRows '))) {
    $t = $t.Replace($pair[0], $pair[1])
  }
  $t
}

try {
  Update-Index
  # ---- setup: the 1.56 answer (cap 1, so the note that names a flag is printed), and its 1.55 spelling
  $ask = Invoke-Engine @('ask','who-writes','--target',$Target,'--project',$Proj,'--db',$Db,'--cap','1','--plain','--out-root',(Join-Path $Work 'bundles'))
  $capNote = '(--cap 1; raise --cap to see them)'
  Check 'setup: 1.56 answer has a CLI-style COMMAND and the cap note' ($ask.Code -eq 0 -and $ask.Out -match '(?m)^COMMAND who-writes --target ' -and $ask.Out.Contains($capNote)) "exit=$($ask.Code) out=$($ask.Out) err=$($ask.Err)"
  $New156 = Join-Path $Work 'new156.txt'
  $Old155 = Join-Path $Work 'old155.txt'
  [IO.File]::WriteAllText($New156, $ask.Out, $Utf8)
  $oldText = ConvertTo-OldStyle $ask.Out
  [IO.File]::WriteAllText($Old155, $oldText, $Utf8)
  Check 'setup: the 1.55 spelling differs from the 1.56 one in the COMMAND and the note' ($oldText -match '(?m)^COMMAND who-writes -Target ' -and $oldText.Contains('(-Cap 1; raise -Cap to see them)') -and -not $oldText.Contains('--cap')) $oldText
  # the chart is asked WITHOUT a cap: a capped chart keeps its nodes when a writer is added (the
  # '+N more' row is no node), so it could not show the known difference
  $askG = Invoke-Engine @('ask','who-writes','--target',$Target,'--project',$Proj,'--db',$Db,'--plain','--out-root',(Join-Path $Work 'bundles'))
  $bundle = ''
  if ($askG.Out -match '(?m)^BUNDLE (.+?)\s*$') { $bundle = $Matches[1] }
  $OldBundle = Join-Path $Work 'oldbundle'
  $haveGraph = $bundle -and (Test-Path -LiteralPath (Join-Path $bundle 'graph.dot'))
  Check 'setup: the answer''s bundle holds graph.dot' $haveGraph "bundle=$bundle"
  if ($haveGraph) { Copy-Item -LiteralPath $bundle -Destination $OldBundle -Recurse }
  $OldDot = Join-Path $Work 'old-chart.dot'
  if ($haveGraph) { Copy-Item -LiteralPath (Join-Path $OldBundle 'graph.dot') -Destination $OldDot }
  $cmdOld = 'who-writes -Target "{0}" -Project "{1}" -Cap 1' -f $Target, $Proj
  $cmdNew = 'who-writes --target "{0}" --project "{1}" --cap 1' -f $Target, $Proj
  $chartOld = 'who-writes -Target "{0}" -Project "{1}"' -f $Target, $Proj
  $chartNew = 'who-writes --target "{0}" --project "{1}"' -f $Target, $Proj

  # ---- nothing changed yet ------------------------------------------------------------------------
  $r = Invoke-Engine @('compare','--old',$Old155,'--db',$Db)
  Check 'Q2-TXT-SAME exit 0 for a 1.55-style report' ($r.Code -eq 0) "exit=$($r.Code) out=$($r.Out) err=$($r.Err)"
  Check 'Q2-TXT-SAME says no differences, no WARNING' ($r.Out -match 'result: no differences' -and ($r.Out + $r.Err) -notmatch 'WARNING') ($r.Out + $r.Err)
  $r = Invoke-Engine @('compare','--old',$Old155,'--new',$New156)
  Check 'Q2-TXT-TWO 1.55 file against 1.56 file is exit 0' ($r.Code -eq 0 -and $r.Out -match 'result: no differences') "exit=$($r.Code) out=$($r.Out) err=$($r.Err)"

  $r = Invoke-Engine @('compare','--old',$New156,'--command',$cmdOld,'--db',$Db)
  Check 'Q2-TXT-CMD a 1.55-style --command is the same question (exit 0, no WARNING)' ($r.Code -eq 0 -and ($r.Out + $r.Err) -notmatch 'WARNING') "exit=$($r.Code) $($r.Out + $r.Err)"
  $r = Invoke-Engine @('compare','--old',$Old155,'--command',($cmdOld -replace '-Cap 1','-Cap 2'),'--db',$Db)
  Check 'Q2-TXT-CMD a real cap change is named as the flag' (($r.Out + $r.Err) -match 'differs from the report''s COMMAND: --cap: 1 vs 2') "exit=$($r.Code) $($r.Out + $r.Err)"

  $csvA = [IO.File]::ReadAllText((Join-Path $Fix 'forms\a.csv'))
  $csvA2 = Join-Path $Work 'a-refooted.csv'
  [IO.File]::WriteAllText($csvA2, $csvA.Replace('forms-csv algorithm v7', 'forms-csv algorithm v8').Replace('2026-10-10 14:32:00', '2026-11-27 09:00:00'), $Utf8)
  Check 'setup: the re-footed CSV is another file' ($csvA -ne [IO.File]::ReadAllText($csvA2))
  $r = Invoke-Engine @('compare','--old',(Join-Path $Fix 'forms\a.csv'),'--new',$csvA2)
  Check 'Q2-CSV-SAME an old CSV against the same rows under a newer footer is exit 0' ($r.Code -eq 0 -and $r.Out -match 'result: no differences') "exit=$($r.Code) out=$($r.Out) err=$($r.Err)"
  $r = Invoke-Engine @('compare','--old',(Join-Path $Fix 'forms\a.csv'),'--new',(Join-Path $Fix 'forms\b.csv'))
  $csvDiff = Get-DiffLines $r.Out
  Check 'Q2-CSV-DIFF a.csv -> b.csv is exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err)"
  $csvGone = @($csvDiff | Where-Object { $_ -match '^- ' } | ForEach-Object { if ($_ -match '"(Tfrm\w+)"') { $Matches[1] } })
  $csvCame = @($csvDiff | Where-Object { $_ -match '^\+ ' } | ForEach-Object { if ($_ -match '"(Tfrm\w+)"') { $Matches[1] } })
  Check 'Q2-CSV-DIFF exactly the known rows: Orders gone, Customers'' handler changed, Help new' (($csvGone -join ',') -eq 'TfrmOrders,TfrmCustomers' -and ($csvCame -join ',') -eq 'TfrmCustomers,TfrmHelp') ($csvDiff -join ' | ')

  if ($haveGraph) {
    foreach ($style in @(@('1.55-style', $chartOld), @('1.56-style', $chartNew))) {
      $r = Invoke-Engine @('compare','--old',$OldBundle,'--command',$style[1],'--db',$Db,'--out-root',(Join-Path $Work 'bundles'))
      Check "Q2-GRAPH-SAME old bundle, $($style[0]) --command, exit 0" ($r.Code -eq 0) "exit=$($r.Code) out=$($r.Out) err=$($r.Err)"
    }
  }

  # ---- the known difference: Reset now writes FName ------------------------------------------------
  $t = [IO.File]::ReadAllText($PasU)
  $from = "procedure TFoo.Reset;`r`nbegin`r`n"
  Check 'setup: Unit1.pas holds the empty Reset' ($t.Contains($from))
  [IO.File]::WriteAllText($PasU, $t.Replace($from, $from + "  FName:= '';`r`n"), [Text.Encoding]::ASCII)
  Update-Index

  $rNew = Invoke-Engine @('compare','--old',$New156,'--db',$Db)
  $want = Get-DiffLines $rNew.Out
  Check 'control: the 1.56-style old side sees the change (exit 1, + and - lines)' ($rNew.Code -eq 1 -and $want.Count -ge 2) "exit=$($rNew.Code) out=$($rNew.Out) err=$($rNew.Err)"
  $rOld = Invoke-Engine @('compare','--old',$Old155,'--db',$Db)
  $got = Get-DiffLines $rOld.Out
  Check 'Q2-TXT-DIFF exit 1 for the 1.55-style report' ($rOld.Code -eq 1) "exit=$($rOld.Code) err=$($rOld.Err)"
  # the old side's own lines are shown as the file holds them, so '-' lines are compared in one spelling
  $gotFolded = @($got | ForEach-Object { $_.Replace('-Cap', '--cap') })
  Check 'Q2-TXT-DIFF the same +/- lines as the 1.56-style old side, nothing more' (($gotFolded -join "`n") -eq ($want -join "`n")) ("got: " + ($got -join ' | ') + "   want: " + ($want -join ' | '))
  Check 'Q2-TXT-DIFF the deleted line is shown in the spelling the old file holds' (@($got | Where-Object { $_ -match '^- ' -and $_.Contains('--cap') }).Count -eq 0) ($got -join ' | ')

  if ($haveGraph) {
    $counts = @()
    foreach ($case in @(@('bundle, 1.55-style', $OldBundle, $chartOld), @('bundle, 1.56-style', $OldBundle, $chartNew), @('.dot file, 1.55-style', $OldDot, $chartOld))) {
      $r = Invoke-Engine @('compare','--old',$case[1],'--command',$case[2],'--db',$Db,'--format','json','--out-root',(Join-Path $Work 'bundles'))
      $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
      # graph.nodes_added / nodes_removed / edges_added / edges_removed are ARRAYS of names
      $added = @(if ($j) { $j.graph.nodes_added })   # @( ) outside: an if-expression unrolls a one-item array
      Check "Q2-GRAPH-DIFF $($case[0]): exit 1, exactly the Reset node added, none removed" ($r.Code -eq 1 -and $added.Count -eq 1 -and $added[0] -match 'Reset' -and @($j.graph.nodes_removed).Count -eq 0) "exit=$($r.Code) out=$($r.Out) err=$($r.Err)"
      if ($j) { $counts += ('{0} / {1} / {2} / {3}' -f (@($j.graph.nodes_added) -join ','), (@($j.graph.nodes_removed) -join ','), (@($j.graph.edges_added) -join ','), (@($j.graph.edges_removed) -join ',')) }
    }
    Check 'Q2-GRAPH-DIFF the same nodes and edges whichever style and form' ($counts.Count -eq 3 -and @($counts | Select-Object -Unique).Count -eq 1) ($counts -join '   |   ')
  }
  # a check that silently did not run (a script error inside a case) must not read as a pass
  $expected = 25
  Check "all $expected checks ran" ($script:checks -eq $expected) "ran $($script:checks)"
}
finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:fail) { Write-Host "run_v156_QE2: FAIL ($script:checks checks)" -ForegroundColor Red; exit 1 }
Write-Host "run_v156_QE2: PASS ($script:checks checks)" -ForegroundColor Green
exit 0
