<#
  run_v152_HBIDE_menu.ps1 -- "Check Initialization of Identifier at Cursor..." (lane HBIDE, ruling HB1).

  WHAT IT COVERS.
    1. Headless (no ToolsAPI, console build of Cmd152 + Cmd.CheckInit): the
       check-init row is VISIBLE, owned by HBIDE, on the main menu (submenu
       Analyze) AND the editor right-click menu, enabled only on an identifier.
       Positive control: the same row switched off is absent from the visible tree.
    2. CheckInitCommandLine: the exact command line for a caret position
       (exe, file, db quoted; --at file:line:col; --json).
    3. CheckInitMessages on canned check-init --json answers (keys as written by
       DRagLint.Query.HappensBefore.Render.HbAnswerJson): MAY-BE-UNSET with a use,
       witness hops, writers and limits -> the exact Messages lines; SET -> no
       hint line; UNKNOWN-CALLEE (lane HBTAIL) -> the callee hint (positive
       control of the "no hint on SET" check); an engine error -> one title.
    4. features\entries\check-init.json carries the FULL ide-menu path and the
       ide-context caption.
    5. Live leg (only with -Engine <1.52 drag-lint.exe>): a two-unit fixture is
       indexed, the command line CheckInitCommandLine builds for the caret on a
       read of HbCfg.GCount is run as is, and its real output is parsed: title
       "check-init HbCfg.GCount: SET" and a use line located at the caret.

  Usage: pwsh -File tests\plugin\run_v152_HBIDE_menu.ps1
#>
[CmdletBinding()]
param([string]$WorkDir = "$env:TEMP\drag-lint-v152-hbide-$PID",
      [string]$Engine = '')   # optional: a 1.52 engine exe for the live leg (5.)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$plug = Join-Path $repo 'src\delphi-plugin'
$fail = 0
function Bad([string]$m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail++ }
function Ok([string]$m)  { Write-Host "ok: $m" }

$caption = 'Check Initialization of Identifier at Cursor...'

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force (Join-Path $WorkDir 'dcu') | Out-Null

# ---- canned engine answers (check-init --json shape, Render.pas HbAnswerJson) ----
$mayBeUnset = @'
{"target":{"qname":"UnitA.GCache","kind":"unit-var","file":"C:\\src\\UnitA.pas","line":9,"type":"TCache","zero_value":"nil"},
 "verdict":"MAY-BE-UNSET","proven":false,"scope":"at","summary":"1 of 1 use may run before a writer",
 "reasons":["no-writer-on-path"],
 "uses":[{"file":"C:\\src\\UnitB.pas","line":14,"col":12,"routine":"UnitB.TForm1.FormCreate","verdict":"MAY-BE-UNSET",
   "reasons":["no-writer-on-path","event-order"],"why":"FormCreate can run before InitCache",
   "witness":[{"step":1,"routine":"Project1","file":"C:\\src\\Project1.dpr","line":20,"col":3,"note":"Application.CreateForm(TForm1)"},
              {"step":2,"routine":"UnitB.TForm1.FormCreate","file":"C:\\src\\UnitB.pas","line":14,"col":12,"note":"reads GCache"}]}],
 "writers":[{"file":"C:\\src\\UnitA.pas","line":30,"col":5,"routine":"UnitA.InitCache","how":"assign","resolved":true,"counts":true,"fired_by":"","callers":{"count":2,"top":["UnitC.Boot"]}},
            {"file":"C:\\src\\UnitD.pas","line":7,"col":3,"routine":"UnitD.TDm.DataModuleCreate","how":"assign","resolved":false,"counts":false,"fired_by":"OnCreate","callers":{"count":0,"top":[]}}],
 "roots":{"ordered":["Project1"],"unordered":0},
 "limits":["budget: 500 routines"],
 "budget":{"routines":12,"ms":40,"exhausted":false}}
'@
$set = @'
{"target":{"qname":"UnitA.GReady","kind":"unit-var","file":"C:\\src\\UnitA.pas","line":10,"type":"Boolean","zero_value":"False"},
 "verdict":"SET","proven":true,"scope":"at","summary":"","reasons":[],
 "uses":[{"file":"C:\\src\\UnitB.pas","line":15,"col":7,"routine":"UnitB.Go","verdict":"SET","reasons":[],"why":"","witness":[]}],
 "writers":[],"roots":{"ordered":[],"unordered":0},"limits":[],"budget":{"routines":3,"ms":5,"exhausted":false}}
