# Guard: a store overwritten ONLY inside a following try body is LIVE on the
# exception path, and must not be called a dead store.
#
#     X := nil;                <- reported as a dead store
#     try
#       X := TObject.Create;   <- the only overwrite, INSIDE the try body
#     except
#       ...                    <- handler never mentions X
#     end;
#     R := X;                  <- X is read AFTER the try
#
# If the exception fires before `X := TObject.Create` completes, the read after
# the try sees the value from `X := nil`. So that store is live on the exception
# path and deleting it -- which is what the rule's advice says to do -- leaves an
# uninitialised object reference behind.
#
# WHY THE RULE GETS IT WRONG. `try..except` wires the handler edge from the END
# of the try body (Cfg.pas), modelling "the exception fired after the body's
# assignments ran". That edge is deliberate and tuned -- used-before-assignment
# depends on the state it carries -- so this is a SYNTACTIC guard scoped to the
# one wrong rule, exactly like its two siblings ProtectedByFollowingTry and
# ReleasesInterfaceRef, whose shared doc-comment already invites a third shape.
#
# NOT COVERED BY ProtectedByFollowingTry: that one requires the HANDLER to
# mention the name. Here the handler never does; the protection comes from where
# the OVERWRITE sits, not from what the handler says.
#
# THE TWO CONTROLS, both of which must keep firing:
#   * PPlainDead     -- an ordinary dead store with no try anywhere. Without it,
#                       switching overwrite-before-read off passes this file.
#   * PTryDeadNoRead -- overwritten inside a try but NEVER read after it. The
#                       exception path leads nowhere that observes the value, so
#                       the store really is dead and must still be reported. This
#                       is what stops the fix degenerating into "any store before
#                       a try is safe", which is the banned cheap version.
#
# Usage: pwsh -File tests/autotest/run_dead_store_overwritten_in_try.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir  = "$env:TEMP\drag-lint-deadstore-try"
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
unit uShapeF;

interface

procedure PTryLive;
procedure PPlainDead;
procedure PTryDeadNoRead;

implementation

procedure PTryLive;
var
  XT: TObject;
  RT: TObject;
begin
  XT := nil;
  try
    XT := TObject.Create;
  except
    Writeln('boom');
  end;
  RT := XT;
  if RT <> nil then RT.Free;
end;

procedure PPlainDead;
var
  XP2: Integer;
  RP2: Integer;
begin
  XP2 := 1;
  XP2 := 2;
  RP2 := XP2;
  Writeln(RP2);
end;

procedure PTryDeadNoRead;
var
  XN: Integer;
  RN: Integer;
begin
  XN := 1;
  try
    XN := 2;
    RN := XN;
    Writeln(RN);
  except
    Writeln('e');
  end;
end;

end.
'@
$file = Join-Path $WorkDir 'uShapeF.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$named = @([regex]::Matches($out, 'overwrite-before-read: Assignment to "(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host ("  reported: {0}" -f ($(if ($named) { $named -join ',' } else { '(none)' }))) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'CONTROLS -- both must keep firing' -ForegroundColor Cyan
Check 'an ordinary dead store IS reported (rule is on)' ($named -contains 'xp2') `
    ("reported: " + ($named -join ','))
Check 'overwritten in a try but NEVER read after IS still reported' ($named -contains 'xn') `
    ("reported: " + ($named -join ','))

Write-Host ''
Write-Host 'THE FIX -- live on the exception path' -ForegroundColor Cyan
Check 'a store overwritten only inside a following try, and read after it, is NOT reported' `
    (-not ($named -contains 'xt')) ("reported: " + ($named -join ','))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
