<#
  run_compare_verb.ps1 -- `drag-lint compare` end to end, against a STUB report producer.

  The verb reruns a saved report's COMMAND through charts\src\Ask-Report.ps1 -Plain and diffs
  the normalised text. Here DRAGLINT_ASK_REPORT points at
  tests\charts\fixtures\producer\Stub-AskReport.ps1, which prints the same SHAPE as the real
  script (header sentence, COMMAND, BUNDLE, INDEX, body) without touching an index, so every
  exit code and output format can be pinned deterministically:

    C-SAME      same answer          -> exit 0, "result: no differences"
    C-DIFF      STUB_VARIANT=B       -> exit 1, exactly one added row
    C-JSON      --format json        -> parses, schema compare/1, exit_code 1
    C-HTML      --format html        -> file written, light/dark CSS, path printed
    C-NOCMD     no source at all     -> exit 2 + usage on stderr
    C-NOCMD2    legacy old, no --command -> exit 2 naming --command
    C-WARN      legacy old + --command   -> WARNING line first
    C-STALE     stub says stale      -> exit 3, ERROR on stderr, JSON envelope still parses
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
$Stub = Join-Path $Fix 'producer\Stub-AskReport.ps1'
$Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $Pwsh) { Skip 'all' 'pwsh 7 not on PATH'; exit 0 }
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-compare-verb-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Work | Out-Null

# Runs the engine; returns .Code .Out .Err. Environment overrides ride along.
function Invoke-Compare([string[]]$ArgList, [hashtable]$Env = @{}) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $psi.Environment['DRAGLINT_ASK_REPORT'] = $Stub
  foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string]$Env[$k] }
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
# The old report: the stub's own plain answer, kept as a file (UTF-8, no BOM).
function New-OldReport([string]$Path, [string]$Question, [string]$Target, [string]$Project) {
  $txt = & $Pwsh -NoProfile -File $Stub -Question $Question -Target $Target -Project $Project -Plain -AllowStale | Out-String
  [IO.File]::WriteAllText($Path, $txt, [Text.UTF8Encoding]::new($false))
}

try {
  $Proj = 'C:\P\A.dproj'
  $Old  = Join-Path $Work 'old.txt'
  New-OldReport $Old 'who-writes' 'Unit1.TFoo.Name' $Proj

  # C-SAME
  $r = Invoke-Compare @('compare','--old',$Old)
  Check 'C-SAME exit 0' ($r.Code -eq 0) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-SAME says no differences' ($r.Out -match 'result: no differences') $r.Out

  # C-DIFF
  $r = Invoke-Compare @('compare','--old',$Old) @{ STUB_VARIANT = 'B' }
  $adds = @($r.Out -split "`r?`n" | Where-Object { $_ -match '^\+ ' })
  Check 'C-DIFF exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-DIFF one added row' ($adds.Count -eq 1 -and $adds[0] -match 'Reset') ($adds -join '|')

  # C-JSON
  $r = Invoke-Compare @('compare','--old',$Old,'--format','json') @{ STUB_VARIANT = 'B' }
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-JSON parses' ($null -ne $j) $r.Out
  Check 'C-JSON schema compare/1' ($j -and $j.schema -eq 'compare/1')
  Check 'C-JSON exit_code 1' ($j -and $j.exit_code -eq 1 -and $r.Code -eq 1) "exit=$($r.Code)"

  # C-HTML
  $html = Join-Path $Work 'out.html'
  $r = Invoke-Compare @('compare','--old',$Old,'--format','html','--output',$html) @{ STUB_VARIANT = 'B' }
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
  $r = Invoke-Compare @('compare','--old',$legacy,'--command','who-writes -Target "Unit1.TFoo.Name" -Project "C:\P\A.dproj"')
  $first = ($r.Out -split "`r?`n")[0]
  Check 'C-WARN WARNING line first' ($first -match '^WARNING: .*original command is unknown') "first=[$first] exit=$($r.Code) err=$($r.Err)"

  # C-STALE
  $stale = Join-Path $Work 'stale.txt'
  New-OldReport $stale 'who-writes' 'Unit1.TFoo.Name' 'C:\P\stale.dproj'
  $r = Invoke-Compare @('compare','--old',$stale)
  Check 'C-STALE exit 3' ($r.Code -eq 3) "exit=$($r.Code)"
  Check 'C-STALE ERROR on stderr' ($r.Err -match '(?m)^ERROR: ') $r.Err
  $r = Invoke-Compare @('compare','--old',$stale,'--format','json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'C-STALE json envelope parses' ($r.Code -eq 3 -and $j -and $j.exit_code -eq 3 -and $j.message) "exit=$($r.Code) out=$($r.Out)"

  # C-REMARKS
  $unit = Join-Path $Work 'TwoBlocks.pas'
  Copy-Item (Join-Path $Fix 'remarks\TwoBlocks.pas') $unit
  $before = [IO.File]::ReadAllLines($unit)
  $line2  = 1 + [array]::FindIndex($before, [Predicate[string]]{ param($s) $s -like '*COMMAND who-calls*' })
  $r = Invoke-Compare @('compare','--in',$unit,'--line',"$line2",'--update-doc')
  $after = [IO.File]::ReadAllLines($unit)
  Check 'C-REMARKS exit 1' ($r.Code -eq 1) "exit=$($r.Code) err=$($r.Err) out=$($r.Out)"
  Check 'C-REMARKS block 1 identical' (($before[0..($line2 - 6)] -join "`n") -eq ($after[0..($line2 - 6)] -join "`n"))
  Check 'C-REMARKS block 2 rewritten' (($after -join "`n") -match 'Unit1\.TFoo\.SetName' -and ($after -join "`n") -notmatch 'TFoo\.Bar \(Foo\.pas:10\)\s*\r?\n\s*/// </remarks>\s*\r?\n\s*procedure Two')
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
  $r = Invoke-Compare @('compare','--question','who-writes','--target','Unit1.TFoo.Name','--project',$Proj,'--save','--auto','--snapshot-dir',$snaps)
  $auto = @(Get-ChildItem (Join-Path $snaps 'auto') -Filter '*.txt' -ErrorAction SilentlyContinue)
  Check 'C-SAVE exit 0' ($r.Code -eq 0) "exit=$($r.Code) err=$($r.Err)"
  Check 'C-SAVE auto snapshot written' ($auto.Count -eq 1) $r.Out
  $r = Invoke-Compare @('compare','--auto','--question','who-writes','--target','Unit1.TFoo.Name','--project',$Proj,'--snapshot-dir',$snaps)
  Check 'C-AUTO compares against the snapshot' ($r.Code -eq 0 -and $r.Out -match 'no differences') "exit=$($r.Code) err=$($r.Err) out=$($r.Out)"

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
