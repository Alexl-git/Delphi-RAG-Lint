<#
  run_missing_doc_impl_section.ps1 -- `missing-doc` must report only the PUBLIC
  surface: a unit-level routine or type declared in the IMPLEMENTATION section
  is private to the unit and is not reported (gaps.log 2026-10-29, GAP-MISSINGDOC;
  ORM3 uPdfScanFields / uPdfScanMerge reported implementation helpers as
  "Public declaration ... has no DocInsight doc-comment").

  Positive control (MUST still fire): an undocumented routine and an undocumented
  type declared in the INTERFACE section of the same unit.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-missingdoc-impl-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

$unit = @(
  'unit ImplDoc;'
  ''
  'interface'
  ''
  'type'
  '  TPubNoDoc = class'
  '  end;'
  ''
  '/// <summary>Documented.</summary>'
  '/// <returns>One.</returns>'
  'function PubDoc: Integer;'
  'function PubNoDocFn: Integer;'
  ''
  'implementation'
  ''
  'type'
  '  TImplOnlyType = class'
  '  end;'
  ''
  'function ImplOnlyFn: Integer;'
  'begin'
  '  Result := 1;'
  'end;'
  ''
  'function PubDoc: Integer;'
  'begin'
  '  Result := ImplOnlyFn;'
  'end;'
  ''
  'function PubNoDocFn: Integer;'
  'begin'
  '  Result := 2;'
  'end;'
  ''
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $src 'ImplDoc.pas'), $unit + "`r`n", [Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'impl.sqlite'
& $Exe index $src --db $db *> $null
$out = (& $Exe lint-all --db $db --enable missing-doc 2>&1 | Out-String)
$md = ($out -split "`r?`n") | Where-Object { $_ -match 'missing-doc' -and $_ -match "Public declaration" }
$joined = $md -join "`n"
Check 'positive control: interface routine PubNoDocFn reported' ($joined -match "'PubNoDocFn'")
Check 'positive control: interface type TPubNoDoc reported'     ($joined -match "'TPubNoDoc'")
Check 'implementation routine ImplOnlyFn NOT reported'          ($joined -notmatch "'ImplOnlyFn'")
Check 'implementation type TImplOnlyType NOT reported'          ($joined -notmatch "'TImplOnlyType'")
Check 'documented PubDoc NOT reported'                          ($joined -notmatch "'PubDoc'")
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { exit 1 }
Write-Host 'run_missing_doc_impl_section: PASS' -ForegroundColor Green
exit 0
