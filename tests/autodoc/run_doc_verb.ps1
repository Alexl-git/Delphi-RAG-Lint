<#
  run_doc_verb.ps1 -- `document` VERB CONTRACT (actions, dry-run, .bak, exits).

  Uses doc_generate.pas (public Add + caller). Asserts:
    * first --apply --json -> action = created, applied = true
    * re-index, second --apply --json -> action = unchanged, applied = false
    * a plain dry-run (no --apply) does NOT modify the file on disk
    * --apply writes a .bak beside the target
    * a bad --qname (nonexistent symbol) -> "symbol not found:" + exit 1
      (the not-found path prints a plain-text message and exits BEFORE the
      JSON block, so there is no JSON action=not_found surface -- exit 1 and
      the message ARE the contract)
    * omitting --qname -> exit 2 (usage)

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\doc_generate.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docverb'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'doc_generate.pas'
$db      = Join-Path $scratch 'verb.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- dry-run (no --apply) must not touch the file, and write no .bak ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath document --qname doc_generate.Add --db $db 2>$null | Out-Null
  $after  = [IO.File]::ReadAllBytes($target)
  Check 'dry-run: file NOT modified' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
  Check 'dry-run: NO .bak written'   (-not (Test-Path "$target.bak"))

  # --- first --apply: action=created, applied=true, .bak written ---
  $r1 = & $exePath document --qname doc_generate.Add --db $db --apply --json 2>$null | Out-String
  $ec1 = $LASTEXITCODE
  $o1 = $null; try { $o1 = ($r1 | ConvertFrom-Json) } catch { $o1 = $null }
  Check 'apply #1: action = created' ($null -ne $o1 -and $o1.action -eq 'created')
  Check 'apply #1: applied = true'   ($null -ne $o1 -and $o1.applied -eq $true)
  Check 'apply #1: exit 0'           ($ec1 -eq 0)
  Check 'apply #1: .bak written'     (Test-Path "$target.bak")

  # --- re-index, second --apply: action=unchanged, applied=false ---
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $r2 = & $exePath document --qname doc_generate.Add --db $db --apply --json 2>$null | Out-String
  $ec2 = $LASTEXITCODE
  $o2 = $null; try { $o2 = ($r2 | ConvertFrom-Json) } catch { $o2 = $null }
  Check 'apply #2: action = unchanged' ($null -ne $o2 -and $o2.action -eq 'unchanged')
  Check 'apply #2: applied = false'    ($null -ne $o2 -and $o2.applied -eq $false)
  Check 'apply #2: exit 0'             ($ec2 -eq 0)

  # --- bad --qname -> "symbol not found:" message + exit 1 (no JSON action) ---
  $rb = & $exePath document --qname doc_generate.NoSuchSymbol --db $db --json 2>$null | Out-String
  $ecb = $LASTEXITCODE
  Check 'bad qname: reports "symbol not found:"' ($rb -match 'symbol not found:')
  Check 'bad qname: exit 1'                      ($ecb -eq 1)

  # --- no --qname -> exit 2 (usage) ---
  & $exePath document --db $db 2>$null | Out-Null
  Check 'no qname: exit 2' ($LASTEXITCODE -eq 2)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
