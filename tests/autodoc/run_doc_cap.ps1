<#
  run_doc_cap.ps1 -- `document` Called-from DISPLAY CAP + DISTINCT-caller dedupe.

  Fixture project cap/ has one function Target and 16 DISTINCT caller routines
  (Caller01..Caller16), each a separate top-level function calling Target once.
  With the CalledFrom dedupe (key = enclosing qname + file, line-free), the
  distinct-caller count is 16.

  UPDATED for Whole-Project Auto-Document Phase 1 Task 1: the CalledFrom cap
  used to be the shared hard-coded DocDisplayCount helper (total > 15 -> show
  10); Task 1 replaced that for CalledFrom specifically with the CONFIG-DRIVEN
  docs.max_callers (manifest key, default 5 -- see LoadDocMaxCallers in
  DRagLint.CLI.pas). This test runs against the DEPLOYED exe with NO local
  manifest override, so it exercises the in-code default: cap=5, "(+11 more)"
  with N = 16 - 5 = 11. (DocDisplayCount itself is unchanged and still governs
  the separate Calls:/Used in units: lines -- only CalledFrom moved to the new
  config knob.)

  Asserts (dry-run preview -- no need to mutate the file):
    * "Called from:" line ends with "(+11 more)"
    * exactly 5 distinct "cap_callers.CallerNN" names precede the suffix
    * Caller01 present, Caller06 NOT shown (past the cap)

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath  = (Resolve-Path $Exe).Path
$fixTgt   = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\cap\cap_target.pas')).Path
$fixCall  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\cap\cap_callers.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_doccap'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item $fixTgt  (Join-Path $scratch 'cap_target.pas')  -Force
Copy-Item $fixCall (Join-Path $scratch 'cap_callers.pas') -Force
$db = Join-Path $scratch 'cap.sqlite'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  $out = & $exePath document --qname cap_target.Target --db $db 2>$null | Out-String
  # Grab the single "Called from:" line.
  $line = ($out -split "`r?`n" | Where-Object { $_ -match 'Called from:' } | Select-Object -First 1)
  Check 'preview: a "Called from:" line is present' ($null -ne $line -and $line -ne '')

  Check 'cap: line ends with "(+11 more)"' ($line -match '\(\+11 more\)\s*$')

  # Count the distinct CallerNN names shown before the "(+N more)" suffix.
  $shown = ([regex]::Matches($line, 'cap_callers\.Caller\d{2}')).Count
  Check 'cap: exactly 5 named callers shown' ($shown -eq 5)

  Check 'cap: Caller01 shown (first)'     ($line -match 'cap_callers\.Caller01\b')
  Check 'cap: Caller05 shown (last kept)' ($line -match 'cap_callers\.Caller05\b')
  Check 'cap: Caller06 NOT shown (past cap)' (-not ($line -match 'cap_callers\.Caller06\b'))

  # Also confirm the JSON dry-run classifies it as created (facts non-empty).
  $j = & $exePath document --qname cap_target.Target --db $db --json 2>$null | Out-String
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { $o = $null }
  Check 'json: action = created' ($null -ne $o -and $o.action -eq 'created')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
