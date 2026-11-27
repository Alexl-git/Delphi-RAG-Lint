<#
  run_v156_EXTB1_valclass.ps1 -- 1.56 lane EXT-B1 (B3): numeric / Boolean / date-time values in data_flows.

  Indexes tests\fixtures\v156-extb1 into a scratch DB and checks, through `sql --json` (rows are
  POSITIONAL arrays; mapped onto columns[].name below):
    V1  value rows exist: an Integer / TDateTime parameter reaching a call argument, a product of two
        field reads written through a Double local, a Boolean derived from a string, Length(), a
        loop accumulation into a Currency local, Inc(X, D), a var Integer argument (argout).
    V2  every value row carries one of the DF_VAL_* classes this lane emits
        (int / float / currency / datetime / bool); a pre-1.56 row keeps val_class ''.
    V3  NEGATIVE: a pure string routine has no value row; a killed scalar assignment does not reach.
    V4  (-BaseExe <the engine built from the lane base>) the rows with val_class '' are EXACTLY
        the base engine's rows for the same fixture (nothing removed, nothing altered, nothing added
        to the old set).
    V5  hook seam: with DRAGLINT_TEST_V156_DFHOOK=1 the unit's self-test hooks (statement hook on
        `raise`, expression hook on `.AsFloat`, write hook) add 'raise' / 'dsfield' rows; without the
        variable there is none.
  Positive control: run with -Exe <the base engine> -- V1 FAILS (no value rows at all).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_EXTB1_valclass: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_EXTB1_valclass: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-extb1'
