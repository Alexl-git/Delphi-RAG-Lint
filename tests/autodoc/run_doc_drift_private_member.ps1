<#
  run_doc_drift_private_member.ps1 -- doc-drift grades what the batch writer
  writes: EVERY interface-section member, private and protected included.

  THE DEFECT (INBOX-2026-09-28-converter-to-engine-doc-drift-misses-deleted-
  nested-callee). `document --unit/--project` writes managed facts blocks on
  every documentable INTERFACE-SECTION symbol (DRagLint.Doc.Batch -- a section
  test, no visibility test), so a form's private method gets one. doc-drift's
  population additionally dropped private and protected members
  (DocRules.IsPublicSymbol), so once that method's callees changed, its block
  went stale and NOTHING reported it: TConvRulesForm.RefreshUnitList kept a
  Calls: line naming a deleted routine through a whole review, while
  `document --qname` on the same symbol proposed the repair immediately.
  Measured on drag-lint's own self-index: 194 managed blocks on non-public
  members, every one of them invisible to the checker.

  The checker now uses the writer's own predicate. The SECTION half is kept:
  an implementation-only routine is outside both the batch writer and CDD's
  public-surface scope, and its hand-written prose is not drift.

    Part A  document --unit --apply writes a block on the PRIVATE method
            (non-vacuity: the population under test really is writer-covered)
    Part B  change the private method's callee, reindex -> doc-drift reports
            its stale facts block (RED before the fix)
    Part C  CONTROL: the implementation-only routine's stale <param> is NOT
            reported -- the section half of the scope still holds
    Part D  lint-all --fix --apply repairs it and a second lint-all is clean
            for that method -- checker and fixer share one population

  Usage: pwsh -File tests\autodoc\run_doc_drift_private_member.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
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

$W = Join-Path $env:TEMP "drag-lint-drift-private-$PID"
if (Test-Path $W) { Remove-Item -Recurse -Force -LiteralPath $W }
New-Item -ItemType Directory $W | Out-Null
$Pas = Join-Path $W 'uDriftPriv.pas'
$Db  = Join-Path $W 'drift.sqlite'

function Write-Ascii([string]$Path, [string]$Text) {
  $n = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $n, [System.Text.Encoding]::ASCII)
}
# lint-all --json prints progress text around ONE array; lint JSON uses start_line.
function Get-Findings {
  $raw = (& $Exe lint-all --db $Db --json 2>$null) -join "`n"
  $a = $raw.IndexOf('['); $b = $raw.LastIndexOf(']')
  if ($a -lt 0 -or $b -le $a) { return ,@() }
  return ,@(ConvertFrom-Json $raw.Substring($a, $b - $a + 1))
}
# First line of the /// block directly above a 1-based declaration line.
function DocStartAbove([int]$DeclLine) {
  $ls = [IO.File]::ReadAllLines($Pas); $i = $DeclLine - 2
  while ($i -ge 0 -and $ls[$i].TrimStart().StartsWith('///')) { $i-- }
  return $i + 2
}
function LineOf([string]$Pattern) {
  (Select-String -LiteralPath $Pas -Pattern $Pattern | Select-Object -First 1).LineNumber
}

Write-Ascii $Pas @'
unit uDriftPriv;

interface

type
  TFoo = class
  private
    /// <summary>Refreshes the list.</summary>
    procedure RefreshList;
    function Helper: Integer;
    function Other: Integer;
  public
    procedure Run;
  end;

implementation

/// <summary>Implementation-only; its prose is not on the documented surface.</summary>
/// <param name="Z">A parameter this routine does not have.</param>
procedure ImplOnly(A: Integer);
begin
  if A > 0 then Exit;
end;

function TFoo.Helper: Integer;
begin
  Result := 1;
end;

function TFoo.Other: Integer;
begin
  Result := 2;
end;

procedure TFoo.RefreshList;
begin
  if Helper > 0 then ImplOnly(1);
end;

procedure TFoo.Run;
begin
  RefreshList;
end;

end.
'@

