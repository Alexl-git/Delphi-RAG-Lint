<#
  run_v152_PLUGCTX_menu.ps1 -- the editor right-click menu of the IDE plugin (lane PLUGCTX).

  WHAT IT COVERS.
    1. Static: DragLint.Plugin.EditorLocalMenu is in the .dpk `contains` AND the
       .dproj; Editor.pas registers it exactly once and unregisters it in its
       teardown; the wizard's Destroyed unregisters it; the unit registers AND
       unregisters its action list with INTAEditorLocalMenu; every
       DragLint.Plugin.Cmd.X stub sets Command.Surfaces and Command.Needs (a
       record local is NOT zero-filled, so an unset set is garbage).
    2. Headless (no ToolsAPI): a console program built from Cmd152 + the six
       stubs checks every row's Surfaces / Needs against the expected map, the
       surface filter, the enable truth table, the right-click path, that
       RegisterCmd152 refuses empty Surfaces, and that BuildCmd152Menu leaves an
       editor-only row OUT of the main menu (positive control: the same row
       with csMainMenu IS placed).
    3. Registry: features\entries\editor-context-menu.json carries the
       ide-context Editor surface 'drag-lint'; every VISIBLE editor row has an
       ide-context Editor surface 'drag-lint > <Caption>' in some entry.
    4. -Build: Win32 + Win64 BPL builds of dclDragLintWizard.dproj into
       -WorkDir (never into third_party); BUILD_EXITCODE=0, no [dcc] Error.

  Usage: pwsh -File tests\autotest\run_v152_PLUGCTX_menu.ps1 [-Build]
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-plugctx-$PID"
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$plug = Join-Path $repo 'src\delphi-plugin'
$fail = 0
function Bad([string]$m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail++ }
function Ok([string]$m)  { Write-Host "ok: $m" }
function Code([string]$text) {
  # strip { } and // comments so a call named in a comment does not count
  $t = [regex]::Replace($text, '\{[^}]*\}', '')
  return [regex]::Replace($t, '//[^\r\n]*', '')
}

$hookUnit = 'DragLint.Plugin.EditorLocalMenu'
$stubs = @('CheckInit', 'DisableRule', 'IdxRange', 'FixMarker', 'FieldRepo', 'ExtractConst')
# rows whose unit needs the IDE (ToolsAPI) and cannot compile headless: id -> unit; their shape is read from the source
$ideOnly = @{ 'fix-marker' = 'FixMarker'; 'disable-rule' = 'DisableRule' }  # DISRULE H5: Cmd.DisableRule uses ToolsAPI; VSFIX made Cmd.FixMarker a real command (ToolsAPI, Plugin.Editor)
# id -> surfaces|needs (the PLUGCTX defaults; an owning lane that changes its row updates this map)
$expect = [ordered]@{
  'check-init'       = 'main+editor|cnSymbol'
  'disable-rule'     = 'main+editor|cnFinding'
  'extract-constant' = 'main+editor|cnNothing'
  'field-repository' = 'main|cnNothing'
  'fix-marker'       = 'main+editor|cnFinding'
  'idx-range'        = 'main+editor|cnFinding'
}

