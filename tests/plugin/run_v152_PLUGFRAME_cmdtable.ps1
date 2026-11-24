<#
  run_v152_PLUGFRAME_cmdtable.ps1 -- the 1.52 plugin command table (lane PLUGFRAME).

  WHAT IT COVERS.
    1. Package membership: DragLint.Plugin.Cmd152 and the six command stubs are
       in the .dpk `contains` clause AND the .dproj (a unit only in the .dproj
       is linked implicitly -> W1033 -> "Cannot load package" in the IDE).
    2. Editor.pas carries exactly ONE BuildCmd152Menu call, and every menu-
       building line of RegisterDragLintMenu (AddWrappedItem / AddSeparator /
       AddSectionHeader / .Caption:=) is identical to the base commit -- the
       visible menu is not otherwise touched.
    3. Headless (no ToolsAPI): a console program built from Cmd152 + the six
       stubs checks the table (the six ids, owners, all hidden), builds the
       rows into a fixture copy of the drag-lint root and checks the VISIBLE
       tree is byte-identical before and after while the FULL tree has one
       hidden item per row. Positive control: the same table with one row
       flipped to Visible must change the visible tree and show its submenu.
    4. Every top-level ParentPath / AfterCaption a row names exists in
       Editor.pas or is a new submenu (a typo would silently append instead).

  Params: -BaseRef  the commit before PLUGFRAME (Editor.pas menu lines compare to it)
          -EnabledIds  ids an owning lane has switched on (skip the hidden check)
          -ExactCount  rows expected (0 = at least the six)

  Usage: pwsh -File tests\plugin\run_v152_PLUGFRAME_cmdtable.ps1
