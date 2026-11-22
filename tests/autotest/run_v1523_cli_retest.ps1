<#
  run_v1523_cli_retest.ps1 -- v1523 TESTS-ENV, CLI-RETEST: the three cards of docs\INBOX-151-cli-retest-fails.md
  (C2, C3, C10) re-run on REBUILT copies of the real DBs, read-only against the engine under test.

    C2   rename --plan --kind symbol --name YADF.Tokens.TToken.Text --to X on a YADFOT copy:
         no refusal naming [receiver-untyped]; "undecided: 0"; the plan decides > 0 edits (positive control).
    C3   the .dpr main block's `Application` refs of Micronite2027 copy carry external_target
         (all of them, and at least 8 rows -- positive control so an empty query cannot pass).
         NEEDS the copy indexed WITH --library-db (a bare-read bind is a library bind; no library = 0 bound).
    C10  fixture t2-library-root-150 (library T2Lib uses uT2LibUnit): find-deadcode does not list uT2LibUnit;
         positive control: an orphan unit IS listed. Needs no real DB.

  DB copies: -YadfDb / -MicDb are DBs the CALLER rebuilt with the engine under test (index --project ... --library-db
  <library> --rebuild). With -Reindex the runner rebuilds both into a scratch folder itself (~10 min, heavy: free RAM
  >= 8 GB required) and deletes them after. A missing DB / dproj / library => that card is SKIPPED, loudly, naming
  the path; a skip is NOT a pass (the final line says SKIPS). C10 always runs.

  Usage (neutral CWD, pwsh 7):
    pwsh -File tests\autotest\run_v1523_cli_retest.ps1 -Exe <drag-lint.exe> [-YadfDb <x.sqlite>] [-MicDb <x.sqlite>] [-Reindex]
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Exe,   # no default engine: a runner must never silently test third_party\dll-win64
  [string]$YadfDb = '',
  [string]$MicDb = '',
  [string]$LibraryWin32 = 'C:\Projects\.drag-lint\library-Win32.sqlite',
  [string]$YadfProj = 'C:\Projects\YADF\YADFOT.dproj',
  [string]$MicProj = 'C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj',
  [switch]$Reindex
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
$script:skips = 0
function Check([bool]$ok, [string]$what, [string]$detail = '') {
  if ($ok) { Write-Host "PASS  $what" }
  else { Write-Host "FAIL  $what" -ForegroundColor Red; if ($detail) { Write-Host "      $detail" }; $script:fail = $true }
}
function Skip([string]$what, [string]$why) { $script:skips++; Write-Host "SKIP  $what -- $why" -ForegroundColor Yellow }
# PS5-safe native call: stderr merged and flattened to plain text lines.
function Invoke-Dl([string[]]$ArgList) {
  & { $ErrorActionPreference = 'Continue'; & $script:ExePath @ArgList 2>&1 | ForEach-Object { "$_" } }
}
$script:ExePath = (Resolve-Path -LiteralPath $Exe).Path
$scratch = Join-Path $env:TEMP ("v1523_cli_retest_" + $PID)
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
  if ($Reindex) {
    $free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
    if ($free -lt 8) { throw "free RAM $([math]::Round($free,1)) GB < 8 GB: wait and retry (heavy rebuild)" }
    foreach ($p in @(@('yadf', $YadfProj), @('mic', $MicProj))) {
      if (-not (Test-Path -LiteralPath $p[1]) -or -not (Test-Path -LiteralPath $LibraryWin32)) { continue }
      $db = Join-Path $scratch ($p[0] + '.sqlite')
      $null = Invoke-Dl @('index', '--project', $p[1], '--db', $db, '--library-db', $LibraryWin32, '--rebuild')
      if ($p[0] -eq 'yadf') { $YadfDb = $db } else { $MicDb = $db }
    }
  }

  # ---- C2 --------------------------------------------------------------------------------------------------------
  if (-not $YadfDb -or -not (Test-Path -LiteralPath $YadfDb)) { Skip 'C2' "no YADFOT DB copy (-YadfDb / -Reindex); looked for: '$YadfDb'" }
  elseif (-not (Test-Path -LiteralPath $LibraryWin32)) { Skip 'C2' "library DB absent: $LibraryWin32" }
  else {
    $o = (Invoke-Dl @('rename', '--plan', '--kind', 'symbol', '--name', 'YADF.Tokens.TToken.Text', '--to', 'X', '--db', $YadfDb, '--library-db', $LibraryWin32)) -join "`n"
    Check ($o -match '(?m)^rename plan: YADF\.Tokens\.TToken\.Text') 'C2 positive control: a rename plan was produced' ($o.Substring(0, [Math]::Min(300, $o.Length)))
    Check ($o -match 'decided: (?!0 edit)\d+ edit') 'C2 positive control: the plan decides edits'
    Check ($o -notmatch 'receiver-untyped') 'C2 no [receiver-untyped] refusal (hard-cast receivers bound)'
    Check ($o -match 'undecided: 0') 'C2 undecided: 0'
  }

  # ---- C3 --------------------------------------------------------------------------------------------------------
  if (-not $MicDb -or -not (Test-Path -LiteralPath $MicDb)) { Skip 'C3' "no Micronite2027 DB copy (-MicDb / -Reindex); looked for: '$MicDb'" }
  else {
    $q = "SELECT count(*), sum(CASE WHEN r.external_target IS NULL AND r.symbol_id IS NULL THEN 1 ELSE 0 END), min(r.external_target) FROM refs r JOIN files f ON f.id = r.file_id WHERE r.name_text = 'Application' AND r.kind = 'read' AND f.path LIKE '%Micronite2027.dpr'"
    $j = (Invoke-Dl @('sql', '--db', $MicDb, '--json', '--query', $q)) -join "`n" | ConvertFrom-Json | ForEach-Object { $_ }
    $row = @($j.rows[0])
    Check ([int]$row[0] -ge 8) "C3 positive control: >= 8 Application read refs in Micronite2027.dpr (the 686 write-through row is the same site as its bound read) (got $($row[0]))"
    Check (([int]$row[0] -ge 8) -and ("$($row[1])" -eq '0')) "C3 no Application ref left with symbol_id AND external_target NULL (got $($row[1]) unbound; min target '$($row[2])')" 'index the DB copy with --library-db <library-Win32.sqlite> (a library-less rebuild binds 0)'
  }

  # ---- C10 -------------------------------------------------------------------------------------------------------
  $fx = Join-Path $PSScriptRoot '..\fixtures\t2-library-root-150'
  $lib = Join-Path $scratch 'lib'
  New-Item -ItemType Directory -Path $lib -Force | Out-Null
  Copy-Item (Join-Path $fx '*') $lib -Force
  [IO.File]::WriteAllText((Join-Path $lib 'uOrphanUnit.pas'), "unit uOrphanUnit;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n")
  $dbL = Join-Path $scratch 'lib.sqlite'
  $null = Invoke-Dl @('index', $lib, '--db', $dbL)
  $d = (Invoke-Dl @('find-deadcode', '--db', $dbL)) -join "`n"
  Check ($d -notmatch '(?m)^uT2LibUnit\s+\[unit\]') 'C10 uT2LibUnit (in T2Lib uses) is not a dead-code candidate' $d
  Check ($d -match '(?m)^uOrphanUnit\s+\[unit\]') 'C10 positive control: the orphan unit IS listed' $d
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
if ($script:skips -gt 0) { Write-Host "PASS with $($script:skips) SKIP(S) (skips are not passes)" -ForegroundColor Yellow; exit 0 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
