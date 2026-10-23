<#
  run_migrate_gaps.ps1 -- CONVERTER's #migrate slice 1 output gaps
  (docs\INBOX-2026-10-23-converter-to-engine-migrate-gaps.md), engine side.

  Pins, on the tests\autotest\fixtures\migrate units (COPIED to a $PID scratch
  folder and indexed there):
    * G8  a '#migrate X -> DL_NONE' break is a marker, never a unit symbol: no
          uses-unit-unresolved item and no uses_unresolved[] row names DL_NONE.
          POSITIVE CONTROL: the two deliberate-break items are still there.
    * G9  every migrate-applied / deliberate-break / migrate-check item carries
          the from_type / to_type of its #convert block (TSrcBtn / TDstBtn).
    * G11 migrate-check items carry old_value = the #migrate Old member.
    * G4  pas_uses[] rows carry migrate_to: the #migrate New of a realised rule
          (Press, or DL_NONE for a deliberate break), '' when no #migrate covers
          the member; status stays mapped (the slice 1 contract).
    * G7  every pas_uses[] row carries rules_file = the document's rules_file.
    * G10 a member reached through 'with btnTop do' is listed on its pas_uses
          row: the body line joins lines[] (it is still never rewritten).
    * G3  convert-validate warns on a #migrate form convert-apply refuses, in a
          #convert block; a realised rename / DL_NONE / a file-scope #migrate
          gets no such warning. Still exit 0 and OK.
  All additive to apply/1.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_migrate_gaps_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures\migrate\*') $WorkDir
function P([string]$n) { return (Join-Path $WorkDir $n) }

$db = P 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db)

function DryRun([string]$Unit, [string]$Rules) {
  $o = (& $Exe convert-apply --unit (P $Unit) --rules (P $Rules) --db $db --format json 2>&1) -join "`n"
  $j = $null
  try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {}
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o; J = $j }
}
$MigKinds = @('migrate-applied', 'deliberate-break', 'migrate-check')
function MigItems($j) { if ($null -eq $j) { return @() }; return @($j.items | Where-Object { $MigKinds -contains $_.kind }) }
function Row($j, [string]$m) { return @($j.pas_uses | Where-Object { $_.instance -eq 'btnTop' -and $_.member -eq $m }) }
function Has($o, [string]$k) { return ($null -ne $o) -and ($o.PSObject.Properties.Name -contains $k) }

# ---- G8 ------------------------------------------------------------------------
$d = DryRun 'DlForm.pas' 'dlnone.rules'
Check 'G8-0 DlForm dry run: exit 0, JSON parsed' (($d.Code -eq 0) -and ($null -ne $d.J)) $d.Out
Check 'G8-1 POSITIVE CONTROL: 2 deliberate-break items still emitted' (@($d.J.items | Where-Object { $_.kind -eq 'deliberate-break' }).Count -eq 2) $d.Out
Check 'G8-2 no uses-unit-unresolved item names DL_NONE' `
  (@($d.J.items | Where-Object { $_.kind -eq 'uses-unit-unresolved' -and $_.text -match 'DL_NONE' }).Count -eq 0) (($d.J.warnings) -join ' | ')
Check 'G8-3 no uses_unresolved[] row named DL_NONE' (@($d.J.uses_unresolved | Where-Object { $_.name -eq 'DL_NONE' }).Count -eq 0) ($d.J.uses_unresolved | ConvertTo-Json -Compress)
Check 'G8-4 no warnings[] line names DL_NONE' (@($d.J.warnings | Where-Object { $_ -match 'DL_NONE' }).Count -eq 0) (($d.J.warnings) -join ' | ')

# ---- G9 / G11 over the three units ------------------------------------------
$m = DryRun 'MigForm.pas' 'rename.rules'
$w = DryRun 'WithForm.pas' 'rename.rules'
$all = @(MigItems $d.J) + @(MigItems $m.J) + @(MigItems $w.J)
Check 'G9-0 POSITIVE CONTROL: every migrate item kind is present (non-vacuous)' `
  (@($MigKinds | Where-Object { $k = $_; @($all | Where-Object { $_.kind -eq $k }).Count -eq 0 }).Count -eq 0) (($all | ForEach-Object { $_.kind }) -join ',')
