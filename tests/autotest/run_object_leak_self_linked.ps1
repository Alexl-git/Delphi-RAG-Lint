# Guard: a node that links itself into a structure is not a leak.
#
# docs\INBOX-object-leak-is-systematically-false.md -- the surviving cause,
# described there as "a tree cursor whose nodes escape via the returned root".
#
# `Cur := TGroup.Create(kind, i, k, Cur)` passes the variable being assigned as
# an ARGUMENT to its own constructor: the new node takes the old one as its
# parent, links itself into the tree, and is reachable from the root the routine
# returns -- so it is freed with the tree, not leaked.
#
# TEscape.Transfer already marked the variable transferred in its call-arg pass;
# the constructor branch two lines later overwrote that with "created", so the
# escape was computed and discarded within one statement. The fix keeps it.
#
# THE CONTROL IS THE WHOLE TEST. "the false finding is gone" is equally satisfied
# by object-leak switching off, so the same fixture holds a genuine leak that
# MUST still be reported, and an ordinary A := T.Create(B) that must still be
# treated as owned.
#
# Usage: pwsh -File tests/autotest/run_object_leak_self_linked.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-objleak-selflink"
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
unit uOL;
interface
type
  TNode = class
  public
    Parent: TNode;
    constructor Create(AParent: TNode);
  end;
function BuildTree(ACount: Integer): TNode;
function PlainLeak: TNode;
implementation
constructor TNode.Create(AParent: TNode);
begin
  Parent := AParent;
end;

// SELF-LINKING: cur is passed to its own constructor, so each node joins the
// tree rooted at Root, which is returned. Not a leak.
function BuildTree(ACount: Integer): TNode;
var
  Root, Cur: TNode;
  I: Integer;
begin
  Root := TNode.Create(nil);
  Cur := Root;
  for I := 0 to ACount - 1 do
    Cur := TNode.Create(Cur);
  Result := Root;
end;

// GENUINE LEAK: created, never freed, never transferred, never returned.
function PlainLeak: TNode;
var
  Temp, Other: TNode;
begin
  Other := TNode.Create(nil);
  Temp := TNode.Create(Other);
  Result := nil;
end;
end.
'@
$file = Join-Path $WorkDir 'uOL.pas'
[System.IO.File]::WriteAllText($file, (($Fixture -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$leaked = @([regex]::Matches($out, 'object-leak: Object "(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host ("  object-leak reported for: {0}" -f ($(if ($leaked) { $leaked -join ',' } else { '(none)' }))) -ForegroundColor DarkGray

# THE DEFECT -- the self-linked cursor is not a leak.
Check 'self-linked tree cursor is NOT reported' (-not ($leaked -contains 'cur'))

# CONTROL -- without this, object-leak simply switching off would pass above.
# `Temp := TNode.Create(Other)` is ALSO the "ordinary A := T.Create(B) is still
# owned" case: it takes another variable as its argument, is never passed on and
# never returned, so it must still be reported. One assertion covers both.
Check 'a genuine leak IS still reported' ($leaked -contains 'temp') `
    ("reported: " + ($leaked -join ','))

# PRE-EXISTING behaviour, pinned so this fix cannot be blamed for it later:
# `Other` is passed as an argument to Temp's constructor, so it is treated as
# TRANSFERRED (the callee may take ownership) and is not reported. That is not
# what this change did -- it was already true -- but an earlier draft of this
# test asserted the opposite and failed, so the expectation is recorded here
# rather than re-derived.
Check 'a var passed as a constructor ARG is treated as transferred' (-not ($leaked -contains 'other'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
