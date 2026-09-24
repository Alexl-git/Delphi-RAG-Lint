<#
  run_readonly_then_writer_same_process.ps1 -- a verb that holds a READ-ONLY
  store and then opens a WRITER on the same index in the SAME process must be
  able to write (batch C fix round 1, 2026-09-24).

  THE DEFECT. D25 made every reader SQLITE_OPEN_READONLY. FireDAC's static
  SQLite turns shared-cache mode on process-wide (FireDAC.Phys.SQLiteWrapper.
  Stat, InternalAfterLoad), so a connection with no SharedCache param joins the
  shared cache of any other connection to the same file in the process. A
  writer opened while a read-only connection was alive then shared that
  READ-ONLY cache, and its first write failed "attempt to write a readonly
  database". `document --project P.dpr --db P.sqlite --apply --reindex` holds
  its read-only store across the post-edit reindex, so it died with exit 3
  AFTER the source edits were written -- the index left stale. The deployed
  1.17.0 (read-write readers) exits 0 on the same fixture.

  THE FIX: ConnectReadOnly and ConnectWriter set SharedCache=False, so every
  drag-lint connection has a private cache, in-process exactly as cross-process.

  ASSERTS: the verb exits 0, prints no readonly-database error, wrote the
  managed block, left the index fresh (a second identical run is a no-op) and
  left the index WAL. POSITIVE CONTROL: the first run really changed the
  source -- a verb that did nothing would pass every other check.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "draglint-ro-then-writer-$PID")
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
try {
  function WriteAscii([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
  }
  WriteAscii (Join-Path $WorkDir 'P.dpr') @'
program P;

uses
  uA in 'uA.pas';

begin
  Bar;
end.
'@
  WriteAscii (Join-Path $WorkDir 'uA.pas') @'
unit uA;

interface

procedure Foo;
procedure Bar;

implementation

procedure Foo;
begin
end;

procedure Bar;
begin
  Foo;
end;

end.
'@
  $dpr = Join-Path $WorkDir 'P.dpr'
  $uA  = Join-Path $WorkDir 'uA.pas'
  $db  = Join-Path $WorkDir 'P.sqlite'
  & $Exe index --project $dpr --db $db *> $null
  Check 'setup: project index built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit $LASTEXITCODE"
  $before = (Get-FileHash $uA).Hash

  $out = (& $Exe document --project $dpr --db $db --apply --reindex 2>&1) -join "`n"
  $ec  = $LASTEXITCODE
  Check 'document --project --apply --reindex exits 0' ($ec -eq 0) "exit=$ec :: $out"
  Check 'no "readonly database" error' ($out -notmatch 'readonly database') $out
  Check 'POSITIVE CONTROL: the run really edited the source' ((Get-FileHash $uA).Hash -ne $before) ''
  Check 'the managed block was written' (([IO.File]::ReadAllText($uA)) -match 'drag-lint:auto BEGIN') ''

  $h = (Get-FileHash $uA).Hash
  $out2 = (& $Exe document --project $dpr --db $db --apply --reindex 2>&1) -join "`n"
  Check 'a second run exits 0' ($LASTEXITCODE -eq 0) $out2
  Check 'a second run is a no-op (the reindex left the index fresh)' ((Get-FileHash $uA).Hash -eq $h) ''
  Check 'the index is still WAL (header byte 18 = 2)' (([IO.File]::ReadAllBytes($db))[18] -eq 2) ''
} finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
