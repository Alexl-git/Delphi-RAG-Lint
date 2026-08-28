<#
  run_resolve_dbs_library_contract.ps1 -- PLAN-SESSION-44 T10, the headless
  slice of T4.

  TWO SUBJECTS, and they are related by one fact.

  (A) THE CONTRACT `DLLibraryDb` MUST CONSUME. `resolve-dbs --platform <P>` is
  the engine's own answer for "which library index covers platform P", and
  CLAUDE.md tells every session to ask it rather than guess. T4 changes the
  plugin to consume it. This pins what it will be consuming.

  (B) THE AGREEMENT THE PLUGIN CURRENTLY DEPENDS ON, which is why (A) matters
  even before T4 lands. GetPlatformAwareLibraryDbPathEx does NOT call the
  engine: it RE-DERIVES the path as <indexes.outDir>\library-<Platform>.sqlite,
  reimplementing a naming convention only the manifest should own. Measured
  2026-08-28, the two agree exactly. They agree because the manifest happens to
  declare db "library-{platform}.sqlite" under that outDir -- change that
  template and the plugin keeps looking at the old name while the engine builds
  the new one, and nothing says so. Until T4 removes the duplication, this
  runner is the only thing standing between that edit and a silently stale
  RTL/VCL index in the IDE.

  WHY THIS IS A REAL GUARD AND NOT AN ECHO. The plan's stated control was:
  point it at a temp dir with NO manifest, it must FAIL. Measured against the
  engine first, IT DID NOT -- `resolve-dbs --config <missing>` printed a blank
  line and exited 0, because the bare branch swallowed the IO error into an
  empty list and the empty list fell back to AArgs.DbPath, itself ''. So the
  control the plan asked for was impossible, and the reason was a defect in the
  verb sessions are told to trust. That is fixed; C1/C2 below are what pin it.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath  = (Resolve-Path $Exe).Path
$manifest = Join-Path (Split-Path $exePath -Parent) 'drag-lint.json'

$scratch = Join-Path C:\TEMP 'draglint_resolvedbs'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function RunResolve([string[]]$ExtraArgs) {
  $o = (& $exePath resolve-dbs @ExtraArgs 2>&1 | Out-String)
  return @{ Out = $o; Code = $LASTEXITCODE
            Lines = @($o -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) }
}

Push-Location C:\TEMP
try {
  Check 'the manifest beside the engine exists (precondition, named not assumed)' `
        (Test-Path $manifest) $manifest
  if (-not (Test-Path $manifest)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

  $mf     = Get-Content $manifest -Raw | ConvertFrom-Json
  $outDir = $mf.indexes.outDir

  foreach ($plat in @('Win32','Win64')) {
    $r = RunResolve @('--platform', $plat)
    $libs = @($r.Lines | Where-Object { $_ -match 'library-.*\.sqlite$' })

    Check "$plat : resolve-dbs names exactly ONE library index" `
          ($libs.Count -eq 1) ("got " + ($libs -join ', '))

    # (B) the agreement. Derived from the MANIFEST, never from a literal -- a
    # hardcoded expectation here would pass on a machine where both are wrong.
    $derived = Join-Path $outDir ("library-$plat.sqlite")
    Check "$plat : it agrees with <outDir>\library-$plat.sqlite, which is what the plugin re-derives" `
          (($libs.Count -eq 1) -and ($libs[0] -ieq $derived)) `
          ("engine=" + ($libs -join ',') + "  plugin-shape=" + $derived)

    # Negative control: the answer must actually depend on --platform. Without
    # this, a verb that returned the same constant for every platform passes
    # every check above.
    $other = if ($plat -eq 'Win32') { 'Win64' } else { 'Win32' }
    Check "$plat : and does NOT name the $other library (the answer tracks --platform)" `
          (($libs.Count -eq 1) -and ($libs[0] -notmatch "library-$other\.sqlite$")) `
          ($libs -join ',')
  }

  # ---- C1/C2: a named --config that is not there is an ERROR, not silence ----
  # THE PLAN'S CONTROL, which the engine could not satisfy until today. Both
  # halves are asserted: a non-zero exit AND no path on stdout. Checking only
  # the exit code would pass while still emitting a bogus empty path; checking
  # only the output would pass while the caller's `if ($LASTEXITCODE)` slept.
  $missingCfg = Join-Path $scratch 'nosuch-manifest.json'
  $bad = RunResolve @('--platform','Win32','--config', $missingCfg)

  Check 'C1 a --config that does not exist exits NON-ZERO' `
        ($bad.Code -ne 0) "exit=$($bad.Code) out=[$($bad.Out.Trim())]"
  Check 'C2 ... and emits no path at all (not a blank line, not an empty JSON entry)' `
        (@($bad.Lines | Where-Object { $_ -match '\.sqlite' }).Count -eq 0) `
        ("lines=" + ($bad.Lines -join ' | '))
  Check 'C2b ... and says WHY, naming the path it could not find' `
        ($bad.Out -match 'config file not found') $bad.Out

  # Positive control for C1/C2: the SAME invocation with the REAL config must
  # succeed and resolve the library. Without it, a verb that failed on every
  # --config would satisfy C1 and C2 completely.
  $good = RunResolve @('--platform','Win32','--config', $manifest)
  Check 'C3 positive control: the same call with the REAL --config succeeds' `
        (($good.Code -eq 0) -and (@($good.Lines | Where-Object { $_ -match 'library-Win32\.sqlite$' }).Count -eq 1)) `
        "exit=$($good.Code) lines=$($good.Lines.Count)"

  # ---- the JSON surface must not carry an empty entry either ---------------
  $badJson = RunResolve @('--platform','Win32','--config', $missingCfg, '--json')
  Check 'C4 --json does not emit [""] for a missing config' `
        ($badJson.Out -notmatch '\[\s*""\s*\]') $badJson.Out
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
