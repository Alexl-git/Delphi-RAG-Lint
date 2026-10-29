<#
  run_lintall_corrupt_library.ps1 -- lane CLIFIX C1 (#16). A library DB that is not a SQLite file
  (first 4 KB zeroed) must DEGRADE lint-all exactly as lint-project does: same findings as a run
  without the library, exit code unchanged, and one line
      warning: library DB <path> unreadable (<sqlite message>) -- continuing without it
  Before the fix lint-all died `FATAL: ESQLiteNativeException ... file is not a database` (exit 3)
  inside used-unit-not-resolvable. Positive control: the intact library prints no warning.
  Control: lint-project, library resolved from an engine-copy manifest, prints the same text.
  Everything runs on scratch copies; no real DB or manifest is touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-corruptlib-$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
$fx   = New-G8Scratch 'dup-unit' $WorkDir
$proj = Join-Path $WorkDir 'proj.sqlite'
$good = Join-Path $WorkDir 'library-Win64.sqlite'
$bad  = Join-Path $WorkDir 'library-Win64-bad.sqlite'
Check 'index project' ((Invoke-G8Index $Exe $fx $proj) -eq 0)
Check 'index library' ((Invoke-G8Index $Exe $fx $good) -eq 0)
Copy-Item $good $bad -Force
$fs = [IO.File]::Open($bad, 'Open', 'ReadWrite')
try { $fs.Write((New-Object byte[] 4096), 0, 4096) } finally { $fs.Close() }

# An engine copy whose manifest names a Library section: lint-project and a one-db lint-all resolve
# the library from it (the path lint-project already degraded on = the control for the shared text).
$eng = Join-Path $WorkDir 'eng'
New-Item -ItemType Directory -Path $eng | Out-Null
$exeDir = Split-Path $Exe -Parent
Copy-Item $Exe (Join-Path $eng 'drag-lint.exe') -Force
Get-ChildItem -Path $exeDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
if (Test-Path (Join-Path $exeDir 'rules')) { Copy-Item (Join-Path $exeDir 'rules') (Join-Path $eng 'rules') -Recurse -Force }
$man = @{ settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
          indexes  = @{ sections = @( @{ name = 'Library'; db = 'library-{platform}.sqlite'; source = 'registry-libraries'; platforms = @('Win64') } ) } }
[IO.File]::WriteAllText((Join-Path $eng 'drag-lint.json'), (($man | ConvertTo-Json -Depth 8) -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
$engExe = Join-Path $eng 'drag-lint.exe'
Copy-Item $bad (Join-Path $eng 'library-Win64.sqlite') -Force

function Run-Cmd([string]$Cmd, [string[]]$A) {
  Push-Location $WorkDir   # cwd under TEMP: the manifest walk-up must not find C:\Projects\.drag-lint.json
  try { $o = & $Cmd @A 2>&1 | ForEach-Object { "$_" }; $code = $LASTEXITCODE } finally { Pop-Location }
  return @{ Out = ($o -join "`n"); Code = $code }
}
function Count-Findings([string]$Out) {
  $m = [regex]::Match($Out, 'lint-all: (\d+) finding')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return -1
}
$none = Run-Cmd $Exe @('lint-all', '--db', $proj)
$ok   = Run-Cmd $Exe @('lint-all', '--db', $proj, '--db', $good)
$rb   = Run-Cmd $Exe @('lint-all', '--db', $proj, '--db', $bad)
$rbx  = Run-Cmd $Exe @('lint-all', '--db', $proj, '--library-db', $bad)
$rm   = Run-Cmd $engExe @('lint-all', '--db', $proj)
$lp   = Run-Cmd $engExe @('lint-project', '--db', $proj)
$warnRx = 'warning: library DB .+ unreadable \(.+\) -- continuing without it'

Check 'no-library run produced a count' ((Count-Findings $none.Out) -ge 0) ('n=' + (Count-Findings $none.Out))
Check 'positive control: intact library, no warning' ($ok.Out -notmatch 'warning: library DB')
Check 'corrupt 2nd --db: no FATAL' ($rb.Out -notmatch 'FATAL')
Check 'corrupt 2nd --db: exit code as without library' ($rb.Code -eq $none.Code) "($($rb.Code) vs $($none.Code))"
Check 'corrupt 2nd --db: warning line' ($rb.Out -match $warnRx)
Check 'corrupt 2nd --db: finding count equals no-library run' ((Count-Findings $rb.Out) -eq (Count-Findings $none.Out))
Check '--library-db corrupt: no FATAL, count equal' (($rbx.Out -notmatch 'FATAL') -and ((Count-Findings $rbx.Out) -eq (Count-Findings $none.Out)))
Check 'manifest-resolved corrupt library, lint-all: no FATAL + warning' (($rm.Out -notmatch 'FATAL') -and ($rm.Out -match $warnRx))
Check 'control lint-project (manifest-resolved): no FATAL' ($lp.Out -notmatch 'FATAL')
Check 'control lint-project: same warning text' ($lp.Out -match $warnRx)
if ($script:Failed) { Write-Host 'run_lintall_corrupt_library: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lintall_corrupt_library: PASS' -ForegroundColor Green
exit 0
