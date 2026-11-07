# run_taint_f1.ps1 -- 1.45 lane lc: taint-sql-injection on index fact F1 (ref_types + ref_receivers).
#
# Fixture tests\lint-project\taint-f1\uF1.pas. A dotted receiver (`Self.FEdit.Text`) used to be untyped:
# a source by the SPELLING of its receiver (weak, warning), a typed sink (`Self.FConn.ExecSQL`) matched
# weakly. With F1 the receiver ref's static type decides:
#   39  Self.FEdit.Text      FEdit: TEdit            -> error (certain source, catalogued TEdit.Text)
#   44  Self.FFancy.Text     FFancy: TFancyEdit      -> error (descends TCustomEdit; the spelling gave no hit at all)
#   49  Self.ParamsLabel.Text ParamsLabel: TLabel    -> NO finding (a label named like a parameter is no source)
#   54  Self.edtMystery.Text no declaration          -> warning (control: unknown type keeps today's weak source)
#   59  Self.FConn.ExecSQL(ParamStr(1)) FConn: TFDConnection -> error (typed dotted sink)
# NO-FACTS RUN: the same index with ref_types and ref_receivers renamed away (the table is then absent,
# as in an index older than 1.44) must answer EXACTLY as the engine without F1 did
# (39 w, 44 none, 49 w, 54 w, 59 w). That run is also the positive control: the assertions above cannot
# pass on the old logic, and the no-facts run cannot pass on the new logic.
#
# Usage: pwsh -File tests\autotest\run_taint_f1.ps1 [-Exe <drag-lint.exe>]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$fx  = Join-Path $repo 'tests\lint-project\taint-f1'
$tmp = Join-Path $env:TEMP "taint_f1_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$db = Join-Path $tmp 'f1.sqlite'; $bare = Join-Path $tmp 'nofacts.sqlite'
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function Sev([string]$Database) {
  $raw = & $exePath lint-all --db $Database --json --quiet 2>$null
  $t = $raw -join "`n"; $b = $t.IndexOf('[')
  $m = @{}
  if ($b -ge 0) { foreach ($f in @($t.Substring($b) | ConvertFrom-Json)) { if ($f.rule -eq 'taint-sql-injection') { $m[[int]$f.start_line] = $f.severity } } }
  return $m
}
Push-Location $env:TEMP
try {
  & $exePath index $fx --db $db 2>&1 | Out-Null
  [IO.File]::Copy($db, $bare, $true)
  $away = 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("ALTER TABLE ref_types RENAME TO x_rt"); c.execute("ALTER TABLE ref_receivers RENAME TO x_rr"); c.commit(); print("ok")'
  $n = (& python -I -c $away $bare 2>&1) -join ' '
  Check 'no-facts copy: ref_types and ref_receivers renamed away' ($n -eq 'ok') $n
  $with = Sev $db
  Check 'F1 39 Self.FEdit.Text -> error'                 ($with[39] -eq 'error') "got $($with[39])"
  Check 'F1 44 TFancyEdit descends TCustomEdit -> error' ($with[44] -eq 'error') "got $($with[44])"
  Check 'F1 49 TLabel named ParamsLabel -> no finding'   (-not $with.ContainsKey(49)) "got $($with[49])"
  Check 'F1 54 unknown receiver type -> still weak'      ($with[54] -eq 'warning') "got $($with[54])"
  Check 'F1 59 typed dotted sink Self.FConn.ExecSQL -> error' ($with[59] -eq 'error') "got $($with[59])"
  $old = Sev $bare
  Check 'no facts 39 as before (warning)' ($old[39] -eq 'warning') "got $($old[39])"
  Check 'no facts 44 as before (none)'    (-not $old.ContainsKey(44)) "got $($old[44])"
  Check 'no facts 49 as before (warning)' ($old[49] -eq 'warning') "got $($old[49])"
  Check 'no facts 54 as before (warning)' ($old[54] -eq 'warning') "got $($old[54])"
  Check 'no facts 59 as before (warning)' ($old[59] -eq 'warning') "got $($old[59])"
} finally {
  Pop-Location
  [IO.Directory]::Delete($tmp, $true)
}
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host 'ALL PASS'
