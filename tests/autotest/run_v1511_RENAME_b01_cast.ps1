<#
  run_v1511_RENAME_b01_cast.ps1 -- B01 proof half (1.51.1): `rename --plan` decides an unbound member whose receiver is a
  HARD CAST `TEdit(FControls[i]).Text` by the cast type, instead of refusing [receiver-untyped].

  FIXTURE tests\autotest\fixtures\v1511-RENAME\b01: lib\LibCtl.pas is a miniature VCL (Text declared once, protected,
  in TControl; TEdit / TComboBox publish it); src\ holds the target uTok.TToken.Text and the casts in uUse.pas. The
  project is indexed WITHOUT the library, so the resolver binds none of the library casts (the shape of the C2 card on
  YADFOT: unbound, receiver "TEdit(FControls[i])"); the plan asks the library.
  CASES
    b1  the 4 casts to a library type (TEdit, TComboBox; write and read) are another symbol's: no refusal.
    b2  POSITIVE CONTROL: MakeCtl(FControls[i]).Text -- a ROUTINE call of the same shape -- still refuses [receiver-untyped].
    b3  the edits are exactly the target's: declaration + TToken / TTokenEx casts (no TEdit / TComboBox line).
    b4  one undecided occurrence in all (b2's).
  RED on 1.51.0-alpha: b1 (4 x [receiver-untyped]) and b4 (5 undecided).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-v1511-rename-b01-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = Join-Path $PSScriptRoot 'fixtures\v1511-RENAME\b01'
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Src = Join-Path $WorkDir 'src'
Copy-Item (Join-Path $Fx 'src') $Src -Recurse
Copy-Item (Join-Path $Fx 'lib') (Join-Path $WorkDir 'lib') -Recurse
$Db  = Join-Path $WorkDir 'fx.sqlite'
$Lib = Join-Path $WorkDir 'lib.sqlite'
function LineOf([string]$Needle) {
  $i = 0; foreach ($l in [IO.File]::ReadAllLines((Join-Path $Src 'uUse.pas'))) { $i++; if ($l.Contains($Needle)) { return $i } }
  return 0
}
Push-Location $WorkDir
try {
  $null | & $Exe index (Join-Path $WorkDir 'lib') --db $Lib --library-db none *> "$Lib.log"
  $null | & $Exe index $Src --db $Db --library-db none *> "$Db.log"
  $o = ($null | & $Exe rename --kind symbol --name uTok.TToken.Text --to Caption --db $Db --library-db $Lib --plan --json 2>$null | Out-String)
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  Check 'b0 the plan is JSON' ($null -ne $j) $o
  $ref = @($j.refusals)
  $castLines = @((LineOf 'kEdit : TEdit('), (LineOf 'kCombo: TComboBox('), (LineOf 'AValue:= TEdit('), (LineOf 'AValue:= TComboBox('))
  $castRefused = @($ref | Where-Object { $castLines -contains [int]$_.line })
  Check 'b1 the 4 library-type casts are decided: no refusal on their lines' ($castRefused.Count -eq 0) ($castRefused | ConvertTo-Json -Compress)
  $mk = @($ref | Where-Object { [int]$_.line -eq (LineOf 'MakeCtl(') })
  Check 'b2 POSITIVE CONTROL: the routine call MakeCtl(...).Text still refuses [receiver-untyped]' ($mk.Count -eq 1 -and $mk[0].kind -eq 'receiver-untyped') $o
  $lines = @($j.edits | ForEach-Object { [int]$_.line } | Sort-Object)
  $want  = @(8, (LineOf 'kTok  : TToken('), (LineOf 'kTokEx: TTokenEx('), (LineOf 'AValue:= TToken(')) | Sort-Object
  Check 'b3 the edits are the target''s only (declaration, TToken / TTokenEx casts)' (($lines -join ',') -eq ($want -join ',')) "edits: $($lines -join ',') want: $($want -join ',')"
  Check 'b4 one undecided occurrence in all' ($ref.Count -eq 1) "refusals: $($ref.Count)"
} finally { Pop-Location }
Write-Host ("run_v1511_RENAME_b01_cast: {0} pass, {1} fail" -f $script:Passed, $script:FailCount)
try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: $WorkDir not deleted" }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
