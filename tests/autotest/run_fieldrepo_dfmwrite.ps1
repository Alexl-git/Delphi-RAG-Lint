#Requires -Version 7.3
<#
  run_fieldrepo_dfmwrite.ps1 -- TT-DFMWRITE (1.54): `repo write-dfm`, the field repository -> DFM change set.

  PART 1  builds and runs tests\fieldrepo\DfmWriteTests.dpr (byte-level DFM and unit editors, literals, field classes).
  PART 2  the built engine on tests\fixtures\fieldrepo\dfmwrite (data, calc, internal-calc, lookup, aggregate fields; a
          graphical DBTable column and a graphical tree-list column):
    W1  dry run: the change set, no byte written, no backup
    W2  a selection: lookup keys added, graphical rows only reported, removals unchecked, blocked when the form needs them
    W3  --apply: golden bytes, everything else byte for byte, backup = the old bytes, one log line per change
    W4  round trip: read-dfm sees no difference, write-dfm plans nothing more and writes nothing
    W5  convert.exe: to binary and back gives the same text
    W6  the form compiles and LOADS before and after (linked DFM, published fields, lookup value, graphical columns kept)
    W7  removal with --select: DFM block and declaration go, nothing else, the form still loads
    W8  refusals: binary DFM, no unit, no Data.DB, no class, read-only unit; nothing written
    W9  usage: direction, selection, --select errors; --dry-run wins
    W10 needed changes, inherited and BDE datasets, SQL aliases, lookup wiring, changed kind, LF + ANSI forms
    W11 --json
  Run: pwsh -File tests\autotest\run_fieldrepo_dfmwrite.ps1 [-Exe <drag-lint.exe>] [-SkipUnit] [-SkipForm]
       -SkipForm leaves out W6 and the load half of W7 (a machine without DevExpress).
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipUnit, [switch]$SkipForm)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = $false
$script:Count = 0
function Check($n, $ok, $d = '') {
  $script:Count++
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== repo write-dfm ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-dfmw-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & $Exe @a 2>&1
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Write-Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:y) { Run (@('repo', 'write-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'repo-to-dfm') + $more) }
function Read-Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:y) { Run (@('repo', 'read-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'dfm-to-repo') + $more) }
function Has($r, $text) { $r.Out.Contains($text) }
function Hash($f) { (Get-FileHash -LiteralPath $f).Hash }
function Text($f) { [IO.File]::ReadAllText($f, [Text.Encoding]::Latin1) }
function Put($f, $t) { [IO.File]::WriteAllText($f, $t.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::Latin1) }
function IdOf($r, $pattern) { $m = [regex]::Match($r.Out, '(?m)^\[(\d+)\] ' + $pattern); if ($m.Success) { $m.Groups[1].Value } else { '' } }
function Backups($dir) { @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '\.before-write-dfm-' }) }
# a repository with edited values: $edit gets the backup text and returns the new one
function EditRepo($from, $to, [scriptblock]$edit) {
  $bk = Join-Path $work ('edit-' + [guid]::NewGuid().ToString('N') + '.txt')
  $null = Run @('repo', 'backup', '--repo', $from, '--out', $bk)
  [IO.File]::WriteAllText($bk, (& $edit ([IO.File]::ReadAllText($bk))))
  $r = Run @('repo', 'restore', '--repo', $to, '--in', $bk)
  Check "R $([IO.Path]::GetFileName($to)) restored" ($r.Code -eq 0) $r.Out
}
# sets one KEY=VALUE line of one DL_FIELDS_INFO record, adding it after the header when it is not there
function SetCol($t, $key, $col, $val) {
  $head = "[DL_FIELDS_INFO $key]`r`n"
  $i = $t.IndexOf($head)
  if ($i -lt 0) { Write-Host "FATAL: no record $key" -ForegroundColor Red; $script:Failed = $true; return $t }
  $end = $t.IndexOf("`r`n[", $i + $head.Length)
  if ($end -lt 0) { $end = $t.Length }
  $rec = $t.Substring($i, $end - $i)
  $new = [regex]::Replace($rec, "(?m)^$col=[^\r\n]*", "$col=$val")
  if (($new -ceq $rec) -and ($rec -notmatch "(?m)^$col=")) { Write-Host "FATAL: no $key $col" -ForegroundColor Red; $script:Failed = $true }
  $t.Substring(0, $i) + $new + $t.Substring($end)
}
function BuildForm($dir) {
  $log = Join-Path $dir 'b.log'
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + (Join-Path $Repo 'build\_build_fieldrepo_dfmwrite_form_local.bat') + '" "' + $dir + '" > "' + $log + '" 2>&1"') -Wait -NoNewWindow
  $l = Get-Content -LiteralPath $log -Raw
  if ($l -notmatch 'BUILD_EXITCODE=0') { return 'BUILD FAILED ' + (($l -split "`n" | Select-String 'Error|Fatal' | Select-Object -First 3) -join ' / ') }
  (& (Join-Path $dir 'AllKindsLoad.exe') 2>&1 | ForEach-Object { "$_" }) -join "`n"
}
try {
  # ---- part 1 ----
  if (-not $SkipUnit) {
    $bat = Join-Path $Repo 'build\_build_fieldrepo_dfmwrite_tests_local.bat'
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'U0 the unit tests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: E\d+')) $blog
    $u = (& (Join-Path $work 'DfmWriteTests.exe') 2>&1 | ForEach-Object { "$_" })
    $uc = $LASTEXITCODE
    $u | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $sum = ($u | Where-Object { $_ -match '^Summary: ' } | Select-Object -Last 1)
    Check "U1 unit tests ($sum)" (($uc -eq 0) -and ($sum -match 'pass=[1-9]\d* fail=0$')) $sum
  }
  # ---- part 2 ----
  $src = Join-Path $Repo 'tests\fixtures\fieldrepo\dfmwrite'
  function NewForms($name) {
    $d = Join-Path $work $name
    [IO.Directory]::CreateDirectory($d) | Out-Null
    foreach ($f in 'uAllKinds.dfm', 'uAllKinds.pas', 'AllKindsLoad.dpr') { [IO.File]::Copy((Join-Path $src $f), (Join-Path $d $f)) }
    $d
  }
  $x = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $x)
  $null = Run @('repo', 'seed-fb', '--ddl', (Join-Path $src 'schema.sql'), '--repo', $x, '--apply')
  $null = Read-Dfm @('--apply') (Join-Path $src 'uFull.dfm') $x
  # STATUS becomes a graphical column (no DFM field can say that); NOTE and PRICE are edited rows with the VISIBLE False of a new row
  $script:y = Join-Path $work 'y.dlrepo'
  EditRepo $x $y { param($t) SetCol (SetCol (SetCol (SetCol (SetCol $t 'ORDERS|STATUS' 'FIELD_KIND' '10') 'ORDERS|STATUS' 'ISCALCULATED' 'false') 'ORDERS|NOTE' 'DISPLAY_WIDTH' '33') 'ORDERS|QTY' 'VISIBLE' 'true') 'ORDERS|PRICE' 'DISPLAY_FORMAT' '0.00' }
  $forms = NewForms 'forms'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $pas = Join-Path $forms 'uAllKinds.pas'
  $hd = Hash $dfm; $hp = Hash $pas; $hr = Hash $y
  $oldDfm = Text $dfm; $oldPas = Text $pas
  $r = Write-Dfm @()
  Check 'W1a dry run without a selection: only property changes' (($r.Code -eq 0) -and ($r.Out -match 'direction repo-to-dfm, \d+ changes, 0 blocked, \d+ unchecked') -and ($r.Out -notmatch '\] (insert|delete) ') -and ($r.Out -match 'memOrdersQTY DisplayLabel: Qty -> It''s a quantity, \\u00E9!\n\[') -and ($r.Out -match 'memOrdersNOTE Size: 40 -> 80\n') -and ($r.Out -match 'memOrdersQTY Visible: False -> True\n\[') -and ($r.Out -match 'memOrdersNOTE DisplayWidth: 40 -> 33\n')) $r.Out
  Check 'W1b a value the repository does not hold changes nothing (a new row''s VISIBLE False included)' (($r.Out -notmatch 'memOrdersID ') -and ($r.Out -notmatch 'memOrdersOLDCOL ') -and ($r.Out -notmatch 'memTools(ID|NAME) ')) $r.Out
  Check 'W1c hiding a field is unchecked' ($r.Out -match 'memOrdersNOTE Visible: True -> False\n  \(unchecked\)') $r.Out
  Check 'W1d no byte written, no backup' (($hd -eq (Hash $dfm)) -and ($hp -eq (Hash $pas)) -and ($hr -eq (Hash $y)) -and ((Backups $forms).Count -eq 0) -and (Has $r 'dry run: nothing written')) $r.Out
  Check 'W1e graphical rows are reported' (Has $r 'warning: uAllKinds.dfm memOrders: graphical columns are grid columns, not written: STATUS') $r.Out
  $r = Write-Dfm @('--dataset', 'memorders', '--names', 'TOTAL,SUMQ,BIG,TOOL,ID,QTY,NOTE,USEDCOL')
  Check 'W2a a lookup pulls its key in, each kind has its class' (($r.Code -eq 0) -and (Has $r "insert uAllKinds.dfm memOrdersTOOLID:  -> TIntegerField; FieldName = 'TOOLID'") -and (Has $r "memOrdersTOOL:  -> TStringField; DisplayLabel = 'Tool'; FieldKind = fkLookup; FieldName = 'TOOL'; LookupDataSet = memTools; LookupKeyFields = 'ID'; LookupResultField = 'NAME'; KeyFields = 'TOOLID'; Size = 30; Lookup = True") -and (Has $r 'memOrdersSUMQ:  -> TAggregateField;') -and (Has $r 'FieldKind = fkInternalCalc') -and (Has $r 'Calculated = True')) $r.Out
  Check 'W2b a field that is not selected: delete, unchecked' ($r.Out -match "\] delete uAllKinds\.dfm memOrdersOLDCOL: TIntegerField; FieldName = 'OLDCOL' -> \n  \(unchecked\)") $r.Out
  $ru = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID')
  Check 'W2c a field the code uses cannot be removed' ($ru.Out -match 'delete uAllKinds\.dfm memOrdersUSEDCOL: [^\n]*\n  BLOCKED: used in the code of the unit') $ru.Out
  Check 'W2d a field that would be removed gets no property change' ($ru.Out -match 'update uAllKinds\.dfm memOrdersQTY DisplayLabel[^\n]*\n  BLOCKED: the field is not in the selection') $ru.Out
  $ra = Write-Dfm @('--dataset', 'memOrders', '--names', 'all')
  Check 'W2e all: every kind but the graphical one' (($ra.Out -match 'insert uAllKinds\.dfm memOrdersPRICE:  -> TBCDField; FieldName = ''PRICE''; DisplayFormat = ''0\.00''; Size = 2') -and (Has $ra 'memOrdersWHENAT:  -> TSQLTimeStampField') -and (Has $ra 'memOrdersDESCR:  -> TMemoField') -and (Has $ra 'memOrdersFLAG:  -> TBooleanField') -and -not (Has $ra 'memOrdersSTATUS')) $ra.Out
  # ---- apply ----
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all', '--apply')
  $n = [regex]::Matches($r.Out, '(?m)^replacing ').Count
  Check 'W3a --apply: one log line per checked change (6 properties, 9 fields)' (($r.Code -eq 0) -and ($n -eq 15) -and (Has $r 'applied: 15 changes')) $r.Out
  $newDfm = Text $dfm; $newPas = Text $pas
  Check 'W3b the DFM is the golden one, byte for byte' ($newDfm -ceq (Text (Join-Path $src 'uAllKinds.expected.dfm'))) $newDfm
  Check 'W3c the unit is the golden one, byte for byte' ($newPas -ceq (Text (Join-Path $src 'uAllKinds.expected.pas'))) $newPas
  $bk = Backups $forms
  Check 'W3d backups hold the old bytes' (($bk.Count -eq 2) -and ((Hash ($bk | Where-Object Name -like '*.dfm.*').FullName) -eq $hd) -and ((Hash ($bk | Where-Object Name -like '*.pas.*').FullName) -eq $hp)) ($bk.Name -join ' ')
  # independent of the golden files: take the planned lines out again
  $keep = (($newPas -split "`r`n") | Where-Object { $_ -notmatch 'memOrders(BIG|DESCR|FLAG|PRICE|SUMQ|TOOLID|TOTAL|WHENAT|TOOL)\b' }) -join "`r`n"
  Check 'W3e the unit: only declarations were added' ($keep -ceq $oldPas) $keep
  $cut = [regex]::Replace($newDfm, "(?ms)^    object memOrders(BIG|DESCR|FLAG|PRICE|SUMQ|TOOLID|TOTAL|WHENAT|TOOL): .*?^    end\r\n", '')
  $want = $oldDfm.Replace("DisplayLabel = 'Qty'", "DisplayLabel = 'It'#39's a quantity, '#233'!'").Replace("      Visible = False`r`n", '').Replace("DisplayFormat = '0'", "DisplayFormat = '#,##0'`r`n      EditFormat = '0'").Replace("      FieldName = 'NOTE'`r`n      Size = 40", "      DisplayWidth = 33`r`n      FieldName = 'NOTE'`r`n      Size = 80")
  Check 'W3f the DFM: only the planned changes' ($cut -ceq $want) $cut
  # ---- round trip ----
  $rr = Read-Dfm @()
  Check 'W4a read-dfm finds no difference' (($rr.Code -eq 0) -and (Has $rr 'direction dfm-to-repo, 0 changes, 0 blocked, 0 unchecked') -and (Has $rr 'memOrders (TFDMemTable) -> ORDERS: 10 data, 1 calc, 1 lookup, 1 internal-calc, 1 aggregate')) $rr.Out
  $h2 = Hash $dfm; $h3 = Hash $pas
  $rw = Write-Dfm @('--dataset', 'memOrders', '--names', 'all', '--apply')
  Check 'W4b a second write has nothing to do and writes nothing' (($rw.Code -eq 0) -and (Has $rw 'applied: 0 changes') -and ($h2 -eq (Hash $dfm)) -and ($h3 -eq (Hash $pas)) -and ((Backups $forms).Count -eq 2)) $rw.Out
  $conv = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\convert.exe'
  $cd = Join-Path $work 'conv'; [IO.Directory]::CreateDirectory($cd) | Out-Null
  [IO.File]::Copy($dfm, (Join-Path $cd 'a.dfm'))
  $null = & $conv -i -b (Join-Path $cd 'a.dfm') 2>&1
  $first = [IO.File]::ReadAllBytes((Join-Path $cd 'a.dfm'))[0]
  $null = & $conv -i -t (Join-Path $cd 'a.dfm') 2>&1
  Check 'W5 convert.exe: to binary and back gives the same text' (($first -in 0xFF, 0x54) -and ((Text (Join-Path $cd 'a.dfm')) -ceq $newDfm)) "first byte $first"
  # ---- compiled ----
  if (-not $SkipForm) {
    $before = BuildForm (NewForms 'load0')
    Check 'W6a control: the form loads before the write' (($before -match 'LOADED$') -and ($before -match 'columns=2,2') -and ([regex]::Matches($before, 'published=TRUE').Count -eq 5)) $before
    $after = BuildForm $forms
    Check 'W6b the written form compiles and loads, every field is published' (($after -match 'LOADED$') -and ([regex]::Matches($after, 'published=TRUE').Count -eq 14) -and ($after -notmatch 'published=FALSE')) $after
    Check 'W6c kinds and properties as Delphi sees them' (($after -match 'memOrdersQTY\|TIntegerField\|fkData\|QTY\|label=It''s a quantity, #233!\|visible=TRUE\|align=2') -and ($after -match 'memOrdersTOTAL\|TFloatField\|fkCalculated') -and ($after -match 'memOrdersBIG\|TStringField\|fkInternalCalc\|BIG\|label=BIG\|visible=FALSE\|align=0\|size=3') -and ($after -match 'memOrdersSUMQ\|TAggregateField\|fkAggregate') -and ($after -match 'memOrdersNOTE\|TStringField\|fkData\|NOTE\|label=NOTE\|visible=TRUE\|align=0\|size=80') -and ($after -match 'memOrdersPRICE\|TBCDField\|fkData\|PRICE\|label=PRICE\|visible=TRUE\|align=1\|size=2')) $after
    Check 'W6d the lookup works at run time' ($after -match '(?m)^lookup=Drill\r?$') $after
    Check 'W6e the graphical columns are still there' ($after -match '(?m)^columns=2,2\r?$') $after
    # negative control: the DFM alone, without the declarations, must NOT load (why the unit is written too)
    $nc = NewForms 'nodecl'
    Put (Join-Path $nc 'uAllKinds.dfm') $newDfm
    $bad = BuildForm $nc
    Check 'W6f control: without the declarations the same DFM does not load' ($bad -match 'FAILED EClassNotFound') $bad
  }
  # ---- removal ----
  $rm = NewForms 'remove'
  $rdfm = Join-Path $rm 'uAllKinds.dfm'
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,USEDCOL') $rdfm
  $id = IdOf $r 'delete uAllKinds\.dfm memOrdersOLDCOL'
  $sel = Join-Path $work 'sel.txt'
  [IO.File]::WriteAllText($sel, $id)
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,USEDCOL', '--select', $sel) $rdfm
  Check 'W7a --select removes block and declaration, nothing else' (($id -ne '') -and ($r.Code -eq 0) -and ((Text $rdfm) -ceq $oldDfm.Replace("    object memOrdersOLDCOL: TIntegerField`r`n      FieldName = 'OLDCOL'`r`n    end`r`n", '')) -and ((Text (Join-Path $rm 'uAllKinds.pas')) -ceq $oldPas.Replace("    memOrdersOLDCOL: TIntegerField;`r`n", ''))) $r.Out
  if (-not $SkipForm) {
    $after = BuildForm $rm
    Check 'W7b the form without it loads' (($after -match 'LOADED$') -and ($after -notmatch 'OLDCOL') -and ([regex]::Matches($after, 'published=TRUE').Count -eq 4)) $after
  }
  # ---- refusals ----
  $bd = NewForms 'bin'
  $bdfm = Join-Path $bd 'uAllKinds.dfm'
  $null = & $conv -i -b $bdfm 2>&1
  $hb = Hash $bdfm
  $r = Write-Dfm @('--apply') $bdfm
  Check 'W8a a binary DFM is refused and stays the same' (($hb -ne $hd) -and ($r.Code -eq 1) -and (Has $r 'a binary DFM is not written') -and ($hb -eq (Hash $bdfm)) -and ((Backups $bd).Count -eq 0)) $r.Out
  $nd = NewForms 'nounit'
  $ndfm = Join-Path $nd 'uAllKinds.dfm'
  [IO.File]::Delete((Join-Path $nd 'uAllKinds.pas'))
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all') $ndfm
  Check 'W8b no unit: no field is added, property changes stay possible' (($r.Out -match 'insert uAllKinds\.dfm memOrdersBIG: [^\n]*\n  BLOCKED: no unit beside the DFM') -and ($r.Out -match 'update uAllKinds\.dfm memOrdersQTY DisplayLabel: [^\n]*\n\[')) $r.Out
  Put (Join-Path $nd 'uAllKinds.pas') ($oldPas.Replace('Data.DB, ', ''))
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all') $ndfm
  Check 'W8c a unit that does not use Data.DB' ($r.Out -match 'insert uAllKinds\.dfm memOrdersBIG: [^\n]*\n  BLOCKED: the interface section of the unit does not use Data\.DB') $r.Out
  Put (Join-Path $nd 'uAllKinds.pas') ($oldPas.Replace('TfrmAllKinds', 'TfrmOther'))
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all') $ndfm
  Check 'W8d a unit without the form class' ($r.Out -match 'BLOCKED: uAllKinds\.pas: class TfrmAllKinds is not declared') $r.Out
  Put (Join-Path $nd 'uAllKinds.pas') $oldPas
  $h = Hash $ndfm
  (Get-Item -LiteralPath (Join-Path $nd 'uAllKinds.pas')).IsReadOnly = $true
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all', '--apply') $ndfm
  (Get-Item -LiteralPath (Join-Path $nd 'uAllKinds.pas')).IsReadOnly = $false
  Check 'W8e a read-only unit: nothing is written, not even the DFM' (($r.Code -eq 1) -and (Has $r 'cannot be written') -and ($h -eq (Hash $ndfm)) -and ((Backups $nd).Count -eq 0)) $r.Out
  # ---- usage ----
  $h = Hash $ndfm
  [IO.File]::WriteAllText($sel, "999`n")
  $codes = @(
    (Run @('repo', 'write-dfm', '--repo', $y, '--dfm', $ndfm, '--apply')).Code,
    (Run @('repo', 'write-dfm', '--repo', $y, '--dfm', $ndfm, '--direction', 'dfm-to-repo', '--apply')).Code,
    (Run @('repo', 'write-dfm', '--repo', $y, '--direction', 'repo-to-dfm', '--apply')).Code,
    (Write-Dfm @('--select', $sel) $ndfm).Code,
    (Write-Dfm @('--names', 'ID', '--apply') $ndfm).Code,
    (Write-Dfm @('--dataset', 'memOrders', '--names', 'NOPE', '--apply') $ndfm).Code,
    (Write-Dfm @('--dataset', 'nope', '--apply') $ndfm).Code,
    (Write-Dfm @('--apply', '--dry-run') $ndfm).Code,
    (Write-Dfm @('--apply') (Join-Path $nd 'missing.dfm')).Code) -join ','
  Check 'W9 usage errors exit 2, failures 1, --dry-run wins; nothing written' (($codes -eq '2,2,2,2,2,2,1,0,1') -and ($h -eq (Hash $ndfm)) -and ((Backups $nd).Count -eq 0)) $codes
  # ---- the rest ----
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all') $ndfm
  [IO.File]::WriteAllText($sel, (IdOf $r 'insert uAllKinds\.dfm memOrdersTOOL:'))
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all', '--select', $sel) $ndfm
  Check 'W10a a lookup without its key field is refused' (($r.Code -eq 1) -and ($r.Out -match 'change \d+ needs change \d+ \(select it too\)') -and ($h -eq (Hash $ndfm))) $r.Out
  $od = Join-Path $work 'other'; [IO.Directory]::CreateDirectory($od) | Out-Null
  $odfm = Join-Path $od 'uOther.dfm'
  Put $odfm @'
