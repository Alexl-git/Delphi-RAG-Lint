<#
  run_diag_asked_reset_wiring.ps1 -- the "already asked for diagnostics" set
  MUST be forgotten whenever a new LSP server process is created.

  WHY THIS IS A SOURCE GUARD AND NOT A BEHAVIOUR TEST
  --------------------------------------------------
  The behaviour lives in a design-time BPL inside a running RAD Studio: the set
  is consulted on EditorViewActivated and the server is spawned by
  EnsureLspClient. Nothing headless can observe it. The alternative to a source
  guard is NO guard, and this is the THIRD defect in the same family:

    1. a file was marked "asked" even when the request never went out;
    2. the same at IDE startup, before the server was up -- so the gutter stayed
       empty for a whole session;
    3. (2026-09-01, reported live) the set survived the server being REPLACED.
       Several engine rebuilds killed the server; afterwards an open unit showed
       no drag-lint marks at all, while the IDE's own W1002 sat in the same
       gutter proving the gutter itself worked.

  All three are the same shape -- the record of a conversation outliving the
  conversation -- and all three are INVISIBLE: the failure is an absence of
  marks, which is indistinguishable from a clean file.

  WHAT IS ASSERTED
  ----------------
  Structure, not just presence of a string: the call must appear INSIDE the
  `if GLspClient = nil then begin ... end` block that constructs the client, and
  it must appear BEFORE the constructor runs. A call sitting anywhere else in
  the unit would satisfy a naive grep and still leave the defect.
#>
[CmdletBinding()]
param(
  [string]$Root = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$notifier = Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.EditViewNotifier.pas'
$editor   = Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.Editor.pas'
foreach ($f in @($notifier, $editor)) {
  if (-not (Test-Path $f)) { Write-Host "FATAL: missing $f" -ForegroundColor Red; exit 2 }
}

$nSrc = Get-Content $notifier -Raw
$eSrc = Get-Content $editor   -Raw

# --- 1. the reset exists and actually clears the set -------------------------
Check 'the reset procedure is declared in the notifier unit' `
  ($nSrc -match '(?m)^\s*procedure\s+DragLintForgetDiagnosticsAsked\s*;')

$implMatch = [regex]::Match($nSrc,
  'procedure\s+DragLintForgetDiagnosticsAsked\s*;\s*begin(?<body>.*?)end\s*;', 'Singleline')
Check 'the reset has an implementation' $implMatch.Success
if ($implMatch.Success) {
  # It must CLEAR the set. A body that only logs, or that reassigns nil without
  # freeing, would compile and pass a presence-only check.
  Check 'the reset actually clears GDiagAskedFor' `
    ($implMatch.Groups['body'].Value -match 'GDiagAskedFor\s*\.\s*Clear')
}

# --- 2. it is called from the SPAWN path, before the client is constructed ----
$spawn = [regex]::Match($eSrc,
  'if\s+GLspClient\s*=\s*nil\s+then\s*begin(?<body>.*?)GLspClient\s*:=\s*TDragLintLspClient\.Create', 'Singleline')
Check 'the client-construction block was located in Editor.pas' $spawn.Success
if ($spawn.Success) {
  Check 'the reset is called BEFORE a new LSP client is constructed' `
    ($spawn.Groups['body'].Value -match 'DragLintForgetDiagnosticsAsked')
}

# --- 3. POSITIVE CONTROL ------------------------------------------------------
# Assert this guard can FAIL. Strip the call out of a copy of the spawn block and
# confirm the same test then reports absent. Without this the guard could be
# passing vacuously -- e.g. if the regex above stopped matching after a refactor,
# $spawn.Success would be false and only that one row would go red while the
# substantive assertion silently never ran.
if ($spawn.Success) {
  $mutated = $spawn.Groups['body'].Value -replace 'DragLint(\.Plugin\.EditViewNotifier)?\.?DragLintForgetDiagnosticsAsked[^;]*;', ''
  Check 'POSITIVE CONTROL: removing the call makes this guard fail' `
    (-not ($mutated -match 'DragLintForgetDiagnosticsAsked'))
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
