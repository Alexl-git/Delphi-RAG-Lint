<#
  run_self_member_receiver.ps1 -- the member of `Self.X` carries receiver 'Self'.

  DEFECT (N-05, docs\INBOX-self-qualified-member-no-receiver.md): ref-gap D
  emits the member of `Self.X` as a 'read' (and the assignment arm as a
  'write'), but receiver_text stayed NULL -- the column is only filled by the
  call stream, which never sees read/write rows. Inside `with P do`, a bare X
  binds to P while `Self.X` is the routine's own member, and the two rows were
  indistinguishable: DRagLint.Report.CycleEdge recovered the qualifier by
  scanning source text (which crosses lines and comments).

  POSITIVE CONTROL: the bare `InBuf` read in the with body keeps receiver NULL,
  and the call-stream member-access `P.Log` gets receiver 'P' as before.
  NO-REGRESSION: the kind of each Self-member row is unchanged (read / write).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-self-rcv-$PID"
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
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory -Force $work | Out-Null
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
# Line numbers below are asserted -- keep the fixture's layout stable.
Write-Ascii (Join-Path $work 'us.pas') @'
unit us;

interface

type
  TPort = class
    InBuf: Integer;
    Log: Integer;
  end;
  TConsumer = class
    InBuf: Integer;
    procedure Go(P: TPort);
  end;

implementation

procedure TConsumer.Go(P: TPort);
begin
  with P do
    Log := Self.InBuf + InBuf;
  Self.InBuf := P.Log;
end;

end.
'@
$db = Join-Path $WorkDir 'self.sqlite'
$io = & $Exe index $work --db $db --library-db none 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Q([string]$Sql) {
  $raw = & $Exe sql --db $db --json --query $Sql 2>$null | Out-String
  $j = $raw | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += [pscustomobject]$h
  }
  return ,$out
}
function RefAt([int]$Line, [int]$Col) {
  $rows = Q "select kind, name_text, coalesce(receiver_text,'<null>') rcv from refs where start_line=$Line and start_col=$Col"
  if ($rows.Count -ne 1) { return $null }
  return $rows[0]
}

Write-Host 'Positive controls' -ForegroundColor Cyan
$r = RefAt 20 25
Check 'control: bare InBuf in the with body has NULL receiver' ($r -and $r.name_text -eq 'InBuf' -and $r.rcv -eq '<null>') "got $($r.kind)/$($r.name_text)/$($r.rcv)"
$r = RefAt 21 19
Check "control: member-access P.Log has receiver 'P'" ($r -and $r.name_text -eq 'Log' -and $r.rcv -eq 'P') "got $($r.kind)/$($r.name_text)/$($r.rcv)"

Write-Host 'Self-qualified members' -ForegroundColor Cyan
$r = RefAt 20 17
Check "Self.InBuf read (with body) has receiver 'Self'" ($r -and $r.kind -eq 'read' -and $r.name_text -eq 'InBuf' -and $r.rcv -eq 'Self') "got $($r.kind)/$($r.name_text)/$($r.rcv)"
$r = RefAt 21 8
Check "Self.InBuf := (write) has receiver 'Self'" ($r -and $r.kind -eq 'write' -and $r.name_text -eq 'InBuf' -and $r.rcv -eq 'Self') "got $($r.kind)/$($r.name_text)/$($r.rcv)"
$r = RefAt 20 12
Check "the Self token itself stays a plain read, receiver NULL" ($r -and $r.kind -eq 'read' -and $r.name_text -eq 'Self' -and $r.rcv -eq '<null>') "got $($r.kind)/$($r.name_text)/$($r.rcv)"

if ($script:Failed) { Write-Host 'run_self_member_receiver: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_self_member_receiver: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
