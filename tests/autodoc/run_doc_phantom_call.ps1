<#
  run_doc_phantom_call.ps1 -- prose in a doc comment must not become a call edge.

  WHAT THIS PINS. INBOX-2026-08-25-autodoc-phantom-call.md reported that
  `document --apply` wrote

      /// <para>Calls: StopStarted</para>

  onto DataCopy's TSettingsGate.RequestOpen, whose body calls nothing.
  StopStarted is a sibling method, and the class-level <remarks> contains a
  usage sketch:

      ///     -> run the stop, then: if Gate.StopStarted(BatchStillRunning) then ...

  RE-MEASURED 2026-08-26 AND IT NO LONGER REPRODUCES. On a freshly reindexed
  DataCopy the current engine regenerates that block with no Calls: fact at all,
  and in fact proposes to DELETE the stale line. The note was closed on that
  measurement, not on the memory of a fix -- and the phantom still sitting in
  DataCopy's source is a historical artifact of an older engine, repaired by one
  `document --unit --apply`.

  THIS GUARD EXISTS BECAUSE THE MECHANISM IS A REPEAT OFFENDER. "A text scan
  cannot tell code from comment" has produced nine separate defects in this
  repo. The behaviour is correct today; nothing was locking it in.

  THE POSITIVE CONTROL IS THE POINT. Asserting only "no Calls: appears" passes
  with call-fact generation switched off entirely, which would be a far worse
  regression than the one being guarded. So CallsBeta -- which really does call
  Beta -- MUST produce "Calls: Beta" in the same run.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\phantomcall\uPhantomCall.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_phantomcall'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'uPhantomCall.pas'
$db     = Join-Path $scratch 'phantomcall.sqlite'
Copy-Item $fixture $target -Force

& $exePath index $scratch --db $db 2>$null | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)

& $exePath document --unit $target --db $db --apply 2>$null | Out-Null
Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)

$lines = Get-Content $target

# The doc block for a method is the contiguous run of /// lines above its
# DECLARATION -- the first of the two textually distinct signature lines, since
# the interface section precedes the implementation.
function Doc-Above([string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $acc = @(); $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $acc = ,($lines[$j]) + $acc; $j-- }
  ($acc -join "`n")
}

$alpha     = Doc-Above 'function Alpha\('
$gamma     = Doc-Above 'function Gamma\('
$callsBeta = Doc-Above 'function CallsBeta\('

foreach ($p in @(@('Alpha', $alpha), @('Gamma', $gamma), @('CallsBeta', $callsBeta))) {
  if ($null -eq $p[1]) {
    Write-Host ("FATAL: no doc block found above {0}" -f $p[0]) -ForegroundColor Red; exit 2
  }
}

Write-Host ''
Write-Host 'Prose naming a sibling must NOT become a call fact' -ForegroundColor Cyan
Check 'Alpha (nearest decl below the prose) has no Calls: fact' `
  ($alpha -notmatch 'Calls:') ($alpha -split "`n" | Where-Object { $_ -match 'Calls:' })
Check 'Gamma has no Calls: fact' `
  ($gamma -notmatch 'Calls:') ($gamma -split "`n" | Where-Object { $_ -match 'Calls:' })

Write-Host ''
Write-Host 'POSITIVE CONTROL -- a real call must still be reported' -ForegroundColor Cyan
# The engine emits the QUALIFIED target, e.g. 'Calls: uPhantomCall.TGate.Beta'.
# Asserting a bare 'Calls: Beta' fails against CORRECT output -- which is how the
# first draft of this control failed, and worth keeping written down: the
# DataCopy phantom said bare 'Calls: StopStarted', so the emitted FORMAT has
# changed since, which is further evidence that phantom predates this engine.
Check 'CallsBeta reports Calls: <qualified> Beta' ($callsBeta -match 'Calls:.*TGate.Beta')

if ($callsBeta -notmatch 'Calls:.*TGate.Beta') {
  Write-Host '  !! The control failed, so the two assertions above prove NOTHING --' -ForegroundColor Yellow
  Write-Host '  !! they pass with call-fact generation switched off entirely.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
