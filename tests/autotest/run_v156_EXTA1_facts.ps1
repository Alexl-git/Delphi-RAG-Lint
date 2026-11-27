<#
  run_v156_EXTA1_facts.ps1 -- 1.56 lane EXT-A1: the parser-emitted facts of the ONE 1.56 extractor bump.

  Indexes tests\fixtures\v156-exta1 (uExtA1.pas + a stand-in System.SysUtils.pas) into a scratch DB
  and checks, through `sql --json` (rows are POSITIONAL arrays; mapped onto columns[].name below):
    B1  symbol_extras.noreturn = 1 on the routines declared `noreturn` (free routine and method),
        = 2 on the known never-returning RTL routines of System.SysUtils (Abort, both
        RaiseLastOSError overloads), and NO row for Beep, for the method TAborter.Abort and for the
        user unit's own free `Abort`.
    B8  every parameter has a row: param_mode '' / const / var / out / constref (`const [Ref]` and
        `[Ref] const`), param_index = the 0-based declared position (grouped names count each).
    B2  variant_part = the 1-based source-order ordinal of the variant branch holding the field,
        nested part included (Width, Height 1; Radius 2; Inner 3; Outer 4); the tag `Kind` is a
        field symbol with variant_tag = 1; fixed-part fields (Id, TPlain.A) have no row.
    C1  call_literal_args: one row per literal argument (string decoded, number as written with
        its sign, constant candidate), arg_index / arg_count, the literal's own line; every row
        joins a refs row on (file_id, call_line, call_col); a subscript `DS.FieldValues['QTY']`
        gets its string row and `DS.Fields[0]` none; an argument that is a parameter / local of
        the file gets none.
  Positive control: run with -Exe <an engine without the EXT-A1 emitters> -- every check but the
  "no row" ones FAILS (the tables exist and hold 0 rows).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_EXTA1_facts: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_EXTA1_facts: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-exta1'
