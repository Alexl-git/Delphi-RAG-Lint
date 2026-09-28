<#
  run_cycle_examples_fresh.ps1 -- the checked-in circular-dependency EXAMPLES
  must equal what the engine emits today.

  WHY (2026-09-28): `circular-demo\CYCLE-REPORT.md` -- the "full report" the
  wiki page links to -- was written 2026-08-17 and never regenerated. On
  2026-09-23 Haiku FAILED on that shape of report (E2065 x5), the playbook was
  rewritten (70e41bed), Haiku then PASSED 4/4 -- and the example everyone would
  hand to a model was still the old, failing one. Nothing noticed, because
  nothing compared the file with the engine. This does.

  HOW. Every verbatim block in an example doc is preceded by a marker line
      <!-- dl:verbatim-cycles <cycles arguments> -->
  and opened by a fence of 3+ backticks. For each example the runner copies the
  project to a scratch root that keeps its REPO-RELATIVE layout, indexes it the
  way the doc says, runs `drag-lint cycles --db <db> <arguments>` from the
  directory the doc says, and replaces the scratch root in the output with
  nothing -- so absolute paths come out repo-relative and a clone anywhere
  reproduces the same text.

    default   compare; FAIL on any drift (this is the battery mode)
    -Update   rewrite the blocks in place (how the docs get refreshed)

  POSITIVE CONTROL: each marker's block must be non-empty and the doc must
  contain at least one marker -- a doc with the markers stripped would
  otherwise pass by comparing nothing.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cycle-examples-$PID",
  [switch]$Update
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
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# One entry per example: where the project lives (repo-relative), the doc that
# carries its verbatim blocks, the directory the doc's commands run from, and
# the documented index arguments + db path (both relative to that directory).
$Examples = @(
  @{ Name = 'circular-demo'
     Project = 'circular-demo'
     Doc = 'circular-demo\CYCLE-REPORT.md'
     RunFrom = ''
     IndexArgs = @('index', '--project', 'circular-demo\CircularDemo.dproj', '--db', 'circular-demo\_D-RAG\CircularDemo.sqlite')
     Db = 'circular-demo\_D-RAG\CircularDemo.sqlite' },
  @{ Name = 'wiki-circular-demo'
     Project = 'circular-demo'
     Doc = 'docs\wiki\Circular-Dependency-Report.md'
     RunFrom = ''
     IndexArgs = @('index', '--project', 'circular-demo\CircularDemo.dproj', '--db', 'circular-demo\_D-RAG\CircularDemo.sqlite')
     Db = 'circular-demo\_D-RAG\CircularDemo.sqlite' },
  @{ Name = 'readme-circular-demo'
     Project = 'circular-demo'
     Doc = 'README.md'
     RunFrom = ''
     IndexArgs = @('index', '--project', 'circular-demo\CircularDemo.dproj', '--db', 'circular-demo\_D-RAG\CircularDemo.sqlite')
     Db = 'circular-demo\_D-RAG\CircularDemo.sqlite' },
  @{ Name = 'circular-uses-demo'
     Project = 'docs\examples\circular-uses-demo'
     Doc = 'docs\examples\circular-uses-demo\REPORT.md'
     RunFrom = 'docs\examples'
     IndexArgs = @('index', 'circular-uses-demo', '--db', 'demo.sqlite')
     Db = 'demo.sqlite' },
  @{ Name = 'circular-uses-demo-readme'
     Project = 'docs\examples\circular-uses-demo'
     Doc = 'docs\examples\circular-uses-demo\README.md'
     RunFrom = 'docs\examples'
     IndexArgs = @('index', 'circular-uses-demo', '--db', 'demo.sqlite')
     Db = 'demo.sqlite' }
)

function Split-Args([string]$Text) {
  return ,@($Text.Trim() -split '\s+' | Where-Object { $_ -ne '' })
}

