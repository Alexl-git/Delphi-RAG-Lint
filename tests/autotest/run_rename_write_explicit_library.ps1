<#
  run_rename_write_explicit_library.ps1 -- Q17 (owner 2026-11-19): a rename WRITE reads a library only when
  the library is passed EXPLICITLY (CLI --library-db <file>, MCP library_db). No implicit library for a write:
  not the manifest's platform library, not the library sections `serve` opened. Dry runs / --plan keep the
  default.

  FIXTURE: tests\fixtures\refactor\rename (RnTypes.TKid.AfterConstruction overrides a LIBRARY method; with the
  library the proof refuses [override-of-library], without it it cannot see the library ancestor). Miniature
  library = libstub\LibStub.pas.

  ASSERT
    CLI  1. --plan with --library-db         -> override-of-library (positive control: the library is read)
         2. --apply WITHOUT --library-db     -> NO override-of-library, and the stderr NOTE names the explicit rule
         3. --apply WITH --library-db        -> override-of-library again
    MCP  (serve --db app --db lib)
         5. dry_run=false WITHOUT library_db -> error does NOT say override-of-library (no served-library proof)
         6. dry_run=false WITH library_db    -> error says override-of-library
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-write-explicit-lib-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
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
$Fx = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\rename").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Run-Exe([string[]]$A) {
  $so = Join-Path $WorkDir 'o.txt'; $se = Join-Path $WorkDir 'e.txt'
  Start-Process $Exe -ArgumentList $A -WorkingDirectory $WorkDir -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  @{ Out = (Get-Content $so -Raw); Err = (Get-Content $se -Raw) }
}

# project copy + project DB + miniature library DB
$app = Join-Path $WorkDir 'app'; New-Item -ItemType Directory $app | Out-Null
foreach ($f in 'PrecRen.dpr', 'PrecRen.dproj', 'RnTypes.pas', 'RnUse.pas') { Copy-Item "$Fx\$f" $app }
$libDir = Join-Path $WorkDir 'lib'; New-Item -ItemType Directory $libDir | Out-Null
Copy-Item "$Fx\libstub\LibStub.pas" $libDir
$lib = Join-Path $WorkDir 'lib.sqlite'; $db = Join-Path $WorkDir 'app.sqlite'
$null = Run-Exe @('index', $libDir, '--db', $lib, '--library-db', 'none')
$null = Run-Exe @('index', '--project', (Join-Path $app 'PrecRen.dproj'), '--db', $db, '--library-db', 'none')
Check 'fixture DBs exist' ((Test-Path $lib) -and (Test-Path $db))
$Q = 'RnTypes.TKid.AfterConstruction'
$proj = Join-Path $app 'PrecRen.dproj'

Write-Host 'CLI' -ForegroundColor Cyan
$r1 = Run-Exe @('rename', '--kind', 'symbol', '--name', $Q, '--to', 'Born', '--db', $db, '--library-db', $lib, '--plan', '--json')
Check '1 plan with --library-db reads the library (override-of-library)' (("$($r1.Out)$($r1.Err)") -match 'override-of-library') "$($r1.Out)"
$r2 = Run-Exe @('rename', '--kind', 'symbol', '--name', $Q, '--to', 'Born', '--db', $db, '--project', $proj, '--apply', '--no-backup')
Check '2 apply without --library-db reads no library (2 not proved incl. no-library)' (("$($r2.Out)$($r2.Err)") -match '2 occurrence\(s\) not proved') "$($r2.Out)$($r2.Err)"
Check '2 apply without --library-db names the explicit rule on stderr' ("$($r2.Err)" -match 'explicit --library-db') "$($r2.Err)"
$r3 = Run-Exe @('rename', '--kind', 'symbol', '--name', $Q, '--to', 'Born', '--db', $db, '--library-db', $lib, '--project', $proj, '--apply', '--no-backup')
Check '3 apply with --library-db reads the library (override-of-library)' (("$($r3.Out)$($r3.Err)") -match 'override-of-library') "$($r3.Out)$($r3.Err)"

Write-Host 'MCP' -ForegroundColor Cyan
function Invoke-Mcp([string]$Args2) {
  $lines = @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"guard","version":"1"}}}',
             '{"jsonrpc":"2.0","method":"notifications/initialized"}',
             ('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"rename_symbol","arguments":{' + $Args2 + '}}}'))
  $req = Join-Path $WorkDir 'req.jsonl'
  [IO.File]::WriteAllText($req, ($lines -join "`n") + "`n", [Text.Encoding]::ASCII)
  $so = Join-Path $WorkDir 'm.txt'; $se = Join-Path $WorkDir 'm.err'
  Start-Process $Exe -ArgumentList 'serve', '--db', $db, '--db', $lib -WorkingDirectory $WorkDir `
    -RedirectStandardInput $req -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  foreach ($ln in (Get-Content $so)) {
    try { $o = $ln | ConvertFrom-Json | ForEach-Object { $_ } } catch { continue }
    if ($o.id -eq 2 -and $o.result) { return $o.result.content[0].text }
  }
  return ''
}
$base = '"qname":"' + $Q + '","to":"Born","project":"' + ($proj -replace '\\', '\\') + '"'
$libj = ($lib -replace '\\', '\\')
$m5 = Invoke-Mcp ($base + ',"dry_run":false')
# without a library the proof also refuses [no-library] (2 not proved); the served library would make it 1
Check '5 write without library_db: no served-library proof (2 not proved incl. no-library)' ($m5 -match '\(2 not proved\)') $m5
$m6 = Invoke-Mcp ($base + ',"dry_run":false,"library_db":"' + $libj + '"')
Check '6 write with library_db reads the library (1 not proved)' ($m6 -match 'override-of-library' -and $m6 -match '\(1 not proved\)') $m6

} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  $script:Failed = $true
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:Failed) { Write-Host 'run_rename_write_explicit_library: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_rename_write_explicit_library: PASS' -ForegroundColor Green
exit 0