# ---- 1. static ----
$dpk   = [IO.File]::ReadAllText((Join-Path $plug 'dclDragLintWizard.dpk'))
$dproj = [IO.File]::ReadAllText((Join-Path $plug 'dclDragLintWizard.dproj'))
$hookPath = Join-Path $plug "$hookUnit.pas"
if (-not (Test-Path $hookPath)) { Bad "missing $hookUnit.pas"; Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
if ($dpk -notmatch ('(?m)^\s*' + [regex]::Escape($hookUnit) + "\s+in\s+'" + [regex]::Escape("$hookUnit.pas") + "'")) { Bad "$hookUnit not in .dpk contains" } else { Ok "$hookUnit in .dpk contains" }
if ($dproj -notmatch ('<DCCReference Include="' + [regex]::Escape("$hookUnit.pas") + '"/>')) { Bad "$hookUnit not in .dproj" } else { Ok "$hookUnit in .dproj" }

$editor = Code ([IO.File]::ReadAllText((Join-Path $plug 'DragLint.Plugin.Editor.pas')))
$n = [regex]::Matches($editor, '(?m)^\s*RegisterDragLintEditorLocalMenu\s*;').Count
if ($n -ne 1) { Bad "Editor.pas registers the editor menu $n times, expected 1" } else { Ok 'Editor.pas: one RegisterDragLintEditorLocalMenu' }
if ($editor -notmatch '(?m)^\s*UnregisterDragLintEditorLocalMenu\s*;') { Bad 'Editor.pas teardown does not unregister the editor menu' } else { Ok 'Editor.pas teardown unregisters' }
$wizard = Code ([IO.File]::ReadAllText((Join-Path $plug 'DragLint.Plugin.Wizard.pas')))
$destroyed = [regex]::Match($wizard, '(?s)procedure TDragLintWizard\.Destroyed;.*?\r?\nend;')
if (-not $destroyed.Success -or $destroyed.Value -notmatch 'UnregisterDragLintEditorLocalMenu') { Bad 'TDragLintWizard.Destroyed does not unregister the editor menu' } else { Ok 'wizard Destroyed unregisters' }
$hook = Code ([IO.File]::ReadAllText($hookPath))
foreach ($p in 'GetEditorLocalMenu', '\.RegisterActionList\(', '\.UnregisterActionList\(', 'Cmd152OnSurface\(\s*Cmd152Table\s*,\s*csEditorContext\s*\)', 'Cmd152Enabled\(') {
  if ($hook -notmatch $p) { Bad "$hookUnit lacks $p" }
}
if ($hook -notmatch "EDITOR_SUBMENU_CAPTION\s*=\s*'drag-lint'") { Bad "$hookUnit lacks EDITOR_SUBMENU_CAPTION = 'drag-lint' (featuregen harvests it)" }
if ($hook -match '(?m)^\s*procedure\s+Destroyed\s*;\s*override') { Bad "${hookUnit}: Destroyed is not virtual (HOWTO pitfall), no override" }
foreach ($s in $stubs) {
  $t = Code ([IO.File]::ReadAllText((Join-Path $plug "DragLint.Plugin.Cmd.$s.pas")))
  if ($t -notmatch 'Command\.Surfaces\s*:=\s*\[') { Bad "Cmd.$s does not set Command.Surfaces" }
  if ($t -notmatch 'Command\.Needs\s*:=\s*cn') { Bad "Cmd.$s does not set Command.Needs" }
}
if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Ok "hook unit wired; $($stubs.Count) stubs set Surfaces + Needs"

# ---- 2. headless ----
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force (Join-Path $WorkDir 'dcu') | Out-Null
$units = @('DragLint.Plugin.Cmd152') + ($stubs | Where-Object { $_ -notin $ideOnly.Values } | ForEach-Object { "DragLint.Plugin.Cmd.$_" })
$usesList = ($units | ForEach-Object { "  $_ in '$plug\$_.pas'" }) -join ",`r`n"
$dpr = @"
program CtxCheck;
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

procedure Nop(Sender: TObject);
begin
end;

function SurfText(const pCmd: TCmd152Command): string;
begin
  Result:= '';
  if csMainMenu in pCmd.Surfaces then Result:= 'main';
  if csEditorContext in pCmd.Surfaces then Result:= Result + (if Result = '' then '' else '+') + 'editor';
end;

const
  NEEDS_TEXT: array[TCmd152Needs] of string = ('cnNothing', 'cnSymbol', 'cnFinding');

var
  lTable, lEditor, lMain: TArray<TCmd152Command>;
  lCmd: TCmd152Command;
  lRoot: TMenuItem;
begin
  try
    lTable:= Cmd152Table;
    if ParamStr(1) = '--table' then
    begin
      for var c in lTable do
        Writeln(c.Id, #9, SurfText(c), '|', NEEDS_TEXT[c.Needs], #9, BoolToStr(c.Visible, True), #9, Cmd152EditorPath(c));
      Exit;
    end;
    for var c in lTable do Check(c.Surfaces <> [], c.Id + ' has a surface');
    lEditor:= Cmd152OnSurface(lTable, csEditorContext);
    lMain:= Cmd152OnSurface(lTable, csMainMenu);
    for var c in lEditor do Check(csEditorContext in c.Surfaces, 'editor filter: ' + c.Id);
    for var c in lMain do Check(csMainMenu in c.Surfaces, 'main filter: ' + c.Id);
    Check(Length(lEditor) + Length(lMain) >= Length(lTable), 'filters cover the table');

    { enable truth table }
    lCmd:= Default(TCmd152Command);
    lCmd.Needs:= cnNothing;
    Check(Cmd152Enabled(lCmd, False, False), 'cnNothing enabled with no context');
    lCmd.Needs:= cnSymbol;
    Check(not Cmd152Enabled(lCmd, False, True), 'cnSymbol disabled without a symbol');
    Check(Cmd152Enabled(lCmd, True, False), 'cnSymbol enabled on a symbol');
    lCmd.Needs:= cnFinding;
    Check(not Cmd152Enabled(lCmd, True, False), 'cnFinding disabled without a finding');
    Check(Cmd152Enabled(lCmd, False, True), 'cnFinding enabled on a finding');

    { right-click path }
    lCmd.Caption:= '&Disable Rule...';
    lCmd.Surfaces:= [csEditorContext];
    Check(Cmd152EditorPath(lCmd) = 'Editor context > drag-lint > Disable Rule...', 'editor path: ' + Cmd152EditorPath(lCmd));
    lCmd.Surfaces:= [csMainMenu];
    Check(Cmd152EditorPath(lCmd) = '', 'no editor path off the editor surface');

    { empty Surfaces refused }
    var lRaised: Boolean:= False;
    lCmd:= Default(TCmd152Command);
    lCmd.Id:= 'ctx-empty-surfaces';
    lCmd.Caption:= 'x';
    lCmd.Click:= Nop;
    try RegisterCmd152(lCmd); except on EArgumentException do lRaised:= True; end;
    Check(lRaised, 'empty Surfaces refused');

    { editor-only row stays off the main menu; control: with csMainMenu it is placed }
    lCmd.Id:= 'ctx-editor-only';
    lCmd.Caption:= 'Editor Only Probe';
    lCmd.Visible:= True;
    lCmd.Surfaces:= [csEditorContext];
    lRoot:= TMenuItem.Create(nil);
    try
      BuildCmd152Menu(lRoot, [lCmd], AddItem);
      Check(Pos('Editor Only Probe', DumpMenuTree(lRoot, False)) = 0, 'editor-only row not in the main menu');
    finally
      lRoot.Free;
    end;
    lCmd.Surfaces:= [csMainMenu, csEditorContext];
    lRoot:= TMenuItem.Create(nil);
    try
      BuildCmd152Menu(lRoot, [lCmd], AddItem);
      Check(Pos('Editor Only Probe', DumpMenuTree(lRoot, True)) > 0, 'control: the same row with csMainMenu is placed');
    finally
      lRoot.Free;
    end;
  except
    on E: Exception do begin Inc(GFail); Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message); end;
  end;
  Writeln(GPass, ' passed, ', GFail, ' failed');
  if GFail > 0 then ExitCode:= 1;
end.
"@
[IO.File]::WriteAllText((Join-Path $WorkDir 'CtxCheck.dpr'), ($dpr -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
$bat = Join-Path $WorkDir 'build.bat'
$lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $WorkDir),
  ('dcc64 -B -NSSystem;Winapi;Vcl -E"{0}" -N0"{0}\dcu" CtxCheck.dpr' -f $WorkDir), 'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$buildLog = Join-Path $WorkDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $buildLog -NoNewWindow -Wait -PassThru
$buildOut = [IO.File]::ReadAllText($buildLog)
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FAIL: headless check did not compile' -ForegroundColor Red
  ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
  exit 1
}
$exe = Join-Path $WorkDir 'CtxCheck.exe'
$rows = @(& $exe --table | Where-Object { $_ } | ForEach-Object {
  $f = $_ -split "`t"; [pscustomobject]@{ Id = $f[0]; Shape = $f[1]; Visible = ($f[2] -eq 'True'); Path = $f[3] } })
$rows | ForEach-Object { Write-Host ("  {0,-17} {1,-24} visible={2}  {3}" -f $_.Id, $_.Shape, $_.Visible, $_.Path) }
foreach ($k in $expect.Keys) {
  $r = $rows | Where-Object Id -eq $k
  if (-not $r -and $ideOnly.ContainsKey($k)) {
    $src = Code ([IO.File]::ReadAllText((Join-Path $plug "DragLint.Plugin.Cmd.$($ideOnly[$k]).pas")))
    $sm = [regex]::Match($src, 'Command\.Surfaces\s*:=\s*\[([^\]]*)\]'); $nm = [regex]::Match($src, 'Command\.Needs\s*:=\s*(cn\w+)')
    $surf = @($sm.Groups[1].Value -split ',' | ForEach-Object { switch ($_.Trim()) { 'csMainMenu' { 'main' } 'csEditorContext' { 'editor' } default { $_.Trim() } } }) -join '+'
    $shape = "$surf|$($nm.Groups[1].Value)"
    if ($shape -ne $expect[$k]) { Bad "$k (source, IDE-only unit) is $shape, expected $($expect[$k])" } else { Ok "$k (source, IDE-only unit) $shape" }
    continue
  }
  if (-not $r) { Bad "table lacks $k"; continue }
  if ($r.Shape -ne $expect[$k]) { Bad "$k is $($r.Shape), expected $($expect[$k])" }
}
$out = & { $ErrorActionPreference = 'Continue'; & $exe 2>&1 | ForEach-Object { "$_" } } | Out-String
$rc = $LASTEXITCODE
Write-Host $out.TrimEnd()
if ($rc -ne 0) { Bad "headless check exit $rc" }
if ($out -notmatch '(\d+) passed, 0 failed') { Bad 'no pass/fail summary from the headless check' }

# ---- 3. registry ----
$ctx = @{}
foreach ($f in Get-ChildItem (Join-Path $repo 'features\entries') -Filter *.json) {
  $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
  foreach ($s in @($j.surfaces)) {
    if ($s.type -eq 'ide-context' -and $s.host -eq 'Editor') { $ctx[$s.caption] = $j.id }
  }
}
if ($ctx['drag-lint'] -ne 'editor-context-menu') { Bad "no entry editor-context-menu with ide-context Editor 'drag-lint' (found: '$($ctx['drag-lint'])')" } else { Ok "registry: editor-context-menu carries ide-context Editor 'drag-lint'" }
foreach ($r in $rows | Where-Object { $_.Visible -and $_.Path }) {
  $cap = $r.Path -replace '^Editor context > ', ''
  if (-not $ctx.ContainsKey($cap)) { Bad "$($r.Id) is visible on the editor menu but no entry has ide-context Editor '$cap'" }
}

# ---- 4. BPL build ----
if ($Build) {
  foreach ($pl in 'Win32', 'Win64') {
    $out = Join-Path $WorkDir "bpl\$pl"
    New-Item -ItemType Directory -Force (Join-Path $out 'dcu') | Out-Null
    $b = Join-Path $WorkDir "bpl_$pl.bat"
    $bl = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $plug),
      ("msbuild /t:Build /p:Config=Debug /p:Platform=$pl /p:DCC_BplOutput=$out /p:DCC_DcpOutput=$out /p:DCC_DcuOutput=$out\dcu /v:normal dclDragLintWizard.dproj"),
      'echo BUILD_EXITCODE=%ERRORLEVEL%')
    [IO.File]::WriteAllText($b, (($bl -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    $log = Join-Path $WorkDir "bpl_$pl.log"
    $null = Start-Process cmd.exe -ArgumentList '/c', "`"$b`"" -RedirectStandardOutput $log -NoNewWindow -Wait -PassThru
    $txt = [IO.File]::ReadAllText($log)
    if ($txt -notmatch 'BUILD_EXITCODE=0' -or $txt -match '\[dcc\w*\] Error|: error ') { Bad "$pl BPL build failed (log $log)" }
    elseif (-not (Test-Path (Join-Path $out 'dclDragLintWizard.bpl'))) { Bad "$pl BPL not produced" }
    else { Ok "$pl BPL build 0 errors" }
  }
}

if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
