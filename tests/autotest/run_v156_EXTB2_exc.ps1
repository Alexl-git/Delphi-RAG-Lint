<#
  run_v156_EXTB2_exc.ps1 -- 1.56 lane EXT-B2 (B4): data flows through raise and except handlers.

  Indexes tests\fixtures\v156-extb2 into a scratch DB and checks, through `sql --json` (rows are
  POSITIONAL arrays; mapped onto columns[].name below):
    R   raise rows (dst_kind 'raise'): a constructor argument of `raise T.Create*(..)` (dst_name = the
        class, dst_index = the argument position, dst_receiver = the unit qualifier), a re-raised
        handler object (`raise;` : dst_name '', dst_index -1; `raise E` : dst_name = the handled
        class), in a handler and in a bare except. (The else part of an except block is not walked at all
        by the data-flow walk today -- DRagLint.Analysis.Cfg emits no item for it -- so it has no row.)
    H   handle rows (src_kind 'except'): the exception object of `on E: T do` (src_name = T, source
        position = the `on` clause) and of a bare except (`ExceptObject`; src_name '', position = the
        `except` keyword) reaching a call argument, Result through a local, a new raise.
    N   NEGATIVES, each beside a positive control: a literal message, a parameter named like a handler
        variable, a local of that name after the handler, a member of that name, the inner handler of
        two nested ones.
    O   (-BaseExe <the engine built from the lane base 7cfa2be7a>) every row that is neither a raise
        row nor an except-sourced row is EXACTLY a base-engine row (nothing removed, altered, added).
  Positive control for the whole runner: run it with -Exe <the base engine> -- R and H FAIL.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_EXTB2_exc: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_EXTB2_exc: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-extb2'
