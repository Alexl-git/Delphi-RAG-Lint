<#
  run_v152_EXTR_resolve.ps1 -- drag-lint 1.52 lane EXTR (resolver side of the extractor bundle).

  Fixture tests\autotest\fixtures\v152-EXTR: lib\ExtrLibClasses.pas is indexed as the LIBRARY store
  (TStringList, TObjectList<T>, TCustomStyleServices, StyleServices); code\ is the project
  (ExtrProg.dpr, uExtrUse.pas, uExtrOwnA.pas, uExtrOwnZ.pas). Every index run passes --db into a
  private work folder, so no real DB is ever touched. `sql --json` rows are POSITIONAL arrays and
  are mapped by column index; the raw rows are printed once with -ShowRaw.

  Cases (each with a positive control):
    g1  generic LIBRARY type receiver `TObjectList<TExtrBox>.Create(True)` -> receiver_type_text
        TObjectList, external_target ExtrLibClasses.TObjectList.Create          (1512-RECV)
        g1c CONTROL: plain `TStringList.Create` keeps TStringList / ExtrLibClasses.TStringList.Create
    g2  generic PROJECT type receiver `TExtrBag<Integer>.Create` -> bound to uExtrUse.TExtrBag.Create
        g2c CONTROL: `TExtrBox.Create` stays unbound to any TExtrBag member
    t1  receiver_type_text of a CALL-form receiver is never the called routine's name:
        `Copy('abc', 1, 2).Trim` -> '' (was 'Copy'); no library: `StyleServices(pOwner).GetSystemColor`
        -> '' (was 'StyleServices')                                           (FOUND 5 of 1.51.1 EXT)
        t1c CONTROLS: hard casts keep their type -- `TExtrBox(pHolder).Grow` -> TExtrBox (project),
        `TStringList(pOwner).Add` -> TStringList with AND without the library, and with the library
        `StyleServices(pOwner).GetSystemColor` -> TCustomStyleServices
    x4  no call edge / member access in the project claims a PROGRAM / UNIT / PACKAGE symbol as its
        receiver (.dpr routines, globals, paren-less function receivers)       (X4-r)
        x4c CONTROL: `GExtrBox.Grow` in the .dpr keeps receiver class uExtrUse.TExtrBox
    r1  `index --resolve-only` (with the library) run twice reproduces the full run byte for byte,
        with-blocks included                                                   (RES found)
        r1c CONTROL: the snapshot holds the with-bound `Grow` (receiver uExtrUse.TExtrBox)
    r2  `index --resolve-only` WITHOUT a library store keeps every external_target / external_kind
        of a call / member-access ref the library run wrote                     (RES found / CLI F3)
        r2c CONTROL: a DB never resolved against the library holds no external_target at all
    o1  order independence: the same sources indexed in two file orders give identical
        (path-normalised) refs / call_edges / returns_owner rows                (X2-r)
        o1c CONTROL: the snapshot carries TExtrUser.GetThing returns_owner (non-empty compare)

  Usage: pwsh -File tests\autotest\run_v152_EXTR_resolve.ps1 [-Exe <drag-lint.exe>] [-ShowRaw]
  Exit 0 = all pass, 1 = a check failed, 2 = setup failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\draglint_v152_extr_$PID",
  [switch]$ShowRaw
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Passed = 0; $script:Failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host ("  [PASS] {0} {1}" -f $Name, $Detail) }
  else     { $script:Failed++; Write-Host ("  [FAIL] {0} {1}" -f $Name, $Detail) -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\v152-EXTR')).Path

function Invoke-Sql([string]$Db, [string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --db $Db --query $Query --json --limit 0 2>$null }
  if ($LASTEXITCODE -ne 0) { throw "sql failed on $Db" }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json | ForEach-Object { $_ }
  # A List, never a bare array: an empty or one-row result must not be unrolled or nested by @().
  $list = [System.Collections.Generic.List[object]]::new()
  foreach ($r in $j.rows) { $list.Add($r) }
  return ,$list
}

# One line per ref (file NAME, not path, so two folders compare), ordered stably.
$RefsQ = "select f.path, r.start_line, r.start_col, r.kind, r.name_text, coalesce(r.receiver_text,''), " +
         "coalesce(r.receiver_type_text,''), coalesce(r.external_target,''), coalesce(r.external_kind,''), " +
         "coalesce((select qualified_name from symbols where id = r.symbol_id),''), " +
         "coalesce((select kind||':'||qualified_name from symbols where id = ce.receiver_type_symbol_id),''), " +
         "coalesce((select qualified_name from symbols where id = ce.target_symbol_id),''), coalesce(ce.confidence,''), " +
         "coalesce((select kind||':'||qualified_name from symbols where id = ma.receiver_type_symbol_id),''), coalesce(ma.mode,'') " +
         "from refs r join files f on f.id = r.file_id left join call_edges ce on ce.ref_id = r.id " +
         "left join member_accesses ma on ma.ref_id = r.id"
function Get-Refs([string]$Db) {
  $out = @()
  foreach ($r in (Invoke-Sql $Db $RefsQ)) {
    $out += [pscustomobject]@{
      File = [IO.Path]::GetFileName([string]$r[0]); Line = [int]$r[1]; Col = [int]$r[2]; Kind = [string]$r[3]
      Name = [string]$r[4]; Rcv = [string]$r[5]; Rtt = [string]$r[6]; Ext = [string]$r[7]; XKind = [string]$r[8]
      Sym = [string]$r[9]; CeRcv = [string]$r[10]; CeTgt = [string]$r[11]; Conf = [string]$r[12]
      MaRcv = [string]$r[13]; Mode = [string]$r[14]
    }
  }
  return ,@($out)
}
function Snap($Refs) {
  return ,@($Refs | ForEach-Object { ($_.PSObject.Properties.Value | ForEach-Object { [string]$_ }) -join '|' } | Sort-Object)
}
function Get-Owners([string]$Db) {
  return ,@((Invoke-Sql $Db ("select s.qualified_name, coalesce(sf.returns_owner,'') from symbols s " +
    "join symbol_facts sf on sf.symbol_id = s.id where s.kind in ('function','method') order by 1")) |
    ForEach-Object { '{0}={1}' -f $_[0], $_[1] })
}
function One($Refs, [string]$File, [int]$Line, [string]$Kind, [string]$Name) {
  $hit = @($Refs | Where-Object { $_.File -eq $File -and $_.Line -eq $Line -and $_.Kind -eq $Kind -and $_.Name -eq $Name })
  if ($hit.Count -ne 1) { return [pscustomobject]@{ Rtt = "<$($hit.Count) rows>"; Ext = ''; Sym = ''; CeTgt = ''; CeRcv = '' } }
  return $hit[0]
}
function Index-Into([string]$Src, [string]$Db, [string]$Lib) {
  if (Test-Path $Db) { [IO.File]::Delete($Db) }
  if ($Lib) { $log = & { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db --library-db $Lib 2>&1 | ForEach-Object { "$_" } } } else { $log = & { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } }
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index $Src exit $LASTEXITCODE" -ForegroundColor Red; $log | Select-Object -Last 5; exit 2 }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
Push-Location $env:TEMP
try {
  Copy-Item (Join-Path $Fx 'lib')  $WorkDir -Recurse -Force
  Copy-Item (Join-Path $Fx 'code') $WorkDir -Recurse -Force
  $Lib   = Join-Path $WorkDir 'lib.sqlite'
  $Proj  = Join-Path $WorkDir 'proj.sqlite'
  $NoLib = Join-Path $WorkDir 'nolib.sqlite'
  $Code  = Join-Path $WorkDir 'code'
  Index-Into (Join-Path $WorkDir 'lib') $Lib ''
  Index-Into $Code $Proj $Lib
  Index-Into $Code $NoLib ''
  $refs  = Get-Refs $Proj
  $bare  = Get-Refs $NoLib
  if ($ShowRaw) { Write-Host '-- raw rows (proj.sqlite):'; Snap $refs | ForEach-Object { Write-Host "   $_" } }
  Write-Host "== v152 EXTR resolve ($Exe)"

  # ---- g1 / g2: generic type receivers
  $g = One $refs 'uExtrUse.pas' 86 'member-access' 'Create'
  Check 'g1 TObjectList<TExtrBox>.Create typed through the library' (($g.Rtt -eq 'TObjectList') -and ($g.Ext -eq 'ExtrLibClasses.TObjectList.Create')) "rtt='$($g.Rtt)' ext='$($g.Ext)'"
  $g = One $refs 'uExtrUse.pas' 48 'member-access' 'Create'
  Check 'g1c CONTROL TStringList.Create stays typed' (($g.Rtt -eq 'TStringList') -and ($g.Ext -eq 'ExtrLibClasses.TStringList.Create')) "rtt='$($g.Rtt)' ext='$($g.Ext)'"
  $g = One $refs 'uExtrUse.pas' 87 'member-access' 'Create'
  Check 'g2 TExtrBag<Integer>.Create binds the project constructor' (($g.Rtt -eq 'TExtrBag') -and ($g.CeTgt -eq 'uExtrUse.TExtrBag.Create')) "rtt='$($g.Rtt)' target='$($g.CeTgt)'"
  $g = One $refs 'uExtrUse.pas' 59 'member-access' 'Create'
  Check 'g2c CONTROL TExtrBox.Create is not a TExtrBag member' (($g.Rtt -eq 'TExtrBox') -and ($g.CeTgt -notlike '*TExtrBag*')) "rtt='$($g.Rtt)' target='$($g.CeTgt)'"

  # ---- t1: call-form receivers
  $t = One $refs 'uExtrUse.pas' 93 'member-access' 'Trim'
  Check "t1 Copy(...).Trim: receiver_type_text is not the routine name" ($t.Rtt -eq '') "rtt='$($t.Rtt)'"
  $t = One $bare 'uExtrUse.pas' 54 'call' 'GetSystemColor'
  Check "t1 no library: StyleServices(pOwner).GetSystemColor receiver_type_text ''" ($t.Rtt -eq '') "rtt='$($t.Rtt)'"
  $t = One $refs 'uExtrUse.pas' 54 'call' 'GetSystemColor'
  Check 't1c CONTROL with library: StyleServices(...) typed by its result' ($t.Rtt -eq 'TCustomStyleServices') "rtt='$($t.Rtt)'"
  $t = One $bare 'uExtrUse.pas' 70 'call' 'Grow'
  Check 't1c CONTROL project hard cast TExtrBox(pHolder) keeps TExtrBox' ($t.Rtt -eq 'TExtrBox') "rtt='$($t.Rtt)'"
  $t = One $bare 'uExtrUse.pas' 92 'call' 'Add'
  Check 't1c CONTROL no library: hard cast TStringList(pOwner) keeps TStringList' ($t.Rtt -eq 'TStringList') "rtt='$($t.Rtt)'"
  $t = One $refs 'uExtrUse.pas' 92 'call' 'Add'
  Check 't1c CONTROL with library: TStringList(pOwner).Add binds' (($t.Rtt -eq 'TStringList') -and ($t.Ext -eq 'ExtrLibClasses.TStringList.Add')) "rtt='$($t.Rtt)' ext='$($t.Ext)'"

  # ---- x4: no program / unit receiver anywhere
  $bad = (Invoke-Sql $Proj ("select r.start_line, r.name_text, s.kind from call_edges ce join refs r on r.id = ce.ref_id " +
    "join symbols s on s.id = ce.receiver_type_symbol_id where s.kind in ('program','unit','package') union all " +
    "select r.start_line, r.name_text, s.kind from member_accesses ma join refs r on r.id = ma.ref_id " +
    "join symbols s on s.id = ma.receiver_type_symbol_id where s.kind in ('program','unit','package')"))
  Check 'x4 no edge / member access claims a program, unit or package receiver' ($bad.Count -eq 0) "rows=$($bad.Count)"
  $x = One $refs 'ExtrProg.dpr' 26 'call' 'Grow'
  Check 'x4c CONTROL GExtrBox.Grow in the .dpr keeps class receiver' ($x.CeRcv -eq 'class:uExtrUse.TExtrBox') "ce_recv='$($x.CeRcv)'"
  $x = One $refs 'ExtrProg.dpr' 23 'call' 'ExtrLocal'
  Check 'x4c CONTROL .dpr bare call still binds' ($x.CeTgt -eq 'ExtrProg.ExtrLocal') "target='$($x.CeTgt)'"

  # ---- r1: resolve-only twice
  $full = Snap $refs
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $Code --db $Proj --library-db $Lib --resolve-only 2>&1 | ForEach-Object { "$_" } }
  $ro1  = Snap (Get-Refs $Proj)
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $Code --db $Proj --library-db $Lib --resolve-only 2>&1 | ForEach-Object { "$_" } }
  $ro2  = Snap (Get-Refs $Proj)
  $d1 = @(Compare-Object $full $ro1).Count; $d2 = @(Compare-Object $ro1 $ro2).Count
  Check 'r1 resolve-only (library) = full run' ($d1 -eq 0) "differing rows=$d1"
  Check 'r1 resolve-only twice is idempotent' ($d2 -eq 0) "differing rows=$d2"
  $w = One $refs 'uExtrUse.pas' 66 'call' 'Grow'
  Check 'r1c CONTROL the with-bound Grow is in the snapshot' ($w.CeRcv -eq 'class:uExtrUse.TExtrBox') "ce_recv='$($w.CeRcv)'"

  # ---- r2: resolve-only without the library keeps the external targets
  $libExt = @($refs | Where-Object { ($_.Kind -in 'call','member-access') -and $_.Ext -ne '' } | ForEach-Object { "$($_.File):$($_.Line):$($_.Col):$($_.Kind):$($_.Name)=$($_.Ext)[$($_.XKind)]" })
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $Code --db $Proj --resolve-only 2>&1 | ForEach-Object { "$_" } }
  $after = Get-Refs $Proj
  $kept  = @($after | Where-Object { ($_.Kind -in 'call','member-access') -and $_.Ext -ne '' } | ForEach-Object { "$($_.File):$($_.Line):$($_.Col):$($_.Kind):$($_.Name)=$($_.Ext)[$($_.XKind)]" })
  $lost  = @(Compare-Object $libExt $kept).Count
  Check 'r2 resolve-only without a library keeps call external targets' (($libExt.Count -gt 0) -and ($lost -eq 0)) "library-run=$($libExt.Count) after=$($kept.Count) differing=$lost"
  $leak = @($bare | Where-Object { $_.Ext -ne '' })
  Check 'r2c CONTROL a DB never resolved against the library holds no external_target' ($leak.Count -eq 0) "rows=$($leak.Count)"

  # ---- o1: two file orders
  $o1 = Join-Path $WorkDir 'order1'; $o2 = Join-Path $WorkDir 'order2'
  foreach ($d in "$o1\a", "$o1\b", "$o2\a", "$o2\b") { New-Item -ItemType Directory -Force $d | Out-Null }
  Copy-Item "$Code\uExtrOwnA.pas", "$Code\ExtrProg.dpr" "$o1\a"; Copy-Item "$Code\uExtrOwnZ.pas", "$Code\uExtrUse.pas" "$o1\b"
  Copy-Item "$Code\uExtrOwnZ.pas", "$Code\uExtrUse.pas" "$o2\a"; Copy-Item "$Code\uExtrOwnA.pas", "$Code\ExtrProg.dpr" "$o2\b"
  $db1 = Join-Path $WorkDir 'order1.sqlite'; $db2 = Join-Path $WorkDir 'order2.sqlite'
  Index-Into $o1 $db1 $Lib
  Index-Into $o2 $db2 $Lib
  $s1 = Snap (Get-Refs $db1); $s2 = Snap (Get-Refs $db2)
  $w1 = Get-Owners $db1;      $w2 = Get-Owners $db2
  $dr = @(Compare-Object $s1 $s2).Count; $dw = @(Compare-Object $w1 $w2).Count
  Check 'o1 refs / edges identical in both file orders' (($s1.Count -gt 0) -and ($dr -eq 0)) "rows=$($s1.Count) differing=$dr"
  Check 'o1 returns_owner identical in both file orders' ($dw -eq 0) "differing=$dw ($(($w1 | Where-Object { $_ -like '*TExtrUser*' }) -join '; ') vs $(($w2 | Where-Object { $_ -like '*TExtrUser*' }) -join '; '))"
  Check 'o1c CONTROL TExtrUser.GetThing returns_owner is recorded' (@($w1 | Where-Object { $_ -eq 'uExtrOwnA.TExtrUser.GetThing=borrowed' }).Count -eq 1) "$(($w1 | Where-Object { $_ -like '*GetThing*' }) -join ',')"
} finally {
  Pop-Location
  try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
}
Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
