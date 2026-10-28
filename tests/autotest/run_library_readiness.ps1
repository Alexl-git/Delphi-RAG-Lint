<#
  run_library_readiness.ps1 -- library-first resolve, lane lf-ready (plan 2026-10-28, s.2.2 + s.2.5 line 1):
  the indexer probes the platform library BEFORE the walk and says whether it is READY.

  Asserted (hermetic engine copy with its own drag-lint.json; one library fixture, six states made by
  editing COPIES of it -- never a real DB):
    ready            -> "library: ... READY", the library is opened ("+ library-db"), sites bind
                        (POSITIVE CONTROL: without it the not-ready rows could pass with the feature off)
    missing          -> "NOT READY -- no library index file", no "+ library-db"
    rebuilding       -> rebuild_in_progress=1 -> "NOT READY -- rebuild in progress"
    stale extractor  -> v=0.0.1 limb      -> "NOT READY -- stale-extractor"   (plan Q1 default)
    schema old       -> schema_version=1  -> "NOT READY -- schema"
    never completed  -> no indexer_fingerprint / indexed_at_unix -> "NOT READY -- no completed walk"
  Every not-ready run still CONTINUES (exit 0, the project DB is written) and prints "library: PENDING".
  --require-library on a not-ready library -> ERROR, exit 2, no project DB written.
  --wait-library 1 with DRAGLINT_LIBRARY_POLL_MS=1000: the run polls (>= 2 "waiting" probes) and, once the
  library copy is made ready mid-wait, opens it.
  Run from a NEUTRAL CWD (C:\TEMP).
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
$py = (Get-Command python -ErrorAction Stop).Source
$root = Join-Path C:\TEMP "draglint_libready_$PID"
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
  Write-Ascii (Join-Path $eng 'drag-lint.json') @"
{
  "settings": { "defaultPlatform": "Win64", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [
    { "name": "Library", "db": "library-{platform}.sqlite", "source": "registry-libraries", "platforms": ["Win64"] },
    { "name": "ProjOn", "db": "projon.sqlite", "include": ["$($app.Replace('\','/'))/App.dpr"], "libraryResolve": true }
  ] }
}
"@
  # python edits a COPY of the library: stale / rebuilding / schema / never-completed
  $mut = Join-Path $root 'mut.py'
  Write-Ascii $mut @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); mode = sys.argv[2]
if mode == 'rebuilding':
    c.execute("insert or replace into schema_meta(key,value) values('rebuild_in_progress','1')")
elif mode == 'stale':
    fp = c.execute("select value from schema_meta where key='indexer_fingerprint'").fetchone()[0]
    limbs = fp.split(';'); limbs[0] = 'v=0.0.1'
    c.execute("update schema_meta set value=? where key='indexer_fingerprint'", (';'.join(limbs),))
elif mode == 'schema':
    c.execute("update schema_meta set value='1' where key='schema_version'")
elif mode == 'never':
    c.execute("delete from schema_meta where key in ('indexer_fingerprint','indexed_at_unix')")
