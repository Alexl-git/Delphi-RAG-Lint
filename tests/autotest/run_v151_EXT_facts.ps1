<#
  run_v151_EXT_facts.ps1 -- v151 lane EXT: extractor facts and the is-never-true sealed cases.

  Indexes tests\autotest\fixtures\v151-EXT into a temp DB and checks:
    * a method merely NAMED Register / RegisterType is not a DI registration (no di-unresolved
      ref); container calls still are (positive control: lines 34, 35, 37 stay);
    * an interface's GUID clause is its signature (literal kept verbatim);
    * `noreturn` is in a routine's directives;
    * is-never-true fires on every sealed shape: plain, nested, forward-declared as the tested
      value (line 45, the forward row as the is-target, is a known gap: see lane EXT REPORT); and stays silent with the rule off (positive control).
  Usage: pwsh -File tests\autotest\run_v151_EXT_facts.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$fx = Join-Path $PSScriptRoot 'fixtures\v151-EXT'
$db = Join-Path ([IO.Path]::GetTempPath()) ("v151-ext-" + [Guid]::NewGuid().ToString('N') + '.sqlite')
$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
  if ($ok) { Write-Host "[PASS] $name" } else { Write-Host "[FAIL] $name  ($detail)"; $script:fail++ }
}
function Rows([string]$q) {
  $j = (& $exePath sql --db $db --query $q --json 2>$null | Out-String | ConvertFrom-Json)
  return ,@($j.rows)
}
& $exePath index $fx --db $db *> $null

$di = Rows "SELECT start_line FROM refs WHERE kind = 'di-unresolved' ORDER BY start_line"
$diLines = ($di | ForEach-Object { $_[0] }) -join ','
Check 'di-unresolved only on container calls (34,35,37)' ($diLines -eq '34,35,37') "got [$diLines]"

$guid = Rows "SELECT signature FROM symbols WHERE kind = 'interface' AND name = 'IShFace'"
Check 'interface GUID literal is the signature' ($guid.Count -eq 1 -and $guid[0][0] -eq "'{6D0C5B1E-1A2B-4C3D-8E9F-0A1B2C3D4E5F}'") "got $($guid | ConvertTo-Json -Compress)"

$nr = Rows "SELECT directives FROM symbols WHERE name = 'Halt2' AND kind = 'procedure'"
Check 'noreturn recorded in directives' ($nr.Count -ge 1 -and ($nr | Where-Object { " $($_[0]) " -match ' noreturn ' })) "got $($nr | ConvertTo-Json -Compress)"

$sealed = Rows "SELECT name FROM symbols WHERE kind = 'class' AND directives = 'sealed' ORDER BY name"
$sealedNames = ($sealed | ForEach-Object { $_[0] }) -join ','
Check 'sealed recorded: plain, generic, nested, full row of the forward' ($sealedNames -eq 'TShFwd,TShGen,TShInner,TShPlain') "got [$sealedNames]"

$raw = & $exePath lint-all --db $db --rule is-never-true --json 2>$null | Out-String
$lines = @(($raw | ConvertFrom-Json) | Where-Object { $_.file_path -like '*uSealShapes.pas' } | ForEach-Object { $_.start_line } | Sort-Object) -join ','
Check 'is-never-true fires on the sealed shapes (41-44; 45 is the known forward-row gap)' ($lines -eq '41,42,43,44') "got [$lines]"

$off = & $exePath lint-all --db $db --json 2>$null | Out-String
$offN = @(($off | ConvertFrom-Json) | Where-Object { $_.rule -eq 'is-never-true' }).Count
Check 'positive control: is-never-true off by default answers nothing' ($offN -eq 0) "$offN finding(s)"

try { [IO.File]::Delete($db) } catch {}
if ($fail -gt 0) { Write-Host "FAIL ($fail)"; exit 1 }
Write-Host 'PASS'
exit 0
