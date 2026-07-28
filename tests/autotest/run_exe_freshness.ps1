<#
  run_exe_freshness.ps1 -- the battery must test the binary the build produces.
  Register item E8, generalised by T3k.

  Why this exists
  ---------------
  tests\autotest\run_formsmap.ps1 and tests\autotest\run_wiring.ps1 defaulted to
  src\cli\Win32\Debug\drag-lint.exe. build\build_draglint_win64.bat -- the
  canonical build -- never refreshes that file, so for weeks those two runners
  ran a hand-built binary from 2026-07-27 14:01 while every other runner ran the
  branch head. They were GREEN the whole time. Not failing: NOT MEASURING.

  That is strictly worse than a red. It manufactured a confident false finding:
  T3i mutated FormsMap's query, rebuilt Win64, watched run_formsmap stay green,
  and concluded the check could not fail -- filed as register item E6, later
  disproved by data-level reproduction. Four consecutive "zero-red battery"
  claims were really "186 measured, 2 unmeasured".

  Both runners were retargeted. This runner exists because THE NEXT ONE WOULD NOT
  ANNOUNCE ITSELF EITHER: the only reason those two were ever found is that one of
  them produced a visible contradiction. Two structural checks, so a stale-binary
  runner is caught by the battery instead of by luck.

  Check 1 -- no runner may default to a Win32 CLI
    Per the v0.86 policy (user ruling 2026-07-05, see
    src\delphi-plugin\DragLint.Plugin.ExeResolver.pas) the IDE BPL is the only
    32-bit artifact and every process the plugin spawns is the Win64 CLI. Whether
    the Win32 CLI stays a supported artifact at all is register item E3, an open
    USER decision -- this check does not decide it. It asserts only the part that
    holds either way: while nothing builds a Win32 CLI, nothing may TEST one by
    default. If E3 is answered "supported", add a Win32 build step and revisit.

  Check 2 -- the Win64 exe may not be older than the source it is built from
    Catches the other half: a runner pointed at the right binary that nobody
    rebuilt. The source set is READ FROM src\cli\drag-lint.dproj's
    DCC_UnitSearchPath rather than hardcoded here, because a hardcoded list of
    directories is exactly the kind of copy that goes stale -- one declaration,
    read by the compiler and by this check.

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

# --- Check 1: no runner defaults to a Win32 CLI ----------------------------
$testsRoot = Join-Path $Repo 'tests'
$win32 = New-Object System.Collections.Generic.List[string]
$runners = @(Get-ChildItem -LiteralPath $testsRoot -Recurse -Filter 'run_*.ps1' -File)
foreach ($f in $runners) {
  $n = 0
  foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
    $n++
    # A path mention inside a comment is fine (this file mentions one). Only a
    # line that both names a Win32 CLI path and assigns it is a default.
    if ($line -match 'Win32\\Debug\\drag-lint\.exe|dll-win32\\drag-lint\.exe') {
      if ($line -match '=' -and $line -notmatch '^\s*#') {
        $win32.Add(("{0}:{1}" -f $f.FullName.Substring($Repo.Length + 1).Replace('\', '/'), $n))
      }
    }
  }
}
Check 'runners enumerated' ($runners.Count -gt 0) "($($runners.Count) run_*.ps1 under tests\, recursive)"
Check 'no runner defaults to a Win32 CLI exe' ($win32.Count -eq 0) "($($win32.Count) offender(s))"
foreach ($x in $win32) { Write-Host "        $x" -ForegroundColor Red }
if ($win32.Count -gt 0) {
  Write-Host '        ^ nothing rebuilds the Win32 CLI, so this runner is green against' -ForegroundColor Yellow
  Write-Host '          a frozen binary: not failing, NOT MEASURING. Point it at' -ForegroundColor Yellow
  Write-Host '          third_party\dll-win64\drag-lint.exe (see run_smoke.ps1).' -ForegroundColor Yellow
}

# --- Check 2: the Win64 exe is not older than its source --------------------
$dproj = Join-Path $Repo 'src\cli\drag-lint.dproj'
Check 'CLI .dproj present' (Test-Path $dproj) $dproj

$srcDirs = New-Object System.Collections.Generic.List[string]
if (Test-Path $dproj) {
  $cliDir = Split-Path $dproj -Parent
  $srcDirs.Add($cliDir)
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

# Both Win64 conventions in use across the battery: the raw build output and the
# staged copy. build_draglint_win64.bat refreshes both, so both must be current.
$exes = @('src\cli\Win64\Debug\drag-lint.exe', 'third_party\dll-win64\drag-lint.exe')
foreach ($rel in $exes) {
  $p = Join-Path $Repo $rel
  if (-not (Test-Path $p)) {
    Check "$rel exists" $false 'run build\build_draglint_win64.bat'
    continue
  }
  $exe = Get-Item $p
  Write-Host ("        {0}  {1}" -f $rel, $exe.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
  if ($null -ne $newest) {
    $ok = $exe.LastWriteTime -ge $newest.LastWriteTime
    Check "$rel is not older than the newest source file" $ok
    if (-not $ok) {
      Write-Host '        ^ the battery is measuring code that is not in this binary.' -ForegroundColor Yellow
      Write-Host '          Run build\build_draglint_win64.bat and re-run the battery.' -ForegroundColor Yellow
    }
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'EXE FRESHNESS: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'EXE FRESHNESS: PASS' -ForegroundColor Green
exit 0
