<#
  run_bare_rhs_refs.ps1 -- bare-RHS-identifier read-ref regression test (Batch D
  / Task 4, the batch's RISK ITEM).

  BUG B: under deep indexing (usage refs on), `Result := maxItems;` emitted NO
  ref for `maxItems` -- a lone identifier that is the WHOLE RHS of an
  assignment fell through the ref-walk (Walk's 'assignment' case only emitted
  the LHS 'write' and then recursed; recursion never lands on a case that
  handles a bare identifier node, so the RHS read was silently dropped).

  FIX: DRagLint.Parser.Delphi13.pas, Walk's NodeType='assignment' case now
  also inspects ANode.ChildByField('rhs') and emits a 'read' ref when that
  field is itself a bare 'identifier' node.

  THE CRITICAL GATE (over-capture guard): the fix must NOT become a blanket
  "any identifier node is a read". Walk visits declaration-name identifiers
  (declVar/declProc/declType) and type-name identifiers (typeref) constantly;
  a blanket rule would spuriously mark every declaration/type reference as a
  'read'. This test's NEGATIVE assertion targets exactly that risk: a type
  name (TFoo) used only in contexts that are NOT a bare-identifier assignment
  RHS must gain NO new 'read' ref from this change.

  FIXTURE (built fresh in a temp workdir, indexed as a whole tree):
    u.pas -- unit u;
      const MaxItems = 10;
      type TFoo = class end;          <- TFoo: type name (negative control)
      var  Keeper: TFoo;               <- Keeper: var name (negative control,
                                           its OWN declaration must not read)
      procedure P;
      var r: Integer;
      begin
        r := MaxItems;                 <- bare RHS read of MaxItems (POSITIVE)
      end;

  ASSERTIONS (direct refs-table queries via python's sqlite3 module -- mirrors
  the pattern already used in run_readonly_verbs.ps1 / run_helper_edges.ps1;
  this is the crispest, most load-bearing check since it verifies the exact
  DB row the parser is responsible for emitting, independent of any later
  find-callers/impact filtering logic):
    (a) POSITIVE: refs has a row kind='read', name_text='MaxItems' at the
        `r := MaxItems;` site.
    (b) NEGATIVE (over-capture guard): refs has NO 'read' row for name_text
        ='TFoo' or name_text='Keeper' or name_text='MaxItems' at the const
        DECLARATION line itself (only the bare-RHS USE site should read).
    (c) find-callers --name MaxItems --json surfaces the P read site too
        (belt-and-braces on the consumer-facing surface, not just raw SQL).

  BLAST-RADIUS (Step 5, run separately by the task but recorded here too):
  index the SAME fixture directory twice -- once against a build WITHOUT the
  fix (not reproducible in this script; recorded in the task report from a
  before/after git-stash comparison) and once with -- the refs COUNT delta
  must equal exactly the number of new bare-RHS reads (1, for MaxItems) with
  zero contribution from declaration/type identifiers.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-bare-rhs-refs by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-bare-rhs-refs"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$UBody = @'
unit u;

interface

const
  MaxItems = 10;

type
  TFoo = class
  end;

var
  Keeper: TFoo;

procedure P;

implementation

procedure P;
var
  r: Integer;
begin
  r := MaxItems;
end;

end.
'@

Write-Ascii (Join-Path $work 'u.pas') $UBody

$db = Join-Path $WorkDir 'bareRhs.sqlite'

Write-Host 'Indexing fixture (deep usage refs on by default for a project index)' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

# --- direct refs-table assertions via python's sqlite3 module ---
$py = Join-Path $WorkDir 'refquery.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
name = sys.argv[2]
kind = sys.argv[3]
cur = c.execute(
    "SELECT name_text, kind, start_line, start_col FROM refs WHERE name_text = ? AND kind = ? ORDER BY start_line",
    (name, kind)
)
cols = [d[0] for d in cur.description]
rows = [dict(zip(cols, r)) for r in cur.fetchall()]
print(json.dumps(rows))
c.close()
'@ | Set-Content $py -Encoding ascii

function Get-Refs([string]$Name, [string]$Kind) {
  $raw = (python $py $db $Name $Kind) -join "`n"
  return ($raw | ConvertFrom-Json)
}

Write-Host ''
Write-Host 'POSITIVE: bare-RHS read of MaxItems (r := MaxItems;)' -ForegroundColor Cyan
$maxItemsReads = @(Get-Refs 'MaxItems' 'read')
Check 'refs has a read row for MaxItems' ($maxItemsReads.Count -ge 1) `
  ("rows=" + ($maxItemsReads | ConvertTo-Json -Compress))
if ($maxItemsReads.Count -ge 1) {
  # The read site is inside procedure P's body (line ~21 in the fixture,
  # `r := MaxItems;`), NOT the const declaration line (line 5). Assert it's
  # on the use line, not the decl line, to rule out a decl-identifier leak
  # disguised as a correct-looking row.
  $declLineText = ($UBody -split "`r`n|`n") | Select-String -Pattern '^\s*MaxItems\s*=' | Select-Object -First 1
  Check 'MaxItems read row is NOT on the const-declaration line' `
    ($maxItemsReads[0].start_line -gt 5) "start_line=$($maxItemsReads[0].start_line)"
}

Write-Host ''
Write-Host 'NEGATIVE (over-capture guard): TFoo (type name) gained no spurious read' -ForegroundColor Cyan
$tfooReads = @(Get-Refs 'TFoo' 'read')
Check 'refs has ZERO read rows for TFoo' ($tfooReads.Count -eq 0) `
  ("rows=" + ($tfooReads | ConvertTo-Json -Compress))

Write-Host ''
Write-Host 'NEGATIVE (over-capture guard): MaxItems const DECLARATION itself gained no read' -ForegroundColor Cyan
$maxItemsAllReads = @(Get-Refs 'MaxItems' 'read')
$declSelfRead = $maxItemsAllReads | Where-Object { $_.start_line -le 5 }
Check 'no MaxItems read row on/before the declaration line' ($null -eq $declSelfRead -or @($declSelfRead).Count -eq 0) `
  ("rows=" + ($maxItemsAllReads | ConvertTo-Json -Compress))

Write-Host ''
Write-Host 'NEGATIVE (over-capture guard): Keeper (var decl name) gained no spurious read' -ForegroundColor Cyan
$keeperReads = @(Get-Refs 'Keeper' 'read')
Check 'refs has ZERO read rows for Keeper (never used as a bare-RHS)' ($keeperReads.Count -eq 0) `
  ("rows=" + ($keeperReads | ConvertTo-Json -Compress))

# --- consumer-facing surface: find-callers also sees the new read ---
Write-Host ''
Write-Host 'find-callers --name MaxItems --json surfaces the bare-RHS read site' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $fcRaw = (& $Exe query find-callers --name MaxItems --db $db --json) -join "`n"
  $fcExit = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'find-callers --name MaxItems exits 0' ($fcExit -eq 0) "exit=$fcExit"
$fc = $null
try {
  $fc = $fcRaw | ConvertFrom-Json
} catch {
  Check 'find-callers --json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$fcRaw"
}
if ($null -ne $fc) {
  Check 'find-callers --json parses as JSON' $true
  $fcText = $fcRaw
  Check 'find-callers output mentions unit u (the read site''s unit)' ($fcText -match '(?i)\bu\b') "raw=$fcRaw"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
