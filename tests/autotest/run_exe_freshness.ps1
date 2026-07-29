<#
  run_exe_freshness.ps1 -- the battery must test the binary the build produces.
  Register item E8, generalised by T3k.

  Why this exists
  ---------------
  tests\autotest\run_formsmap.ps1 and tests\autotest\run_wiring.ps1 defaulted to
  $Exe = "$PSScriptRoot\..\..\src\cli\Win32\Debug\drag-lint.exe"
  build\build_draglint_win64.bat -- the canonical build -- never refreshes that
  file, so for weeks those two runners ran a hand-built binary from 2026-07-27
  14:01 while every other runner ran the branch head. They were GREEN the whole
  time. Not failing: NOT MEASURING.

  That is strictly worse than a red. It manufactured a confident false finding:
  T3i mutated FormsMap's query, rebuilt Win64, watched run_formsmap stay green,
  and concluded the check could not fail -- filed as register item E6, later
  disproved by data-level reproduction. Four consecutive "zero-red battery"
  claims were really "186 measured, 2 unmeasured".

  Both runners were retargeted. This runner exists because THE NEXT ONE WOULD NOT
  ANNOUNCE ITSELF EITHER: the only reason those two were ever found is that one of
  them produced a visible contradiction.

  Check 1 -- every exe any runner resolves must exist and be current
    NOT a blacklist. The first version of this runner checked two forbidden path
    fragments (Win32\Debug, dll-win32) and validated freshness on two hardcoded
    Win64 paths -- so a runner defaulting to src\cli\Win32\Release\ or
    src\cli\Win64\Release\ would have passed both while being exactly as stale as
    E8, which is precisely the failure this file claims to prevent. A blacklist
    cannot deliver "caught by the battery instead of by luck"; it only ever
    catches the shapes someone already thought of.
    So: parse every run_*.ps1, extract every drag-lint.exe path it actually
    resolves, and assert freshness on each one that exists. Whatever a runner
    points at, that is what gets checked.

  Check 2 -- the canonical build outputs must exist and be current
    src\cli\Win64\Debug\drag-lint.exe (the build output) and
    third_party\dll-win64\drag-lint.exe (the staged copy). Both are refreshed by
    build_draglint_win64.bat; a runner naming neither is still covered by Check 1.

  "Current" means: not older than the newest file in the CLI's own source set,
  which is READ FROM src\cli\drag-lint.dproj's DCC_UnitSearchPath rather than
  hardcoded here -- a hardcoded directory list is exactly the kind of copy that
  goes stale. One declaration, read by the compiler and by this check. Every
  <DCC_UnitSearchPath> block is read, not the first (register K5): a .dproj
  carries one per build configuration.

  Three things this file asserts that nothing in tests\ can currently exercise,
  and why they are self-tests rather than surveys (Task 4f)
    K5  the real .dproj has exactly ONE configuration block, so it cannot tell a
        first-match parse from a union parse. A synthetic two-block document can,
        and does.
    K11 no line in tests\ puts a `#` inside a string literal ahead of an exe
        literal -- and that is precisely the state in which a regression would
        remove coverage with nothing to see. Three synthetic lines pin the rule
        in both directions.
    K10 a BARE relative literal is CWD-relative, so resolving it against the repo
        root is only right while the driver runs runners from there. That is now
        asserted against run_battery.ps1's own -WorkingDirectory rather than
        assumed.

  On Win32, and on register item E3
    Whether the Win32 CLI stays a supported artifact is E3, an open USER
    decision, and this runner does not decide it. It needs no special case:
    nothing builds a Win32 CLI today, so any Win32 exe a runner names is
    automatically older than the source and Check 1 fails on it for the true
    reason -- it is stale -- rather than because its path matched a list. If E3
    is answered "supported", add a Win32 build step and this check starts
    passing on its own.

  Comment handling, and why this file is its own test case
    A path mention inside a comment must not count as a default. The first
    version excluded only `^\s*#`, which does NOT cover BLOCK comments (the
    angle-hash form this header is written in) -- and the header above sits in
    exactly such a block. That line escaped only because it happened
    to contain no `=`, while the comment claiming the mechanism worked was
    describing a mechanism that did not cover the very mention it pointed at.
    Block comments are now tracked properly, and the "Why this exists" paragraph
    above deliberately writes that stale Win32 path as a QUOTED literal -- the
    exact shape the extractor looks for. So if block-comment tracking ever
    regresses, THIS FILE is the first thing the guard reports, and it reports a
    path that genuinely exists and is genuinely stale. A self-test beats a
    promise. Verified by disabling the block-comment branch and watching this
    runner name itself.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_exe_freshness.ps1
