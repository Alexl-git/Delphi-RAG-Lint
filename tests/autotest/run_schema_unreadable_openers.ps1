<#
.SYNOPSIS
  150 TL guard: read-only verbs that open an index through a bare TSQLiteSymbolStore.Create refuse
  an index BELOW SCHEMA_READ_MIN with the named reason instead of an access violation.

.DESCRIPTION
  150 SC made the constructor prepare its statements for every READABLE schema and routed the main
  openers through IsSchemaReadable; about 30 read-only sites (charts, menu-tree, forms-csv, unwith,
  multi-project rename, drift, MCP rename, JSON envelope probes) still called the bare constructor,
  so an index below READ_MIN left every prepared query nil and the first query was an AV.
  TL routes them through TSQLiteSymbolStore.CreateReadable (raises ESchemaUnreadable carrying
  SchemaUnreadableReason) or OpenReadable (nil + reason).

  Fixture (temp dir): AppU.Go calls LibU.TLibThing.Run, indexed by -Exe, then a copy stamped to
  READ_MIN - 1 (python stdlib sqlite3; missing python = FATAL, never a skip).
  Each O<n> check: the verb on the stamped copy prints 'older than this engine reads' and no
  access violation. Positive control: the 150 base build (no CreateReadable) fails O1..O4 with
  'EAccessViolation' or (O2..O4) a silent answer from the v22 index; O1 (charts) already refused on base
  through its GuardedDb stale-index check, which the guard accepts. Arm C (control): the same verbs on the CURRENT copy do not print the reason.
#>
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { Write-Host 'FATAL: python not found (needed to stamp an old schema_version)'; exit 2 }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("schemaop-" + [Guid]::NewGuid().ToString('N'))
$appDir = Join-Path $tmp 'app'
[IO.Directory]::CreateDirectory($appDir) | Out-Null
$script:Failed = $false

function Suo-Check([string]$Id, [bool]$Ok, [string]$What) {
  if ($Ok) { Write-Host "PASS $Id $What" } else { Write-Host "FAIL $Id $What"; $script:Failed = $true }
}
function Suo-Write([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Suo-Run([string[]]$CliArgs) {
  $o = & $exePath @CliArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Suo-Av([string]$Text) { return ($Text -match 'AccessViolation|Access violation') }

try {
  Suo-Write (Join-Path $appDir 'AppU.pas') @'
unit AppU;

interface

type
  TThing = class
  public
    procedure Run;
  end;

procedure Go;

implementation

procedure TThing.Run;
begin
end;

procedure Go;
var
  T: TThing;
begin
  T:= TThing.Create;
  with T do
    Run;
  T.Free;
end;

end.
'@
  Suo-Write (Join-Path $appDir 'App.dpr') @'
program App;

uses
  AppU in 'AppU.pas';

begin
  Go;
end.
'@
  $dpr = Join-Path $appDir 'App.dpr'
  $proj = Join-Path $tmp 'proj.sqlite'
  $r = Suo-Run @('index', '--project', $dpr, '--db', $proj)
  if ($r.Code -ne 0) { throw "project index exit $($r.Code)`n$($r.Out)" }

  $srcMin = [regex]::Match([IO.File]::ReadAllText((Join-Path $Repo 'src\storage\DRagLint.Storage.Schema.pas')), 'SCHEMA_READ_MIN\s*=\s*(\d+)\s*;')
  if (-not $srcMin.Success) { Write-Host 'FATAL: SCHEMA_READ_MIN not found in DRagLint.Storage.Schema.pas'; exit 2 }
  $old = [int]$srcMin.Groups[1].Value - 1

  $stamp = Join-Path $tmp 'stamp.py'
  [IO.File]::WriteAllText($stamp, @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("UPDATE schema_meta SET value = ? WHERE key = 'schema_version'", (sys.argv[2],))
c.commit()
c.close()
'@)
  $projU = Join-Path $tmp 'proj-u.sqlite'
  [IO.File]::Copy($proj, $projU, $true)
  & $py -I $stamp $projU "$old"
  if ($LASTEXITCODE -ne 0) { throw "stamp $projU v$old failed" }

  $verbs = @(
    @{ Id = 'O1'; Name = 'butterfly (Charts.Q.Butterfly)'; Args = @('butterfly', '--qname', 'AppU.Go', '--format', 'text') },
    @{ Id = 'O2'; Name = 'menu-tree (MenuTree)'; Args = @('menu-tree', '--project', $dpr) },
    @{ Id = 'O3'; Name = 'forms-csv (FormsMap)'; Args = @('forms-csv', '--project', $dpr, '--output', (Join-Path $tmp 'f.csv')) },
    @{ Id = 'O4'; Name = 'unwith --plan (Refactor.Unwith)'; Args = @('unwith', '--in', (Join-Path $appDir 'AppU.pas'), '--plan') }
  )
  foreach ($v in $verbs) {
    $r = Suo-Run ($v.Args + @('--db', $projU))
    $ok = (($r.Out -match 'older than this engine reads') -or (($v.Id -eq 'O1') -and ($r.Code -eq 2) -and ($r.Out -match 'A stale index is not authoritative'))) -and -not (Suo-Av $r.Out)
    Suo-Check $v.Id $ok "$($v.Name) on a v$old index: named reason, no AV (exit $($r.Code))"
    if (-not $ok) { ($r.Out -split "`n" | Select-Object -Last 4) | ForEach-Object { Write-Host "  | $_" } }
    $c = Suo-Run ($v.Args + @('--db', $proj))
    Suo-Check ("C" + $v.Id.Substring(1)) (-not ($c.Out -match 'older than this engine reads') -and -not (Suo-Av $c.Out)) "$($v.Name) on the current index: no refusal, no AV (exit $($c.Code))"
  }
}
finally {
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Verbose "temp dir left: $tmp" }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
