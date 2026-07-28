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

  Check 1 -- every exe any runner resolves must be current
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
  goes stale. One declaration, read by the compiler and by this check.

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

$srcDirs = New-Object System.Collections.Generic.List[string]
if (Test-Path $dproj) {
  $cliDir = Split-Path $dproj -Parent
  $srcDirs.Add($cliDir)
  # NOTE (deferred to the second sweep, recorded in the register): a .dproj
  # carries one DCC_UnitSearchPath per build configuration. This takes the first
  # match, so a config-specific path present only in a later block is not seen
  # and the source set can silently shrink. The count assertion below is the
  # floor that makes a large shrink visible; a per-config union is the real fix.
  $m = [regex]::Match((Get-Content $dproj -Raw), '<DCC_UnitSearchPath>(.*?)</DCC_UnitSearchPath>', 'Singleline')
  if ($m.Success) {
    foreach ($p in ($m.Groups[1].Value -split ';')) {
      $t = $p.Trim()
      if ($t -eq '' -or $t.StartsWith('$(')) { continue }
      $full = Join-Path $cliDir $t
      if (Test-Path $full) { $srcDirs.Add((Resolve-Path $full).Path) }
    }
  }
}
Check 'source dirs read from the .dproj search path' ($srcDirs.Count -gt 1) "($($srcDirs.Count) dirs)"

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
function Get-ExeLiterals([string]$Path) {
  $out = New-Object System.Collections.Generic.List[object]
  $inBlock = $false
  $n = 0
  foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
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
    $hash = $code.IndexOf('#')
    if ($hash -ge 0) { $code = $code.Substring(0, $hash) }
    if ($code.Trim() -eq '') { continue }
    foreach ($mm in [regex]::Matches($code, '["'']([^"'']*[\\/]drag-lint\.exe)["'']', 'IgnoreCase')) {
      $out.Add([pscustomobject]@{ Line = $n; Literal = $mm.Groups[1].Value })
    }
  }
  return $out
}

function Resolve-ExeLiteral([string]$Literal, [string]$RunnerDir) {
  $s = $Literal
  if ($s.StartsWith('$PSScriptRoot')) { $s = $s.Substring('$PSScriptRoot'.Length).TrimStart('\', '/'); $base = $RunnerDir }
  elseif ($s.StartsWith('..'))        { $base = $RunnerDir }
  elseif ([IO.Path]::IsPathRooted($s)) { return [IO.Path]::GetFullPath($s) }
  else                                 { $base = $Repo }
  if ($s -match '\$') { return $null }   # any other variable: cannot resolve statically
  return [IO.Path]::GetFullPath((Join-Path $base $s))
}

$testsRoot = Join-Path $Repo 'tests'
$runners = @(Get-ChildItem -LiteralPath $testsRoot -Recurse -Filter 'run_*.ps1' -File)
Check 'runners enumerated' ($runners.Count -gt 0) "($($runners.Count) run_*.ps1 under tests\, recursive)"

$targets   = @{}   # resolved full path -> list of "runner:line"
$unresolved = 0
foreach ($f in $runners) {
  $dir = Split-Path $f.FullName -Parent
  foreach ($hit in (Get-ExeLiterals $f.FullName)) {
    $full = Resolve-ExeLiteral $hit.Literal $dir
    if ($null -eq $full) { $unresolved++; continue }
    $key = $full.ToLowerInvariant()
    if (-not $targets.ContainsKey($key)) { $targets[$key] = @{ Path = $full; Sites = New-Object System.Collections.Generic.List[string] } }
    $targets[$key].Sites.Add(("{0}:{1}" -f $f.FullName.Substring($Repo.Length + 1).Replace('\', '/'), $hit.Line))
  }
}
Check 'runners resolve at least one exe target' ($targets.Count -gt 0) "($($targets.Count) distinct target(s), $unresolved variable-only reference(s) skipped)"

# --- Check 1: every resolved target that EXISTS must be current ------------
# An ABSENT target is not silently ignored, but it is not this runner's failure
# either: every runner already guards with its own Test-Path and exits 2, so
# absence is loud where staleness is silent. Reported so it stays visible.
foreach ($k in ($targets.Keys | Sort-Object)) {
  $t = $targets[$k]
  $rel = if ($t.Path.StartsWith($Repo)) { $t.Path.Substring($Repo.Length + 1) } else { $t.Path }
  if (-not (Test-Path -LiteralPath $t.Path)) {
    Write-Host ("  [INFO] referenced but absent: {0}   <- {1}" -f $rel, ($t.Sites -join ', ')) -ForegroundColor DarkGray
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
