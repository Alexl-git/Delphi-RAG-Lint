<#
  run_v156_G46.ps1 -- `ask change-coupling` (1.56 lane G46, gap G-46) on a scratch git repository AND a scratch hg
  repository this runner builds from tests\fixtures\v156\G46 (UA UB UC UD UF; no unit names another).

  Usage: run_v156_G46.ps1 -Exe <drag-lint.exe> [-ExpectRed] [-Scratch <dir>]      (PowerShell 7.3 or later)
    -ExpectRed : the engine is the BASE engine; the question must be refused as "unknown question" (exit != 0).

  History (same in both tools; commit dates 2026-01-01 .. 2026-02-08):
    c1 2026-01-01 add UA UB UC UD UF
    c2 02-01 UA UB     c3 02-02 UA UB     c4 02-03 UA UB UC     c5 02-04 UC UD     c6 02-05 UA
    c7 02-06 UA modified, UF renamed to UG, UD deleted
    c8 02-07 UA UB + 45 text files (mechanical: more than 40 files, skipped)
  Hand-computed with --since c1 (revision, and the date 2026-01-15), indexed units UA UB UC UG:
    counted commits 6, Excluded 1, support A=5 B=3 C=2 G=1, Gone = UD.pas UF.pas (2), Unindexed 0
    weight = 2 * co / (support A + support B)
    --min-support 2 : AB co 3 w 0.75                                   (1 pair)
    --min-support 1 : AB 3 0.75, BC 1 0.40, AG 1 0.33, AC 1 0.29      (4 pairs, in that order)
  No --since (whole history, c1 counted): commits 7; support A=6 B=4 C=3 G=1; min-support 2:
    AB co 4 w 0.80, BC co 2 w 0.57, AC co 2 w 0.44
  POSITIVE CONTROL: one more commit c9 (UA UB) raises exactly AB (since c1, min 2): co 4, supports 6/4, w 0.80;
  and the pair comparer must REJECT the table with one weight changed.
#>
param(
  [Parameter(Mandatory)][string]$Exe,
  [switch]$ExpectRed,
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Scratch) { $Scratch = Join-Path $env:TEMP "g46-run-$PID" }
[IO.Directory]::CreateDirectory($Scratch) | Out-Null
$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}
function Run-Engine([string[]]$a) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } } | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
function Run-Tool([string]$dir, [string]$tool, [string[]]$a) {
  Push-Location -LiteralPath $dir
  try {
    $o = & { $ErrorActionPreference = 'Continue'; & $tool @a 2>&1 | ForEach-Object { "$_" } } | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$tool $($a -join ' ') failed in ${dir}: $o" }
    $o.Trim()
  } finally { Pop-Location }
}

if ($ExpectRed) {
  $r = Run-Engine @('ask', 'change-coupling', '--target', 'project', '--db', (Join-Path $Scratch 'none.sqlite'), '--plain')
  Check 'RED change-coupling refused as unknown question' (($r.Code -ne 0) -and ($r.Text -match 'unknown question')) "exit=$($r.Code) $($r.Text)"
  Write-Host "RED: $script:pass pass, $script:fail fail"; exit $(if ($script:fail) { 1 } else { 0 })
}

$fx = Join-Path $repo 'tests\fixtures\v156\G46'
$days = @{ c1 = '2026-01-01'; c2 = '2026-02-01'; c3 = '2026-02-02'; c4 = '2026-02-03'; c5 = '2026-02-04'; c6 = '2026-02-05'; c7 = '2026-02-06'; c8 = '2026-02-07'; c9 = '2026-02-08' }

function Commit-All([string]$tool, [string]$wc, [string]$name) {
  $stamp = "$($days[$name])T12:00:00"
  if ($tool -eq 'git') {
    Run-Tool $wc git @('add', '-A', '--', '.') | Out-Null
    $env:GIT_AUTHOR_DATE = $stamp; $env:GIT_COMMITTER_DATE = $stamp
    try { Run-Tool $wc git @('commit', '-q', '-m', $name) | Out-Null } finally { Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE }
    Run-Tool $wc git @('rev-parse', 'HEAD')
  } else {
    Run-Tool $wc hg @('addremove', '-q') | Out-Null
    Run-Tool $wc hg @('commit', '-q', '-u', 'g46', '-d', "$($days[$name]) 12:00", '-m', $name) | Out-Null
    Run-Tool $wc hg @('log', '-r', '.', '--template', '{node}')
  }
}
function Touch([string]$wc, [string[]]$units, [string]$tag) {
  foreach ($u in $units) {
    $f = Join-Path $wc "$u.pas"
    [IO.File]::WriteAllText($f, [IO.File]::ReadAllText($f) + "{ $tag }`r`n", [Text.Encoding]::ASCII)
  }
}

