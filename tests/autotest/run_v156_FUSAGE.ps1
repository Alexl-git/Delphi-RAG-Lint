#Requires -Version 7.3
<#
  run_v156_FUSAGE.ps1 -- lane FUSAGE (1.56): the engine sub-verb `repo field-usage --fields "A,B,C" --json`.
  Builds two fixture projects (a .pas and a .dfm each), indexes them with the engine under test, and checks
  the one-line JSON {"usage":[{"field":"ID","kinds":["dfm","grid","lookup","code"]}]} that the IDE plugin
  (Cmd.FieldRepo.ShowFieldsWithUsage / ApplyUsage) parses.
  Positive control: fixture B is fixture A minus one use per kind (the code use of ID, the grid column of
  ID); the kinds must drop exactly those words, so a verb that always answers the same kinds fails.
  A missing exe is a FAIL, never a skip. Exit 0 only when every check passes.
  Parameters: -Repo <root> (default: two levels above this script); -Exe <drag-lint.exe> (default: the Win64
              Debug build of this tree, src\cli\Win64\Debug\drag-lint.exe); -OutDir <dir> scratch (default: temp)
#>
[CmdletBinding()]
param([string]$Repo = '', [string]$Exe = '', [string]$OutDir = '')
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Exe) { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP "dl-fusage-$PID" }
$ErrorActionPreference = 'Stop'
Write-Host '== FUSAGE repo field-usage ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FUSAGE: FAIL -- engine not found: $Exe" -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS $Name" }
  else { $script:Fail++; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
function New-Fixture([string]$Dir, [bool]$WithIdCode, [bool]$WithIdGrid) {
  New-Item -ItemType Directory -Path $Dir -Force | Out-Null
  $pas = @('unit Unit1;', '', 'interface', '', 'implementation', '', 'uses', '  FireDAC.Comp.Client;', '',
    'procedure Touch(pQuery: TFDQuery);', 'begin')
  if ($WithIdCode) { $pas += "  pQuery.FieldByName('ID').AsInteger := 1;" }
  $pas += @("  pQuery.FieldByName('QTY').AsInteger := 2;", 'end;', '', 'end.')
  $dfm = @('object Form1: TForm1', '  Left = 0', '  object edtId: TDBEdit', '    Left = 8', "    DataField = 'ID'", '  end')
  if ($WithIdGrid) { $dfm += @('  object colId: TcxGridDBColumn', "    DataBinding.FieldName = 'ID'", '  end') }
  $dfm += @('  object lcbCity: TDBLookupComboBox', "    KeyField = 'CITY'", '  end', 'end')
  [IO.File]::WriteAllText((Join-Path $Dir 'Unit1.pas'), (($pas -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $Dir 'Unit1.dfm'), (($dfm -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
function Index-Fixture([string]$Dir, [string]$Db) {
  if (Test-Path -LiteralPath $Db) { [IO.File]::Delete($Db) }
  & { $ErrorActionPreference = 'Continue'; & $Exe index $Dir --db $Db *> (Join-Path $OutDir 'index.log') }
}
# The extractor rows of ds_field_accesses come from another lane (EXT); this runner seeds them from the fixture's
# own literal accesses so the verb is tested on the table shape, not on the extractor. -Fields = names to seed.
function Seed-Code([string]$Db, [string[]]$Names) {
  $py = Join-Path $OutDir 'seed.py'
  $lines = @('import sqlite3, sys', 'c = sqlite3.connect(sys.argv[1])',
    "f = c.execute(`"select id from files where path like '%Unit1.pas'`").fetchone()[0]",
    "s = c.execute('select id from symbols where file_id=? limit 1', (f,)).fetchone()[0]",
    'for i, n in enumerate(sys.argv[2:]):',
    "    c.execute('insert into ds_field_accesses values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', (f, s, i, 'read', 10 + i, 3, 'FieldByName', 'pQuery', n, n, 'literal', n, 'AsInteger', '', '', -1, '', 0, 0, 0, 0, 10 + i, 3))",
    'c.commit()')
  [IO.File]::WriteAllText($py, (($lines -join "`n") + "`n"), [Text.Encoding]::ASCII)
  & { $ErrorActionPreference = 'Continue'; & python -I $py $Db @Names *> (Join-Path $OutDir 'seed.log') }
  if ($LASTEXITCODE -ne 0) { Write-Host "FUSAGE: FAIL -- seeding code rows failed (see seed.log)" -ForegroundColor Red; exit 1 }
}
function Run-Usage([string[]]$UsageArgs) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe repo field-usage @UsageArgs 2>$null }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Lines = @($out | ForEach-Object { "$_" }) }
}
function Kinds($Parsed, [string]$Field) {
  $row = @($Parsed.usage | Where-Object { $_.field -eq $Field })
  if ($row.Count -eq 0) { return $null }
  return ($row[0].kinds -join ',')
}
$fxA = Join-Path $OutDir 'fxA'; $fxB = Join-Path $OutDir 'fxB'
$dbA = Join-Path $OutDir 'fxA.sqlite'; $dbB = Join-Path $OutDir 'fxB.sqlite'
New-Fixture $fxA $true $true
New-Fixture $fxB $false $false
Index-Fixture $fxA $dbA
Index-Fixture $fxB $dbB
Seed-Code $dbA @('ID', 'QTY')
Seed-Code $dbB @('QTY')

# A: ID = dfm control + grid column + code; QTY = code; CITY = lookup; NOPE unused
$a = Run-Usage @('--fields', 'ID, QTY,CITY,NOPE', '--json', '--db', $dbA)
Check 'A exit 0' ($a.Exit -eq 0) "exit=$($a.Exit)"
Check 'A one line' ($a.Lines.Count -eq 1) "lines=$($a.Lines.Count)"
$pa = $null
try { $pa = $a.Lines[0] | ConvertFrom-Json } catch { Write-Verbose 'not json' }
Check 'A parses as JSON with a usage array' ($null -ne $pa -and $null -ne $pa.PSObject.Properties['usage'])
if ($null -ne $pa) {
  Check 'A ID = dfm,grid,code' ((Kinds $pa 'ID') -eq 'dfm,grid,code') "got $(Kinds $pa 'ID')"
  Check 'A QTY = code' ((Kinds $pa 'QTY') -eq 'code') "got $(Kinds $pa 'QTY')"
  Check 'A CITY = lookup' ((Kinds $pa 'CITY') -eq 'lookup') "got $(Kinds $pa 'CITY')"
  Check 'A NOPE (unused) omitted' ($null -eq (Kinds $pa 'NOPE'))
  Check 'A field names upper-case, only usage key' (@($pa.PSObject.Properties).Count -eq 1)
}
# B: positive control -- the code use and the grid column of ID removed
$b = Run-Usage @('--fields', 'ID,QTY,CITY', '--json', '--db', $dbB)
$pb = $null
try { $pb = $b.Lines[0] | ConvertFrom-Json } catch { Write-Verbose 'not json' }
Check 'B parses' ($null -ne $pb)
if ($null -ne $pb) {
  Check 'B ID = dfm only (code + grid dropped)' ((Kinds $pb 'ID') -eq 'dfm') "got $(Kinds $pb 'ID')"
  Check 'B QTY, CITY unchanged' (((Kinds $pb 'QTY') -eq 'code') -and ((Kinds $pb 'CITY') -eq 'lookup'))
}
# lower-case request and duplicates give the same answer once
$c = Run-Usage @('--fields', 'id,ID,qty', '--json', '--db', $dbA)
$pc = $null
try { $pc = $c.Lines[0] | ConvertFrom-Json } catch { Write-Verbose 'not json' }
Check 'case-insensitive, duplicates folded' ($null -ne $pc -and @($pc.usage).Count -eq 2)
# nothing used -> still the shape
$d = Run-Usage @('--fields', 'NOPE', '--json', '--db', $dbA)
Check 'no use -> {"usage":[]}' (($d.Exit -eq 0) -and ($d.Lines.Count -eq 1) -and ($d.Lines[0] -eq '{"usage":[]}')) "got $($d.Lines -join '|')"
# plain text form
$e = Run-Usage @('--fields', 'ID,NOPE', '--db', $dbA)
Check 'plain text: ID: dfm, grid, code' (($e.Exit -eq 0) -and (@($e.Lines).Count -eq 1) -and ($e.Lines[0] -eq 'ID: dfm, grid, code')) "got $($e.Lines -join '|')"
# usage and failure exits
$f = Run-Usage @('--json', '--db', $dbA)
Check 'no --fields -> exit 2' ($f.Exit -eq 2) "exit=$($f.Exit)"
$g = Run-Usage @('--fields', 'ID', '--json', '--db', (Join-Path $OutDir 'missing.sqlite'))
Check 'missing index -> exit 1, no stdout' (($g.Exit -eq 1) -and ($g.Lines.Count -eq 0)) "exit=$($g.Exit)"
# the sub-verb is listed in the unknown-sub-verb message
$h = & { $ErrorActionPreference = 'Continue'; & $Exe repo no-such-verb 2>&1 | ForEach-Object { "$_" } }
Check 'sub-verb list names field-usage' ((($h -join ' ') -match 'field-usage')) "got $($h -join ' ')"
Write-Host "SUMMARY pass=$script:Pass fail=$script:Fail"
if ($script:Fail -ne 0) { Write-Host 'FUSAGE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FUSAGE: PASS' -ForegroundColor Green
exit 0
