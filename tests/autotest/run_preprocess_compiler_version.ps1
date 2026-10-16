<#
  run_preprocess_compiler_version.ps1 -- the index preprocesses for the PROJECT'S
  Delphi, and {$IF CompilerVersion ...} is evaluated at all.

  THE PROBLEMS (evaluation on ProjectA, a Delphi 10.3 project, 2026-09-28):
    * the built-in defines were pinned to Delphi 13 -- VER370,
      compiler_version_37 -- whatever the project is built with, so a
      {$IFDEF VER330} branch of 10.3 code was never indexed;
    * CompilerVersion and RTLVersion were never given a VALUE. The evaluator
      reads an unknown identifier as False, so EVERY {$IF CompilerVersion >= N}
      took its ELSE branch, on every compiler.

  THE FIX (extractor 1.20.0-alpha). The built-ins say VER<N>0 /
  compiler_version_<N> for the target Delphi, and every profile carries
  CompilerVersion and RTLVersion as numbers. A non-default version joins the
  indexer fingerprint (`cv=`), so switching compilers re-parses.

  WHERE THE TARGET COMES FROM (2026-10-07). It used to be the $BDS environment
  variable -- configuration outside the project. Now: --delphi <bds>, else the
  .dproj's <ProjectVersion>, else (no project) the newest Studio installed.
  $BDS is NOT read. This suite pins all of that:
    T1/T2  --delphi 20.0 / 37.0 on a folder index (no project: the Studio need
           not be installed, only the defines follow the target);
    T3     a .dproj with ProjectVersion 18.8 is analysed as Delphi 10.3 even
           with BDS pointing at a Delphi 13 root -- when BDS 20.0 is installed;
           otherwise it falls back to the default Studio with a note naming
           --delphi (merge 2026-10-15: upstream's fixtures carry versions this
           machine lacks, and refusing broke them);
    T4     an unmapped ProjectVersion falls back the same way, the note naming
           the version and --delphi;
    T5     an EXPLICIT --delphi naming a Studio that is not installed still
           exits 2 on a project -- the user's own statement is never second-guessed.

  Usage: pwsh -File tests/autotest/run_preprocess_compiler_version.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-compiler-version-$PID"
)
$savedBds = $env:BDS
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory (Join-Path $WorkDir 'src') | Out-Null
$env:BDS = $null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $WorkDir 'src\uCv.pas') @'
unit uCv;

interface

{$IF CompilerVersion >= 30}
procedure ModernApi;
{$ELSE}
procedure AncientApi;
{$IFEND}
{$IFDEF VER330}
procedure RioOnly;
{$ENDIF}
{$IFDEF VER370}
procedure FlorenceOnly;
{$ENDIF}

implementation

end.
'@

function Probe([string]$Db) {
  $has = @{}
  foreach ($n in @('ModernApi', 'AncientApi', 'RioOnly', 'FlorenceOnly')) {
    & $Exe query --name $n --db $Db --exact 2>&1 | Out-Null
    $has[$n] = ($LASTEXITCODE -eq 0)
  }
  return $has
}
function IndexFolder([string]$Delphi, [string]$Name) {
  $db = Join-Path $WorkDir "$Name.sqlite"
  $out = (@(& $Exe index (Join-Path $WorkDir 'src') --db $db --quiet --delphi $Delphi 2>&1) | ForEach-Object { "$_" }) -join "`n"
  return @{ Code = $LASTEXITCODE; Out = $out; Has = (Probe $db); Db = $db }
}

Write-Host 'T1 -- --delphi 20.0 (Delphi 10.3)' -ForegroundColor Cyan
$rio = IndexFolder '20.0' 'rio'
Check 'T1 index exits 0' ($rio.Code -eq 0) $rio.Out
Check 'T1 {$IF CompilerVersion >= 30} takes the THEN branch (ModernApi)' $rio.Has.ModernApi ''
Check 'T1 ... and not the ELSE branch (AncientApi absent)' (-not $rio.Has.AncientApi) ''
Check 'T1 VER330 is defined for 10.3 (RioOnly)' $rio.Has.RioOnly ''
Check 'T1 VER370 is NOT defined for 10.3 (FlorenceOnly absent)' (-not $rio.Has.FlorenceOnly) ''

