<#
  run_forward_stub_type_candidate.ps1 -- a forward declaration is not a second
  candidate for the call resolver's receiver typing.

  THE PROBLEM (evaluation on ProjectA, 2026-09-28). `TAppQuery = class;` at line 67
  of UPrimary.pas and `TAppQuery = class(...) ... end;` at line 1362 are TWO
  `class` rows with one qualified name. The readers (query, hover, outline, ...)
  fold the stub away (DRagLint.Core.ForwardStub), but the call resolver's
  candidate map (GetTypeCandidates) kept both, so every `vQ: TAppQuery` receiver
  saw two in-scope candidates and DECLINED: vQ.GraveParametro bound 3 times out
  of 35,813 references.

  THE FIX. GetTypeCandidates drops a row with the same test PairForwardStubs
  applies: a class/interface with empty heritage and no children, followed LATER
  in the same file by a row of the same kind and qualified name.

  CONTROLS, because folding too much is the failure that would look like a win:
    * two REAL same-named classes in two used units still decline;
    * a one-line class WITH heritage (`EOops = class(TObject);`) is a class, not
      a stub, and stays bindable (its call climbs to the ancestor's method).

  Usage: pwsh -File tests/callresolve/run_forward_stub_type_candidate.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_forward_stub_candidate_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The stub and its body in ONE unit, as in UPrimary.pas; a holder class
# between them is the reason the stub exists.
Write-Ascii (Join-Path $src 'uStub.pas') @'
unit uStub;

interface

type
  TQry = class;

  THolder = class
  public
    Q: TQry;
  end;

  TQry = class(TObject)
  public
    procedure Grave(const A: string);
  end;

  EOops = class(TQry);

procedure UseQry;
procedure UseOops;

implementation

procedure TQry.Grave(const A: string);
begin
end;

procedure UseQry;
var
  vQ: TQry;
begin
  vQ := TQry.Create;
  vQ.Grave('x');
end;

procedure UseOops;
var
  E: EOops;
begin
  E.Grave('y');
end;

end.
'@

# CONTROL: two REAL classes named TDup, in two units the caller uses.
foreach ($u in @('uDupA', 'uDupB')) {
  Write-Ascii (Join-Path $src "$u.pas") @"
unit $u;

interface

type
  TDup = class(TObject)
  public
    procedure Ping;
  end;

implementation

procedure TDup.Ping;
begin
end;

end.
"@
}
Write-Ascii (Join-Path $src 'uDupUser.pas') @'
unit uDupUser;

interface

procedure UseDup;

implementation

uses
  uDupA, uDupB;

procedure UseDup;
var
  D: TDup;
begin
  D.Ping;
end;

end.
'@

$db = Join-Path $WorkDir 'stub.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Callers([string]$Name) {
  $raw = (& $exePath query find-callers --name $Name --resolved --json --db $db 2>$null) -join "`n"
  try { return @(ConvertFrom-Json -InputObject $raw) } catch { return @() }
}

$py = Join-Path $WorkDir 'n.py'
Write-Ascii $py @'
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute("select count(*) from symbols where kind='class' and qualified_name='uStub.TQry'").fetchone()[0])
'@
$raw = (python $py $db) -join ''
Check 'precondition: symbols holds the stub AND the body (2 rows)' ($raw -eq '2') "rows=$raw -- with one row the stub never existed and the assertions below prove nothing"

$g = Callers 'Grave'
Check 'ASSERT: vQ: TQry types through the stub -- vQ.Grave binds' `
  (@($g | Where-Object { $_.caller_qname -eq 'uStub.UseQry' -and $_.target_qname -eq 'uStub.TQry.Grave' }).Count -eq 1) `
  "rows=$(($g | ForEach-Object { "$($_.caller_qname)->$($_.target_qname)[$($_.confidence)]" }) -join '; ')"
Check 'ASSERT: the binding is certain' (@($g | Where-Object { $_.caller_qname -eq 'uStub.UseQry' -and $_.confidence -eq 'certain' }).Count -eq 1) ''

$p = Callers 'Ping'
Check 'CONTROL: two REAL same-named classes in scope still decline' ($p.Count -eq 0) `
  "rows=$(($p | ForEach-Object { "$($_.caller_qname)->$($_.target_qname)" }) -join '; ')"

Check 'CONTROL: a one-line class WITH heritage is a class, not a stub (E.Grave climbs to TQry.Grave)' `
  (@($g | Where-Object { $_.caller_qname -eq 'uStub.UseOops' -and $_.target_qname -eq 'uStub.TQry.Grave' }).Count -eq 1) `
  "rows=$(($g | ForEach-Object { "$($_.caller_qname)->$($_.target_qname)" }) -join '; ')"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_forward_stub_candidate_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
