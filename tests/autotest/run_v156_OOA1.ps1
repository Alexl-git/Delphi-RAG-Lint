<#
  run_v156_OOA1.ps1 -- lane OOA-1: ambiguous-unit-reference (G-06) and assignment-narrows (G-15).
  Fixtures: tests\fixtures\v156\OOA1\g06 (project-wide, lint-all) and \g15 (per file, lint-all walks it).
  Each rule has positive and negative cases; an engine without the rules fails the positives (RED).
  Run from a neutral cwd, pwsh 7.  -Exe = the engine to test (default: this tree's third_party\dll-win64).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v156_ooa1_$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
$exePath = (Resolve-Path $Exe).Path
$fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\OOA1").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

function Run-Fixture($name, $rule) {
  $proj = Join-Path $WorkDir $name
  Copy-Item -LiteralPath (Join-Path $fix $name) -Destination $proj -Recurse
  $db = Join-Path (Join-Path $proj '_D-RAG') 'p.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $proj --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $out = & { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --rule $rule 2>$null } | Out-String
  return @{ Out = $out; Hits = @(($out -split "`r?`n") | Where-Object { $_ -match [regex]::Escape($rule) }) }
}
function Line-Of($file, $text) { (Select-String -LiteralPath $file -SimpleMatch $text | Select-Object -First 1).LineNumber }

# positive-control: ambiguous-unit-reference
# positive-control: assignment-narrows
# ---- G-06 ambiguous-unit-reference ----
$r = Run-Fixture 'g06' 'ambiguous-unit-reference'
$h = $r.Hits
Check 'A1 bare call of a name two used units declare is reported once, in uPosCall' `
  (@($h | Where-Object { $_ -match 'uPosCall\.pas' }).Count -eq 1) $r.Out
Check 'A2 bare type name two used units declare is reported in uPosType' `
  (@($h | Where-Object { $_ -match 'uPosType\.pas' }).Count -eq 1) $r.Out
Check 'A3 the message names the winning (last) unit uB' `
  ((@($h | Where-Object { $_ -match 'uPosCall\.pas' }) -join ' ') -match 'uB') $r.Out
Check 'A4 qualified reference uA.Normalize is silent' (-not ($r.Out -match 'uNegQualified')) $r.Out
Check 'A5 a unit that declares the name itself is silent' (-not ($r.Out -match 'uNegOwn')) $r.Out
Check 'A6 an overload pair with differing signatures is silent' (-not ($r.Out -match 'uNegOverload')) $r.Out
Check 'A7 identical type aliases are silent' (-not ($r.Out -match 'uNegAlias')) $r.Out
Check 'A8 only one of the two units used is silent' (-not ($r.Out -match 'uNegOne')) $r.Out
Check 'A9 a local variable of the same name is silent' (-not ($r.Out -match 'uNegLocal')) $r.Out
Check 'A10 the declaring units themselves are silent' (-not ($r.Out -match '(?<![A-Za-z])u[AB]\.pas')) $r.Out

# ---- G-15 assignment-narrows ----
$r = Run-Fixture 'g15' 'assignment-narrows'
$src = Join-Path $WorkDir 'g15\uNarrow.pas'
$want = @('Int := I64;','Small := Int;','Int := Total;','Int := ABag.Big;') | ForEach-Object { Line-Of $src $_ }
$got  = @($r.Hits | ForEach-Object { if ($_ -match 'uNarrow\.pas[:(](\d+)') { [int]$Matches[1] } })
Check 'B1 the four narrowing assignments are reported (variable, variable, function result, property)' `
  ((($want | Sort-Object) -join ',') -eq (($got | Sort-Object) -join ',')) "want=$($want -join ',') got=$($got -join ',') out=$($r.Out)"
Check 'B2 cast, constant, masked, widening and same-width assignments are silent' ($got.Count -eq 4) "got=$($got -join ',')"
Check 'B3 nothing is reported in the declaring unit' (-not ($r.Out -match 'uSrc\.pas')) $r.Out

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}