<#
  run_rename_inactive_local.ps1 -- RN 149: `rename --qname` / `--kind symbol` over a routine-local accept the routine's own
  tokens inside an inactive {$IFDEF} branch (no ref there; same symbol by scope), as `--kind param` already did.
  POSITIVE CONTROL: a unit-level variable's inactive-branch token is still refused [no-ref-occurrence].
  RED on 1.48.0-alpha: the local refused and wrote 3 of 5 edits.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Continue'; $env:DRAGLINT_RENAME_TEST_UNGATED = '1'
$work = Join-Path $env:TEMP ('draglint-rninact-' + [Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\fixtures\refactor\rename\inactive_local\RtA.pas') $work
$fail = 0
function Check($n, $ok) { if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green } else { Write-Host "  [FAIL] $n" -ForegroundColor Red; $script:fail++ } }
Push-Location $work
try {
  $null = & $Exe index . --db db.sqlite --library-db none 2>&1
  foreach ($form in @(@('--qname'), @('--kind', 'symbol', '--qname'))) {
    $o = (& $Exe rename @form 'RtA.Go.Tmp' --to Acc --db db.sqlite --library-db none --dry-run 2>&1 | Out-String)
    Check "local via $($form -join ' '): 5 edits incl. the inactive branch, no refusal" (($o -match 'Dry run: 5 edit') -and ($o -match 'L18:C3') -and ($o -notmatch 'refused'))
  }
  $o = (& $Exe rename --qname RtA.Glob --to G2 --db db.sqlite --library-db none --dry-run 2>&1 | Out-String)
  Check 'control: a unit-level variable stays refused [no-ref-occurrence]' ($o -match 'refused \[no-ref-occurrence\]')
} finally { Pop-Location }
if ($fail) { Write-Host "FAIL: $fail" -ForegroundColor Red; exit 1 }; Write-Host 'PASS' -ForegroundColor Green