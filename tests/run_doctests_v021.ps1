<#
  run_doctests_v021.ps1 -- makes the legacy `.bat` doctest suite visible to the
  battery.

  WHY THIS FILE EXISTS. tests\run_battery.ps1 discovers runners by FILENAME
  PATTERN (`run_*.ps1`, recursive). tests\run_v021_doctests.bat is named
  `run_*` but is a `.bat`, so it -- and the 27 fixtures it stitches together --
  were never enumerated, never skipped, never reported. Not a gap anyone chose:
  a gap the discovery mechanism creates silently.

  WHAT THAT COST, concretely. `resolve-uses` shipped a user-visible multi-DB
  defect while carrying a fixture in this very folder. And every one of these
  fixtures hard-coded `third_party\dll\drag-lint.exe` -- the RETIRED Win32 build,
  which still exists and still reports the same version string as the current
  Win64 one. Run as they stood, 15 of 27 sections FAILED; repointed at the
  current engine, ALL 27 PASS. The tests were never rotten. They were aimed at a
  dead binary and nobody could see them fail.

  WHAT THIS DOES NOT COVER. v021 is a strict superset of the v016-v020 drivers
  (verified by comparing their fixture lists), so those are redundant and were
  deleted. But ~34 further fixtures -- T27 through T65, plus T_resolve_uses --
  are called by NO driver at all and remain unassessed; many are IDE-form tests
  (hover/completion/signature/refactor forms, keyboard, notifier, registry
  colours) that cannot run headless. See
  docs\INBOX-68-bat-tests-are-invisible-to-the-battery.md.

  THE POSITIVE CONTROL IS THE SECTION COUNT. The driver is a chain of
  `call ... || set FAILED=1`; if its fixture list were emptied, or every `call`
  silently did nothing, it would still exit 0. Asserting the number of sections
  that actually announced themselves is what stops this wrapper from becoming a
  green light for an empty suite -- which is precisely the failure mode that let
  the .bat suite rot invisibly in the first place.

  Usage: pwsh -File tests/run_doctests_v021.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  # Honoured because every fixture now reads `if not defined EXE set EXE=...`,
  # so the battery can point the whole suite at a specific build.
  [string]$Exe = "$PSScriptRoot\..\third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

# The driver stitches 27 sections. Pinned, not derived from the driver's own
# text: deriving it would make an emptied driver agree with itself.
$ExpectedSections = 27

$driver = Join-Path $PSScriptRoot 'run_v021_doctests.bat'
if (-not (Test-Path $driver)) { Write-Host "FATAL: driver not found: $driver" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Exe))    { Write-Host "FATAL: exe not found: $Exe"       -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$log = Join-Path $env:TEMP ("drag-lint-doctests-v021-{0}.log" -f $PID)
$env:EXE = $Exe   # every fixture defers to a pre-set EXE

Write-Host 'Running the legacy .bat doctest chain against the current engine' -ForegroundColor Cyan
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $driver `
                   -Wait -NoNewWindow -PassThru `
                   -RedirectStandardOutput $log -RedirectStandardError "$log.err"
$out = if (Test-Path $log) { Get-Content $log } else { @() }
Remove-Item Env:\EXE -ErrorAction SilentlyContinue

$sections = @($out | Where-Object { $_ -match '^=== T\d+' })
$fails    = @($out | Where-Object { $_ -match '^FAIL' })

Check 'driver exits 0' ($p.ExitCode -eq 0) ("exit={0}; {1} FAIL line(s): {2}" -f $p.ExitCode, $fails.Count, (($fails | Select-Object -First 6) -join ' | '))

Check ("POSITIVE CONTROL: all {0} sections actually ran" -f $ExpectedSections) `
  ($sections.Count -eq $ExpectedSections) `
  ("sections announced={0} want={1} -- a driver whose fixture list was emptied still exits 0, so the count is what makes this wrapper mean something" -f $sections.Count, $ExpectedSections)

Check 'no section reported FAIL' ($fails.Count -eq 0) (($fails | Select-Object -First 10) -join "`n")

if (Test-Path $log)        { Remove-Item $log        -Force -ErrorAction SilentlyContinue }
if (Test-Path "$log.err")  { Remove-Item "$log.err"  -Force -ErrorAction SilentlyContinue }

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
