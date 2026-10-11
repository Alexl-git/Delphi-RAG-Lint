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