c.commit(); c.close()
'@
  $libDb  = Join-Path $out 'library-Win64.sqlite'
  $good   = Join-Path $root 'library-good.sqlite'
  $projDb = Join-Path $out 'projon.sqlite'
  $extCount = 'select count(*) from refs where external_target is not null and external_target <> ''''  '
  function Q([string]$Db,[string]$Query) {
    $raw = (& $exe sql --db $Db --json --limit 5000 --query $Query 2>$null) -join "`n"
    $b = $raw.IndexOf('{'); if ($b -lt 0) { return ,@() }
    return ,@(($raw.Substring($b) | ConvertFrom-Json).rows)
  }
  function Fresh([string]$Mode) {
    foreach ($f in $libDb,"$libDb-wal","$libDb-shm",$projDb,"$projDb-wal","$projDb-shm") { if (Test-Path $f) { [IO.File]::Delete($f) } }
    if ($Mode -ne 'missing') { Copy-Item $good $libDb -Force }
    if ($Mode -in 'rebuilding','stale','schema','never') { & $py -I $mut $libDb $Mode | Out-Null }
  }
  Push-Location C:\TEMP
  try {
    & $exe index $lib --db $good 2>&1 | Out-Null
    Check 'library fixture indexed' ((Test-Path $good) -and ($LASTEXITCODE -eq 0))

    # ---- ready: the positive control
    Fresh 'ready'
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') 2>&1 | Out-String)
    Check 'ready: exit 0 and project DB written' (($LASTEXITCODE -eq 0) -and (Test-Path $projDb)) $txt
    Check 'ready: "library: ... READY" printed before the walk' ($txt -match 'library: .*library-Win64\.sqlite \(Win64\) READY') $txt
    Check 'ready: the library is opened' ($txt -match '\+ library-db .*library-Win64\.sqlite') $txt
    Check 'ready: sites bind (external_target filled)' ((Q $projDb $extCount)[0][0] -gt 0)
    Check 'ready: no PENDING line' ($txt -notmatch 'library: PENDING') $txt

    # ---- the five not-ready states
    $cases = @(
      @{ mode='missing';    why='no library index file' },
      @{ mode='rebuilding'; why='rebuild in progress' },
      @{ mode='stale';      why='stale-extractor' },
      @{ mode='schema';     why='schema v' },
      @{ mode='never';      why='no completed walk' }
    )
    foreach ($c in $cases) {
      Fresh $c.mode
      $txt = (& $exe index --project (Join-Path $app 'App.dpr') 2>&1 | Out-String)
      $m = $c.mode
      Check "$m`: run continues (exit 0, project DB written)" (($LASTEXITCODE -eq 0) -and (Test-Path $projDb)) $txt
      Check "$m`: NOT READY with the reason" ($txt -match ('NOT READY -- ' + [regex]::Escape($c.why))) $txt
      Check "$m`: says it is marked pending / PENDING summary" (($txt -match 'marked pending') -and ($txt -match 'library: PENDING')) $txt
      Check "$m`: the library is NOT opened" ($txt -notmatch '\+ library-db') $txt
      Check "$m`: nothing bound" ((Q $projDb $extCount)[0][0] -eq 0)
    }

    # ---- --require-library
    Fresh 'rebuilding'
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') --require-library 2>&1 | Out-String)
    Check '--require-library, not ready: exit 2' ($LASTEXITCODE -eq 2) $txt
    Check '--require-library, not ready: ERROR names the reason' ($txt -match 'ERROR: library: .*NOT READY -- rebuild in progress') $txt
    Check '--require-library, not ready: nothing walked (no files indexed)' ((-not (Test-Path $projDb)) -or ((Q $projDb 'select count(*) from files')[0][0] -eq 0))
    Fresh 'ready'
    $txt = (& $exe index --project (Join-Path $app 'App.dpr') --require-library 2>&1 | Out-String)
    Check '--require-library, ready: exit 0' ($LASTEXITCODE -eq 0) $txt

    # ---- --wait-library: poll, the library becomes ready mid-wait, the run binds
    Fresh 'rebuilding'
    $env:DRAGLINT_LIBRARY_POLL_MS = '1000'
    $log = Join-Path $root 'wait.log'
    $p = Start-Process -FilePath $exe -ArgumentList 'index','--project',(Join-Path $app 'App.dpr'),'--wait-library','1' `
         -RedirectStandardOutput $log -RedirectStandardError (Join-Path $root 'wait.err') -PassThru -NoNewWindow
    # wait until the run is actually polling, let it poll a few times, THEN finish the "rebuild"
    $until = (Get-Date).AddSeconds(900)
    while (((Get-Content $log -Raw -ErrorAction SilentlyContinue) -notmatch 'library: waiting') -and ((Get-Date) -lt $until)) { Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3
    Copy-Item $good $libDb -Force   # the "rebuild" completed
    $p.WaitForExit(120000) | Out-Null
    $txt = Get-Content $log -Raw
    $env:DRAGLINT_LIBRARY_POLL_MS = $null
    Check '--wait-library: polled at least twice' (([regex]::Matches($txt,'library: waiting')).Count -ge 2) $txt
    Check '--wait-library: library ready after the wait -> opened' ($txt -match '\+ library-db .*library-Win64\.sqlite') $txt
    Check '--wait-library: sites bind' ((Q $projDb $extCount)[0][0] -gt 0)
  } finally { Pop-Location; $env:DRAGLINT_LIBRARY_POLL_MS = $null }
} finally {
  if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
