<#
  run_doc_idempotent.ps1 -- THE idempotency lock for `document`.

  Managed-region regeneration must be a fixed point: applying the doc-comment,
  RE-INDEXING (the store caches file content by mtime/sha -- a stale index would
  hand back pre-insert line numbers and give a false result), then applying
  again must leave the file BYTE-IDENTICAL and report action=unchanged / 0 edits.

  Fixture doc_generate.pas (public Add + caller UseAdd). Sequence:
    index -> document --apply (run 1) -> RE-INDEX -> document --apply (run 2)
  Asserts:
    * file bytes after run 2 == file bytes after run 1 (regions stable)
    * run-2 --json action = 'unchanged', edits = 0, applied = false

  If this FAILS, the StripManagedBlock / idempotency logic regressed -- the
  assertion is NOT weakened; the harness reports the bug loudly.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\doc_generate.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docidem'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'doc_generate.pas'
$db      = Join-Path $scratch 'idem.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- run 1: apply, capture bytes ---
  $r1 = & $exePath document --qname doc_generate.Add --db $db --apply --json 2>$null | Out-String
  $o1 = $null; try { $o1 = ($r1 | ConvertFrom-Json) } catch { $o1 = $null }
  Check 'run1: action = created'  ($null -ne $o1 -and $o1.action -eq 'created')
  Check 'run1: applied = true'    ($null -ne $o1 -and $o1.applied -eq $true)
  $bytes1 = [IO.File]::ReadAllBytes($target)

  # --- CRITICAL: re-index so the store sees the post-insert line numbers ---
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- run 2: apply again; must be a no-op ---
  $r2 = & $exePath document --qname doc_generate.Add --db $db --apply --json 2>$null | Out-String
  $o2 = $null; try { $o2 = ($r2 | ConvertFrom-Json) } catch { $o2 = $null }
  Check 'run2: action = unchanged' ($null -ne $o2 -and $o2.action -eq 'unchanged')
  Check 'run2: edits = 0'          ($null -ne $o2 -and [int]$o2.edits -eq 0)
  Check 'run2: applied = false'    ($null -ne $o2 -and $o2.applied -eq $false)
  $bytes2 = [IO.File]::ReadAllBytes($target)

  Check 'IDEMPOTENT: file bytes identical after run 2 vs run 1' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes1,[byte[]]$bytes2))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