#>
[CmdletBinding()]
param(
  [string] $Repo = "$PSScriptRoot\..\.."
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

$Repo = (Resolve-Path $Repo).Path
Write-Host '== exe freshness (E8) ==' -ForegroundColor Cyan

# --- the newest source file the CLI is built from --------------------------
$dproj = Join-Path $Repo 'src\cli\drag-lint.dproj'
Check 'CLI .dproj present' (Test-Path $dproj) $dproj

# K5 -- a .dproj carries ONE <DCC_UnitSearchPath> PER BUILD CONFIGURATION, and
# this used to read only the FIRST match. A path present only in a later
# configuration block was invisible, so the "newest source file" could be
# computed over a silently smaller set and understate itself. Now the UNION of
# every block, de-duplicated in first-seen order.
#
# src\cli\drag-lint.dproj carries exactly ONE block today (23 entries), so the
# real .dproj cannot discriminate the two versions -- which is why the fix ships
# with the SELF-TEST below over a synthetic two-configuration document rather
# than with a claim. Revert this to [regex]::Match and that check goes red.
function Get-DprojSearchPathEntries([string]$Text) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($Text, '<DCC_UnitSearchPath>(.*?)</DCC_UnitSearchPath>', 'Singleline')) {
    foreach ($p in ($m.Groups[1].Value -split ';')) {
      $t = $p.Trim()
      if ($t -ne '' -and -not $out.Contains($t)) { $out.Add($t) }
    }
  }
  return $out
}

$k5Probe = '<Project>' +
  '<PropertyGroup Condition="Debug"><DCC_UnitSearchPath>..\alpha;..\shared</DCC_UnitSearchPath></PropertyGroup>' +
  '<PropertyGroup Condition="Release"><DCC_UnitSearchPath>..\shared;..\only_in_release</DCC_UnitSearchPath></PropertyGroup>' +
  '</Project>'
$k5 = @(Get-DprojSearchPathEntries $k5Probe)
Check 'search-path parse reads EVERY build configuration, not just the first (K5)' `
  (($k5 -contains '..\only_in_release') -and ($k5.Count -eq 3)) "(got: $($k5 -join ' '))"

$srcDirs = New-Object System.Collections.Generic.List[string]
$dprojBlocks = 0
if (Test-Path $dproj) {
  $cliDir = Split-Path $dproj -Parent
  $srcDirs.Add($cliDir)
  $dprojText = Get-Content $dproj -Raw
  $dprojBlocks = [regex]::Matches($dprojText, '<DCC_UnitSearchPath>', 'Singleline').Count
  foreach ($t in (Get-DprojSearchPathEntries $dprojText)) {
    if ($t.StartsWith('$(')) { continue }
    $full = Join-Path $cliDir $t
    if (Test-Path $full) {
      $r = (Resolve-Path $full).Path
      if (-not $srcDirs.Contains($r)) { $srcDirs.Add($r) }
    }
  }
}
Check 'source dirs read from the .dproj search path' ($srcDirs.Count -gt 1) `
  "($($srcDirs.Count) dirs, from $dprojBlocks DCC_UnitSearchPath block(s))"

