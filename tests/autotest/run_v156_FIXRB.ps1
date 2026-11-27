<#
  run_v156_FIXRB.ps1 -- 1.56 fix lane FIXR-B: the extraction findings of REV-1 (#2, #6, #13).

  Indexes tests\fixtures\v156\FIXRB\* into scratch DBs and reads them through `sql --json` (rows are
  POSITIONAL arrays; mapped onto columns[].name below).

    M   (#2) the except-context memo of DRagLint.Index.DataFlowExc is keyed on the WALK, not on tree
        addresses. Three units of the same length and shape differ only in the handled class; each
        `on E: T do` row must name ITS class. Address reuse cannot be forced from outside, so the run
        sets DRAGLINT_DFX_TEST_REUSE=1: the RED-proof engine (the commit before the fix) reads it as
        "every tree and routine node is at the cached address" and then serves uExcBB / uExcCC the
        contexts of uExcAA. The fixed engine does not read the variable at all.
        Positive control: -Exe <the RED-proof engine> -- M2 and M3 FAIL (src_name EFooErr).
    C   (#6) the declared scalar class of a field / function result comes from the SCOPE that declares
        it (owner type + name). C-WRONG rows carried the class of a same-named function of the unit;
        C-OWN rows had no class because another class declares the name with another type.
        Positive control: -Exe <the base engine ffbbc5972> -- C-WRONG and C-OWN FAIL; the C-KEEP rows
        (the receiver's type does declare the function) pass on both.
    I   (#13) idx_refs_file_line: a writable open by a verb that is no index run does not build it on
        an existing DB; the next index run does. Needs python (sqlite3) on PATH to drop the index.
        Positive control: -Exe <the base engine> -- I2 FAILS (Migrate builds it at once).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_FIXRB: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_FIXRB: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fx   = Join-Path $repo 'tests\fixtures\v156\FIXRB'
$work = Join-Path $env:TEMP ('dl-v156-fixrb-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name); a failed query returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $Query --db $Db --json 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()
}
function Lane-Index([string]$Dir, [string]$Db, [string]$LogName) {
  $log = Join-Path $work $LogName
  & { $ErrorActionPreference = 'Continue'; & $Exe index $Dir --db $Db *> $log }
  return $LASTEXITCODE
}
# an EMPTY row set arrives as $null: it must not count as one row
function Has($rs, [scriptblock]$p) { @(@($rs) | Where-Object { $null -ne $_ } | Where-Object $p).Count -gt 0 }
$rowSql = "SELECT s.name AS routine, d.dst_kind, d.dst_line, d.dst_name, d.src_kind, d.src_line, d.src_name, d.val_class " +
          "FROM data_flows d JOIN symbols s ON s.id = d.symbol_id LIMIT 100000"

try {
  # ---- M: the except-context memo (#2) ------------------------------------------------------
  Write-Host 'M  except-context memo is per walk (REV-1 #2)' -ForegroundColor Cyan
  $srcM = Join-Path $work 'exc'
  Copy-Item (Join-Path $fx 'exc') $srcM -Recurse
  $sizes = @(Get-ChildItem $srcM -Filter '*.pas' | ForEach-Object { $_.Length } | Sort-Object -Unique)
  Check 'M0 the three units have ONE length (fixture input: same shape, same ranges)' ($sizes.Count -eq 1) "sizes=[$($sizes -join ',')]"
  $dbM = Join-Path $work 'm.sqlite'
  $old = $env:DRAGLINT_DFX_TEST_REUSE
  $env:DRAGLINT_DFX_TEST_REUSE = '1'
  try { $rc = Lane-Index $srcM $dbM 'index-m.log' } finally { $env:DRAGLINT_DFX_TEST_REUSE = $old }
  Check 'M index exits 0' ($rc -eq 0) "rc=$rc"
  $ex = @(Lane-Sql $dbM $rowSql | Where-Object { $_.src_kind -eq 'except' })
  Check 'M1 uExcAA: the handler row names EFooErr (POSITIVE CONTROL: except rows exist)' (Has $ex { $_.routine -eq 'RunAA' -and $_.src_name -eq 'EFooErr' }) "rows=$($ex.Count)"
  Check 'M2 uExcBB: the handler row names EBarErr, not the class of the unit walked before it' ((Has $ex { $_.routine -eq 'RunBB' -and $_.src_name -eq 'EBarErr' }) -and -not (Has $ex { $_.routine -eq 'RunBB' -and $_.src_name -ne 'EBarErr' })) "got=[$((@($ex | Where-Object { $_.routine -eq 'RunBB' }) | ForEach-Object { $_.src_name }) -join ',')]"
  Check 'M3 uExcCC: the handler row names EQuxErr' ((Has $ex { $_.routine -eq 'RunCC' -and $_.src_name -eq 'EQuxErr' }) -and -not (Has $ex { $_.routine -eq 'RunCC' -and $_.src_name -ne 'EQuxErr' })) "got=[$((@($ex | Where-Object { $_.routine -eq 'RunCC' }) | ForEach-Object { $_.src_name }) -join ',')]"

  # ---- C: scope-keyed declared classes (#6) ---------------------------------------------------
  Write-Host 'C  declared scalar class by declaring scope (REV-1 #6)' -ForegroundColor Cyan
  $srcC = Join-Path $work 'cls'
  Copy-Item (Join-Path $fx 'cls') $srcC -Recurse
  $M = @{}
  $ln = 0
  foreach ($line in [IO.File]::ReadAllLines((Join-Path $srcC 'uFixRbCls.pas'))) {
    $ln++
    $hit = [regex]::Match($line, '\{ (M-[A-Z-]+) \}')
    if ($hit.Success) { $M[$hit.Groups[1].Value] = $ln }
  }
  Check 'C0 fixture markers found (fixture input)' ($M.Count -eq 11) "markers=$($M.Count)"
  $dbC = Join-Path $work 'c.sqlite'
  $rc = Lane-Index $srcC $dbC 'index-c.log'
  Check 'C index exits 0' ($rc -eq 0) "rc=$rc"
  $all = @(Lane-Sql $dbC $rowSql | Where-Object { $_.dst_kind -eq 'arg' })
  function At([string]$Mark) { @($all | Where-Object { $_.dst_line -eq $M[$Mark] }) }
  function Classes([string]$Mark) { "classes=[$((At $Mark | ForEach-Object { "$($_.src_kind):$($_.src_name):$($_.val_class)" }) -join ' ')]" }

  Check 'C-WRONG pOther.Total (a string property of TOther): POSITIVE CONTROL -- the receiver row exists' (Has (At 'M-OTHER') { $_.src_kind -eq 'param' -and $_.val_class -eq '' }) (Classes 'M-OTHER')
  Check 'C-WRONG pOther.Total gets NO class from TOrderA.Total: Currency' (-not (Has (At 'M-OTHER') { $_.val_class -ne '' })) (Classes 'M-OTHER')
  Check 'C-WRONG pRec.CharLength (a string record field): POSITIVE CONTROL -- the receiver row exists' (Has (At 'M-REC') { $_.src_kind -eq 'param' -and $_.val_class -eq '' }) (Classes 'M-REC')
  Check 'C-WRONG pRec.CharLength gets NO class from the unit function CharLength: Integer' (-not (Has (At 'M-REC') { $_.val_class -ne '' })) (Classes 'M-REC')
  Check 'C-WRONG FOther.Total (field of type TOther): POSITIVE CONTROL -- the pre-1.56 ref row exists' (Has (At 'M-FIELD-OTHER') { $_.src_kind -eq 'ref' -and $_.src_name -eq 'Total' -and $_.val_class -eq '' }) (Classes 'M-FIELD-OTHER')
  Check 'C-WRONG FOther.Total gets NO class' (-not (Has (At 'M-FIELD-OTHER') { $_.val_class -ne '' })) (Classes 'M-FIELD-OTHER')

  Check 'C-KEEP pOrder.Total (TOrderA declares Total: Currency): value row, val_class currency' (Has (At 'M-SELF') { $_.src_kind -eq 'ref' -and $_.src_name -eq 'Total' -and $_.val_class -eq 'currency' }) (Classes 'M-SELF')
  Check 'C-KEEP FSelf.Total (field of type TOrderA): value row, val_class currency' (Has (At 'M-FIELD-SELF') { $_.src_kind -eq 'ref' -and $_.src_name -eq 'Total' -and $_.val_class -eq 'currency' }) (Classes 'M-FIELD-SELF')
  Check 'C-KEEP bare Total inside a TOrderA method: value row, val_class currency' (Has (At 'M-OWN-BARE') { $_.src_kind -eq 'ref' -and $_.val_class -eq 'currency' }) (Classes 'M-OWN-BARE')
  Check 'C-KEEP bare CharLength (the unit function): value row, val_class int' (Has (At 'M-BARE') { $_.src_kind -eq 'ref' -and $_.val_class -eq 'int' }) (Classes 'M-BARE')
  Check 'C-KEEP the unit variable GRate: Currency keeps its class beside a local GRate: string elsewhere' (Has (At 'M-GLOBAL') { $_.src_kind -eq 'global' -and $_.val_class -eq 'currency' }) (Classes 'M-GLOBAL')
  Check 'C-KEEP the local GRate: string: POSITIVE CONTROL -- the parameter reaches the sink through it' (Has (At 'M-LOCAL') { $_.src_kind -eq 'param' -and $_.val_class -eq '' }) (Classes 'M-LOCAL')
  Check 'C-KEEP the local GRate: string has no class' (-not (Has (At 'M-LOCAL') { $_.val_class -ne '' })) (Classes 'M-LOCAL')

  Check 'C-OWN TOrderA.FCode: Integer: POSITIVE CONTROL -- the pre-1.56 field row is kept' (Has (At 'M-CODE-A') { $_.src_kind -eq 'field' -and $_.src_name -eq 'FCode' -and $_.val_class -eq '' }) (Classes 'M-CODE-A')
  Check 'C-OWN TOrderA.FCode: Integer: a value row of ITS class (int), though TOrderB.FCode is a string' (Has (At 'M-CODE-A') { $_.src_kind -eq 'field' -and $_.val_class -eq 'int' }) (Classes 'M-CODE-A')
  Check 'C-OWN TOrderB.FCode: string: the field row exists and has no class' ((Has (At 'M-CODE-B') { $_.src_kind -eq 'field' -and $_.val_class -eq '' }) -and -not (Has (At 'M-CODE-B') { $_.val_class -ne '' })) (Classes 'M-CODE-B')

  # ---- I: idx_refs_file_line is built by an index run (#13) --------------------------------------
  Write-Host 'I  idx_refs_file_line is built by an index run only (REV-1 #13)' -ForegroundColor Cyan
  $py = Join-Path $work 'idx.py'
  [IO.File]::WriteAllText($py, @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
if len(sys.argv) > 2 and sys.argv[2] == 'drop':
    c.execute('DROP INDEX IF EXISTS idx_refs_file_line')
    c.commit()
print(c.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_refs_file_line'").fetchone()[0])
'@)
  function Idx([string]$Db, [string]$Verb = '') {
    $o = & { $ErrorActionPreference = 'Continue'; if ($Verb) { & python.exe -I $py $Db $Verb 2>&1 } else { & python.exe -I $py $Db 2>&1 } }
    return ("$o").Trim()
  }
  Check 'I0 a new DB has the index after its first index run (POSITIVE CONTROL)' ((Idx $dbC) -eq '1') "idx=$(Idx $dbC)"
  Check 'I1 the index is dropped (fixture input: a DB of an older engine)' ((Idx $dbC 'drop') -eq '0')
  $log = Join-Path $work 'tsf.log'
  & { $ErrorActionPreference = 'Continue'; & $Exe test-store-freshness --db $dbC *> $log }
  Check 'I2 a writable open that is no index run (test-store-freshness) exits 0 and does NOT build it' (($LASTEXITCODE -eq 0) -and ((Idx $dbC) -eq '0')) "rc=$LASTEXITCODE idx=$(Idx $dbC)"
  $rc = Lane-Index $srcC $dbC 'index-c2.log'
  Check 'I3 the next index run builds it' (($rc -eq 0) -and ((Idx $dbC) -eq '1')) "rc=$rc idx=$(Idx $dbC)"
}
finally {
  if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } }
  else { Write-Host "scratch kept: $work" }
}

Write-Host ''
Write-Host "run_v156_FIXRB: $($script:pass) passed, $($script:fail) failed" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