Push-Location $W
try {
  & $Exe index $W --db $Db 2>$null | Out-Null

  # ---- Part A: the batch writer covers the private method ------------------
  & $Exe document --unit $Pas --db $Db --apply --no-backup 2>$null | Out-Null
  $src = [IO.File]::ReadAllText($Pas)
  $declLine = LineOf '^\s*procedure RefreshList;'
  $lines = [IO.File]::ReadAllLines($Pas)
  $above = ($lines[0..($declLine - 2)] -join "`n")
  $lastBlock = $above.LastIndexOf('drag-lint:auto BEGIN')
  $blockText = if ($lastBlock -ge 0) { $above.Substring($lastBlock) } else { '' }
  Check 'A: document --unit wrote a managed block on the PRIVATE RefreshList' ($blockText -ne '')
  Check 'A: ...whose Calls: line names its callee Helper' ($blockText -match 'Calls:[^<]*Helper') "block=[$($blockText -replace '\s+',' ')]"

  # ---- Part B: the callee changes; the block is now stale ------------------
  $src = [IO.File]::ReadAllText($Pas)
  $src = $src.Replace('if Helper > 0 then ImplOnly(1);', 'if Other > 0 then ImplOnly(1);')
  Write-Ascii $Pas $src
  & $Exe index $W --db $Db 2>$null | Out-Null
  # doc-drift anchors at the FIRST LINE OF THE DOC COMMENT, not the declaration.
  $declLine = LineOf '^\s*procedure RefreshList;'
  $docLine  = DocStartAbove $declLine
  $helpDoc  = DocStartAbove (LineOf '^\s*function Helper: Integer;')
  $f = Get-Findings
  $drift = @($f | Where-Object { $_.rule -eq 'doc-drift' -and [int]$_.start_line -eq [int]$docLine })
  Check 'B: doc-drift reports the stale block on the private method' ($drift.Count -ge 1) `
    ("docLine=$docLine; doc-drift lines: " + ((@($f | Where-Object { $_.rule -eq 'doc-drift' }) | ForEach-Object { $_.start_line }) -join ','))
  # Helper lost its only caller, so its private block's Called from: is stale too.
  Check 'B: ...and on private Helper, whose Called from: changed' (@($f | Where-Object { $_.rule -eq 'doc-drift' -and [int]$_.start_line -eq [int]$helpDoc }).Count -ge 1)

  # ---- Part C: the section half still holds --------------------------------
  $implLine = LineOf '^procedure ImplOnly\('
  $implHits = @($f | Where-Object { $_.rule -like 'doc-*' -and [int]$_.start_line -eq [int]$implLine })
  Check 'C: CONTROL: the implementation-only routine is not graded' ($implHits.Count -eq 0) `
    (($implHits | ForEach-Object { "$($_.rule)@$($_.start_line)" }) -join ',')
  Check 'C: non-vacuity: lint-all produced findings at all' ($f.Count -gt 0)

  # ---- Part D: the fixer shares the population ------------------------------
  & $Exe lint-all --db $Db --fix --apply --no-backup 2>$null | Out-Null
  & $Exe index $W --db $Db 2>$null | Out-Null
  $declLine = LineOf '^\s*procedure RefreshList;'
  $lines = [IO.File]::ReadAllLines($Pas)
  $above = ($lines[0..($declLine - 2)] -join "`n")
  $lastBlock = $above.LastIndexOf('drag-lint:auto BEGIN')
  $blockText = if ($lastBlock -ge 0) { $above.Substring($lastBlock) } else { '' }
  Check 'D: --fix rewrote the Calls: line to name Other' ($blockText -match 'Calls:[^<]*Other') "block=[$($blockText -replace '\s+',' ')]"
  Check 'D: ...and it no longer names Helper' ($blockText -notmatch 'Calls:[^<]*Helper')
  $docLine = DocStartAbove $declLine
  $f2 = Get-Findings
  $drift2 = @($f2 | Where-Object { $_.rule -eq 'doc-drift' -and [int]$_.start_line -eq [int]$docLine })
  Check 'D: a second lint-all reports no drift on RefreshList' ($drift2.Count -eq 0)
} finally {
  Pop-Location
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0

} finally {
  if ($W -and (Test-Path -LiteralPath $W)) { Remove-Item -LiteralPath $W -Recurse -Force -ErrorAction SilentlyContinue }
}
