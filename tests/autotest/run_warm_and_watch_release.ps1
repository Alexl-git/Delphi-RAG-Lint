<#
  run_warm_and_watch_release.ps1 -- 1.39.1: a background rule-cache warm and an
  `index --watch` no longer pin a database (or the engine image) for their
  lifetime. The three 1.39.0 known issues it closes:

  K1. `shutdown --all` did not stop a background warm (`warm-rule-cache
      --detached`): the warm opened no control channel, so the verb never saw
      it, and the warm kept the exe image locked until it ended (minutes on a
      large project).
  K2. `index` did not stop a stale warm of the SAME database: only the next
      warm did (StopStaleWarm ran in DoWarmRuleCache alone), so an index ran
      while an old warm went on computing on the database it was rewriting.
  K3. `index --watch` held `<db>.indexing.lock` for its whole lifetime, so any
      second `index` of that database (IDE save-reindex, agent reindex) exited 2
      until the watch ended. It now holds the lock only during a tick.

  WHAT THIS ASSERTS
    W0 CONTROL: a held warm (DRAGLINT_TEST_WARM_HOLD_MS) is alive and wrote its marker
    W1 `shutdown --db <db>` (the --all discovery, filtered) lists the warm's pid and exits 0            <- K1
    W1b ... labelled with its real role (warm-rule-cache), not 'lsp'  <- 1.39.1
    W2 ... and the warm process is gone afterwards                  <- K1
    W3 CONTROL: the stand-in "stale warm" (same engine image) is alive before the index
    W4 `index --project` of that database stops the stale warm      <- K2
    W5 ... and the index itself exits 0
    W6 CONTROL: the watch finished its first tick and is still running
    W7 a second `index` of the watched database exits 0 (not 2)     <- K3
    W8 the watch runs another tick after the second run and is still alive

  RED-CHECK: on the 1.39.0 build W1/W2, W4 and W7 FAIL; the controls pass.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
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

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
function Wait-Until([scriptblock]$cond, [int]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 200 }
  return [bool](& $cond)
}

$work = Join-Path C:\TEMP "draglint_warm_watch_$PID"
[void][System.IO.Directory]::CreateDirectory($work)
$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'WW.dpr') @'
program WW;

uses
  UWW in 'UWW.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'UWW.pas') @'
unit UWW;

interface

procedure Touch;

implementation

procedure Touch;
begin
end;

end.
'@
$dpr = Join-Path $dir 'WW.dpr'
$db = Join-Path $work 'ww.sqlite'
$marker = $db + '.rule-cache-warm.pid'
$started = New-Object System.Collections.Generic.List[System.Diagnostics.Process]

$o = & $Exe index --project $dpr --db $db --rule-cache-warm off 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "fixture index failed ($LASTEXITCODE): $o" }

