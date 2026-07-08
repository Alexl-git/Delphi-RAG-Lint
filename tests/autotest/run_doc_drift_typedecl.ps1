<#
  run_doc_drift_typedecl.ps1 -- Task 1 (BACKLOG-lint-false-positives.md FP #1):
  doc-drift's param/return analysis (findings 1-6) must NOT run on a non-routine
  symbol. Before the fix, TDocDrift.Analyze ran ExtractParamList/ParseParamNames
  against EffectiveSignature(AStore, ASym) for EVERY symbol kind. On a class TYPE
  declaration, EffectiveSignature returns the ancestor/interface heading -- e.g.
  '(TFrame)' or '(TInterfacedObject, ISomeIntf)' -- which got mis-parsed as a
  parameter list, so a documented class/interface decl spuriously fired
  ddParamMissing once per ancestor/interface name ("signature param \"TFrame\"
  has no <param> tag"), and because ddParamMissing is Fixable, --fix would have
  emitted a wrong <param name="TFrame"> stub into a class comment.

  Fixture (self-contained, mirrors the bug report): a trivial TFrame base class
  and ISomeIntf interface declared locally (so the unit indexes with no external
  dependency), then:
    TX = class(TFrame)                          -- documented, ancestor only
    TY = class(TInterfacedObject, ISomeIntf)     -- documented, ancestor + interface
  Both TX and TY carry a /// <summary> so ExistingDocFor finds a doc-comment
  (doc-drift --qname exits 1 "no doc-comment on: X" otherwise).

  ASSERTION: run `doc-drift --qname <Unit>.TX --json` and `.TY --json`. Each
  output line is a compact JSON object {kind, detail, fixable, line} (one per
  finding; DRagLint.CLI.pas DoDocDrift / DocDriftKindStr). The FP is
  kind="ddParamMissing" with detail mentioning the ancestor/interface name as a
  "signature param". Assert NO line is ddParamMissing at all for these
  non-routine symbols, AND (belt-and-suspenders / robust even if some future
  finding kind's wording changes) no finding's detail mentions TFrame,
  TInterfacedObject, or ISomeIntf as a signature param.

  Run against the CURRENT exe first to confirm RED (FP fires), then after the
  fix (gate findings 1-6 on ASym.Kind in [skProcedure,skFunction,skMethod,
  skConstructor,skDestructor]) confirm GREEN.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-drift-typedecl"
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
# Absolutize so the exe path survives regardless of CWD (mirrors run_doc_returns.ps1).
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
$fixtureFile = Join-Path $srcDir 'DriftTypeDecl.pas'
$db = Join-Path $WorkDir 'typedecl.sqlite'

# Self-contained fixture: trivial TFrame/ISomeIntf stubs declared locally so the
# unit indexes with no external dependency, then two DOCUMENTED classes -- one
# with an ancestor only, one with an ancestor AND an implemented interface --
# mirroring the report's TYadfOptionsFrame / TYadfOptionsPage shapes.
$Fixture = @'
unit DriftTypeDecl;

interface

type
  TFrame = class(TObject)
  end;

  ISomeIntf = interface
    ['{12345678-1234-1234-1234-123456789ABC}']
    procedure DoIt;
  end;

  /// <summary>A documented frame type.</summary>
  TX = class(TFrame)
  end;

  /// <summary>A documented options page.</summary>
  TY = class(TInterfacedObject, ISomeIntf)
  public
    procedure DoIt;
  end;

implementation

procedure TY.DoIt;
begin
end;

end.
'@
function Write-Fixture([string]$Path) {
  $norm = $Fixture -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
Write-Fixture $fixtureFile

& $Exe index $srcDir --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)
Check 'db built' (Test-Path $db)

function Get-Findings([string]$QName) {
  $lines = & $Exe doc-drift --qname $QName --db $db --json 2>&1
  $ec = $LASTEXITCODE
  $objs = @()
  foreach ($line in $lines) {
    $line = "$line".Trim()
    if ($line -eq '') { continue }
    try { $objs += ($line | ConvertFrom-Json) } catch { }
  }
  return @{ Ec = $ec; Findings = $objs; Raw = ($lines -join "`n") }
}

Write-Host 'TX = class(TFrame) -- documented, ancestor only' -ForegroundColor Cyan
$rTX = Get-Findings 'DriftTypeDecl.TX'
Check 'TX: doc-drift exits 0' ($rTX.Ec -eq 0) $rTX.Raw

$txParamMissing = @($rTX.Findings | Where-Object { $_.kind -eq 'ddParamMissing' })
Check 'TX: no ddParamMissing finding at all' ($txParamMissing.Count -eq 0) ($rTX.Raw)

$txBadDetail = @($rTX.Findings | Where-Object {
  $_.detail -match 'TFrame' -or $_.detail -match 'TInterfacedObject' -or $_.detail -match 'ISomeIntf'
})
Check 'TX: no finding mentions TFrame/TInterfacedObject/ISomeIntf as a signature param' `
  ($txBadDetail.Count -eq 0) ($rTX.Raw)

Write-Host ''
Write-Host 'TY = class(TInterfacedObject, ISomeIntf) -- documented, ancestor + interface' -ForegroundColor Cyan
$rTY = Get-Findings 'DriftTypeDecl.TY'
Check 'TY: doc-drift exits 0' ($rTY.Ec -eq 0) $rTY.Raw

$tyParamMissing = @($rTY.Findings | Where-Object { $_.kind -eq 'ddParamMissing' })
Check 'TY: no ddParamMissing finding at all' ($tyParamMissing.Count -eq 0) ($rTY.Raw)

$tyBadDetail = @($rTY.Findings | Where-Object {
  $_.detail -match 'TFrame' -or $_.detail -match 'TInterfacedObject' -or $_.detail -match 'ISomeIntf'
})
Check 'TY: no finding mentions TFrame/TInterfacedObject/ISomeIntf as a signature param' `
  ($tyBadDetail.Count -eq 0) ($rTY.Raw)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
