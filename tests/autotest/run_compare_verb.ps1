<#
  run_compare_verb.ps1 -- `drag-lint compare` end to end, against the REAL in-process engine.

  The verb reruns a saved report's COMMAND and diffs the normalised text. Every chart question
  is answered in-process by the engine, so this test copies the fixture project
  tests\fixtures\compare-verb (Cmp.dproj: TFoo.FName written by SetName and Load) into a temp
  folder, indexes it into a PRIVATE temp DB and passes that DB with --db on every rerun (the
  fixture is in no manifest; no real DB is touched). The old report is the engine's own
  `ask who-writes --plain`. DRAGLINT_ASK_REPORT points at a script that does not exist, so a
  rerun that silently fell back to PowerShell could not pass:

    C-SAME      same index, same answer -> exit 0, "result: no differences", NEW names the temp DB
    C-DIFF      Reset made a writer + reindex -> exit 1, + Reset row, totals line changed
    C-JSON      --format json        -> parses, schema compare/1, exit_code 1
    C-HTML      --format html        -> file written, light/dark CSS, path printed
    C-NOCMD     no source at all     -> exit 2 + usage on stderr
    C-NOCMD2    legacy old, no --command -> exit 2 naming --command
    C-WARN      legacy old + --command   -> WARNING line first
    C-STALE     a member file edited, not reindexed -> exit 3, ERROR on stderr, JSON envelope parses
    C-REMARKS   --in U.pas --line N --update-doc -> only block 2 rewritten
    C-SHOW      --show report        -> HTML page
    C-CSV       two forms CSVs       -> exit 1
    C-GRAPH     two bundle folders   -> exit 1, graph counts in the JSON
    C-HOSTILE   graph.svg with script / on* / javascript: / markup after </svg>, and the R26
                bypasses (<scr<script>ipt>, "onclick=, javascript&colon;, <meta refresh>)
                                     -> the SVG is WITHHELD (not inlined) on the compare and
                                        --show pages, a withheld line instead, CSP meta kept;
                                        the text output carries the same WARNING
    C-SAFE      the real graphviz graph.svg -> still inlined, nothing withheld
    C-ENTITY    &#xD800; in a DOT TITLE and in the SVG -> exit 0/1 (never the stale code 3)
    C-QUOTED    quoted DOT ids ("A" -> "B") -> read, so two different charts are exit 1
    C-EMPTY     a non-blank DOT that parses to nothing -> exit 2 'parsed as empty', not 'same'
    C-THROW     an exception inside the verb (--output is a folder) -> exit 2, ERROR: <class>,
                                     JSON envelope on stdout (exit 3 stays 'stale index' only)
    C-SAVE      --question --save    -> a snapshot file; --auto then compares against it
    C-HELP      compare --help       -> the banner names the verb

  Run from any CWD, pwsh 7:  pwsh -File tests\autotest\run_compare_verb.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe  = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Repo = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Skip($n,$why){ Write-Host ("[SKIP] {0}" -f $n) -ForegroundColor Yellow; Write-Host "      $why" -ForegroundColor DarkGray }

$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path $Repo).Path
$Fix  = Join-Path $Repo 'tests\charts\fixtures'
$Proj0 = Join-Path $Repo 'tests\fixtures\compare-verb'
if (-not (Test-Path (Join-Path $Proj0 'Cmp.dproj'))) { Check 'fixture tests\fixtures\compare-verb\Cmp.dproj present' $false; exit 1 }
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-compare-verb-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$PDir = Join-Path $Work 'proj'
New-Item -ItemType Directory -Force -Path $PDir | Out-Null
Copy-Item (Join-Path $Proj0 '*') $PDir
$Proj   = Join-Path $PDir 'Cmp.dproj'
$Db     = Join-Path $Work 'cmp.sqlite'
$PasU   = Join-Path $PDir 'Unit1.pas'
$Target = 'Unit1.TFoo.FName'