foreach ($ex in $Examples) {
  Write-Host ''
  Write-Host ("== {0} ({1})" -f $ex.Name, $ex.Doc) -ForegroundColor Cyan
  $docPath = Join-Path $Repo $ex.Doc
  Check "$($ex.Name): doc exists" (Test-Path $docPath) $docPath
  if (-not (Test-Path $docPath)) { continue }

  # Copy the project (sources only) into the scratch root at the same relative path.
  $src = Join-Path $Repo $ex.Project
  $dst = Join-Path $WorkDir $ex.Project
  New-Item -ItemType Directory -Force $dst | Out-Null
  Get-ChildItem $src -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj', '.inc', '.dfm' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $dst $_.Name) }
  $runDir = if ($ex.RunFrom) { Join-Path $WorkDir $ex.RunFrom } else { $WorkDir }
  $dbDir = Split-Path (Join-Path $runDir $ex.Db)
  if ($dbDir) { New-Item -ItemType Directory -Force $dbDir | Out-Null }

  Push-Location $runDir
  try {
    & $Exe @($ex.IndexArgs) *> $null
    Check "$($ex.Name): indexed the documented way" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

    $text  = [IO.File]::ReadAllText($docPath)
    $nl    = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [Collections.Generic.List[string]]($text -split "`r?`n")
    $markers = 0
    $changed = $false
    $i = 0
    while ($i -lt $lines.Count) {
      # EXCERPT blocks (the wiki quotes a few lines, not the whole playbook):
      # every line must appear VERBATIM in the engine's output, except a line
      # that is exactly `...` (an elision). -Update cannot rewrite an excerpt --
      # choosing lines is editorial -- so drift is reported in both modes.
      if ($lines[$i] -match '^<!--\s*dl:excerpt-cycles\s+(.*?)\s*-->\s*$') {
        $markers++
        $argText = $Matches[1]
        $open = $i + 1
        if ($open -ge $lines.Count -or $lines[$open] -notmatch '^(`{3,})') {
          Check "$($ex.Name): excerpt marker '$argText' is followed by a fence" $false "line $($open + 1)"
          $i++; continue
        }
        $fence = $Matches[1]
        $close = $open + 1
        while ($close -lt $lines.Count -and $lines[$close] -ne $fence) { $close++ }
        $cycArgs = @('cycles', '--db', $ex.Db) + (Split-Args $argText)
        $raw = & $Exe @cycArgs 2>$null
        $freshSet = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($f in @($raw | ForEach-Object { ("$_").Replace($runDir + '\', '').Replace($WorkDir + '\', '').TrimEnd() })) { [void]$freshSet.Add($f) }
        $quoted = 0
        $missing = @()
        for ($k = $open + 1; $k -lt $close; $k++) {
          $ln = $lines[$k].TrimEnd()
          if ($ln -eq '' -or $ln -eq '...') { continue }
          $quoted++
          if (-not $freshSet.Contains($ln)) { $missing += $ln }
        }
        Check "$($ex.Name): excerpt of 'cycles $argText' quotes at least one line" ($quoted -gt 0) "quoted=$quoted"
        $detail = if ($missing.Count -eq 0) { "$quoted line(s) all found" } else { "$($missing.Count) line(s) not in the engine output, first: '$($missing[0])' -- re-pick the excerpt lines from fresh output" }
        Check "$($ex.Name): every excerpt line of 'cycles $argText' is verbatim engine output" ($missing.Count -eq 0) $detail
        $i = $close + 1
        continue
      }
      if ($lines[$i] -match '^<!--\s*dl:verbatim-cycles\s+(.*?)\s*-->\s*$') {
        $markers++
        $argText = $Matches[1]
        $open = $i + 1
        if ($open -ge $lines.Count -or $lines[$open] -notmatch '^(`{3,})') {
          Check "$($ex.Name): marker '$argText' is followed by a fence" $false "line $($open + 1)"
          $i++; continue
        }
        $fence = $Matches[1]
        $close = $open + 1
        while ($close -lt $lines.Count -and $lines[$close] -ne $fence) { $close++ }
        if ($close -ge $lines.Count) {
          Check "$($ex.Name): fence for '$argText' is closed by the same $($fence.Length)-backtick line" $false
          $i++; continue
        }
        $current = @()
        for ($k = $open + 1; $k -lt $close; $k++) { $current += $lines[$k] }

        $cycArgs = @('cycles', '--db', $ex.Db) + (Split-Args $argText)
        $raw = & $Exe @cycArgs 2>$null
        $exit = $LASTEXITCODE
        # Paths relative to the directory the doc's commands run FROM (so the
        # re-index line and the file paths agree with "Indexed with: ..."),
        # then anything else under the scratch root relative to the repo root.
        $fresh = @($raw | ForEach-Object { ("$_").Replace($runDir + '\', '').Replace($WorkDir + '\', '').TrimEnd() })
        while ($fresh.Count -gt 0 -and $fresh[-1] -eq '') { $fresh = @($fresh[0..($fresh.Count - 2)]) }
        Check "$($ex.Name): cycles $argText ran and printed something" (($exit -eq 0) -and ($fresh.Count -gt 0)) "exit=$exit lines=$($fresh.Count)"
        $innerFence = @($fresh | Where-Object { $_ -match "^$fence" }).Count
        Check "$($ex.Name): the $($fence.Length)-backtick outer fence is longer than any fence inside the output" ($innerFence -eq 0) "inner lines starting with the outer fence: $innerFence"

        $same = (($current | ForEach-Object { $_.TrimEnd() }) -join "`n") -eq ($fresh -join "`n")
        if ($Update) {
          if (-not $same) {
            $lines.RemoveRange($open + 1, $close - $open - 1)
            $lines.InsertRange($open + 1, [string[]]$fresh)
            $changed = $true
            Write-Host ("  [UPDATED] cycles {0}: {1} -> {2} line(s)" -f $argText, $current.Count, $fresh.Count) -ForegroundColor Yellow
          } else {
            Write-Host ("  [same] cycles {0}" -f $argText) -ForegroundColor DarkGray
          }
          $i = $open + 1 + $fresh.Count + 1
        } else {
          $firstDiff = -1
          for ($k = 0; $k -lt [Math]::Max($current.Count, $fresh.Count); $k++) {
            $a = if ($k -lt $current.Count) { $current[$k].TrimEnd() } else { '<missing>' }
            $b = if ($k -lt $fresh.Count) { $fresh[$k] } else { '<missing>' }
            if ($a -ne $b) { $firstDiff = $k; break }
          }
          $detail = if ($same) { "$($fresh.Count) line(s)" } else { "first difference at block line $($firstDiff + 1): doc='$($current[$firstDiff])' engine='$($fresh[$firstDiff])' -- regenerate with -Update" }
          Check "$($ex.Name): the block for 'cycles $argText' matches the engine" $same $detail
          $i = $close + 1
        }
      } else { $i++ }
    }
    Check "$($ex.Name): the doc carries at least one dl:verbatim-cycles marker (POSITIVE CONTROL)" ($markers -gt 0) "markers=$markers"
    if ($Update -and $changed) {
      [IO.File]::WriteAllText($docPath, ($lines -join $nl), [Text.Encoding]::ASCII)
      Write-Host "  wrote $docPath" -ForegroundColor Yellow
    }
  } finally {
    Pop-Location
  }
}

Write-Host ''
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
