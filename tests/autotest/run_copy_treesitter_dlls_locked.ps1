<#
  run_copy_treesitter_dlls_locked.ps1 -- Copy-TreeSitterDlls (lib\CliBuildPaths.ps1)
  does not fail on a DLL that is already in place and loaded
  (INBOX-2026-09-29-engine-followups-from-1.20.4 item 4b, last bullet).

  THE DEFECT. Several refactor suites stage tree-sitter*.dll into the SHARED
  tests\refactor folder with Copy-Item -Force. Under the battery's -Jobs 4 one
  suite's test exe has the DLL loaded while another suite copies over it, the
  copy throws "being used by another process", and run_enum_helper failed in
  every parallel battery while passing alone. The bytes it tried to write were
  the bytes already there.

    A. dest identical + locked     -> no throw (nothing needed copying).
    B. POSITIVE CONTROL: dest DIFFERENT + locked -> throws; a stale DLL is
       never silently kept.
    C. dest different, not locked  -> copied (bytes equal after).

  pwsh 7; touches only %TEMP%.
#>
[CmdletBinding()]
param([string]$WorkDir = "$env:TEMP\drag-lint-copy-ts-dlls-$PID")
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
. (Join-Path $PSScriptRoot 'lib\CliBuildPaths.ps1')
$src  = Join-Path $WorkDir 'src'
$dest = Join-Path $WorkDir 'dest'
New-Item -ItemType Directory -Force $src, $dest | Out-Null
$name = 'tree-sitter-fake.dll'
$srcF = Join-Path $src $name
$dstF = Join-Path $dest $name
[IO.File]::WriteAllBytes($srcF, [byte[]](1..64))
Copy-TreeSitterDlls -Dest $dest -SourceDir $src | Out-Null

function Try-Copy {
  try { Copy-TreeSitterDlls -Dest $dest -SourceDir $src | Out-Null; return '' } catch { return $_.Exception.Message }
}

Write-Host 'A. identical DLL in place, held open (as a loaded image is)' -ForegroundColor Cyan
$h = [IO.File]::Open($dstF, 'Open', 'Read', 'Read')
try { $ea = Try-Copy } finally { $h.Dispose() }
Check 'A1 no throw' ($ea -eq '') "[$ea]"

Write-Host 'B. CONTROL: a DIFFERENT DLL in place, held open' -ForegroundColor Cyan
[IO.File]::WriteAllBytes($srcF, [byte[]](64..1))
$h = [IO.File]::Open($dstF, 'Open', 'Read', 'Read')
try { $eb = Try-Copy } finally { $h.Dispose() }
Check 'B1 throws (a stale DLL is not kept silently)' ($eb -ne '') "[$eb]"

Write-Host 'C. a different DLL in place, not held' -ForegroundColor Cyan
$ec = Try-Copy
$same = ([Convert]::ToBase64String([IO.File]::ReadAllBytes($srcF)) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($dstF)))
Check 'C1 copied' (($ec -eq '') -and $same) "[$ec]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