'@
$unknownCallee = @'
{"target":{"qname":"UnitA.GLog","kind":"unit-var","file":"C:\\src\\UnitA.pas","line":11,"type":"TLog","zero_value":"nil"},
 "verdict":"UNKNOWN-CALLEE","proven":false,"scope":"at","summary":"UnitB.Go calls Plugin.Setup, which the index cannot resolve",
 "reasons":["unknown-callee"],
 "uses":[{"file":"C:\\src\\UnitB.pas","line":16,"col":3,"routine":"UnitB.Go","verdict":"MAY-BE-UNSET","reasons":["unknown-callee"],"why":"","witness":[]}],
 "writers":[],"roots":{"ordered":[],"unordered":0},"limits":[],"budget":{"routines":3,"ms":5,"exhausted":false}}
'@
foreach ($p in @(@('may.json', $mayBeUnset), @('set.json', $set), @('unk.json', $unknownCallee),
                 @('err.txt', "ERROR: check-init: --at names no variable or field`r`n"))) {
  [IO.File]::WriteAllText((Join-Path $WorkDir $p[0]), $p[1], [Text.Encoding]::ASCII)
}

$dpr = @"
program CheckInitMenuCheck;
{`$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, Vcl.Menus,
  DragLint.Plugin.Cmd152 in '$plug\DragLint.Plugin.Cmd152.pas',
  DragLint.Plugin.Cmd.CheckInit in '$plug\DragLint.Plugin.Cmd.CheckInit.pas';

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

function Render(const pMsgs: TArray<TCheckInitMsg>): string;
const
  KINDS: array[TCheckInitMsgKind] of string = ('T', 'M');
begin
  Result:= '';
  for var M in pMsgs do
    Result:= Result + Format('%s|%s|%d|%d|%s', [KINDS[M.Kind], M.FileName, M.Line, M.Col, M.Text]) + sLineBreak;
end;

function Load(const pName: string): string;
begin
  Result:= TFile.ReadAllText(TPath.Combine('$WorkDir', pName));
end;

procedure Expect(const pGot, pWant, pWhat: string);
begin
  Check(pGot = pWant, pWhat + sLineBreak + '--- got ---' + sLineBreak + pGot + '--- want ---' + sLineBreak + pWant);
end;

var
  lMine: TArray<TCmd152Command>;
  lRoot: TMenuItem;
  lVisible: string;
  lCmd: TCmd152Command;
  lGot, lWant: string;
begin
  if ParamStr(1) = 'cmdline' then
  begin
    Writeln(CheckInitCommandLine(ParamStr(2), ParamStr(3), ParamStr(4), StrToInt(ParamStr(5)), StrToInt(ParamStr(6))));
    Exit;
  end;
  if ParamStr(1) = 'parse' then
  begin
    Write(Render(CheckInitMessages(TFile.ReadAllText(ParamStr(2)), StrToInt(ParamStr(3)))));
    Exit;
  end;
  try
    SetLength(lMine, 0);
    for lCmd in Cmd152Table do
      if lCmd.Id = 'check-init' then lMine:= lMine + [lCmd];
    Check(Length(lMine) = 1, 'one check-init row, got ' + IntToStr(Length(lMine)));
    if Length(lMine) = 1 then
    begin
      lCmd:= lMine[0];
      Check(lCmd.OwnerLane = 'HBIDE', 'owner lane');
      Check(lCmd.Visible, 'check-init row is visible');
      Check(lCmd.ParentPath = 'Analyze', 'parent path Analyze');
      Check(lCmd.Caption = '$caption', 'caption: ' + lCmd.Caption);
      Check(lCmd.Surfaces = [csMainMenu, csEditorContext], 'main menu and editor right-click');
      Check(lCmd.Needs = cnSymbol, 'needs an identifier under the caret');
      Check(not Cmd152Enabled(lCmd, False, True), 'disabled without an identifier');
      Check(Cmd152Enabled(lCmd, True, False), 'enabled on an identifier');
      Check(Cmd152EditorPath(lCmd) = 'Editor context > drag-lint > $caption', 'editor path: ' + Cmd152EditorPath(lCmd));
      lRoot:= TMenuItem.Create(nil);
      try
        BuildCmd152Menu(lRoot, lMine, AddItem);
        lVisible:= DumpMenuTree(lRoot, True);
      finally
        lRoot.Free;
      end;
      Writeln('--- visible ---'); Write(lVisible); Writeln('--- end ---');
      Check(lVisible = 'Analyze' + sLineBreak + '  $caption' + sLineBreak, 'visible tree Analyze > caption');
      { positive control: the same row switched off is not in the visible tree }
      lMine[0].Visible:= False;
      lRoot:= TMenuItem.Create(nil);
      try
        BuildCmd152Menu(lRoot, lMine, AddItem);
        Check(DumpMenuTree(lRoot, True) = '', 'control: a hidden row shows nothing');
      finally
        lRoot.Free;
      end;
    end;

    { command line for a caret position }
    lGot:= CheckInitCommandLine('C:\x y\drag-lint.exe', 'C:\p q\UnitB.pas', 'C:\d b\App.sqlite', 14, 12);  // # exe-freshness: absent (a fake path the command line only quotes)
    Expect(lGot, '"C:\x y\drag-lint.exe" check-init --at "C:\p q\UnitB.pas:14:12" --db "C:\d b\App.sqlite" --json', 'command line');  // # exe-freshness: absent (a fake path the command line only quotes)

    { MAY-BE-UNSET: use, witness hops, writers, limits }
    lGot:= Render(CheckInitMessages(Load('may.json'), 1));
    lWant:=
      'T||0|0|check-init UnitA.GCache: MAY-BE-UNSET -- 1 of 1 use may run before a writer' + sLineBreak +
      'M|C:\src\UnitB.pas|14|12|use in UnitB.TForm1.FormCreate: MAY-BE-UNSET [no-writer-on-path, event-order] -- FormCreate can run before InitCache' + sLineBreak +
      'M|C:\src\Project1.dpr|20|3|  1. Project1: Application.CreateForm(TForm1)' + sLineBreak +
      'M|C:\src\UnitB.pas|14|12|  2. UnitB.TForm1.FormCreate: reads GCache' + sLineBreak +
      'M|C:\src\UnitA.pas|30|5|writer UnitA.InitCache (assign), 2 caller(s)' + sLineBreak +
      'M|C:\src\UnitD.pas|7|3|writer UnitD.TDm.DataModuleCreate (assign, fired by OnCreate, unresolved, not counted), 0 caller(s)' + sLineBreak +
      'M||0|0|limit: budget: 500 routines' + sLineBreak;
    Expect(lGot, lWant, 'MAY-BE-UNSET lines');

    { SET: title, the use, no hint }
    lGot:= Render(CheckInitMessages(Load('set.json'), 0));
    lWant:=
      'T||0|0|check-init UnitA.GReady: SET' + sLineBreak +
      'M|C:\src\UnitB.pas|15|7|use in UnitB.Go: SET' + sLineBreak;
    Expect(lGot, lWant, 'SET lines');
    Check(Pos('checkInit', lGot) = 0, 'SET carries no callee hint');

    { UNKNOWN-CALLEE (HBTAIL): the hint is there -- positive control of the check above }
    lGot:= Render(CheckInitMessages(Load('unk.json'), 1));
    lWant:=
      'T||0|0|check-init UnitA.GLog: UNKNOWN-CALLEE -- UnitB.Go calls Plugin.Setup, which the index cannot resolve' + sLineBreak +
      'M||0|0|UNKNOWN-CALLEE: a call the index cannot resolve may set it; answer the callee in <project>\_D-RAG\drag-lint-project.json "checkInit": {"callees": {"<Name>": "sets" or "reads"}}' + sLineBreak +
      'M|C:\src\UnitB.pas|16|3|use in UnitB.Go: MAY-BE-UNSET [unknown-callee]' + sLineBreak;
    Expect(lGot, lWant, 'UNKNOWN-CALLEE lines');
    Check(Pos('checkInit', lGot) > 0, 'UNKNOWN-CALLEE carries the callee hint');

    { engine error: one title with the first output line }
    lGot:= Render(CheckInitMessages(Load('err.txt'), 2));
    Expect(lGot, 'T||0|0|check-init failed (exit 2): ERROR: check-init: --at names no variable or field' + sLineBreak, 'error line');
    lGot:= Render(CheckInitMessages('', 2));
    Expect(lGot, 'T||0|0|check-init failed (exit 2): no output' + sLineBreak, 'error without output');
    lGot:= Render(CheckInitMessages('not json', 1));
    Expect(lGot, 'T||0|0|check-init failed (exit 1): not json' + sLineBreak, 'exit 1 without a JSON answer');
  except
    on E: Exception do begin Inc(GFail); Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message); end;
  end;
  Writeln(GPass, ' passed, ', GFail, ' failed');
  if GFail > 0 then ExitCode:= 1;
end.
"@
[IO.File]::WriteAllText((Join-Path $WorkDir 'CheckInitMenuCheck.dpr'), ($dpr -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
$bat = Join-Path $WorkDir 'build.bat'
$lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $WorkDir),
  ('dcc64 -B -NSSystem;Winapi;Vcl -E"{0}" -N0"{0}\dcu" CheckInitMenuCheck.dpr' -f $WorkDir), 'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$buildLog = Join-Path $WorkDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $buildLog -NoNewWindow -Wait -PassThru; $null = $null.Handle
$buildOut = [IO.File]::ReadAllText($buildLog)
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FAIL: headless check did not compile' -ForegroundColor Red
  ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
  exit 1
}
$out = & { $ErrorActionPreference = 'Continue'; & (Join-Path $WorkDir 'CheckInitMenuCheck.exe') 2>&1 | ForEach-Object { "$_" } } | Out-String
$rc = $LASTEXITCODE
Write-Host $out.TrimEnd()
if ($rc -ne 0) { Bad "headless check exit $rc" }
if ($out -notmatch '(\d+) passed, 0 failed') { Bad 'no pass/fail summary from the headless check' }

# ---- registry entry: FULL ide-menu path + editor right-click caption ----
$entry = Get-Content (Join-Path $repo 'features\entries\check-init.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ }
$menu = @($entry.surfaces | Where-Object type -eq 'ide-menu' | ForEach-Object { $_.path })
$ctx  = @($entry.surfaces | Where-Object { ($_.type -eq 'ide-context') -and ($_.host -eq 'Editor') } | ForEach-Object { $_.caption })
if ($menu -contains "drag-lint > Analyze > $caption") { Ok 'entry: ide-menu path' } else { Bad "entry lacks ide-menu path 'drag-lint > Analyze > $caption' (has: $($menu -join '; '))" }
if ($ctx -contains "drag-lint > $caption") { Ok 'entry: ide-context caption' } else { Bad "entry lacks ide-context caption 'drag-lint > $caption' (has: $($ctx -join '; '))" }

# ---- 5. live leg: the built command line against a real 1.52 engine ----
if ($Engine) {
  $fx = Join-Path $WorkDir 'live'
  New-Item -ItemType Directory -Force $fx | Out-Null
  $unitSrc = "unit HbCfg;`r`n`r`ninterface`r`n`r`nvar`r`n  GCount: Integer;`r`n`r`nprocedure Bump;`r`n`r`nimplementation`r`n`r`nprocedure Bump;`r`nbegin`r`n  GCount:= GCount + 1;`r`nend;`r`n`r`ninitialization`r`n  GCount:= 1;`r`nend.`r`n"
  $progSrc = "program HbLive;`r`n`r`nuses`r`n  HbCfg in 'HbCfg.pas';`r`n`r`nbegin`r`n  Bump;`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $fx 'HbCfg.pas'), $unitSrc, [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $fx 'HbLive.dpr'), $progSrc, [Text.Encoding]::ASCII)
  $liveDb = Join-Path $WorkDir 'live.sqlite'
  $null = & { $ErrorActionPreference = 'Continue'; & $Engine index $fx --db $liveDb 2>&1 | ForEach-Object { "$_" } }
  $unitPath = Join-Path $fx 'HbCfg.pas'
  $checker = Join-Path $WorkDir 'CheckInitMenuCheck.exe'
  $cmd = (& $checker cmdline $Engine $unitPath $liveDb 14 12 | Out-String).Trim()
  Write-Host "live command: $cmd"
  $liveOut = Join-Path $WorkDir 'live-out.txt'
  $liveExit = (Start-Process cmd.exe -ArgumentList '/c', "`"$cmd`"" -RedirectStandardOutput $liveOut -NoNewWindow -Wait -PassThru).ExitCode
  Write-Host '--- raw engine output ---'; Write-Host ([IO.File]::ReadAllText($liveOut)).TrimEnd()
  $lines = @(& $checker parse $liveOut $liveExit)
  Write-Host '--- messages ---'; $lines | ForEach-Object { Write-Host $_ }
  if ($lines.Count -ge 1 -and $lines[0] -clike 'T||0|0|check-init HbCfg.GCount: SET*') { Ok 'live: title' } else { Bad "live: title is '$($lines[0])' (exit $liveExit)" }
  if (@($lines | Where-Object { $_ -like "M|$unitPath|14|12|use in *: SET*" }).Count -eq 1) { Ok 'live: use line at the caret' } else { Bad 'live: no use line at HbCfg.pas:14:12' }
} else { Write-Host 'skip: live leg (no -Engine)' }

if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
