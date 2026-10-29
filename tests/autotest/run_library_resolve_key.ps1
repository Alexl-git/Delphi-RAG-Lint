<#
  run_library_resolve_key.ps1 -- item 4 (untypable receivers), spec s.9 Q1: the per-section manifest
  key "libraryResolve" (default FALSE) lets `index --all` / `index --project` open the platform
  library index as an extra store for the call-resolve pass, so a value receiver typed by name binds
  to refs.external_target WITHOUT remembering --library-db.

  Asserted (hermetic engine copy with its own drag-lint.json; the library DB is indexed straight to
  library-Win64.sqlite so ResolveLibraryDb finds it through the manifest):
    1. DEFAULT OFF: a section without the key opens NO library (no "+ library-db" line) and its
       refs.external_target stays NULL for every row  (the 2026-10-25 no-attach ruling).
    2. ON (index --all --only): the run opens the library ("+ library-db ...library-Win64.sqlite")
       and the same sites bind  (external_target filled: needs the resolver fill lane).
    3. ON (index --project): same through the DoIndex path.
    4. The key survives a manifest round trip (`manifest` JSON still shows it) is covered by
       run_manifest.ps1; here: an explicit --library-db still wins over the key (no second open).
  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
function Write-Ascii([string]$Path,[string]$Body){ [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$fixDir = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
$root = Join-Path C:\TEMP "draglint_libresolve_$PID"
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

  $o = $out.Replace('\','/')
  $manifest = @"
{
  "settings": { "defaultPlatform": "Win64", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [
    { "name": "Library", "db": "library-{platform}.sqlite", "source": "registry-libraries", "platforms": ["Win64"] },
    { "name": "AppOff", "db": "appoff.sqlite", "include": ["$($app.Replace('\','/'))"] },
    { "name": "AppOn",  "db": "appon.sqlite",  "include": ["$($app.Replace('\','/'))"], "libraryResolve": true },
    { "name": "ProjOn", "db": "projon.sqlite", "include": ["$($app.Replace('\','/'))/App.dpr"], "libraryResolve": true }
  ] }
}
"@
  Write-Ascii (Join-Path $eng 'drag-lint.json') $manifest

  function Q([string]$Db,[string]$Query) {
    $raw = (& $exe sql --db $Db --json --limit 5000 --query $Query 2>$null) -join "`n"
    $b = $raw.IndexOf('{'); if ($b -lt 0) { return ,@() }
    $j = $raw.Substring($b) | ConvertFrom-Json
    return ,@($j.rows)
  }
  $extCount = 'select count(*) from refs where external_target is not null and external_target <> ''''  '
  Push-Location C:\TEMP
  try {
    $libDb = Join-Path $out 'library-Win64.sqlite'
    & $exe index $lib --db $libDb 2>&1 | Out-Null
    Check 'library index built at the manifest library path' ((Test-Path $libDb) -and ($LASTEXITCODE -eq 0))

    # 1. default OFF
    $txt = (& $exe index --all --only AppOff 2>&1 | Out-String)
    Check 'AppOff: section indexed' (Test-Path (Join-Path $out 'appoff.sqlite')) $txt
    Check 'OFF: no library opened' ($txt -notmatch '\+ library-db')
    Check 'OFF: external_target NULL on every row' ((Q (Join-Path $out 'appoff.sqlite') $extCount)[0][0] -eq 0)

    # 2. ON via index --all
    $txt = (& $exe index --all --only AppOn 2>&1 | Out-String)
    Check 'AppOn: section indexed' (Test-Path (Join-Path $out 'appon.sqlite')) $txt
    Check 'ON (--all): the platform library is opened' ($txt -match '\+ library-db .*library-Win64\.sqlite') $txt
    Check 'ON (--all): sites bind (external_target filled)' ((Q (Join-Path $out 'appon.sqlite') $extCount)[0][0] -gt 0)

    # 3. ON via index --project
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') 2>&1 | Out-String)
    Check 'ON (--project): the platform library is opened' ($txt -match '\+ library-db .*library-Win64\.sqlite') $txt
    Check 'ON (--project): sites bind (external_target filled)' ((Q (Join-Path $out 'projon.sqlite') $extCount)[0][0] -gt 0)

    # 4. an explicit --library-db wins: opened exactly once
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') --library-db $libDb --resolve-only 2>&1 | Out-String)
    Check 'explicit --library-db: opened once, not twice' (([regex]::Matches($txt,'\+ library-db')).Count -eq 1) $txt
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