inherited frmOther: TfrmOther
  inherited memOrders: TFDMemTable
    UpdateOptions.UpdateTableName = 'ORDERS'
    inherited memOrdersQTY: TIntegerField
      DisplayLabel = 'Mine'
      FieldName = 'QTY'
    end
    inherited memOrdersNOTE: TStringField
      DisplayWidth = 5
    end
  end
  object tblOrders: TTable
    TableName = 'Orders.DB'
    object tblOrdersQTY: TIntegerField
      FieldName = 'QTY'
    end
  end
  object qryOrders: TFDQuery
    SQL.Strings = (
      'SELECT O.ID, O.QTY AS HOWMANY FROM ORDERS O')
    object qryOrdersHOWMANY: TIntegerField
      FieldName = 'HOWMANY'
    end
  end
  object qryJoin: TFDQuery
    SQL.Strings = (
      'SELECT * FROM ORDERS, TOOLS')
  end
end
'@
  Put (Join-Path $od 'uOther.pas') "unit uOther;`ninterface`nuses DB;`ntype`n  TfrmOther = class(TfrmBase)`n    tblOrders: TTable;`n    tblOrdersQTY: TIntegerField;`n    qryOrders: TFDQuery;`n    qryOrdersHOWMANY: TIntegerField;`n    qryJoin: TFDQuery;`n  end;`nimplementation`nend.`n"
  $r = Write-Dfm @() $odfm
  Check 'W10b an inherited field: only what it states changes' ((Has $r "memOrdersQTY DisplayLabel: Mine -> It's a quantity") -and ($r.Out -notmatch 'memOrdersQTY (DisplayFormat|EditFormat|Alignment)') -and (Has $r '1 inherited fields not written')) $r.Out
  Check 'W10c a SELECT alias: the column behind it' (Has $r 'qryOrdersHOWMANY DisplayFormat:  -> #,##0') $r.Out
  Check 'W10d a join has no table' (Has $r 'qryJoin (TFDQuery) <- UNRESOLVED (the SQL reads 2 tables)') $r.Out
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID') $odfm
  Check 'W10e no field is added to an inherited dataset' ($r.Out -match 'insert [^\n]*memOrdersID[^\n]*\n  BLOCKED: the dataset is inherited') $r.Out
  $r = Write-Dfm @('--dataset', 'tblOrders', '--names', 'ID,TOTAL') $odfm
  Check 'W10f a BDE dataset: no column field, a calc field yes' (($r.Out -match 'insert uOther\.dfm tblOrdersID: [^\n]*\n  BLOCKED: the repository holds the Firebird type') -and ($r.Out -match 'insert uOther\.dfm tblOrdersTOTAL: [^\n]*\n(?!  BLOCKED)')) $r.Out
  $r = Write-Dfm @('--dataset', 'qryOrders', '--names', 'ID,QTY,PRICE') $odfm
  Check 'W10g a column the SELECT does not return is not added' (($r.Out -match 'insert uOther\.dfm qryOrdersPRICE: [^\n]*\n  BLOCKED: the SQL does not return it') -and ($r.Out -match "insert uOther\.dfm qryOrdersID:  -> TIntegerField; FieldName = 'ID'\n(?!  BLOCKED)") -and ($r.Out -notmatch 'insert uOther\.dfm qryOrdersQTY')) $r.Out
  $r = Write-Dfm @('--dataset', 'qryJoin', '--names', 'ID') $odfm
  Check 'W10h a selection needs a table' (($r.Code -eq 2) -and (Has $r 'qryJoin has no table')) $r.Out
  $z = Join-Path $work 'z.dlrepo'
  EditRepo $y $z { param($t) SetCol (SetCol (SetCol $t 'ORDERS|TOOL' 'SOURCEKEY' 'QTY') 'ORDERS|TOTAL' 'FIELD_KIND' '1') 'ORDERS|NOTE' 'DISPLAY_FORMAT' '0.0' }
  $r = Write-Dfm @() $dfm $z
  Check 'W10i lookup wiring follows the repository' ($r.Out -match 'memOrdersTOOL KeyFields: TOOLID -> QTY\n(?!  )') $r.Out
  Check 'W10j a changed kind is unchecked' ($r.Out -match 'memOrdersTOTAL FieldKind: fkCalculated -> fkData\n  \(unchecked\)') $r.Out
  Check 'W10k a property the class does not have is blocked' ($r.Out -match 'memOrdersNOTE DisplayFormat:  -> 0\.0\n  BLOCKED: TStringField has no property DisplayFormat') $r.Out
  [IO.File]::WriteAllText($sel, (IdOf $r 'update uAllKinds\.dfm memOrdersTOTAL FieldKind'))
  $kd = NewForms 'kind'
  $kdfm = Join-Path $kd 'uAllKinds.dfm'
  Put $kdfm $newDfm; Put (Join-Path $kd 'uAllKinds.pas') $newPas
  $r = Write-Dfm @('--select', $sel) $kdfm $z
  $kindWant = $newDfm.Replace("      FieldKind = fkCalculated`r`n      FieldName = 'TOTAL'`r`n      DisplayFormat = '0.00'`r`n      Calculated = True`r`n", "      FieldName = 'TOTAL'`r`n      DisplayFormat = '0.00'`r`n")
  Check 'W10l a chosen kind change rewrites FieldKind and Calculated only' (($r.Code -eq 0) -and ($kindWant -cne $newDfm) -and ((Text $kdfm) -ceq $kindWant)) ($r.Out + (Text $kdfm))
  Put (Join-Path $kd 'uAllKinds.pas') $oldPas
  Put $kdfm $oldDfm.Replace("  object Image: TImage", "  object memTools2: TFDMemTable`r`n    UpdateOptions.UpdateTableName = 'TOOLS'`r`n  end`r`n  object Image: TImage")
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all') $kdfm
  Check 'W10m two datasets of the lookup table: named, not guessed' ($r.Out -match 'memOrdersTOOL: [^\n]*\n  BLOCKED: 2 datasets read TOOLS: memTools memTools2') $r.Out
  $lf = $oldDfm.Replace("`r`n", "`n").Replace("Caption = 'All field kinds'", "Caption = 'Caf" + [char]0xE9 + "'")
  [IO.File]::WriteAllText($kdfm, $lf, [Text.Encoding]::Latin1); Put (Join-Path $kd 'uAllKinds.pas') $oldPas
  $r = Write-Dfm @('--apply') $kdfm
  $lfWant = $want.Replace("`r`n", "`n").Replace("Caption = 'All field kinds'", "Caption = 'Caf" + [char]0xE9 + "'")
  Check 'W10n LF line ends and an ANSI byte stay' (($r.Code -eq 0) -and ((Text $kdfm) -ceq $lfWant)) $r.Out
  $o = & $Exe repo write-dfm --repo $y --dfm $ndfm --direction repo-to-dfm --dataset memOrders --names all --json 2>$null
  $j = ($o -join "`n") | ConvertFrom-Json
  Check 'W11 --json: one object, the same change set' (($j.changeSet.direction -eq 'repo-to-dfm') -and ($j.changeSet.count -eq 16) -and ($j.applied -eq 0) -and ($j.datasets.Count -eq 1)) ($o -join "`n")
}
finally {
  if ($env:DL_KEEP_WORKDIR -ne '1') { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "kept: $work" }
}
if ($script:Failed) { Write-Host "REPO WRITE-DFM: FAIL ($($script:Count) checks)" -ForegroundColor Red; exit 1 }
Write-Host "REPO WRITE-DFM: PASS ($($script:Count) checks)" -ForegroundColor Green
exit 0
