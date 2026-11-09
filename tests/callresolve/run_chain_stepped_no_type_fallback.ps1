<#
  run_chain_stepped_no_type_fallback.ps1 -- wave-146 b8 leftover (149 RB2 item 1): the kind-7
  unit-qualified TYPE rung of TypeReceiverCore took the LAST segment of a dotted receiver as a
  type name even after the kind-10 walk had stepped a member. `FW.Lost.Run`, with
  TWorker.Lost a parenless function of an unknown type, bound certain to Lost.Run because a
  class named Lost is in scope -- a wrong certain edge.

  THE FIX: once the walk stepped a member the chain is a value chain; its last segment is a
  member, never a unit-qualified type name, so the type rung does not run.

  Pins: A1 FW.Lost.Run has NO certain edge to uK7.Lost.Run. CONTROLS (green on both engines):
  A2 `uK7.Lost.Run` (unit-qualified type receiver: the head is a unit) binds uK7.Lost.Run;
  A3 `FW.Me.Run` (Me: TWorker, a typed member) binds uK7.TWorker.Run.
  POSITIVE CONTROL: on 1.48.0-alpha A1 is RED.
  Run from any CWD, pwsh 7. Pass -Exe with the engine under test.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_chain_stepped_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($dir,$name,$t){ [IO.File]::WriteAllText((Join-Path $dir $name), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

W $WorkDir 'uK7.pas' @'
unit uK7;
interface
type
  Lost = class
  public
    procedure Run;
  end;
  TWorker = class
  public
    Me: TWorker;
    function Lost: TNoSuchType;
    procedure Run;
  end;
  THolder = class
  private
    FW: TWorker;
  public
    procedure ViaLost;
    procedure ViaUnit;
    procedure ViaMe;
  end;
implementation
procedure Lost.Run; begin end;
function TWorker.Lost: TNoSuchType; begin end;
procedure TWorker.Run; begin end;
procedure THolder.ViaLost;
begin
  FW.Lost.Run;
end;
procedure THolder.ViaUnit;
begin
  uK7.Lost.Run;
end;
procedure THolder.ViaMe;
begin
  FW.Me.Run;
end;
end.
'@
W $WorkDir 'K7.dpr' @'
program K7;
uses
  uK7 in 'uK7.pas';
begin
end.
'@

$db = Join-Path $WorkDir 'k7.sqlite'
Push-Location C:\TEMP
& $exePath index --project (Join-Path $WorkDir 'K7.dpr') --db $db 2>&1 | Out-Null
Check 'V index built' (Test-Path $db) $db
$raw = & $exePath sql --db $db --json --limit 200 --query "SELECT r.receiver_text, r.name_text, coalesce(e.confidence,''), coalesce(s.qualified_name,'') FROM refs r LEFT JOIN call_edges e ON e.ref_id = r.id LEFT JOIN symbols s ON s.id = e.target_symbol_id WHERE r.kind = 'call' AND r.name_text = 'Run'" | Out-String
Pop-Location
$j = $raw | ConvertFrom-Json
$rows = foreach ($r in $j.rows) { [pscustomobject]@{ Rcv=[string]$r[0]; Name=[string]$r[1]; Conf=[string]$r[2]; Target=[string]$r[3] } }
Check "V the three Run sites were read ($(@($rows).Count))" (@($rows).Count -eq 3) $raw
function Site($rcv){ @($rows | Where-Object { $_.Rcv -eq $rcv }) | Select-Object -First 1 }

$s = Site 'FW.Lost'
Check "A1 FW.Lost.Run is NOT bound to the type Lost (got '$($s.Conf) $($s.Target)')" ($null -ne $s -and $s.Target -ne 'uK7.Lost.Run')
$s = Site 'uK7.Lost'
Check "A2 CONTROL uK7.Lost.Run (unit-qualified type) -> certain uK7.Lost.Run (got '$($s.Conf) $($s.Target)')" ($null -ne $s -and $s.Conf -eq 'certain' -and $s.Target -ceq 'uK7.Lost.Run')
$s = Site 'FW.Me'
Check "A3 CONTROL FW.Me.Run (typed member) -> certain uK7.TWorker.Run (got '$($s.Conf) $($s.Target)')" ($null -ne $s -and $s.Conf -eq 'certain' -and $s.Target -ceq 'uK7.TWorker.Run')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
