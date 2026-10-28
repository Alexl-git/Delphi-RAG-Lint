<#
  run_index_all_library_first.ps1 -- `index --all` runs library sections BEFORE project sections,
  and a project section binds the library of ITS OWN platform.

  Plan: docs\superpowers\plans\2026-10-28-library-first-resolve-plan.md s.2.6 (lf-order).

  1. ORDER (always, no flag): a manifest listing two project sections BEFORE its registry-libraries
     section is planned library-first (`--dry-run`, text and --json).
  2. PLATFORM: a closure section whose .dproj says Win64, under a manifest default of Win32 and a
     neutral CWD, opens library-Win64 (before: ResolvePlan gives Platform='' and the CWD/manifest
     default picked library-Win32).
  3. EXPLICIT --platform still wins (Win32 here, against the Win64 .dproj) - positive control that
     the platform really steers the library.
  4. UNKNOWN platform (no .dproj, no --platform): one visible NOTE, never a silent default.

  The library DBs are tiny fixtures built under the test root; no real DB is read or written.
  Run from a neutral CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
function Write-Ascii([string]$Path,[string]$Body){ [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$fixDir = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
$root = Join-Path C:\TEMP "draglint_libfirst_$PID"
try {
  if (Test-Path $root) { [IO.Directory]::Delete($root, $true) }
  $eng = Join-Path $root 'eng'; $out = Join-Path $root 'out'; $lib = Join-Path $root 'lib'
  $app64 = Join-Path $root 'app64'; $appNo = Join-Path $root 'appno'
  New-Item -ItemType Directory -Path $eng,$out,$lib,$app64,$appNo | Out-Null
  Copy-Item $exeSrc (Join-Path $eng 'drag-lint.exe') -Force
  Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
  if (Test-Path (Join-Path $exeSrcDir 'rules')) { Copy-Item (Join-Path $exeSrcDir 'rules') (Join-Path $eng 'rules') -Recurse -Force }
  $exe = Join-Path $eng 'drag-lint.exe'
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $lib -Force
  foreach ($a in $app64,$appNo) {
    Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $a -Force
    Write-Ascii (Join-Path $a 'App.dpr') "program App;`n`nuses`n  xt_app in 'xt_app.pas',`n  xt_app2 in 'xt_app2.pas';`n`nbegin`nend.`n"
  }
  Write-Ascii (Join-Path $app64 'App.dproj') "<Project><PropertyGroup><Platform Condition=`"'`$(Platform)'==''`">Win64</Platform></PropertyGroup></Project>`n"

  $o = $out.Replace('\','/')
  # project sections are listed BEFORE the library section on purpose
  $manifest = @"
{
  "settings": { "defaultPlatform": "Win32", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [
    { "name": "Proj64", "db": "proj64.sqlite", "include": ["$($app64.Replace('\','/'))/App.dpr"], "libraryResolve": true },
    { "name": "ProjNo",  "db": "projno.sqlite",  "include": ["$($appNo.Replace('\','/'))/App.dpr"], "libraryResolve": true },
    { "name": "Library", "db": "library-{platform}.sqlite", "source": "registry-libraries", "platforms": ["Win32","Win64"] }
  ] }
}
"@
  Write-Ascii (Join-Path $eng 'drag-lint.json') $manifest

  Push-Location C:\TEMP
  try {
    foreach ($p in 'Win32','Win64') { & $exe index $lib --db (Join-Path $out "library-$p.sqlite") 2>&1 | Out-Null }
    Check 'fixture libraries built' ((Test-Path (Join-Path $out 'library-Win32.sqlite')) -and (Test-Path (Join-Path $out 'library-Win64.sqlite')))

    # 1. ORDER
    $txt = (& $exe index --all --dry-run 2>&1 | Out-String)
    $iLib = $txt.IndexOf('[Library['); $iP64 = $txt.IndexOf('[Proj64]'); $iPNo = $txt.IndexOf('[ProjNo]')
    Check 'dry-run: all three sections planned' (($iLib -ge 0) -and ($iP64 -ge 0) -and ($iPNo -ge 0)) $txt
    Check 'dry-run (text): library listed before both project sections' (($iLib -ge 0) -and ($iLib -lt $iP64) -and ($iLib -lt $iPNo)) $txt
    $j = ((& $exe index --all --dry-run --json 2>&1) -join "`n"); $j = $j.Substring($j.IndexOf('{')) | ConvertFrom-Json
    $names = @($j.sections | ForEach-Object { $_.name })
    Check 'dry-run (json): first section is the library' ($names.Count -ge 3 -and $names[0] -eq 'Library') ($names -join ',')
    $txt = (& $exe index --all --dry-run --only Proj64 2>&1 | Out-String)
    Check '--only <project>: not delayed, planned alone' (($txt -match '\[Proj64\]') -and ($txt -notmatch '\[Library\['))

    # 2. PLATFORM from the .dproj (manifest default is Win32)
    $txt = (& $exe index --all --only Proj64 2>&1 | Out-String)
    Check 'Win64 .dproj: library-Win64 is opened' ($txt -match '\+ library-db .*library-Win64\.sqlite') $txt
    Check 'Win64 .dproj: library-Win32 is NOT opened' ($txt -notmatch 'library-Win32\.sqlite')

    # 3. explicit --platform wins
    $txt = (& $exe index --all --only Proj64 --platform Win32 --force-reparse 2>&1 | Out-String)
    Check 'explicit --platform Win32 wins over the .dproj' ($txt -match '\+ library-db .*library-Win32\.sqlite') $txt

    # 4. unknown platform -> visible NOTE
    $txt = (& $exe index --all --only ProjNo 2>&1 | Out-String)
    Check 'unknown platform: a visible NOTE names the section' ($txt -match 'NOTE: platform of section "ProjNo" is unknown') $txt
    Check 'known platform: no such NOTE' ((& $exe index --all --only Proj64 --force-reparse 2>&1 | Out-String) -notmatch 'is unknown')
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
