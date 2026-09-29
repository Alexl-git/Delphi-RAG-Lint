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
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath  = (Resolve-Path $Exe).Path
$manifest = Join-Path (Split-Path $exePath -Parent) 'drag-lint.json'

$scratch = Join-Path C:\TEMP "draglint_resolvedbs_$PID"
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

# ---- N: the never-built NOTE advises a command that WORKS ----------------------
# The NOTE guessed the section name from the DB FILE base name: `--only
# library-Win64` for the library (the section is `Library`, and it needs
# --platform) and `--only Foo` for a project section named `P-Foo` whose DB is
# <proj>\_D-RAG\Foo.sqlite. Both advised commands exited 2 ("--only matched no
# configured section"). The check RUNS the advice, with --dry-run appended, so
# the assertion is "the command works", not "the text looks right".
#
# ISOLATION: an ENGINE COPY in %TEMP% with its own drag-lint.json, run from a
# CWD under %TEMP%, so neither resolve-dbs nor the advised `index --all` can
# see the shared engine manifest. The advice is only ever run with --dry-run.
$nRoot = Join-Path $env:TEMP "draglint_resolvedbs_note_$PID"
try {
  if (Test-Path $nRoot) { Remove-Item $nRoot -Recurse -Force }
  $nEng  = Join-Path $nRoot 'eng'
  $nProj = Join-Path $nRoot 'proj'
  New-Item -ItemType Directory -Path $nEng, $nProj | Out-Null
  $exeDir = Split-Path $exePath -Parent
  Copy-Item $exePath (Join-Path $nEng 'drag-lint.exe') -Force
  Get-ChildItem -Path $exeDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $nEng $_.Name) -Force }
  if (Test-Path (Join-Path $exeDir 'rules')) { Copy-Item (Join-Path $exeDir 'rules') (Join-Path $nEng 'rules') -Recurse -Force }
  $nExe = Join-Path $nEng 'drag-lint.exe'
  $nMf = @{
    settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
    indexes  = @{ sections = @(
      @{ name = 'P-Foo';   include = @('..\proj\Foo.dpr') },
      @{ name = 'Library'; db = 'library-{platform}.sqlite'; source = 'registry-libraries'; platforms = @('Win64') }
    ) }
  } | ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText((Join-Path $nEng 'drag-lint.json'), ($nMf -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $nProj 'Foo.dpr'), "program Foo;`r`n`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)

  Push-Location $nRoot
  try {
    $nOut  = (& $nExe resolve-dbs --platform win64 2>&1 | Out-String)
    $notes = @($nOut -split "`r?`n" | Where-Object { $_ -match '^NOTE: .* has never been built -- run: ' })
    $fooDb = Join-Path $nProj '_D-RAG\Foo.sqlite'
    Check 'N0 precondition: neither fixture DB exists' `
          ((-not (Test-Path $fooDb)) -and (@(Get-ChildItem $nRoot -Recurse -Filter '*.sqlite').Count -eq 0)) $fooDb

    foreach ($case in @(
        @{ Tag = 'N1'; Db = '\library-Win64.sqlite'; Only = 'Library' },
        @{ Tag = 'N2'; Db = '\proj\_D-RAG\Foo.sqlite'; Only = 'P-Foo'   })) {
      $line = @($notes | Where-Object { $_.Contains($case.Db) })
      Check "$($case.Tag) a never-built NOTE names $($case.Db)" ($line.Count -eq 1) $nOut
      if ($line.Count -ne 1) { continue }
      $cmd = ($line[0] -split ' -- run: ', 2)[1].Trim()
      Check "$($case.Tag) ... and advises --only $($case.Only) (the SECTION name, not the file name)" `
            ($cmd -match ('--only ' + [regex]::Escape($case.Only) + '(\s|$)')) $cmd
      # Run the advice. Replace the leading engine name with the COPY, keep the
      # rest verbatim, and append --dry-run so nothing is built.
      Check "$($case.Tag) ... which starts with the engine name" ($cmd -match '^drag-lint ') $cmd
      $argv = @([regex]::Matches(($cmd -replace '^drag-lint\s+', ''), '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') }) + '--dry-run'
      $dOut = (& $nExe @argv 2>&1 | Out-String)
      $dCode = $LASTEXITCODE
      Check "$($case.Tag) ... and that command, run with --dry-run, exits 0" ($dCode -eq 0) `
            ("exit=$dCode cmd=[$cmd] out=[" + $dOut.Trim() + ']')
    }
    Check 'N3 the library advice carries --platform (a library section is per-platform)' `
          (@($notes | Where-Object { $_.Contains('\library-Win64.sqlite') -and ($_ -match '--platform Win64(\s|$)') }).Count -eq 1) `
          ($notes -join ' | ')
    Check 'N4 the project advice carries no --platform (a project section has none)' `
          (@($notes | Where-Object { $_.Contains('\proj\_D-RAG\Foo.sqlite') -and ($_ -notmatch '--platform') }).Count -eq 1) `
          ($notes -join ' | ')

    # N5: resolve-dbs --config <m> read THAT manifest, so the advice must too --
    # otherwise the advised `index --all` loads the engine's default manifest.
    # alt.json names the section P-Alt, which the default manifest does NOT
    # have, so advice that dropped --config would exit 2 when run.
    $cfgDir = Join-Path $nRoot 'cfgcwd'
    New-Item -ItemType Directory -Path $cfgDir | Out-Null
    $cfgMf = Join-Path $nEng 'alt.json'
    $altMf = @{
      settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
      indexes  = @{ sections = @( @{ name = 'P-Alt'; include = @('..\proj\Foo.dpr') } ) }
    } | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($cfgMf, ($altMf -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
    Push-Location $cfgDir
    try {
      $cOut  = (& $nExe resolve-dbs --platform win64 --config $cfgMf 2>&1 | Out-String)
      $cLine = @($cOut -split "`r?`n" | Where-Object { $_ -match '^NOTE: .*\\proj\\_D-RAG\\Foo\.sqlite .* -- run: ' })
      $cCmd  = if ($cLine.Count -eq 1) { ($cLine[0] -split ' -- run: ', 2)[1].Trim() } else { '' }
      Check 'N5 with --config, the advice names P-Alt and carries the same --config' `
            (($cCmd -match '--only P-Alt(\s|$)') -and ($cCmd -match ('--config "' + [regex]::Escape($cfgMf) + '"'))) "cmd=[$cCmd] out=[$($cOut.Trim())]"
      $cArgv = @([regex]::Matches(($cCmd -replace '^drag-lint\s+', ''), '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') }) + '--dry-run'
      $cRun  = (& $nExe @cArgv 2>&1 | Out-String)
      Check 'N5 ... and that command, run with --dry-run, exits 0' ($LASTEXITCODE -eq 0) "cmd=[$cCmd] out=[$($cRun.Trim())]"
    } finally { Pop-Location }
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $nRoot) { Remove-Item -LiteralPath $nRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_resolvedbs_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
