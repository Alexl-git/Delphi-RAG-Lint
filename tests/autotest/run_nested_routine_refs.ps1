<#
  run_nested_routine_refs.ps1 -- calls made inside a NESTED (local) routine must
  reach the reference index.

  THE BUG (INBOX-datacopy-2026-08-06 section 6 -- "it tells you to delete live code")
  -----------------------------------------------------------------------------------
  `unused-public-symbol` reported `uFileUtils.SamePathFolder` as dead public API.
  It is not: it is the FROM-vs-TO folder collision guard, and it is called. But
  its only call site sits inside `CollidesWithFromPath`, a local function
  declared inside a method.

  There was no ref row for it AT ALL -- not a resolution failure, nothing was
  ever recorded. In Pascal a nested routine lives in the DECLARATION part,
  before `begin`, so it is a sibling of `declVars` and NOT a child of the
  `body` field. The walker descended only into `body`, so nested routine bodies
  were never entered and every call inside one was invisible.

  Blast radius was wider than one rule: find-callers, impact and the call graph
  all under-reported for any unit using local functions -- idiomatic Delphi, and
  commonest in exactly the large routines people most want a call graph for.
  The facts walker DID descend, which is why the generated `Calls:` block named
  a symbol that find-callers then denied.

  This asserts the reference is recorded AND that the rule still fires on a
  genuinely uncalled export -- a "fix" that merely stopped the rule would pass
  the first half and fail the second.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-nested-refs"
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

$src = @'
unit nestedrefs;

interface

function CalledOnlyFromNested(const A, B: string): Boolean;
function NeverCalledAtAll(const A: string): Boolean;

procedure Outer(const AText: string);

implementation

function CalledOnlyFromNested(const A, B: string): Boolean;
begin
  result:= A = B;
end;

function NeverCalledAtAll(const A: string): Boolean;
begin
  result:= A <> '';
end;

procedure Outer(const AText: string);

  function Guard(const AValue: string): Boolean;
  begin
    { the ONLY call site, and it is inside a nested routine }
    result:= CalledOnlyFromNested(AValue, AText);
  end;

begin
  if Guard(AText) then
    Writeln('same');
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $WorkDir 'nestedrefs.pas'), $src, [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'nested.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

$py = Join-Path $WorkDir 'refs.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
out = {}
for nm in ('CalledOnlyFromNested','NeverCalledAtAll','Guard'):
    out[nm] = c.execute("SELECT COUNT(*) FROM refs WHERE name_text LIKE ? COLLATE NOCASE", (nm,)).fetchone()[0]
print(json.dumps(out))
c.close()
'@ | Set-Content $py -Encoding ascii
$refs = (& python $py $db) -join "`n" | ConvertFrom-Json

Write-Host 'Reference index' -ForegroundColor Cyan
Check 'a call made INSIDE a nested routine is recorded' ($refs.CalledOnlyFromNested -ge 1) `
  "refs=$($refs.CalledOnlyFromNested)"
Check 'a call to the nested routine itself is still recorded' ($refs.Guard -ge 1) "refs=$($refs.Guard)"
Check 'an export nobody calls has no refs' ($refs.NeverCalledAtAll -eq 0) "refs=$($refs.NeverCalledAtAll)"

Write-Host ''
Write-Host 'find-callers' -ForegroundColor Cyan
$fc = (& $Exe query find-callers --name CalledOnlyFromNested --db $db 2>$null | Out-String)
Check 'find-callers resolves the nested call site' ($fc -match 'nestedrefs\.pas')

Write-Host ''
Write-Host 'unused-public-symbol' -ForegroundColor Cyan
$lint = (& $Exe lint-all --db $db 2>$null | Out-String)
Check 'the nested-called export is NOT called dead' `
  (-not ($lint -match 'unused-public-symbol.*CalledOnlyFromNested'))
Check 'a genuinely uncalled export IS still reported' `
  ($lint -match 'unused-public-symbol.*NeverCalledAtAll') 'else the fix just disabled the rule'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
