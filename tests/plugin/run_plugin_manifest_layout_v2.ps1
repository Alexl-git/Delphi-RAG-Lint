<#
  run_plugin_manifest_layout_v2.ps1 -- installed layout v2 phase 3 (P2): the IDE plugin finds
  drag-lint.json through the engine's resolver (TInstalledLayout), not by building
  '<dir>\drag-lint.json' itself.

  1. Builds and runs ManifestPathsTests.dpr over src\delphi-plugin\DragLint.Plugin.ManifestPaths.pas.
  2. POSITIVE CONTROL: builds the same test over a stub of that unit that answers the pre-phase-3
     way (exe/BPL dir only, raw outDir). The test MUST fail there, or it cannot tell the two apart.
  3. Source anchors: every plugin manifest lookup goes through the unit, and no lookup in
     DbResolver / OptionsFrames still appends 'drag-lint.json' to a folder by hand.
  The IDE itself reading a roaming manifest is live proof owed (VM-TEST-CHECKLIST section L).

  RED BASELINE, measured 2026-11-08 (lane 148-XP3): the stub run is the pre-fix behaviour
  (cases 3a 3b 5 6b 7a 8b fail) and the anchors fail on the lane base 6fac00822.

  Usage: pwsh -File tests\plugin\run_plugin_manifest_layout_v2.ps1 [-SrcDir <src\delphi-plugin>]
#>
[CmdletBinding()]
param(
  [string]$SrcDir  = "$PSScriptRoot\..\..\src\delphi-plugin",
  [string]$WorkDir = "$env:TEMP\drag-lint-manifestpaths-build-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d)
  if (-not $ok) { $script:Failed = $true }
}

$SrcDir  = (Resolve-Path $SrcDir).Path
$Repo    = (Resolve-Path "$PSScriptRoot\..\..").Path
$Dpr     = Join-Path $Repo 'tests\ManifestPathsTests.dpr'
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host "FATAL: rsvars not found: $rs" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
[void][IO.Directory]::CreateDirectory($WorkDir)

# Builds the test with $UnitDir first on the unit path; returns the run's exit code.
function Invoke-Test([string]$Tag, [string]$UnitDir) {
  $out = Join-Path $WorkDir $Tag
  $dcu = Join-Path $out 'dcu'
  [void][IO.Directory]::CreateDirectory($dcu)
  $u = '{0};{1};{2}' -f $UnitDir, (Join-Path $Repo 'src\index'), (Join-Path $Repo 'src\core')
  $bat = Join-Path $out 'build.bat'
  $lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f (Split-Path $Dpr -Parent)),
             ('dcc64 -B -Q -E"{0}" -N0"{1}" -U"{2}" ManifestPathsTests.dpr' -f $out, $dcu, $u),
             'echo BUILD_EXITCODE=%ERRORLEVEL%')
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $log = Join-Path $out 'build.log'
  [void](Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log `
          -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru)
  $b = Get-Content $log -Raw
  if ($b -notmatch 'BUILD_EXITCODE=0') { Write-Host $b; Write-Host "FATAL: $Tag compile failed" -ForegroundColor Red; exit 2 }
  $r = & (Join-Path $out 'ManifestPathsTests.exe') 2>&1 | Out-String
  $rc = $LASTEXITCODE
  Write-Host $r.TrimEnd()
  return $rc
}

Write-Host '== 1. the unit =='
$rc = Invoke-Test 'real' $SrcDir
Check 'ManifestPathsTests over the real unit' ($rc -eq 0) "exit $rc"

Write-Host '== 2. positive control: the pre-phase-3 answers must FAIL =='
$stubDir = Join-Path $WorkDir 'stub'
[void][IO.Directory]::CreateDirectory($stubDir)
$real = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.ManifestPaths.pas'))
$impl = $real.IndexOf("`r`nimplementation`r`n")
if ($impl -lt 0) { Write-Host 'FATAL: no implementation section' -ForegroundColor Red; exit 2 }
$stubBody = @'

implementation

function PluginManifestIn(const ADir: string): TManifestLocation;
begin
  Result:= Default(TManifestLocation);
  Result.Path   := TPath.Combine(ADir, 'drag-lint.json');
  Result.RootDir:= ADir;
  Result.Origin := moExeDir;
  Result.Exists := TFile.Exists(Result.Path);
end;

function PluginManifestCandidates(const AEngineExe, ABplDir: string): TArray<string>;
begin
  Result:= nil;
  if AEngineExe <> '' then Result:= Result + [TPath.Combine(ExtractFilePath(AEngineExe), 'drag-lint.json')];
  Result:= Result + [ExtractFilePath(ABplDir) + 'drag-lint.json'];
end;

function PluginLibraryOutDir(const ARawOutDir, AManifestPath: string): string;
begin
  Result:= ARawOutDir;
end;

function PluginManifestWriteTarget(const AEngineDir: string): string;
begin
  Result:= AEngineDir + 'drag-lint.json';
end;

end.
'@
$stub = $real.Substring(0, $impl) + ($stubBody -replace "`r?`n", "`r`n")
[IO.File]::WriteAllText((Join-Path $stubDir 'DragLint.Plugin.ManifestPaths.pas'), $stub, [Text.Encoding]::ASCII)
$rcStub = Invoke-Test 'stub' $stubDir
Check 'positive control: the stub (old behaviour) fails the test' ($rcStub -ne 0) "exit $rcStub"

Write-Host '== 3. source anchors =='
$db = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.DbResolver.pas'))
$of = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.OptionsFrames.pas'))
$dpk = [IO.File]::ReadAllText((Join-Path $SrcDir 'dclDragLintWizard.dpk'))
Check 'ManifestPathBesideEngine asks the resolver' ($db -match '(?s)function ManifestPathBesideEngine: string;\s+begin\s+Result:= PluginManifestIn\(')
Check 'TryLoadManifest parses against the resolver RootDir' ($db -match '(?s)function TryLoadManifest.{0,900}?PluginManifestIn\(.{0,600}?ParseText\(Content, Located\.RootDir\)')
Check 'ManifestLibraryDbFor probes PluginManifestCandidates' ($db -match '(?s)function ManifestLibraryDbFor.{0,2500}?Manifests:= PluginManifestCandidates\(')
Check 'ManifestLibraryDbFor reads outDir like the engine' ($db -match '(?s)function ManifestLibraryDbFor.{0,4000}?OutDir:= PluginLibraryOutDir\(OutDir, MPath\)')
Check 'ManifestPathForWrite asks the write target' ($of -match '(?s)function TDLLinterOptionsFrame\.ManifestPathForWrite.{0,2500}?Result:= PluginManifestWriteTarget\(ExeDir\)')
Check 'no hand-built drag-lint.json path left in DbResolver' ($db -notmatch "\+\s*'drag-lint\.json'|,\s*'drag-lint\.json'\)")
Check 'no hand-built drag-lint.json path left in OptionsFrames' ($of -notmatch "ExeDir \+ 'drag-lint\.json'")
Check 'the package contains the unit' ($dpk -match 'DragLint\.Plugin\.ManifestPaths in ''DragLint\.Plugin\.ManifestPaths\.pas''')

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
