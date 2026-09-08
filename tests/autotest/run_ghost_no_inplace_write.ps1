<#
  run_ghost_no_inplace_write.ps1 -- ghost-check must NEVER write the file you
  are editing.

  THE OWNER'S RULING, 2026-09-08:
  "We need to stop unattended rewrites of modified files. If file was modified in
  the editor after the original save time, it means we cannot modify it back."

  THE DEFECT IT CLOSES. `ghost-check` used to overwrite each real .pas with the
  unsaved editor buffer, stamp mtime = Now to force a rebuild, compile the whole
  project, then restore. It fires unattended 3.5 s after you stop typing
  (LiveDiagnostics GHOST_IDLE_MS, AutoCompileBuffer defaults True), so that
  window was enough for the IDE to notice "changed on disk" and offer a reload --
  and accepting DISCARDED the live edits.

  WHY THE EXISTING GUARD DID NOT CATCH IT. tests\autotest\run_ghost_ownership.ps1
  asserts the RESTORE: that the bytes are back afterwards. That is true of the
  broken behaviour too. It is structurally incapable of seeing the WINDOW during
  which the file on disk is wrong, which is the entire defect.

  SO THIS GUARD WATCHES, IT DOES NOT SAMPLE. A FileSystemWatcher queues an event
  for every write regardless of how briefly the file is wrong, so a fast
  write-then-restore cannot slip between two polls. The final byte/FILETIME
  equality check is kept as a second, weaker net.

  IT NEEDS NO WORKING COMPILER, AND THAT IS DELIBERATE. The in-place path applies
  its overlay BEFORE invoking the compiler, so the write is observable even when
  dcc/msbuild is absent or the fixture project does not build. The guard asserts
  file-system behaviour, not compiler output, and therefore runs anywhere.

  CASE 2 IS THE POSITIVE CONTROL. `--in-place` must still be seen writing. Without
  it, case 1 would pass just as well against a watcher that never fires, an
  engine that refuses the manifest, or a fixture the verb skips -- which is the
  "a guard that cannot fail" shape this repo keeps rediscovering.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("ghostw_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# --- fixture: a minimal but REAL project ------------------------------------
$unitSrc = @(
  'unit GhostU;', '', 'interface', '', 'procedure Go;', '',
  'implementation', '', 'procedure Go;', 'begin', 'end;', '', 'end.'
) -join "`r`n"
$unitPath = Join-Path $WorkDir 'GhostU.pas'
[IO.File]::WriteAllText($unitPath, $unitSrc + "`r`n", [Text.Encoding]::ASCII)

# the unsaved buffer: same unit with an extra line, i.e. genuinely dirty
$bufPath = Join-Path $WorkDir 'GhostU.buffer.pas'
[IO.File]::WriteAllText($bufPath, ($unitSrc -replace 'procedure Go;\r\nbegin', "procedure Go;`r`nbegin`r`n  // edited in the editor, never saved") + "`r`n", [Text.Encoding]::ASCII)

$dprPath = Join-Path $WorkDir 'GhostP.dpr'
[IO.File]::WriteAllText($dprPath, "program GhostP;`r`n`r`nuses`r`n  GhostU in 'GhostU.pas';`r`n`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)

$dprojPath = Join-Path $WorkDir 'GhostP.dproj'
[IO.File]::WriteAllText($dprojPath, @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>GhostP.dpr</MainSource><DCC_DcuOutput>.\`$(Platform)\`$(Config)\DCU</DCC_DcuOutput></PropertyGroup>
  <ItemGroup><DCCReference Include="GhostU.pas"/></ItemGroup>
</Project>
"@, [Text.Encoding]::ASCII)

$manifest = Join-Path $WorkDir 'overlays.txt'
[IO.File]::WriteAllText($manifest, "$unitPath`t$bufPath`r`n", [Text.Encoding]::ASCII)

function Get-Stamp([string]$p) {
  $fi = Get-Item -LiteralPath $p
  return [pscustomobject]@{
    Sha  = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
    Ft   = $fi.LastWriteTimeUtc.ToFileTimeUtc()   # 100 ns, exact
    Len  = $fi.Length
  }
}

# Runs ghost-check with a watcher armed on the real unit; returns the number of
# change events seen for it, plus before/after stamps.
function Invoke-Watched([string]$Tag, [string[]]$ExtraArgs) {
  $before = Get-Stamp $unitPath
  $fsw = New-Object IO.FileSystemWatcher $WorkDir, 'GhostU.pas'
  $fsw.NotifyFilter = [IO.NotifyFilters]::LastWrite -bor [IO.NotifyFilters]::Size -bor `
                      [IO.NotifyFilters]::CreationTime -bor [IO.NotifyFilters]::Attributes
  $fsw.IncludeSubdirectories = $false
  # ${Tag}, not $Tag_ -- the latter parses as a variable named Tag_ and expands
  # to nothing, so both cases would share one source identifier.
  $srcId = "ghostw_${Tag}_" + [Guid]::NewGuid().ToString('N').Substring(0,6)
  $null = Register-ObjectEvent -InputObject $fsw -EventName Changed -SourceIdentifier "$srcId.chg"
  $null = Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier "$srcId.new"
  $fsw.EnableRaisingEvents = $true
  try {
    # $argList, NOT $args -- $args is an automatic variable inside a function.
    $argList = @('ghost-check', $dprojPath, '--overlays', $manifest, '--platform', 'win64', '--format', 'json') + $ExtraArgs
    $out = Join-Path $WorkDir "$Tag.out"
    $p = Start-Process $exePath -ArgumentList $argList -WorkingDirectory $WorkDir -NoNewWindow -PassThru -Wait `
           -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    Start-Sleep -Milliseconds 400      # let queued watcher events drain
    $events = @(Get-Event -SourceIdentifier "$srcId.*" -ErrorAction SilentlyContinue)
    $n = $events.Count
    $events | ForEach-Object { Remove-Event -EventIdentifier $_.EventIdentifier -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ Events = $n; Before = $before; After = (Get-Stamp $unitPath); Exit = $p.ExitCode }
  } finally {
    $fsw.EnableRaisingEvents = $false
    Unregister-Event -SourceIdentifier "$srcId.chg" -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier "$srcId.new" -ErrorAction SilentlyContinue
    $fsw.Dispose()
  }
}

Write-Host ''
Write-Host 'The fixture is genuinely DIRTY (else the verb would rightly skip it)' -ForegroundColor Cyan
Check 'the buffer differs from the file on disk' `
  ((Get-FileHash $unitPath).Hash -ne (Get-FileHash $bufPath).Hash) ''

Write-Host ''
Write-Host 'CASE 1 -- the DEFAULT must never touch the real file' -ForegroundColor Cyan
$def = Invoke-Watched 'default' @()
Check 'the real .pas saw ZERO file-system change events during the run' `
  ($def.Events -eq 0) `
  "$($def.Events) event(s) -- the engine wrote the file you are editing"
Check 'its bytes are unchanged' ($def.After.Sha -eq $def.Before.Sha) ''
Check 'its FILETIME is unchanged to the exact 100ns tick' `
  ($def.After.Ft -eq $def.Before.Ft) `
  "before=$($def.Before.Ft) after=$($def.After.Ft) -- a restored-but-restamped file still trips the IDE"
Check 'no _D-RAG ghost journal or backup was written beside the project' `
  (-not (Test-Path (Join-Path $WorkDir '_D-RAG\GhostU.pas.ghost-orig')) -and
   -not (Test-Path (Join-Path $WorkDir '_D-RAG\GhostU.pas.ghost-journal'))) `
  'the shadow path must not create the crash-recovery artifacts either'

Write-Host ''
Write-Host 'CASE 2 -- POSITIVE CONTROL: --in-place must still be SEEN writing' -ForegroundColor Cyan
$inp = Invoke-Watched 'inplace' @('--in-place')
Check 'the watcher DOES observe writes under --in-place' `
  ($inp.Events -gt 0) `
  "$($inp.Events) event(s) -- if this is 0 the watcher is blind and case 1 proved nothing"
Check '--in-place still restores the bytes afterwards (6036261 is not regressed)' `
  ($inp.After.Sha -eq $inp.Before.Sha) ''

Write-Host ''
Write-Host 'The two modes actually differ' -ForegroundColor Cyan
Check 'default is quieter on disk than --in-place' `
  ($def.Events -lt $inp.Events) `
  "default=$($def.Events) in-place=$($inp.Events) -- equal counts mean the flag changed nothing"

try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