$work  = Join-Path $env:TEMP ('dl-v156-extb2-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
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
function Lane-Index([string]$Dir, [string]$Db, [string]$LogName, [string]$With = $Exe) {
  $log = Join-Path $work $LogName
  & { $ErrorActionPreference = 'Continue'; & $With index $Dir --db $Db *> $log }
  return $LASTEXITCODE
}
$rowSql = "SELECT s.name AS routine, d.dst_kind, d.dst_line, d.dst_col, d.dst_index, d.dst_name, d.dst_receiver, " +
          "d.src_kind, d.src_index, d.src_line, d.src_col, d.src_name, d.via_local, d.cond, d.val_class " +
          "FROM data_flows d JOIN symbols s ON s.id = d.symbol_id LIMIT 100000"
function Has($rs, [scriptblock]$p) { @($rs | Where-Object $p).Count -gt 0 }
function Row-Key($r) { "$($r.routine)|$($r.dst_kind)|$($r.dst_line)|$($r.dst_col)|$($r.dst_index)|$($r.dst_name)|$($r.dst_receiver)|$($r.src_kind)|$($r.src_index)|$($r.src_line)|$($r.src_col)|$($r.src_name)|$($r.via_local)|$($r.cond)|$($r.val_class)" }

try {
  $src = Join-Path $work 'src'
  Copy-Item $fxSrc $src -Recurse
  $probe = Join-Path $src 'uExtB2.pas'
  $M = @{}
  $ln = 0
  foreach ($line in [IO.File]::ReadAllLines($probe)) {
    $ln++
    $hit = [regex]::Match($line, '\{ (M-[A-Z-]+) \}')
    if ($hit.Success) { $M[$hit.Groups[1].Value] = $ln }
  }
  Check 'fixture markers found (fixture input)' ($M.Count -eq 23) "markers=$($M.Count)"

  $db = Join-Path $work 'a.sqlite'
  $rc = Lane-Index $src $db 'index-a.log'
  Check 'index exits 0' ($rc -eq 0) "rc=$rc"
  $all = @(Lane-Sql $db $rowSql)
  Check 'data_flows has rows at all (POSITIVE CONTROL for every negative below)' ($all.Count -gt 0) "rows=$($all.Count)"
  $rz = @($all | Where-Object { $_.dst_kind -eq 'raise' })
  $ex = @($all | Where-Object { $_.src_kind -eq 'except' })
  function Of([string]$Routine) { @($all | Where-Object { $_.routine -eq $Routine -or $_.routine -like "*.$Routine" }) }

  Write-Host 'R raise rows' -ForegroundColor Cyan
  Check 'RaiseArg: Msg -> raise EProbe.Create(Msg): dst raise, class EProbe, argument 0, direct' (Has (Of 'RaiseArg') { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-RAISE' -and $_.dst_name -eq 'EProbe' -and $_.dst_index -eq 0 -and $_.dst_receiver -eq '' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq '' -and $_.via_local -eq 0 })
  $t = @((Of 'RaiseFmt') | Where-Object { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-FMT' -and $_.dst_name -eq 'EProbe' -and $_.dst_index -eq 1 })
  Check 'RaiseFmt: the string param reaches CreateFmt argument 1 (the open array)' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.val_class -eq '' })
  Check 'RaiseFmt: the Integer param reaches it as a value row (int)' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 1 -and $_.val_class -eq 'int' })
  Check 'RaiseQualified: raise uExtB2.EProbe.Create(Msg): class EProbe, receiver uExtB2' (Has (Of 'RaiseQualified') { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-QUAL' -and $_.dst_name -eq 'EProbe' -and $_.dst_receiver -eq 'uExtB2' -and $_.dst_index -eq 0 -and $_.src_kind -eq 'param' })
  Check 'Reraise: `raise;` in on E: EProbe: dst raise, class empty, index -1, source = the handler object' (Has (Of 'Reraise') { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-RERAISE' -and $_.dst_name -eq '' -and $_.dst_index -eq -1 -and $_.src_kind -eq 'except' -and $_.src_name -eq 'EProbe' -and $_.src_line -eq $M.'M-RE-ON' })
  Check 'Wrap: E.Message -> raise EOther.Create(..): class EOther, argument 0, source except EProbe' (Has (Of 'Wrap') { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-WRAP' -and $_.dst_name -eq 'EOther' -and $_.dst_index -eq 0 -and $_.src_kind -eq 'except' -and $_.src_name -eq 'EProbe' -and $_.src_line -eq $M.'M-WRAP-ON' })
  Check 'RaiseVar: `raise E`: the object itself (index -1), class = the handled class' (Has (Of 'RaiseVar') { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-VAR' -and $_.dst_name -eq 'EProbe' -and $_.dst_index -eq -1 -and $_.src_kind -eq 'except' -and $_.src_name -eq 'EProbe' -and $_.src_line -eq $M.'M-VAR-ON' })
  Check 'BareExcept: `raise;` in a bare except: source except, class empty, at the except keyword' (Has (Of 'BareExcept') { $_.dst_kind -eq 'raise' -and $_.dst_line -eq $M.'M-BARE-RAISE' -and $_.dst_index -eq -1 -and $_.src_kind -eq 'except' -and $_.src_name -eq '' -and $_.src_line -eq $M.'M-BARE' })

  Write-Host 'H handle rows' -ForegroundColor Cyan
  Check 'HandleLog: Sink(E.Message): arg row, source except EProbe at the on clause, direct' (Has (Of 'HandleLog') { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'Sink' -and $_.dst_line -eq $M.'M-ON-SINK' -and $_.dst_index -eq 0 -and $_.src_kind -eq 'except' -and $_.src_name -eq 'EProbe' -and $_.src_line -eq $M.'M-ON' -and $_.src_index -eq -1 -and $_.val_class -eq '' -and $_.via_local -eq 0 })
  Check 'HandleResult: S := E.Message; Result := S: result row, source except EOther, via local' (Has (Of 'HandleResult') { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'except' -and $_.src_name -eq 'EOther' -and $_.src_line -eq $M.'M-RES-ON' -and $_.via_local -eq 1 })
  Check 'BareExcept: Sink(Exception(ExceptObject).Message): arg row, source except, class empty' (Has (Of 'BareExcept') { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'Sink' -and $_.dst_line -eq $M.'M-BARE-SINK' -and $_.src_kind -eq 'except' -and $_.src_name -eq '' -and $_.src_line -eq $M.'M-BARE' })
  $t = @((Of 'Nested') | Where-Object { $_.dst_kind -eq 'arg' -and $_.src_kind -eq 'except' })
  Check 'Nested: the outer sink reads the outer handler object (EProbe)' (Has $t { $_.dst_line -eq $M.'M-OUTER-SINK' -and $_.src_name -eq 'EProbe' -and $_.src_line -eq $M.'M-OUTER-ON' })
  Check 'Nested: the inner sink reads the inner handler object (EOther)' (Has $t { $_.dst_line -eq $M.'M-INNER-SINK' -and $_.src_name -eq 'EOther' -and $_.src_line -eq $M.'M-INNER-ON' })

  Write-Host 'N negatives' -ForegroundColor Cyan
  Check 'NEGATIVE: Nested: the inner sink does not read the outer (shadowed) object' (-not (Has $t { $_.dst_line -eq $M.'M-INNER-SINK' -and $_.src_name -eq 'EProbe' }))
  Check 'NEGATIVE: Nested: the outer sink does not read the inner object' (-not (Has $t { $_.dst_line -eq $M.'M-OUTER-SINK' -and $_.src_name -eq 'EOther' }))
  Check 'NEGATIVE: RaiseLiteral: a literal message makes no raise row' (-not (Has $rz { $_.dst_line -eq $M.'M-LIT' }))
  $t = @((Of 'Outside') | Where-Object { $_.dst_line -eq $M.'M-OUT' })
  Check 'Outside: POSITIVE CONTROL -- the parameter E reaches the sink' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 0 })
  Check 'NEGATIVE: Outside: a parameter named E outside any handler is no except source' (-not (Has $t { $_.src_kind -eq 'except' }))
  $t = @((Of 'AfterHandler') | Where-Object { $_.dst_line -eq $M.'M-AFTER' })
  Check 'AfterHandler: POSITIVE CONTROL -- P reaches the sink through the local E' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.via_local -eq 1 })
  Check 'NEGATIVE: AfterHandler: the local E after the handler is no except source' (-not (Has $t { $_.src_kind -eq 'except' }))
  $t = @((Of 'MemberNamedE') | Where-Object { $_.dst_line -eq $M.'M-MEMBER' })
  Check 'MemberNamedE: POSITIVE CONTROL -- P reaches the sink' (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 0 })
  Check 'NEGATIVE: MemberNamedE: `P.E` in a handler is a member, not the handler object' (-not (Has $t { $_.src_kind -eq 'except' }))
  Check 'every raise row sits on a raise marker line; every except source on an on / except marker line' ((@($rz | Where-Object { $_.dst_line -notin @($M.'M-RAISE', $M.'M-FMT', $M.'M-QUAL', $M.'M-RERAISE', $M.'M-WRAP', $M.'M-VAR', $M.'M-BARE-RAISE') }).Count -eq 0) -and (@($ex | Where-Object { $_.src_line -notin @($M.'M-ON', $M.'M-RES-ON', $M.'M-RE-ON', $M.'M-WRAP-ON', $M.'M-VAR-ON', $M.'M-BARE', $M.'M-OUTER-ON', $M.'M-INNER-ON') }).Count -eq 0) -and $rz.Count -gt 0 -and $ex.Count -gt 0) "raise=$($rz.Count) except=$($ex.Count)"

  if ($BaseExe -ne '') {
    Write-Host 'O the other rows are untouched' -ForegroundColor Cyan
    $dbB = Join-Path $work 'base.sqlite'
    $rcB = Lane-Index $src $dbB 'index-base.log' $BaseExe
    $base = @(Lane-Sql $dbB $rowSql $BaseExe)
    Check 'base engine indexed the fixture and wrote rows (POSITIVE CONTROL)' ($rcB -eq 0 -and $base.Count -gt 0) "rc=$rcB rows=$($base.Count)"
    $kb = @($base | ForEach-Object { Row-Key $_ } | Sort-Object)
    $kn = @($all | Where-Object { $_.dst_kind -ne 'raise' -and $_.src_kind -ne 'except' } | ForEach-Object { Row-Key $_ } | Sort-Object)
    $d = @(Compare-Object $kb $kn)
    Check 'rows that are neither raise nor except-sourced == the base engine''s rows (set diff 0)' ($d.Count -eq 0 -and $kb.Count -eq $kn.Count) "base=$($kb.Count) rest=$($kn.Count) diff=$($d.Count) $(($d | Select-Object -First 3 | ForEach-Object { $_.SideIndicator + $_.InputObject }) -join ' ; ')"
    Check 'B4 rows are additions' ($all.Count -gt $kb.Count) "all=$($all.Count) base=$($kb.Count)"
  }

  Write-Host ''
  Write-Host "run_v156_EXTB2_exc: pass=$($script:pass) fail=$($script:fail)"
  if ($script:fail -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
}
finally {
  if (-not $KeepScratch -and (Test-Path -LiteralPath $work)) { [IO.Directory]::Delete($work, $true) }
}