$bad = @($all | Where-Object { $_.from_type -ne 'TSrcBtn' -or $_.to_type -ne 'TDstBtn' })
Check 'G9-1 every migrate item carries from_type TSrcBtn / to_type TDstBtn' ($bad.Count -eq 0) (($bad | ForEach-Object { "$($_.kind)@$($_.line)=[$($_.from_type)->$($_.to_type)]" }) -join ', ')
$mc = @($all | Where-Object { $_.kind -eq 'migrate-check' })
Check 'G11 every migrate-check item has old_value = its #migrate Old (path)' `
  (($mc.Count -gt 0) -and (@($mc | Where-Object { -not (Has $_ 'old_value') -or ($_.old_value -ne $_.path) }).Count -eq 0)) ($mc | ConvertTo-Json -Compress -Depth 3)

# ---- G4 ------------------------------------------------------------------------
$cnt = @(Row $d.J 'Count'); $hint = @(Row $d.J 'Hint'); $clk = @(Row $d.J 'Click'); $cap = @(Row $d.J 'Caption')
Check 'G4-1 DL_NONE rows Count/Hint: migrate_to DL_NONE, status still mapped' `
  (($cnt.Count -eq 1) -and ($hint.Count -eq 1) -and ($cnt[0].migrate_to -eq 'DL_NONE') -and ($hint[0].migrate_to -eq 'DL_NONE') -and `
   ($cnt[0].status -eq 'mapped') -and ($hint[0].status -eq 'mapped')) ($d.J.pas_uses | ConvertTo-Json -Compress -Depth 3)
Check 'G4-2 rename row Click: migrate_to Press' (($clk.Count -eq 1) -and ($clk[0].migrate_to -eq 'Press')) ($clk | ConvertTo-Json -Compress)
Check 'G4-3 CONTROL: #link row Caption: migrate_to present and empty' (($cap.Count -eq 1) -and (Has $cap[0] 'migrate_to') -and ($cap[0].migrate_to -eq '')) ($cap | ConvertTo-Json -Compress)

# ---- G7 ------------------------------------------------------------------------
$rows = @($d.J.pas_uses) + @($m.J.pas_uses)
Check 'G7 every pas_uses row carries rules_file = the document rules_file' `
  (($rows.Count -gt 0) -and (@($d.J.pas_uses | Where-Object { $_.rules_file -ne $d.J.rules_file }).Count -eq 0) -and `
   (@($m.J.pas_uses | Where-Object { $_.rules_file -ne $m.J.rules_file }).Count -eq 0) -and ($d.J.rules_file -ne '')) ($rows | ConvertTo-Json -Compress -Depth 3)

# ---- G10 -----------------------------------------------------------------------
$wl = (Get-Content (P 'WithForm.pas'))
$withLine = 1 + [array]::IndexOf($wl, '  with btnTop do')
$wclk = @(Row $w.J 'Click')
Check 'G10-0 POSITIVE CONTROL: the with migrate-check is still emitted' `
  (@($w.J.items | Where-Object { $_.kind -eq 'migrate-check' -and $_.line -eq $withLine }).Count -ge 1) $w.Out
Check 'G10-1 the with body site (Click, line after the with) is on the Click row lines[], beside the plain site' `
  (($wclk.Count -eq 1) -and (@($wclk[0].lines) -contains ($withLine + 1)) -and (@($wclk[0].lines) -contains ($withLine + 2)) -and ($wclk[0].count -eq 2)) ($wclk | ConvertTo-Json -Compress)
Check 'G10-2 ... still exactly 1 migrate-applied (the with body is never rewritten)' (@($w.J.items | Where-Object { $_.kind -eq 'migrate-applied' }).Count -eq 1) $w.Out

# ---- G3 ------------------------------------------------------------------------
$v = (& $Exe convert-validate --rules (P 'refused.rules') 2>$null) -join "`n"
$vc = $LASTEXITCODE
$rl = Get-Content (P 'refused.rules')
function LineOf([string]$t) { return 1 + [array]::IndexOf($rl, $t) }
Check 'G3-0 convert-validate still exit 0 and OK' (($vc -eq 0) -and ($v -match '(?m)^OK\s*$')) $v
Check 'G3-1 the scoped #migrate is warned on its line' ($v -match ("(?m)^line {0}: warning: #migrate .*scoped" -f (LineOf '#migrate TSrcBtn:Click -> Press'))) $v
Check 'G3-2 the template #migrate is warned on its line' ($v -match ("(?m)^line {0}: warning: #migrate .*replacement templates" -f (LineOf '#migrate Count -> Items.Count'))) $v
Check 'G3-3 CONTROL: no warning on the realised DL_NONE / rename / file-scope lines' `
  (-not ($v -match ("(?m)^line ({0}|{1}|{2}): warning: #migrate" -f (LineOf '#migrate Hint -> DL_NONE'), (LineOf '#migrate Click -> Press'), (LineOf '#migrate Early -> Later')))) $v
$v2 = (& $Exe convert-validate --rules (P 'dlnone.rules') 2>$null) -join "`n"
Check 'G3-4 CONTROL: a book of realised #migrate rules gets no #migrate warning' (-not ($v2 -match 'warning: #migrate')) $v2

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_migrate_gaps_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