function Build-History([string]$tool, [string]$wc, [bool]$withC9) {
  [IO.Directory]::CreateDirectory($wc) | Out-Null
  foreach ($f in Get-ChildItem $fx -Filter *.pas) { Copy-Item $f.FullName $wc -Force }
  if ($tool -eq 'git') {
    Run-Tool $wc git @('init', '-q') | Out-Null
    foreach ($kv in @(@('user.name', 'g46'), @('user.email', 'g46@example.invalid'), @('core.autocrlf', 'false'), @('commit.gpgsign', 'false'))) { Run-Tool $wc git @('config', $kv[0], $kv[1]) | Out-Null }
  } else { Run-Tool $wc hg @('init') | Out-Null }
  $ids = @{}
  $ids.c1 = Commit-All $tool $wc 'c1'
  Touch $wc @('UA', 'UB') 'c2'; $ids.c2 = Commit-All $tool $wc 'c2'
  Touch $wc @('UA', 'UB') 'c3'; $ids.c3 = Commit-All $tool $wc 'c3'
  Touch $wc @('UA', 'UB', 'UC') 'c4'; $ids.c4 = Commit-All $tool $wc 'c4'
  Touch $wc @('UC', 'UD') 'c5'; $ids.c5 = Commit-All $tool $wc 'c5'
  Touch $wc @('UA') 'c6'; $ids.c6 = Commit-All $tool $wc 'c6'
  Touch $wc @('UA') 'c7'
  [IO.File]::Delete((Join-Path $wc 'UD.pas'))
  $uf = [IO.File]::ReadAllText((Join-Path $wc 'UF.pas')).Replace('unit UF;', 'unit UG;').Replace('ProcF', 'ProcG')
  [IO.File]::Delete((Join-Path $wc 'UF.pas'))
  [IO.File]::WriteAllText((Join-Path $wc 'UG.pas'), $uf, [Text.Encoding]::ASCII)
  $ids.c7 = Commit-All $tool $wc 'c7'
  Touch $wc @('UA', 'UB') 'c8'
  $bulk = Join-Path $wc 'bulk'; [IO.Directory]::CreateDirectory($bulk) | Out-Null
  1..45 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $bulk ("f{0:D2}.txt" -f $_)), "x$_`r`n") }
  $ids.c8 = Commit-All $tool $wc 'c8'
  if ($withC9) { Touch $wc @('UA', 'UB') 'c9'; $ids.c9 = Commit-All $tool $wc 'c9' }
  $ids
}

function Ask-Pairs([string]$db, [string]$out, [string[]]$extra) {
  if (Test-Path $out) { [IO.Directory]::Delete($out, $true) }
  $r = Run-Engine (@('ask', 'change-coupling', '--target', 'project', '--db', $db, '--plain', '--out-root', $out) + $extra)
  $csv = Get-ChildItem $out -Recurse -Filter change_coupling_pairs.csv -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  $m = Get-ChildItem $out -Recurse -Filter meta.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  $pairs = @()
  if ($csv) { $pairs = @(Import-Csv $csv.FullName | ForEach-Object { "{0}-{1} co={2} sA={3} sB={4} w={5}" -f $_.unit_a, $_.unit_b, $_.co_changes, $_.support_a, $_.support_b, $_.weight }) }
  $meta = if ($m) { (Get-Content $m.FullName -Raw | ConvertFrom-Json | ForEach-Object { $_ }).emitter } else { $null }
  [pscustomobject]@{ Code = $r.Code; Text = $r.Text; Pairs = $pairs; Meta = $meta }
}
function Same-List($a, $b) { (@($a) -join ';') -ceq (@($b) -join ';') }

