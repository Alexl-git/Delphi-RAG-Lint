#Requires -Version 7
<#
  run_context_via_callers_guard.ps1 -- `context` reports the sites that reach a
  method ONLY through the interface it implements, in BOTH formats (RB-5, 1.38).

  THE GAP. The markdown bundle gained "## Callers via interface dispatch
  (IFoo.Bar): N site(s)" with RB-5, but `context --format json` carried no
  trace of them: a JSON consumer saw caller_count and a resolution tally and
  could not tell a method reached through its interface from dead code.

  WHAT THIS PINS (inline fixture: TWorker.DoWork reached only via IWorker;
  TWorker.Direct called once through a class-typed receiver as the control)
    FC    find-callers --resolved --json: N via rows target TWorker.DoWork.
    CX1   context --format markdown: the via header says N site(s).
    CX2   context --format json: "via_dispatch" = [{via, kind, sites}] with
          via = IWorker.DoWork, kind = interface, sites = N.
    CX3   POSITIVE CONTROL: context --format json for TWorker.Direct has NO
          "via_dispatch" key (present only when non-empty, like impact's).

  Usage: pwsh -File tests\autotest\run_context_via_callers_guard.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-context-via-$PID"
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
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

WriteAnsi (Join-Path $src 'uViaWork.pas') @'
unit uViaWork;

interface

type
  IWorker = interface
    ['{6B1E2C30-0000-4000-8000-00000000C001}']
    procedure DoWork(const A: Integer);
  end;

  TWorker = class(TInterfacedObject, IWorker)
  public
    procedure DoWork(const A: Integer);
    procedure Direct;
  end;

implementation

procedure TWorker.DoWork(const A: Integer);
begin
end;

procedure TWorker.Direct;
begin
end;

end.
'@
WriteAnsi (Join-Path $src 'uViaUse.pas') @'
unit uViaUse;

interface

uses uViaWork;

procedure UseOne(const W: IWorker);
procedure UseTwo;
procedure UseClass(const C: TWorker);

implementation

procedure UseOne(const W: IWorker);
begin
  W.DoWork(1);
end;

procedure UseTwo;
var
  W: IWorker;
begin
  W:= TWorker.Create;
  W.DoWork(2);
end;

procedure UseClass(const C: TWorker);
begin
  C.Direct;
end;

end.
'@

$db = Join-Path $WorkDir 'via.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$IMPL  = 'uViaWork.TWorker.DoWork'
$IFACE = 'uViaWork.IWorker.DoWork'

$jraw = (& $Exe query find-callers --name DoWork --resolved --json --db $db 2>$null) -join "`n"
$fc = @($jraw.Substring($jraw.IndexOf('[')) | ConvertFrom-Json)
$N = @($fc | Where-Object { $_.target_qname -eq $IMPL -and $_.via -eq $IFACE }).Count
Check 'FC find-callers --resolved: N >= 1 via rows on TWorker.DoWork' ($N -ge 1) "N=$N"

$md = (& $Exe context --task "modify TWorker.DoWork" --db $db --format markdown 2>$null | Out-String)
Check 'CX1 markdown via header = N' ($md -like "*## Callers via interface dispatch (${IFACE}): $N site(s)*")

$js = (& $Exe context --task "modify TWorker.DoWork" --db $db --format json 2>$null | Out-String)
$o = $js.Substring($js.IndexOf('{')) | ConvertFrom-Json
$vd = @($o.via_dispatch)
Check 'CX2 json via_dispatch names IWorker.DoWork, kind interface, sites = N' `
  (($o.PSObject.Properties.Name -contains 'via_dispatch') -and ($vd.Count -eq 1) -and
   ($vd[0].via -eq $IFACE) -and ($vd[0].kind -eq 'interface') -and ([int]$vd[0].sites -eq $N)) $js.Trim()

$jd = (& $Exe context --task "modify TWorker.Direct" --db $db --format json 2>$null | Out-String)
$od = $jd.Substring($jd.IndexOf('{')) | ConvertFrom-Json
Check 'CX3 control: no via_dispatch key on a directly-called method' `
  (($od.resolved -eq $true) -and -not ($od.PSObject.Properties.Name -contains 'via_dispatch')) $jd.Trim()

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
}
