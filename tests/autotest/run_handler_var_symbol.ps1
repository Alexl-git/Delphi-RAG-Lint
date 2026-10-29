<#
  run_handler_var_symbol.ps1 -- the `on E: T do` handler variable is a local_var
  symbol (item 4 of the untypable-receivers plan, lane X).

  DEFECT: the handler variable was never a symbol, so `E.Message` had nothing to
  type its receiver from. Now each `on E: T do` emits a local_var named E, parented
  to the enclosing routine, Signature = the type text as written, range = the
  handler clause. `on T do` (no variable) emits nothing.

  FIXTURE (tests\autotest\fixtures\handlervar\uHandlerVar.pas): RunTwo has two
  sibling handlers both named E (lines 21-22, 23-24); RunBare has `on Exception
  do` (no variable); RunShadow has a routine-level `var E: Integer` (line 42) AND a
  handler E (49-50).

  SECOND HALF (receiver_type_text of the E.Message rows = Exception) needs R1 in
  the tree: it is reported SKIP until then. A SKIP is NOT a pass -- INT must enable
  it once R1 is merged (set -RequireReceiverType).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-handler-var-$PID",
  [switch]$RequireReceiverType
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item "$PSScriptRoot\fixtures\handlervar\uHandlerVar.pas" $work -Force
$db = Join-Path $WorkDir 'hv.sqlite'
$null = & $Exe index $work --db $db --library-db none 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Q([string]$Sql) {
  $raw = & $Exe sql --db $db --json --query $Sql 2>$null | Out-String
  $j = $raw | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += [pscustomobject]$h
  }
  return ,$out
}
$rows = Q "select qualified_name qn, signature sig, start_line sl, end_line el from symbols where kind='local_var' and name='E' order by start_line"
Check 'four local_var rows named E (3 handlers + 1 routine var)' ($rows.Count -eq 4) "got $($rows.Count)"
if ($rows.Count -eq 4) {
  Check 'RunTwo handler 1: EConvertError, lines 21-24 clause' ($rows[0].qn -eq 'uHandlerVar.RunTwo.E' -and $rows[0].sig -eq 'EConvertError' -and $rows[0].sl -eq 21 -and $rows[0].el -eq 22) "$($rows[0].qn) $($rows[0].sig) $($rows[0].sl)-$($rows[0].el)"
  Check 'RunTwo handler 2: Exception'                          ($rows[1].qn -eq 'uHandlerVar.RunTwo.E' -and $rows[1].sig -eq 'Exception' -and $rows[1].sl -eq 23 -and $rows[1].el -eq 24) "$($rows[1].qn) $($rows[1].sig) $($rows[1].sl)-$($rows[1].el)"
  Check 'RunShadow routine var E: Integer (control)'           ($rows[2].qn -eq 'uHandlerVar.RunShadow.E' -and $rows[2].sig -eq 'Integer' -and $rows[2].sl -eq 42) "$($rows[2].qn) $($rows[2].sig) $($rows[2].sl)"
  Check 'RunShadow handler E: unit-qualified type kept'        ($rows[3].qn -eq 'uHandlerVar.RunShadow.E' -and $rows[3].sig -eq 'System.SysUtils.Exception' -and $rows[3].sl -eq 49 -and $rows[3].el -eq 50) "$($rows[3].qn) $($rows[3].sig) $($rows[3].sl)-$($rows[3].el)"
  Check 'handler clause ranges do not overlap' ($rows[0].el -lt $rows[1].sl)
}
$n = (Q "select s.id from symbols s join symbols p on p.id=s.parent_id where s.kind='local_var' and s.name='E' and p.name='RunBare'").Count
Check '`on Exception do` (RunBare) adds no local_var' ($n -eq 0) "got $n"
$n = (Q "select id from symbols where kind='local_var' and name='S'").Count
Check 'control: ordinary locals S still emitted (3)' ($n -eq 3) "got $n"

# Second half: needs R1 (receiver_type_text filled). SKIP-marked until INT enables it.
$typed = (Q "select id from refs where name_text='Message' and receiver_type_text='Exception'").Count
if ($RequireReceiverType) {
  Check 'E.Message rows carry receiver_type_text (needs R1)' ($typed -ge 1) "typed=$typed"
} else {
  Write-Host "  [SKIP] E.Message receiver_type_text = Exception (R1 not merged; typed=$typed). This half is INCAPABLE of failing until -RequireReceiverType." -ForegroundColor Yellow
}

if ($script:Failed) { Write-Host 'run_handler_var_symbol: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_handler_var_symbol: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
