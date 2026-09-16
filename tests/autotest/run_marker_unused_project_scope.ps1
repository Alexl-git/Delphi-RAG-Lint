<#
  run_marker_unused_project_scope.ps1 -- `review-marker-unused` must not fire on
  a marker that IS suppressing a store-backed (project-scope) finding.

  THE DEFECT (docs\INBOX-lint-two-rule-false-positives-on-new-code.md, #2;
  cause confirmed at the code level in session 98, fixed 2026-09-16):
    ApplyLineMarkers joins a finding to its marker by MarkerKey(path, line,
    rule), and the path was only LowerCase'd. The POPULATE side keys the
    finding's F.FilePath -- ABSOLUTE for every store-backed rule (class
    metrics, unused-public-symbol, the uses-edge and duplicate-global rules)
    -- while the CHECK side keys the scanned file's path as the caller typed
    it: `lint src\X.pas` is RELATIVE. Two spellings of one file never joined,
    so the marker suppressed the finding AND was reported unused. The two
    hints contradicted each other and exactly one could be obeyed.

  THE FIXTURE carries BOTH a project-scope marker (deep-inheritance, a class
  metric read through the store) AND a file-scope marker (self-assignment, a
  .scm rule keyed by the scanned path) in ONE file, and lints by a RELATIVE
  path from the fixture's own directory. A fix that normalises only one side
  of the join passes a single-rule fixture; it cannot pass this one.

  CONTROLS:
    1. both rules FIRE before any marker exists (a later silence then means
       "suppressed", not "never ran");
    2. after `allow` on both: NO finding, NO review-marker-unused -- by the
       relative path, the absolute path, and a forward-slash spelling;
    3. a marker on an UNRELATED line is still reported unused (the detector is
       alive; the fix did not widen the join into "any marker anywhere").

  POSITIVE CONTROL: red on the pre-fix engine at check 2 for the
  deep-inheritance marker (relative path), green everywhere else.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-marker-projscope-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'uProbe.pas'
$db  = Join-Path $WorkDir 'probe.sqlite'
$err = Join-Path $WorkDir 'stderr.txt'

# Seven-deep inheritance (deep-inheritance threshold 6 -> TA7 fires, DIT 7)
# plus a self-assignment for the file-scope rule.
$SRC = @(
  'unit uProbe;'
  ''
  'interface'
  ''
  'type'
  '  TA0 = class(TObject) end;'
  '  TA1 = class(TA0) end;'
  '  TA2 = class(TA1) end;'
  '  TA3 = class(TA2) end;'
  '  TA4 = class(TA3) end;'
  '  TA5 = class(TA4) end;'
  '  TA6 = class(TA5) end;'
  '  TA7 = class(TA6) end;'
  ''
  'procedure Nudge(var B: Integer);'
  ''
  'implementation'
  ''
  'procedure Nudge(var B: Integer);'
  'begin'
  '  B:= B;'
  'end;'
  ''
  'end.'
) -join "`r`n"
[System.IO.File]::WriteAllText($pas, $SRC + "`r`n", [System.Text.Encoding]::ASCII)
$DEEP_LINE = 13   # TA7
$SELF_LINE = 21   # B:= B;

& $Exe index $WorkDir --db $db *> $null
Check 'fixture indexed' ($LASTEXITCODE -eq 0) ''

function Relevant([string]$Out) { (($Out -split "`n" | Where-Object { $_ -match 'review-marker|deep-inheritance:|self-assignment:' }) -join ' || ') }
function LintAs([string]$PathSpelling) {
  Push-Location $WorkDir
  try {
    $o = & $Exe lint $PathSpelling --db $db 2>$err
    return (($o | Out-String) -replace "`r`n", "`n")
  } finally { Pop-Location }
}

Write-Host ''
Write-Host '-- 1. KNOWN-FIRING: both rules fire before any marker exists' -ForegroundColor Cyan
$r = LintAs 'uProbe.pas'
Write-Host ("  " + (($r -split "`n" | Where-Object { $_ -match 'deep-inheritance|self-assignment' }) -join "`n  ")) -ForegroundColor DarkGray
Check "deep-inheritance fires on line $DEEP_LINE (store-backed)" ($r -match "uProbe\.pas:$DEEP_LINE`:\d+.*deep-inheritance") ''
Check "self-assignment fires on line $SELF_LINE (file-scope)" ($r -match "uProbe\.pas:$SELF_LINE`:\d+.*self-assignment") ''
$deepAbs = ($r -split "`n" | Where-Object { $_ -match 'deep-inheritance' } | Select-Object -First 1)
Check 'the store-backed finding is printed with an ABSOLUTE path (the two spellings this pins)' ($deepAbs -match '^[A-Za-z]:\\') "line=$deepAbs"

Write-Host ''
Write-Host '-- 2. allow both, then lint by three spellings: no finding, no unused hint' -ForegroundColor Cyan
& $Exe allow $pas --fix-line $DEEP_LINE --fix-rule deep-inheritance --apply 2>$err | Out-Null
Check 'allow deep-inheritance --apply exits 0' ($LASTEXITCODE -eq 0) ''
& $Exe allow $pas --fix-line $SELF_LINE --fix-rule self-assignment --apply 2>$err | Out-Null
Check 'allow self-assignment --apply exits 0' ($LASTEXITCODE -eq 0) ''
$markers = @(Get-Content -LiteralPath $pas | Where-Object { $_ -match 'dl:ok' })
Check 'two markers written' ($markers.Count -eq 2) ($markers -join ' | ')

foreach ($spelling in @('uProbe.pas', $pas, ($pas -replace '\\', '/'))) {
  $r = LintAs $spelling
  $tag = if ($spelling -eq 'uProbe.pas') { 'RELATIVE' } elseif ($spelling -match '/') { 'FORWARD-SLASH' } else { 'ABSOLUTE' }
  Check "[$tag] deep-inheritance suppressed"            (-not ($r -match 'deep-inheritance:')) (Relevant $r)
  Check "[$tag] self-assignment suppressed"             (-not ($r -match 'self-assignment:')) (Relevant $r)
  Check "[$tag] NO review-marker-unused for the store-backed marker" (-not ($r -match "uProbe\.pas:$DEEP_LINE`:.*review-marker-unused")) (Relevant $r)
  Check "[$tag] NO review-marker-unused for the file-scope marker"   (-not ($r -match "uProbe\.pas:$SELF_LINE`:.*review-marker-unused")) (Relevant $r)
}

Write-Host ''
Write-Host '-- 3. the detector is still alive: an unrelated marker IS reported unused' -ForegroundColor Cyan
$lines = [System.IO.File]::ReadAllLines($pas)
$lines[5] = $lines[5] + '  // dl:ok self-assignment -- planted on an unrelated line'
[System.IO.File]::WriteAllLines($pas, $lines, [System.Text.Encoding]::ASCII)
$r = LintAs 'uProbe.pas'
Check 'review-marker-unused fires on the planted line 6' ($r -match 'uProbe\.pas:6:.*review-marker-unused') (Relevant $r)
Check 'and still NOT on the two real markers' (-not ($r -match "uProbe\.pas:($DEEP_LINE|$SELF_LINE):.*review-marker-unused")) (Relevant $r)

Write-Host ''
if ($script:Failed) { Write-Host 'run_marker_unused_project_scope: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_marker_unused_project_scope: PASS' -ForegroundColor Green
exit 0
