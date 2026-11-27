#Requires -Version 7.3
<#
  run_v156_GCW.ps1 -- lane GC-W (1.56): `repo write-dfm` writes the in-place editor of a grid column
  (PropertiesClassName and its Properties.* lines) from DL_GRID_COLUMNS.PROPERTIES_CLASS_NAME / PROPERTIES (schema 5).

  PART 1  builds and runs tests\fieldrepo\GridEditorWriteTests.dpr (TDfmDocument.TryEditor / SetEditor on bytes, every
          written text through the RTL text -> binary -> text).
  PART 2  the built engine on tests\fixtures\fieldrepo\dfmwrite; every check after a write reads the BYTES of the file:
    E1  dry run: one change per column whose editor differs; a class the form does not load yet is unchecked and a
        warning names the unit; a row whose column the form lacks is a warning; no byte written
    E2  --apply leaves the unchecked editors out; --select writes them
    E3  a unit that uses the editor's unit: the changes are checked, --apply writes them; golden bytes of the two
        columns, nothing else in the DFM, the unit untouched
    E4  the written file: a second plan has nothing to do for the editors; convert.exe to binary and back gives the
        same text
    E5  the form compiles and LOADS: the columns have the editor class and its properties
    E6  the same class, other properties: checked without the unit, the stated lines are replaced
    E7  a new grid column (graphical row) carries the editor its DL_GRID_COLUMNS row holds
    E8  refusals: PROPERTIES with a line that is not a Properties line is BLOCKED; a column of a field the selection
        removes gets no editor
  Run: pwsh -File tests\autotest\run_v156_GCW.ps1 [-Exe <drag-lint.exe>] [-SkipUnit] [-SkipForm]
       -SkipForm leaves out E5 (a machine without DevExpress).
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
Write-Host '== repo write-dfm, grid column editors (1.56 GC-W) ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-gcw-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Write-Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:y) { Run (@('repo', 'write-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'repo-to-dfm') + $more) }
function Text($f) { [IO.File]::ReadAllText($f, [Text.Encoding]::Latin1) }
function Put($f, $t) { [IO.File]::WriteAllText($f, $t.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::Latin1) }
function IdOf($r, $pattern) { $m = [regex]::Match($r.Out, '(?m)^\[(\d+)\] ' + $pattern); if ($m.Success) { $m.Groups[1].Value } else { '' } }
function PlanOf($r) { $m = [regex]::Match($r.Out, '(?m)^# plan ([0-9a-f]{16})$'); if ($m.Success) { $m.Groups[1].Value } else { 'none' } }
function PutSel($f, $r, $ids) { [IO.File]::WriteAllText($f, "# plan $(PlanOf $r)`n" + (@($ids) -join "`n")) }
# one record of a backup section: header line and the lines up to the next record
function RecordOf($t, $head) {
  $i = $t.IndexOf($head)
  if ($i -lt 0) { Write-Host "FATAL: no record $head" -ForegroundColor Red; $script:Failed = $true; return '' }
  $end = $t.IndexOf("`r`n[", $i + $head.Length)
  $t.Substring($i, $end - $i + 2)
}
# adds records before the end line of a section and counts them
function AddRecords($t, $table, $records) {
  $m = [regex]::Match($t, "#end $table (\d+)")
  $n = [int]$m.Groups[1].Value + @($records).Count
  $t.Substring(0, $m.Index) + (@($records) -join '') + "#end $table $n" + $t.Substring($m.Index + $m.Length)
}
# a DL_GRID_COLUMNS record of GridView with an editor; $props = its Properties.* lines
function GridRecord($column, $field, $index, $class, [string[]]$props) {
  $r = "[DL_GRID_COLUMNS frmAllKinds|GridView|$column]`r`nTABLE_NAME=ORDERS`r`nFIELD_NAME=$field`r`nCOLUMN_INDEX=$index`r`n"
  if ($class) { $r += "PROPERTIES_CLASS_NAME=$class`r`n" }
  if ($props.Count -gt 0) { $r += "PROPERTIES:`r`n" + ((@($props) | ForEach-Object { " |$_`r`n" }) -join '') }
  $r + "`r`n"
}
# a repository restored from the base backup plus these DL_GRID_COLUMNS records
function NewRepo($name, $records) {
  $bk = Join-Path $work "$name.txt"
  [IO.File]::WriteAllText($bk, (AddRecords $script:base 'DL_GRID_COLUMNS' $records))
  $f = Join-Path $work "$name.dlrepo"
  $r = Run @('repo', 'restore', '--repo', $f, '--in', $bk)
  Check "E0 repository $name restored" ($r.Code -eq 0) $r.Out
  $f
}
$src = Join-Path $Repo 'tests\fixtures\fieldrepo\dfmwrite'
function NewForms($name) {
  $d = Join-Path $work $name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  foreach ($f in 'uAllKinds.dfm', 'uAllKinds.pas', 'AllKindsLoad.dpr') { [IO.File]::Copy((Join-Path $src $f), (Join-Path $d $f)) }
  $d
}
# the unit with the DevExpress units that register the two editor classes
function UseEditorUnits($dir) {
  $p = Join-Path $dir 'uAllKinds.pas'
  Put $p ((Text $p).Replace('cxGridDBTableView, cxGridLevel,', 'cxGridDBTableView, cxCurrencyEdit, cxDropDownEdit, cxGridLevel,'))
}
function BuildForm($dir) {
  # the loader also prints what Delphi made of the two editors
  $dpr = Join-Path $dir 'AllKindsLoad.dpr'
  $t = (Text $dpr).Replace("  uAllKinds in 'uAllKinds.pas';", "  cxEdit, cxCurrencyEdit, cxDropDownEdit, cxGridCustomTableView, cxGridDBTableView,`n  uAllKinds in 'uAllKinds.pas';")
  $t = $t.Replace("      Writeln('columns='", "      Writeln('qty=', GForm.GridViewQTY.PropertiesClassName, '|', (GForm.GridViewQTY.Properties as TcxCurrencyEditProperties).DisplayFormat, '|', (GForm.GridViewQTY.Properties as TcxCurrencyEditProperties).Nullable);`n      Writeln('status=', GForm.GridViewSTATUS.PropertiesClassName, '|', (GForm.GridViewSTATUS.Properties as TcxComboBoxProperties).Items.CommaText, '|', GForm.GridViewSTATUS.Width);`n      Writeln('columns='")
  Put $dpr $t
  $log = Join-Path $dir 'b.log'
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + (Join-Path $Repo 'build\_build_fieldrepo_dfmwrite_form_local.bat') + '" "' + $dir + '" > "' + $log + '" 2>&1"') -Wait -NoNewWindow
  $l = Get-Content -LiteralPath $log -Raw
  if ($l -notmatch 'BUILD_EXITCODE=0') { return 'BUILD FAILED ' + (($l -split "`n" | Select-String 'Error|Fatal' | Select-Object -First 3) -join ' / ') }
  (& { $ErrorActionPreference = 'Continue'; & (Join-Path $dir 'AllKindsLoad.exe') 2>&1 | ForEach-Object { "$_" } }) -join "`n"
}
$qtyLines = "        PropertiesClassName = 'TcxCurrencyEditProperties'`r`n        Properties.DisplayFormat = '0.00'`r`n        Properties.Nullable = False`r`n"
$statusLines = "        PropertiesClassName = 'TcxComboBoxProperties'`r`n        Properties.Items.Strings = (`r`n          'one'`r`n          'it'#39's two')`r`n"
$qtyNew = "TcxCurrencyEditProperties; Properties\.DisplayFormat = '0\.00'; Properties\.Nullable = False"
$statusNew = "TcxComboBoxProperties; Properties\.Items\.Strings = \( 'one' 'it'#39's two'\)"
try {
  # ---- part 1 ----
  if (-not $SkipUnit) {
    $bat = Join-Path $Repo 'build\_build_fieldrepo_grideditor_tests_local.bat'
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'U0 the unit tests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: E\d+')) (($bl -split "`n" | Select-String 'Error|Fatal' | Select-Object -First 3) -join ' / ')
    $u = (& { $ErrorActionPreference = 'Continue'; & (Join-Path $work 'GridEditorWriteTests.exe') 2>&1 | ForEach-Object { "$_" } })
    $uc = $LASTEXITCODE
    $u | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $sum = ($u | Where-Object { $_ -match '^SUMMARY ' } | Select-Object -Last 1)
    Check "U1 unit tests ($sum), none skipped" (($uc -eq 0) -and ($sum -eq 'SUMMARY pass=27 fail=0')) $sum
  }
  # ---- part 2 ----
  $x = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $x)
  $null = Run @('repo', 'seed-fb', '--ddl', (Join-Path $src 'schema.sql'), '--repo', $x, '--apply')
  $null = Run @('repo', 'read-dfm', '--repo', $x, '--dfm', (Join-Path $src 'uFull.dfm'), '--direction', 'dfm-to-repo', '--apply')
  $bk = Join-Path $work 'bk.txt'
  $null = Run @('repo', 'backup', '--repo', $x, '--out', $bk)
  $t = [IO.File]::ReadAllText($bk)
  # PIC: a graphical row, DL_GRID_COLUMNS puts its column first in GridView as colPic, with an editor
  $status = RecordOf $t '[DL_FIELDS_INFO ORDERS|STATUS]'
  $pic = $status.Replace('FIELD_KIND=2', 'FIELD_KIND=10').Replace('ISCALCULATED=true', 'ISCALCULATED=false').Replace('[DL_FIELDS_INFO ORDERS|STATUS]', '[DL_FIELDS_INFO ORDERS|PIC]')
  $script:base = AddRecords $t 'DL_FIELDS_INFO' @($pic)
  $qty = GridRecord 'GridViewQTY' 'QTY' 0 'TcxCurrencyEditProperties' @("Properties.DisplayFormat = '0.00'", 'Properties.Nullable = False')
  $sta = GridRecord 'GridViewSTATUS' 'STATUS' 1 'TcxComboBoxProperties' @('Properties.Items.Strings = (', "  'one'", "  'it'#39's two')")
  $gone = GridRecord 'colGone' 'NOTE' 2 'TcxTextEditProperties' @()
  $plain = GridRecord 'colNoEditor' 'NOTE' 3 '' @()
  $script:y = NewRepo 'y' @($qty, $sta, $gone, $plain)

  # ---- E1 dry run ----
  $forms = NewForms 'dry'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $pas = Join-Path $forms 'uAllKinds.pas'
  $oldDfm = Text $script:dfm
  $r = Write-Dfm @()
  $idQty = IdOf $r "update uAllKinds\.dfm GridViewQTY Properties:  -> $qtyNew\n  \(unchecked\)"
  $idSta = IdOf $r "update uAllKinds\.dfm GridViewSTATUS Properties:  -> $statusNew\n  \(unchecked\)"
  Check 'E1a one change per column, the whole editor on one line, unchecked: the form does not load the class yet' (($r.Code -eq 0) -and ($idQty -ne '') -and ($idSta -ne '')) $r.Out
  Check 'E1b the warning names the class and the unit that registers it' (($r.Out -match 'warning: uAllKinds\.dfm GridViewQTY: the editor TcxCurrencyEditProperties is new to the form, which loads only when the unit that registers the class \(cxCurrencyEdit\) is in the project: the change is unchecked') -and ($r.Out -match 'GridViewSTATUS: the editor TcxComboBoxProperties is new to the form[^\n]*\(cxDropDownEdit\)')) $r.Out
  Check 'E1c a row whose column the form lacks: a warning, no change; a row without an editor: nothing' (($r.Out -match 'warning: uAllKinds\.dfm memOrders: the editor of colGone is not written: GridView has no such column') -and ($r.Out -notmatch '\] \w+ uAllKinds\.dfm colGone') -and ($r.Out -notmatch 'colNoEditor')) $r.Out
  Check 'E1d a dry run writes no byte' ((Text $script:dfm) -ceq $oldDfm) ''

  # ---- E2 --apply leaves them out, --select writes them ----
  $ra = Write-Dfm @('--apply')
  Check 'E2a --apply leaves the unchecked editors out' (($ra.Code -eq 0) -and ((Text $script:dfm) -notmatch 'PropertiesClassName')) $ra.Out
  $applied = Text $script:dfm; $oldPas = Text $pas
  $r = Write-Dfm @()
  $idQty = IdOf $r 'update uAllKinds\.dfm GridViewQTY Properties:'
  $sel = Join-Path $work 'e.sel'
  PutSel $sel $r @($idQty)
  $rs = Write-Dfm @('--select', $sel)
  $nd = Text $script:dfm
  Check 'E2b --select writes the one it names: after DataBinding, class first' (($rs.Code -eq 0) -and ($nd.Contains("      object GridViewQTY: TcxGridDBColumn`r`n        DataBinding.FieldName = 'QTY'`r`n$qtyLines      end`r`n")) -and ($nd -notmatch 'TcxComboBoxProperties')) ($rs.Out + "`n" + $nd)
  Check 'E2c nothing else in the DFM, the unit untouched' (($nd.Replace($qtyLines, '') -ceq $applied) -and ((Text $pas) -ceq $oldPas)) $nd

  # ---- E3 a unit that uses the editor units: checked ----
  $forms = NewForms 'checked'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $pas = Join-Path $forms 'uAllKinds.pas'
  $null = Write-Dfm @('--apply') # the checked field changes are in now
  UseEditorUnits $forms
  $applied = Text $script:dfm; $oldPas = Text $pas
  $r = Write-Dfm @()
  Check 'E3a the unit uses cxCurrencyEdit and cxDropDownEdit: both changes are checked, no warning' (($r.Out -match "(?m)^\[\d+\] update uAllKinds\.dfm GridViewQTY Properties:  -> $qtyNew`$(?!\n  \()") -and ($r.Out -match "(?m)^\[\d+\] update uAllKinds\.dfm GridViewSTATUS Properties:  -> $statusNew`$(?!\n  \()") -and ($r.Out -notmatch 'is new to the form')) $r.Out
  $ra = Write-Dfm @('--apply')
  $nd = Text $script:dfm
  $golden = "      object GridViewQTY: TcxGridDBColumn`r`n        DataBinding.FieldName = 'QTY'`r`n$qtyLines      end`r`n      object GridViewSTATUS: TcxGridDBColumn`r`n        Caption = 'Status'`r`n$statusLines        Width = 40`r`n      end`r`n"
  Check 'E3b --apply writes both: golden bytes of the two columns' (($ra.Code -eq 0) -and ($ra.Out -match 'applied: 2 changes') -and $nd.Contains($golden)) ($ra.Out + "`n" + $nd)
  Check 'E3c nothing else in the DFM, the unit untouched, a backup of the DFM' (($nd.Replace($qtyLines, '').Replace($statusLines, '') -ceq $applied) -and ((Text $pas) -ceq $oldPas) -and (@(Get-ChildItem -LiteralPath $forms -File | Where-Object { $_.Name -match '^uAllKinds\.dfm\.before-write-dfm-' }).Count -ge 1)) $nd

  # ---- E4 the written bytes ----
  $r2 = Write-Dfm @()
  Check 'E4a a second plan reads the written file: nothing more to do for the editors' (($r2.Code -eq 0) -and ($r2.Out -notmatch 'Properties:') -and ($r2.Out -notmatch 'is new to the form')) $r2.Out
  $conv = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\convert.exe'
  $cd = Join-Path $work 'conv'; [IO.Directory]::CreateDirectory($cd) | Out-Null
  [IO.File]::Copy($script:dfm, (Join-Path $cd 'a.dfm'))
  $null = & { $ErrorActionPreference = 'Continue'; & $conv -i -b (Join-Path $cd 'a.dfm') 2>&1 | ForEach-Object { "$_" } }
  $first = [IO.File]::ReadAllBytes((Join-Path $cd 'a.dfm'))[0]
  $null = & { $ErrorActionPreference = 'Continue'; & $conv -i -t (Join-Path $cd 'a.dfm') 2>&1 | ForEach-Object { "$_" } }
  Check 'E4b convert.exe: to binary and back gives the same text' (($first -in 0xFF, 0x54) -and ((Text (Join-Path $cd 'a.dfm')) -ceq $nd)) "first byte $first"

  # ---- E5 compiled ----
  if (-not $SkipForm) {
    $after = BuildForm $forms
    Check 'E5 the form compiles and loads: both columns have their editor class and its properties' (($after -match 'LOADED') -and ($after -match '(?m)^qty=TcxCurrencyEditProperties\|0\.00\|FALSE\r?$') -and ($after -match "(?m)^status=TcxComboBoxProperties\|one,`"it's two`"\|40\r?$")) $after
  }

  # ---- E6 the same class, other properties ----
  $qty2 = GridRecord 'GridViewQTY' 'QTY' 0 'TcxCurrencyEditProperties' @("Properties.DisplayFormat = '0.000'")
  $y2 = NewRepo 'y2' @($qty2, $sta)
  $forms = NewForms 'same'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $null = Write-Dfm @('--apply')
  Put $script:dfm ((Text $script:dfm).Replace("        DataBinding.FieldName = 'QTY'`r`n", "        DataBinding.FieldName = 'QTY'`r`n$qtyLines"))
  $applied = Text $script:dfm
  $r = Write-Dfm @() $script:dfm $y2
  Check 'E6a the same class, other properties: old -> new, checked without the unit; the class is in the form now, so the combo box is still unchecked' (($r.Out -match "(?m)^\[\d+\] update uAllKinds\.dfm GridViewQTY Properties: $qtyNew -> TcxCurrencyEditProperties; Properties\.DisplayFormat = '0\.000'`$(?!\n  \()") -and ($r.Out -match "GridViewSTATUS Properties:  -> $statusNew\n  \(unchecked\)") -and ($r.Out -notmatch 'GridViewQTY: the editor')) $r.Out
  $ra = Write-Dfm @('--apply') $script:dfm $y2
  $nd = Text $script:dfm
  Check 'E6b --apply replaces the stated lines, nothing else' (($ra.Code -eq 0) -and ($nd -ceq $applied.Replace($qtyLines, "        PropertiesClassName = 'TcxCurrencyEditProperties'`r`n        Properties.DisplayFormat = '0.000'`r`n"))) ($ra.Out + "`n" + $nd)

  # ---- E7 a new column carries its editor ----
  $picRow = GridRecord 'colPic' 'PIC' 0 'TcxLabelProperties' @('Properties.Alignment.Horz = taCenter')
  $y3 = NewRepo 'y3' @($picRow)
  $forms = NewForms 'pic'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $null = Write-Dfm @('--apply') $script:dfm $y3
  $r = Write-Dfm @() $script:dfm $y3
  $colPic = IdOf $r "insert uAllKinds\.dfm colPic:  -> TcxGridDBColumn; GridView index 0; DataBinding\.FieldName = 'PIC'; PropertiesClassName = 'TcxLabelProperties'; Properties\.Alignment\.Horz = taCenter\n  \(unchecked\)"
  Check 'E7a the new column shows its editor; a warning names cxLabel' (($colPic -ne '') -and ($r.Out -match 'warning: uAllKinds\.dfm colPic: the editor TcxLabelProperties is new to the form[^\n]*\(cxLabel\)')) $r.Out
  PutSel $sel $r @($colPic)
  $rs = Write-Dfm @('--select', $sel) $script:dfm $y3
  $nd = Text $script:dfm
  Check 'E7b the block: binding, class, properties' (($rs.Code -eq 0) -and $nd.Contains("      object colPic: TcxGridDBColumn`r`n        DataBinding.FieldName = 'PIC'`r`n        PropertiesClassName = 'TcxLabelProperties'`r`n        Properties.Alignment.Horz = taCenter`r`n      end`r`n      object GridViewQTY: TcxGridDBColumn`r`n")) ($rs.Out + "`n" + $nd)
  $r2 = Write-Dfm @() $script:dfm $y3
  Check 'E7c a second plan has nothing to do for it' (($r2.Code -eq 0) -and ($r2.Out -notmatch 'colPic')) $r2.Out

  # ---- E8 refusals ----
  $bad = GridRecord 'GridViewQTY' 'QTY' 0 'TcxCurrencyEditProperties' @('Width = 9')
  $y4 = NewRepo 'y4' @($bad)
  $forms = NewForms 'bad'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $r = Write-Dfm @() $script:dfm $y4
  Check 'E8a PROPERTIES with a line that is not a Properties line: BLOCKED' ($r.Out -match 'update uAllKinds\.dfm GridViewQTY Properties:[^\n]*\n  BLOCKED: uAllKinds\.dfm: not a line of Properties\.\*: Width = 9') $r.Out
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID')
  Check 'E8b a column of a field the selection removes gets no editor' ($r.Out -match 'update uAllKinds\.dfm GridViewQTY Properties:[^\n]*\n  BLOCKED: the column shows a field that is not in the selection') $r.Out
}
finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("{0} checks, {1}" -f $script:Count, $(if ($script:Failed) { 'FAILED' } else { 'all passed' })) -ForegroundColor (@('Green','Red')[[int]$script:Failed])
exit ([int]$script:Failed)
