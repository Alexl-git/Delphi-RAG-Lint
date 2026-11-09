<#
  run_misleading_indentation_ifelse.ps1 -- lane 150 LN item 3 (GA FOUND-BUG): misleading-indentation also checks
  `if .. else` (the else branch is the controlled single statement). Fixture tests\lint\misleading-indentation.pas:
  line 56 (indented under an if..else) must fire, line 61 (aligned) must not. Positive controls: line 11 (plain
  `if`) fires, so the rule is on; line 61 silent shows the check is not a blanket.
#>
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$bad = $false
function Check([string]$N, [bool]$Ok) { if ($Ok) { Write-Host "  ok   $N" } else { $script:bad = $true; Write-Host "  FAIL $N" -ForegroundColor Red } }
$Exe = (Resolve-Path $Exe).Path
$fx = (Resolve-Path "$PSScriptRoot\..\lint\misleading-indentation.pas").Path
$j = (& $Exe lint $fx --rule misleading-indentation --json 2>$null) -join "`n" | ConvertFrom-Json
$lines = @($j | ForEach-Object { [int]$_.start_line })
Check 'C1 control: plain-if line 11 fires (rule is on)' ($lines -contains 11)
Check 'E1 if..else dangling statement line 56 fires' ($lines -contains 56)
Check 'E2 aligned statement after if..else line 61 is silent' (-not ($lines -contains 61))
Check 'E3 no other new hit (11,16,19,36,56 only)' ((@($lines | Sort-Object) -join ',') -eq '11,16,19,36,56')
if ($bad) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS' }