<#
  run_receiver_type_text.ps1 -- item 4 (untypable receivers), spec
  2026-10-28-untypable-receivers s.8. refs.receiver_type_text carries the
  receiver's declared type text; with --library-db the TLibraryOracle binds a
  receiver typed BY NAME to refs.external_target.

  Part A: project only (xt_app + xt_app2). Part B: same project with
  --library-db (xt_lib indexed alone). RED until resolver lane R1 (part A) and
  R2 (part B). A head the PROJECT cannot type (a library type or global:
  TLibEnc.UTF8, LibApp) has receiver_type_text '' in part A -- no store knows it --
  and the library-typed text in part B (lane R4R ruling; spec s.4.1 row 3).
  P8 needs the extractor's handler local_var (lane X). Controls: external_target NULL for ALL rows in part A; the local
  call_edges set is byte-identical between A and B; P2 is never TOtherLib.Add.
  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\xtyped')).Path
$scratch = Join-Path C:\TEMP "draglint_xtyped_$PID"
try {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
  $libDir = Join-Path $scratch 'lib'; $appDir = Join-Path $scratch 'app'
  New-Item -ItemType Directory -Path $libDir,$appDir -Force | Out-Null
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $libDir -Force
  Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $appDir -Force
  $libDb = Join-Path $scratch 'lib.sqlite'; $dbA = Join-Path $scratch 'a.sqlite'; $dbB = Join-Path $scratch 'b.sqlite'

  # sql --json rows are POSITIONAL arrays: map them onto columns[].name.
  function Q([string]$Db,[string]$Query) {
    $raw = (& $exePath sql --db $Db --json --limit 5000 --query $Query 2>$null) -join "`n"
    $b = $raw.IndexOf('{'); if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
    $o = $raw.Substring($b) | ConvertFrom-Json
    $names = @($o.columns | ForEach-Object { $_.name }); $out = @()
    foreach ($r in @($o.rows)) { $h = @{}; for ($i=0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }; $out += $h }
    return ,@($out)
  }
  $refSql = 'select name_text, receiver_text, receiver_type_text, external_target from refs'
  function Rows($rows,$name,$rcv) { @($rows | Where-Object { $_.name_text -eq $name -and ($_.receiver_text -eq $rcv -or ($rcv -eq '' -and -not $_.receiver_text)) }) }

  # site -> name, receiver_text, type text, external target ($null = NULL)
  $sites = @(
    @{ id='P1'; n='Read';     r='S';             t='TLibStream';       x='xt_lib.TLibStream.Read' },
    @{ id='P2'; n='Add';      r='S.Defs';        t='TLibStream.Defs';  x='xt_lib.TLibDefs.Add' },
    @{ id='P3'; n='Pos';      r='A';             t='TAppStream';       x='xt_lib.TLibBase.Pos' },
    @{ id='P4'; n='Own';      r='A';             t='TAppStream';       x=$null },
    @{ id='P5'; n='GetBytes'; r='TLibEnc.UTF8';  t='';                 tb='TLibEnc.UTF8'; x='xt_lib.TLibEnc.GetBytes' },
    @{ id='P6'; n='Base';     r='LibApp';        t='';                 tb='TLibBase';     x='xt_lib.TLibBase.Base' },
    @{ id='P7'; n='Own';      r='GArr[1]';       t='TAppStream';       x=$null },
    @{ id='P8'; n='Base';     r='E';             t='ELibError';        x='xt_lib.TLibBase.Base' },
    @{ id='P9'; n='LibFormat';r='';              t='';                 x='xt_lib.LibFormat' },
    @{ id='N1'; n='Anything'; r='D';             t='TAppDup';          x=$null },
    @{ id='N2'; n='Add';      r='Nowhere';       t='';                 x=$null },
    @{ id='N3'; n='Missing';  r='S';             t='TLibStream';       x=$null }
  )

  Push-Location C:\TEMP
  try {
    & $exePath index $libDir --db $libDb 2>$null | Out-Null
    Check 'library index built' ($LASTEXITCODE -eq 0)

    # ---- Part A: project only ----
    $outA = & $exePath index $appDir --db $dbA 2>&1 | Out-String
    Check 'A: app index built' ($LASTEXITCODE -eq 0)
    $a = Q $dbA $refSql
    foreach ($s in $sites) {
      $rw = @(Rows $a $s.n $s.r)
      $ok = ($rw.Count -gt 0) -and (@($rw | Where-Object { $_.receiver_type_text -cne $s.t }).Count -eq 0)
      Check "A: $($s.id) receiver_type_text = '$($s.t)'" $ok ("rows=" + $rw.Count + " got=" + (($rw | ForEach-Object { "'" + $_.receiver_type_text + "'" }) -join ','))
    }
    Check 'A CONTROL: external_target NULL for ALL rows' (@($a | Where-Object { $_.external_target }).Count -eq 0)
    Check 'A: stats line shows no-store' ($outA -match 'no-store')

    # ---- Part B: with the library ----
    $outB = & $exePath index $appDir --db $dbB --library-db $libDb 2>&1 | Out-String
    Check 'B: app index built with --library-db' ($LASTEXITCODE -eq 0)
    $b = Q $dbB $refSql
    foreach ($s in $sites) {
      $rw = @(Rows $b $s.n $s.r)
      $tb = if ($s.ContainsKey('tb')) { $s.tb } else { $s.t }
      Check "B: $($s.id) receiver_type_text = '$tb'" (($rw.Count -gt 0) -and (@($rw | Where-Object { $_.receiver_type_text -cne $tb }).Count -eq 0)) ("got=" + (($rw | ForEach-Object { "'" + $_.receiver_type_text + "'" }) -join ','))
      if ($s.x) { $ok = @($rw | Where-Object { $_.external_target -ceq $s.x }).Count -gt 0 }
      else      { $ok = ($rw.Count -gt 0) -and (@($rw | Where-Object { $_.external_target }).Count -eq 0) }
      Check "B: $($s.id) external_target = '$($s.x)'" $ok ("got=" + (($rw | ForEach-Object { "'" + $_.external_target + "'" }) -join ','))
    }
    Check 'B CONTROL: P2 is NOT TOtherLib.Add' (@($b | Where-Object { $_.external_target -like '*TOtherLib*' }).Count -eq 0)
    $edgeSql = 'select r.name_text, r.receiver_text, e.target_symbol_id from call_edges e join refs r on r.id = e.ref_id order by 1,2,3'
    $ea = (Q $dbA $edgeSql | ForEach-Object { "$($_.name_text)|$($_.receiver_text)|$($_.target_symbol_id)" }) -join "`n"
    $eb = (Q $dbB $edgeSql | ForEach-Object { "$($_.name_text)|$($_.receiver_text)|$($_.target_symbol_id)" }) -join "`n"
    Check 'B: local call_edges identical to part A (a library never changes a local edge)' (($ea.Length -gt 0) -and ($ea -ceq $eb))

    # ---- idempotency + provenance ----
    $dump1 = (Q $dbB 'select id, receiver_type_text, external_target from refs order by id' | ForEach-Object { "$($_.id)|$($_.receiver_type_text)|$($_.external_target)" }) -join "`n"
    & $exePath index $appDir --db $dbB --library-db $libDb --resolve-only 2>&1 | Out-Null
    & $exePath index $appDir --db $dbB --library-db $libDb --resolve-only 2>&1 | Out-Null
    $dump2 = (Q $dbB 'select id, receiver_type_text, external_target from refs order by id' | ForEach-Object { "$($_.id)|$($_.receiver_type_text)|$($_.external_target)" }) -join "`n"
    Check 'B: --resolve-only twice is idempotent' (($dump1.Length -gt 0) -and ($dump1 -ceq $dump2))
    $meta = Q $dbB "select value from schema_meta where key = 'external_stores'"
    Check 'B: schema_meta.external_stores names the library db' (($meta.Count -gt 0) -and ($meta[0].value -like '*lib.sqlite*'))
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }