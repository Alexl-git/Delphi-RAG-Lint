<#
  run_plugin_repo_manifest.ps1 -- the IDE plugin resolves a CONFIGURED
  repository's indexes (#31, 2026-10-15).

  WHY. The plugin found indexes only through the manifest beside its BPL and
  <projdir>\_D-RAG\<project>.sqlite. A repository configured with `drag-lint
  init` keeps them in <root>\_D-RAG\<name>.sqlite, so the IDE found nothing
  there. And had it loaded that config through the engine's own
  ManifestFromRepoConfig, the Library section would have pointed beside
  ParamStr(0) -- inside the IDE, that is bds.exe -- for the newest Studio, not
  beside the engine for the project's Delphi.

  A design-time BPL cannot run headless, so this compiles a console probe
  against the SAME units the plugin's DragLint.Plugin.DbResolver.TryLoadManifest
  calls (TRepoConfigIO.TryLoad, RepoBdsFor, ManifestFromRepoConfigAt,
  ResolveProjectDb) and checks what they answer.

  Checks (printed by the probe):
    C1  the repository config is found above the project file
    C2  the project resolves to <root>\_D-RAG\<name>.sqlite
    C3  the Library section lives beside the ENGINE given, for the project's Delphi
    C4  RepoBdsFor reads the project's "delphi"
    C5  a project outside any configured repository finds no config (the plugin
        then keeps the manifest beside its BPL, exactly as before)

  Needs RAD Studio (dcc64); SKIP 77 without it. Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$WorkDir = "C:\TEMP\draglint_plugin_repo_$PID")
try {
$ErrorActionPreference = 'Stop'
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rsvars)) { Write-Host 'SKIP: RAD Studio 37.0 not installed (rsvars.bat missing)'; exit 77 }

$src = (Resolve-Path "$PSScriptRoot\..\..\src").Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$root   = Join-Path $WorkDir 'repo'
$outer  = Join-Path $WorkDir 'loose'
$engine = Join-Path $WorkDir 'engine'
$build  = Join-Path $WorkDir 'build'
New-Item -ItemType Directory -Force (Join-Path $root 'App'), (Join-Path $root '_D-RAG'), (Join-Path $outer 'Other'), $engine, (Join-Path $build 'dcu') | Out-Null

Write-Ascii (Join-Path $root 'App\App.dpr') "program App;`n`nbegin`nend.`n"
Write-Ascii (Join-Path $root 'App\App.dproj') "<Project><PropertyGroup><ProjectVersion>18.8</ProjectVersion><MainSource>App.dpr</MainSource></PropertyGroup></Project>`n"
Write-Ascii (Join-Path $root '_D-RAG\config.json') @'
{
  "version": 1,
  "projects": [
    { "name": "App", "dproj": "App\\App.dproj", "platform": "Win32", "delphi": "20.0" }
  ],
  "exclude": []
}
'@
Write-Ascii (Join-Path $outer 'Other\Other.dproj') "<Project><PropertyGroup><ProjectVersion>18.8</ProjectVersion></PropertyGroup></Project>`n"

Write-Ascii (Join-Path $build 'RepoManifestProbe.dpr') @'
program RepoManifestProbe;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DRagLint.Index.Manifest,
  DRagLint.Index.RepoConfig;

var
  Fails: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string);
begin
  if AOk then Writeln('[PASS] ', AName)
  else
  begin
    Writeln('[FAIL] ', AName, ' -- ', ADetail);
    Inc(Fails);
  end;
end;

var
  Root, Engine, Dproj, Outside: string;
  Cfg, Cfg2   : TRepoConfig;
  Err, Err2   : string;
  M           : TIndexManifest;
  Db, LibDb   : string;
  Claimants   : TArray<string>;
  Bds         : string;
begin
  Root   := ParamStr(1);
  Engine := ParamStr(2);
  Dproj  := TPath.Combine(Root, 'App\App.dproj');
  Outside:= ParamStr(3);
  Check('C1 the repository config is found above the project file', TRepoConfigIO.TryLoad(Dproj, Cfg, Err), Err);
  Bds:= RepoBdsFor(Cfg, Dproj);
  Check('C4 RepoBdsFor reads the project''s "delphi"', Bds = '20.0', 'got ' + Bds);
  M:= ManifestFromRepoConfigAt(Cfg, Engine, Bds);
  Check('C2 the project resolves to <root>\_D-RAG\App.sqlite',
    (ResolveProjectDb(M, Dproj, Db, Claimants) = pdmUnique) and SameText(Db, TPath.Combine(Root, '_D-RAG\App.sqlite')), 'got ' + Db);
  LibDb:= '';
  for var Sec in M.Sections do
    if SameText(Sec.Source, 'registry-libraries') then LibDb:= Sec.Db;
  Check('C3 the Library section lives beside the ENGINE, for the project''s Delphi',
    SameText(LibDb, TPath.Combine(Engine, 'library\20.0\library-{platform}.sqlite')), 'got ' + LibDb);
  Check('C5 a project outside any configured repository finds no config',
    (not TRepoConfigIO.TryLoad(Outside, Cfg2, Err2)) and (Err2 = ''), Err2);
  if Fails = 0 then Writeln('OK') else Writeln('FAILED ', Fails);
end.
'@

$units = @('index', 'core', 'project', 'lint', 'storage', 'parser', 'preprocess', 'config', 'query', 'doc', 'analysis', 'workspace') |
  ForEach-Object { Join-Path $src $_ } | Where-Object { Test-Path $_ }
$bat = Join-Path $build 'build.bat'
Write-Ascii $bat @"
@echo off
call "$rsvars" >NUL
dcc64 -Q -NU"$build\dcu" -E"$build" -U"$($units -join ';')" "$build\RepoManifestProbe.dpr"
"@
$log = & cmd /c "`"$bat`"" 2>&1 | Out-String
$probe = Join-Path $build 'RepoManifestProbe.exe'
if (-not (Test-Path $probe)) { Write-Host '[FAIL] the probe compiles against the plugin''s resolver units' -ForegroundColor Red; Write-Host $log; exit 1 }
Write-Host '[PASS] the probe compiles against the plugin''s resolver units' -ForegroundColor Green

$out = & $probe $root $engine (Join-Path $outer 'Other\Other.dproj') 2>&1 | Out-String
$out.TrimEnd() -split "`r?`n" | ForEach-Object {
  if ($_ -like '[PASS]*') { Write-Host $_ -ForegroundColor Green } elseif ($_ -like '[FAIL]*') { Write-Host $_ -ForegroundColor Red } else { Write-Host $_ }
}
if ($out -match '(?m)^OK\s*$') { Write-Host 'PASS' -ForegroundColor Green; exit 0 } else { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
}
finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
