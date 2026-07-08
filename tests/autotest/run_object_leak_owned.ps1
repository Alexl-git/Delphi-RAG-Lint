<#
  run_object_leak_owned.ps1 -- Task 2 (BACKLOG-lint-false-positives.md FP #2):
  object-leak must NOT fire on a TComponent descendant constructed with a
  non-nil AOwner argument (e.g. TLabel.Create(Self)) even when the local is
  never separately stored in a field/array and never explicitly freed --
  the VCL owner (Self) inserts it into its Components list and frees it on
  its own destruction, so an explicit Free would risk a double-free.

  Before the fix, DRagLint.Diagnostics.FlowChecks.pas's object-leak block
  recorded EVERY constructor-assignment site as a leak candidate regardless
  of the AOwner argument, so the owner-parented local was flagged as a false
  positive (info object-leak "may be leaked").

  Fixture: tests/lint-project/objleak-owned/objleakowned.pas -- a
  self-contained minimal TComponent/TLabel/TStringList stub hierarchy (so
  IsDescendantOf(TLabel, TComponent) resolves via the store without pulling
  in the real VCL), then three routines:
    - MakeOwnedLabel: lbl := TLabel.Create(Self); lbl.Parent := X;
      lbl is NOT stored, NOT freed -- owner-parented -> must NOT be flagged
      after the fix (the FP under test).
    - LeakStringList: sl := TStringList.Create; (TStringList has no AOwner,
      not a TComponent descendant) -- genuine leak -> MUST still be flagged.
    - LeakNilOwnedLabel: c := TLabel.Create(nil); explicit NIL owner -> no
      real owner -> genuine leak -> MUST still be flagged.

  Ancestry resolution requires a store, so this indexes the fixture into a
  temp DB and runs `check-ast <file> --db <db> --format json` (mirrors
  run_objleak_interproc.ps1 / run_managed_class.ps1), then filters findings
  for rule == 'object-leak' by start_line.

  Run against the CURRENT (pre-fix) exe -> expect RED: MakeOwnedLabel's lbl
  IS flagged (FP present). After the fix -> GREEN: lbl clean, both leak
  controls still flagged.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
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
# Absolutize so the exe path survives regardless of CWD (mirrors run_doc_returns.ps1 / run_doc_drift_typedecl.ps1).
$Exe = (Resolve-Path $Exe).Path

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

$dir = Join-Path $PSScriptRoot '..\lint-project\objleak-owned'
$dir = (Resolve-Path $dir).Path
$pas = Join-Path $dir 'objleakowned.pas'
$db  = Join-Path $env:TEMP 'objleak_owned.sqlite'
if (Test-Path $db) { Remove-Item $db -Force }

& $Exe index $dir --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)
Check 'db built' (Test-Path $db)

$raw = & $Exe check-ast $pas --db $db --format json 2>$null
# the CLI prints a few preamble lines before the JSON array -- slice from the
# first '[' so ConvertFrom-Json sees only JSON (mirrors run_objleak_interproc.ps1).
$txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
$findings = @()
if ($b -ge 0) { try { $findings = @(($txt.Substring($b) | ConvertFrom-Json)) } catch { $findings = @() } }

$leaks = @($findings | Where-Object { $_.rule -eq 'object-leak' })
Write-Host 'object-leak findings:'
$leaks | ForEach-Object { Write-Host ("  object-leak:{0} [{1}] {2}" -f $_.start_line, $_.severity, $_.message) }

# MakeOwnedLabel's lbl := TLabel.Create(Self) is at line 35 in the fixture.
$ownedLine = 35
# LeakStringList's sl := TStringList.Create is at line 45.
$leakStringListLine = 45
# LeakNilOwnedLabel's c := TLabel.Create(nil) is at line 54.
$leakNilOwnedLine = 54

$ownedFlagged   = @($leaks | Where-Object { $_.start_line -eq $ownedLine }).Count -gt 0
$slLeakFlagged  = @($leaks | Where-Object { $_.start_line -eq $leakStringListLine }).Count -gt 0
$nilLeakFlagged = @($leaks | Where-Object { $_.start_line -eq $leakNilOwnedLine }).Count -gt 0

Check 'owner-parented lbl (TLabel.Create(Self)) NOT flagged' (-not $ownedFlagged)
Check 'genuine leak: TStringList.Create (no owner) IS flagged' $slLeakFlagged
Check 'genuine leak: TLabel.Create(nil) (explicit nil owner) IS flagged' $nilLeakFlagged

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
