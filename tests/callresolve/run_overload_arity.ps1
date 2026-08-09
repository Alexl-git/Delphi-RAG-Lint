<#
  run_overload_arity.ps1 -- a call binds to the overload with the matching
  ARGUMENT COUNT, not to whichever same-named candidate was scanned first.

  THE BUG (PLAN-autodoc-phaseC-2026-08-09, item B1; filed by YADF 2026-08-07)
  --------------------------------------------------------------------------------
  LookupMethodOnType matched candidates by NAME alone. When more than one
  matched it returned `First` -- the first in scan order -- and stamped the edge
  'ambiguous'. For an overload set that means the LOWEST-id declaration wins
  every call site regardless of how many arguments were actually passed.

  The filed case, YADF.Layout.pas:5589 -- a 2-arg delegator whose body calls the
  3-arg implementation:

      function FormatSource(const ASource: string; const AOpts: TYadfOptions): string;
      begin
        Result := FormatSource(ASource, AOpts, Reason);   // <- 3 arguments
      end;

  bound to the 2-ARG symbol, i.e. to itself. Two consequences, both visible in
  the generated docs: the delegator documents a phantom self-recursion
  ("Calls: YADF.Layout.FormatSource", "Called from: YADF.Layout.FormatSource"),
  and the 603-line function that IS the formatter records ZERO callers.

  Arity is enough to settle every case of this shape. What it deliberately does
  NOT settle is asserted too -- see the controls below -- because a fix that
  simply started claiming 'certain' would pass the positive checks alone.

  DEFAULT PARAMETERS mean a candidate accepts a RANGE of argument counts, not
  one, so the fit test is [required..declared]. A signature with defaults that
  was tested for equality would be filtered out by its own call sites.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-overload-arity"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Pick/1, Pick/2, Pick/3 mirror YADF's delegating chain. Blend/2 is the control:
# two overloads of the SAME arity differing only by parameter TYPE, which arity
# cannot decide and which must therefore stay uncertain. Fill has a DEFAULT
# parameter, so it accepts 1 or 2 arguments.
Write-Ascii (Join-Path $WorkDir 'arity.pas') @'
unit arity;

interface

function Pick(const A: string): string; overload;
function Pick(const A: string; const B: string): string; overload;
function Pick(const A, B, C: string): string; overload;

function Blend(const A: string): string; overload;
function Blend(const A: Integer): string; overload;

function Fill(const A: string; const B: Integer = 0): string;

procedure Drive;
procedure DriveMultiline;

implementation

function Pick(const A: string): string;
begin
  Result := Pick(A, '');
end;

function Pick(const A: string; const B: string): string;
begin
  Result := Pick(A, B, '');
end;

function Pick(const A, B, C: string): string;
begin
  Result := A + B + C;
end;

function Blend(const A: string): string;
begin
  Result := A;
end;

function Blend(const A: Integer): string;
begin
  Result := IntToStr(A);
end;

function Fill(const A: string; const B: Integer = 0): string;
begin
  Result := A;
end;

procedure Drive;
begin
  Pick('x');
  Fill('y');
  Blend('z');
end;

procedure DriveMultiline;
begin
  Pick('a',
       'b',
       'c');
end;

end.
'@

$db = Join-Path $WorkDir 'arity.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

# Report each call site as (enclosing routine, target arity, confidence). Arity
# is read back off the TARGET's own signature so the assertions below name the
# thing under test rather than an id that shifts whenever the fixture is edited.
$py = Join-Path $WorkDir 'edges.py'
@'
import sqlite3, sys, json, re

def arity(sig):
    if not sig: return 0
    d = 0
    inner = ""
    for ch in sig:
        if ch == '(':
            d += 1
            if d == 1: continue
        elif ch == ')':
            d -= 1
            if d == 0: break
        if d >= 1: inner += ch
    inner = inner.strip()
    if not inner: return 0
    n = 0
    for grp in inner.split(';'):
        names = grp.split(':')[0]
        names = re.sub(r'^\s*(const|var|out)\s+', '', names.strip(), flags=re.I)
        n += len([x for x in names.split(',') if x.strip()])
    return n

c = sqlite3.connect(sys.argv[1])
out = []
for row in c.execute("""
    SELECT enc.name, enc.signature, r.name_text, ce.target_symbol_id, ce.confidence,
           tgt.signature, r.start_line
    FROM refs r
    JOIN call_edges ce ON ce.ref_id = r.id
    JOIN symbols enc ON enc.id = r.enclosing_symbol_id
    JOIN symbols tgt ON tgt.id = ce.target_symbol_id
    WHERE r.kind = 'call'"""):
    out.append({"from": row[0], "from_arity": arity(row[1]), "callee": row[2],
                "target_id": row[3], "conf": row[4], "target_arity": arity(row[5]),
                "line": row[6]})
# Call refs with NO edge at all, so a "fix" that stops resolving is visible.
out_noedge = [r[0] for r in c.execute("""
    SELECT r.name_text FROM refs r LEFT JOIN call_edges ce ON ce.ref_id = r.id
    WHERE r.kind = 'call' AND ce.ref_id IS NULL AND r.name_text IN ('Pick','Blend','Fill')""")]
print(json.dumps({"edges": out, "noedge": out_noedge}))
c.close()
'@ | Set-Content $py -Encoding ascii
$res = (& python $py $db) -join "`n" | ConvertFrom-Json
$edges = @($res.edges)

function Edge($fromArity, $callee) {
  @($edges | Where-Object { $_.from_arity -eq $fromArity -and $_.callee -eq $callee }) | Select-Object -First 1
}
function EdgeFrom($fromName, $callee) {
  @($edges | Where-Object { $_.from -eq $fromName -and $_.callee -eq $callee }) | Select-Object -First 1
}

Write-Host 'Arity decides the overload' -ForegroundColor Cyan
$e1 = Edge 1 'Pick'    # inside Pick/1: Pick(A, '')      -> 2 args
Check 'Pick/1 body calling Pick(A,'''') binds the 2-arg overload' `
  ($null -ne $e1 -and $e1.target_arity -eq 2) "target arity=$($e1.target_arity)"
Check 'and it is CERTAIN, not ambiguous' ($null -ne $e1 -and $e1.conf -eq 'certain') `
  "conf=$($e1.conf)"

$e2 = Edge 2 'Pick'    # inside Pick/2: Pick(A, B, '')   -> 3 args
Check 'Pick/2 body calling Pick(A,B,'''') binds the 3-arg overload' `
  ($null -ne $e2 -and $e2.target_arity -eq 3) "target arity=$($e2.target_arity)"
Check 'and it is CERTAIN' ($null -ne $e2 -and $e2.conf -eq 'certain') "conf=$($e2.conf)"

Write-Host ''
Write-Host 'No phantom self-recursion (the filed symptom)' -ForegroundColor Cyan
Check 'Pick/1 does not resolve its call to ITSELF' `
  ($null -ne $e1 -and $e1.target_arity -ne 1) "target arity=$($e1.target_arity)"
Check 'Pick/2 does not resolve its call to ITSELF' `
  ($null -ne $e2 -and $e2.target_arity -ne 2) "target arity=$($e2.target_arity)"

Write-Host ''
Write-Host 'Plain call sites' -ForegroundColor Cyan
$e3 = EdgeFrom 'Drive' 'Pick'
Check 'Drive calling Pick(''x'') binds the 1-arg overload' `
  ($null -ne $e3 -and $e3.target_arity -eq 1) "target arity=$($e3.target_arity)"
$e4 = EdgeFrom 'DriveMultiline' 'Pick'
Check 'a call whose arguments span 3 lines is counted as 3 args' `
  ($null -ne $e4 -and $e4.target_arity -eq 3) "target arity=$($e4.target_arity)"

Write-Host ''
Write-Host 'Controls -- what arity must NOT decide' -ForegroundColor Cyan
$e5 = EdgeFrom 'Drive' 'Blend'
Check 'same-arity overloads differing only by TYPE stay uncertain' `
  ($null -eq $e5 -or $e5.conf -ne 'certain') "conf=$($e5.conf)"
$e6 = EdgeFrom 'Drive' 'Fill'
Check 'a DEFAULT parameter still accepts the shorter call' `
  ($null -ne $e6 -and $e6.target_arity -eq 2) `
  "Fill(A, B=0) called with 1 arg; target arity=$($e6.target_arity)"
Check 'no Pick/Blend/Fill call site lost its edge entirely' ($res.noedge.Count -eq 0) `
  "unresolved=$($res.noedge -join ',')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
