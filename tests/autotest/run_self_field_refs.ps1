<#
  run_self_field_refs.ps1 -- Self.-qualified field reference regression test
  (Batch E / Task 4, ref-gap D).

  GAP: under deep indexing (usage refs on), `Self.client` (an exprDot node
  whose lhs base is the `Self` identifier) emitted a 'read' ref for the LHS
  base identifier `Self` only -- the RHS member `client` was never captured
  as a ref. This means field-name-prefix rename-at-use misses every
  Self.-qualified use site of a field.

  FIX: DRagLint.Parser.Delphi13.pas, Walk's NodeType='exprDot' case now also
  inspects ANode.ChildByField('rhs') and emits a 'read' ref for it, but ONLY
  when the lhs base identifier's text is (case-insensitively) 'Self'.

  THE CRITICAL GATE (over-capture guard): the fix must NOT become "emit a
  read for the rhs member of every exprDot". Ungated, that would flood the
  index with every `obj.Method` / `obj.Prop` member access anywhere in the
  codebase (those members are already captured elsewhere as call/type_use
  refs when relevant; re-emitting them here as generic 'read' refs was
  explicitly ruled out by the existing comment above the handler). This
  test's NEGATIVE assertions target exactly that risk: a non-Self dotted
  access (`other.Method(...)`) and a non-Self property access (`obj.Prop`)
  must gain NO new 'read' ref on their member name from this change.

  FIXTURE (built fresh in a temp workdir, indexed as a whole tree):
    u.pas -- unit u;
      type
        TOther = class
          Prop: Integer;
          procedure Method;
        end;
        TThing = class
          client: TOther;             <- field under test
          procedure Run(other: TOther; obj: TOther);
        end;
      implementation
      procedure TThing.Run(other: TOther; obj: TOther);
      var Y: TOther;
      begin
        Self.client := other;         <- Self.client WRITE-side dotted access
        Y := Self.client;             <- Self.client READ-side (POSITIVE, rhs of assignment)
        other.Method;                 <- non-Self dotted access (NEGATIVE)
        obj.Prop := 1;                <- non-Self dotted access (NEGATIVE)
      end;

  Note: `Self.client := other;` is itself an ASSIGNMENT whose LHS is an
  exprDot -- Walk's assignment case only special-cases a bare-identifier lhs,
  so the exprDot lhs recurses generically into the exprDot handler, which is
  exactly the path being fixed here. `Y := Self.client;` puts Self.client on
  the RHS, recursing into exprDot the same way.

  ASSERTIONS (direct refs-table queries via python's sqlite3 module -- same
  pattern as run_bare_rhs_refs.ps1):
    (a) POSITIVE: refs has >=1 row kind='read', name_text='client' whose
        start_line is one of the two Self.client use sites (not the field's
        own declaration line).
    (b) NEGATIVE (over-capture guard): refs has NO 'read' row for
        name_text='Method' or name_text='Prop' (the non-Self member names)
        anywhere in the file.

  BLAST-RADIUS (Step 5, run separately by the task but recorded here too):
  the refs COUNT delta introduced by this fix should equal exactly the
  number of new Self.member reads (2, for the two Self.client sites), with
  zero contribution from non-Self dotted member accesses.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-self-field-refs by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-self-field-refs-$PID"
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
  Self.client := other;
  Y := Self.client;
  other.Method;
  obj.Prop := 1;
end;

end.
'@

Write-Ascii (Join-Path $work 'u.pas') $UBody

$db = Join-Path $WorkDir 'selfField.sqlite'

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
Write-Host 'POSITIVE: Self.client sites gain a read ref for client' -ForegroundColor Cyan
$clientReads = @(Get-Refs 'client' 'read')
Check 'refs has >=1 read row for client' ($clientReads.Count -ge 1) `
  ("rows=" + ($clientReads | ConvertTo-Json -Compress))
if ($clientReads.Count -ge 1) {
  # The field's own declaration line ("client: TOther;") must not be the
  # source of this read -- it should come from the Self.client use sites in
  # TThing.Run (below the 'implementation' line).
  $declLineText = ($UBody -split "`r`n|`n") | Select-String -Pattern '^\s*client:\s*TOther;' | Select-Object -First 1
  $declLine = if ($declLineText) { $declLineText.LineNumber } else { -1 }
  $onDeclLine = $clientReads | Where-Object { $_.start_line -eq $declLine }
  Check 'client read row(s) are NOT on the field-declaration line' `
    ($null -eq $onDeclLine -or @($onDeclLine).Count -eq 0) `
    ("declLine=$declLine; rows=" + ($clientReads | ConvertTo-Json -Compress))
}
# Both Self.client USE SITES must be captured -- that is what rename-at-use
# needs. Until 2026-09-28 the write-side lhs was captured as a READ (the
# INBOX-self-qualified-field-write-indexed-as-read defect); extractor
# 1.20.0-alpha captures it as a WRITE. So: exactly one read (the rhs of
# `Y := Self.client`) and exactly one write (the lhs of `Self.client := other`),
# two sites in total -- the same coverage, each with its true kind.
$clientWrites = @(Get-Refs 'client' 'write')
Check 'the read-side Self.client (rhs) is captured as exactly ONE read' `
  ($clientReads.Count -eq 1) ("reads=" + ($clientReads | ConvertTo-Json -Compress))
Check 'the write-side Self.client (lhs) is captured as exactly ONE write' `
  ($clientWrites.Count -eq 1) ("writes=" + ($clientWrites | ConvertTo-Json -Compress))
Check 'both Self.client use sites captured (2 sites, read + write)' `
  (($clientReads.Count + $clientWrites.Count) -eq 2) ("reads=$($clientReads.Count) writes=$($clientWrites.Count)")

Write-Host ''
Write-Host 'NEGATIVE (over-capture guard): non-Self dotted member Method gained no spurious read' -ForegroundColor Cyan
$methodReads = @(Get-Refs 'Method' 'read')
Check 'refs has ZERO read rows for Method (non-Self access: other.Method)' ($methodReads.Count -eq 0) `
  ("rows=" + ($methodReads | ConvertTo-Json -Compress))

Write-Host ''
Write-Host 'NEGATIVE (over-capture guard): non-Self dotted member Prop gained no spurious read' -ForegroundColor Cyan
$propReads = @(Get-Refs 'Prop' 'read')
Check 'refs has ZERO read rows for Prop (non-Self access: obj.Prop)' ($propReads.Count -eq 0) `
  ("rows=" + ($propReads | ConvertTo-Json -Compress))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-self-field-refs-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
