#Requires -Version 7.3
<#
  run_fieldrepo_dfmwrite.ps1 -- TT-DFMWRITE (1.54): `repo write-dfm`, the field repository -> DFM change set.

  PART 1  builds and runs tests\fieldrepo\DfmWriteTests.dpr (byte-level DFM and unit editors, literals, field classes).
  PART 2  the built engine on tests\fixtures\fieldrepo\dfmwrite (data, calc, internal-calc, lookup, aggregate fields; a
          graphical DBTable column and a graphical tree-list column):
    W1  dry run: the change set, no byte written, no backup
    W2  a selection: lookup keys added, graphical rows never fields, removals unchecked, blocked when the form needs them
    W3  --apply: golden bytes, everything else byte for byte, backup = the old bytes, one log line per change
    W4  round trip: read-dfm sees no difference, write-dfm plans nothing more and writes nothing
    W5  convert.exe: to binary and back gives the same text
    W6  the form compiles and LOADS before and after (linked DFM, published fields, lookup value, graphical columns kept)
    W7  removal with --select: DFM block and declaration go, nothing else, the form still loads
    W8  refusals: binary DFM, no unit, no Data.DB, no class, read-only unit; nothing written
    W9  usage: direction, selection, --select errors; --dry-run wins
    W10 needed changes, inherited and BDE datasets, SQL aliases, lookup wiring, changed kind, LF + ANSI forms
    W11 --json
    W12 a lookup whose current dataset has no known table is never rewired (frames, modules, joins)
    W13 a field the form or its unit binds by name is not removed
    W14 --select needs the plan its ids are from
    W15 the first persistent field of a dataset is unchecked
    W16 conditional directives in the unit
    W17 two forms, one form given twice
    W18 the parts of one lookup wiring are written together
    W19 no selected change names a field that the same selection deletes
    W20 an inherited lookup gets its whole wiring or none
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
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Write-Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:y) { Run (@('repo', 'write-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'repo-to-dfm') + $more) }
function Read-Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:y) { Run (@('repo', 'read-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'dfm-to-repo') + $more) }
function Has($r, $text) { $r.Out.Contains($text) }
function Hash($f) { (Get-FileHash -LiteralPath $f).Hash }
function Text($f) { [IO.File]::ReadAllText($f, [Text.Encoding]::Latin1) }
function Put($f, $t) { [IO.File]::WriteAllText($f, $t.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::Latin1) }
function IdOf($r, $pattern) { $m = [regex]::Match($r.Out, '(?m)^\[(\d+)\] ' + $pattern); if ($m.Success) { $m.Groups[1].Value } else { '' } }
function PlanOf($r) { $m = [regex]::Match($r.Out, '(?m)^# plan ([0-9a-f]{16})$'); if ($m.Success) { $m.Groups[1].Value } else { 'none' } }
# a --select file: the plan line of the dry run and the ids
function PutSel($f, $r, $ids) { [IO.File]::WriteAllText($f, "# plan $(PlanOf $r)`n" + (@($ids) -join "`n")) }
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
  (& { $ErrorActionPreference = 'Continue'; & (Join-Path $dir 'AllKindsLoad.exe') 2>&1 | ForEach-Object { "$_" } }) -join "`n"
}
try {
  # ---- part 1 ----
  if (-not $SkipUnit) {
    $bat = Join-Path $Repo 'build\_build_fieldrepo_dfmwrite_tests_local.bat'
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'U0 the unit tests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: E\d+')) $blog
    $u = (& { $ErrorActionPreference = 'Continue'; & (Join-Path $work 'DfmWriteTests.exe') 2>&1 | ForEach-Object { "$_" } })
    $uc = $LASTEXITCODE
    $u | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $sum = ($u | Where-Object { $_ -match '^Summary: ' } | Select-Object -Last 1)
    Check "U1 unit tests ($sum), none skipped" (($uc -eq 0) -and ($sum -eq 'Summary: pass=164 fail=0')) $sum
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
  # 1.55 Q3(1): a graphical row whose column the form lacks is written (run_v155_GRIDCOL.ps1); GridViewSTATUS is STATUS's column
  Check 'W1e a graphical row whose column the form has: nothing planned, nothing to warn' (($r.Out -notmatch 'GridViewSTATUS') -and -not (Has $r 'graphical column')) $r.Out
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
  Check 'W4a read-dfm finds no difference in a field (the two grid columns the repository never read are the only changes)' (($rr.Code -eq 0) -and (Has $rr 'direction dfm-to-repo, 2 changes, 0 blocked, 0 unchecked') -and ([regex]::Matches($rr.Out, '(?m)^\[\d+\] insert DL_GRID_COLUMNS frmAllKinds\|GridView\|').Count -eq 2) -and (Has $rr 'memOrders (TFDMemTable) -> ORDERS: 10 data, 1 calc, 1 lookup, 1 internal-calc, 1 aggregate')) $rr.Out
  $h2 = Hash $dfm; $h3 = Hash $pas
  $rw = Write-Dfm @('--dataset', 'memOrders', '--names', 'all', '--apply')
  Check 'W4b a second write has nothing to do and writes nothing' (($rw.Code -eq 0) -and (Has $rw 'applied: 0 changes') -and ($h2 -eq (Hash $dfm)) -and ($h3 -eq (Hash $pas)) -and ((Backups $forms).Count -eq 2)) $rw.Out
  $conv = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\convert.exe'
  $cd = Join-Path $work 'conv'; [IO.Directory]::CreateDirectory($cd) | Out-Null
  [IO.File]::Copy($dfm, (Join-Path $cd 'a.dfm'))
  $null = & { $ErrorActionPreference = 'Continue'; & $conv -i -b (Join-Path $cd 'a.dfm') 2>&1 | ForEach-Object { "$_" } }
  $first = [IO.File]::ReadAllBytes((Join-Path $cd 'a.dfm'))[0]
  $null = & { $ErrorActionPreference = 'Continue'; & $conv -i -t (Join-Path $cd 'a.dfm') 2>&1 | ForEach-Object { "$_" } }
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
  PutSel $sel $r $id
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,USEDCOL', '--select', $sel) $rdfm
  Check 'W7a --select removes block and declaration, nothing else' (($id -ne '') -and ($r.Code -eq 0) -and ((Text $rdfm) -ceq $oldDfm.Replace("    object memOrdersOLDCOL: TIntegerField`r`n      FieldName = 'OLDCOL'`r`n    end`r`n", '')) -and ((Text (Join-Path $rm 'uAllKinds.pas')) -ceq $oldPas.Replace("    memOrdersOLDCOL: TIntegerField;`r`n", ''))) $r.Out
  if (-not $SkipForm) {
    $after = BuildForm $rm
    Check 'W7b the form without it loads' (($after -match 'LOADED$') -and ($after -notmatch 'OLDCOL') -and ([regex]::Matches($after, 'published=TRUE').Count -eq 4)) $after
  }
  # ---- refusals ----
  $bd = NewForms 'bin'
  $bdfm = Join-Path $bd 'uAllKinds.dfm'
  $null = & { $ErrorActionPreference = 'Continue'; & $conv -i -b $bdfm 2>&1 | ForEach-Object { "$_" } }
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
  PutSel $sel (Write-Dfm @() $ndfm) '999'
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
  PutSel $sel $r (IdOf $r 'insert uAllKinds\.dfm memOrdersTOOL:')
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'all', '--select', $sel) $ndfm
  Check 'W10a a lookup without its key field is refused, a usage error' (($r.Code -eq 2) -and ($r.Out -match 'change \d+ needs change \d+ \(select it too\)') -and ($h -eq (Hash $ndfm))) $r.Out
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
  # 1.55 owner ruling 2026-11-26: BDE policy is per project (fieldrepo.bde); with no setting (full) a BDE dataset gets column fields like any other; readonly / none: run_v155_DFMWRITE2 B2
  Check 'W10f a BDE dataset, no fieldrepo.bde setting: the column field and the calc field are planned' (($r.Out -match 'insert uOther\.dfm tblOrdersID: [^\n]*\n(?!  BLOCKED)') -and ($r.Out -match 'insert uOther\.dfm tblOrdersTOTAL: [^\n]*\n(?!  BLOCKED)')) $r.Out
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
  $kd = NewForms 'kind'
  $kdfm = Join-Path $kd 'uAllKinds.dfm'
  Put $kdfm $newDfm; Put (Join-Path $kd 'uAllKinds.pas') $newPas
  $r = Write-Dfm @() $kdfm $z
  PutSel $sel $r (IdOf $r 'update uAllKinds\.dfm memOrdersTOTAL FieldKind')
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
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe repo write-dfm --repo $y --dfm $ndfm --direction repo-to-dfm --dataset memOrders --names all --json 2>$null }
  $j = ($o -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }
  Check 'W11 --json: one object, the same change set, the plan id' (($j.plan -match '^[0-9a-f]{16}$') -and($j.changeSet.direction -eq 'repo-to-dfm') -and ($j.changeSet.count -eq 16) -and ($j.applied -eq 0) -and ($j.datasets.Count -eq 1)) ($o -join "`n")
  # ---- H1: lookups ----
  $ld = Join-Path $work 'look'; [IO.Directory]::CreateDirectory($ld) | Out-Null
  $ldfm = Join-Path $ld 'uLook.dfm'
  function LookForm($current, $datasets) {
    Put $ldfm ("object frmLook: TfrmLook`n  object qryMain: TFDQuery`n    UpdateOptions.UpdateTableName = 'ORDERS'`n    object qryMainTOOLID: TIntegerField`n      FieldName = 'TOOLID'`n    end`n    object qryMainQTY: TIntegerField`n      FieldName = 'QTY'`n    end`n" +
      "    object qryMainTOOL: TStringField`n      FieldKind = fkLookup`n      FieldName = 'TOOL'`n      LookupDataSet = $current`n      LookupKeyFields = 'ID'`n      LookupResultField = 'NAME'`n      KeyFields = 'QTY'`n      Size = 30`n      Lookup = True`n    end`n  end`n$datasets`nend`n")
  }
  $oneTool = "  object qryOneTool: TFDQuery`n    SQL.Strings = (`n      'SELECT ID, NAME FROM TOOLS WHERE ID = :ID')`n  end"
  Put (Join-Path $ld 'uLook.pas') "unit uLook;`ninterface`nuses Data.DB;`ntype`n  TfrmLook = class(TForm)`n    qryMain: TFDQuery;`n  end;`nimplementation`nend.`n"
  $plainTool = "  object qryTools: TFDQuery`n    SQL.Strings = (`n      'SELECT ID, NAME, '':x &z'' AS X FROM TOOLS /* :y !z */')`n  end"
  $other = "  object qryOther: TFDQuery`n    SQL.Strings = (`n      'SELECT ID FROM ORDERS')`n  end`n"
  LookForm 'qryToolsJoin' "  object qryToolsJoin: TFDQuery`n    SQL.Strings = (`n      'SELECT T.ID, T.NAME FROM TOOLS T JOIN ORDERS O ON O.TOOLID = T.ID')`n  end`n$oneTool"
  $r = Write-Dfm @() $ldfm
  Check 'W12a a lookup into a join is not rewired' ($r.Out -match 'qryMainTOOL LookupDataSet: qryToolsJoin -> TOOLS\n  BLOCKED: the table of the current lookup dataset qryToolsJoin is not known: the SQL reads 2 tables') $r.Out
  Check 'W12b nor is any part of its wiring' (($r.Out -match 'qryMainTOOL KeyFields: QTY -> TOOLID\n  BLOCKED: the table of') -and ($r.Out -notmatch '-> qryOneTool')) $r.Out
  $h = Hash $ldfm
  $r = Write-Dfm @('--apply') $ldfm
  Check 'W12c --apply leaves it alone' (($r.Code -eq 0) -and ((Text $ldfm) -match 'LookupDataSet = qryToolsJoin\r\n') -and ((Text $ldfm) -match "KeyFields = 'QTY'\r\n")) $r.Out
  LookForm 'tblTools' "  inherited tblTools: TFDTable`n    Left = 8`n  end`n$oneTool"
  $r = Write-Dfm @() $ldfm
  Check 'W12d an inherited table that does not restate TableName' ($r.Out -match 'LookupDataSet: tblTools -> TOOLS\n  BLOCKED: the table of the current lookup dataset tblTools is not known: no TableName') $r.Out
  LookForm 'dmMain.tblTools' $oneTool
  $r = Write-Dfm @() $ldfm
  Check 'W12e a data module of another folder' ($r.Out -match 'LookupDataSet: dmMain\.tblTools -> TOOLS\n  BLOCKED: the current lookup dataset dmMain\.tblTools is not in the form') $r.Out
  LookForm 'Frame1.tblTools' "  inline Frame1: TFrame1`n    object tblTools: TFDTable`n      TableName = 'TOOLS'`n    end`n  end`n$oneTool"
  $r = Write-Dfm @() $ldfm
  Check 'W12f a dataset in a frame is found by its qualified name: no change' (($r.Out -notmatch 'LookupDataSet') -and ($r.Out -match 'qryMainTOOL KeyFields: QTY -> TOOLID\n(?!  )')) $r.Out
  LookForm 'qryOther' "  object qryOther: TFDQuery`n    SQL.Strings = (`n      'SELECT ID FROM ORDERS')`n  end`n$plainTool"
  $r = Write-Dfm @() $ldfm
  Check 'W12g control: a current dataset that reads another table is rewired' (($r.Out -match 'qryMainTOOL LookupDataSet: qryOther -> qryTools\n(?!  )') -and ($r.Out -match 'qryMainTOOL KeyFields: QTY -> TOOLID\n(?!  )')) $r.Out
  LookForm 'qryOther' "  object qryOther: TFDQuery`n    SQL.Strings = (`n      'SELECT ID FROM ORDERS')`n  end`n  inline Frame1: TFrame1`n    object tblTools: TFDTable`n      TableName = 'TOOLS'`n    end`n  end"
  $r = Write-Dfm @() $ldfm
  Check 'W12h a dataset inside a frame is no new target' ($r.Out -match 'LookupDataSet: qryOther -> TOOLS\n  BLOCKED: the only dataset that reads TOOLS, Frame1\.tblTools, is inside a frame') $r.Out
  Put $ldfm "inherited frmLook: TfrmLook`n  inherited qryMain: TFDQuery`n    UpdateOptions.UpdateTableName = 'ORDERS'`n    inherited qryMainTOOL: TStringField`n      FieldKind = fkLookup`n      FieldName = 'TOOL'`n    end`n  end`n$oneTool`nend`n"
  $r = Write-Dfm @() $ldfm
  Check 'W12i an inherited lookup that states no wiring gets none' (($r.Code -eq 0) -and ($r.Out -notmatch 'LookupDataSet|KeyFields|LookupResult')) $r.Out
  $param = 'the only dataset that reads TOOLS, qryOneTool, has SQL parameters'
  LookForm 'qryOther' ($other + $oneTool)
  $r = Write-Dfm @() $ldfm
  Check 'W12j a query with parameters is no new target' ($r.Out -match "LookupDataSet: qryOther -> TOOLS\n  BLOCKED: $param") $r.Out
  $bound = "  object dsMain: TDataSource`n    DataSet = qryMain`n  end`n  object tblTools: TFDTable`n    MasterSource = dsMain`n    TableName = 'TOOLS'`n  end"
  LookForm 'qryOther' ($other + $bound)
  $r = Write-Dfm @() $ldfm
  Check 'W12k nor is a dataset bound to a master' ($r.Out -match 'LookupDataSet: qryOther -> TOOLS\n  BLOCKED: the only dataset that reads TOOLS, tblTools, is bound to a master \(MasterSource\)') $r.Out
  LookForm 'qryOneTool' $oneTool
  $r = Write-Dfm @() $ldfm
  Check 'W12l a current target with parameters stays, its wiring is not changed' (($r.Out -notmatch 'LookupDataSet:') -and ($r.Out -match 'qryMainTOOL KeyFields: QTY -> TOOLID\n  BLOCKED: the current lookup dataset qryOneTool has SQL parameters')) $r.Out
  $noTool = "object frmLook: TfrmLook`n  object qryMain: TFDQuery`n    UpdateOptions.UpdateTableName = 'ORDERS'`n    object qryMainTOOLID: TIntegerField`n      FieldName = 'TOOLID'`n    end`n  end`n"
  Put $ldfm ($noTool + "$oneTool`nend`n")
  $r = Write-Dfm @('--dataset', 'qryMain', '--names', 'TOOL') $ldfm
  Check 'W12m a new lookup into a query with parameters is blocked' ($r.Out -match "insert uLook\.dfm qryMainTOOL: [^\n]*\n  BLOCKED: $param") $r.Out
  Put $ldfm ($noTool + "$plainTool`nend`n")
  $r = Write-Dfm @('--dataset', 'qryMain', '--names', 'TOOL') $ldfm
  Check 'W12n control: a colon in a SQL string or comment is no parameter' ($r.Out -match "insert uLook\.dfm qryMainTOOL: [^\n]*LookupDataSet = qryTools[^\n]*\n(?!  )") $r.Out
  # a data module named by the unit
  $lpas = Text (Join-Path $ld 'uLook.pas')
  Put (Join-Path $ld 'uLook.pas') $lpas.Replace('uses Data.DB;', 'uses Data.DB, uMod;')
  function ModForm($body) { Put (Join-Path $ld 'uMod.dfm') "object dmMod: TdmMod`n$body`nend`n" }
  ModForm $oneTool
  LookForm 'qryOther' $other
  $r = Write-Dfm @() $ldfm
  Check 'W12o the same in a data module' ($r.Out -match 'LookupDataSet: qryOther -> TOOLS\n  BLOCKED: the only dataset that reads TOOLS, dmMod\.qryOneTool, has SQL parameters') $r.Out
  ModForm "  inline Frame1: TFrame1`n    object tblTools: TFDTable`n      TableName = 'TOOLS'`n    end`n  end"
  $r = Write-Dfm @() $ldfm
  Check 'W12p a frame of a module' ($r.Out -match 'LookupDataSet: qryOther -> TOOLS\n  BLOCKED: the only dataset that reads TOOLS, dmMod\.Frame1\.tblTools, is inside a frame') $r.Out
  ModForm $plainTool
  $r = Write-Dfm @() $ldfm
  Check 'W12q control: a plain dataset of a module' ($r.Out -match 'LookupDataSet: qryOther -> dmMod\.qryTools\n(?!  )') $r.Out
  Put (Join-Path $ld 'uLook.pas') $lpas
  # ---- N2: a target whose rows the DFM does not settle ----
  function Query($name, $sql, $props = '') { "  object $name`: TFDQuery`n$props    UpdateOptions.UpdateTableName = 'TOOLS'`n" + $(if ($sql) { "    SQL.Strings = (`n      '$sql')`n" } else { '' }) + '  end' }
  $sets = @(
    @('W12r SQL set in code', (Query 'qryCode' ''), 'has no SELECT in the DFM'),
    @('W12s a SELECT over two tables', (Query 'qryCode' 'SELECT T.ID, T.NAME FROM TOOLS T JOIN ORDERS O ON O.TOOLID = T.ID'), 'has a SELECT that does not read TOOLS alone'),
    @('W12t an unreadable SELECT', (Query 'qryCode' 'SELECT ID, NAME FROM TOOLS UNION SELECT ID, NAME FROM TOOLS'), 'has a SELECT that is not understood'),
    @('W12u Filtered', (Query 'qryCode' 'SELECT ID, NAME FROM TOOLS' "    Filter = 'ID > 1'`n    Filtered = True`n"), 'is filtered'),
    @('W12v macros', (Query 'qryCode' 'SELECT ID, NAME FROM TOOLS &COND'), 'has SQL macros'),
    @('W12w a WHERE', (Query 'qryCode' 'SELECT ID, NAME FROM TOOLS WHERE ID > 1'), 'has a SELECT that may not return all rows \(WHERE\)'),
    @('W12x a memory table', "  object qryCode: TFDMemTable`n    UpdateOptions.UpdateTableName = 'TOOLS'`n  end", 'has no SELECT in the DFM'),
    @('W12y an inherited dataset', "  inherited qryCode: TFDTable`n    TableName = 'TOOLS'`n  end", 'is inherited'))
  function Unwired($dataset) { $t = Text $ldfm; $t.Contains("LookupDataSet = $dataset`r`n") -and $t.Contains(" KeyFields = 'QTY'`r`n") -and $t.Contains("LookupResultField = 'NAME'`r`n") }
  foreach ($s in $sets) {
    LookForm 'qryOther' ($other + $s[1])
    $r = Write-Dfm @('--apply') $ldfm
    Check "$($s[0]): no new target" (($r.Out -match "LookupDataSet: qryOther -> TOOLS\n  BLOCKED: the only dataset that reads TOOLS, qryCode, $($s[2])") -and (Has $r 'applied: ') -and (Unwired 'qryOther')) $r.Out
    LookForm 'qryCode' $s[1]
    $r = Write-Dfm @('--apply') $ldfm
    Check "$($s[0]): already wired there: unchecked with the reason" (($r.Out -match "qryMainTOOL KeyFields: QTY -> TOOLID\n  \(unchecked\)") -and ($r.Out -match "warning: uLook\.dfm qryMainTOOL: the lookup changes are unchecked: the current lookup dataset qryCode $($s[2])") -and (Has $r 'applied: ') -and (Unwired 'qryCode')) $r.Out
    Put $ldfm ($noTool + $s[1] + "`nend`n")
    $r = Write-Dfm @('--dataset', 'qryMain', '--names', 'TOOL') $ldfm
    Check "$($s[0]): a new lookup into it is blocked" ($r.Out -match "insert uLook\.dfm qryMainTOOL: [^\n]*\n  BLOCKED: the only dataset that reads TOOLS, qryCode, $($s[2])") $r.Out
  }
  LookForm 'qryOther' ($other + (Query 'qryCode' 'SELECT ID, NAME FROM TOOLS ORDER BY NAME' "    Filter = 'ID > 1'`n"))
  $r = Write-Dfm @() $ldfm
  Check 'W12z control: a whole SELECT, a filter that is off' (($r.Out -match 'LookupDataSet: qryOther -> qryCode\n(?!  )') -and ($r.Out -notmatch 'unchecked:')) $r.Out
  LookForm 'qryOther' ($other + "  object tblTools: TFDTable`n    TableName = 'TOOLS'`n  end")
  $r = Write-Dfm @() $ldfm
  Check 'W12z control: a table' ($r.Out -match 'LookupDataSet: qryOther -> tblTools\n(?!  )') $r.Out
  # ---- N3: an inherited lookup that states only its dataset ----
  function InheritedLook($tools) {
    Put $ldfm ("inherited frmLook: TfrmLook`n  inherited qryMain: TFDQuery`n    UpdateOptions.UpdateTableName = 'ORDERS'`n$tools    inherited qryMainTOOL: TStringField`n      FieldKind = fkLookup`n      FieldName = 'TOOL'`n      LookupDataSet = qryOther`n    end`n  end`n$other$plainTool`nend`n")
  }
  $toolId = "    inherited qryMainTOOLID: TIntegerField`n      FieldName = 'TOOLID'`n    end`n"
  InheritedLook $toolId
  $r = Write-Dfm @('--apply') $ldfm
  $t = Text $ldfm
  Check 'W20a the key and result field are written with the new dataset' (($r.Code -eq 0) -and (Has $r 'applied: 4 changes') -and ($t -match 'LookupDataSet = qryTools\r\n') -and ($t -match "LookupKeyFields = 'ID'\r\n") -and ($t -match "LookupResultField = 'NAME'\r\n") -and ($t -match " KeyFields = 'TOOLID'\r\n")) ($r.Out + $t)
  InheritedLook ''
  $h = Hash $ldfm
  $r = Write-Dfm @('--apply') $ldfm
  Check 'W20b a part that has no name blocks the wiring' (($r.Out -match 'LookupDataSet: qryOther -> qryTools\n  BLOCKED: part of a lookup wiring that is blocked') -and (Has $r 'qryMain has no field for ORDERS.TOOLID') -and ($h -eq (Hash $ldfm))) $r.Out
  $nv = Join-Path $work 'nv.dlrepo'
  EditRepo $y $nv { param($t) SetCol $t 'ORDERS|TOOL' 'DESTVALUE' '' }
  InheritedLook $toolId
  $h = Hash $ldfm
  $r = Write-Dfm @('--apply') $ldfm $nv
  Check 'W20c the repository does not hold the result column: blocked' (($r.Out -match 'LookupDataSet: qryOther -> qryTools\n  BLOCKED: part of') -and ($r.Out -match 'LookupResultField: [^\n]*\n  BLOCKED: the repository does not hold it') -and ($h -eq (Hash $ldfm))) $r.Out
  LookForm 'qryOther' ($other + $plainTool)
  $r = Write-Dfm @('--apply') $ldfm $nv
  Check 'W20d the same for a field of the form itself' (($r.Out -match 'LookupResultField: NAME -> \n  BLOCKED: the repository does not hold it') -and (Unwired 'qryOther')) $r.Out
  # ---- one wiring, one change ----
  LookForm 'qryOther' ($other + $plainTool)
  Put $ldfm ((Text $ldfm).Replace("LookupResultField = 'NAME'", "LookupResultField = 'ID'"))
  $r = Write-Dfm @() $ldfm
  $wire = @('KeyFields', 'LookupDataSet', 'LookupResultField' | ForEach-Object { IdOf $r "update uLook\.dfm qryMainTOOL $($_):" })
  $h = Hash $ldfm
  $bad = foreach ($i in 0..2) {
    PutSel $sel $r $wire[$i]
    $x1 = Write-Dfm @('--select', $sel) $ldfm
    $miss = @($wire | Where-Object { $_ -ne $wire[$i] }) -join ', '
    if (($x1.Code -ne 2) -or -not (Has $x1 "change $($wire[$i]) needs changes $miss (select them too)") -or ($h -ne (Hash $ldfm))) { $x1.Out }
  }
  Check 'W18a one part alone is refused, the missing ids are named, nothing written' (($wire -notcontains '') -and (-not $bad)) ("$wire" + $bad + $r.Out)
  $h = Hash $ldfm
  PutSel $sel $r $wire[0, 1]
  $x1 = Write-Dfm @('--select', $sel) $ldfm
  Check 'W18b two of three are refused' (($x1.Code -eq 2) -and (Has $x1 "needs change $($wire[2]) (select it too)") -and ($h -eq (Hash $ldfm))) $x1.Out
  PutSel $sel $r $wire
  $x1 = Write-Dfm @('--select', $sel) $ldfm
  $wired = Text $ldfm
  Check 'W18c control: all parts together are written' (($x1.Code -eq 0) -and (Has $x1 'applied: 3 changes') -and ($wired -match "LookupDataSet = qryTools\r\n") -and ($wired -match "LookupResultField = 'NAME'") -and ($wired -match " KeyFields = 'TOOLID'")) ($x1.Out + $wired)
  LookForm 'qryOther' ($other + "  object qryTools: TFDQuery`n    SQL.Strings = (`n      'SELECT ID, NAME FROM TOOLS')`n    object qryToolsID: TIntegerField`n      FieldName = 'ID'`n    end`n  end")
  Put $ldfm ((Text $ldfm).Replace("LookupResultField = 'NAME'", "LookupResultField = 'ID'"))
  $r = Write-Dfm @() $ldfm
  Check 'W18d one blocked part blocks the whole wiring' (($r.Out -match 'LookupResultField: ID -> NAME\n  BLOCKED: qryTools has no field for TOOLS\.NAME') -and ($r.Out -match 'LookupDataSet: qryOther -> qryTools\n  BLOCKED: part of a lookup wiring that is blocked \(change \d+\)') -and ($r.Out -match 'KeyFields: QTY -> TOOLID\n  BLOCKED: part of a lookup wiring that is blocked')) $r.Out
  # ---- a field wired and deleted in one selection ----
  $wz = Join-Path $work 'wz.dlrepo'
  EditRepo $y $wz { param($t) (SetCol $t 'ORDERS|TOOL' 'SOURCEKEY' 'XCOL').Replace('|SUM(QTY)', '|SUM(XCOL)') }
  $all = @('--dataset', 'qryMain', '--names', 'all')
  $more = "    object qryMainXCOL: TIntegerField`n      FieldName = 'XCOL'`n    end`n    object qryMainYCOL: TIntegerField`n      FieldName = 'YCOL'`n    end`n"
  Put (Join-Path $ld 'uLook.pas') "unit uLook;`ninterface`nuses Data.DB;`ntype`n  TfrmLook = class(TForm)`n    qryMain: TFDQuery;`n    qryMainXCOL: TIntegerField;`n    qryMainYCOL: TIntegerField;`n  end;`nimplementation`nend.`n"
  $wpas = Text (Join-Path $ld 'uLook.pas')
  function WireForm { LookForm 'qryTools' $plainTool
    Put $ldfm ((Text $ldfm).Replace("    object qryMainTOOL:", $more + "    object qryMainSUMQ: TAggregateField`n      FieldName = 'SUMQ'`n      Expression = 'SUM(QTY)'`n    end`n    object qryMainTOOL:")) }
  function Both($what, $pattern) {
    $r = Write-Dfm $all $ldfm $wz
    $w = IdOf $r $pattern; $dx = IdOf $r 'delete uLook\.dfm qryMainXCOL'; $dy = IdOf $r 'delete uLook\.dfm qryMainYCOL'
    $h = Hash $ldfm; $hp2 = Hash (Join-Path $ld 'uLook.pas'); $n = (Backups $ld).Count
    PutSel $sel $r @($w, $dx)
    $x1 = Write-Dfm ($all + @('--select', $sel)) $ldfm $wz
    Check "W19 $what`: wiring to a deleted field is refused, nothing written" (($w -ne '') -and ($dx -ne '') -and ($x1.Code -eq 2) -and ($x1.Out -match "deletes qryMainXCOL, but the form would still name 'XCOL': ") -and ($h -eq (Hash $ldfm)) -and ($hp2 -eq (Hash (Join-Path $ld 'uLook.pas'))) -and ($n -eq (Backups $ld).Count)) ($r.Out + $x1.Out)
    PutSel $sel $r @($w, $dy)
    $x1 = Write-Dfm ($all + @('--select', $sel)) $ldfm $wz
    Check "W19 $what`: control: deleting an unrelated field with it works" (($dy -ne '') -and ($x1.Code -eq 0) -and (Has $x1 'applied: 2 changes') -and ((Text $ldfm) -notmatch 'YCOL') -and ((Text $ldfm) -match 'XCOL')) $x1.Out
    Put (Join-Path $ld 'uLook.pas') $wpas
  }
  WireForm
  Both 'KeyFields' 'update uLook\.dfm qryMainTOOL KeyFields: QTY -> XCOL'
  WireForm
  Both 'Expression' 'update uLook\.dfm qryMainSUMQ Expression: SUM\(QTY\) -> SUM\(XCOL\)'
  Put $ldfm ($noTool.Replace("    object qryMainTOOLID", $more + "    object qryMainTOOLID") + "$plainTool`nend`n")
  Both 'a new lookup' 'insert uLook\.dfm qryMainTOOL:'
  # ---- M1: by-name bindings ----
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID') (Join-Path $nd 'uAllKinds.dfm')
  Check 'W13a a column of a tree list binds NOTE (1.55: removed with it, run_v155_DFMWRITE2 E7), a grid QTY; OLDCOL is free' (($r.Out -match "delete uAllKinds\.dfm TreeNOTE: [^\n]*\n  \(unchecked\)\n\[\d+\] delete uAllKinds\.dfm memOrdersNOTE: [^\n]*\n  \(unchecked\)") -and ($r.Out -match 'delete uAllKinds\.dfm memOrdersQTY: [^\n]*\n  BLOCKED: its grid item GridViewQTY cannot be removed: used in the DFM') -and ($r.Out -match 'delete uAllKinds\.dfm memOrdersOLDCOL: [^\n]*\n  \(unchecked\)')) $r.Out
  $r = Write-Dfm @('--dataset', 'memTools', '--names', 'ID') $dfm
  Check 'W13b the result field of a lookup' ($r.Out -match "delete uAllKinds\.dfm memToolsNAME: [^\n]*\n  BLOCKED: the DFM names 'NAME': memOrdersTOOL\.LookupResultField") $r.Out
  $bd2 = Join-Path $work 'bind'; [IO.Directory]::CreateDirectory($bd2) | Out-Null
  $bdf = Join-Path $bd2 'uBind.dfm'
  $fields = (1..16 | ForEach-Object { "    object qryMainF$($_): TIntegerField`n      FieldName = 'F$($_)'`n    end`n" }) -join ''
  Put $bdf ("object frmBind: TfrmBind`n  object dsMain: TDataSource`n    DataSet = qryMain`n  end`n  object Edit: TDBEdit`n    DataField = 'F1'`n    DataSource = dsMain`n  end`n  object Lbl: TLabel`n    Caption = 'F7'`n  end`n" +
    "  object Grid: TDBGrid`n    Columns = <`n      item`n        Expanded = False`n        FieldName = 'F9'`n        Title.Caption = 'F8'`n      end>`n  end`n" +
    "  object qryMain: TFDQuery`n    IndexFieldNames = 'F2:D;ID'`n    UpdateOptions.UpdateTableName = 'ORDERS'`n    object qryMainID: TIntegerField`n      FieldName = 'ID'`n    end`n$fields" +
    "    object qryMainSUM: TAggregateField`n      FieldName = 'SUM'`n      Expression = 'SUM(F3)'`n    end`n    object qryMainLK: TStringField`n      FieldKind = fkLookup`n      FieldName = 'LK'`n      LookupDataSet = qryDet`n      LookupKeyFields = 'A;B'`n      LookupResultField = 'C'`n      KeyFields = 'ID;F4'`n    end`n  end`n" +
    "  object qryDet: TFDQuery`n    MasterSource = dsMain`n    MasterFields = 'ID;F5'`n    SQL.Strings = (`n      'SELECT F8, X FROM DET'`n      'WHERE Y = :F6')`n    object qryDetF7: TIntegerField`n      FieldName = 'F7'`n      Origin = 'F12'`n    end`n  end`nend`n")
  Put (Join-Path $bd2 'uBind.pas') "unit uBind;`ninterface`nuses Data.DB;`ntype`n  TfrmBind = class(TForm)`n  end;`nimplementation`nprocedure P;`nbegin`n  Q.Locate('ID;F10', V, []);`n  ShowMessage('F11 is a word of a text');`n  Q.Filter := 'F13 > 1';`n  Q.IndexFieldNames := 'F14:D';`n  Q.MasterFields := 'A;F15';`n  S := 'F16X, XF16';`nend;`nend.`n"
  $r = Write-Dfm @('--dataset', 'qryMain', '--names', 'ID') $bdf
  $state = (1..16 | ForEach-Object { $m = [regex]::Match($r.Out, "delete uBind\.dfm qryMainF$($_): [^\n]*\n  (BLOCKED: [^\n]*|\(unchecked\))"); if (-not $m.Success) { '?' } elseif ($m.Value -match 'BLOCKED') { 'B' } else { '-' } }) -join ''
  Check 'W13c DataField, IndexFieldNames, Expression, KeyFields, MasterFields, a SQL parameter, a grid column; Locate, Filter, IndexFieldNames, MasterFields and a string in the code that is a reference (FieldByName / Locate / a property of the list); not a word of any other string (ShowMessage), a caption, a selected column, the field of another dataset, a longer word' ($state -eq 'BBBBBB--BB--BBB-') ($state + "`n" + $r.Out)
  # Q17 B (owner 2026-11-26): only REAL references block a field delete -- a caption in the DFM or a word of a message in the code does not
  $q = Join-Path $work 'q17'; [IO.Directory]::CreateDirectory($q) | Out-Null
  $qdfm = Join-Path $q 'uQ.dfm'
  Put $qdfm ("object frmQ: TfrmQ`n  object dsMain: TDataSource`n    DataSet = qryMain`n  end`n  object Lbl: TLabel`n    Caption = 'G1'`n  end`n  object Edit: TDBEdit`n    DataField = 'G2'`n    DataSource = dsMain`n  end`n" +
    "  object qryMain: TFDQuery`n    UpdateOptions.UpdateTableName = 'ORDERS'`n    object qryMainID: TIntegerField`n      FieldName = 'ID'`n    end`n    object qryMainG1: TIntegerField`n      FieldName = 'G1'`n    end`n    object qryMainG2: TIntegerField`n      FieldName = 'G2'`n    end`n" +
    "    object qryMainG3: TIntegerField`n      FieldName = 'G3'`n    end`n    object qryMainG4: TIntegerField`n      FieldName = 'G4'`n    end`n    object qryMainG5: TIntegerField`n      FieldName = 'G5'`n    end`n  end`nend`n")
  Put (Join-Path $q 'uQ.pas') "unit uQ;`ninterface`nuses Data.DB;`ntype`n  TfrmQ = class(TForm)`n  end;`nimplementation`nprocedure P;`nbegin`n  ShowMessage('G1 is a caption, G4 a word');`n  V := qryMain.FieldByName('G3').AsInteger;`n  V := qryMain.FieldValues['G5'];`nend;`nend.`n"
  $r = Write-Dfm @('--dataset', 'qryMain', '--names', 'ID') $qdfm
  $state = (1..5 | ForEach-Object { $m = [regex]::Match($r.Out, "delete uQ\.dfm qryMainG$($_): [^\n]*\n  (BLOCKED: [^\n]*|\(unchecked\))"); if (-not $m.Success) { '?' } elseif ($m.Value -match 'BLOCKED') { 'B' } else { '-' } }) -join ''
  Check 'W13d Q17: a caption (G1) and a word of a message (G1, G4) do not block; DataField (G2), FieldByName (G3) and FieldValues[] (G5) do' ($state -eq '-BB-B') ($state + "`n" + $r.Out)
  # ---- M2: the plan id ----
  $pd = NewForms 'plan'
  $pdfm = Join-Path $pd 'uAllKinds.dfm'; $ppas = Join-Path $pd 'uAllKinds.pas'
  $names = @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,USEDCOL')
  $r = Write-Dfm $names $pdfm
  $again = Write-Dfm $names $pdfm
  $id = IdOf $r 'delete uAllKinds\.dfm memOrdersOLDCOL'
  Check 'W14a the same files and repository: the same plan id' ((PlanOf $r) -eq (PlanOf $again) -and (PlanOf $r) -ne 'none') $r.Out
  PutSel $sel $r $id
  function Refused($what, $more, $repo) {
    $h1 = Hash $pdfm; $h2 = Hash $ppas
    $x1 = Write-Dfm ($more + @('--select', $sel)) $pdfm $repo
    $x2 = Write-Dfm ($more + @('--apply', '--select', $sel)) $pdfm $repo
    Check "W14b $what`: --select and --apply --select are refused, nothing written" (($x1.Code -eq 1) -and ($x2.Code -eq 1) -and ($x1.Out -match 'the plan is now') -and ($h1 -eq (Hash $pdfm)) -and ($h2 -eq (Hash $ppas)) -and ((Backups $pd).Count -eq 0)) ($x1.Out + $x2.Out)
  }
  Put $pdfm $oldDfm.Replace("'All field kinds'", "'All the field kinds'")
  Refused 'the form changed' $names $y
  Put $pdfm $oldDfm; Put $ppas ($oldPas + "{ }`r`n")
  Refused 'the unit changed' $names $y
  Put $ppas $oldPas
  $y2 = Join-Path $work 'y2.dlrepo'
  EditRepo $y $y2 { param($t) SetCol $t 'ORDERS|PRICE' 'DISPLAY_LABEL' 'Cost' }
  Refused 'the repository changed, the change list did not' $names $y2
  Refused 'another selection' @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE') $y
  [IO.File]::WriteAllText($sel, $id)
  $h = Hash $pdfm
  $r = Write-Dfm ($names + @('--select', $sel)) $pdfm
  Check 'W14c no plan line: a usage error, nothing written' (($r.Code -eq 2) -and (Has $r 'has no line') -and ($h -eq (Hash $pdfm)) -and ((Backups $pd).Count -eq 0)) $r.Out
  PutSel $sel $again $id
  $r = Write-Dfm ($names + @('--apply', '--select', $sel)) $pdfm
  Check 'W14d control: the plan is the same again: written' (($r.Code -eq 0) -and (Has $r 'applied: 1 changes') -and ((Text $pdfm) -notmatch 'OLDCOL')) $r.Out
  # ---- M3: the first persistent field ----
  $fd = Join-Path $work 'first'; [IO.Directory]::CreateDirectory($fd) | Out-Null
  $fdfm = Join-Path $fd 'uFirst.dfm'
  Put $fdfm "object frmFirst: TfrmFirst`n  object qryPlain: TFDQuery`n    SQL.Strings = (`n      'SELECT ID, QTY FROM ORDERS')`n  end`nend`n"
  Put (Join-Path $fd 'uFirst.pas') "unit uFirst;`ninterface`nuses Data.DB;`ntype`n  TfrmFirst = class(TForm)`n    qryPlain: TFDQuery;`n  end;`nimplementation`nend.`n"
  $h = Hash $fdfm
  $r = Write-Dfm @('--dataset', 'qryPlain', '--names', 'ID') $fdfm
  Check 'W15a the first persistent field is unchecked, with a warning' (($r.Out -match "insert uFirst\.dfm qryPlainID: [^\n]*\n  \(unchecked\)") -and ($r.Out -match 'warning: uFirst\.dfm qryPlain: has no persistent field\. .*vanish')) $r.Out
  PutSel $sel $r (IdOf $r 'insert uFirst\.dfm qryPlainID')
  $ra = Write-Dfm @('--dataset', 'qryPlain', '--names', 'ID', '--apply') $fdfm
  Check 'W15b --apply writes nothing' ((Has $ra 'applied: 0 changes') -and ($h -eq (Hash $fdfm))) $ra.Out
  $ra = Write-Dfm @('--dataset', 'qryPlain', '--names', 'ID', '--select', $sel) $fdfm
  Check 'W15c control: --select writes it' ((Has $ra 'applied: 1 changes') -and ((Text $fdfm) -match 'object qryPlainID: TIntegerField')) $ra.Out
  $r = Write-Dfm @('--dataset', 'qryPlain', '--names', 'ID,QTY') $fdfm
  Check 'W15d control: the second one is checked' ($r.Out -match "insert uFirst\.dfm qryPlainQTY: [^\n]*\n(?!  )") $r.Out
  # ---- M4: directives ----
  $cd2 = NewForms 'cond'
  $cdfm = Join-Path $cd2 'uAllKinds.dfm'; $cpas = Join-Path $cd2 'uAllKinds.pas'
  $used = "    memOrdersUSEDCOL: TIntegerField;`r`n"
  $demo = $oldPas.Replace($used, "    {`$IFDEF DEMO}`r`n$used    {`$ENDIF}`r`n")
  Put $cpas $demo
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,OLDCOL,USEDCOL,FLAG', '--apply') $cdfm
  Check 'W16a the new declaration goes outside $IFDEF' (($r.Code -eq 0) -and ((Text $cpas) -ceq $demo.Replace("    memOrdersOLDCOL: TIntegerField;`r`n", "    memOrdersOLDCOL: TIntegerField;`r`n    memOrdersFLAG: TBooleanField;`r`n"))) (Text $cpas)
  Put $cdfm $oldDfm
  Put $cpas ($oldPas.Replace('TfrmAllKinds = class(TForm)', 'TfrmAllKinds = class(TForm) {$IFNDEF X}').Replace("  private`r`n", "  {`$ENDIF}`r`n  private`r`n"))
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,OLDCOL,USEDCOL,FLAG') $cdfm
  Check 'W16b no safe place: blocked' ($r.Out -match 'insert uAllKinds\.dfm memOrdersFLAG: [^\n]*\n  BLOCKED: uAllKinds\.pas: no place to declare') $r.Out
  # ---- two forms ----
  $t1 = NewForms 'two1'; $t2 = NewForms 'two2'
  $f1 = Join-Path $t1 'uAllKinds.dfm'; $f2 = Join-Path $t2 'uAllKinds.dfm'
  $r = Write-Dfm @('--apply') "$f1;$f1"
  Check 'W17a one form given twice is planned once' (($r.Code -eq 0) -and (Has $r 'applied: 6 changes') -and ((Text $f1) -ceq $want)) $r.Out
  Put $f1 $oldDfm
  $r = Write-Dfm @('--apply') "$f1;$f2"
  Check 'W17b two forms are both written' (($r.Code -eq 0) -and (Has $r 'applied: 12 changes') -and ((Text $f1) -ceq $want) -and ((Text $f2) -ceq $want)) $r.Out
  Put $f1 $oldDfm
  $null = & { $ErrorActionPreference = 'Continue'; & $conv -i -b $f2 2>&1 | ForEach-Object { "$_" } }
  $n1 = (Backups $t1).Count
  $r = Write-Dfm @('--apply') "$f1;$f2"
  Check 'W17c the second form cannot be written: the first one stays' (($r.Code -eq 1) -and ((Text $f1) -ceq $oldDfm) -and ((Backups $t1).Count -eq $n1)) $r.Out
}
finally {
  if ($env:DL_KEEP_WORKDIR -ne '1') { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "kept: $work" }
}
if ($script:Failed) { Write-Host "REPO WRITE-DFM: FAIL ($($script:Count) checks)" -ForegroundColor Red; exit 1 }
Write-Host "REPO WRITE-DFM: PASS ($($script:Count) checks)" -ForegroundColor Green
exit 0