$work  = Join-Path $env:TEMP ('dl-v156-extb1-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name); a failed query returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query, [string]$With = $Exe) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $With sql --query $Query --db $Db --json 2>$null }
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
function Lane-Index([string]$Dir, [string]$Db, [string]$LogName, [bool]$Hook, [string]$With = $Exe) {
  $log = Join-Path $work $LogName
  if ($Hook) { $env:DRAGLINT_TEST_V156_DFHOOK = '1' }
  try { & { $ErrorActionPreference = 'Continue'; & $With index $Dir --db $Db *> $log } }
  finally { if ($Hook) { $env:DRAGLINT_TEST_V156_DFHOOK = $null } }
  return $LASTEXITCODE
}
$rowSql = "SELECT s.name AS routine, d.dst_kind, d.dst_line, d.dst_col, d.dst_index, d.dst_name, d.dst_receiver, " +
          "d.src_kind, d.src_index, d.src_line, d.src_col, d.src_name, d.via_local, d.cond, d.val_class " +
          "FROM data_flows d JOIN symbols s ON s.id = d.symbol_id LIMIT 100000"
function Has($rs, [scriptblock]$p) { @($rs | Where-Object $p).Count -gt 0 }
function Row-Key($r) { "$($r.routine)|$($r.dst_kind)|$($r.dst_line)|$($r.dst_col)|$($r.dst_index)|$($r.dst_name)|$($r.dst_receiver)|$($r.src_kind)|$($r.src_index)|$($r.src_line)|$($r.src_col)|$($r.src_name)|$($r.via_local)|$($r.cond)" }

try {
  $src = Join-Path $work 'src'
  Copy-Item $fxSrc $src -Recurse
  $probe = Join-Path $src 'uExtB1.pas'
  $M = @{}
  $ln = 0
  foreach ($line in [IO.File]::ReadAllLines($probe)) {
    $ln++
    $hit = [regex]::Match($line, '\{ (M-[A-Z-]+) \}')
    if ($hit.Success) { $M[$hit.Groups[1].Value] = $ln }
  }
  Check 'fixture markers found (fixture input)' ($M.Count -ge 14) "markers=$($M.Count)"

  $db = Join-Path $work 'a.sqlite'
  $rc = Lane-Index $src $db 'index-a.log' $false
  Check 'index exits 0' ($rc -eq 0) "rc=$rc"
  $all = @(Lane-Sql $db $rowSql)
  Check 'data_flows has rows at all (POSITIVE CONTROL for every negative below)' ($all.Count -gt 0) "rows=$($all.Count)"
  $val = @($all | Where-Object { $_.val_class -ne '' })
  $old = @($all | Where-Object { $_.val_class -eq '' })
  function Of([string]$Routine) { @($all | Where-Object { $_.routine -eq $Routine -or $_.routine -like "*.$Routine" }) }

  Write-Host 'V1 value rows' -ForegroundColor Cyan
  Check 'IntArg: Integer param -> SinkI argument, val_class int, direct' (Has (Of 'IntArg') { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'SinkI' -and $_.dst_line -eq $M.'M-INT' -and $_.dst_index -eq 0 -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq 'int' -and $_.via_local -eq 0 -and $_.cond -eq 0 })
  Check 'StampArg: TDateTime param -> SinkD argument, val_class datetime' (Has (Of 'StampArg') { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-DATE' -and $_.src_kind -eq 'param' -and $_.val_class -eq 'datetime' })
  Check 'FloatMul: d := Q.A.AsFloat * Q.B.AsFloat; M.T.AsFloat := d -> write row, val_class float, via local' (Has (Of 'FloatMul') { $_.dst_kind -eq 'write' -and $_.dst_name -eq 'AsFloat' -and $_.dst_receiver -eq 'M.T' -and $_.dst_line -eq $M.'M-MUL-DST' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq 'float' -and $_.via_local -eq 1 })
  Check 'IsBlank: Result := S = '''' -> result row from the string param, val_class bool' (Has (Of 'IsBlank') { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq 'bool' })
  Check 'LenOf: Result := Length(S) -> result row from the string param, val_class int' (Has (Of 'LenOf') { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq 'int' })
  Check 'SumUp: Total := Total + Q.Amount.AsCurrency in a loop -> result row, val_class currency, via local, cond 1' (Has (Of 'SumUp') { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq 'currency' -and $_.via_local -eq 1 -and $_.cond -eq 1 })
  Check 'CountUp: Inc(Cnt, Step) -> result row from Step, val_class int' (Has (Of 'CountUp') { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq 'int' })
  $t = @((Of 'Mixed') | Where-Object { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-MIXED' })
  Check 'Mixed: the string param row keeps val_class empty' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq '' })
  Check 'Mixed: the Integer param reaches the same sink as a value row (int)' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 1 -and $_.val_class -eq 'int' })
  Check 'ParseIt: TryStrToInt(S, N); SinkI(N) -> argout source, val_class int' (Has (Of 'ParseIt') { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-TRY-SINK' -and $_.src_kind -eq 'argout' -and $_.src_index -eq 1 -and $_.src_line -eq $M.'M-TRY' -and $_.val_class -eq 'int' })

  Write-Host 'V2 classes' -ForegroundColor Cyan
  $classes = @($all | ForEach-Object { $_.val_class } | Sort-Object -Unique)
  $bad = @($classes | Where-Object { $_ -notin @('', 'int', 'float', 'currency', 'datetime', 'bool') })
  Check 'every val_class is one this lane emits' ($bad.Count -eq 0) "classes=[$($classes -join ',')]"
  Check 'the fixture shows all five classes' (@($classes | Where-Object { $_ -ne '' }).Count -eq 5) "classes=[$($classes -join ',')]"

  Write-Host 'V3 negatives' -ForegroundColor Cyan
  $t = Of 'Plain'
  Check 'Plain: POSITIVE CONTROL -- the string rows exist' (@($t).Count -eq 2) "rows=$(@($t).Count)"
  Check 'NEGATIVE: Plain (strings only) has no value row' (-not (Has $t { $_.val_class -ne '' }))
  $t = @((Of 'KillInt') | Where-Object { $_.dst_line -eq $M.'M-KILL' })
  Check 'KillInt: POSITIVE CONTROL -- B reaches the sink' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 1 -and $_.val_class -eq 'int' })
  Check 'NEGATIVE: KillInt: the overwritten A does not reach the sink' (-not (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 0 }))
  # v156 INT: since EXT-B2 (raise) and EXT-B3 (dsfield) are merged the REAL emitters write these kinds in a plain run;
  # the old negative ('none without the self-test hooks') held only for an engine with EXT-B1 alone.
  $real = @($all | Where-Object { $_.dst_kind -in @('raise', 'dsfield') -or $_.src_kind -eq 'dsfield' })
  Check 'plain run: the real emitters (EXT-B2 raise, EXT-B3 dsfield) write their rows' ($real.Count -gt 0) "rows=$($real.Count)"

  if ($BaseExe -ne '') {
    Write-Host 'V4 the old row set is untouched' -ForegroundColor Cyan
    $dbB = Join-Path $work 'base.sqlite'
    $rcB = Lane-Index $src $dbB 'index-base.log' $false $BaseExe
    $base = @(Lane-Sql $dbB $rowSql $BaseExe)
    Check 'base engine indexed the fixture and wrote rows (POSITIVE CONTROL)' ($rcB -eq 0 -and $base.Count -gt 0) "rc=$rcB rows=$($base.Count)"
    $kb = @($base | ForEach-Object { Row-Key $_ } | Sort-Object)
    $kn = @($old | ForEach-Object { Row-Key $_ } | Sort-Object)
    $d = @(Compare-Object $kb $kn)
    Check 'rows with val_class empty == the base engine''s rows (set diff 0)' ($d.Count -eq 0 -and $kb.Count -eq $kn.Count) "base=$($kb.Count) new-old-set=$($kn.Count) diff=$($d.Count) $(($d | Select-Object -First 3 | ForEach-Object { $_.SideIndicator + $_.InputObject }) -join ' ; ')"
    Check 'value rows are additions' ($val.Count -gt 0 -and $all.Count -eq $kb.Count + $val.Count) "all=$($all.Count) base=$($kb.Count) value=$($val.Count)"
  }

  Write-Host 'V5 hook seam' -ForegroundColor Cyan
  $dbH = Join-Path $work 'hook.sqlite'
  $rcH = Lane-Index $src $dbH 'index-hook.log' $true
  $hk = @(Lane-Sql $dbH $rowSql)
  $t = @($hk | Where-Object { $_.routine -eq 'Hooked' })
  Check 'hook run exits 0' ($rcH -eq 0) "rc=$rcH"
  Check 'expression hook: the dsfield source born at .AsFloat reaches the write through d' (Has $t { $_.dst_kind -eq 'write' -and $_.dst_line -eq $M.'M-HOOK-WRITE' -and $_.src_kind -eq 'dsfield' -and $_.src_line -eq $M.'M-HOOK-READ' -and $_.val_class -eq 'float' -and $_.via_local -eq 1 })
  Check 'write hook: a dsfield destination row at the accessor write' (Has $t { $_.dst_kind -eq 'dsfield' -and $_.dst_line -eq $M.'M-HOOK-WRITE' -and $_.dst_receiver -eq 'M.T' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 })
  Check 'statement hook: Msg reaches the raise (dst raise, argument 0)' (Has $t { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-HOOK-RAISE' -and $_.dst_index -eq 0 -and $_.dst_name -eq 'EHookStub' -and $_.src_kind -eq 'param' -and $_.src_index -eq 2 -and $_.val_class -eq '' })
  $kh = @($hk | Where-Object { $_.dst_kind -notin @('raise', 'dsfield') -and $_.src_kind -ne 'dsfield' } | ForEach-Object { (Row-Key $_) + '|' + $_.val_class } | Sort-Object)
  $ka = @($all | Where-Object { $_.dst_kind -notin @('raise', 'dsfield') -and $_.src_kind -ne 'dsfield' } | ForEach-Object { (Row-Key $_) + '|' + $_.val_class } | Sort-Object)
  Check 'hooks only ADD rows: every other row is identical to the plain run' (@(Compare-Object $ka $kh).Count -eq 0 -and $ka.Count -gt 0) "plain=$($ka.Count) hooked-rest=$($kh.Count)"

  Write-Host ''
  Write-Host "run_v156_EXTB1_valclass: pass=$($script:pass) fail=$($script:fail)"
  if ($script:fail -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
}
finally {
  if (-not $KeepScratch -and (Test-Path -LiteralPath $work)) { [IO.Directory]::Delete($work, $true) }
}
