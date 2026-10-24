<#
  run_lint_fp_rns_other_instance.ps1 -- referenced-never-set on a field written
  through ANOTHER INSTANCE of the same class (e3d W5 item 2).

  `pChild.FParent := Self` inside a TNode method writes TNode.FParent -- on the
  child, but it is the same field of the same class, and a private field is
  only reachable from this unit. The rule credited only `Result.` / `Self.`
  receivers, so FParent was reported "read but never written".

  Positive controls: a field of ANOTHER class that is written only through a
  TNode-typed receiver (`pNode.FParent := ..` inside a TOther method) must
  still be reported for TOther -- else the fix credits any dotted lhs by name;
  and a field read but never written at all must still be reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fp-rns-other-$PID"
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
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$src = @'
unit fprnsother;

interface

type
  TNode = class
  private
    FParent: TNode;
    FSibling: TNode;
    FNever: Integer;
  public
    procedure Adopt(pChild: TNode);
    procedure Link;
    function Depth: Integer;
  end;

  TOther = class
  private
    FParent: TNode;
  public
    procedure Steal(pNode: TNode);
    function Has: Boolean;
  end;

implementation

procedure TNode.Adopt(pChild: TNode);
begin
  pChild.FParent := Self;
end;

procedure TNode.Link;
var
  lPeer: TNode;
begin
  lPeer := TNode.Create;
  lPeer.FSibling := Self;
end;

function TNode.Depth: Integer;
begin
  Result := FNever;
  if FParent <> nil then Inc(Result);
  if FSibling <> nil then Inc(Result);
end;

procedure TOther.Steal(pNode: TNode);
begin
  pNode.FParent := nil;
end;

function TOther.Has: Boolean;
begin
  Result := FParent <> nil;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$unit = Join-Path $WorkDir 'fprnsother.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)

$out = (& $Exe lint $unit --rule referenced-never-set 2>$null | Out-String)

Write-Host 'False positives that must be GONE' -ForegroundColor Cyan
Check 'TNode.FParent written via a parameter of the same class is not reported' `
  (-not ($out -match 'fprnsother\.pas:8:')) ''
Check 'TNode.FSibling written via a local of the same class is not reported' `
  (-not ($out -match 'fprnsother\.pas:9:')) ''
Write-Host 'True positives that must SURVIVE' -ForegroundColor Cyan
Check 'TNode.FNever, read and never written, is still reported' `
  ($out -match 'fprnsother\.pas:10:') 'else the rule is off'
Check 'TOther.FParent, written only through a TNode receiver, is still reported' `
  ($out -match 'fprnsother\.pas:19:') 'else any dotted lhs is credited by name'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
