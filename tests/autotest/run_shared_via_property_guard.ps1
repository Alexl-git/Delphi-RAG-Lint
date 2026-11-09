#Requires -Version 7
<#
  run_shared_via_property_guard.ps1 -- 'Used in (via property X):' is an INBOUND fact on a
  dl:shared unit (wave 149 lane LX, UP 149 row: "add 'Used in (via property X):' to
  ProjectTags.INBOUND_LABELS with label parsing of the variable part").

  THE GAP (148 UP REPORT, assumption). Wave 148 gave a getter / setter one line per property it
  serves, 'Used in (via property Value): <routine> (<file>) [r]'. The entries name the routines
  that read the property -- as project-dependent as 'Called from:' -- but the label was only a
  block boundary, not an inbound label: on a unit two projects compile (dl:shared) each
  project's `document` REPLACED the line with what it alone can see, so the line flipped
  between projects and doc-drift never settled. The fixed inbound labels merge instead (the
  owner's option 1, run_shared_unit_staleness): the writer unions the stored entries it cannot
  see, tags its own with [Project], the checker forgives the other project's.

  The label has a VARIABLE part (the property name), so it is matched as the fixed prefix
  'Used in (via property ' plus the name up to '):' -- one inbound key per property.

  FIXTURE: shared\MarkProv.pas (dl:shared ProjA, ProjB) TProvider.GetValue reads FValue and is
  the read accessor of property Value and of property Twin (two via lines on one routine);
  a\AUse.pas reads P.Value (A only); b\BUse.pas reads P.Value and P.Twin (B only).
  Checks:
    V1  A documents: GetValue's via line names AUse.
    V2  B documents: the via line KEEPS AUse (the merge) and gains BUse.
    V3  A adopts once: both entries tagged, [A]AUse... and [B]BUse...; the Twin line (only B
        renders it) is kept by A's write, not dropped.
    V4  neither project sees doc-drift on MarkProv afterwards; neither writes again.
    C1  POSITIVE CONTROL (the merge is not 'keep everything'): A stops reading P.Value -> A sees
        doc-drift, and A's write REAPS its own [A]AUse entry while B's [B]BUse stays.
  (PlainProv, unmarked, is documented too: both projects' ownRoots hold ..\shared, so it
  participates and merges exactly like the marked unit -- measured, not assumed.)
  RED on 1.48.0-alpha (the via label is not inbound): V2 / V3 / V4 fail.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-shared-via-$PID"
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
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$RunStart = Get-Date
$StrayReport = Join-Path (Get-Location).Path ('lint-report-' + (Get-Date -Format 'yyyyMMdd') + '.txt')
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$shDir = Join-Path $WorkDir 'shared'
$aDir  = Join-Path $WorkDir 'a'
$bDir  = Join-Path $WorkDir 'b'
foreach ($d in $shDir, "$aDir\_D-RAG", "$bDir\_D-RAG") { New-Item -ItemType Directory $d -Force | Out-Null }

function New-Prov([string]$Name, [bool]$Marked) {
  $mark = if ($Marked) { '   // dl:shared ProjA, ProjB' } else { '' }
  Write-Ascii (Join-Path $shDir "$Name.pas") @"
unit $Name;$mark

interface

type
  TProvider = class
  private
    FValue: Integer;
  public
    function GetValue: Integer;
    property Value: Integer read GetValue;
    property Twin: Integer read GetValue;
  end;

implementation

function TProvider.GetValue: Integer;
begin
  Result:= FValue;
end;

end.
"@
}
New-Prov 'MarkProv'  $true
New-Prov 'PlainProv' $false

function New-User([string]$Dir, [string]$Unit, [string]$Body) {
  Write-Ascii (Join-Path $Dir "$Unit.pas") @"
unit $Unit;

interface

uses MarkProv, PlainProv;

function UseIt(const P: MarkProv.TProvider; const Q: PlainProv.TProvider): Integer;

implementation

function UseIt(const P: MarkProv.TProvider; const Q: PlainProv.TProvider): Integer;
begin
$Body
end;

end.
"@
}
New-User $aDir 'AUse' '  Result:= P.Value + Q.Value;'
New-User $bDir 'BUse' '  Result:= P.Value + P.Twin + Q.Value;'
Write-Ascii "$aDir\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".", "../shared"] }'
Write-Ascii "$bDir\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".", "../shared"] }'
$dbA = "$aDir\_D-RAG\A.sqlite"
$dbB = "$bDir\_D-RAG\B.sqlite"

function Reindex([string]$Db, [string[]]$Dirs) { foreach ($d in $Dirs) { & $Exe index $d --db $Db 2>&1 | Out-Null } }
function ReindexBoth { Reindex $dbA @($shDir); Reindex $dbB @($shDir) }
function DocApply([string]$Db, [string]$Unit) { & $Exe document --unit (Join-Path $shDir "$Unit.pas") --db $Db --apply --no-backup 2>$null | Out-Null }
function DocEditCount([string]$Db, [string]$Unit) {
  $o = ((& $Exe document --unit (Join-Path $shDir "$Unit.pas") --db $Db 2>$null) -join "`n") -replace '</?para>', ''
  if ($o -match 'decl\(s\)[^,]*,\s*(\d+)\s*edit\(s\)') { return [int]$Matches[1] }
  if ($o -match 'nothing to document') { return 0 }
  return -1   # an output shape this guard does not know is a FAIL, never a silent 0
}
function DriftCount([string]$Db, [string]$Unit) {
  $o = & $Exe lint-all --db $Db --quiet --output (Join-Path (Split-Path $Db) 'lint-report.txt') 2>$null   # --output: lint-all otherwise drops lint-report-<date>.txt into the caller's cwd (150 LN item 5)
  return @($o | Select-String 'doc-drift' | Where-Object { $_.Line -match "\\$Unit\.pas:" }).Count
}
function ViaLine([string]$Unit, [string]$Prop) {
  $m = Select-String -Path (Join-Path $shDir "$Unit.pas") -SimpleMatch -Pattern "Used in (via property $Prop):" | Select-Object -First 1
  if ($m) { return ($m.Line -replace '</?para>', '').Trim() } else { return '' }
}

Reindex $dbA @($shDir, $aDir)
Reindex $dbB @($shDir, $bDir)
Check 'fixture indexed' ((Test-Path $dbA) -and (Test-Path $dbB))

DocApply $dbA 'MarkProv'; DocApply $dbA 'PlainProv'; ReindexBoth
$v1 = ViaLine 'MarkProv' 'Value'
Check 'V1 A wrote GetValue''s via line naming AUse' ($v1 -match 'AUse\.UseIt') "line: $v1"

DocApply $dbB 'MarkProv'; DocApply $dbB 'PlainProv'; ReindexBoth
$v2 = ViaLine 'MarkProv' 'Value'
Check 'V2 the merged via line KEEPS the other project''s AUse' ($v2 -match 'AUse\.UseIt') "line: $v2"
Check 'V2 the merged via line gains BUse' ($v2 -match 'BUse\.UseIt') "line: $v2"

DocApply $dbA 'MarkProv'; ReindexBoth
$v3 = ViaLine 'MarkProv' 'Value'
Check 'V3 adoption tags both: [A]AUse.UseIt and [B]BUse.UseIt' (($v3 -match '\[A\]AUse\.UseIt') -and ($v3 -match '\[B\]BUse\.UseIt')) "line: $v3"
$tw = ViaLine 'MarkProv' 'Twin'
Check 'V3 the second via line (Twin, only B renders it) is kept by A''s write' ($tw -match 'BUse\.UseIt') "line: $tw"
Check 'V4 A sees no doc-drift on MarkProv' ((DriftCount $dbA 'MarkProv') -eq 0)
Check 'V4 B sees no doc-drift on MarkProv' ((DriftCount $dbB 'MarkProv') -eq 0)
Check 'V4 idempotent under A' ((DocEditCount $dbA 'MarkProv') -eq 0)
Check 'V4 idempotent under B' ((DocEditCount $dbB 'MarkProv') -eq 0)

# C1: A stops reading P.Value -- its tagged entry is A's to reap, B's stays.
New-User $aDir 'AUse' '  Result:= Q.Value;'
Reindex $dbA @($aDir, $shDir)
Check 'C1 A sees doc-drift once its own use is gone' ((DriftCount $dbA 'MarkProv') -gt 0)
DocApply $dbA 'MarkProv'; ReindexBoth
$c1 = ViaLine 'MarkProv' 'Value'
Check 'C1 A''s write reaps [A]AUse and keeps [B]BUse' (($c1 -match '\[B\]BUse\.UseIt') -and ($c1 -notmatch 'AUse')) "line: $c1"

Check 'S1 no stray lint-report-<date>.txt written into the caller cwd' (-not ((Test-Path $StrayReport) -and ((Get-Item $StrayReport).LastWriteTime -ge $RunStart))) $StrayReport
if ($script:Failed) { Write-Host 'run_shared_via_property_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_shared_via_property_guard: PASS' -ForegroundColor Green
exit 0
} finally {
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