# Runs the engine; returns .Code .Out .Err. DRAGLINT_ASK_REPORT names a missing script: no PowerShell fallback.
function Invoke-Compare([string[]]$ArgList) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $psi.Environment['DRAGLINT_ASK_REPORT'] = (Join-Path $Work 'no-such-Ask-Report.ps1')
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
# (Re)indexes the temp copy into the private temp DB; incremental after the first run.
function Update-Index {
  $r = Invoke-Compare @('index','--project',$Proj,'--db',$Db)
  Check 'setup: index the fixture into the temp DB' ($r.Code -eq 0 -and (Test-Path $Db)) "exit=$($r.Code) err=$($r.Err)"
}
# Rewrites one exact piece of the temp copy's Unit1.pas (ASCII, CRLF kept); the piece must be there.
function Edit-Unit([string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($PasU)
  Check "setup: Unit1.pas holds [$From]" ($t.Contains($From))
  [IO.File]::WriteAllText($PasU, $t.Replace($From, $To), [Text.Encoding]::ASCII)
}
# The old report: the engine's own plain answer from the temp DB, kept as a file (UTF-8, no BOM).
function New-OldReport([string]$Path) {
  $r = Invoke-Compare @('ask','who-writes','--target',$Target,'--project',$Proj,'--db',$Db,'--plain','--out-root',(Join-Path $Work 'bundles'))
  Check 'setup: ask --plain wrote the old report' ($r.Code -eq 0 -and $r.Out -match '(?m)^COMMAND who-writes ') "exit=$($r.Code) err=$($r.Err)"
  [IO.File]::WriteAllText($Path, $r.Out, [Text.UTF8Encoding]::new($false))
}

try {
  Update-Index
  $Old  = Join-Path $Work 'old.txt'
  New-OldReport $Old

  # C-SAME: nothing changed between the two runs
  $r = Invoke-Compare @('compare','--old',$Old,'--db',$Db)
  Check 'C-SAME exit 0' ($r.Code -eq 0) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-SAME says no differences' ($r.Out -match 'result: no differences') $r.Out
  Check 'C-SAME new run read the temp DB, fresh' ($r.Out -match '(?m)^NEW .*index cmp\.sqlite .*\(fresh\)') $r.Out

  # C-DIFF: a real change -- Reset now writes FName -- reindexed, so the rerun answers differently
  Edit-Unit "procedure TFoo.Reset;`r`nbegin`r`n" "procedure TFoo.Reset;`r`nbegin`r`n  FName:= '';`r`n"
  Update-Index
  $r = Invoke-Compare @('compare','--old',$Old,'--db',$Db)
  $lines = @($r.Out -split "`r?`n")
  $adds = @($lines | Where-Object { $_ -match '^\+ ' })
  $dels = @($lines | Where-Object { $_ -match '^- ' })
  Check 'C-DIFF exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-DIFF Reset row added' (@($adds | Where-Object { $_ -match 'TFoo\.Reset @Unit1\.pas:\d+ -- 1 write site' }).Count -eq 1) ($adds -join '|')
  Check 'C-DIFF totals 2 -> 3, nothing else changed' ($adds.Count -eq 2 -and $dels.Count -eq 1 -and $dels[0] -match '2 write sites / 2 routines' -and ($adds -match '3 write sites / 3 routines')) (($dels + $adds) -join '|')

  # C-JSON
  $r = Invoke-Compare @('compare','--old',$Old,'--db',$Db,'--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-JSON parses' ($null -ne $j) $r.Out
  Check 'C-JSON schema compare/1' ($j -and $j.schema -eq 'compare/1')
  Check 'C-JSON exit_code 1' ($j -and $j.exit_code -eq 1 -and $r.Code -eq 1) "exit=$($r.Code)"
  Check 'C-JSON counts 1 removed / 2 added' ($j -and $j.counts.removed -eq 1 -and $j.counts.added -eq 2) ($j.counts | ConvertTo-Json -Compress)

  # C-HTML
  $html = Join-Path $Work 'out.html'
  $r = Invoke-Compare @('compare','--old',$Old,'--db',$Db,'--format','html','--output',$html)
  Check 'C-HTML exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-HTML file written' (Test-Path $html)
  Check 'C-HTML light/dark css' ((Test-Path $html) -and ([IO.File]::ReadAllText($html) -match 'prefers-color-scheme'))
  Check 'C-HTML path printed' ($r.Out -match [regex]::Escape($html)) $r.Out

  # C-NOCMD
  $r = Invoke-Compare @('compare')
  Check 'C-NOCMD exit 2' ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'C-NOCMD usage on stderr' ($r.Err -match 'Usage: drag-lint compare') $r.Err
  $legacy = Join-Path $Work 'legacy.txt'
  [IO.File]::WriteAllText($legacy, "Who writes this field (drag-lint report who-writes) for Unit1.TFoo.Name, asked on 2026-10-01.`r`nTotals: 2 write sites / 2 routines.`r`n  Unit1.TFoo.SetName (Unit1.pas:10)`r`n  Unit1.TFoo.Load (Unit1.pas:42)`r`n", [Text.Encoding]::ASCII)
  $r = Invoke-Compare @('compare','--old',$legacy)
  Check 'C-NOCMD2 exit 2' ($r.Code -eq 2) "exit=$($r.Code)"
  Check 'C-NOCMD2 names --command' ($r.Err -match '--command') $r.Err

  # C-WARN
  # The command is unquoted: the engine's ParamStr does not undo the \" escaping ArgumentList applies.
  $r = Invoke-Compare @('compare','--old',$legacy,'--db',$Db,'--command',"who-writes -Target $Target -Project $Proj")
  $first = ($r.Out -split "`r?`n")[0]
  Check 'C-WARN WARNING line first' ($first -match '^WARNING: .*original command is unknown') "first=[$first] exit=$($r.Code) err=$($r.Err)"
  Check 'C-WARN the rerun answered (exit 0/1)' ($r.Code -in 0, 1) "exit=$($r.Code) err=$($r.Err)"

  # C-STALE: a member file changed since the index was built; the new run must refuse
  Edit-Unit "  FName:= '';`r`n" "  FName:= ''; // edited, not reindexed`r`n"
  $r = Invoke-Compare @('compare','--old',$Old,'--db',$Db)
  Check 'C-STALE exit 3' ($r.Code -eq 3) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-STALE ERROR on stderr' ($r.Err -match '(?m)^ERROR: .*stale') $r.Err
  $r = Invoke-Compare @('compare','--old',$Old,'--db',$Db,'--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-STALE json envelope parses' ($r.Code -eq 3 -and $j -and $j.exit_code -eq 3 -and $j.message) "exit=$($r.Code) out=$($r.Out)"
  Update-Index
  # positive control: the same compare after the reindex is no longer refused as stale
  Check 'C-STALE reindexed -> answers again (exit 1)' ((Invoke-Compare @('compare','--old',$Old,'--db',$Db)).Code -eq 1)

  # C-REMARKS: block 2 is pointed at the fixture's question (its body is not the real answer)
  $unit = Join-Path $Work 'TwoBlocks.pas'
  $tb = [IO.File]::ReadAllText((Join-Path $Fix 'remarks\TwoBlocks.pas'))
  $tb = $tb.Replace('COMMAND who-calls -Target "TFoo.Two" -Project "C:\P\A.dproj" -Depth 3', "COMMAND who-writes -Target `"$Target`" -Project `"$Proj`"")
  [IO.File]::WriteAllText($unit, $tb, [Text.Encoding]::ASCII)
  $before = [IO.File]::ReadAllLines($unit)
  $line2  = 1 + [array]::FindIndex($before, [Predicate[string]]{ param($s) $s -like "*COMMAND who-writes -Target ""$Target""*" })
  Check 'setup: TwoBlocks block 2 retargeted' ($line2 -gt 6)
  $r = Invoke-Compare @('compare','--in',$unit,'--line',"$line2",'--db',$Db,'--update-doc')
  $after = [IO.File]::ReadAllLines($unit)
  Check 'C-REMARKS exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err) out=$($r.Out)"
  Check 'C-REMARKS block 1 identical' (($before[0..($line2 - 6)] -join "`n") -eq ($after[0..($line2 - 6)] -join "`n"))
  Check 'C-REMARKS block 2 rewritten' (($after -join "`n") -match 'TFoo\.SetName \(Unit1\.pas:\d+\)' -and ($after -join "`n") -notmatch 'TFoo\.Bar \(Foo\.pas:10\)\s*\r?\n\s*/// </remarks>\s*\r?\n\s*procedure Two') (($after[($line2 - 3)..($after.Count - 1)]) -join ' | ')
  Check 'C-REMARKS usage: --update-doc needs --in' ((Invoke-Compare @('compare','--old',$Old,'--update-doc')).Code -eq 2)

  # C-SHOW
  $page = Join-Path $Work 'show.html'
  $r = Invoke-Compare @('compare','--show',$Old,'--output',$page)
  Check 'C-SHOW exit 0' ($r.Code -eq 0) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-SHOW page written' ((Test-Path $page) -and ([IO.File]::ReadAllText($page) -match 'prefers-color-scheme'))
  Check 'C-SHOW refuses other sources' ((Invoke-Compare @('compare','--show',$Old,'--old',$Old)).Code -eq 2)

  # C-CSV
  $r = Invoke-Compare @('compare','--old',(Join-Path $Fix 'forms\a.csv'),'--new',(Join-Path $Fix 'forms\b.csv'))
  Check 'C-CSV exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err)"

  # C-GRAPH
  $ga = Join-Path $Work 'ga'; $gb = Join-Path $Work 'gb'
  New-Item -ItemType Directory -Force -Path $ga, $gb | Out-Null
  Copy-Item (Join-Path $Fix 'graph\who-writes-a.dot') (Join-Path $ga 'graph.dot')
  Copy-Item (Join-Path $Fix 'graph\who-writes-a.svg') (Join-Path $ga 'graph.svg')
  Copy-Item (Join-Path $Fix 'graph\who-writes-b.dot') (Join-Path $gb 'graph.dot')
  Copy-Item (Join-Path $Fix 'graph\who-writes-a.svg') (Join-Path $gb 'graph.svg')
  $r = Invoke-Compare @('compare','--old',$ga,'--new',$gb,'--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-GRAPH exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-GRAPH json has graph counts' ($j -and $null -ne $j.graph.nodes_added) $r.Out

  # C-HOSTILE: a graph.svg is data from disk; nothing in it may run in the page (O3)
  $ha = Join-Path $Work 'ha'; $hb = Join-Path $Work 'hb'
  New-Item -ItemType Directory -Force -Path $ha, $hb | Out-Null
  Copy-Item (Join-Path $Fix 'graph\who-writes-a.dot') (Join-Path $ha 'graph.dot')
  Copy-Item (Join-Path $Fix 'graph\hostile.svg') (Join-Path $ha 'graph.svg')
  Copy-Item (Join-Path $Fix 'graph\who-writes-b.dot') (Join-Path $hb 'graph.dot')
  Copy-Item (Join-Path $Fix 'graph\hostile.svg') (Join-Path $hb 'graph.svg')
  $withheld = 'chart image withheld: the SVG contains content that is not allowed ('
  $csp = '<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; img-src data:">'
  $hpage = Join-Path $Work 'hostile.html'
  $r = Invoke-Compare @('compare','--old',$ha,'--new',$hb,'--format','html','--output',$hpage)
  $spage = Join-Path $Work 'hostile-show.html'
  $r2 = Invoke-Compare @('compare','--show',$ha,'--output',$spage)
  foreach ($pg in @(@('compare', $r, $hpage), @('show', $r2, $spage))) {
    $h = $(if (Test-Path $pg[2]) { [IO.File]::ReadAllText($pg[2]) } else { '' })
    Check "C-HOSTILE $($pg[0]) page written" ($pg[1].Code -le 1 -and $h -ne '') "exit=$($pg[1].Code) err=$($pg[1].Err)"
    Check "C-HOSTILE $($pg[0]) no script / handler / javascript: / payload" ($h -ne '' -and $h -notmatch '(?i)<script|<foreignobject|javascript:|alert\(|\son\w+\s*=') ([regex]::Match($h, '(?i).{0,60}(<script|javascript:|alert\(|\son\w+\s*=).{0,60}').Value)
    Check "C-HOSTILE $($pg[0]) CSP meta" ($h.Contains($csp))
    Check "C-HOSTILE $($pg[0]) svg withheld" ($h -notmatch '(?i)<svg' -and $h.Contains($withheld)) ([regex]::Match($h, '(?i).{0,60}<svg.{0,60}').Value)
  }
  # R26: the reviewer's bypasses of the old strip-based defusing, each against the built exe
  $svgHead = '<svg width="10pt" height="10pt" xmlns="http://www.w3.org/2000/svg"><g id="graph0" class="graph"><text>KEEP-NODE</text>'
  $bypasses = [ordered]@{
    'split-script' = '<scr<script>ipt>alert(11)</scr<script>ipt>'
    'quote-onclick' = '<text x="1"onclick="alert(12)">X</text>'
    'colon-entity' = '<a href="javascript&colon;alert(14)"><text>L</text></a>'
    'meta-refresh' = '<meta http-equiv="refresh" content="0;url=https://example.invalid/">'
  }
  # the old side has no svg, so any <svg on the compare page would be the refused one
  $plain = Join-Path $Work 'plain'
  New-Item -ItemType Directory -Force -Path $plain | Out-Null
  Copy-Item (Join-Path $Fix 'graph\who-writes-a.dot') (Join-Path $plain 'graph.dot')
  foreach ($name in $bypasses.Keys) {
    $bd = Join-Path $Work "byp-$name"
    New-Item -ItemType Directory -Force -Path $bd | Out-Null
    Copy-Item (Join-Path $Fix 'graph\who-writes-b.dot') (Join-Path $bd 'graph.dot')
    [IO.File]::WriteAllText((Join-Path $bd 'graph.svg'), ($svgHead + $bypasses[$name] + '</g></svg>'), [Text.Encoding]::ASCII)
    $bp = Join-Path $Work "byp-$name.html"
    $bs = Join-Path $Work "byp-$name-show.html"
    $rb = Invoke-Compare @('compare','--old',$plain,'--new',$bd,'--format','html','--output',$bp)
    $rs = Invoke-Compare @('compare','--show',$bd,'--output',$bs)
    foreach ($pg in @(@('compare', $rb, $bp), @('show', $rs, $bs))) {
      $h = $(if (Test-Path $pg[2]) { [IO.File]::ReadAllText($pg[2]) } else { '' })
      $snip = [regex]::Match($h, '(?i).{0,40}(<svg|alert\(|example\.invalid).{0,40}').Value
      Check "C-HOSTILE $name $($pg[0]) withheld, no payload, CSP" ($pg[1].Code -le 1 -and $h -ne '' -and $h -notmatch '(?i)<svg|alert\(|example\.invalid' -and $h.Contains($withheld) -and $h.Contains($csp)) ("exit={0} err={1} hit={2}" -f $pg[1].Code, $pg[1].Err, $snip)
    }
    $rt = Invoke-Compare @('compare','--old',$plain,'--new',$bd)
    Check "C-HOSTILE $name text WARNING" ($rt.Code -le 1 -and $rt.Out -match ('(?m)^WARNING: ' + [regex]::Escape($withheld))) "exit=$($rt.Code) out=$($rt.Out)"
  }

  # C-SAFE: the real graphviz SVG is still inlined, nothing withheld
  $safe = Join-Path $Work 'safe.html'
  $r = Invoke-Compare @('compare','--old',$gb,'--new',$ga,'--format','html','--output',$safe)
  $h = $(if (Test-Path $safe) { [IO.File]::ReadAllText($safe) } else { '' })
  Check 'C-SAFE graphviz svg inlined and marked' ($r.Code -eq 1 -and $h -match '<svg' -and $h -match 'dl-added' -and -not $h.Contains('withheld')) "exit=$($r.Code) err=$($r.Err)"

  # C-ENTITY: a lone surrogate entity is not a character; it must not kill the verb with exit 3
  $ea = Join-Path $Work 'ea'
  New-Item -ItemType Directory -Force -Path $ea | Out-Null
  $dotE = [IO.File]::ReadAllText((Join-Path $Fix 'graph\who-writes-b.dot')) -replace 'TITLE="6 write sites', 'TITLE="&#xD800; -- 6 write sites'
  [IO.File]::WriteAllText((Join-Path $ea 'graph.dot'), $dotE, [Text.Encoding]::ASCII)
  Copy-Item (Join-Path $Fix 'graph\hostile.svg') (Join-Path $ea 'graph.svg')
  foreach ($fmt in 'json', 'html') {
    $out = Join-Path $Work "entity.$fmt"
    $r = Invoke-Compare @('compare','--old',$ha,'--new',$ea,'--format',$fmt,'--output',$out)
    $j = $null; if ($fmt -eq 'json' -and (Test-Path $out)) { try { $j = Get-Content $out -Raw | ConvertFrom-Json } catch { } }
    $ok = ($r.Code -in 0, 1) -or ($r.Code -eq 2 -and $r.Err -match '(?m)^ERROR: ' -and ($fmt -ne 'json' -or $j))
    Check "C-ENTITY $fmt not exit 3" ($ok -and $r.Code -ne 3) "exit=$($r.Code) err=$($r.Err)"
  }

  # C-QUOTED / C-EMPTY: a DOT the adapter could not read must never compare as "same"
  $qa = Join-Path $Work 'qa.dot'; $qb = Join-Path $Work 'qb.dot'
  [IO.File]::WriteAllText($qa, "digraph G {`r`n  ""A"" -> ""B"";`r`n}`r`n", [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText($qb, "digraph G {`r`n  ""A"" -> ""C"";`r`n}`r`n", [Text.Encoding]::ASCII)
  $r = Invoke-Compare @('compare','--old',$qa,'--new',$qb)
  Check 'C-QUOTED different quoted-id charts are exit 1' ($r.Code -eq 1) "exit=$($r.Code) out=$($r.Out) err=$($r.Err)"
  $ma = Join-Path $Work 'ma.dot'; $mb = Join-Path $Work 'mb.dot'
  [IO.File]::WriteAllText($ma, "graph G {`r`n  a -- b;`r`n}`r`n", [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText($mb, "graph G {`r`n  c -- d;`r`n}`r`n", [Text.Encoding]::ASCII)
  $r = Invoke-Compare @('compare','--old',$ma,'--new',$mb,'--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-EMPTY unreadable chart refused, exit 2 + envelope' ($r.Code -eq 2 -and $r.Err -match 'parsed as empty' -and $j -and $j.exit_code -eq 2) "exit=$($r.Code) err=$($r.Err)"

  # C-THROW: writing --output into a folder raises; that is a setup error, never the stale exit
  $r = Invoke-Compare @('compare','--old',$ga,'--new',$gb,'--format','json','--output',$Work)
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-THROW exit 2 + ERROR class + envelope' ($r.Code -eq 2 -and $r.Err -match '(?m)^ERROR: E\w+: ' -and $j -and $j.exit_code -eq 2) "exit=$($r.Code) err=$($r.Err) out=$($r.Out)"

  # C-SAVE / C-AUTO
  $snaps = Join-Path $Work 'snaps'
  $r = Invoke-Compare @('compare','--question','who-writes','--target',$Target,'--project',$Proj,'--db',$Db,'--save','--auto','--snapshot-dir',$snaps)
  $auto = @(Get-ChildItem (Join-Path $snaps 'auto') -Filter '*.txt' -ErrorAction SilentlyContinue)
  Check 'C-SAVE exit 0' ($r.Code -eq 0) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-SAVE auto snapshot written' ($auto.Count -eq 1) $r.Out
  Check 'C-SAVE snapshot is the real answer' ($auto.Count -eq 1 -and ([IO.File]::ReadAllText($auto[0].FullName) -match 'TFoo\.Reset @Unit1\.pas'))
  $r = Invoke-Compare @('compare','--auto','--question','who-writes','--target',$Target,'--project',$Proj,'--db',$Db,'--snapshot-dir',$snaps)
  Check 'C-AUTO compares against the snapshot' ($r.Code -eq 0 -and $r.Out -match 'no differences') "exit=$($r.Code) err=$($r.Err) out=$($r.Out)"
  # positive control: Reset stops writing FName, reindex -> the same --auto compare now differs
  Edit-Unit "  FName:= ''; // edited, not reindexed`r`n" ''
  Update-Index
  $r = Invoke-Compare @('compare','--auto','--question','who-writes','--target',$Target,'--project',$Proj,'--db',$Db,'--snapshot-dir',$snaps)
  Check 'C-AUTO a real change since the snapshot -> exit 1' ($r.Code -eq 1 -and $r.Out -match '(?m)^- .*TFoo\.Reset') "exit=$($r.Code) err=$($r.Err) out=$($r.Out)"

  # C-USAGE: every exit 2/3 the verb decides itself still prints the compare/1 envelope in json mode
  $r = Invoke-Compare @('compare','--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-NOCMD json envelope (exit 2 + message)' ($r.Code -eq 2 -and $j -and $j.schema -eq 'compare/1' -and $j.exit_code -eq 2 -and $j.message) "exit=$($r.Code) out=$($r.Out)"
  $r = Invoke-Compare @('compare','--show',(Join-Path $Work 'no-such-file.txt'),'--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-SHOW refusal json envelope' ($r.Code -eq 2 -and $j -and $j.exit_code -eq 2 -and $j.message) "exit=$($r.Code) out=$($r.Out)"
  $r = Invoke-Compare @('compare','--question','who-writes','--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-USAGE --question without --target: json envelope' ($r.Code -eq 2 -and $j -and $j.exit_code -eq 2) "exit=$($r.Code) out=$($r.Out)"
  $r = Invoke-Compare @('compare','--question','who-writes','--target','T','--save','--update-doc','--snapshot-dir',$snaps)
  Check 'C-USAGE snapshot-only refuses --update-doc' ($r.Code -eq 2 -and $r.Err -match 'only takes a snapshot') "exit=$($r.Code) err=$($r.Err)"
  $r = Invoke-Compare @('compare','--question','who-writes','--target','T','--save','--format','json','--snapshot-dir',$snaps)
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-USAGE snapshot-only refuses --format json (envelope)' ($r.Code -eq 2 -and $j -and $j.exit_code -eq 2) "exit=$($r.Code) out=$($r.Out)"
  Check 'C-USAGE --new without --old' ((Invoke-Compare @('compare','--new',$Old)).Code -eq 2)
  Check 'C-USAGE --old-db without a command' ((Invoke-Compare @('compare','--old-db',$Old)).Code -eq 2)
  Check 'C-USAGE --in without --line' ((Invoke-Compare @('compare','--in',$unit)).Code -eq 2)
  # C-HELP
  $r = Invoke-Compare @('compare','--help')
  Check 'C-HELP exit 0 and banner lists the verb' ($r.Code -eq 0 -and $r.Out -match '(?m)^  drag-lint compare ') "exit=$($r.Code)"
}
finally {
  Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { Write-Host 'run_compare_verb: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_compare_verb: PASS' -ForegroundColor Green
exit 0
