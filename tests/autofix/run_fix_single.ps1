<#
  run_fix_single.ps1 -- TDD harness for the single-finding fix mode
  (lint --fix --fix-line <L> --fix-rule <R> [--apply|--json|--no-backup]).

  Copies the redundant_parens.pas fixture to a scratch file under C:\TEMP
  (the fix mutates the file + writes a .bak), then:
    1) preview: --fix --fix-line 7 --fix-rule redundant-parentheses --json
       must emit a JSON array whose targeted object has
       fixable=true, applied=false, preview=true, rule=redundant-parentheses,
       and MUST NOT touch the file on disk.
    2) apply: same + --apply must strip the outer parens (line 7 becomes
       "  X := (A + B);"), report applied=true/preview=false, and write a .bak.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\redundant_parens.pas')).Path
$L       = 7
$Rule    = 'redundant-parentheses'

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_fixsingle'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'redundant_parens.pas'
$bak    = "$target.bak"

# Builds the target-selecting arguments for a given form:
#   'positional' -> `lint <target> ...`  (the original contract)
#   'file'       -> `lint --file <target> ...`  (AutoFix spec D2 + IDE Task 7)
# Everything else about the fix invocation is identical, so the two forms MUST
# produce the same preview/apply behaviour.
function TargetArgs($form) {
  if ($form -eq 'file') { return @('lint','--file',$target) }
  return @('lint',$target)
}

# Runs the full preview + apply contract for one target-selecting form and
# asserts fixable=true/applied=false/preview=true on preview, and paren-strip +
# .bak on apply. $tag prefixes every check so the two runs are distinguishable.
function Invoke-FixChecks($form, $tag) {
  # --- 1) PREVIEW (--json, no --apply): JSON reports the targeted finding, file untouched ---
  Copy-Item $fixture $target -Force
  if (Test-Path $bak) { Remove-Item $bak -Force }
  $before = [IO.File]::ReadAllText($target)
  $pvArgs = (TargetArgs $form) + @('--fix','--fix-line',$L,'--fix-rule',$Rule,'--json')
  $raw = & $exePath @pvArgs 2>$null | Out-String
  $arr = $null
  try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
  # Normalize to array
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }

  Check "$tag preview: JSON parses as a non-empty array" ($null -ne $arr -and $arr.Count -ge 1)
  $t = $null
  if ($null -ne $arr) { $t = $arr | Where-Object { $_.rule -eq $Rule } | Select-Object -First 1 }
  Check "$tag preview: targeted finding present (rule=redundant-parentheses)" ($null -ne $t)
  if ($null -ne $t) {
    Check "$tag preview: line = 7"         ($t.line -eq $L)
    Check "$tag preview: fixable = true"   ($t.fixable -eq $true)
    Check "$tag preview: applied = false"  ($t.applied -eq $false)
    Check "$tag preview: preview = true"   ($t.preview -eq $true)
  }
  Check "$tag preview: JSON array has exactly the targeted finding (count=1)" ($null -ne $arr -and $arr.Count -eq 1)
  Check "$tag preview: file NOT modified on disk" ([IO.File]::ReadAllText($target) -eq $before)
  Check "$tag preview: NO .bak written"           (-not (Test-Path $bak))

  # --- 2) APPLY (--apply --json): parens stripped, applied=true, .bak exists ---
  Copy-Item $fixture $target -Force
  if (Test-Path $bak) { Remove-Item $bak -Force }
  $apArgs = (TargetArgs $form) + @('--fix','--fix-line',$L,'--fix-rule',$Rule,'--json','--apply')
  $raw2 = & $exePath @apArgs 2>$null | Out-String
  $arr2 = $null
  try { $arr2 = ($raw2 | ConvertFrom-Json) } catch { $arr2 = $null }
  if ($null -ne $arr2 -and $arr2 -isnot [System.Array]) { $arr2 = @($arr2) }
  $t2 = $null
  if ($null -ne $arr2) { $t2 = $arr2 | Where-Object { $_.rule -eq $Rule } | Select-Object -First 1 }

  Check "$tag apply: targeted finding present" ($null -ne $t2)
  if ($null -ne $t2) {
    Check "$tag apply: applied = true"  ($t2.applied -eq $true)
    Check "$tag apply: preview = false" ($t2.preview -eq $false)
  }
  $lines = [IO.File]::ReadAllLines($target)
  $line7 = if ($lines.Count -ge $L) { $lines[$L-1] } else { '' }
  Check "$tag apply: line 7 parens stripped (`"  X := (A + B);`")" ($line7.Trim() -eq 'X := (A + B);')
  Check "$tag apply: .bak written" (Test-Path $bak)
  if (Test-Path $bak) {
    $bakText = [IO.File]::ReadAllText($bak)
    Check "$tag apply: .bak holds the ORIGINAL ((A + B))" ($bakText.Contains('((A + B))'))
  }
}

Push-Location C:\TEMP
try {
  # Positional form: `lint <path> --fix ...` (the original, unchanged contract).
  Invoke-FixChecks 'positional' '[positional]'
  # --file form: `lint --file <path> --fix ...` -- AutoFix spec D2 + IDE Task 7
  # spawn this exact shape; it MUST behave identically to the positional form.
  Invoke-FixChecks 'file' '[--file]'
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
