<#
  run_codelens_cache_lru.ps1 -- build and run CodeLensCacheLruTests.dpr.

  The code-lens cache had NO size bound: TDragLintCodeLensCache.FByFile only ever
  shrank via Clear or InvalidateFile, so an IDE session that visited many files
  grew it indefinitely. It is now capped at CODELENS_MAX_FILES and evicts
  least-recently-used first.

  WHY A COMPILED CONSOLE TEST rather than an exe-driven autotest: the cache is a
  plain TDictionary + TCriticalSection with no Open Tools API dependency, so it
  links and runs outside the IDE. The design-time BPL it normally ships in cannot
  be rebuilt while RAD Studio is open, so in-IDE behaviour stays unverified --
  but the eviction logic does not need the IDE to be exercised, and waiting for a
  closed IDE would mean not testing it at all. Same shape as
  tests\refactor\run_enum_helper.ps1, which builds EnumHelperTests.dpr the same
  way.

  The assertions live in the .dpr. Two of them (TestLruNotFifo) separate LRU from
  FIFO and were confirmed to FAIL with touch-on-read neutralised, so they are
  load-bearing rather than decorative.
#>
[CmdletBinding()]
param(
  [string]$Dpr     = "$PSScriptRoot\..\CodeLensCacheLruTests.dpr",
  [string]$WorkDir = "$env:TEMP\drag-lint-codelens-lru"
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dpr)) { Write-Host "FATAL: dpr not found: $Dpr" -ForegroundColor Red; exit 2 }
$Dpr     = (Resolve-Path $Dpr).Path
$DprDir  = Split-Path $Dpr -Parent
$DprName = Split-Path $Dpr -Leaf

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$DcuDir = Join-Path $WorkDir 'dcu'
New-Item -ItemType Directory $DcuDir | Out-Null

# dcc64 refuses to create output into a directory that does not exist (F2039),
# hence both are made above rather than relying on the compiler to do it.
$bat = Join-Path $WorkDir 'build.bat'
$lines = @(
  '@echo off',
  ('call "{0}"' -f $rs),
  ('cd /d "{0}"' -f $DprDir),
  ('dcc64 -B -E"{0}" -N0"{1}" {2}' -f $WorkDir, $DcuDir, $DprName),
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

$buildLog = Join-Path $WorkDir 'build.log'
$p = Start-Process cmd.exe -ArgumentList "/c","`"$bat`"" `
       -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err" `
       -NoNewWindow -Wait -PassThru
$buildOut = Get-Content $buildLog -Raw
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FATAL: compile failed' -ForegroundColor Red
  Write-Host $buildOut
  exit 2
}

$exe = Join-Path $WorkDir ([System.IO.Path]::GetFileNameWithoutExtension($DprName) + '.exe')
if (-not (Test-Path $exe)) { Write-Host "FATAL: exe not produced: $exe" -ForegroundColor Red; exit 2 }

$out = & $exe 2>&1 | Out-String
$rc  = $LASTEXITCODE
Write-Host $out.TrimEnd()

if ($rc -ne 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($out -notmatch '(\d+) passed, 0 failed') {
  # A run that printed nothing would otherwise sail through on exit 0.
  Write-Host 'FAIL: no pass/fail summary in output' -ForegroundColor Red; exit 1
}
Write-Host 'PASS' -ForegroundColor Green
exit 0
