<#
  run_v1511_EXT_refs.ps1 -- 1.51.1 lane EXT: the refs the extractor owes a rename (B26, B01 extractor half).

  Fixtures: tests\index\v1511-ext\ (uExtDefs.pas, uExtProbe.pas, uExtShapes.pas; they compile with dcc64).
  Lines are located by text, never by number. Rows are mapped from `sql --json` (positional) by column name.

  NEW in 1.51.1 (RED on the 1.51.0 extractor):
    T1  `PExtBox = ^TExtBox` emits a type_use ref for the pointer's base type, bound to the record;
    T2  a pointer declared before its base (`PExtLate = ^TExtLate`) and an inline `Mark: ^TExtPoint` do too;
    S1  `property BoxTitle: string read FBox.Title write FBox.Title`: both FBox roots are property-spec refs
        bound to the field TExtHolder.FBox (they were unbound 'read' refs: a class body has no routine);
    S2  both Title members of that specifier are bound to TExtBox.Title;
    S3  a three-part path `read FBox.Origin.PosX` binds Origin to TExtBox.Origin and PosX to TExtPoint.PosX;
    S4  the root of an indexed specifier `read FPair[0].Title` is a property-spec ref bound to TExtHolder.FPair;
    S5  no specifier path leaves a second ref on the same token (one row per token and kind);
    G1  a generic constraint `TExtBoxG<T: TExtItem> = class` emits a type_use bound to TExtItem;
    G2  a generic method implementation header `function TExtBoxG<T>.GetAt` emits the type_use of its
        class qualifier, as `procedure TExtLeaf.OldRun` always did (bound to TExtBoxG);
    G3  `lInner: TExtBoxG<TExtLeaf>.TInnerG`: the generic owner of a nested type and its argument
        emit type_use refs (TExtBoxG, TExtLeaf), not only the leaf TInnerG;
    G4  NEGATIVE: the type parameters T / K of those declarations and headers emit no type_use at
        their declaring token (`<T: TExtItem>`, `<T>.GetAt`, `Fill<K: TExtOther>`, `Fill<K>(`);
    D1  `message WM_EXT_PROBE` emits a read ref bound to the constant.

  HELD from 1.51.0 (regression pins for the B26 list and the B01 extractor half; GREEN on base too --
  they are the POSITIVE CONTROLS: the queries can see a bound ref):
    H1  `MakeItem().Count` and `MakeItem.Count`: Count bound, receiver ref = the MakeItem ref;
    H2  `inherited Run` is a call bound to TExtItem.Run, `inherited Calc(pA)` to TExtItem.Calc,
        `inherited Count := 2` a member-access bound to TExtItem.Count;
    H3  `for lItem in FItems` writes lItem (bound to the local) and reads FItems;
    H4  bare specifiers `read GetShown` / `read FCount2 write FCount2` are property-spec refs bound to the members;
    H5  record-constant field names (Alpha, Beta; nested Origin / PosX) are record-field refs bound to the fields;
    H6  `FItems[pIdx].Text`: bound to TExtItem.Text, receiver_type_text = TExtItem (the element type);
    H7  B01: `TExtOther(FObjs[pIdx]).Text` is bound to TExtOther.Text -- NOT TExtItem.Text -- with
        receiver_type_text = TExtOther and a receiver ref that is the cast, typed via 'cast';
    H8  no parse error in any fixture.

  Usage: pwsh -File tests\autotest\run_v1511_EXT_refs.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$fxDir = Join-Path $Repo 'tests\index\v1511-ext'
