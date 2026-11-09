<#
  run_marker_rules_dir.ps1 -- lane 150 LN item 4 (IC 149 finding): review-marker-malformed read the rule ids from
  <exe-dir>\rules even when the linter ran with --rules-dir, so a dl:ok naming a rule that only the --rules-dir
  catalogue holds (sql-injection-concat) was called "not a rule id" although the rule fires.
  Setup: a private copy of the exe + companions WITHOUT a rules folder; the rules come from the real exe's folder
  through --rules-dir. Controls: C1 the rule fires (so --rules-dir is honoured by the runner); C2 a bogus id is
  still malformed (the reporter is on); C3 without --rules-dir the copy has no rules (the setup is a real test).
#>
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$bad = $false
function Check([string]$N, [bool]$Ok) { if ($Ok) { Write-Host "  ok   $N" } else { $script:bad = $true; Write-Host "  FAIL $N" -ForegroundColor Red } }
$Exe = (Resolve-Path $Exe).Path
$Rules = Join-Path (Split-Path $Exe) 'rules'
$Tmp = Join-Path $env:TEMP ('markrd_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
try {
  $eng = Join-Path $Tmp 'eng'; [IO.Directory]::CreateDirectory($eng) | Out-Null
  Get-ChildItem (Split-Path $Exe) -File | Copy-Item -Destination $eng -Force
  $x = Join-Path $eng 'drag-lint.exe'
  $body = "unit U1;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nuses FireDAC.Comp.Client;`r`n`r`nprocedure P(Q: TFDQuery; const N: string);`r`nbegin`r`n  Q.SQL.Text:= 'select * from t where a = ' + N; // dl:ok {0} -- reviewed`r`nend;`r`n`r`nend.`r`n"
  $good = Join-Path $Tmp 'u1.pas'; $bogus = Join-Path $Tmp 'u2.pas'
  [IO.File]::WriteAllText($good, ($body -f 'sql-injection-concat'), [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText($bogus, (($body -f 'bogus-rule-x').Replace('U1', 'U2')), [Text.Encoding]::ASCII)
  function Run([string]$F, [string[]]$Extra) { @(& $x lint $F @Extra --enable review-marker-malformed 2>&1 | ForEach-Object { "$_" }) }
  $a = Run $good @('--rules-dir', $Rules)
  $nm = Join-Path $Tmp 'u4.pas'; [IO.File]::WriteAllText($nm, (($body -f 'x').Replace(' // dl:ok x -- reviewed', '').Replace('U1', 'U4')), [Text.Encoding]::ASCII)
  $n = Run $nm @('--rules-dir', $Rules)
  Check 'C1 control: the rule fires with --rules-dir (marker absent)' (@($n | Where-Object { $_ -match '\[warning\] sql-injection-concat' }).Count -eq 1)
  Check 'M1 a dl:ok for a --rules-dir rule is not malformed' (@($a | Where-Object { $_ -match 'review-marker-malformed' }).Count -eq 0)
  $b = Run $bogus @('--rules-dir', $Rules)
  Check 'C2 control: a bogus id is still malformed' (@($b | Where-Object { $_ -match 'review-marker-malformed' }).Count -eq 1)
  $c = Run $good @()
  Check 'C3 control: without --rules-dir the copy knows no rule (setup is real)' (@($c | Where-Object { $_ -match 'review-marker-malformed' }).Count -eq 1)
} finally { [IO.Directory]::Delete($Tmp, $true) }
if ($bad) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS' }