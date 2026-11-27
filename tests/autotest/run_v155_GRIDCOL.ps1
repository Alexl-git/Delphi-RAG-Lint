#Requires -Version 7.3
<#
  run_v155_GRIDCOL.ps1 -- lane GRIDCOL (1.55): `repo write-dfm` writes the grid columns that are not fields, owner
  ruling Q3(1) NO (spec docs\superpowers\specs\2026-11-26-dfmwrite2-design.md, section Q3(1)).

  A graphical row (FIELD_KIND 10) whose column the form lacks becomes a TcxGridDBColumn in the TcxGridDBTableView that
  DL_GRID_COLUMNS names, else in the only one that shows the dataset; its GRID_* bodies become handlers. Every one of these
  changes is unchecked: --apply never writes them, only their ids in a --select file do (the second confirmation).
    G1  dry run: the column (DL_GRID_COLUMNS place and the only view), its two handlers, all unchecked; a column the form
        has (STATUS) plans nothing and warns nothing
    G2  --apply leaves them out
    G3  a handler without its column is refused (exit 2)
    G4  --select writes the columns at their places, declarations, handlers; nothing else changes
    G5  the form compiles and loads: the columns are there, at their index, and the handler runs
    G6  a second plan has nothing more to do for them; read-dfm stores no other code for them
    G7  refusals: a name the unit has, a unit the handler type needs, two views and no DL_GRID_COLUMNS row
  Run: pwsh -File tests\autotest\run_v155_GRIDCOL.ps1 [-Exe <drag-lint.exe>] [-SkipForm]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipForm)
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
Write-Host '== repo write-dfm, graphical grid columns (1.55 Q3(1)) ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v155-gridcol-' + [guid]::NewGuid().ToString('N'))
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
function BuildForm($dir) {
  # the loader also prints the new columns: their index, what OnGetDisplayText makes of the record, OnCustomDrawCell
  $dpr = Join-Path $dir 'AllKindsLoad.dpr'
  $t = (Text $dpr).Replace("  uAllKinds in 'uAllKinds.pas';", "  cxGridCustomTableView, cxGridDBTableView,`n  uAllKinds in 'uAllKinds.pas';").Replace("  GI: Integer;", "  GI: Integer;`n  GText: string;`n  GColumn: TcxGridDBColumn;")
  $t = $t.Replace("      Writeln('columns='", "      GColumn := TcxGridDBColumn(GForm.FindComponent('GridViewIMG'));`n      if GColumn <> nil then`n      begin`n        GText := '';`n        GColumn.OnGetDisplayText(GColumn, nil, GText);`n        Writeln('img=', GColumn.Index, '|', GText, '|', Assigned(GColumn.OnCustomDrawCell), '|', GColumn.DataBinding.FieldName);`n      end;`n      GColumn := TcxGridDBColumn(GForm.FindComponent('colPic'));`n      if GColumn <> nil then`n        Writeln('pic=', GColumn.Index);`n      Writeln('columns='")
  Put $dpr $t
  $log = Join-Path $dir 'b.log'
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + (Join-Path $Repo 'build\_build_fieldrepo_dfmwrite_form_local.bat') + '" "' + $dir + '" > "' + $log + '" 2>&1"') -Wait -NoNewWindow
  $l = Get-Content -LiteralPath $log -Raw
  if ($l -notmatch 'BUILD_EXITCODE=0') { return 'BUILD FAILED ' + (($l -split "`n" | Select-String 'Error|Fatal' | Select-Object -First 3) -join ' / ') }
  (& { $ErrorActionPreference = 'Continue'; & (Join-Path $dir 'AllKindsLoad.exe') 2>&1 | ForEach-Object { "$_" } }) -join "`n"
}
try {
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
  $null = Run @('repo', 'read-dfm', '--repo', $x, '--dfm', (Join-Path $src 'uFull.dfm'), '--direction', 'dfm-to-repo', '--apply')
  $bk = Join-Path $work 'bk.txt'
  $null = Run @('repo', 'backup', '--repo', $x, '--out', $bk)
  $t = [IO.File]::ReadAllText($bk)
  # STATUS: graphical, and the form has its column (GridViewSTATUS); IMG: graphical, two bodies, no column, no
  # DL_GRID_COLUMNS row; PIC: graphical, DL_GRID_COLUMNS puts it first in GridView as colPic
  $status = RecordOf $t '[DL_FIELDS_INFO ORDERS|STATUS]'
  $graphical = $status.Replace('FIELD_KIND=2', 'FIELD_KIND=10').Replace('ISCALCULATED=true', 'ISCALCULATED=false')
  $t = $t.Replace($status, $graphical)
  $img = $graphical.Replace('[DL_FIELDS_INFO ORDERS|STATUS]', "[DL_FIELDS_INFO ORDERS|IMG]`r`nDISPLAY_LABEL=Picture`r`nGRID_DISPLAYTEXT_BODY:`r`n |AText := 'P' + {{QTY}}.AsString;`r`nGRID_DRAWCELL_BODY:`r`n |ADone := False;")
  $pic = $graphical.Replace('[DL_FIELDS_INFO ORDERS|STATUS]', '[DL_FIELDS_INFO ORDERS|PIC]')
  $t = AddRecords $t 'DL_FIELDS_INFO' @($img, $pic)
  $t = AddRecords $t 'DL_GRID_COLUMNS' @("[DL_GRID_COLUMNS frmAllKinds|GridView|colPic]`r`nTABLE_NAME=ORDERS`r`nFIELD_NAME=PIC`r`nCOLUMN_INDEX=0`r`n`r`n")
  [IO.File]::WriteAllText($bk, $t)
  $script:y = Join-Path $work 'y.dlrepo'
  $r = Run @('repo', 'restore', '--repo', $script:y, '--in', $bk)
  Check 'G0 the repository with three graphical rows and one DL_GRID_COLUMNS place' ($r.Code -eq 0) $r.Out

  $forms = NewForms 'cols'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $pas = Join-Path $forms 'uAllKinds.pas'
  $r = Write-Dfm @()
  $colImg = IdOf $r "insert uAllKinds\.dfm GridViewIMG:  -> TcxGridDBColumn; GridView index 2; Caption = 'Picture'; DataBinding\.FieldName = 'IMG'\n  \(unchecked\)"
  $evText = IdOf $r 'insert uAllKinds\.dfm GridViewIMG OnGetDisplayText:  -> GridViewIMGGetDisplayText\n  \(unchecked\)'
  $evDraw = IdOf $r 'insert uAllKinds\.dfm GridViewIMG OnCustomDrawCell:  -> GridViewIMGCustomDrawCell\n  \(unchecked\)'
  $colPic = IdOf $r "insert uAllKinds\.dfm colPic:  -> TcxGridDBColumn; GridView index 0; DataBinding\.FieldName = 'PIC'\n  \(unchecked\)"
  Check 'G1a the column of the only view, unchecked' (($r.Code -eq 0) -and ($colImg -ne '')) $r.Out
  Check 'G1b its two handlers, unchecked' (($evText -ne '') -and ($evDraw -ne '')) $r.Out
  Check 'G1c the DL_GRID_COLUMNS place: name and index' ($colPic -ne '') $r.Out
  Check 'G1d a column the form has plans nothing, and no "not written" warning' (($r.Out -notmatch 'GridViewSTATUS') -and ($r.Out -notmatch 'graphical columns are grid columns')) $r.Out
  $oldDfm = Text $script:dfm; $oldPas = Text $pas
  $ra = Write-Dfm @('--apply')
  $afterApply = Text $script:dfm
  Check 'G2 --apply leaves the columns out' (($ra.Code -eq 0) -and ($afterApply -notmatch 'GridViewIMG|colPic') -and ((Text $pas) -notmatch 'GridViewIMG|colPic')) $ra.Out
  $oldDfm = Text $script:dfm; $oldPas = Text $pas # the checked property changes are in now
  $r = Write-Dfm @()
  $colImg = IdOf $r 'insert uAllKinds\.dfm GridViewIMG:  ->'
  $evText = IdOf $r 'insert uAllKinds\.dfm GridViewIMG OnGetDisplayText:'
  $evDraw = IdOf $r 'insert uAllKinds\.dfm GridViewIMG OnCustomDrawCell:'
  $colPic = IdOf $r 'insert uAllKinds\.dfm colPic:  ->'
  $sel = Join-Path $work 'g.sel'
  PutSel $sel $r @($evText)
  $rs = Write-Dfm @('--select', $sel)
  Check 'G3 a handler without its column is refused, nothing written' (($rs.Code -eq 2) -and ($rs.Out -match "change $evText needs change $colImg") -and ((Text $script:dfm) -ceq $oldDfm)) $rs.Out
  PutSel $sel $r @($colPic, $colImg, $evText, $evDraw)
  $rs = Write-Dfm @('--select', $sel)
  $nd = Text $script:dfm; $np = Text $pas
  Check 'G4a the DL_GRID_COLUMNS place: first column of GridView' (($rs.Code -eq 0) -and ($nd.Contains("      DataController.Summary.SummaryGroups = <>`r`n      object colPic: TcxGridDBColumn`r`n        DataBinding.FieldName = 'PIC'`r`n      end`r`n      object GridViewQTY: TcxGridDBColumn`r`n"))) ($rs.Out + "`n" + $nd)
  Check 'G4b the only view: after its last column, with both handlers' ($nd.Contains("        Width = 40`r`n      end`r`n      object GridViewIMG: TcxGridDBColumn`r`n        Caption = 'Picture'`r`n        DataBinding.FieldName = 'IMG'`r`n        OnGetDisplayText = GridViewIMGGetDisplayText`r`n        OnCustomDrawCell = GridViewIMGCustomDrawCell`r`n      end`r`n    end`r`n")) $nd
  Check 'G4c the declarations beside their neighbours' ($np.Contains("    GridView: TcxGridDBTableView;`r`n    colPic: TcxGridDBColumn;`r`n    GridViewQTY: TcxGridDBColumn;`r`n    GridViewSTATUS: TcxGridDBColumn;`r`n    GridViewIMG: TcxGridDBColumn;`r`n")) $np
  Check 'G4d the handler declarations' ($np.Contains("    procedure GridViewIMGGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord; var AText: string);`r`n    procedure GridViewIMGCustomDrawCell(Sender: TcxCustomGridTableView; ACanvas: TcxCanvas; AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean);`r`n  private`r`n")) $np
  Check 'G4e the methods: a DLFR region each, the macro is the field component' (($np -match "(?s)procedure TfrmAllKinds\.GridViewIMGGetDisplayText\([^\r\n]*\r\nbegin\r\n  \{\`$REGION 'DLFR GridViewIMG\.OnGetDisplayText[^\r\n]*\r\n.*AText := 'P' \+ memOrdersQTY\.AsString;\r\n.*\{\`$ENDREGION[^\r\n]*\r\nend;") -and ($np -match "(?s)procedure TfrmAllKinds\.GridViewIMGCustomDrawCell\([^\r\n]*\r\nbegin\r\n  \{\`$REGION 'DLFR GridViewIMG\.OnCustomDrawCell[^\r\n]*\r\n.*ADone := False;\r\n") -and ($np -notmatch '\{\{')) $np
  $keepPas = $np.Replace("    colPic: TcxGridDBColumn;`r`n", '').Replace("    GridViewIMG: TcxGridDBColumn;`r`n", '') -replace "(?m)^    procedure GridViewIMG\w+\([^\r\n]*\r\n", '' -replace "(?s)procedure TfrmAllKinds\.GridViewIMG\w+\(.*?\r\nend;\r\n\r\n", ''
  $keepDfm = [regex]::Replace($nd, "(?ms)^      object (colPic|GridViewIMG): .*?^      end\r\n", '')
  Check 'G4f nothing else in the unit and the DFM' (($keepPas -ceq $oldPas) -and ($keepDfm -ceq $oldDfm)) ($keepPas + "`n----`n" + $keepDfm)
  if (-not $SkipForm) {
    $after = BuildForm $forms
    Check 'G5 the form compiles and loads, the columns at their index, the handler runs' (($after -match 'LOADED') -and ($after -match '(?m)^columns=4,2\r?$') -and ($after -match '(?m)^img=3\|P5\|TRUE\|IMG\r?$') -and ($after -match '(?m)^pic=0\r?$')) $after
  }
  $r2 = Write-Dfm @()
  Check 'G6a a second plan has nothing more to do for the columns' (($r2.Code -eq 0) -and ($r2.Out -notmatch 'GridViewIMG|colPic')) $r2.Out
  $rr = Run @('repo', 'read-dfm', '--repo', $script:y, '--dfm', $script:dfm, '--direction', 'dfm-to-repo')
  Check 'G6b read-dfm: the handlers hold the stored code, no field row changes' (($rr.Code -eq 0) -and ($rr.Out -notmatch 'DL_FIELDS_INFO ORDERS\|(IMG|PIC)') -and ($rr.Out -match 'insert DL_GRID_COLUMNS frmAllKinds\|GridView\|GridViewIMG:')) $rr.Out

  # ---- refusals ----
  $cf = NewForms 'clash'
  $cpas = Join-Path $cf 'uAllKinds.pas'
  Put $cpas ((Text $cpas).Replace("    function Used: Integer;", "    function Used: Integer;`n    function GridViewIMG: Integer;"))
  $r = Write-Dfm @() (Join-Path $cf 'uAllKinds.dfm')
  Check 'G7a a name the unit already has: the column is BLOCKED' ($r.Out -match "insert uAllKinds\.dfm GridViewIMG:  -> [^\n]*\n  BLOCKED: uAllKinds\.pas: the unit already has GridViewIMG") $r.Out
  Check 'G7b a blocked column gets no handlers; the other column is planned' (($r.Out -notmatch 'GridViewIMG On') -and ($r.Out -match 'insert uAllKinds\.dfm colPic:  -> [^\n]*\n  \(unchecked\)')) $r.Out
  $uf = NewForms 'units'
  $upas = Join-Path $uf 'uAllKinds.pas'
  Put $upas ((Text $upas).Replace('cxGraphics, ', ''))
  $r = Write-Dfm @() (Join-Path $uf 'uAllKinds.dfm')
  Check 'G7c no cxGraphics: OnCustomDrawCell BLOCKED, OnGetDisplayText unchecked' (($r.Out -match 'GridViewIMG OnCustomDrawCell:  -> GridViewIMGCustomDrawCell\n  BLOCKED: the interface section of the unit does not use cxGraphics') -and ($r.Out -match 'GridViewIMG OnGetDisplayText:  -> GridViewIMGGetDisplayText\n  \(unchecked\)')) $r.Out
  $vf = NewForms 'views'
  $vdfm = Join-Path $vf 'uAllKinds.dfm'
  Put $vdfm ((Text $vdfm).Replace("    object GridLevel: TcxGridLevel", "    object GridView2: TcxGridDBTableView`n      DataController.DataSource = dsOrders`n    end`n    object GridLevel: TcxGridLevel"))
  Put (Join-Path $vf 'uAllKinds.pas') ((Text (Join-Path $vf 'uAllKinds.pas')).Replace("    GridLevel: TcxGridLevel;", "    GridView2: TcxGridDBTableView;`n    GridLevel: TcxGridLevel;"))
  $r = Write-Dfm @() $vdfm
  Check 'G7d two views and no DL_GRID_COLUMNS row: not written, said why; the named place still is' (($r.Out -notmatch 'insert uAllKinds\.dfm GridView2?IMG') -and ($r.Out -match 'warning: uAllKinds\.dfm memOrders: graphical column IMG not written: 2 grid views show the dataset \(GridView, GridView2\) and DL_GRID_COLUMNS names none') -and ($r.Out -match 'insert uAllKinds\.dfm colPic:')) $r.Out
  # ---- REVFIX (1.55 final review #4): a new grid column of a view on a BDE dataset obeys fieldrepo.bde ----
  foreach ($case in @(@('g8full', 'full', '\(unchecked\)'), @('g8ro', 'readonly', 'BLOCKED: BDE dataset: read only \(project policy\)'), @('g8none', 'none', 'BLOCKED: BDE not allowed in this project'))) {
    $gp = Join-Path $work $case[0]
    $gd = Join-Path $gp 'f'
    [IO.Directory]::CreateDirectory($gd) | Out-Null
    foreach ($f in 'uAllKinds.dfm', 'uAllKinds.pas') { Put (Join-Path $gd $f) ((Text (Join-Path $src $f)).Replace('memOrders: TFDMemTable', 'memOrders: TTable')) }
    [IO.Directory]::CreateDirectory((Join-Path $gp '_D-RAG')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $gp '_D-RAG\drag-lint-project.json'), "{`"fieldrepo`": {`"bde`": `"$($case[1])`"}}")
    $r = Write-Dfm @() (Join-Path $gd 'uAllKinds.dfm')
    Check "G8 BDE $($case[1]): the new grid column is $($case[2])" (($r.Code -eq 0) -and ($r.Out -match ("insert uAllKinds\.dfm GridViewIMG:  -> TcxGridDBColumn; [^\n]*\n  " + $case[2]))) $r.Out
    if ($case[1] -ne 'full') {
      Check "G8b BDE $($case[1]): its handlers are not offered" ($r.Out -notmatch 'GridViewIMG On\w+:') $r.Out
      $gOld = Text (Join-Path $gd 'uAllKinds.dfm')
      PutSel (Join-Path $work 'g8.sel') $r @(IdOf $r 'insert uAllKinds\.dfm GridViewIMG:')
      $rs = Write-Dfm @('--select', (Join-Path $work 'g8.sel')) (Join-Path $gd 'uAllKinds.dfm')
      Check "G8c BDE $($case[1]): selecting it is refused, the DFM stays" (($rs.Code -eq 2) -and ($rs.Out -match 'is blocked: BDE') -and ((Text (Join-Path $gd 'uAllKinds.dfm')) -ceq $gOld)) $rs.Out
    } else {
      Check 'G8b control (full): its handlers are offered' ($r.Out -match 'GridViewIMG OnGetDisplayText:') $r.Out
    }
  }
}
finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("{0} checks, {1}" -f $script:Count, $(if ($script:Failed) { 'FAILED' } else { 'all passed' })) -ForegroundColor (@('Green','Red')[[int]$script:Failed])
exit ([int]$script:Failed)