$script:Failed = $false
$script:Passed = 0
$script:FailedCount = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name"; $script:Passed++ }
  else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:Failed = $true; $script:FailedCount++ }
}
function Get-Line([string]$File, [string]$Text) {
  $hit = Select-String -Path (Join-Path $fxDir $File) -SimpleMatch -Pattern $Text | Select-Object -First 1
  if (-not $hit) { throw "fixture $File lost the line '$Text'" }
  return $hit.LineNumber
}
function Invoke-Sql([string]$Db, [string]$Query) {
  $txt = (& { $ErrorActionPreference = 'Continue'; & $exePath sql --db $Db --query $Query --json --limit 0 2>$null }) -join "`n"
  $doc = $txt | ConvertFrom-Json | ForEach-Object { $_ }
  $cols = @($doc.columns | ForEach-Object { $_.name })
  $out = foreach ($r in @($doc.rows)) {
    $o = [ordered]@{}
    for ($k = 0; $k -lt $cols.Count; $k++) { $o[$cols[$k]] = $r[$k] }
    [pscustomobject]$o
  }
  return , @($out)
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v1511ext-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$dir = Join-Path $tmp 'fx'
[IO.Directory]::CreateDirectory($dir) | Out-Null
foreach ($f in Get-ChildItem $fxDir -File -Filter *.pas) { [IO.File]::Copy($f.FullName, (Join-Path $dir $f.Name)) }
$db = Join-Path $tmp 'fx.sqlite'
$log = (& { $ErrorActionPreference = 'Continue'; & $exePath index $dir --db $db --library-db none 2>&1 | ForEach-Object { "$_" } }) -join "`n"

$all = Invoke-Sql $db @"
select f.path path, r.id id, r.start_line line, r.start_col col, r.kind kind, r.name_text name,
       s.qualified_name target, r.receiver_text rcv, r.receiver_type_text rcvtype,
       (select receiver_ref_id from ref_receivers x where x.ref_id = r.id) rcvref,
       (select via from ref_types t where t.ref_id = r.id) via
from refs r join files f on f.id = r.file_id left join symbols s on s.id = r.symbol_id
"@
function Refs([string]$File, [string]$LineText, [string]$Name, [string]$Kind = '') {
  $ln = Get-Line $File $LineText
  return , @($all | Where-Object { $_.path -like "*\$File" -and $_.line -eq $ln -and $_.name -eq $Name -and ($Kind -eq '' -or $_.kind -eq $Kind) })
}
function AllBound($Rows, [int]$Count, [string]$Target) {
  return ($Rows.Count -eq $Count) -and (@($Rows | Where-Object { $_.target -ne $Target }).Count -eq 0)
}
function Show($Rows) { return (@($Rows | ForEach-Object { "$($_.kind)@$($_.line):$($_.col)->$($_.target)" }) -join ' | ') }

# ---- new in 1.51.1 ----
$r = Refs 'uExtShapes.pas' 'PExtBox = ^TExtBox;' 'TExtBox' 'type_use'
Check 'T1 pointer base type emits a bound type_use' (AllBound $r 1 'uExtShapes.TExtBox') (Show $r)
$r1 = Refs 'uExtShapes.pas' 'PExtLate = ^TExtLate;' 'TExtLate' 'type_use'
$r2 = Refs 'uExtShapes.pas' 'Mark: ^TExtPoint;' 'TExtPoint' 'type_use'
Check 'T2 forward and inline pointer base types emit bound type_use refs' ((AllBound $r1 1 'uExtShapes.TExtLate') -and (AllBound $r2 1 'uExtShapes.TExtPoint')) ((Show $r1) + ' / ' + (Show $r2))

$r = Refs 'uExtShapes.pas' 'property BoxTitle: string read FBox.Title write FBox.Title;' 'FBox'
Check 'S1 dotted specifier roots are property-spec refs bound to the field' ((AllBound $r 2 'uExtShapes.TExtHolder.FBox') -and (@($r | Where-Object { $_.kind -ne 'property-spec' }).Count -eq 0)) (Show $r)
$r = Refs 'uExtShapes.pas' 'property BoxTitle: string read FBox.Title write FBox.Title;' 'Title'
Check 'S2 dotted specifier members are bound' (AllBound $r 2 'uExtShapes.TExtBox.Title') (Show $r)
$r1 = Refs 'uExtShapes.pas' 'property OriginX: Integer read FBox.Origin.PosX;' 'Origin'
$r2 = Refs 'uExtShapes.pas' 'property OriginX: Integer read FBox.Origin.PosX;' 'PosX'
Check 'S3 a three-part specifier path binds every member' ((AllBound $r1 1 'uExtShapes.TExtBox.Origin') -and (AllBound $r2 1 'uExtShapes.TExtPoint.PosX')) ((Show $r1) + ' / ' + (Show $r2))
$r = Refs 'uExtShapes.pas' 'property FirstTitle: string read FPair[0].Title;' 'FPair'
Check 'S4 indexed specifier root is a bound property-spec ref' ((AllBound $r 1 'uExtShapes.TExtHolder.FPair') -and ($r[0].kind -eq 'property-spec')) (Show $r)
$specLines = @('property BoxTitle: string read FBox.Title write FBox.Title;', 'property OriginX: Integer read FBox.Origin.PosX;', 'property FirstTitle: string read FPair[0].Title;') | ForEach-Object { Get-Line 'uExtShapes.pas' $_ }
$dups = @($all | Where-Object { $_.path -like '*\uExtShapes.pas' -and $specLines -contains $_.line } | Group-Object line, col, kind | Where-Object { $_.Count -gt 1 })
Check 'S5 one ref per specifier token and kind' ($dups.Count -eq 0) (@($dups | ForEach-Object { $_.Name }) -join ' | ')

$r = Refs 'uExtDecls.pas' 'TExtBoxG<T: TExtItem> = class' 'TExtItem' 'type_use'
Check 'G1 generic constraint emits a bound type_use' (AllBound $r 1 'uExtDefs.TExtItem') (Show $r)
$r1 = Refs 'uExtDecls.pas' 'function TExtBoxG<T>.GetAt(const pIdx: Integer): Integer;' 'TExtBoxG' 'type_use'
$r2 = Refs 'uExtDecls.pas' 'procedure TExtBoxG<T>.Fill<K>(const pKey: K);' 'TExtBoxG' 'type_use'
$r3 = Refs 'uExtDecls.pas' 'procedure TExtLeaf.OldRun;' 'TExtLeaf' 'type_use'
Check 'G2 generic implementation header emits its class qualifier' ((AllBound $r1 1 'uExtDecls.TExtBoxG') -and (AllBound $r2 1 'uExtDecls.TExtBoxG') -and (AllBound $r3 1 'uExtDecls.TExtLeaf')) ((Show $r1) + ' / ' + (Show $r2) + ' / ' + (Show $r3))
$r1 = Refs 'uExtDecls.pas' 'lInner: TExtBoxG<TExtLeaf>.TInnerG;' 'TExtBoxG' 'type_use'
$r2 = Refs 'uExtDecls.pas' 'lInner: TExtBoxG<TExtLeaf>.TInnerG;' 'TExtLeaf' 'type_use'
$r3 = Refs 'uExtDecls.pas' 'lInner: TExtBoxG<TExtLeaf>.TInnerG;' 'TInnerG' 'type_use'
Check 'G3 generic owner of a nested type emits owner and argument' ((AllBound $r1 1 'uExtDecls.TExtBoxG') -and (AllBound $r2 1 'uExtDecls.TExtLeaf') -and ($r3.Count -eq 1)) ((Show $r1) + ' / ' + (Show $r2) + ' / ' + (Show $r3))
$declLines = @('TExtBoxG<T: TExtItem> = class', 'function TExtBoxG<T>.GetAt(const pIdx: Integer): Integer;', 'procedure Fill<K: TExtOther>(const pKey: K);', 'procedure TExtBoxG<T>.Fill<K>(const pKey: K);') | ForEach-Object { Get-Line 'uExtDecls.pas' $_ }
$tp = @($all | Where-Object { $_.path -like '*uExtDecls.pas' -and $declLines -contains $_.line -and $_.name -eq 'T' })
$kp = @($all | Where-Object { $_.path -like '*uExtDecls.pas' -and $declLines -contains $_.line -and $_.name -eq 'K' })
$kUse = @($kp | Where-Object { $_.kind -eq 'type_use' })
Check 'G4 type parameters emit no ref where they are declared' (($tp.Count -eq 0) -and ($kUse.Count -eq 2) -and ($kp.Count -eq 2)) ((Show $tp) + ' / ' + (Show $kp))
$r = Refs 'uExtDecls.pas' 'procedure WMProbe(var pMsg: TExtMsg); message WM_EXT_PROBE;' 'WM_EXT_PROBE' 'read'
Check 'D1 message directive constant emits a bound read' (AllBound $r 1 'uExtDecls.WM_EXT_PROBE') (Show $r)

# ---- held from 1.51.0 (positive controls) ----
$r1 = Refs 'uExtProbe.pas' 'Result := MakeItem().Count;' 'Count'
$m1 = Refs 'uExtProbe.pas' 'Result := MakeItem().Count;' 'MakeItem'
$r2 = Refs 'uExtProbe.pas' 'Result := Result + MakeItem.Count;' 'Count'
$m2 = Refs 'uExtProbe.pas' 'Result := Result + MakeItem.Count;' 'MakeItem'
Check 'H1 a member of a call result is bound and names its receiver ref' ((AllBound $r1 1 'uExtDefs.TExtItem.Count') -and (AllBound $r2 1 'uExtDefs.TExtItem.Count') -and ($m1.Count -eq 1) -and ($m2.Count -eq 1) -and ($r1[0].rcvref -eq $m1[0].id) -and ($r2[0].rcvref -eq $m2[0].id)) ((Show $r1) + ' / ' + (Show $r2))
$r1 = Refs 'uExtProbe.pas' '  inherited Run;' 'Run' 'call'
$r2 = Refs 'uExtProbe.pas' 'Result := inherited Calc(pA) + 1;' 'Calc' 'call'
$r3 = Refs 'uExtShapes.pas' 'inherited Count := 2;' 'Count' 'member-access'
Check 'H2 inherited X is bound to the ancestor member' ((AllBound $r1 1 'uExtDefs.TExtItem.Run') -and (AllBound $r2 1 'uExtDefs.TExtItem.Calc') -and (AllBound $r3 1 'uExtDefs.TExtItem.Count')) ((Show $r1) + ' / ' + (Show $r2) + ' / ' + (Show $r3))
$r1 = Refs 'uExtProbe.pas' 'for lItem in FItems do' 'lItem' 'write'
$r2 = Refs 'uExtProbe.pas' 'for lItem in FItems do' 'FItems' 'read'
Check 'H3 for-in writes the loop variable and reads the collection' ((AllBound $r1 1 'uExtProbe.TExtChild.ProbeForIn.lItem') -and (AllBound $r2 1 'uExtProbe.TExtChild.FItems')) ((Show $r1) + ' / ' + (Show $r2))
$r1 = Refs 'uExtProbe.pas' 'property Shown: Integer read GetShown;' 'GetShown' 'property-spec'
$r2 = Refs 'uExtProbe.pas' 'property Mirror: Integer read FCount2 write FCount2;' 'FCount2' 'property-spec'
Check 'H4 bare specifiers are bound property-spec refs' ((AllBound $r1 1 'uExtProbe.TExtChild.GetShown') -and (AllBound $r2 2 'uExtProbe.TExtChild.FCount2')) ((Show $r1) + ' / ' + (Show $r2))
$r1 = Refs 'uExtProbe.pas' "cExtRec: TExtRec = (Alpha: 1; Beta: 'b');" 'Alpha' 'record-field'
$r2 = Refs 'uExtShapes.pas' "cExtBox: TExtBox = (Origin: (PosX: 1; PosY: 2); Title: 't');" 'PosX' 'record-field'
Check 'H5 record-constant field names are bound record-field refs' ((AllBound $r1 1 'uExtDefs.TExtRec.Alpha') -and (AllBound $r2 1 'uExtShapes.TExtPoint.PosX')) ((Show $r1) + ' / ' + (Show $r2))
$r = Refs 'uExtProbe.pas' 'Result := FItems[pIdx].Text;' 'Text'
Check 'H6 a member of a subscripted receiver is bound through the element type' ((AllBound $r 1 'uExtDefs.TExtItem.Text') -and ($r[0].rcvtype -eq 'TExtItem')) (Show $r)
$r = Refs 'uExtProbe.pas' 'Result := TExtOther(FObjs[pIdx]).Text;' 'Text'
$c = Refs 'uExtProbe.pas' 'Result := TExtOther(FObjs[pIdx]).Text;' 'TExtOther'
Check 'H7 B01 a hard-cast receiver gives the static type and the receiver ref' ((AllBound $r 1 'uExtDefs.TExtOther.Text') -and ($r[0].rcvtype -eq 'TExtOther') -and ($c.Count -eq 1) -and ($r[0].rcvref -eq $c[0].id) -and ($c[0].via -eq 'cast')) ((Show $r) + " rcvtype=$($r[0].rcvtype) rcvref=$($r[0].rcvref) cast=$($c[0].id)/$($c[0].via)")
$diag = @($log -split "`n" | Where-Object { $_ -match 'parse error|[1-9]\d* errors' })
Check 'H8 no parse error in any fixture' ($diag.Count -eq 0) ($diag -join ' | ')

Write-Host "run_v1511_EXT_refs: $($script:Passed) passed, $($script:FailedCount) failed"
if ($script:Failed) { exit 1 } else { exit 0 }
