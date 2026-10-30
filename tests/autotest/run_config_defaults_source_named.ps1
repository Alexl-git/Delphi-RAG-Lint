<#
  run_config_defaults_source_named.ps1 -- a .drag-lint.json defaults file is
  NAMED wherever it decides a write, and a broken one stops the source writers
  (INBOX-2026-09-29-engine-followups-from-1.20.4 items 4b and 5).

  THE DEFECTS.
    * A "db" key counts as an explicit --db, but the refusal for a missing one
      said only "An explicit --db must be an existing index" -- the user typed
      no --db, and nothing said which file supplied it.
    * `index --project <B>` run inside project A's tree, where A's
      .drag-lint.json says {"db": "A.sqlite"}, writes B into A.sqlite and the
      `Database:` line gave no hint where that path came from.
    * A .drag-lint.json that failed to parse (a wrong-typed docs key) stopped
      the INDEX writers but not the SOURCE writers: `document --apply` and
      `lint --fix --apply` carried on with the default for the bad key.

    A. config db missing      -> exit 2, the ERROR names the config file and its "db" key.
    B. CONTROL: command-line --db missing -> exit 2, ERROR keeps the explicit-db
       wording and names NO config file (so A is not vacuous).
    C. index --project (target under the config folder) -> the line after `Database:`
       names the config file; the Database: line itself is unchanged.
    D. CONTROL: index with a command-line --db -> no config-source line.
    E. broken config + document --apply      -> exit 2, refusing to write.
    F. broken config + lint --fix --apply    -> exit 2, refusing to write.
    G. CONTROL: broken config + document (dry run) -> NOT refused (exit 0).

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-config-source-$PID"
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
function Write-Ascii([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function RunIn([string]$Dir, [string[]]$A) {
  Push-Location $Dir
  try {
    $out = & $Exe @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
  } finally { Pop-Location }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# A tiny project, indexed from a folder with NO defaults file.
$proj = Join-Path $WorkDir 'p'
New-Item -ItemType Directory -Force (Join-Path $proj 'sub') | Out-Null
Write-Ascii (Join-Path $proj 'P.dpr') "program P;`nuses U1 in 'sub\U1.pas';`nbegin`nend.`n"
$u1 = Join-Path $proj 'sub\U1.pas'
Write-Ascii $u1 "unit U1;`ninterface`nprocedure Foo;`nimplementation`nprocedure Foo; begin end;`nend.`n"
$neutral = Join-Path $WorkDir 'neutral'
New-Item -ItemType Directory -Force $neutral | Out-Null
$goodDb = Join-Path $WorkDir 'good.sqlite'
$r0 = RunIn $neutral @('index', '--project', (Join-Path $proj 'P.dpr'), '--db', $goodDb)
if ($r0.Code -ne 0) { Write-Host "FATAL: fixture index failed (exit $($r0.Code))" -ForegroundColor Red; Write-Host $r0.Out; exit 2 }

# A folder whose defaults file names a db that does not exist.
$cfgDir  = Join-Path $WorkDir 'cfgmissing'
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$cfgFile = Join-Path $cfgDir '.drag-lint.json'
$nope    = Join-Path $WorkDir 'nope\x.sqlite'
Write-Ascii $cfgFile ((@{ db = $nope } | ConvertTo-Json))

Write-Host 'A. config "db" names a missing file' -ForegroundColor Cyan
$a = RunIn $cfgDir @('query', '--name', 'Foo')
$aErr = (($a.Out -split "`r?`n") | Where-Object { $_ -match '^ERROR: query: --db' } | Select-Object -First 1)
Check 'A1 exit 2' ($a.Code -eq 2) "exit=$($a.Code)"
Check 'A2 the ERROR line names the config file' ([bool]$aErr -and $aErr.Contains($cfgFile)) "[$aErr]"
Check 'A3 the ERROR line names the "db" key' ([bool]$aErr -and $aErr.Contains('"db" key')) "[$aErr]"

Write-Host 'B. CONTROL: a command-line --db names a missing file' -ForegroundColor Cyan
$b = RunIn $neutral @('query', '--name', 'Foo', '--db', $nope)
$bErr = (($b.Out -split "`r?`n") | Where-Object { $_ -match '^ERROR: query: --db' } | Select-Object -First 1)
Check 'B1 exit 2' ($b.Code -eq 2) "exit=$($b.Code)"
Check 'B2 ERROR line present, names no defaults file' ([bool]$bErr -and -not $bErr.Contains('.drag-lint.json')) "[$bErr]"
Check 'B3 keeps the explicit --db wording' ($b.Out -match 'An explicit --db must be an existing index')

Write-Host 'C. index --project from a folder whose defaults name the db' -ForegroundColor Cyan
$cfg2   = Join-Path $WorkDir 'cfgA'
New-Item -ItemType Directory -Force $cfg2 | Out-Null
$cfg2F  = Join-Path $cfg2 '.drag-lint.json'
Write-Ascii $cfg2F '{"db": "A.sqlite"}'
# 585d7a3d (4b-1, guard run_index_cwd_config_db_anchor.ps1): a CWD "db" key decides only a
# write UNDER that file's folder, so the project indexed here lives inside cfgA.
$projA = Join-Path $cfg2 'p'
New-Item -ItemType Directory -Force (Join-Path $projA 'sub') | Out-Null
Copy-Item (Join-Path $proj 'P.dpr') $projA
Copy-Item $u1 (Join-Path $projA 'sub')
$c = RunIn $cfg2 @('index', '--project', (Join-Path $projA 'P.dpr'))
$cl = @($c.Out -split "`r?`n")
$ci = [Array]::FindIndex($cl, [Predicate[string]]{ param($x) $x -match '^Database:\s' })
Check 'C1 exit 0, Database: A.sqlite' (($c.Code -eq 0) -and ($ci -ge 0) -and ($cl[$ci] -match '^Database:\s+A\.sqlite\s*$')) "exit=$($c.Code) [$(if ($ci -ge 0) { $cl[$ci] })]"
# stderr (the "(loaded defaults ...)" banner, the pipe notice) interleaves with stdout in
# the merged stream, so the source line is matched by content, not as the very next line.
$cSrc = @($cl | Where-Object { $_.Contains('"db" key of') -and $_.Contains($cfg2F) }) | Select-Object -First 1
Check 'C2 a line names the defaults file as the source of the db' ([bool]$cSrc) "[$cSrc]"

Write-Host 'D. CONTROL: the same index with a command-line --db' -ForegroundColor Cyan
$d = RunIn $cfg2 @('index', '--project', (Join-Path $proj 'P.dpr'), '--db', (Join-Path $WorkDir 'd.sqlite'))
Check 'D1 exit 0, no line names the defaults file as the db source' (($d.Code -eq 0) -and ($d.Out -notmatch '"db" key of')) "exit=$($d.Code)"

# A folder whose defaults file has a wrong-typed docs key.
$bad = Join-Path $WorkDir 'cfgbad'
New-Item -ItemType Directory -Force $bad | Out-Null
Write-Ascii (Join-Path $bad '.drag-lint.json') '{"docs": {"captureLooseComments": "yes"}}'
$before = (Get-FileHash $u1).Hash

Write-Host 'E. broken defaults + document --apply' -ForegroundColor Cyan
$e = RunIn $bad @('document', '--unit', $u1, '--db', $goodDb, '--apply')
Check 'E1 exit 2' ($e.Code -eq 2) "exit=$($e.Code)"
Check 'E2 refusing to write' ($e.Out -match 'document: refusing to write')
Check 'E3 unit unchanged' ((Get-FileHash $u1).Hash -eq $before)

Write-Host 'F. broken defaults + lint --fix --apply' -ForegroundColor Cyan
$f = RunIn $bad @('lint', $u1, '--db', $goodDb, '--fix', '--apply')
Check 'F1 exit 2' ($f.Code -eq 2) "exit=$($f.Code)"
Check 'F2 refusing to write' ($f.Out -match 'lint: refusing to write')

Write-Host 'G. CONTROL: broken defaults + document dry run' -ForegroundColor Cyan
$g = RunIn $bad @('document', '--unit', $u1, '--db', $goodDb)
Check 'G1 not refused (exit 0)' (($g.Code -eq 0) -and ($g.Out -notmatch 'refusing to write')) "exit=$($g.Code)"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