foreach ($tool in 'git', 'hg') {
  Write-Host "-- $tool --"
  $root = Join-Path $Scratch $tool
  if (Test-Path $root) { [IO.Directory]::Delete($root, $true) }
  $wc = Join-Path $root 'repo'
  $ids = Build-History $tool $wc $false
  $db = Join-Path $root 'g46.sqlite'
  $ix = Run-Engine @('index', $wc, '--db', $db)
  Check "$tool index" ($ix.Code -eq 0) $ix.Text

  $want2 = @('UA-UB co=3 sA=5 sB=3 w=0.75')
  $want1 = @('UA-UB co=3 sA=5 sB=3 w=0.75', 'UB-UC co=1 sA=3 sB=2 w=0.40', 'UA-UG co=1 sA=5 sB=1 w=0.33', 'UA-UC co=1 sA=5 sB=2 w=0.29')
  $wantAll = @('UA-UB co=4 sA=6 sB=4 w=0.80', 'UB-UC co=2 sA=4 sB=3 w=0.57', 'UA-UC co=2 sA=6 sB=3 w=0.44')

  $a = Ask-Pairs $db (Join-Path $root 'o1') @('--since', $ids.c1)
  Check "$tool since rev, min-support 2: one pair AB w 0.75" ((Same-List $a.Pairs $want2) -and $a.Code -eq 0) "$($a.Pairs -join ' | ') $($a.Text)"
  Check "$tool meta: Commits 6, Excluded 1, Gone 2, Unindexed 0, Units 4, Vcs" ($a.Meta -and $a.Meta.Commits -eq 6 -and $a.Meta.Excluded -eq 1 -and $a.Meta.Gone -eq 2 -and $a.Meta.Unindexed -eq 0 -and $a.Meta.Units -eq 4 -and $a.Meta.Vcs -eq $tool) ($a.Meta | ConvertTo-Json -Compress)
  $a = Ask-Pairs $db (Join-Path $root 'o2') @('--since', '2026-01-15')
  Check "$tool since date 2026-01-15 equals since rev" (Same-List $a.Pairs $want2) ($a.Pairs -join ' | ')
  $a = Ask-Pairs $db (Join-Path $root 'o3') @('--since', $ids.c1, '--min-support', '1')
  Check "$tool min-support 1: four pairs in weight order" ((Same-List $a.Pairs $want1) -and $a.Meta.PairsAll -eq 4) "$($a.Pairs -join ' | ')"
  $a = Ask-Pairs $db (Join-Path $root 'o4') @('--since', $ids.c1, '--min-support', '1', '--cap', '2')
  Check "$tool cap 2 lists the two heaviest" ((Same-List $a.Pairs $want1[0..1]) -and $a.Meta.PairsAll -eq 4) ($a.Pairs -join ' | ')
  $a = Ask-Pairs $db (Join-Path $root 'o5') @()
  Check "$tool whole history: AB 0.80, BC 0.57, AC 0.44, 7 commits" ((Same-List $a.Pairs $wantAll) -and $a.Meta.Commits -eq 7) "$($a.Pairs -join ' | ') $($a.Text)"
  Check "PC-2 the pair comparer rejects one weight changed" (-not (Same-List $a.Pairs @('UA-UB co=4 sA=6 sB=4 w=0.81', $wantAll[1], $wantAll[2])))
  $a = Ask-Pairs $db (Join-Path $root 'o6') @('--since', 'no-such-revision-g46')
  Check "$tool unknown revision is refused with a reason" (($a.Code -ne 0) -and ($a.Text -match 'unknown revision')) "exit=$($a.Code) $($a.Text)"
  $a = Ask-Pairs $db (Join-Path $root 'o7') @('--min-support', '0')
  Check "$tool --min-support 0 is refused" ($a.Code -ne 0) $a.Text

  # POSITIVE CONTROL: one more commit raises exactly the AB weight
  $root2 = Join-Path $Scratch "$tool-pc"
  if (Test-Path $root2) { [IO.Directory]::Delete($root2, $true) }
  $wc2 = Join-Path $root2 'repo'
  $ids2 = Build-History $tool $wc2 $true
  $db2 = Join-Path $root2 'g46.sqlite'
  $ix = Run-Engine @('index', $wc2, '--db', $db2)
  $a = Ask-Pairs $db2 (Join-Path $root2 'o1') @('--since', $ids2.c1)
  Check "PC-1 $tool one more AB commit: co 4, supports 6/4, w 0.80 (was 0.75)" (Same-List $a.Pairs @('UA-UB co=4 sA=6 sB=4 w=0.80')) ($a.Pairs -join ' | ')
}

Write-Host "G46: $script:pass pass, $script:fail fail"
exit $(if ($script:fail) { 1 } else { 0 })