Write-Host '=== K1: shutdown --all stops a background warm ===' -ForegroundColor Cyan
$env:DRAGLINT_TEST_WARM_HOLD_MS = '60000'
try {
  $warm = Start-Process -FilePath $Exe -ArgumentList @('warm-rule-cache', '--detached', '--db', "`"$db`"") -WindowStyle Hidden -PassThru
} finally { Remove-Item Env:\DRAGLINT_TEST_WARM_HOLD_MS -ErrorAction SilentlyContinue }
$started.Add($warm)
$ok0 = Wait-Until { (Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -eq "$($warm.Id)") } 15
Start-Sleep -Milliseconds 500
Check 'W0 CONTROL: the held warm is alive and wrote its marker' ($ok0 -and -not $warm.HasExited) "pid $($warm.Id) exited=$($warm.HasExited)"
# --db, never a bare --all: --all would stand down every engine of this user (the IDE's LSP, other runs).
$sd = & $Exe shutdown --db $db --wait 10 2>&1 | Out-String
$sdCode = $LASTEXITCODE
Check 'W1 shutdown (--db filter of --all) lists the warm and exits 0' (($sdCode -eq 0) -and ($sd -match "pid $($warm.Id)\b")) "exit=$sdCode $($sd.Trim() -replace '\s+', ' ')"
# 1.39.1: the listing names the engine's real role; it used to print 'lsp' for every engine.
Check 'W1b ... and labels it warm-rule-cache, not lsp' ($sd -match "(?m)^\s*pid $($warm.Id)\s+warm-rule-cache\s") "$(($sd -split '\r?\n' | Where-Object { $_ -match "pid $($warm.Id)\b" } | Select-Object -First 1))"
$gone = Wait-Until { $warm.HasExited } 15
Check 'W2 ... and the warm process is gone' $gone "exited=$($warm.HasExited)"

Write-Host '=== K2: index stops a stale warm of the same database ===' -ForegroundColor Cyan
# Stand-in stale warm: a long-lived process of THIS engine image (as run_rule_cache_warm_background B9).
$otherDb = Join-Path $work 'other.sqlite'
$stale = Start-Process -FilePath $Exe -ArgumentList @('index', "`"$dir`"", '--db', "`"$otherDb`"", '--watch', '--interval', '60') -WindowStyle Hidden -PassThru
$started.Add($stale)
Start-Sleep -Seconds 3
[System.IO.File]::WriteAllText($marker, "$($stale.Id)", [System.Text.Encoding]::ASCII)
Check 'W3 CONTROL: the stand-in stale warm is alive before the index' (-not $stale.HasExited) "pid $($stale.Id)"
$o5 = & $Exe index --project $dpr --db $db --rule-cache-warm off 2>&1 | Out-String
$code5 = $LASTEXITCODE
$stopped = Wait-Until { $stale.HasExited } 10
Check 'W4 index --project stops the stale warm of its database' $stopped "pid $($stale.Id) exited=$($stale.HasExited)"
Check 'W5 ... and the index exits 0' ($code5 -eq 0) "exit=$code5 $(if ($code5 -ne 0) { $o5.Trim() })"

Write-Host '=== K3: index --watch holds the lock only during a tick ===' -ForegroundColor Cyan
$wOut = Join-Path $work 'watch.out'
$watch = Start-Process -FilePath $Exe -ArgumentList @('index', '--project', "`"$dpr`"", '--db', "`"$db`"", '--watch', '--interval', '3', '--rule-cache-warm', 'off') `
  -RedirectStandardOutput $wOut -RedirectStandardError (Join-Path $work 'watch.err') -WindowStyle Hidden -PassThru
$started.Add($watch)
$tick1 = Wait-Until { (Test-Path -LiteralPath $wOut) -and ((Get-Content -LiteralPath $wOut -Raw) -match 'Done\.') } 30
Start-Sleep -Milliseconds 300
Check 'W6 CONTROL: the watch finished its first tick and is running' ($tick1 -and -not $watch.HasExited) "exited=$($watch.HasExited)"
$o7 = & $Exe index --project $dpr --db $db --rule-cache-warm off 2>&1 | Out-String
$code7 = $LASTEXITCODE
Check 'W7 a second index of the watched database exits 0 (not 2)' ($code7 -eq 0) "exit=$code7 $(if ($code7 -ne 0) { $o7.Trim() -replace '\s+', ' ' })"
$ticksBefore = ([regex]::Matches((Get-Content -LiteralPath $wOut -Raw), 'Indexing tick')).Count
$more = Wait-Until { ([regex]::Matches((Get-Content -LiteralPath $wOut -Raw), 'Done\.')).Count -ge 2 -and ([regex]::Matches((Get-Content -LiteralPath $wOut -Raw), 'Indexing tick')).Count -gt $ticksBefore } 20
Check 'W8 the watch runs another tick afterwards and is still alive' ($more -and -not $watch.HasExited) "ticks=$ticksBefore exited=$($watch.HasExited)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
}
catch { Write-Host "[FAIL] harness: $_" -ForegroundColor Red; exit 1 }
finally {
  foreach ($p in $started) { try { if (-not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(5000) } } catch { } }
  $w = Join-Path C:\TEMP "draglint_warm_watch_$PID"
  if (Test-Path -LiteralPath $w) { try { [System.IO.Directory]::Delete($w, $true) } catch { } }
}
