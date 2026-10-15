<#
  run_resolver_note_names_versions.ps1 -- the resolver freshness note names the
  product version and labels the resolver version as such (Gitea drag-lint#19,
  second occurrence, 2026-10-14).

  THE DEFECT. On an index whose edges came from an older resolver, every query
  printed

      resolver: edges were derived by r=1.18.0-alpha;schema=23, this build is r=1.19.0-alpha;schema=23

  while `--version` of the same exe said `drag-lint 1.18.0-alpha`. "this build
  is" put the RESOLVER fingerprint where a reader expects the product version,
  so the two outputs looked like two different builds.

  WHAT THIS ASSERTS, for the three notes (older stamp, newer stamp, no stamp):
    1. the note names the exact product version `--version` prints   <- THE FIX
    2. the note never says "this build is r=" / "this build (r="     <- THE FIX
    3. CONTROL: the note still carries both fingerprints (the stored one and
       the engine's), so the advice stays checkable

  RED-CHECK: against the pre-fix build 1 and 2 FAIL on all three notes; 3
  passes on both.

  Needs python (stdlib sqlite3) to age the stamp -- the `sql` verb is read-only.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_resolver_note_$PID"
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

$py = 'C:\Python314\python.exe'
if (-not (Test-Path $py)) { $pyCmd = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1; if ($pyCmd) { $py = $pyCmd.Source } }
if (-not (Test-Path $py)) {
  Write-Host 'SKIP: run_resolver_note_names_versions: no python found (C:\Python314, nor on PATH)' -ForegroundColor Yellow
  exit 77
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $src $name),
    ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Emit 'uCallee.pas' @'
unit uCallee;
interface
procedure Target;
implementation
procedure Target;
begin
end;
end.
'@

$db = Join-Path $WorkDir 'note.sqlite'

$pySet = Join-Path $WorkDir 'set.py'
[System.IO.File]::WriteAllText($pySet, @"
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
if sys.argv[2] == '-':
    c.execute("DELETE FROM schema_meta WHERE key='resolver_fingerprint'")
else:
    c.execute("UPDATE schema_meta SET value=? WHERE key='resolver_fingerprint'", (sys.argv[2],))
c.commit(); c.close()
"@, [System.Text.Encoding]::ASCII)

Write-Host ''
Write-Host 'run_resolver_note_names_versions -- the resolver note does not pass a fingerprint off as the product version' -ForegroundColor Cyan

Push-Location C:\TEMP
try {
  $verLine = (& $Exe --version 2>&1 | Select-Object -First 1 | Out-String).Trim()
  $product = if ($verLine -match '^drag-lint\s+(\S+)') { $Matches[1] } else { '' }
  Check '--version names a product version' ($product -ne '') $verLine

  & $Exe index $src --db $db 2>&1 | Out-Null
  Check 'the fixture indexed' (Test-Path $db) $db
  if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

  $cases = @(
    @{ Name = 'OLDER stamp'; Stamp = 'r=0.0.1-ancient;schema=21'; Want = 'r=0\.0\.1-ancient' },
    @{ Name = 'NEWER stamp'; Stamp = 'r=99.0.0-future;schema=23'; Want = 'r=99\.0\.0-future' },
    @{ Name = 'NO stamp';    Stamp = '-';                         Want = '' }
  )
  foreach ($c in $cases) {
    Write-Host ''
    Write-Host ("CASE {0}" -f $c.Name) -ForegroundColor Cyan
    & $py $pySet $db $c.Stamp 2>&1 | Out-Null
    $out  = & $Exe query --name Target --db $db --exact 2>&1 | Out-String
    $note = ($out -split "`r?`n" | Where-Object { $_ -match '^\s*resolver:' }) -join ' '
    Check 'a resolver note is printed' ($note -ne '') $note
    Check 'it names the product version --version prints' `
      ($product -ne '' -and $note.Contains("drag-lint $product")) `
      "want 'drag-lint $product' in: $note"
    Check 'it never calls the resolver fingerprint "this build"' `
      (-not ($note -match 'this build( is|\s*\()\s*r=')) $note
    Check 'CONTROL: it carries the engine''s resolver fingerprint' ($note -match 'r=\d+\.\d+\.\d+') $note
    if ($c.Want -ne '') {
      Check 'CONTROL: and the stored one' ($note -match $c.Want) $note
    }
  }
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\draglint_resolver_note_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
