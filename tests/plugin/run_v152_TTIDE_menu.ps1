<#
  run_v152_TTIDE_menu.ps1 -- the Field Repository submenu (lane TTIDE, TT migration M10-M11).

  WHAT IT COVERS.
    1. Headless (no ToolsAPI, console build of Cmd152 + Cmd.FieldRepo): the
       FULL menu tree has submenu "Field Repository" with all six items; the
       VISIBLE tree shows all six (1.52 BK-TTFINISH / B33: the ORM, DataService and
       Param Array rows are unhidden now that their verbs ship; golden -RequireForm passes).
       Positive control: the same table with every row switched off shows none.
     1b. FieldRepoGenArgs / FieldRepoRunSummary (pure helpers of the three new rows).
    2. FieldRepoCommandLine quotes exe and arguments and carries the verb.
    3. features\entries\field-repository.json registers the six FULL ide-menu
       paths.

  Usage: pwsh -File tests\plugin\run_v152_TTIDE_menu.ps1
#>
[CmdletBinding()]
param([string]$WorkDir = "$env:TEMP\drag-lint-v152-ttide-$PID")
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot '..\autotest\lib\WorkDirCleanup.ps1')
try {
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$plug = Join-Path $repo 'src\delphi-plugin'
$fail = 0
function Bad([string]$m) { Write-Host "FAIL: $m" -ForegroundColor Red; $script:fail++ }
function Ok([string]$m)  { Write-Host "ok: $m" }

$shown  = @('Open Field Repository Editor...', 'Refresh Schema from Database...', 'FDMemTable from CSV...',
            'Generate / Update ORM Source...', 'Generate DataService Units...', 'Param Array Assistant...')
$hidden = @()

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
    { 1.56 FRAME-2: + field-repository-10-grid-copy (Copy Grid Columns..., visible) -> ten rows }
    Check(Length(lMine) = 10, 'ten rows (six TTIDE, three TT-DIALOG, one 1.56 grid-copy), got ' + IntToStr(Length(lMine)));
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
    Check(Pos('Generate / Update ORM Source...', lVisible) > 0, 'ORM visible');
    Check(Pos('Generate DataService Units...', lVisible) > 0, 'DataService visible');
    Check(Pos('Param Array Assistant...', lVisible) > 0, 'Param Array visible');
    { positive control: every row off shows none }
    for var i:= 0 to High(lMine) do lMine[i].Visible:= False;
    lRoot:= Fixture;
    try
      BuildCmd152Menu(lRoot, lMine, AddItem);
      lVisible:= DumpMenuTree(lRoot, True);
    finally
      lRoot.Free;
    end;
    Check(Pos('Param Array Assistant...', lVisible) = 0, 'control: switched-off row hidden');
    { 1b: generator arguments and the dry-run summary }
    Check(FieldRepoGenArgs('C:\c d', '', '', '', False) = '--code-dir "C:\c d"', 'gen args code dir: ' + FieldRepoGenArgs('C:\c d', '', '', '', False));
    Check(FieldRepoGenArgs('', 's', 'c', 'A,B', True) = '--server-dir "s" --client-dir "c" --table "A,B" --apply', 'gen args all: ' + FieldRepoGenArgs('', 's', 'c', 'A,B', True));
    Check(FieldRepoRunSummary('changed x.pas'#13#10'--- a'#13#10'+++ b'#13#10'@@ line 3 @@'#13#10'-old'#13#10'+new'#13#10'repo update-orm: 0 new, 1 changed', 10) =
      'changed x.pas'#13#10'repo update-orm: 0 new, 1 changed', 'summary drops diff lines');
    Check(Pos('more lines', FieldRepoRunSummary('a'#13#10'b'#13#10'c', 2)) > 0, 'summary caps the line count');
    { command line }
    var s: string:= FieldRepoCommandLine('C:\x y\drag-lint.exe', 'refresh-schema', 'C:\p q\a.dproj', '--dry-run');  // # exe-freshness: absent (a fake path the command line only quotes)
    Check(s = '"C:\x y\drag-lint.exe" repo refresh-schema --project "C:\p q\a.dproj" --dry-run', 'command line: ' + s);  // # exe-freshness: absent (a fake path the command line only quotes)
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
  ('dcc64 -B -NSSystem;Winapi;Vcl -E"{0}" -N0"{0}\dcu" -U"{1};{1}\..\core;{1}\..\lint;{1}\..\project;{1}\..\sql" FieldRepoMenuCheck.dpr' -f $WorkDir, $plug), 'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$buildLog = Join-Path $WorkDir 'build.log'
$null = Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $buildLog -NoNewWindow -Wait -PassThru; $null = $null.Handle
$buildOut = [IO.File]::ReadAllText($buildLog)
if ($buildOut -notmatch 'BUILD_EXITCODE=0') {
  Write-Host 'FAIL: headless check did not compile' -ForegroundColor Red
  ($buildOut -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
  exit 1
}
$out = & { $ErrorActionPreference = 'Continue'; & (Join-Path $WorkDir 'FieldRepoMenuCheck.exe') 2>&1 | ForEach-Object { "$_" } } | Out-String
$rc = $LASTEXITCODE
Write-Host $out.TrimEnd()
if ($rc -ne 0) { Bad "headless check exit $rc" }
if ($out -notmatch '(\d+) passed, 0 failed') { Bad 'no pass/fail summary from the headless check' }

# ---- registry entry: the six FULL ide-menu paths ----
$entry = Get-Content (Join-Path $repo 'features\entries\field-repository.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ }
$paths = @($entry.surfaces | Where-Object type -eq 'ide-menu' | ForEach-Object { $_.path })
foreach ($c in ($shown + $hidden)) {
  $want = "drag-lint > Field Repository > $c"
  if ($paths -notcontains $want) { Bad "entry lacks ide-menu path '$want'" }
}
if ($paths.Count -ge 6) { Ok "entry registers $($paths.Count) ide-menu paths" }

if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