#>
[CmdletBinding()]
param(
  # 7833a66b7 = main at 1.51.2-alpha (67823450c + the RPT Reports item factory, merged into 1.52 by INT15)
  [string]$BaseRef = '7833a66b7',
  [string[]]$EnabledIds = @('field-repository', 'field-repository-02-refresh', 'field-repository-03-orm', 'field-repository-04-dataservice', 'field-repository-05-memtable', 'field-repository-06-paramarray', 'field-repository-07-read-dataset', 'field-repository-08-read-form', 'field-repository-09-select-fields', 'check-init'),   # TTIDE (INT 1.52); 03/04/06 enabled by BK-TTFINISH (B33); check-init enabled by HBIDE
  [int]$ExactCount = 11,   # headless rows: check-init + idx-range + 9 field-repository (3 of them 1.54 TT-DIALOG); ToolsAPI units left out (H5)
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-plugframe-$PID"
)
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot '..\autotest\lib\WorkDirCleanup.ps1')
try {
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$plug = Join-Path $repo 'src\delphi-plugin'
$fail = 0
function Bad([string]$m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail++ }
function Ok([string]$m)  { Write-Host "ok: $m" }

$units = @('DragLint.Plugin.Cmd152', 'DragLint.Plugin.Cmd.CheckInit', 'DragLint.Plugin.Cmd.DisableRule',
           'DragLint.Plugin.Cmd.IdxRange', 'DragLint.Plugin.Cmd.FixMarker', 'DragLint.Plugin.Cmd.FieldRepo',
           'DragLint.Plugin.Cmd.ExtractConst')
$required = [ordered]@{ 'check-init' = 'HBIDE'; 'disable-rule' = 'DISRULE'; 'extract-constant' = 'XCONST';
                        'field-repository' = 'TTIDE'; 'fix-marker' = 'VSFIX'; 'idx-range' = 'IDXRANGE2' }

# ---- 1. package membership ----
$dpk   = [IO.File]::ReadAllText((Join-Path $plug 'dclDragLintWizard.dpk'))
$dproj = [IO.File]::ReadAllText((Join-Path $plug 'dclDragLintWizard.dproj'))
foreach ($u in $units) {
  if (-not (Test-Path (Join-Path $plug "$u.pas"))) { Bad "missing unit file $u.pas"; continue }
  if ($dpk -notmatch ('(?m)^\s*' + [regex]::Escape($u) + "\s+in\s+'" + [regex]::Escape("$u.pas") + "'")) { Bad "$u not in .dpk contains" }
  if ($dproj -notmatch ('<DCCReference Include="' + [regex]::Escape("$u.pas") + '"/>')) { Bad "$u not in .dproj" }
}
if ($fail -eq 0) { Ok "$($units.Count) units in .dpk contains and .dproj" }

# ---- 2. Editor.pas: one hook, menu lines unchanged ----
$editorPath = Join-Path $plug 'DragLint.Plugin.Editor.pas'
$editor = [IO.File]::ReadAllText($editorPath)
$hooks = [regex]::Matches($editor, '(?m)^[^{/\r\n]*\bBuildCmd152Menu\s*\(')
if ($hooks.Count -ne 1) { Bad "Editor.pas has $($hooks.Count) BuildCmd152Menu calls, expected 1" } else { Ok 'Editor.pas: one BuildCmd152Menu call' }
$menuLine = '\bAddWrappedItem\(|\bAddSeparator\(|\bAddSectionHeader\(|\.Caption\s*:='
$base = & { $ErrorActionPreference = 'Continue'; & git -C $repo show "${BaseRef}:src/delphi-plugin/DragLint.Plugin.Editor.pas" 2>$null }
if ($LASTEXITCODE -ne 0 -or -not $base) { Bad "cannot read Editor.pas at $BaseRef" }
else {
  $was = @($base | Where-Object { $_ -match $menuLine } | ForEach-Object { $_.Trim() })
  $now = @(($editor -split "`r?`n") | Where-Object { $_ -match $menuLine } | ForEach-Object { $_.Trim() } |
           Where-Object { $_ -ne 'Result:= AddWrappedItem(AParent, ACaption, AClick);' } |   # the hook's own factory line
  Where-Object { $_ -ne "Form.Caption:= 'drag-lint Call Graph';" })   # BK-SCOPEUI B39: a progress FORM's caption, not a menu item
  # positive control: the extraction must see the real menu (dozens of lines), or the compare is vacuous
  if ($was.Count -lt 50) { Bad "menu-line extraction saw only $($was.Count) lines at $BaseRef" }
  elseif (Compare-Object $was $now -SyncWindow 0) {
    Bad 'Editor.pas menu-building lines differ from base:'
    Compare-Object $was $now -SyncWindow 0 | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.SideIndicator) $($_.InputObject)" }
  } else { Ok "Editor.pas: $($now.Count) menu-building lines identical to $BaseRef" }
}
if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }

# ---- 3. headless table + fixture tree ----
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force (Join-Path $WorkDir 'dcu') | Out-Null
# H5 (INT): a unit whose uses clause names ToolsAPI outside a CONSOLE conditional cannot build headless (dcc64 has no designide);
# it stays in the package checks above and is left out of the console program. Its rows are then
# checked only by literal presence in its source.
$ideOnly  = @($units | Where-Object { $s = [IO.File]::ReadAllText((Join-Path $plug "$_.pas")); ($s -match '(?m)^\s*ToolsAPI\s*[,;]') -and ($s -notmatch '\{\$IFN?DEF CONSOLE\}') })
$headless = @($units | Where-Object { $ideOnly -notcontains $_ })
if ($headless -notcontains 'DragLint.Plugin.Cmd152') { Bad 'Cmd152 itself must build headless (no ToolsAPI)' }
if ($ideOnly.Count) { Ok "headless build leaves out ToolsAPI units: $($ideOnly -join ', ')" }
$usesList = ($headless | ForEach-Object { "  $_ in '$plug\$_.pas'" }) -join ",`r`n"
$dpr = @"
program Cmd152Check;
{`$APPTYPE CONSOLE}
uses
  System.SysUtils, Vcl.Menus,
$usesList;

var
  GPass, GFail: Integer;

procedure Check(pCond: Boolean; const pWhat: string);
begin
  if pCond then Inc(GPass) else begin Inc(GFail); Writeln('CHECK FAILED: ', pWhat); end;
end;

function AddItem(pParent: TMenuItem; const pCaption: string; pClick: TCmd152Click): TMenuItem;
begin
  Result:= TMenuItem.Create(pParent);
  Result.Caption:= pCaption;
  pParent.Add(Result);
end;

procedure Sub(pParent: TMenuItem; const pCaption: string; const pItems: array of string);
begin
  var lSub: TMenuItem:= AddItem(pParent, pCaption, nil);
  for var s in pItems do AddItem(lSub, s, nil);
end;

{ Fixture copy of the drag-lint root as RegisterDragLintMenu has built it when the hook runs. }
function Fixture: TMenuItem;
begin
  Result:= TMenuItem.Create(nil);
  for var s in TArray<string>.Create('Full Compile Sweep', '-', 'Rename Symbol...', 'Extract Method (selection)... (Ctrl+Alt+M)',
    'Safe Delete Symbol...', 'drag-lint Options...', '-') do AddItem(Result, s, nil);
  Sub(Result, 'Uses && Dependencies', ['Uses Audit -- interface->impl moves + unused...']);
  Sub(Result, 'Reports', ['Forms for testers (CSV)...']);
  Sub(Result, 'Inspect Symbol', ['Class Surface...']);
  Sub(Result, 'Code Quality', ['Run Lint All (Full Report)...', 'Allow a Finding on This Line...']);
  Sub(Result, 'Generate && Export', ['Doc Comment Stub (symbol)...']);
  Sub(Result, 'Convert Components', ['Open Conversion Editor...']);
  Sub(Result, 'Bookmarks', ['Go to Bookmark...']);
  Sub(Result, 'Index && Maintenance', ['Rebuild Index for This Project']);
end;

var
  lTable: TArray<TCmd152Command>;
  lRoot: TMenuItem;
  lBefore, lAfter, lFull: string;
begin
  try
    lTable:= Cmd152Table;
    if ParamStr(1) = '--table' then
    begin
      for var c in lTable do
        Writeln(c.Id, #9, c.OwnerLane, #9, c.ParentPath, #9, c.AfterCaption, #9, c.Caption, #9, BoolToStr(c.Visible, True));
      Exit;
    end;
    for var i:= 1 to High(lTable) do Check(CompareText(lTable[i - 1].Id, lTable[i].Id) < 0, 'table sorted by Id');
    for var c in lTable do Check(Assigned(c.Click) and (c.Caption <> ''), c.Id + ' has caption + click');

    lRoot:= Fixture;
    try
      lBefore:= DumpMenuTree(lRoot, True);
      BuildCmd152Menu(lRoot, lTable, AddItem);
      lAfter:= DumpMenuTree(lRoot, True);
      lFull:= DumpMenuTree(lRoot, False);
      Writeln('--- full tree ---'); Write(lFull); Writeln('--- end ---');
      if ParamStr(1) <> '--allow-visible' then
        Check(lBefore = lAfter, 'visible tree byte-identical before/after BuildCmd152Menu');
      for var c in lTable do
        Check(Pos(c.Caption, lFull) > 0, c.Id + ' item present in the full tree');
      Check(Length(lFull) > Length(lBefore), 'full tree grew');
    finally
      lRoot.Free;
    end;

    { positive control: one row switched on must show, with its submenu }
    if Length(lTable) > 0 then
    begin
      lTable[0].Visible:= True;
      lRoot:= Fixture;
      try
        lBefore:= DumpMenuTree(lRoot, True);
        BuildCmd152Menu(lRoot, lTable, AddItem);
        lAfter:= DumpMenuTree(lRoot, True);
        Check(lBefore <> lAfter, 'control: a visible row changes the visible tree');
        Check(Pos(lTable[0].Caption, lAfter) > 0, 'control: the visible row is in the visible tree');
      finally
        lRoot.Free;
      end;
    end;
    { duplicate ids are refused }
    var lRaised: Boolean:= False;
    try RegisterCmd152(lTable[0]); except on EArgumentException do lRaised:= True; end;
    Check(lRaised, 'duplicate Id refused');
  except
    on E: Exception do begin Inc(GFail); Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message); end;
  end;
  Writeln(GPass, ' passed, ', GFail, ' failed');
  if GFail > 0 then ExitCode:= 1;
end.
"@
[IO.File]::WriteAllText((Join-Path $WorkDir 'Cmd152Check.dpr'), ($dpr -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
$bat = Join-Path $WorkDir 'build.bat'
$lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $WorkDir),
  ('dcc64 -B -NSSystem;Winapi;Vcl -E"{0}" -N0"{0}\dcu" Cmd152Check.dpr' -f $WorkDir), 'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$buildLog = Join-Path $WorkDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $buildLog -NoNewWindow -Wait -PassThru; $null = $null.Handle
$buildOut = [IO.File]::ReadAllText($buildLog)
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FAIL: headless check did not compile' -ForegroundColor Red
  ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
  exit 1
}
$exe = Join-Path $WorkDir 'Cmd152Check.exe'

$rows = @(& $exe --table | Where-Object { $_ } | ForEach-Object {
  $f = $_ -split "`t"; [pscustomobject]@{ Id = $f[0]; Owner = $f[1]; Parent = $f[2]; After = $f[3]; Caption = $f[4]; Visible = ($f[5] -eq 'True') } })
Write-Host "table: $($rows.Count) rows"
$rows | ForEach-Object { Write-Host ("  {0,-17} {1,-9} {2,-28} visible={3}  {4}" -f $_.Id, $_.Owner, $_.Parent, $_.Visible, $_.Caption) }
if ($ExactCount -gt 0 -and $rows.Count -ne $ExactCount) { Bad "table has $($rows.Count) rows, expected $ExactCount" }
foreach ($k in $required.Keys) {
  $r = $rows | Where-Object Id -eq $k
  if (-not $r) {
    $src = @($ideOnly | Where-Object { [IO.File]::ReadAllText((Join-Path $plug "$_.pas")) -match ("'" + [regex]::Escape($k) + "'") })
    if ($src.Count) { Ok "$k registered by IDE-only unit $($src -join ', ') (not in the headless table)" } else { Bad "table lacks $k" }
    continue
  }
  if ($r.Owner -ne $required[$k]) { Bad "$k owner '$($r.Owner)', expected $($required[$k])" }
}
$visible = @($rows | Where-Object { $_.Visible -and ($EnabledIds -notcontains $_.Id) })
if ($visible.Count) { Bad "rows visible before their lane enabled them: $(($visible.Id) -join ', ')" } else { Ok 'every row hidden (or listed in -EnabledIds)' }

# ---- 4. named parents / anchors exist ----
foreach ($r in $rows) {
  $top = ($r.Parent -split '>')[0].Trim()
  if ($top -and $editor -notmatch ("Caption:=\s*'" + [regex]::Escape($top) + "'")) { Write-Host "  note: $($r.Id) creates new submenu '$top'" }
  if ($r.After -and $editor -notmatch ("'" + [regex]::Escape($r.After) + "'")) { Bad "$($r.Id) AfterCaption '$($r.After)' not found in Editor.pas" }
}

$out = & { $ErrorActionPreference = 'Continue'; & $exe $(if ($EnabledIds.Count) { '--allow-visible' }) 2>&1 | ForEach-Object { "$_" } } | Out-String
$rc = $LASTEXITCODE
Write-Host $out.TrimEnd()
if ($rc -ne 0) { Bad "headless check exit $rc" }
if ($out -notmatch '(\d+) passed, 0 failed') { Bad 'no pass/fail summary from the headless check' }

if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