$newest = $null
foreach ($d in $srcDirs) {
  Get-ChildItem -LiteralPath $d -File -Include *.pas, *.inc, *.dpr, *.dproj -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    if ($null -eq $newest -or $_.LastWriteTime -gt $newest.LastWriteTime) { $newest = $_ }
  }
}
Check 'newest source file located' ($null -ne $newest)
if ($null -ne $newest) {
  Write-Host ("        newest source : {0}  {1}" -f
    $newest.FullName.Substring($Repo.Length + 1), $newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
}

# --- enumerate every exe any runner actually resolves ----------------------
# Strips <# block #> and # line comments first, then takes every quoted literal
# ending in <sep>drag-lint.exe. The separator requirement drops a bare
# 'drag-lint.exe' filename (run_smoke builds one for a copy destination), which
# names no location and cannot be a stale target.
#
# K11 -- `#` only starts a comment OUTSIDE a string literal. This used to cut the
# line at the first `#` unconditionally, so `$Tag = "rc#1"; $Exe = "...\drag-lint.exe"`
# would have dropped the exe literal and that site would have gone unchecked with
# no sign. There is no such line in tests\ today, which is exactly why the
# requirement is asserted by the self-test below instead of by a survey: a
# regression here removes coverage silently, and "no instance today" is the
# condition under which nobody would notice.
#
# LIMIT, stated rather than implied: this is a scanner, not a PowerShell parser.
# It tracks single and double quotes only; a `#` inside a here-string, or a
# doubled '' escape, can still confuse it. It is strictly better than cutting at
# the first `#`, and it is not a lexer.
function Remove-PsLineComment([string]$Code) {
  $inS = $false; $inD = $false
  for ($i = 0; $i -lt $Code.Length; $i++) {
    $c = $Code[$i]
    if ($c -eq "'" -and -not $inD) { $inS = -not $inS; continue }
    if ($c -eq '"' -and -not $inS) { $inD = -not $inD; continue }
    if ($c -eq '#' -and -not $inS -and -not $inD) { return $Code.Substring(0, $i) }
  }
  return $Code
}

function Get-ExeLiteralsFromLines([string[]]$Lines) {
  $out = New-Object System.Collections.Generic.List[object]
  $inBlock = $false
  $n = 0
  foreach ($line in $Lines) {
    $n++
    $code = $line
    if ($inBlock) {
      $end = $code.IndexOf('#>')
      if ($end -lt 0) { continue }
      $code = $code.Substring($end + 2); $inBlock = $false
    }
    $start = $code.IndexOf('<#')
    if ($start -ge 0) {
      $rest = $code.Substring($start)
      $end = $rest.IndexOf('#>')
      if ($end -lt 0) { $code = $code.Substring(0, $start); $inBlock = $true }
      else { $code = $code.Substring(0, $start) + $rest.Substring($end + 2) }
    }
    $code = Remove-PsLineComment $code
    if ($code.Trim() -eq '') { continue }
    foreach ($mm in [regex]::Matches($code, '["'']([^"'']*[\\/]drag-lint\.exe)["'']', 'IgnoreCase')) {
      $out.Add([pscustomobject]@{ Line = $n; Literal = $mm.Groups[1].Value })
    }
  }
  return $out
}

function Get-ExeLiterals([string]$Path) {
  return Get-ExeLiteralsFromLines ([System.IO.File]::ReadAllLines($Path))
}

# K11 self-test. Three probe lines, one requirement each: a `#` inside a string
# must not hide a following literal; a real trailing comment must still be
# stripped; and code before a trailing comment must still count.
#
# THE PROBE STRINGS ARE ASSEMBLED, NOT WRITTEN. This file is itself inside the
# scanned population, so a quoted `...\drag-lint.exe` on a CODE line here would
# be extracted as a genuine target and the guard would fail on its own fixtures
# -- which is exactly what the first version of this self-test did. Splitting the
# filename keeps the source free of the shape the extractor looks for while the
# probe still carries it at run time. (The header's block-comment self-test is
# deliberately the opposite: there the literal IS written out, because a comment
# is precisely where it must not count.)
$EXE_ = 'drag' + '-lint.exe'
$k11Keep = @(Get-ExeLiteralsFromLines @(('$Tag = "rc#1"; $Exe = "..\..\third_party\dll-win64\{0}"' -f $EXE_)))
$k11Drop = @(Get-ExeLiteralsFromLines @(('$X = 1   # see ..\..\src\cli\Win32\Debug\{0}' -f $EXE_)))
$k11Half = @(Get-ExeLiteralsFromLines @(('$Exe = "..\..\a\{0}"  # not "..\..\b\{0}"' -f $EXE_)))
Check 'a # inside a STRING LITERAL does not hide a following exe literal (K11)' `
  (($k11Keep.Count -eq 1) -and ($k11Keep[0].Literal -eq ('..\..\third_party\dll-win64\' + $EXE_))) `
  "(got $($k11Keep.Count): $(($k11Keep | ForEach-Object { $_.Literal }) -join ', '))"
Check 'a # that really does start a comment still hides the rest of the line (K11)' `
  ($k11Drop.Count -eq 0) "(got $($k11Drop.Count))"
Check 'code before a trailing comment counts, the comment after it does not (K11)' `
  (($k11Half.Count -eq 1) -and ($k11Half[0].Literal -eq ('..\..\a\' + $EXE_))) `
  "(got $($k11Half.Count): $(($k11Half | ForEach-Object { $_.Literal }) -join ', '))"

# K10 -- a BARE RELATIVE literal ('src\cli\Win64\Debug\drag-lint.exe', no
# $PSScriptRoot and no leading '..') is CWD-relative at run time, not
# runner-relative and not repo-relative. Resolving it against $Repo is therefore
# correct only while the process CWD IS the repo root. That is not an accident
# to be relied on quietly: it is a REQUIREMENT of the battery, and it is
# asserted below against tests\run_battery.ps1's own -WorkingDirectory, so the
# day the driver stops supplying it this guard reddens instead of resolving
# 17 sites against a base nothing guarantees.
$script:BareRelativeSites = 0
function Resolve-ExeLiteral([string]$Literal, [string]$RunnerDir) {
  $s = $Literal
  if ($s.StartsWith('$PSScriptRoot')) { $s = $s.Substring('$PSScriptRoot'.Length).TrimStart('\', '/'); $base = $RunnerDir }
  elseif ($s.StartsWith('..'))        { $base = $RunnerDir }
  elseif ([IO.Path]::IsPathRooted($s)) { return [IO.Path]::GetFullPath($s) }
  else                                 { $base = $Repo; $script:BareRelativeSites++ }
  if ($s -match '\$') { return $null }   # any other variable: cannot resolve statically
  return [IO.Path]::GetFullPath((Join-Path $base $s))
}

$testsRoot = Join-Path $Repo 'tests'
$runners = @(Get-ChildItem -LiteralPath $testsRoot -Recurse -Filter 'run_*.ps1' -File)
Check 'runners enumerated' ($runners.Count -gt 0) "($($runners.Count) run_*.ps1 under tests\, recursive)"

$targets    = @{}   # resolved full path -> list of "runner:line"
$unresolved = New-Object System.Collections.Generic.List[string]
$siteCount  = 0
$runnersWithResolvedSite = 0
foreach ($f in $runners) {
  $dir = Split-Path $f.FullName -Parent
  $rel = $f.FullName.Substring($Repo.Length + 1).Replace('\', '/')
  $anyResolved = $false
  foreach ($hit in (Get-ExeLiterals $f.FullName)) {
    $siteCount++
    $full = Resolve-ExeLiteral $hit.Literal $dir
    if ($null -eq $full) { $unresolved.Add(("{0}:{1}  {2}" -f $rel, $hit.Line, $hit.Literal)); continue }
    $anyResolved = $true
    $key = $full.ToLowerInvariant()
    if (-not $targets.ContainsKey($key)) { $targets[$key] = @{ Path = $full; Sites = New-Object System.Collections.Generic.List[string] } }
    $targets[$key].Sites.Add(("{0}:{1}" -f $rel, $hit.Line))
  }
  if ($anyResolved) { $runnersWithResolvedSite++ }
}
Check 'runners resolve at least one exe target' ($targets.Count -gt 0) `
  "($($targets.Count) distinct target(s) from $siteCount site(s); $runnersWithResolvedSite runner(s) with a RESOLVED site)"

# K10 -- the base a bare relative literal is resolved against is the battery's
# CWD, and this is where that stops being an assumption. run_battery.ps1 starts
# every runner with -WorkingDirectory $repoRoot (deliberately, so the engine's
# config walk-up finds C:\Projects\.drag-lint.json -- see its own comment), and
# that is the ONLY reason resolving against $Repo here matches what those
# runners will actually open. Assert the requirement, at its source.
$batteryPath = Join-Path $Repo 'tests\run_battery.ps1'
$batteryText = if (Test-Path $batteryPath) { Get-Content $batteryPath -Raw } else { '' }
Check 'the battery starts every runner with the REPO ROOT as CWD (what makes a bare relative exe literal resolve here) (K10)' `
  ($batteryText -match '(?s)Start-Process.*?-WorkingDirectory\s+\$repoRoot') `
  "($script:BareRelativeSites bare-relative site(s) resolved against the repo root)"
if (-not ($batteryText -match '(?s)Start-Process.*?-WorkingDirectory\s+\$repoRoot')) {
  Write-Host '        ^ the driver no longer pins the runners CWD to the repo root, so a bare' -ForegroundColor Yellow
  Write-Host '          relative exe literal now resolves somewhere this guard cannot predict.' -ForegroundColor Yellow
  Write-Host '          Either restore -WorkingDirectory $repoRoot, or rewrite those literals' -ForegroundColor Yellow
  Write-Host '          in the $PSScriptRoot form, which is CWD-independent.' -ForegroundColor Yellow
}

# --- the enumeration needs a FLOOR, and it must floor the RIGHT quantity ----
# Target count is the wrong thing to floor: a regression that dropped the
# "$PSScriptRoot\..." form -- 145 of 168 sites -- would still leave 23 sites and
# BOTH real targets, so a `> 0` check passes with 86% of coverage silently gone.
# That is the shrinking-battery lesson in miniature.
#
# THE FIRST VERSION OF THIS FLOOR WAS ITSELF VACUOUS, and it is worth saying why
# rather than quietly fixing it. It counted EXTRACTED sites, so killing
# Resolve-ExeLiteral's $PSScriptRoot branch left the count untouched at 167/191
# and the check PASSED while 145 sites went unverified. Extraction and
# resolution are two stages and a floor on the first says nothing about the
# second. Both are now asserted: the floor counts runners with a RESOLVED site,
# and an unresolvable literal is a failure in its own right below.
#
# Floored as a FRACTION of runners rather than a literal count, so it scales with
# the battery instead of going stale the way a hardcoded "31 tests" did. Measured
# when written: 167 of 191 runners contribute a resolved site (87%). The 24 that
# do not are DUnitX harnesses which build and run their own exe.
$floorFrac = 0.70
$floor = [int][Math]::Floor($runners.Count * $floorFrac)
Check "at least $([int]($floorFrac * 100))% of runners contribute a RESOLVED exe site (coverage floor)" `
  ($runnersWithResolvedSite -ge $floor) "($runnersWithResolvedSite of $($runners.Count); floor $floor)"
if ($runnersWithResolvedSite -lt $floor) {
  Write-Host '        ^ far fewer runners resolve to a checkable exe than they used to.' -ForegroundColor Yellow
  Write-Host '          Most likely a literal FORM stopped being recognised or stopped' -ForegroundColor Yellow
  Write-Host '          resolving (there are 6), which shrinks coverage without changing' -ForegroundColor Yellow
  Write-Host '          the target list at all.' -ForegroundColor Yellow
}

# An unresolvable literal is a hole, not a curiosity: that runner names an exe
# this guard cannot check. Zero today; reported per site so a new one is
# actionable rather than a number.
Check 'every extracted exe literal resolves to a concrete path' ($unresolved.Count -eq 0) `
  "($($unresolved.Count) unresolved of $siteCount)"
foreach ($x in $unresolved) { Write-Host "        $x" -ForegroundColor Red }

# --- Check 1: every resolved target must exist AND be current --------------
# An absent target is a FAILURE, not an INFO. An earlier version made it INFO and
# justified that with "every runner already guards with its own Test-Path and
# exits 2" -- an unmeasured universal, and false: of the 167 runners contributing
# a site, 110 have no Test-Path on the exe at all, and 47 of those also lack
# $ErrorActionPreference = 'Stop' (measured by re-running this file's own
# extractor over the same population, then grepping each contributing runner).
# Rather than swap one claimed mechanism for another, the check no longer needs
# one: if a runner names an exe this guard cannot find, the guard cannot verify
# that runner's target, and saying so is the honest outcome.
foreach ($k in ($targets.Keys | Sort-Object)) {
  $t = $targets[$k]
  $rel = if ($t.Path.StartsWith($Repo)) { $t.Path.Substring($Repo.Length + 1) } else { $t.Path }
  if (-not (Test-Path -LiteralPath $t.Path)) {
    Check "$rel exists (referenced by a runner)" $false ("resolved by: " + ($t.Sites -join ', '))
    continue
  }
  $exe = Get-Item -LiteralPath $t.Path
  Write-Host ("        {0}  {1}" -f $rel, $exe.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
  if ($null -ne $newest) {
    $ok = $exe.LastWriteTime -ge $newest.LastWriteTime
    Check "$rel is not older than the newest source file" $ok
    if (-not $ok) {
      Write-Host ("        ^ resolved by: {0}" -f ($t.Sites -join ', ')) -ForegroundColor Yellow
      Write-Host '          Those runners are measuring code that is not in this binary.' -ForegroundColor Yellow
      Write-Host '          Either run build\build_draglint_win64.bat, or -- if this is a' -ForegroundColor Yellow
      Write-Host '          platform/config nothing builds (see register E3 for Win32) --' -ForegroundColor Yellow
      Write-Host '          retarget them the way run_smoke.ps1 was retargeted.' -ForegroundColor Yellow
    }
  }
}

# --- Check 2: the canonical build outputs -----------------------------------
foreach ($rel in @('src\cli\Win64\Debug\drag-lint.exe', 'third_party\dll-win64\drag-lint.exe')) {
  $p = Join-Path $Repo $rel
  Check "$rel exists (canonical build output)" (Test-Path $p) `
    $(if (Test-Path $p) { '' } else { 'run build\build_draglint_win64.bat' })
  if ((Test-Path $p) -and ($null -ne $newest)) {
    Check "$rel is not older than the newest source file" ((Get-Item $p).LastWriteTime -ge $newest.LastWriteTime)
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'EXE FRESHNESS: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'EXE FRESHNESS: PASS' -ForegroundColor Green
exit 0
