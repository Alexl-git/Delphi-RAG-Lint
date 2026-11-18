<#
  run_v152_TTIDE_menu.ps1 -- the Field Repository submenu (lane TTIDE, TT migration M10-M11).

  WHAT IT COVERS.
    1. Headless (no ToolsAPI, console build of Cmd152 + Cmd.FieldRepo): the
       FULL menu tree has submenu "Field Repository" with all six items; the
       VISIBLE tree shows exactly the three whose engine verb / editor ships
       (Open editor, Refresh schema, FDMemTable from CSV) and hides the three
       whose verb has not shipped (ORM source, DataService units, Param Array).
       Positive control: the same table with every row switched on shows all six.
    2. FieldRepoCommandLine quotes exe and arguments and carries the verb.
    3. features\entries\field-repository.json registers the six FULL ide-menu
       paths.

  Usage: pwsh -File tests\plugin\run_v152_TTIDE_menu.ps1
#>
[CmdletBinding()]
param([string]$WorkDir = "$env:TEMP\drag-lint-v152-ttide-$PID")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$plug = Join-Path $repo 'src\delphi-plugin'
$fail = 0
function Bad([string]$m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail++ }
function Ok([string]$m)  { Write-Host "ok: $m" }

$shown  = @('Open Field Repository Editor...', 'Refresh Schema from Database...', 'FDMemTable from CSV...')
$hidden = @('Generate / Update ORM Source...', 'Generate DataService Units...', 'Param Array Assistant...')

$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force (Join-Path $WorkDir 'dcu') | Out-Null
$dpr = @"
program FieldRepoMenuCheck;
{`$APPTYPE CONSOLE}
uses
  System.SysUtils, Vcl.Menus,
  DragLint.Plugin.Cmd152 in '$plug\DragLint.Plugin.Cmd152.pas',
  DragLint.Plugin.Cmd.FieldRepo in '$plug\DragLint.Plugin.Cmd.FieldRepo.pas';

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

function Fixture: TMenuItem;
begin
  Result:= TMenuItem.Create(nil);
  AddItem(Result, 'Rename Symbol...', nil);
end;

var
  lTable, lMine: TArray<TCmd152Command>;
  lRoot: TMenuItem;
  lVisible, lFull: string;
  lCmd: TCmd152Command;
begin
  try
    lTable:= Cmd152Table;
    SetLength(lMine, 0);
    for lCmd in lTable do
      if lCmd.OwnerLane = 'TTIDE' then lMine:= lMine + [lCmd];
    Check(Length(lMine) = 6, 'six TTIDE rows, got ' + IntToStr(Length(lMine)));
    for lCmd in lMine do Check(lCmd.ParentPath = 'Field Repository', lCmd.Id + ' parent path');
    lRoot:= Fixture;
    try
      BuildCmd152Menu(lRoot, lMine, AddItem);
      lVisible:= DumpMenuTree(lRoot, True);
      lFull:= DumpMenuTree(lRoot, False);
      Writeln('--- visible ---'); Write(lVisible); Writeln('--- full ---'); Write(lFull); Writeln('--- end ---');
    finally
      lRoot.Free;
    end;
    Check(Pos('Field Repository', lFull) > 0, 'submenu in the full tree');
    for lCmd in lMine do Check(Pos(lCmd.Caption, lFull) > 0, lCmd.Caption + ' in the full tree');
    Check(Pos('Open Field Repository Editor...', lVisible) > 0, 'Open editor visible');
    Check(Pos('Refresh Schema from Database...', lVisible) > 0, 'Refresh visible');
    Check(Pos('FDMemTable from CSV...', lVisible) > 0, 'FDMemTable visible');
    Check(Pos('Generate / Update ORM Source...', lVisible) = 0, 'ORM hidden');
    Check(Pos('Generate DataService Units...', lVisible) = 0, 'DataService hidden');
    Check(Pos('Param Array Assistant...', lVisible) = 0, 'Param Array hidden');
    { positive control: every row on shows all six }
    for var i:= 0 to High(lMine) do lMine[i].Visible:= True;
    lRoot:= Fixture;
    try
      BuildCmd152Menu(lRoot, lMine, AddItem);
      lVisible:= DumpMenuTree(lRoot, True);
    finally
      lRoot.Free;
    end;
    Check(Pos('Param Array Assistant...', lVisible) > 0, 'control: switched-on row shows');
    { command line }
    var s: string:= FieldRepoCommandLine('C:\x y\drag-lint.exe', 'refresh-schema', 'C:\p q\a.dproj', '--dry-run');
    Check(s = '"C:\x y\drag-lint.exe" repo refresh-schema --project "C:\p q\a.dproj" --dry-run', 'command line: ' + s);
    Check(FieldRepoCommandLine('e.exe', 'info', 'a.dproj', '') = '"e.exe" repo info --project "a.dproj"', 'command line without extra');
    { masked input: the VCL InputQuery masks the edit when the prompt starts with #31 }
    Check(MaskedPrompt('Pw:') = #31 + 'Pw:', 'MaskedPrompt prefixes #31');
  except
    on E: Exception do begin Inc(GFail); Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message); end;
  end;
  Writeln(GPass, ' passed, ', GFail, ' failed');
  if GFail > 0 then ExitCode:= 1;
end.
"@
[IO.File]::WriteAllText((Join-Path $WorkDir 'FieldRepoMenuCheck.dpr'), ($dpr -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
$bat = Join-Path $WorkDir 'build.bat'
$lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $WorkDir),
  ('dcc64 -B -NSSystem;Winapi;Vcl -E"{0}" -N0"{0}\dcu" FieldRepoMenuCheck.dpr' -f $WorkDir), 'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$buildLog = Join-Path $WorkDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $buildLog -NoNewWindow -Wait -PassThru
$buildOut = [IO.File]::ReadAllText($buildLog)
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FAIL: headless check did not compile' -ForegroundColor Red
  ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
  exit 1
}
$out = & (Join-Path $WorkDir 'FieldRepoMenuCheck.exe') 2>&1 | Out-String
$rc = $LASTEXITCODE
Write-Host $out.TrimEnd()
if ($rc -ne 0) { Bad "headless check exit $rc" }
if ($out -notmatch '(\d+) passed, 0 failed') { Bad 'no pass/fail summary from the headless check' }

# ---- registry entry: the six FULL ide-menu paths ----
$entry = Get-Content (Join-Path $repo 'features\entries\field-repository.json') -Raw | ConvertFrom-Json
$paths = @($entry.surfaces | Where-Object type -eq 'ide-menu' | ForEach-Object { $_.path })
foreach ($c in ($shown + $hidden)) {
  $want = "drag-lint > Field Repository > $c"
  if ($paths -notcontains $want) { Bad "entry lacks ide-menu path '$want'" }
}
if ($paths.Count -ge 6) { Ok "entry registers $($paths.Count) ide-menu paths" }

if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
