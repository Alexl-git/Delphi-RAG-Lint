# Guard: referenced-never-set must count a member CALL on a field as a WRITE.
#
# docs\INBOX-referenced-never-set-record-methods.md.
#
# THE DEFECT. The rule counted only ASSIGNMENTS to a field. A record-typed field
# mutated exclusively through its own methods -- FFanOut.Reset;, if
# FFanOut.Consider(x) then -- is never the lhs of an assignment, so writes
# stayed at zero and the field was reported "read but never written -- it always
# holds its zero value", which was the opposite of true.
#
# WHY THE FIX IS TYPE-AGNOSTIC, and this is the load-bearing point. The rule is
# SINGLE-FILE AST (Check(const AFile...), no store), and the filed case's record
# type TFanOutGate is declared in a DIFFERENT unit from the field. So "credit the
# call only when the receiver's type is a record declared here" would NOT have
# closed the filed case. A member call on a field is therefore a write whatever
# the field's type is. The accepted cost, stated so it is a decision and not a
# surprise: a class-typed FList.Add(x) where FList is never assigned stops being
# reported.
#
# THE NEGATIVE CONTROLS ARE THE POINT. "the false findings are gone" is equally
# satisfied by a rule that stopped firing at all, and a member READ (FRec.Count
# in value position) is exactly the shape that must NOT be credited or the rule
# loses its remaining reach.
#
# Usage: pwsh -File tests/autotest/run_referenced_never_set_record_methods.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-refnever-recmethods"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$Fixture = @'
unit uRNSRec;
interface
type
  TGate = record
  private
    FTicks: Integer;
  public
    procedure Reset;
    function Consider(APayload: Integer): Boolean;
    function Count: Integer;
  end;

  TOwner = class
  private
    FViaStmt: TGate;
    FViaCall: TGate;
    FViaSelf: TGate;
    FReadOnlyMember: TGate;
    FNeverSet: Integer;
  public
    constructor Create;
    function Tick: Boolean;
    function Total: Integer;
  end;
implementation

procedure TGate.Reset;
begin
  FTicks := 0;
end;

function TGate.Consider(APayload: Integer): Boolean;
begin
  FTicks := FTicks + APayload;
  Result := FTicks > 0;
end;

function TGate.Count: Integer;
begin
  Result := FTicks;
end;

constructor TOwner.Create;
begin
  inherited Create;
  FViaStmt.Reset;
  Self.FViaSelf.Reset;
end;

function TOwner.Tick: Boolean;
begin
  Result := FViaCall.Consider(1);
end;

function TOwner.Total: Integer;
begin
  Result := FReadOnlyMember.Count + FNeverSet;
end;

end.
'@

$file = Join-Path $WorkDir 'uRNSRec.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'referenced-never-set: Field "(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host ("  reported: {0}" -f ($(if ($hits) { $hits -join ',' } else { '(none)' }))) -ForegroundColor DarkGray

# THE DEFECT -- three shapes of "mutated through its own method".
Check 'a paren-less member call (FRec.Reset;) counts as a write'      (-not ($hits -contains 'FViaStmt'))
Check 'a member call in an expression (FRec.Consider(x)) is a write'  (-not ($hits -contains 'FViaCall'))
Check 'Self.FRec.Reset; counts as a write'                            (-not ($hits -contains 'FViaSelf'))

# NEGATIVE CONTROLS -- these must fire BEFORE and AFTER. Widening what counts as
# a write is exactly the change that can leave the rule unable to fire at all,
# and a member READ must stay a read or nothing dotted is ever reported again.
Check 'a member READ in value position is NOT a write'  ($hits -contains 'FReadOnlyMember')
Check 'a plain field nothing ever writes IS reported'   ($hits -contains 'FNeverSet')
Check 'exactly two findings remain'                     ($hits.Count -eq 2) ("got " + $hits.Count + ": " + ($hits -join ','))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }