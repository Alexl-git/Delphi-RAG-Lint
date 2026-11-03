<#
  run_cli141_followups.ps1 -- 1.41 lane "cli": five small CLI defects, one RED/GREEN check each.

    REVCT-OUTPUT  reverse-calltree --output F writes F (and stdout stays free of the tree)
    LOCK-TEXT     a lock refusal names the verb that was refused (purge-locals), not "index"
    DST-LOGSTAMP  the index log's `stage: X -- started HH:MM:SS` is the real local clock
    WARM-TMP      warm-rule-cache deletes the .tmp-<pid> cache files of a DEAD writer, keeps a live one's
    SERVE-ALLDBS  `serve` with no --db and several manifest databases says once which it uses
                  and no longer lists every other database as "ignored"

  POSITIVE CONTROLS: `index` still reports "ERROR: index:" on a held lock; a live pid's .tmp file survives;
  without --output the tree is still on stdout. (`serve --db A --db B` keeping its "ignored:" list is owned
  by run_serve_multidb_warning_guard.ps1.)
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cli141-$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$env:DRAGLINT_RULE_CACHE_DIR = Join-Path $WorkDir 'cache'
New-Item -ItemType Directory $env:DRAGLINT_RULE_CACHE_DIR | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, (($Body -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
Write-Ascii (Join-Path $src 'ua.pas') "unit ua;`ninterface`nprocedure Pa;`nimplementation`nprocedure Pa; begin end;`nend.`n"
$db = Join-Path $WorkDir 'p.sqlite'
Push-Location $WorkDir
try {
  # ---- DST-LOGSTAMP (also builds the index) ----------------------------------
  Write-Host 'DST-LOGSTAMP' -ForegroundColor Cyan
  $before = Get-Date
  $log = & $Exe index $src --db $db 2>&1 | Out-String
  $after = Get-Date
  $m = [regex]::Match($log, 'stage: \S+ -- started (\d\d):(\d\d):(\d\d)')
  Check 'index log has a "started HH:MM:SS" line' $m.Success
  if ($m.Success) {
    $stamp = $before.Date.AddHours([int]$m.Groups[1].Value).AddMinutes([int]$m.Groups[2].Value).AddSeconds([int]$m.Groups[3].Value)
    $off = [math]::Min([math]::Abs(($stamp - $before).TotalSeconds), [math]::Abs(($stamp - $after).TotalSeconds))
    if ($off -gt 12 * 3600) { $off = 86400 - $off }
    Check 'stamp is within 5 min of the real local clock' ($off -lt 300) ("off by {0:N0} s" -f $off)
  }

  # ---- REVCT-OUTPUT -----------------------------------------------------------
  Write-Host 'REVCT-OUTPUT' -ForegroundColor Cyan
  $out = Join-Path $WorkDir 'tree.txt'
  $stdout = & $Exe reverse-calltree --qname Pa --db $db --output $out 2>&1 | Out-String
  Check 'exit 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE stdout=[$($stdout.Trim())]"
  Check '--output file exists' (Test-Path $out)
  $fileText = if (Test-Path $out) { Get-Content $out -Raw } else { '' }
  Check 'file holds the tree root' ($fileText -match 'Pa')
  Check 'stdout names the file and does not carry the tree' (($stdout -match [regex]::Escape($out)) -and ($stdout -notmatch '(?m)^ua\.Pa'))
  $plain = & $Exe reverse-calltree --qname Pa --db $db 2>&1 | Out-String
  Check 'POSITIVE CONTROL: without --output the tree is on stdout' ($plain -match 'Pa')

  # ---- LOCK-TEXT --------------------------------------------------------------
  Write-Host 'LOCK-TEXT' -ForegroundColor Cyan
  $fs = [System.IO.File]::Open("$db.indexing.lock", 'OpenOrCreate', 'Write', 'None')
  try {
    $e1 = & $Exe purge-locals --db $db 2>&1 | Out-String
    Check 'purge-locals refused (exit 2)' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
    Check 'refusal names purge-locals' ($e1 -match 'ERROR: purge-locals:') ($e1.Trim())
    $e2 = & $Exe index $src --db $db 2>&1 | Out-String
    Check 'POSITIVE CONTROL: index still says "ERROR: index:"' ($e2 -match 'ERROR: index:') ($e2.Trim())
  } finally { $fs.Dispose() }

  # ---- WARM-TMP ---------------------------------------------------------------
  Write-Host 'WARM-TMP' -ForegroundColor Cyan
  & $Exe warm-rule-cache --db $db 2>&1 | Out-Null
  $cacheFile = Get-ChildItem $env:DRAGLINT_RULE_CACHE_DIR -Filter 'rules-*.json' | Select-Object -First 1
  Check 'warm-rule-cache wrote its cache file' ($null -ne $cacheFile)
  if ($cacheFile) {
    $p = Start-Process cmd.exe -ArgumentList '/c', 'exit' -PassThru -WindowStyle Hidden
    $p.WaitForExit()
    $deadPid = $p.Id
    $p.Dispose() # an open Process object keeps the exited pid openable; release it
    $deadTmp = "$($cacheFile.FullName).tmp-$deadPid"
    $liveTmp = "$($cacheFile.FullName).tmp-$PID"
    Set-Content $deadTmp 'x'; Set-Content $liveTmp 'x'
    & $Exe warm-rule-cache --db $db 2>&1 | Out-Null
    Check 'dead writer''s .tmp file is gone' (-not (Test-Path $deadTmp))
    Check 'POSITIVE CONTROL: a live pid''s .tmp file is kept' (Test-Path $liveTmp)
  }

  # ---- SERVE-ALLDBS -----------------------------------------------------------
  Write-Host 'SERVE-ALLDBS' -ForegroundColor Cyan
  $sw = Join-Path $WorkDir 'serve'
  foreach ($n in 'alpha', 'beta', 'gamma') {
    New-Item -ItemType Directory (Join-Path $sw $n) -Force | Out-Null
    Write-Ascii (Join-Path $sw "$n\u$n.pas") "unit u$n;`ninterface`nimplementation`nend.`n"
  }
  $mtext = '{ "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' +
    ' "indexes": { "outDir": "out", "sections": [' +
    ' { "name": "SecAlpha", "db": "alpha.sqlite", "include": ["alpha"] },' +
    ' { "name": "SecBeta", "db": "beta.sqlite", "include": ["beta"] },' +
    ' { "name": "SecGamma", "db": "gamma.sqlite", "include": ["gamma"] } ] } }'
  Write-Ascii (Join-Path $sw '.drag-lint.json') $mtext
  Push-Location $sw
  try {
    & $Exe index --all --config (Join-Path $sw '.drag-lint.json') --jobs 1 2>&1 | Out-Null
    Check 'fixture: three databases built' ((Get-ChildItem (Join-Path $sw 'out') -Filter *.sqlite -ErrorAction SilentlyContinue).Count -eq 3)
    $emptyIn = Join-Path $WorkDir 'empty.in'; Write-Ascii $emptyIn ''
    $errF = Join-Path $WorkDir 'serve.err'
    $pr = Start-Process -FilePath $Exe -ArgumentList @('serve') -RedirectStandardInput $emptyIn -RedirectStandardError $errF `
            -RedirectStandardOutput (Join-Path $WorkDir 'serve.out') -NoNewWindow -PassThru
    if (-not $pr.WaitForExit(30000)) { try { $pr.Kill($true) } catch { } }
    $se = if (Test-Path $errF) { Get-Content $errF -Raw } else { '' }
    Check 'serve names the database it uses' ($se -match 'NOTE -- no --db given.*FIRST') ($se -replace '\s+', ' ')
    Check 'serve does not list the other databases as ignored' ($se -notmatch 'ignored:') ($se -replace '\s+', ' ')
  } finally { Pop-Location }
}
finally { Pop-Location }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
