<#
  run_convert_apply_tail_unit.ps1 -- E-CONVERT-TAIL-UNIT (wave 147, C1).

  THE DEFECT. `#convert TOldBtn -> TNewBtn, LibNew, Extra` parsed the tail units
  (TConversionRule.UnitsAdd) and docs\CONVERSION-RULES.md says "ADD = ... every
  #convert trailing unit", but convert-apply added only the unit that DECLARES the
  To type: Extra never reached the uses clause (dry run and --apply alike).

  THE CONTRACT: every tail unit of a #convert rule whose To type the unit's
  conversion produced is added to the uses clause once (case-insensitive, never a
  duplicate); a tail unit the unit already uses is not added twice; a #convert
  rule that converts nothing in the unit adds nothing.
  CONTROLS: the declaring unit still lands; an unmatched rule's tail does not; the
  bytes (--apply) are read back, not the plan.

  Fixture written fresh under $WorkDir. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_tail_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null
function P([string]$n) { return (Join-Path $WorkDir $n) }
function W([string]$n, [string]$t) { [IO.File]::WriteAllText((P $n), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function GetTxt([string]$n) { return [IO.File]::ReadAllText((P $n)) }

W 'LibOld.pas' "unit LibOld;`n`ninterface`n`nuses`n  Classes;`n`ntype`n  TOldBtn = class(TComponent)`n  end;`n  TUnusedBtn = class(TComponent)`n  end;`n`nimplementation`n`nend.`n"
W 'LibNew.pas' "unit LibNew;`n`ninterface`n`nuses`n  Classes;`n`ntype`n  TNewBtn = class(TComponent)`n  end;`n  TOtherBtn = class(TComponent)`n  end;`n`nimplementation`n`nend.`n"
W 'Extra.pas'  "unit Extra;`n`ninterface`n`nimplementation`n`nend.`n"
W 'Extra2.pas' "unit Extra2;`n`ninterface`n`nimplementation`n`nend.`n"
W 'F1.pas' "unit F1;`n`ninterface`n`nuses`n  Classes, LibOld;`n`ntype`n  TF1 = class(TComponent)`n    b1: TOldBtn;`n  end;`n`nimplementation`n`n{`$R *.dfm}`n`nend.`n"
W 'F1.dfm' "object F1: TF1`n  object b1: TOldBtn`n  end`nend`n"
W 'P.dpr' "program P;`n`nuses`n  LibOld, LibNew, Extra, Extra2, F1;`n`nbegin`nend.`n"
W 'a.rules' "#convert TOldBtn -> TNewBtn, LibNew, Extra`n#unuse LibOld`n"
W 'b.rules' "#convert TOldBtn -> TNewBtn, LibNew`n#unuse LibOld`n"
W 'c.rules' "#convert TOldBtn -> TNewBtn, LibNew, Extra`n#convert TUnusedBtn -> TOtherBtn, Extra2`n#unuse LibOld`n"
W 'd.rules' "#convert TOldBtn -> TNewBtn, LibNew, extra, Extra`n#unuse LibOld`n"

$db = P 't.sqlite'
& $Exe index --project (P 'P.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db)

function Apply([string]$Rules, [bool]$Write) {
  $a = @('convert-apply', '--unit', (P 'F1.pas'), '--rules', (P $Rules), '--db', $db)
  if ($Write) { $a += @('--apply', '--no-backup', '--no-reindex') }
  $o = (& $Exe @a 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function UsesLine([string]$t) { if ($t -match '(?s)\buses\s+(.*?);') { return ($Matches[1] -replace '\s+', ' ') }; return '<none>' }

$orig = GetTxt 'F1.pas'
# dry run
$r = Apply 'a.rules' $false
Check 'D1 dry run: exit 0, LibNew AND Extra planned as adds' (($r.Code -eq 0) -and ($r.Out -match 'add LibNew') -and ($r.Out -match 'add Extra\b')) $r.Out
Check 'D2 dry run wrote nothing' ((GetTxt 'F1.pas') -eq $orig)
# bytes
$r = Apply 'a.rules' $true
$u = UsesLine (GetTxt 'F1.pas')
Check 'B1 --apply: exit 0' ($r.Code -eq 0) $r.Out
Check 'B2 bytes: the interface uses holds LibNew and Extra, not LibOld' (($u -match '\bLibNew\b') -and ($u -match '\bExtra\b') -and ($u -notmatch '\bLibOld\b')) $u
Check 'B3 bytes: Extra appears once' (([regex]::Matches((GetTxt 'F1.pas'), '\bExtra\b')).Count -eq 1) (GetTxt 'F1.pas')
# controls: a fresh unit each time
function Fresh() { W 'F1.pas' $orig.Replace("`r`n", "`n"); W 'F1.dfm' "object F1: TF1`n  object b1: TOldBtn`n  end`nend`n"; & $Exe index --project (P 'P.dpr') --db $db 2>&1 | Out-Null }
Fresh
$r = Apply 'b.rules' $true
$u = UsesLine (GetTxt 'F1.pas')
Check 'C1 CONTROL no tail unit in the rule: LibNew lands, Extra does not' (($u -match '\bLibNew\b') -and ($u -notmatch '\bExtra\b')) ($u + $r.Out)
Fresh
$r = Apply 'c.rules' $true
$u = UsesLine (GetTxt 'F1.pas')
Check 'C2 CONTROL a rule that converts nothing here adds no tail (Extra2 absent), the matching rule''s Extra lands' (($u -match '\bExtra\b') -and ($u -notmatch '\bExtra2\b')) ($u + $r.Out)
Fresh
$r = Apply 'd.rules' $true
Check 'C3 a tail unit named twice (case differs) is added once' (([regex]::Matches((GetTxt 'F1.pas'), '(?i)\bExtra\b')).Count -eq 1) (GetTxt 'F1.pas')
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
