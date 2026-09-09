<#
  run_battery_stderr_guard.ps1 -- the battery runner must not EXECUTE GARBAGE.

  WHAT HAPPENED. On 2026-09-09 a backslash-collapse corrupted
  `tests\run_battery.ps1`: one comment line became three, and two of them
  PowerShell parsed as COMMANDS. The author wrote

      # in third_party\dll-win64\rules and src\cli\Win64\Release\rules after the

  and what reached disk was

      # in third_partydll-win64
      ules and srccliWin64Release
      ules after the

  Every backslash was eaten; the two `\r` sequences became carriage returns that
  split the line. Every battery run then emitted, twice, to stderr:

      The term 'ules' is not recognized as a name of a cmdlet, function, script
      file, or executable program.

  and the battery reported `495 pass / 0 fail`. The banner was true and the file
  was still corrupt.

  WHY NOTHING CAUGHT IT. These are NON-TERMINATING errors: they change no exit
  code, fail no runner, and **nothing reads the battery's own stderr**. A defect
  in the RUNNER ITSELF that does not move an exit code is invisible to the only
  thing anyone looks at. The commit shipped, pushed, inside a green run.

  WHY A PARSE CHECK CANNOT REPLACE THIS. `ules and srccliWin64Release` is
  syntactically VALID PowerShell -- a command invocation with two arguments. It
  parses clean and fails only at runtime. Check 6 below asserts exactly that
  against the corrupt fixture, so that anyone tempted to "simplify" this guard
  into a static parse check sees the measurement that rules it out.

  THE INVARIANT THIS ASSERTS, and the decision behind it. The note that asked
  for this guard left one question open: should a dirty stderr FAIL or merely
  WARN, since some runner might legitimately write to stderr? Measured
  2026-09-09 on the full 497-runner battery: **stderr was 0 bytes**. No runner
  emits expected stderr today, so the strict rule costs nothing and is adopted:
  a clean run writes NOTHING to stderr. A zero baseline is the only moment such
  a rule can be adopted cheaply -- once one runner is allowed to dirty stderr,
  every future collapse hides behind it.

  WHY IT PROBES WITH `-List`. `-List` enumerates and exits before running any
  runner (4.8 s), so this guard cannot recurse into the battery that contains
  it. Crucially `if ($List)` sits at run_battery.ps1:510, AFTER the rules-sync
  region at ~425-471 where the corruption actually lived -- so `-List` DOES
  execute the hazardous code. Check 4 proves that rather than assuming it: a
  probe that exited before the corrupt region would report a clean stderr
  forever, which is the "guard incapable of failing" shape this repo keeps
  rediscovering.

  MEASURED RED, THEN GREEN -- 2026-09-09, and the RED reading was taken WITHOUT
  touching the real run_battery.ps1. `-RepoRoot` was pointed at a scratch tree
  holding a stand-in battery that prints the marker, exits 0, and carries the
  collapse verbatim:

    [PASS] the -List probe exits 0 exit=0
    [FAIL] the -List probe writes NOTHING to stderr stderr=414 byte(s)
           -- first line: ules: ...\tests\run_battery.ps1:4
    [FAIL]   ...and in particular executes no unrecognized command
    [PASS] the probe actually EXECUTED the region that was corrupt
    [PASS] the corrupt probe DOES dirty stderr
    [PASS]   ...while still EXITING 0 and running the lines after it
    [PASS] a PARSE check would NOT have caught it -- parse errors: 0

  Note the shape of that RED: exactly the two stderr checks moved, the probe
  still exited 0, and the non-vacuity check still passed. Against the real tree:
  8 PASS / 0 FAIL, stderr 0 bytes, 4.8 s.

  Run from a NEUTRAL CWD, pwsh 7.
    pwsh -File tests\autotest\run_battery_stderr_guard.ps1
    pwsh -File tests\autotest\run_battery_stderr_guard.ps1 -RepoRoot <scratch>  # RED
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path,
  [string]$WorkDir  = ''
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("batstderr_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# The signature of an executed-garbage line, in the words PowerShell actually
# uses. Kept as one pattern so checks 3 and 5 assert the SAME detector -- a
# positive control that exercised a different pattern would prove nothing about
# the real check.
$NOT_RECOGNIZED = 'is not recognized as a name of a cmdlet'

$battery = Join-Path $RepoRoot 'tests\run_battery.ps1'
Write-Host ''
Write-Host ("battery : {0}" -f $battery) -ForegroundColor Cyan
Check 'the battery runner exists' (Test-Path $battery) $battery
if (-not (Test-Path $battery)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# --- 1-4. The real assertion: a battery probe writes nothing to stderr -------

$pOut = Join-Path $WorkDir 'list.out'
$pErr = Join-Path $WorkDir 'list.err'
$proc = Start-Process pwsh -ArgumentList '-File', $battery, '-List' `
          -WorkingDirectory $RepoRoot -RedirectStandardOutput $pOut `
          -RedirectStandardError $pErr -NoNewWindow -Wait -PassThru

$errBytes = (Get-Item $pErr).Length
$errText  = if ($errBytes -gt 0) { [IO.File]::ReadAllText($pErr) } else { '' }
$outText  = [IO.File]::ReadAllText($pOut)

Write-Host ''
Write-Host 'THE BATTERY RUNNER ITSELF' -ForegroundColor Cyan
Check 'the -List probe exits 0' ($proc.ExitCode -eq 0) "exit=$($proc.ExitCode)"
Check 'the -List probe writes NOTHING to stderr' ($errBytes -eq 0) `
  ("stderr=$errBytes byte(s)" + $(if ($errBytes -gt 0) { " -- first line: " + (($errText -split "`r?`n")[0]) } else { '' }))
Check '  ...and in particular executes no unrecognized command' `
  (-not ($errText -match $NOT_RECOGNIZED)) `
  'this is the exact signature the 2026-09-09 collapse produced, twice, on every run'

# NON-VACUITY. Without this, a probe that exited early -- or a run_battery whose
# -List moved ABOVE the rules-sync region -- would report a clean stderr forever.
Check 'the probe actually EXECUTED the region that was corrupt' `
  ($outText -match 'rule catalogue') `
  'the collapse sat in the rules-sync block at ~run_battery.ps1:425-471; `if ($List)` is at :510, so -List runs it'

# --- 5-6. POSITIVE CONTROLS --------------------------------------------------
# End-to-end, not a regex self-test: a genuinely corrupt script is executed in a
# child pwsh exactly as the battery is, and the SAME detector must fire on the
# SAME capture mechanism.

$corrupt = Join-Path $WorkDir 'corrupt_probe.ps1'
$corruptLines = @(
  'Write-Host ''before the corrupt line''',
  '# The next line is the 2026-09-09 collapse, reproduced verbatim: a comment',
  '# whose backslashes were eaten, leaving a command invocation behind.',
  'ules and srccliWin64Release',
  'Write-Host ''after the corrupt line'''
)
[IO.File]::WriteAllText($corrupt, (($corruptLines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

$cOut = Join-Path $WorkDir 'corrupt.out'
$cErr = Join-Path $WorkDir 'corrupt.err'
$cProc = Start-Process pwsh -ArgumentList '-File', $corrupt `
           -WorkingDirectory $WorkDir -RedirectStandardOutput $cOut `
           -RedirectStandardError $cErr -NoNewWindow -Wait -PassThru
$cErrText = [IO.File]::ReadAllText($cErr)
$cOutText = [IO.File]::ReadAllText($cOut)

Write-Host ''
Write-Host 'POSITIVE CONTROL -- a really corrupt script, run the same way' -ForegroundColor Cyan
Check 'the corrupt probe DOES dirty stderr' `
  (($cErr | Get-Item).Length -gt 0 -and ($cErrText -match $NOT_RECOGNIZED)) `
  'if this fails, the checks above are measuring nothing -- the capture or the pattern is broken'
Check '  ...while still EXITING 0 and running the lines after it' `
  ($cProc.ExitCode -eq 0 -and ($cOutText -match 'after the corrupt line')) `
  "exit=$($cProc.ExitCode) -- THIS is why the defect hid: a non-terminating error moves no exit code"

# The note's own finding, pinned so nobody replaces this guard with a parse check.
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($corrupt, [ref]$tokens, [ref]$parseErrors)
Check 'a PARSE check would NOT have caught it' (@($parseErrors).Count -eq 0) `
  ("parse errors on the corrupt fixture: {0} -- valid PowerShell, so static parsing cannot replace running it" -f @($parseErrors).Count)

try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
