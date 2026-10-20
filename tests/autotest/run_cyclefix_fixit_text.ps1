<#
  run_cyclefix_fixit_text.ps1 -- E18 Task 13: the `Fix it` block of `cycles --plan` and the `fix` object of
  `cycles --format json --causes`.

  Asserts, on a COPY of circular-demo (library DB: a copy, never the real one):
    (a) `cycles --plan --project <copy>\CircularDemo.dproj` ends every cycle with a block
        `Fix it (mechanical, compile-gated):` with the dry-run and apply commands naming `--cycle N`
        and the project, one `cuts` line per cuttable edge (the chosen one first, marked), a
        `requires` line. Cycle 1 (Part A) names its Part B follow-up `demoaudit -> democonfig (move
        globals)`; cycle 2 names `member hand-over`; cycle 3 names `routine-call inversion`.
    (b) without --project the commands carry `--project <your.dproj>`.
    (c) `--format json --causes` carries fix.available = true for all three, both commands, the
        chosen edge first with recipe ids, and followup on the Part A cycle.
    (d) AGREEMENT: for cycle 2 and 3 a `--fix --cycle N` dry run plans the SAME edge the block marks
        chosen.
    (e) POSITIVE CONTROLS: tests\fixtures\cyclefix\nocut (a construction on both edges) prints
        `Fix it: not available -- construction` and fix.available = false; the demo with
        `--library-db none` (cycle 2's member hand-over needs the library) prints `not available`
        for cycle 2 only -- the block follows the planner, not a constant.
    (f) the runs write NOTHING: SHA-256 of every file of the copies and their index DBs is the same
        before and after; the real library DBs keep size + mtime.

  Without the platform library on disk the checks that need it are SKIPped. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-fixit-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
# E18 T13: removes this run's scratch (WorkDir) however the run ends; kept only on failure when
# -KeepScratch is passed (the path is printed).
function Remove-Scratch {
  if ($script:Failed -and $KeepScratch) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow; return }
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
trap { $script:Failed = $true; Remove-Scratch; break }

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}
function Get-TreeHash([string]$Dir, [string]$Db) {
  $files = @(Get-ChildItem $Dir -File -Recurse) + @(Get-Item $Db)
  return (($files | Sort-Object FullName | ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Index-Copy([string]$Dir, [string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $idx = & $Exe index --project (Join-Path $Dir $Dproj) --db $db 2>&1 | Out-String
  Check "${Tag}: SANITY the copy indexed with 0 errors" (($idx -match ', 0 errors') -and ($idx -notmatch '[1-9]\d* errors')) $idx
  return $db
}
# `cycles <args>` -> stdout text (stderr dropped)
function Run-Cycles([string[]]$A) { return (& $Exe cycles @A 2>$null | Out-String) }
# The text of cycle N of a --plan output (from its `## Cycle N` heading to the next one).
function Cycle-Text([string]$Plan, [int]$N) {
  $m = [regex]::Match($Plan, "(?ms)^## Cycle $N`:.*?(?=^## Cycle \d+`:|\z)")
  return $m.Value
}
function Fix-Block([string]$Cycle) {
  $m = [regex]::Match($Cycle, '(?ms)^Fix it( \(mechanical.*?|: not available.*?)(?=\r?\n\r?\n|\z)')
  return $m.Value
}

$stampBefore = Get-LibStamp
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$haveLib = Test-Path $LibraryDb
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
Push-Location $WorkDir
try {
  if ($haveLib) { Copy-Item $LibraryDb $Lib -Force } else { $Lib = 'none' }
  $demo = Join-Path $WorkDir 'demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demo
  $db = Index-Copy $demo 'CircularDemo.dproj' 'demo'
  $proj = Join-Path $demo 'CircularDemo.dproj'
  $nocut = Join-Path $WorkDir 'nocut'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\nocut') $nocut
  $ndb = Index-Copy $nocut 'NoCut.dproj' 'nocut'
  $nproj = Join-Path $nocut 'NoCut.dproj'
  $hashBefore = (Get-TreeHash $demo $db) + '|' + (Get-TreeHash $nocut $ndb)

  Write-Host '== (a) the text, with --project' -ForegroundColor Cyan
  $plan = Run-Cycles @('--plan', '--project', $proj, '--db', $db, '--library-db', $Lib)
  $c1 = Cycle-Text $plan 1; $c2 = Cycle-Text $plan 2; $c3 = Cycle-Text $plan 3
  Check 'a0: SANITY three cycles in the plan' ($c1 -and $c2 -and $c3) ($plan.Substring(0, [Math]::Min(400, $plan.Length)))
  $b1 = Fix-Block $c1; $b2 = Fix-Block $c2; $b3 = Fix-Block $c3
  foreach ($p in @(@(1, $b1), @(2, $b2), @(3, $b3))) {
    $n = $p[0]; $b = $p[1]
    if ($n -eq 2 -and -not $haveLib) { Write-Host '  [SKIP] cycle 2 needs the platform library (member hand-over)'; continue }
    Check "a$n`: block header" ($b -match '^Fix it \(mechanical, compile-gated\):') $b
    Check "a$n`: dry-run command names --cycle $n and the project" `
      ($b -match ('(?m)^  dry run : drag-lint cycles --fix --project "' + [regex]::Escape($proj) + '" --db "' + [regex]::Escape($db) + '" --cycle ' + $n + '\s*$')) $b
    Check "a$n`: apply command is the dry run plus --apply" `
      ($b -match ('(?m)^  apply   : drag-lint cycles --fix --project "' + [regex]::Escape($proj) + '" --db "' + [regex]::Escape($db) + '" --cycle ' + $n + ' --apply\s*$')) $b
    Check "a$n`: requires line" ($b -match '(?m)^  requires: the project builds with 0 errors before the fix \(the dry run checks this\)\s*$') $b
  }
  Check 'a1: Part A cuts line + Part B follow-up `demoaudit -> democonfig (move globals)`' `
    ($b1 -match '(?m)^  cuts    : the INTERFACE coupling' -and $b1 -match 'demoaudit -> democonfig \(move globals\)') $b1
  if ($haveLib) {
    Check 'a2: cuts line names demouiconnect -> demogageport, member hand-over, (chosen)' `
      ($b2 -match '(?m)^  cuts    : demouiconnect -> demogageport \(member hand-over through an extracted interface\) \(chosen\)\s*$') $b2
  }
  Check 'a3: cuts line names routine-call inversion, (chosen)' `
    ($b3 -match '(?m)^  cuts    : demoblueprint -> demoblueprint\.viewmodel \(routine-call inversion\) \(chosen\)\s*$') $b3
  Check 'a5: exactly ONE Fix it block per cycle' `
    ((([regex]::Matches($c1, '(?m)^Fix it')).Count -eq 1) -and (([regex]::Matches($c2, '(?m)^Fix it')).Count -eq 1) -and (([regex]::Matches($c3, '(?m)^Fix it')).Count -eq 1)) `
    ("{0}/{1}/{2}" -f ([regex]::Matches($c1, '(?m)^Fix it')).Count, ([regex]::Matches($c2, '(?m)^Fix it')).Count, ([regex]::Matches($c3, '(?m)^Fix it')).Count)
  Check 'a4: the block is last in its cycle (nothing after it but the next heading)' `
    ($b2 -ne '' -and $c2.TrimEnd().EndsWith($b2.TrimEnd())) ($c2.Substring([Math]::Max(0, $c2.Length - 300)))

  Write-Host '== (b) the text, without --project' -ForegroundColor Cyan
  $plan2 = Run-Cycles @('--plan', '--db', $db, '--library-db', $Lib)
  Check 'b1: dry run carries `--project <your.dproj>` (unquoted placeholder)' `
    ($plan2 -match '(?m)^  dry run : drag-lint cycles --fix --project <your\.dproj> --db "[^"]+" --cycle 1\s*$') ''
  Check 'b2: apply carries `--project <your.dproj>` too' ($plan2 -match '--project <your\.dproj> --db "[^"]+" --cycle 3 --apply') ''

  Write-Host '== (c) JSON --causes' -ForegroundColor Cyan
  $jt = Run-Cycles @('--format', 'json', '--causes', '--project', $proj, '--db', $db, '--library-db', $Lib)
  $j = try { $jt | ConvertFrom-Json } catch { $null }
  Check 'c0: SANITY three groups, each with a fix object' ($j -and @($j).Count -eq 3 -and @($j | Where-Object { $null -ne $_.fix }).Count -eq 3) $jt
  if ($j -and @($j).Count -eq 3) {
    $g = @($j)
    Check 'c1: fix.available = true for cycle 1 and 3' ($g[0].fix.available -eq $true -and $g[2].fix.available -eq $true) ($g | ConvertTo-Json -Depth 6 -Compress)
    if ($haveLib) { Check 'c2: fix.available = true for cycle 2' ($g[1].fix.available -eq $true) ($g[1].fix | ConvertTo-Json -Compress) }
    Check 'c3: dry_run and apply are the two commands' `
      ($g[2].fix.dry_run -eq "drag-lint cycles --fix --project `"$proj`" --db `"$db`" --cycle 3" -and $g[2].fix.apply -eq "$($g[2].fix.dry_run) --apply") ($g[2].fix | ConvertTo-Json -Compress)
    Check 'c4: cycle 3 edges[0] is the chosen routine-inversion edge' `
      (@($g[2].fix.edges)[0].from -eq 'demoblueprint' -and @($g[2].fix.edges)[0].to -eq 'demoblueprint.viewmodel' -and @($g[2].fix.edges)[0].recipe -eq 'routine-inversion' -and @($g[2].fix.edges)[0].chosen -eq $true) ($g[2].fix | ConvertTo-Json -Compress)
    Check 'c5: cycle 1 (Part A) has part a, no edges, a followup demoaudit -> democonfig move-globals' `
      ($g[0].fix.part -eq 'a' -and @($g[0].fix.edges).Count -eq 0 -and $g[0].fix.followup.from -eq 'demoaudit' -and $g[0].fix.followup.to -eq 'democonfig' -and $g[0].fix.followup.recipe -eq 'move-globals') ($g[0].fix | ConvertTo-Json -Compress)
    Check 'c6: reason is empty when available' ($g[2].fix.reason -eq '') ''
    $jn = (Run-Cycles @('--format', 'json', '--causes', '--db', $db, '--library-db', $Lib)) | ConvertFrom-Json
    Check 'c7: without --project the JSON commands carry --project <your.dproj>' `
      ($jn -and $jn[2].fix.dry_run -like '*--project <your.dproj> --db *') ''

    # a library that cannot be opened: the rest of the --causes output is unchanged, the fix objects say why
  $jbad = (& $Exe cycles --format json --causes --project $proj --db $db --library-db (Join-Path $WorkDir 'no-such-library.sqlite') 2>$null | Out-String) | ConvertFrom-Json
  Check 'c8: missing --library-db: exit 0 path, JSON still parses with 3 groups' ($jbad -and @($jbad).Count -eq 3) ''
  Check 'c8: every fix has available=false and reason `library unavailable: library database not found: <path>`' `
    ($jbad -and @($jbad | Where-Object { $_.fix.available -eq $false -and $_.fix.reason -like 'library unavailable: library database not found: *no-such-library.sqlite' }).Count -eq 3) (($jbad | ConvertTo-Json -Depth 5 -Compress))
  Check 'c8: the commands are still there and the groups/edges are unchanged' `
    ($jbad -and $jbad[1].fix.dry_run -like '*--cycle 2' -and (($jbad | ForEach-Object { $_.units -join ',' }) -join ';') -eq (($g | ForEach-Object { $_.units -join ',' }) -join ';') -and @($jbad[2].edges).Count -eq @($g[2].edges).Count -and @($jbad[2].edges).Count -gt 0) ''

  Write-Host '== (d) agreement with the --fix dry run' -ForegroundColor Cyan
    foreach ($n in 2, 3) {
      if ($n -eq 2 -and -not $haveLib) { continue }
      $fx = (& $Exe cycles --fix --project $proj --db $db --cycle $n --no-compile --library-db $Lib --format json 2>$null | Out-String) | ConvertFrom-Json
      $ch = @($g[$n - 1].fix.edges | Where-Object { $_.chosen })[0]
      Check "d$n`: --fix --cycle $n plans the edge the block marks chosen ($($ch.from)->$($ch.to))" `
        ($fx -and $fx.cycles[0].verdict -eq 'mechanical' -and $ch -and $fx.cycles[0].edge -eq "$($ch.from)->$($ch.to)" -and $fx.cycles[0].recipe -eq $ch.recipe) ($fx.cycles[0] | ConvertTo-Json -Depth 3 -Compress)
    }
  }

  Write-Host '== (e) positive controls' -ForegroundColor Cyan
  $nplan = Run-Cycles @('--plan', '--project', $nproj, '--db', $ndb, '--library-db', 'none')
  Check 'e1: nocut text: `Fix it: not available -- construction`' ($nplan -match '(?m)^Fix it: not available -- construction') $nplan
  Check 'e2: nocut text has no dry-run line' ($nplan -notmatch 'dry run :') ''
  $nj = (Run-Cycles @('--format', 'json', '--causes', '--project', $nproj, '--db', $ndb, '--library-db', 'none')) | ConvertFrom-Json
  Check 'e3: nocut JSON fix.available = false, reason starts with construction' `
    ($nj -and $nj[0].fix.available -eq $false -and $nj[0].fix.reason -like 'construction*') ($nj | ConvertTo-Json -Depth 6 -Compress)
  Check 'e4: nocut JSON still carries both commands' ($nj -and $nj[0].fix.dry_run -like '*--cycle 1' -and $nj[0].fix.apply -like '*--cycle 1 --apply') ''
  $noLib = Run-Cycles @('--plan', '--project', $proj, '--db', $db, '--library-db', 'none')
  Check 'e5: demo without the library: cycle 2 is `not available`, cycles 1 and 3 still offer the fix' `
    ((Fix-Block (Cycle-Text $noLib 2)) -match '^Fix it: not available -- ' -and (Fix-Block (Cycle-Text $noLib 1)) -match '^Fix it \(mechanical' -and (Fix-Block (Cycle-Text $noLib 3)) -match '^Fix it \(mechanical') (Fix-Block (Cycle-Text $noLib 2))

  Write-Host '== (f) nothing written' -ForegroundColor Cyan
  Check 'f1: the copies and their index DBs are byte-identical after every run' `
    ((Get-TreeHash $demo $db) + '|' + (Get-TreeHash $nocut $ndb) -eq $hashBefore) ''
} finally {
  Pop-Location
  Remove-Scratch
}
Check 'z1: the real library DBs are unchanged (size + mtime)' ((Get-LibStamp) -eq $stampBefore) ''

Write-Host ("{0} PASS" -f $script:Passed)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
