<#
  run_member_access_refs.ps1 -- member-access-on-typed-receiver indexing RED test
  (ref-gap G, Task 1).

  GAP: today the parser does NOT emit any ref with kind='member-access'. A
  dotted access whose LHS is a plain (non-Self) typed identifier -- e.g.
  `Edit1.Prop` or `obj.Prop` -- has its RHS member name indexed only
  incidentally (or not at all) under existing kinds; there is no ref kind
  that specifically marks "member M accessed via a plain-identifier
  receiver", which is what a component-conversion applier needs to find
  instance-scoped access sites (e.g. rewrite `Edit1.Text` -> `cxEdit1.Text`)
  without touching `Self.`-qualified fields (ref-gap D territory) or
  call-receiver expressions (`GetX().Prop`, `TOther(x).Prop`).

  FIX (Task 2, SEPARATE + SUPERVISED, NOT this task): the parser will emit a
  NEW ref kind='member-access' for exprDot nodes whose lhs base is a plain
  identifier that is NOT 'Self', gated to exclude call-expression / typecast
  receivers.

  THIS TASK (Task 1) writes the RED test only. No parser change here.

  FIXTURE (built fresh in a temp workdir, indexed as a whole tree):
    u.pas -- unit u;
      type
        TOther = class
          Prop: Integer;
          procedure Method;
        end;
        TThing = class
          client: TOther;
          Edit1: TOther;
          procedure Run(other: TOther; obj: TOther);
        end;
      implementation
      procedure TOther.Method; begin end;
      procedure TThing.Run(other: TOther; obj: TOther);
      var Y: TOther;
      begin
        Edit1.Prop := 5;          <- member-access WRITE-side on Edit1.Prop
        Y := Edit1;               <- plain read of Edit1 (no member) -- NOT member-access
        obj.Prop := Edit1.Prop;   <- member-access on obj.Prop (write) AND Edit1.Prop (read)
        Self.client := other;     <- ref-gap D territory (Self.) -- NOT a NEW member-access
        other.Method;             <- member-access on other.Method? (method member) -- see note
      end;

  METHOD-MEMBER NOTE: `other.Method` is a dotted access whose rhs is a
  method, not a property/field. The gate as specified (lhs plain identifier,
  not Self, rhs plain identifier) WOULD emit a member-access ref for
  'Method' too -- property-vs-method disambiguation is NOT part of this
  gate; it is a query-time concern for a later batch. This test does NOT
  assert either presence or absence of a member-access row for 'Method' as
  a REQUIREMENT of the gate; on the CURRENT (pre-Task-2) exe no
  member-access kind exists at all, so this is moot for the RED. Once
  Task 2 ships, whatever the gate actually produces for 'Method' becomes
  the documented, accepted behavior -- not re-litigated here.

  ASSERTIONS (direct refs-table queries via python's sqlite3 module -- same
  pattern as run_self_field_refs.ps1 / run_bare_rhs_refs.ps1):
    POSITIVE (FAIL today -- this is the RED):
      (a) refs has >=1 row kind='member-access', name_text='Prop' whose
          start_line is one of the Edit1.Prop / obj.Prop use sites.
      (b) at least 3 such rows total (Edit1.Prop write, obj.Prop write,
          Edit1.Prop read on the same combined-statement line).
    NEGATIVE (over-capture guard -- pass trivially today, become real gates
    after Task 2):
      (c) NO member-access row for name_text='client' (Self.-qualified --
          excluded; ref-gap D already emits 'read' for this).
      (d) NO member-access row for name_text='Edit1' (bare identifier read,
          `Y := Edit1;` -- there is no member here at all).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-member-access-refs by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-member-access-refs"
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

type
  TOther = class
  public
    Prop: Integer;
    procedure Method;
  end;

  TThing = class
  public
    client: TOther;
    Edit1: TOther;
    procedure Run(other: TOther; obj: TOther);
  end;

implementation

procedure TOther.Method;
begin
end;

procedure TThing.Run(other: TOther; obj: TOther);
var
  Y: TOther;
begin
  Edit1.Prop := 5;
  Y := Edit1;
  obj.Prop := Edit1.Prop;
  Self.client := other;
  other.Method;
end;

end.
'@

Write-Ascii (Join-Path $work 'u.pas') $UBody

$db = Join-Path $WorkDir 'memberAccess.sqlite'

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
Write-Host 'POSITIVE (RED today): Edit1.Prop / obj.Prop sites gain a member-access ref for Prop' -ForegroundColor Cyan
$propMemberAccess = @(Get-Refs 'Prop' 'member-access')
Check 'refs has >=1 member-access row for Prop' ($propMemberAccess.Count -ge 1) `
  ("rows=" + ($propMemberAccess | ConvertTo-Json -Compress))
Check 'at least 3 member-access rows for Prop (Edit1.Prop write, obj.Prop write, Edit1.Prop read)' `
  ($propMemberAccess.Count -ge 3) ("rows=" + ($propMemberAccess | ConvertTo-Json -Compress))

Write-Host ''
Write-Host 'NEGATIVE (over-capture guard): Self.client gains NO member-access (ref-gap D territory, not this gate)' -ForegroundColor Cyan
$clientMemberAccess = @(Get-Refs 'client' 'member-access')
Check 'refs has ZERO member-access rows for client (Self.-qualified access)' ($clientMemberAccess.Count -eq 0) `
  ("rows=" + ($clientMemberAccess | ConvertTo-Json -Compress))

Write-Host ''
Write-Host 'NEGATIVE (over-capture guard): bare identifier read (Y := Edit1;) gains NO member-access' -ForegroundColor Cyan
$edit1MemberAccess = @(Get-Refs 'Edit1' 'member-access')
Check 'refs has ZERO member-access rows for Edit1 (bare identifier, no member)' ($edit1MemberAccess.Count -eq 0) `
  ("rows=" + ($edit1MemberAccess | ConvertTo-Json -Compress))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
