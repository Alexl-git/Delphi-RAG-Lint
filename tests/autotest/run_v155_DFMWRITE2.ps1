#Requires -Version 7.3
<#
  run_v155_DFMWRITE2.ps1 -- lane DFMWRITE2 (1.55): `repo write-dfm`, owner rulings 2026-11-26
  (spec docs\superpowers\specs\2026-11-26-dfmwrite2-design.md).

  Q1 A   a field event the repository holds and the form lacks is created (DFM + declaration + method), unchecked
    E1  dry run: one unchecked insert per missing handler, nothing for a field that has one
    E2  --apply leaves it out
    E3  --select writes OnGetText, the declaration and the method (DLFR region, macros expanded); the form loads and
        the handler runs; a second plan has nothing more to do for it; repo gen-handlers finds the region unchanged
    E4  a field the selection adds brings its event: the event needs the insert
    E5  a name the unit already has: BLOCKED
  Q3(2) NO  removing a field takes its grid / layout items with it
    E7  the tree-list column of NOTE: a linked unchecked delete; the field is no longer blocked by it
    E8  --select of the field alone is refused (exit 2)
    E9  field + column written: DFM block and declaration of both go, the form loads with one tree column
    E10 the grid column of QTY is named by a footer summary: column and field BLOCKED
  BDE policy per project (owner 2026-11-26, revised Q2): setting fieldrepo.bde of the form's project folder
    B1  no setting / full: a BDE dataset is planned as any other (field insert, new handler, grid item removal)
    B2  readonly / none: all three BLOCKED "BDE dataset: read only (project policy)" / "BDE not allowed in this project"
    B3  positive control: readonly leaves a FireDAC dataset alone
    B4  an unknown value is refused
  Run: pwsh -File tests\autotest\run_v155_DFMWRITE2.ps1 [-Exe <drag-lint.exe>] [-SkipForm]
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
Write-Host '== repo write-dfm, 1.55 rulings ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v155-dfmw2-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Write-Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:y) { Run (@('repo', 'write-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'repo-to-dfm') + $more) }
function Has($r, $text) { $r.Out.Contains($text) }
function Text($f) { [IO.File]::ReadAllText($f, [Text.Encoding]::Latin1) }
function Put($f, $t) { [IO.File]::WriteAllText($f, $t.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::Latin1) }
function IdOf($r, $pattern) { $m = [regex]::Match($r.Out, '(?m)^\[(\d+)\] ' + $pattern); if ($m.Success) { $m.Groups[1].Value } else { '' } }
function PlanOf($r) { $m = [regex]::Match($r.Out, '(?m)^# plan ([0-9a-f]{16})$'); if ($m.Success) { $m.Groups[1].Value } else { 'none' } }
function PutSel($f, $r, $ids) { [IO.File]::WriteAllText($f, "# plan $(PlanOf $r)`n" + (@($ids) -join "`n")) }
# a multi-line column of one DL_FIELDS_INFO record, put right after its header
function AddBody($t, $key, $col, $lines) {
  $head = "[DL_FIELDS_INFO $key]`r`n"
  $i = $t.IndexOf($head)
  if ($i -lt 0) { Write-Host "FATAL: no record $key" -ForegroundColor Red; $script:Failed = $true; return $t }
  $add = "${col}:`r`n" + ((@($lines) | ForEach-Object { " |$_`r`n" }) -join '')
  $t.Substring(0, $i + $head.Length) + $add + $t.Substring($i + $head.Length)
}
function BuildForm($dir) {
  # the loader also prints the display text of QTY and PRICE (their OnGetText, when there is one)
  $dpr = Join-Path $dir 'AllKindsLoad.dpr'
  Put $dpr ((Text $dpr).Replace("      Writeln('columns='", "      Writeln('gettext=', Assigned(GForm.memOrders.FieldByName('QTY').OnGetText), '|', GForm.memOrders.FieldByName('QTY').DisplayText);`n      if GForm.memOrders.FindField('PRICE') <> nil then`n        Writeln('price=', Assigned(GForm.memOrders.FieldByName('PRICE').OnGetText), '|', GForm.memOrders.FieldByName('PRICE').DisplayText);`n      Writeln('columns='"))
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
  $t = AddBody $t 'ORDERS|QTY' 'ONGETTEXT_BODY' @("if DisplayText then", "  Text := 'Q' + {{QTY}}.AsString", "else", "  Text := {{QTY}}.AsString;")
  $t = AddBody $t 'ORDERS|PRICE' 'ONGETTEXT_BODY' @("Text := 'P' + Sender.AsString;")
  [IO.File]::WriteAllText($bk, $t)
  $script:y = Join-Path $work 'y.dlrepo'
  $r = Run @('repo', 'restore', '--repo', $script:y, '--in', $bk)
  Check 'E0 the repository with two OnGetText bodies' ($r.Code -eq 0) $r.Out

  # ---- Q1: events ----
  $forms = NewForms 'ev'
  $script:dfm = Join-Path $forms 'uAllKinds.dfm'
  $pas = Join-Path $forms 'uAllKinds.pas'
  $oldDfm = Text $script:dfm; $oldPas = Text $pas
  $r = Write-Dfm @()
  Check 'E1a a missing handler is an unchecked insert' (($r.Code -eq 0) -and ($r.Out -match '\] insert uAllKinds\.dfm memOrdersQTY OnGetText:  -> memOrdersQTYGetText\n  \(unchecked\)')) $r.Out
  Check 'E1b only for a field with a body' (([regex]::Matches($r.Out, '(?m)^\[\d+\] insert .* On\w+:').Count -eq 1)) $r.Out
  $id = IdOf $r 'insert uAllKinds\.dfm memOrdersQTY OnGetText'
  $ra = Write-Dfm @('--apply')
  Check 'E2 --apply leaves the event out' (($ra.Code -eq 0) -and -not ((Text $script:dfm).Contains('OnGetText')) -and -not ((Text $pas).Contains('GetText'))) $ra.Out
  $oldDfm = Text $script:dfm; $oldPas = Text $pas # the checked property changes are in now
  $r = Write-Dfm @()
  $id = IdOf $r 'insert uAllKinds\.dfm memOrdersQTY OnGetText'
  $sel = Join-Path $work 'e3.sel'
  PutSel $sel $r @($id)
  $rs = Write-Dfm @('--select', $sel)
  $nd = Text $script:dfm; $np = Text $pas
  Check 'E3a --select: the DFM assigns the handler' (($rs.Code -eq 0) -and ($nd -match "      FieldName = 'QTY'\r\n      Visible = False\r\n      OnGetText = memOrdersQTYGetText\r\n      DisplayFormat = "))($rs.Out + "`n" + $nd)
  Check 'E3b the declaration after the components' ($np -match "    Image: TImage;\r\n    procedure memOrdersQTYGetText\(Sender: TField; var Text: string; DisplayText: Boolean\);\r\n  private\r\n") $np
  Check 'E3c the method: DLFR region, the macro is the component' (($np -match "(?s)procedure TfrmAllKinds\.memOrdersQTYGetText\(Sender: TField; var Text: string; DisplayText: Boolean\);\r\nbegin\r\n  \{\`$REGION 'DLFR memOrdersQTY\.OnGetText[^\r\n]*\r\n.*Text := 'Q' \+ memOrdersQTY\.AsString\r\n.*\{\`$ENDREGION[^\r\n]*\r\nend;\r\n\r\nend\.") -and ($np -notmatch '\{\{')) $np
  $keep = $np -replace "(?m)^    procedure memOrdersQTYGetText[^\r\n]*\r\n", '' -replace "(?s)procedure TfrmAllKinds\.memOrdersQTYGetText.*?\r\nend;\r\n\r\n", ''
  Check 'E3d nothing else in the unit and the DFM' (($keep -ceq $oldPas) -and ($nd.Replace("      OnGetText = memOrdersQTYGetText`r`n", '') -ceq $oldDfm)) $keep
  $r2 = Write-Dfm @()
  Check 'E3e a second plan: the handler is there, no event change' (($r2.Code -eq 0) -and ($r2.Out -notmatch 'OnGetText:')) $r2.Out
  $rg = Run @('repo', 'gen-handlers', '--repo', $script:y, '--dfm', $script:dfm, '--dataset', 'memOrders')
  Check 'E3g repo gen-handlers finds the new region current' (($rg.Code -eq 0) -and ($rg.Out -match 'unchanged memOrdersQTY\.OnGetText \(TfrmAllKinds\.memOrdersQTYGetText\)') -and ($rg.Out -match ' 0 to write, ')) $rg.Out
  if (-not $SkipForm) {
    $after = BuildForm $forms
    Check 'E3f the form compiles, loads and the handler runs' (($after -match 'LOADED') -and ($after -match '(?m)^gettext=TRUE\|Q5\r?$')) $after
  }
  # a new field brings its event
  $nf = NewForms 'newfield'
  $ndfm = Join-Path $nf 'uAllKinds.dfm'
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,OLDCOL,USEDCOL,PRICE') $ndfm
  $ins = IdOf $r 'insert uAllKinds\.dfm memOrdersPRICE:  ->'
  $ev = IdOf $r 'insert uAllKinds\.dfm memOrdersPRICE OnGetText:  -> memOrdersPRICEGetText'
  Check 'E4a the new field and its event, the event unchecked' (($ins -ne '') -and ($ev -ne '') -and ($r.Out -match 'memOrdersPRICE OnGetText:  -> memOrdersPRICEGetText\n  \(unchecked\)')) $r.Out
  PutSel $sel $r @($ev)
  $rs = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,OLDCOL,USEDCOL,PRICE', '--select', $sel) $ndfm
  Check 'E4b the event without its field is refused' (($rs.Code -eq 2) -and ($rs.Out -match "change $ev needs change $ins")) $rs.Out
  PutSel $sel $r @($ins, $ev)
  $rs = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,OLDCOL,USEDCOL,PRICE', '--select', $sel) $ndfm
  $nd = Text $ndfm; $np = Text (Join-Path $nf 'uAllKinds.pas')
  Check 'E4c field and event written' (($rs.Code -eq 0) -and ($nd -match "(?s)object memOrdersPRICE: TBCDField\r\n[^\r\n]*FieldName = 'PRICE'\r\n.*OnGetText = memOrdersPRICEGetText\r\n") -and ($np -match "memOrdersPRICE: TBCDField;\r\n(    [^\r\n]*\r\n)*    procedure memOrdersPRICEGetText\(")) ($rs.Out + "`n" + $nd + "`n" + $np)
  if (-not $SkipForm) {
    $after = BuildForm $nf
    Check 'E4d the form loads, the new field has its handler' (($after -match 'LOADED') -and ($after -match '(?m)^price=TRUE\|P')) $after
  }
  # a name the unit already has
  $cf = NewForms 'clash'
  $cpas = Join-Path $cf 'uAllKinds.pas'
  Put $cpas ((Text $cpas).Replace("    function Used: Integer;", "    function Used: Integer;`n    function memOrdersQTYGetText: Integer;"))
  $r = Write-Dfm @() (Join-Path $cf 'uAllKinds.dfm')
  Check 'E5 a name the unit already has: BLOCKED' ($r.Out -match 'memOrdersQTY OnGetText:  -> memOrdersQTYGetText\n  BLOCKED: uAllKinds\.pas: the unit already has memOrdersQTYGetText') $r.Out

  # two fields whose names differ only by non-identifier characters get one handler name: the second is BLOCKED in the plan
  $c2 = Get-Content -LiteralPath $bk -Raw
  $pi = $c2.IndexOf('[DL_FIELDS_INFO ORDERS|PRICE]'); $qi = $c2.IndexOf('[DL_FIELDS_INFO ORDERS|QTY]')
  $dup = $c2.Substring($pi, $qi - $pi).Replace('ORDERS|PRICE', 'ORDERS|PRI-CE')
  $c2 = $c2.Substring(0, $qi) + $dup + $c2.Substring($qi)
  $c2 = $c2.Replace('#end DL_FIELDS_INFO 17', '#end DL_FIELDS_INFO 18')
  $bk2 = Join-Path $work 'bk2.txt'; [IO.File]::WriteAllText($bk2, $c2)
  $y2 = Join-Path $work 'y2.dlrepo'
  $null = Run @('repo', 'restore', '--repo', $y2, '--in', $bk2)
  $hf = NewForms 'handlerclash'
  $hdfm = Join-Path $hf 'uAllKinds.dfm'; $hpas = Join-Path $hf 'uAllKinds.pas'
  $hOldDfm = Text $hdfm; $hOldPas = Text $hpas
  $hn = @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,OLDCOL,USEDCOL,PRICE,PRI-CE')
  $r = Write-Dfm $hn $hdfm $y2
  Check 'E11a two fields with one handler name: the second event is BLOCKED naming both' (($r.Out -match 'memOrdersPRICE OnGetText:  -> memOrdersPRICEGetText\n  \(unchecked\)') -and ($r.Out -match 'BLOCKED: handler memOrdersPRICEGetText is the name of two fields: (PRICE and PRI-CE|PRI-CE and PRICE)')) $r.Out
  $all = @([regex]::Matches($r.Out, '(?m)^\[(\d+)\] ') | ForEach-Object { $_.Groups[1].Value })
  PutSel $sel $r $all
  $rs = Write-Dfm ($hn + @('--select', $sel)) $hdfm $y2
  Check 'E11b selecting the blocked event is refused, the files stay as they were' (($rs.Code -eq 2) -and ($rs.Out -match 'change \d+ is blocked: handler memOrdersPRICEGetText is the name of two fields') -and ((Text $hdfm) -ceq $hOldDfm) -and ((Text $hpas) -ceq $hOldPas)) $rs.Out

  # ---- REVFIX (1.55 final review): a unit that ends in `begin ... end.` -- the new method goes BEFORE that block ----
  foreach ($case in @(@('e12a', "begin`n  RegisterClass(TfrmAllKinds);`nend.", 'an initialization block written begin..end.'),
      @('e12b', "procedure Tail;`nbegin`n  if True then`n  begin`n    case 1 of`n      1: ;`n    end;`n  end;`nend;`n`nbegin`n  try`n    RegisterClass(TfrmAllKinds);`n  finally`n  end;`nend.", 'nested begin / case / try before and inside it'))) {
    $ef = NewForms $case[0]
    $epas = Join-Path $ef 'uAllKinds.pas'; $edfm = Join-Path $ef 'uAllKinds.dfm'
    $tail = $case[1].Replace("`n", "`r`n")
    $et = Text $epas
    $cut = $et.LastIndexOf("end.")
    Put $epas ($et.Substring(0, $cut) + $tail + "`r`n")
    $r = Write-Dfm @() $edfm
    PutSel $sel $r @(IdOf $r 'insert uAllKinds\.dfm memOrdersQTY OnGetText')
    $rs = Write-Dfm @('--select', $sel) $edfm
    $np = Text $epas
    $at = $np.IndexOf('procedure TfrmAllKinds.memOrdersQTYGetText(')
    $block = $np.LastIndexOf("`r`nbegin`r`n")
    Check "E12 $($case[2]): the method is written before the block, the block is whole" (($rs.Code -eq 0) -and ($at -gt 0) -and ($at -lt $block) -and $np.EndsWith($tail.Substring($tail.LastIndexOf("begin`r`n  ")) + "`r`n") -and ($np.Substring(0, $at).EndsWith("end;`r`n`r`n")) -and
      ($np.Substring($at, $block - $at) -match "(?s)^procedure TfrmAllKinds\.memOrdersQTYGetText\(.*?\r\nend;\r\n$")) ($rs.Out + "`n" + $np.Substring([Math]::Max(0, $np.Length - 900)))
  }
  # control: the fixture itself ends in a plain `end.` and E3c pins the method before it
  # ---- Q3(2): removing a field takes its grid items ----
  $rf = NewForms 'remove'
  $rdfm = Join-Path $rf 'uAllKinds.dfm'; $rpas = Join-Path $rf 'uAllKinds.pas'
  $rOld = Text $rdfm; $rOldPas = Text $rpas
  $names = @('--dataset', 'memOrders', '--names', 'ID,QTY,OLDCOL,USEDCOL')
  $r = Write-Dfm $names $rdfm
  $col = IdOf $r "delete uAllKinds\.dfm TreeNOTE: TcxDBTreeListColumn; DataBinding\.FieldName = 'NOTE' -> \n  \(unchecked\)"
  $fld = IdOf $r "delete uAllKinds\.dfm memOrdersNOTE: [^\n]*\n  \(unchecked\)"
  Check 'E7 the tree-list column is a linked unchecked delete, the field is free' (($col -ne '') -and ($fld -ne '') -and ([int]$col -lt [int]$fld)) $r.Out
  PutSel $sel $r @($fld)
  $rs = Write-Dfm ($names + @('--select', $sel)) $rdfm
  Check 'E8 the field without its column is refused' (($rs.Code -eq 2) -and ($rs.Out -match "change $fld needs change $col")) $rs.Out
  PutSel $sel $r @($col, $fld)
  $rs = Write-Dfm ($names + @('--select', $sel)) $rdfm
  $wantDfm = [regex]::Replace([regex]::Replace($rOld, "(?ms)^    object TreeNOTE: .*?^    end\r\n", ''), "(?ms)^    object memOrdersNOTE: .*?^    end\r\n", '')
  $wantPas = $rOldPas.Replace("    TreeNOTE: TcxDBTreeListColumn;`r`n", '').Replace("    memOrdersNOTE: TStringField;`r`n", '')
  Check 'E9a column and field go from the DFM and the unit, nothing else' (($rs.Code -eq 0) -and ((Text $rdfm) -ceq $wantDfm) -and ((Text $rpas) -ceq $wantPas)) ($rs.Out + "`n" + (Text $rdfm))
  if (-not $SkipForm) {
    $after = BuildForm $rf
    Check 'E9b the form loads with one tree column' (($after -match 'LOADED') -and ($after -match '(?m)^columns=2,1\r?$') -and ($after -notmatch 'memOrdersNOTE')) $after
  }
  $r = Write-Dfm @('--dataset', 'memOrders', '--names', 'ID,NOTE,OLDCOL,USEDCOL') (Join-Path (NewForms 'qty') 'uAllKinds.dfm')
  Check 'E10 a column another property names: column and field BLOCKED' (($r.Out -match "delete uAllKinds\.dfm GridViewQTY: [^\n]*\n  BLOCKED: used in the DFM: GridView\.") -and ($r.Out -match "delete uAllKinds\.dfm memOrdersQTY: [^\n]*\n  BLOCKED: its grid item GridViewQTY cannot be removed")) $r.Out

  # ---- BDE policy per project (owner 2026-11-26, revised Q2): project setting fieldrepo.bde = full | readonly | none ----
  # memOrders made a TTable; the project folder (the one holding _D-RAG) of the form carries the setting.
  function NewBdeForms($name, $policy, $class = 'TTable') {
    $p = Join-Path $work $name
    $d = Join-Path $p 'f'
    [IO.Directory]::CreateDirectory($d) | Out-Null
    foreach ($f in 'uAllKinds.dfm', 'uAllKinds.pas') { Put (Join-Path $d $f) ((Text (Join-Path $src $f)).Replace('memOrders: TFDMemTable', "memOrders: $class")) }
    [IO.Directory]::CreateDirectory((Join-Path $p '_D-RAG')) | Out-Null
    if ($policy) { [IO.File]::WriteAllText((Join-Path $p '_D-RAG\drag-lint-project.json'), "{`"fieldrepo`": {`"bde`": `"$policy`"}}") }
    Join-Path $d 'uAllKinds.dfm'
  }
  $bn = @('--dataset', 'memOrders', '--names', 'ID,QTY,OLDCOL,USEDCOL,PRICE')
  $insPrice = 'insert uAllKinds\.dfm memOrdersPRICE:  -> TBCDField[^\n]*\n'
  $evQty = 'insert uAllKinds\.dfm memOrdersQTY OnGetText:  -> memOrdersQTYGetText\n'
  $delCol = "delete uAllKinds\.dfm TreeNOTE: TcxDBTreeListColumn; DataBinding\.FieldName = 'NOTE' -> \n"
  foreach ($case in @(@('bdedefault', ''), @('bdefull', 'full'))) {
    $bd = NewBdeForms $case[0] $case[1]
    $r = Write-Dfm $bn $bd
    $tag = if ($case[1]) { 'full' } else { 'no setting' }
    Check "B1a BDE $tag : a field insert is planned as for FireDAC" (($r.Code -eq 0) -and ($r.Out -match ($insPrice + '\[')) -and ($r.Out -notmatch 'BLOCKED: BDE')) $r.Out
    Check "B1b BDE $tag : the new handler and the grid item removal are unchecked, not blocked" (($r.Out -match ($evQty + '  \(unchecked\)')) -and ($r.Out -match ($delCol + '  \(unchecked\)'))) $r.Out
    $ra = Write-Dfm ($bn + @('--apply')) $bd
    Check "B1c BDE $tag : --apply writes the checked field insert (positive control of B2d)" (($ra.Code -eq 0) -and ((Text $bd).Contains('object memOrdersPRICE: TBCDField'))) $ra.Out
  }
  foreach ($case in @(@('readonly', 'BDE dataset: read only \(project policy\)'), @('none', 'BDE not allowed in this project'))) {
    $bd = NewBdeForms ('bde' + $case[0]) $case[0]
    $bOld = Text $bd
    $r = Write-Dfm $bn $bd
    Check "B2a BDE $($case[0]): the field insert is BLOCKED" (($r.Code -eq 0) -and ($r.Out -match ($insPrice + '  BLOCKED: ' + $case[1]))) $r.Out
    Check "B2b BDE $($case[0]): the new handler is BLOCKED" ($r.Out -match ($evQty + '  BLOCKED: ' + $case[1])) $r.Out
    Check "B2c BDE $($case[0]): the grid item removal is BLOCKED" ($r.Out -match ($delCol + '  BLOCKED: ' + $case[1])) $r.Out
    $ra = Write-Dfm ($bn + @('--apply')) $bd
    Check "B2d BDE $($case[0]): --apply writes none of them" (($ra.Code -eq 0) -and -not ((Text $bd).Contains('memOrdersPRICE')) -and -not ((Text $bd).Contains('OnGetText')) -and ((Text $bd).Contains('object TreeNOTE'))) $ra.Out
  }
  $r = Write-Dfm $bn (NewBdeForms 'fdreadonly' 'readonly' 'TFDMemTable')
  Check 'B3 positive control: readonly leaves a FireDAC dataset alone' (($r.Code -eq 0) -and ($r.Out -match ($insPrice + '\[')) -and ($r.Out -notmatch 'BLOCKED: BDE')) $r.Out
  # R-155-BDE (owner 2026-11-26): readonly / none also refuse DELETING a persistent field (OLDCOL: no grid item, so the
  # 1.55 first cut allowed it); full (and no setting) still plans it
  $bd5 = @('--dataset', 'memOrders', '--names', 'ID,QTY,NOTE,USEDCOL')
  $delOld = 'delete uAllKinds\.dfm memOrdersOLDCOL: [^\n]*\n'
  foreach ($case in @(@('bde5full', 'full', '\(unchecked\)'), @('bde5readonly', 'readonly', 'BLOCKED: BDE dataset: read only \(project policy\)'),
      @('bde5none', 'none', 'BLOCKED: BDE not allowed in this project'))) {
    $r = Write-Dfm $bd5 (NewBdeForms $case[0] $case[1])
    Check "B5 BDE $($case[1]): deleting a persistent field is $($case[2])" (($r.Code -eq 0) -and ($r.Out -match ($delOld + '  ' + $case[2]))) $r.Out
  }
  $r = Write-Dfm $bd5 (NewBdeForms 'bde5fd' 'readonly' 'TFDMemTable')
  Check 'B5c positive control: readonly leaves the field delete of a FireDAC dataset alone' (($r.Code -eq 0) -and ($r.Out -match ($delOld + '  \(unchecked\)'))) $r.Out
  $r = Write-Dfm $bn (NewBdeForms 'bdebad' 'readwrite')
  Check 'B4 an unknown fieldrepo.bde value is refused (exit 1, names the key)' (($r.Code -eq 1) -and ($r.Out -match 'fieldrepo\.bde')) $r.Out
  # ---- REVFIX (1.55 final review #3, #5): the policy must not fail open ----
  # B6: a form outside every project tree, the repository inside a project: the repository's project decides
  $rp = Join-Path $work 'rp'
  [IO.Directory]::CreateDirectory((Join-Path $rp '_D-RAG')) | Out-Null
  [IO.File]::WriteAllText((Join-Path $rp '_D-RAG\drag-lint-project.json'), '{"fieldrepo": {"bde": "readonly"}}')
  $rpRepo = Join-Path $rp 'y.dlrepo'
  [IO.File]::Copy($script:y, $rpRepo)
  $od = Join-Path $work 'outside\f'
  [IO.Directory]::CreateDirectory($od) | Out-Null
  foreach ($f in 'uAllKinds.dfm', 'uAllKinds.pas') { Put (Join-Path $od $f) ((Text (Join-Path $src $f)).Replace('memOrders: TFDMemTable', 'memOrders: TTable')) }
  $r = Write-Dfm $bn (Join-Path $od 'uAllKinds.dfm') $rpRepo
  Check 'B6a a form outside the project tree: the project of the repository decides (insert BLOCKED)' (($r.Code -eq 0) -and ($r.Out -match ($insPrice + '  BLOCKED: BDE dataset: read only \(project policy\)'))) $r.Out
  Check 'B6b the plan names the policy and where it is from' ($r.Out -match '(?m)^bde policy readonly for uAllKinds\.dfm: fieldrepo\.bde of .*\\rp\\_D-RAG') $r.Out
  $r = Write-Dfm $bn (Join-Path $od 'uAllKinds.dfm')
  Check 'B6c control: no project anywhere -> full, and the plan SAYS it is the default for want of a project' (($r.Code -eq 0) -and ($r.Out -notmatch 'BLOCKED: BDE') -and ($r.Out -match '(?m)^bde policy full for uAllKinds\.dfm: default: no (project folder|fieldrepo\.bde in) ')) $r.Out
  $rj = Write-Dfm ($bn + @('--json')) (Join-Path $od 'uAllKinds.dfm') $rpRepo
  $jl = @($rj.Out -split "`n" | Where-Object { $_.StartsWith('{') })
  $jb = if ($jl.Count -gt 0) { @(($jl[-1] | ConvertFrom-Json | ForEach-Object { $_ }).bde) } else { @() }
  Check 'B6d --json carries it: bde[].dfm / policy / source' (($jb.Count -eq 1) -and ($jb[0].policy -eq 'readonly') -and ($jb[0].dfm -like '*uAllKinds.dfm') -and ($jb[0].source -like 'fieldrepo.bde of *')) $rj.Out
  # B8: a value that is not a string is refused, not read as full
  foreach ($bad in @('true', '0', '["none"]', '{"x": 1}', 'null')) {
    $bd = NewBdeForms ('bdetype' + [Math]::Abs($bad.GetHashCode())) ''
    [IO.File]::WriteAllText((Join-Path (Split-Path (Split-Path $bd)) '_D-RAG\drag-lint-project.json'), "{`"fieldrepo`": {`"bde`": $bad}}")
    $r = Write-Dfm $bn $bd
    Check "B8 fieldrepo.bde = $bad (not a string) is refused: exit 1, names the key, plans nothing" (($r.Code -eq 1) -and ($r.Out -match 'fieldrepo\.bde') -and ($r.Out -notmatch '# plan ')) $r.Out
  }
  # B9: two forms of two projects in one run: each has the policy of its own project
  $b9full = NewBdeForms 'b9full' 'full'
  $b9ro = NewBdeForms 'b9ro' 'readonly'
  foreach ($e in 'dfm', 'pas') { [IO.File]::Move(($b9ro -replace 'dfm$', $e), ((Split-Path $b9ro) + "\uSecond.$e")) }
  $b9ro = (Split-Path $b9ro) + '\uSecond.dfm'
  $r = Write-Dfm @() "$b9full;$b9ro"
  Check 'B9a the first form (full): its new handler is offered' (($r.Code -eq 0) -and ($r.Out -match ($evQty + '  \(unchecked\)'))) $r.Out
  Check 'B9b the second form (readonly): its new handler is BLOCKED -- the first file does not decide for it' ($r.Out -match ($evQty.Replace('uAllKinds', 'uSecond') + '  BLOCKED: BDE dataset: read only')) $r.Out
  Check 'B9c both policies are named' (($r.Out -match '(?m)^bde policy full for uAllKinds\.dfm: ') -and ($r.Out -match '(?m)^bde policy readonly for uSecond\.dfm: ')) $r.Out
  # B10 (#5): a class that DESCENDS from a BDE dataset, known from the project's index (type_ancestors)
  function NewIndexed($name, $class, [switch]$NoIndex) {
    $bd = NewBdeForms $name 'none' $class
    $p = Split-Path (Split-Path $bd)
    Put (Join-Path $p 'uMyData.pas') "unit uMyData;`n`ninterface`n`nuses`n  DBTables, FireDAC.Comp.Client;`n`ntype`n  TMyQuery = class(TQuery)`n  end;`n`n  TMyQuery2 = class(TMyQuery)`n  end;`n`n  TMyMem = class(TFDMemTable)`n  end;`n`nimplementation`n`nend.`n"
    if (-not $NoIndex) { $script:ix = Run @('index', $p, '--db', (Join-Path $p "_D-RAG\$name.sqlite")) }
    $bd
  }
  $r = Write-Dfm $bn (NewIndexed 'b10q' 'TMyQuery2')
  Check 'B10a TMyQuery2 = class(TMyQuery) = class(TQuery), policy none: the insert is BLOCKED' (($r.Code -eq 0) -and ($r.Out -match ($insPrice + '  BLOCKED: BDE not allowed in this project'))) ($r.Out + "`n" + $script:ix.Out)
  Check 'B10b the plan says the index was asked' ($r.Out -match '(?m)^bde policy none for uAllKinds\.dfm: .*BDE classes: by name and \d+ descendant\(s\) from b10q\.sqlite') $r.Out
  $r = Write-Dfm $bn (NewIndexed 'b10m' 'TMyMem')
  Check 'B10c control: TMyMem = class(TFDMemTable) in the same index is left alone' (($r.Code -eq 0) -and ($r.Out -match ($insPrice + '\[')) -and ($r.Out -notmatch 'BLOCKED: BDE')) $r.Out
  $r = Write-Dfm $bn (NewIndexed 'b10n' 'TMyQuery2' -NoIndex)
  Check 'B10d no index: the descendant is NOT known, and the plan says the classes are by name only' (($r.Code -eq 0) -and ($r.Out -notmatch 'BLOCKED: BDE') -and ($r.Out -match '(?m)^bde policy none for uAllKinds\.dfm: .*BDE classes: by name only \(no project index')) $r.Out
  $r = Write-Dfm $bn (NewIndexed 'b10w' 'TwwTable' -NoIndex)
  Check 'B10e no index: a well-known third-party BDE descendant (TwwTable) is known by name' (($r.Code -eq 0) -and ($r.Out -match ($insPrice + '  BLOCKED: BDE not allowed in this project'))) $r.Out
}
finally {
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
Write-Host ("{0} checks, {1}" -f $script:Count, $(if ($script:Failed) { 'FAILED' } else { 'all passed' })) -ForegroundColor (@('Green','Red')[[int]$script:Failed])
exit ([int]$script:Failed)
