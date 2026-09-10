<#
  run_library_sibling_platform_guard.ps1 -- Option A2 of
  docs\PLAN-proptree-tcomponent-members.md, which also discharges
  docs\INBOX-nested-library-roots-double-walk.md.

  TWO OVERLAP SHAPES, ONE FIX. Registry library paths are walked RECURSIVELY per
  root (the compiler does not walk them that way) and the configured roots
  overlap:

    shape 1  parent/child      'source\rtl\win' contains 'source\rtl\win\winrt';
                               'spring4d\Source' contains 17 listed roots.
                               Cost: ~900 redundant IndexFile calls per platform,
                               ~10% of a 5.5 h --rebuild.
    shape 2  parent whose      '$(DXVCL)\Library\RS37' contains 'WinArm64EC' and
             children are      'Win64x'. Cost: 2,462 foreign-platform files in
             OTHER PLATFORMS   library-Win32.sqlite, 21,265 twinned class qnames,
                               16,748 unresolved ancestor edges, and TcxGrid
                               showing 103 top-level members against Win64's 471.

  WHY THIS GUARD ASSERTS ON `index --all --dry-run` AND NOT ON A FIXTURE.
  This was designed as a hermetic fixture first, and the design was WRONG -- worth
  recording, because the wrong version would have passed while testing nothing.
  A LIBRARY section's roots do not come from the manifest: DRagLint.Index.Plan
  sets PS.Roots := AResolver.ReadPlatformLibraryPaths(Plat), i.e. from the
  REGISTRY, and only smLibrary sections carry a Platform at all (a folder section
  is smFolderTree with Platform = ''). So a temp-folder fixture can never reach
  the code path this fix lives on, and `index <dir> --platform Win32` does not
  help either -- on a bare folder index --platform only feeds the preprocessor
  profile (it is parsed into CheckPlatform, read by DoIndexAll and the profile
  resolver, never as a section platform).

  The dry run is therefore the only cheap surface that exercises the REAL plan.
  It is honest here because both printed lines are rendered by the SAME two
  functions the walk calls -- SiblingPlatformExcludes and CollapseNestedRoots --
  so this cannot degrade into pinning a printer that agrees with nothing.

  EXPECTATIONS ARE DERIVED FROM THE REGISTRY, NOT HARD-CODED. A guard that
  asserted the literal pair ('WinArm64EC', 'Win64x') would pass on this machine
  and mean nothing on another, and would keep passing if the fix were replaced by
  a hard-coded list -- which is precisely the implementation this rejects.

  CASES
    A   for EVERY library section the plan emits, the sibling-platform prune is
        exactly (registered platforms - this section's own platform).
    P   POSITIVE CONTROL, and the one that matters most: the section's OWN
        platform is NEVER pruned. 'RS37\Win32' (165 files) is legitimately part of
        the Win32 library, so a fix that pruned every platform token would destroy
        real source while making CASE A pass.
    M   MIRROR: the rule is not "drop WinArm64EC". Win32 must be pruned from the
        WinArm64EC section exactly as WinArm64EC is pruned from the Win32 one.
        Skipped with a loud SKIP (never a silent pass) if the plan emits only one
        library platform on this machine.
    N   NESTED ROOTS: the roots line reconciles (total = walked + collapsed) and,
        where the manifest really does carry overlapping roots, at least one is
        collapsed. The "at least one" half is asserted only when the machine's
        registry actually has an overlap -- computed here independently of the
        engine, so this cannot pass vacuously.

  RED SIGNATURE against the PRE-FIX engine (snapshot of commit 5754e07,
  sha256 1F24617176B8607D1EF09866987C4DD3E884C930F1B52581273AEFA6D0901A59):
  the pre-fix dry run prints neither line, so every A/P/M/N assertion fails on
  'line absent'. That is a weaker red than a wrong VALUE, and it is called out
  rather than glossed: the strong end-to-end proof is the INBOX note's own
  measurement -- `attempted + up-to-date + oversize - walked` on a real library
  section, ~900 before and 0 after -- which is verified from the section summary
  during the next full re-parse, not here, because it costs hours.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Skip($n, $why) { Write-Host ("  [SKIP] {0} -- {1}" -f $n, $why) -ForegroundColor Yellow }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# --- the machine's own answer, computed WITHOUT the engine ---------------------
$libKey = 'HKCU:\Software\Embarcadero\BDS\37.0\Library'
if (-not (Test-Path $libKey)) { Write-Host "FATAL: no registry Library key: $libKey" -ForegroundColor Red; exit 2 }
$registered = @(Get-ChildItem $libKey | ForEach-Object { $_.PSChildName })
Check 'registry lists platforms (independent expectation source)' ($registered.Count -ge 2) "$($registered.Count): $($registered -join ', ')"

# --- run the dry plan ---------------------------------------------------------
# stdout and stderr to SEPARATE handles: merged, a stderr write can be cut in
# half and a stdout line spliced into the gap, which breaks line-anchored regex.
# The manifest is named EXPLICITLY rather than left to discovery. Without it the
# answer depends on which exe ran: the deployed third_party\dll-win64\drag-lint.exe
# sits beside its drag-lint.json and resolves 35 sections, while the freshly built
# src\cli\Win64\Debug\drag-lint.exe has no manifest beside it and resolves ZERO --
# which this guard reported as "0 library section(s)", i.e. as a failure of the
# engine rather than of its own invocation.
$config = Join-Path (Resolve-Path "$PSScriptRoot\..\..").Path 'third_party\dll-win64\drag-lint.json'
if (-not (Test-Path $config)) { Write-Host "FATAL: manifest not found: $config" -ForegroundColor Red; exit 2 }
$out = & $Exe index --all --config $config --dry-run 2>$null
$text = $out -join "`n"

$sections = @()
$cur = $null
foreach ($line in $out) {
  # GREEDY to the LAST ']' on purpose: a library section renders its name as
  # 'Library[Win32]', so the whole token is '[Library[Win32]]' and a lazy
  # [^\]]+ stops inside it and never reaches ' mode='. Caught by this guard
  # failing with "0 library section(s)" against an engine that printed 13.
  if ($line -match '^\s{4}\[(.+)\]\s+mode=(\w+)') {
    if ($cur) { $sections += $cur }
    $name = $Matches[1]; $mode = $Matches[2]
    $plat = if ($name -match '\[([^\]]+)\]$') { $Matches[1] } else { '' }
    $cur = [pscustomobject]@{
      Name = $name; Mode = $mode; Platform = $plat
      Sib = $null; RootsTotal = $null; RootsWalked = $null; RootsCollapsed = $null
    }
  }
  elseif ($cur -and $line -match '^\s+sibling-platform-prune:\s+(\d+)\s+\[(.*)\]\s*$') {
    $cur.Sib = @(($Matches[2] -split ',\s*') | Where-Object { $_ -ne '' })
  }
  elseif ($cur -and $line -match '^\s+roots:\s+(\d+) total, (\d+) walked, (\d+) nested-collapsed') {
    $cur.RootsTotal = [int]$Matches[1]; $cur.RootsWalked = [int]$Matches[2]; $cur.RootsCollapsed = [int]$Matches[3]
  }
}
if ($cur) { $sections += $cur }

$libs = @($sections | Where-Object { $_.Mode -eq 'library' })
Check 'dry run emits at least one library section' ($libs.Count -ge 1) "$($libs.Count) library section(s)"
if ($libs.Count -eq 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# --- CASE A + P ---------------------------------------------------------------
Write-Host ''
Write-Host 'CASE A/P: prune is exactly (registered - own), and NEVER the own platform' -ForegroundColor Cyan
foreach ($s in $libs) {
  $expected = @($registered | Where-Object { $_ -ne $s.Platform } | Sort-Object)
  $actual   = @($s.Sib | Sort-Object)
  Check "[$($s.Platform)] sibling-platform-prune line is present" ($null -ne $s.Sib) "got: $(if ($null -eq $s.Sib) { 'ABSENT' } else { $s.Sib.Count })"
  if ($null -ne $s.Sib) {
    Check "[$($s.Platform)] prunes exactly the OTHER registered platforms" (($actual -join '|') -eq ($expected -join '|')) "expected $($expected.Count), got $($actual.Count)"
    # CASE P -- the control that stops "prune every platform token" passing.
    Check "[$($s.Platform)] does NOT prune its OWN platform" (-not ($actual -contains $s.Platform)) "own='$($s.Platform)'"
  }
}

# --- CASE M -------------------------------------------------------------------
Write-Host ''
Write-Host 'CASE M (mirror): the rule is symmetric, not a hard-coded name' -ForegroundColor Cyan
if ($libs.Count -lt 2) {
  Skip 'mirror' "the plan emits only $($libs.Count) library platform on this machine"
} else {
  $a = $libs[0]; $b = $libs[1]
  if ($null -ne $a.Sib -and $null -ne $b.Sib) {
    Check "[$($a.Platform)] prunes '$($b.Platform)'" ($a.Sib -contains $b.Platform) "got: $($a.Sib -join ', ')"
    Check "[$($b.Platform)] prunes '$($a.Platform)'" ($b.Sib -contains $a.Platform) "got: $($b.Sib -join ', ')"
  } else { Check 'mirror needs both prune lines' $false 'one or both ABSENT' }
}

# --- CASE N -------------------------------------------------------------------
Write-Host ''
Write-Host 'CASE N: nested-root collapse reconciles, and actually fires where roots overlap' -ForegroundColor Cyan
foreach ($s in @($sections | Where-Object { $_.Mode -in @('library','folderTree') })) {
  Check "[$($s.Name)] roots line is present" ($null -ne $s.RootsTotal) "got: $(if ($null -eq $s.RootsTotal) { 'ABSENT' } else { $s.RootsTotal })"
  if ($null -ne $s.RootsTotal) {
    Check "[$($s.Name)] roots reconcile: total = walked + collapsed" ($s.RootsTotal -eq ($s.RootsWalked + $s.RootsCollapsed)) "$($s.RootsTotal) vs $($s.RootsWalked)+$($s.RootsCollapsed)"
  }
}

# Independent overlap check, so "0 collapsed" cannot pass vacuously.
$plat0 = @($libs)[0].Platform
$sp = (Get-ItemProperty "$libKey\$plat0" -Name 'Search Path' -ErrorAction SilentlyContinue).'Search Path'
if ([string]::IsNullOrWhiteSpace($sp)) {
  Skip 'overlap positive control' "no Search Path readable for $plat0"
} else {
  $roots = @(($sp -split ';') | Where-Object { $_ -match '\S' -and $_ -notmatch '^\$\(' } |
             ForEach-Object { $_.Trim().TrimEnd('\').ToLower() })
  $overlaps = 0
  foreach ($r in $roots) { foreach ($o in $roots) { if ($r -ne $o -and $r.StartsWith($o + '\')) { $overlaps++; break } } }
  if ($overlaps -eq 0) {
    Skip 'overlap positive control' "this machine's $plat0 Search Path has no literal nested pair (unexpanded `$(VAR) roots are not resolvable here)"
  } else {
    $s0 = @($libs)[0]
    Check "[$($s0.Platform)] collapses at least one root (registry shows $overlaps literal overlap(s))" ($s0.RootsCollapsed -ge 1) "collapsed=$($s0.RootsCollapsed)"
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
