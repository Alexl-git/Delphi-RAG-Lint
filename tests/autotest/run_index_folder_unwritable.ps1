<#
  run_index_folder_unwritable.ps1 -- an index folder that cannot be created or
  written is reported by path and reason, not as a FATAL (backlog #32,
  2026-10-14).

  THE GAP. Library indexes live beside the engine, in <exe dir>\library\<bds>\
  (owner ruling 2026-10-07), so an engine installed in a folder the user cannot
  write -- Program Files -- cannot build them. The index folder was created with
  a bare TDirectory.CreateDirectory: the run died with
      FATAL: EInOutError: <the OS message, in the OS language>
  exit 3, naming neither the folder's role nor what to do.

  NOW: before anything opens the database the folder is created AND probed for
  a write; a failure is
      ERROR: cannot use the index folder <dir>: <reason>
  plus, for a library index, that it lives beside the engine and the engine must
  run from a folder the user can write. No FATAL: the section fails, and
  `index --all` reports it in its FAILED sections line (exit 1, its contract);
  a single-target `index` exits 2.

  THE FIXTURE copies the engine to a scratch folder and puts a FILE named
  "library" beside it, so the library folder cannot be created. Nothing is
  indexed either way; a 90 s cap kills the run if that ever stops being true.

  CASES:
    L   index --all --only Library: section FAILED (exit 1), folder named   <- FIX
    L'  the message says the library index lives beside the engine          <- FIX
  RED-CHECK: on the pre-fix exe L and L' fail (FATAL EInOutError, exit 3).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_idxfolder_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$exeDir = Split-Path -Parent $Exe

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$eng  = Join-Path $WorkDir 'eng'
$repo = Join-Path $WorkDir 'repo'
New-Item -ItemType Directory $eng, (Join-Path $repo '_D-RAG') -Force | Out-Null
Copy-Item $Exe $eng
Copy-Item (Join-Path $exeDir '*.dll') $eng
if (Test-Path (Join-Path $exeDir 'rules')) { Copy-Item -Recurse (Join-Path $exeDir 'rules') (Join-Path $eng 'rules') }
if (-not (Test-Path (Join-Path $eng 'sqlite3.dll'))) {
  $sq = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\sqlite3.dll'
  if (Test-Path $sq) { Copy-Item $sq $eng }
}
[System.IO.File]::WriteAllText((Join-Path $eng 'library'), 'a FILE where the library folder should go', [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText((Join-Path $repo '_D-RAG\config.json'), '{ "version": 1, "projects": [] }', [System.Text.Encoding]::ASCII)
$engExe = Join-Path $eng (Split-Path -Leaf $Exe)

Write-Host ''
Write-Host 'run_index_folder_unwritable -- a library folder that cannot be created' -ForegroundColor Cyan

$so = Join-Path $WorkDir 'out.txt'
$se = Join-Path $WorkDir 'err.txt'
$p = Start-Process $engExe -ArgumentList @('index', '--all', '--only', 'Library', '--platform', 'win32') `
       -WorkingDirectory $repo -RedirectStandardOutput $so -RedirectStandardError $se -PassThru -WindowStyle Hidden
$killed = $false
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $killed = $true }
$text = ''
foreach ($f in @($so, $se)) { if (Test-Path $f) { $text += [System.IO.File]::ReadAllText($f) } }
$code = if ($killed) { 'killed' } else { $p.ExitCode }

Check 'L the run ends by itself (nothing was indexed)' (-not $killed) $text
Check 'L no FATAL, no exit 3: the section fails and --all reports it (exit 1)' (($code -eq 1) -and -not ($text -match 'FATAL') -and ($text -match 'FAILED sections \(1 of 1\): Library')) ("exit $code`n$text")
Check 'L the error names the library folder' ($text -match ('cannot use the index folder ' + [regex]::Escape((Join-Path $eng 'library')))) $text
Check "L' and says the library index lives beside the engine" ($text -match 'beside the engine') $text

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_idxfolder_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
