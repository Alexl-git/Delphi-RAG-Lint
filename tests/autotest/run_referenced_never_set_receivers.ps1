# Guard: referenced-never-set must count `Result.F := x` and `Self.F := x` as WRITES.
#
# docs\INBOX-referenced-never-set-false-positive-on-record-factories.md.
#
# LhsBaseIdent peels a dotted lhs to its LEFTMOST identifier, so
# `Result.FActive := True` credited the write to `Result` and `Self.FField := x`
# to `Self` -- neither is a field, so no write was recorded and the field was
# then reported "read but never written". Measured 2026-08-16: all three live
# findings on our own source were this shape (Project.OwnRoots.pas, a record
# factory) -- 100% false on the only population there was.
#
# THE POSITIVE CONTROL IS THE POINT. "the false findings are gone" is equally
# satisfied by a rule that stopped reporting, so a field that genuinely is never
# written MUST still fire in the same fixture.
#
# SCOPE, DELIBERATE: only `result` and `self` receivers are credited. Crediting
# the member of any dotted lhs would mis-attribute `SomeOther.FField := x` and
# silently suppress a real finding.
#
# KNOWN REMAINING GAP, asserted so it is visible rather than forgotten: the pass
# is CLASS-SCOPED, so `Result.FField := x` inside a STANDALONE function (not a
# method of the record) is still not seen. The real-world shape is a class
# function of the type itself, which is covered.
#
# Usage: pwsh -File tests/autotest/run_referenced_never_set_receivers.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-refnever-receivers"
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
unit uRNS;
interface
type
  TRec = record
  private
    FViaResult: Boolean;
    FViaSelf: Boolean;
    FNeverSet: Boolean;
  public
    class function Make: TRec; static;
    procedure Touch;
    function Read: Boolean;
  end;
implementation
class function TRec.Make: TRec;
begin
  Result.FViaResult := True;
end;
procedure TRec.Touch;
begin
  Self.FViaSelf := True;
end;
function TRec.Read: Boolean;
begin
  Result := FViaResult and FViaSelf and FNeverSet;
end;
end.
'@
$file = Join-Path $WorkDir 'uRNS.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'referenced-never-set: Field "(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host ("  reported: {0}" -f ($(if ($hits) { $hits -join ',' } else { '(none)' }))) -ForegroundColor DarkGray

# THE DEFECT -- both receiver forms are writes.
Check 'Result.F := x counts as a write (class function of the type)' (-not ($hits -contains 'FViaResult'))
Check 'Self.F := x counts as a write' (-not ($hits -contains 'FViaSelf'))

# POSITIVE CONTROL -- a field nothing ever writes MUST still be reported, or a
# rule that simply stopped firing would pass both arms above.
Check 'a genuinely never-written field IS still reported' ($hits -contains 'FNeverSet')
Check 'exactly one finding remains' ($hits.Count -eq 1) ("got " + $hits.Count)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
