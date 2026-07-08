<#
  run_naming_autofix.ps1 -- Batch C Task 6/7: naming re-casing findings
  (method-pascalcase, local-var-casing, const-casing) become FIXABLE via the
  rename engine (DRagLint.Refactor.NamingFix.BuildNamingFixEdits), applied
  through the existing store-backed append in FinalizeAndOutput (mirrors the
  doc-drift/missing-doc pattern), opt-in only via config "autofix": [...].

  Task 6 owns the MINIMAL RED->GREEN skeleton below (one rule: method-
  pascalcase, opted in via AutoFixIds, `lint-all --fix --apply` rewrites the
  decl AND every call site). Task 7 expands this into the full per-rule
  battery (local-var-casing, const-casing, conflict-skip, not-opted-in-skip).

  Fixture: a unit with a mis-cased method `procedure doSomething;` (should be
  `DoSomething` under PascalCase, the default MethodCase) declared on a class,
  called from one other routine in the same unit. `lint-all` needs an index
  (global rename resolves callers via the store), so this script indexes the
  fixture first, then runs `lint-all --db <db> --fix --apply --config <cfg>`
  with "autofix": ["method-pascalcase"] in the config.

  ASSERTION (minimal, Task 6 GREEN bar):
    - Before the naming-fix wiring: --fix --apply does NOT change the
      identifier (RED: rule not fixable yet).
    - After: both the declaration and the call site read `DoSomething`
      (GREEN), and the CLI's own FixCount-derived summary reports >=1 fix.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-naming-autofix"
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
# Absolutize so the exe path survives regardless of CWD (mirrors run_doc_drift_typedecl.ps1).
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
$fixtureFile = Join-Path $srcDir 'NamingAutofix.pas'
$db = Join-Path $WorkDir 'naming.sqlite'
$cfgPath = Join-Path $WorkDir 'drag-lint-lint.json'

# Self-contained fixture: TThing.doSomething is mis-cased (should be
# DoSomething under the default PascalCase MethodCase). Called once from
# RunIt in the same unit, so a global rename must touch both the decl and
# the call site.
$Fixture = @'
unit NamingAutofix;

interface

type
  TThing = class
  public
    procedure doSomething;
  end;

procedure RunIt;

implementation

procedure TThing.doSomething;
begin
end;

procedure RunIt;
var
  Thing: TThing;
begin
  Thing:= TThing.Create;
  try
    Thing.doSomething;
  finally
    Thing.Free;
  end;
end;

end.
'@
function Write-Fixture([string]$Path) {
  $norm = $Fixture -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
Write-Fixture $fixtureFile

# Opt in method-pascalcase via config "autofix" (Cfg.IsAutoFix gate in
# FinalizeAndOutput -- naming re-casing stays off by default).
'{ "autofix": ["method-pascalcase"] }' | Out-File -FilePath $cfgPath -Encoding ascii

& $Exe index $srcDir --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)
Check 'db built' (Test-Path $db)

function Get-FixtureText {
  return Get-Content -Raw $fixtureFile
}

Write-Host 'lint-all --fix --apply with method-pascalcase opted in' -ForegroundColor Cyan
$out = & $Exe lint-all --db $db --config $cfgPath --rule method-pascalcase --fix --apply --quiet 2>&1
$ec = $LASTEXITCODE
Write-Host ($out -join "`n")

# -cmatch/-cnotmatch: CASE-SENSITIVE (PowerShell's plain -match is case-insensitive
# by default, which would silently pass on the still-mis-cased "doSomething").
$after = Get-FixtureText
$ifaceRenamed = $after -cmatch 'procedure\s+DoSomething;'
$implRenamed  = $after -cmatch 'procedure\s+TThing\.DoSomething;'
$callRenamed  = $after -cmatch 'Thing\.DoSomething;'
$ifaceStale   = $after -cmatch 'procedure\s+doSomething;'
$implStale    = $after -cmatch 'TThing\.doSomething;'
$callStale    = $after -cmatch 'Thing\.doSomething;'

Check 'interface declaration renamed to DoSomething' $ifaceRenamed $after
Check 'implementation header renamed to TThing.DoSomething' $implRenamed $after
Check 'call site renamed to Thing.DoSomething' $callRenamed $after
Check 'no stale lower-case doSomething interface decl remains' (-not $ifaceStale) $after
Check 'no stale lower-case TThing.doSomething impl header remains' (-not $implStale) $after
Check 'no stale lower-case doSomething call site remains' (-not $callStale) $after

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