$work  = Join-Path $env:TEMP ('dl-v156-exta1-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name). A failed query returns an EMPTY array.
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

try {
  $fx = Join-Path $work 'fx'
  Copy-Item -Recurse $fxSrc $fx
  $db  = Join-Path $work 'a1.sqlite'
  $log = Join-Path $work 'index.log'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> $log }
  Check 'index exit 0' ($LASTEXITCODE -eq 0) "rc=$LASTEXITCODE"

  # ---- symbol_extras, keyed by the symbol's qualified name -------------------------------------
  $x = @(Lane-Sql $db ("SELECT s.qualified_name AS qn, s.kind AS kind, x.noreturn AS noreturn, x.variant_part AS vpart, " +
                       "x.variant_tag AS vtag, x.param_mode AS pmode, x.param_index AS pindex " +
                       "FROM symbol_extras x JOIN symbols s ON s.id = x.symbol_id ORDER BY s.qualified_name, x.param_index"))
  function Extra([string]$Qn) { return @($x | Where-Object { $_.qn -eq $Qn }) }
  function One([string]$Qn) { $r = Extra $Qn; if ($r.Count -eq 1) { return $r[0] } return $null }

  Write-Host 'B1 noreturn'
  foreach ($qn in 'uExtA1.Fail', 'uExtA1.TWorker.Stop') {
    $r = One $qn
    Check "B1 directive $qn" (($null -ne $r) -and ([int]$r.noreturn -eq 1)) ("rows=" + (Extra $qn).Count)
  }
  $r = One 'System.SysUtils.Abort'
  Check 'B1 known System.SysUtils.Abort' (($null -ne $r) -and ([int]$r.noreturn -eq 2)) ("rows=" + (Extra 'System.SysUtils.Abort').Count)
  $rl = Extra 'System.SysUtils.RaiseLastOSError'
  Check 'B1 known both RaiseLastOSError overloads' (($rl.Count -eq 2) -and (@($rl | Where-Object { [int]$_.noreturn -eq 2 }).Count -eq 2)) "rows=$($rl.Count)"
  foreach ($qn in 'System.SysUtils.Beep', 'System.SysUtils.TAborter.Abort', 'uExtA1.Abort', 'uExtA1.Plain', 'uExtA1.TWorker.Go') {
    Check "B1 no row $qn" ((Extra $qn).Count -eq 0)
  }
  $nr = @($x | Where-Object { [int]$_.noreturn -ne 0 })
  Check 'B1 noreturn rows total = 5' ($nr.Count -eq 5) "n=$($nr.Count)"

  Write-Host 'B8 parameter mode'
  $want = [ordered]@{
    'uExtA1.Modes.AVal'   = @('', 0);         'uExtA1.Modes.AConst' = @('const', 1)
    'uExtA1.Modes.AVar'   = @('var', 2);      'uExtA1.Modes.AOut'   = @('out', 3)
    'uExtA1.Modes.ARef'   = @('constref', 4); 'uExtA1.Modes.ARef2'  = @('constref', 5)
    'uExtA1.Plain.X'      = @('', 0);         'uExtA1.Plain.Y'      = @('', 1)
    'uExtA1.Fail.AText'   = @('const', 0);    'uExtA1.TWorker.Stop.AWhy' = @('const', 0)
    'uExtA1.TWorker.Go.ACount' = @('var', 0); 'uExtA1.UseCalls.DS'  = @('', 0)
    'System.SysUtils.RaiseLastOSError.LastError' = @('', 0)
  }
  foreach ($qn in $want.Keys) {
    $r = One $qn
    $got = if ($null -ne $r) { "$($r.pmode)/$($r.pindex)" } else { "rows=$((Extra $qn).Count)" }
    Check "B8 $qn" (($null -ne $r) -and ("$($r.pmode)" -eq $want[$qn][0]) -and ([int]$r.pindex -eq $want[$qn][1])) "got=$got"
  }
  $params  = @(Lane-Sql $db "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'param'")
  $withRow = @($x | Where-Object { $_.kind -eq 'param' })
  Check 'B8 every param symbol has a row' (($params.Count -eq 1) -and ([int]$params[0].n -gt 0) -and ([int]$params[0].n -eq $withRow.Count)) "params=$($params[0].n) rows=$($withRow.Count)"

  Write-Host 'B2 variant part'
  $vp = [ordered]@{ 'uExtA1.TShape.Width' = 1; 'uExtA1.TShape.Height' = 1; 'uExtA1.TShape.Radius' = 2; 'uExtA1.TShape.Inner' = 3; 'uExtA1.TShape.Outer' = 4 }
  foreach ($qn in $vp.Keys) {
    $r = One $qn
    $got = if ($null -ne $r) { "$($r.vpart)" } else { "rows=$((Extra $qn).Count)" }
    Check "B2 $qn" (($null -ne $r) -and ([int]$r.vpart -eq $vp[$qn]) -and ([int]$r.vtag -eq 0)) "got=$got"
  }
  $r = One 'uExtA1.TShape.Kind'
  Check 'B2 tag Kind: a field with variant_tag = 1, variant_part = 0' (($null -ne $r) -and ($r.kind -eq 'field') -and ([int]$r.vtag -eq 1) -and ([int]$r.vpart -eq 0)) ("rows=" + (Extra 'uExtA1.TShape.Kind').Count)
  $tag = @(Lane-Sql $db "SELECT signature AS sig FROM symbols WHERE qualified_name = 'uExtA1.TShape.Kind' AND kind = 'field'")
  Check 'B2 tag symbol: exactly one, signature TKind' (($tag.Count -eq 1) -and ($tag[0].sig -eq 'TKind')) "n=$($tag.Count)"
  foreach ($qn in 'uExtA1.TShape.Id', 'uExtA1.TPlain.A') { Check "B2 no row $qn" ((Extra $qn).Count -eq 0) }
  $vr = @($x | Where-Object { ([int]$_.vpart -ne 0) -or ([int]$_.vtag -ne 0) })
  Check 'B2 variant rows total = 6' ($vr.Count -eq 6) "n=$($vr.Count)"

  # ---- call_literal_args -----------------------------------------------------------------------
  Write-Host 'C1 call literal arguments'
  $c = @(Lane-Sql $db ("SELECT a.callee_name AS callee, a.receiver_text AS recv, a.arg_index AS ai, a.arg_count AS ac, a.lit_kind AS lk, " +
                       "a.value AS val, a.call_line AS cl, a.lit_line AS ll, a.symbol_id AS sid, " +
                       "(SELECT COUNT(*) FROM refs r WHERE r.file_id = a.file_id AND r.start_line = a.call_line AND r.start_col = a.call_col " +
                       "AND r.kind IN ('call', 'index-access')) AS refs, " +
                       "(SELECT s.qualified_name FROM symbols s WHERE s.id = a.symbol_id) AS owner " +
                       "FROM call_literal_args a ORDER BY a.file_id, a.ordinal"))
  $sig = @($c | ForEach-Object { "$($_.callee)|$($_.recv)|$($_.ai)/$($_.ac)|$($_.lk)|$($_.val)" })
  $wantSig = @(
    'FieldByName|DS|0/1|string|CODE'
    'FieldByName|DS|0/1|const|FLD_NAME'
    'Locate|DS|0/3|string|A;B'
    'Locate|DS|1/3|number|5'
    'Plain||0/2|number|1'
    'Plain||1/2|number|-2'
    'FieldValues|DS|0/1|string|QTY'
    "Format||0/2|string|%s's"
    'SetKind|Other|0/2|const|TKind.kB'
  )
  foreach ($w in $wantSig) { Check "C1 row $w" ($sig -contains $w) }
  Check 'C1 rows total = 9 (no row for a parameter / local argument, none for Fields[0])' ($c.Count -eq $wantSig.Count) ("n=$($c.Count): " + ($sig -join ' ; '))
  Check 'C1 every row joins exactly one call / index-access ref' (($c.Count -gt 0) -and (@($c | Where-Object { [int]$_.refs -ne 1 }).Count -eq 0))
  Check 'C1 every row has its enclosing routine uExtA1.UseCalls' (($c.Count -gt 0) -and (@($c | Where-Object { $_.owner -ne 'uExtA1.UseCalls' }).Count -eq 0))
  $m = @($c | Where-Object { $_.val -eq '-2' })
  Check 'C1 a literal on the next line keeps its own lit_line' (($m.Count -eq 1) -and ([int]$m[0].ll -eq ([int]$m[0].cl + 1)))
}
finally {
  if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } }
  else { Write-Host "scratch kept: $work" }
}

Write-Host ''
Write-Host "run_v156_EXTA1_facts: pass=$script:pass fail=$script:fail" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if ($script:fail -ne 0) { exit 1 }
exit 0
