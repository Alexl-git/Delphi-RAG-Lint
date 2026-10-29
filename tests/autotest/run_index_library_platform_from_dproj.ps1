<#
  run_index_library_platform_from_dproj.ps1 -- library-first resolve, lane lf-ready (plan s.2.1, s.1.3):
  the platform library a project section binds against is chosen PROJECT-authoritatively
  (--platform, else the project DB's own plat= stamp, else the .dproj's <Platform>), never from the CWD
  or the manifest default.

  Fixture: manifest default platform Win32 with BOTH library-Win32 and library-Win64 present; a project
  whose .dproj says Win64; the run starts from a NEUTRAL CWD.
    1. index --project App.dproj (no --platform)  -> opens library-Win64   (RED today: library-Win32)
    2. the second run (the project DB now carries plat=win64) -> still library-Win64
    3. an explicit --platform Win32 wins over the dproj -> library-Win32 (control: the choice is live)
    2b. index --all --dry-run prints "library: <path> (Win64, <state>)" for the opted-in project section
  (3 runs last: it re-stamps the project DB as Win32.)  Run from C:\TEMP.
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
function Write-Ascii([string]$Path,[string]$Body){ [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
if (-not $Exe) {
  $Exe = Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe' }
}
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$fixDir = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
$root = Join-Path C:\TEMP "draglint_libplat_$PID"
try {
  if (Test-Path $root) { [IO.Directory]::Delete($root, $true) }
  $eng = Join-Path $root 'eng'; $out = Join-Path $root 'out'; $lib = Join-Path $root 'lib'; $app = Join-Path $root 'app'
  New-Item -ItemType Directory -Path $eng,$out,$lib,$app | Out-Null
  Copy-Item $exeSrc (Join-Path $eng 'drag-lint.exe') -Force
  Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
  if (Test-Path (Join-Path $exeSrcDir 'rules')) { Copy-Item (Join-Path $exeSrcDir 'rules') (Join-Path $eng 'rules') -Recurse -Force }
  $exe = Join-Path $eng 'drag-lint.exe'
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $lib -Force
  Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $app -Force
  Write-Ascii (Join-Path $app 'App.dpr') "program App;`n`nuses`n  xt_app in 'xt_app.pas',`n  xt_app2 in 'xt_app2.pas';`n`nbegin`nend.`n"
  Write-Ascii (Join-Path $app 'App.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>App.dpr</MainSource>
    <Platform Condition="'$(Platform)'==''">Win64</Platform>
  </PropertyGroup>
</Project>
'@
  $o = $out.Replace('\','/')
  Write-Ascii (Join-Path $eng 'drag-lint.json') @"
{
  "settings": { "defaultPlatform": "Win32", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [
    { "name": "Library", "db": "library-{platform}.sqlite", "source": "registry-libraries", "platforms": ["Win32", "Win64"] },
    { "name": "ProjOn", "db": "projon.sqlite", "include": ["$($app.Replace('\','/'))/App.dproj"], "libraryResolve": true }
  ] }
}
"@
  $projDb = Join-Path $out 'projon.sqlite'
  Push-Location C:\TEMP
  try {
    & $exe index $lib --db (Join-Path $out 'library-Win64.sqlite') 2>&1 | Out-Null
    & $exe index $lib --db (Join-Path $out 'library-Win32.sqlite') --platform win32 2>&1 | Out-Null
    Check 'both library fixtures indexed' ((Test-Path (Join-Path $out 'library-Win64.sqlite')) -and (Test-Path (Join-Path $out 'library-Win32.sqlite')))

    $txt = (& $exe index --project (Join-Path $app 'App.dproj') 2>&1 | Out-String)
    Check '1. dproj says Win64 -> library-Win64 is opened' ($txt -match '\+ library-db .*library-Win64\.sqlite') $txt
    Check '1. the CWD/manifest-default library-Win32 is NOT opened' ($txt -notmatch '\+ library-db .*library-Win32\.sqlite') $txt

    $txt = (& $exe index --project (Join-Path $app 'App.dproj') --resolve-only 2>&1 | Out-String)
    Check '2. second run (DB stamp plat=win64) -> library-Win64' ($txt -match '\+ library-db .*library-Win64\.sqlite') $txt

    $txt = (& $exe index --all --dry-run --only ProjOn 2>&1 | Out-String)
    Check '2b. --all --dry-run prints the library line with platform and state' ($txt -match 'library: .*library-Win64\.sqlite \(Win64, \w[\w-]*\)') $txt

    $txt = (& $exe index --project (Join-Path $app 'App.dproj') --platform Win32 --resolve-only 2>&1 | Out-String)
    Check '3. explicit --platform Win32 wins -> library-Win32' ($txt -match 'library: .*library-Win32\.sqlite \(Win32\)') $txt

  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
