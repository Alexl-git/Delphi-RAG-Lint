<#
  run_library_gate_honours_config.ps1 -- `index --all --config <manifest>` evaluates the
  library gate against THAT manifest, not the engine directory's drag-lint.json
  (LIBRARY-GATE-IGNORES-CONFIG: EvaluateLibraryGate built Default(TArgs), so an engine with
  a stub json marked real DBs library_resolve_state=pending although the named manifest has
  a ready library).
  Hermetic engine copy whose own drag-lint.json is a STUB (no Library section); the real
  manifest is passed with --config. Fixture: tests\callresolve\fixtures\xtyped.
    a. --config run -> "library: bound", marker state=bound, external_target > 0
    b. POSITIVE CONTROL: the same run WITHOUT --config (stub only) -> pending, external_target = 0
       (proves the stub really cannot see the library, so (a) can only pass via --config)
  Run from a NEUTRAL CWD (C:\TEMP). Touches no shared index.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
function Write-Ascii([string]$Path,[string]$Body){ [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n","`r`n"), [Text.Encoding]::ASCII) }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$fixDir = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
$root = Join-Path C:\TEMP "draglint_libcfg_$PID"
try {
  $eng = Join-Path $root 'eng'; $out = Join-Path $root 'out'; $lib = Join-Path $root 'lib'; $app = Join-Path $root 'app'
  New-Item -ItemType Directory -Path $eng,$out,$lib,$app | Out-Null
  Copy-Item $exeSrc (Join-Path $eng 'drag-lint.exe') -Force
  Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
  if (Test-Path (Join-Path $exeSrcDir 'rules')) { Copy-Item (Join-Path $exeSrcDir 'rules') (Join-Path $eng 'rules') -Recurse -Force }
  $exe = Join-Path $eng 'drag-lint.exe'
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $lib -Force
  Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $app -Force
  Write-Ascii (Join-Path $app 'App.dpr') "program App;`n`nuses`n  xt_app in 'xt_app.pas',`n  xt_app2 in 'xt_app2.pas';`n`nbegin`nend.`n"
  $o = $out.Replace('\','/'); $a = $app.Replace('\','/')
  $sections = @"
    { "name": "ProjOn", "db": "projon.sqlite", "include": ["$a/App.dpr"], "libraryResolve": true }
"@
  # the engine's own json: a stub that knows no library
  Write-Ascii (Join-Path $eng 'drag-lint.json') @"
{ "settings": { "defaultPlatform": "Win64", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [ $sections ] } }
"@
  $cfg = Join-Path $root 'real.json'
  Write-Ascii $cfg @"
{ "settings": { "defaultPlatform": "Win64", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [
    { "name": "Library", "db": "library-{platform}.sqlite", "source": "registry-libraries", "platforms": ["Win64"] },
    $sections ] } }
"@
  function Q([string]$Db,[string]$Query) {
    $raw = (& $exe sql --db $Db --json --limit 5000 --query $Query 2>$null) -join "`n"
    $b = $raw.IndexOf('{'); if ($b -lt 0) { return ,@() }
    return ,@(($raw.Substring($b) | ConvertFrom-Json).rows)
  }
  $extCount = 'select count(*) from refs where external_target is not null and external_target <> '''''
  $projOn = Join-Path $out 'projon.sqlite'; $libDb = Join-Path $out 'library-Win64.sqlite'
  Push-Location C:\TEMP
  try {
    & $exe index $lib --db $libDb 2>&1 | Out-Null
    Check 'library index built' (Test-Path $libDb)
    $txt = (& $exe index --all --config $cfg --only ProjOn 2>&1 | Out-String)
    Check 'project DB built' (Test-Path $projOn) $txt
    Check 'a: no "library: PENDING" with --config' ($txt -notmatch 'library: PENDING') $txt
    $m = (& $exe sql --db $projOn --json --query "select value from schema_meta where key = 'library_resolve_state'" 2>$null) -join "`n"
    Check 'a: marker state=bound' ($m -match 'bound') $m
    Check 'a: external_target > 0' ((Q $projOn $extCount)[0][0] -gt 0)
    [IO.File]::Delete($projOn)
    $txt2 = (& $exe index --all --only ProjOn 2>&1 | Out-String)
    Check 'b control: without --config the stub engine json cannot see the library (pending)' ($txt2 -match 'library: PENDING|NOT READY') $txt2
    Check 'b control: external_target = 0' ((Q $projOn $extCount)[0][0] -eq 0)
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }