<#
  run_serve_multidb_warning_guard.ps1 -- `serve` uses only the FIRST --db, and
  must SAY SO when it is given more than one.

  THE DEFECT THIS PINS:
    TMCPServer.Create takes an ARRAY of db paths and opens FDbPaths[0]. The
    others are accepted, held, and silently ignored:

        if Length(FDbPaths) > 0 then
          FStore := TSQLiteSymbolStore.Create(FDbPaths[0]);

    So `drag-lint serve --db A --db B` answers every question from A while
    looking, from the caller's side, exactly like a server that searched both.
    An MCP client asking "who calls X" gets a confident, complete-looking answer
    computed over half its configured corpus.

    This is the same class as the stale-index hazard the repo already records --
    a wrong answer that renders as a plausible one -- except here the engine has
    the information needed to warn and simply does not.

  WHY A WARNING AND NOT MULTI-DB SUPPORT: honesty is a one-line fix; real
  multi-DB at MCP call time is a feature with its own design. Shipping the
  warning first means nobody builds on a false premise in the meantime, and
  `docs\editors\vscode-and-zed-mcp.md` stops saying the behaviour is
  "not verified" when it is now measured.

  CONTROLS:
    * ONE --db must produce NO such warning. Without this the assertion below
      passes for a build that warns unconditionally, which would be noise on
      every single-DB serve -- i.e. the overwhelming majority of real use.
    * The warning must NAME the ignored DB, not just say "extra databases".
      A warning that does not say WHICH is one the reader cannot act on.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-serve-multidb"
)
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
New-Item -ItemType Directory $WorkDir | Out-Null

# Two real, distinct indexes. Built by indexing two one-unit trees, so both are
# genuine databases rather than empty files -- an empty file could be rejected
# for a reason that has nothing to do with the multi-DB path.
foreach ($n in @('alpha', 'beta')) {
  $d = Join-Path $WorkDir $n
  New-Item -ItemType Directory $d | Out-Null
  $body = "unit u$n;" + [char]10 + "interface" + [char]10 + "implementation" + [char]10 +
          "procedure P$n; begin end;" + [char]10 + "end." + [char]10
  [System.IO.File]::WriteAllText((Join-Path $d "u$n.pas"),
    (($body -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [' + [char]10 +
  '    { "name": "SecAlpha", "db": "alpha.sqlite", "include": ["alpha"] },' + [char]10 +
  '    { "name": "SecBeta",  "db": "beta.sqlite",  "include": ["beta"]  } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)

$dbA = Join-Path $WorkDir 'out\alpha.sqlite'
$dbB = Join-Path $WorkDir 'out\beta.sqlite'

$emptyIn = Join-Path $WorkDir 'empty.in'
[System.IO.File]::WriteAllText($emptyIn, '', [System.Text.Encoding]::ASCII)

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $dbA) -or -not (Test-Path $dbB)) {
    Write-Host "FATAL: index did not produce both DBs" -ForegroundColor Red; exit 2
  }

  # `serve` is a stdin protocol server: it would sit until the timeout if left
  # alone. Feed it EOF immediately -- the warning is emitted in Create, before
  # any request is read, so an empty session is enough to observe it.
  $errTwo = Join-Path $WorkDir 'two.err'
  $errOne = Join-Path $WorkDir 'one.err'
  $p = Start-Process -FilePath $Exe -ArgumentList @('serve', '--db', $dbA, '--db', $dbB) `
         -RedirectStandardInput $emptyIn -RedirectStandardError $errTwo `
         -RedirectStandardOutput (Join-Path $WorkDir 'two.out') `
         -NoNewWindow -PassThru
  if (-not $p.WaitForExit(30000)) { try { $p.Kill($true) } catch { } }
  $two = if (Test-Path $errTwo) { Get-Content $errTwo -Raw } else { '' }

  $p = Start-Process -FilePath $Exe -ArgumentList @('serve', '--db', $dbA) `
         -RedirectStandardInput $emptyIn -RedirectStandardError $errOne `
         -RedirectStandardOutput (Join-Path $WorkDir 'one.out') `
         -NoNewWindow -PassThru
  if (-not $p.WaitForExit(30000)) { try { $p.Kill($true) } catch { } }
  $one = if (Test-Path $errOne) { Get-Content $errOne -Raw } else { '' }
}
finally { Pop-Location }

Write-Host ''
Write-Host 'Two --db flags: serve must admit it uses only the first' -ForegroundColor Cyan
Check 'a warning is emitted' `
  ($two -match '(?i)only the first|ignor') ("stderr: " + ($two -replace '\s+', ' '))
Check 'and it NAMES the ignored database' `
  ($two -match [regex]::Escape('beta.sqlite')) `
  'a warning that does not say WHICH db is one the reader cannot act on'

Write-Host ''
Write-Host 'POSITIVE CONTROL -- one --db must stay quiet' -ForegroundColor Cyan
Check 'a single --db produces no such warning' `
  (-not ($one -match '(?i)only the first|ignor')) `
  ("stderr: " + ($one -replace '\s+', ' '))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
