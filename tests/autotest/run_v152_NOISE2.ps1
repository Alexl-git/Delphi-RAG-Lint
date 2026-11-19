<#
  run_v152_NOISE2.ps1 -- 1.52 lane NOISE2 (owner ruling B4 part 1: FP-only noise audit).

  The audit removed two false-positive SHAPES from large-magic-number (rules\large-magic-number.json,
  exclude_if_preceded_by). Each removed shape is checked absent AND paired with a still-firing
  true-positive twin, so a rule that went silent everywhere cannot pass:
    (a) the literal that starts the rhs of an assignment to a dotted member
        (Q.Length := 50000; Timer.Interval := 3000) -- the member names it, as magic-literal's N-12;
        twins: a plain local target, a literal inside a larger rhs.
    (b) the default value of an INI read whose key literal names it
        (ReadInteger(Sec, 'TimeInJobFolder', 1800000)); twins: the same argument shape on a call
        that is not a Read*, and a literal after the Read* call.
  With the pre-lane rules\large-magic-number.json the five (a)/(b) absence checks FAIL (lines 9 10 11 15 16 fire).

  The fixture is tests\lint\large-magic-number-v152.pas; rules come from the repo's rules\ via
  --rules-dir, so the runner tests the checked-in json, not whatever sits beside the exe.

  Usage: pwsh -File tests\autotest\run_v152_NOISE2.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }

$Fixture = Join-Path $Root 'tests\lint\large-magic-number-v152.pas'
$Rules   = Join-Path $Root 'rules'
$Rule    = 'large-magic-number'

$Pass = 0; $Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}

Push-Location ([IO.Path]::GetTempPath())
try { $Out = & { $ErrorActionPreference = 'Continue'; & $Exe lint $Fixture --rules-dir $Rules --json 2>$null } } finally { Pop-Location }
$Txt = ($Out -join "`n")
$All = @(if ($Txt.Trim() -eq '') { @() } else { @(($Txt | ConvertFrom-Json) | ForEach-Object { $_ }) })
# lint --json is a bare array; the line field is start_line (never .line)
$Lines = @($All | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
Write-Host ("large-magic-number lines: " + (($Lines | Sort-Object) -join ','))

Check 'rule is live on the fixture (positive control: any finding)' ($Lines.Count -gt 0)
Check '(a) Q.Length := 50000 is silent'            (-not ($Lines -contains 9))
Check '(a) Q.Interval := 3000 is silent'           (-not ($Lines -contains 10))
Check '(a) Self.Q.Size := 5000000 is silent'       (-not ($Lines -contains 11))
Check '(a) twin: X := 50000 still fires'           ($Lines -contains 12)
Check '(a) twin: X := Q.Count * 3000 still fires'  ($Lines -contains 13)
Check '(a) twin: Q.Interval := X * 3000 still fires' ($Lines -contains 14)
Check '(b) ReadInteger default is silent'          (-not ($Lines -contains 15))
Check '(b) ReadInt64 default is silent'            (-not ($Lines -contains 16))
Check '(b) twin: same shape on Lookup still fires' ($Lines -contains 17)
Check '(b) twin: literal after the Read* call fires' ($Lines -contains 18)

Write-Host ("run_v152_NOISE2: {0} pass / {1} fail" -f $Pass, $Fail)
if ($Fail -gt 0) { exit 1 }
exit 0