Write-Host ''
Write-Host 'T2 -- --delphi 37.0 (Delphi 13)' -ForegroundColor Cyan
$flo = IndexFolder '37.0' 'florence'
Check 'T2 index exits 0' ($flo.Code -eq 0) $flo.Out
Check 'T2 CompilerVersion is 37 -> ModernApi' ($flo.Has.ModernApi -and -not $flo.Has.AncientApi) ''
Check 'T2 VER370, not VER330, for 13' ($flo.Has.FlorenceOnly -and -not $flo.Has.RioOnly) ''

$py = Join-Path $WorkDir 'fp.py'
Write-Ascii $py @'
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute("select value from schema_meta where key='indexer_fingerprint'").fetchone()[0])
'@
$fpRio = ((python $py $rio.Db) -join '').Trim()
$fpFlo = ((python $py $flo.Db) -join '').Trim()
Check 'T1 a 10.3 index is stamped cv=33' ($fpRio -match ';cv=33$') $fpRio
Check 'T2 a Delphi 13 index keeps the stamp it always had (no cv= limb)' ($fpFlo -notmatch 'cv=') $fpFlo

# --- T3: the .dproj decides, $BDS does not -----------------------------------------
Write-Host ''
Write-Host 'T3 -- .dproj ProjectVersion 18.8, BDS pointing at a Delphi 13 root' -ForegroundColor Cyan
$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory $proj | Out-Null
Write-Ascii (Join-Path $proj 'P.dpr') "program P;`n`nuses`n  uCv in '..\src\uCv.pas';`n`nbegin`nend.`n"
Write-Ascii (Join-Path $proj 'P.dproj') "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>18.8</ProjectVersion>`n    <MainSource>P.dpr</MainSource>`n  </PropertyGroup>`n</Project>`n"
$have20 = Test-Path 'HKCU:\Software\Embarcadero\BDS\20.0'
if ($have20) { $have20 = [bool](Get-ItemProperty 'HKCU:\Software\Embarcadero\BDS\20.0' -ErrorAction SilentlyContinue).RootDir }
$env:BDS = 'C:\FakeEmbarcadero\Studio\37.0'
$db3 = Join-Path $WorkDir 'proj.sqlite'
$o3 = (@(& $Exe index --project (Join-Path $proj 'P.dproj') --platform win32 --db $db3 2>&1) | ForEach-Object { "$_" }) -join "`n"
$c3 = $LASTEXITCODE
$env:BDS = $null
if ($have20) {
  Check 'T3 index exits 0 (BDS 20.0 installed here)' ($c3 -eq 0) $o3
  $h3 = Probe $db3
  Check 'T3 analysed as 10.3: VER330 (RioOnly), not VER370' ($h3.RioOnly -and -not $h3.FlorenceOnly) ''
  $fp3 = ((python $py $db3) -join '').Trim()
  Check 'T3 stamped cv=33 -- BDS=...\37.0 was ignored' ($fp3 -match ';cv=33$') $fp3
} else {
  Check 'T3 BDS 20.0 is not installed here: falls back, exit 0' ($c3 -eq 0) $o3
  Check 'T3 ... with a note naming --delphi' (($o3 -match 'not installed') -and ($o3 -match '--delphi')) $o3
}

# --- T4: unmapped version -------------------------------------------------------------
Write-Host ''
Write-Host 'T4 -- unmapped ProjectVersion' -ForegroundColor Cyan
Write-Ascii (Join-Path $proj 'P.dproj') "<Project><PropertyGroup><ProjectVersion>99.9</ProjectVersion></PropertyGroup></Project>`n"
$o4 = (@(& $Exe index --project (Join-Path $proj 'P.dproj') --platform win32 --db (Join-Path $WorkDir 'p4.sqlite') 2>&1) | ForEach-Object { "$_" }) -join "`n"
Check 'T4 falls back to the default Studio, exit 0' ($LASTEXITCODE -eq 0) $o4
Check 'T4 the note names the version and --delphi' (($o4 -match '99\.9') -and ($o4 -match '--delphi')) $o4

# --- T5: an explicit --delphi that is not installed still refuses --------------------
Write-Host ''
Write-Host 'T5 -- explicit --delphi naming a Studio not installed' -ForegroundColor Cyan
$o5 = (@(& $Exe index --project (Join-Path $proj 'P.dproj') --platform win32 --delphi 98.0 --db (Join-Path $WorkDir 'p5.sqlite') 2>&1) | ForEach-Object { "$_" }) -join "`n"
Check 'T5 exits 2' ($LASTEXITCODE -eq 2) $o5

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  $env:BDS = $savedBds
  foreach ($d in @("$env:TEMP\drag-lint-compiler-version-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
