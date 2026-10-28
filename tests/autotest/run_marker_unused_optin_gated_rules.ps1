<#
  run_marker_unused_optin_gated_rules.ps1 -- a file-scoped `lint <file> --db` must
  not call a dl:ok marker unused when the marker's rule is one that run never
  evaluates because TProjectLintRules.Run gates it on OptedIn (and the per-file
  call hands it no opt-in list).

  THE DEFECT (CONVERTER, 2026-10-25): FeatureGen.Check.pas:28 carries
  `dl:ok uses-global-census@...`; lint-all honours it, `lint <file>` reported
  review-marker-unused -- "remove it" -- and obeying that re-opens the census
  finding in lint-all. LintUnjudgedMarkerRules only covered the no-index case.

  The rule ids are NOT written out here: they are read from the OptedIn('<id>')
  calls in src\lint\DRagLint.Lint.ProjectRules.pas, so a rule added behind that
  gate without joining the unjudged list makes this guard fail.

  CHECKS
    1. every OptedIn-gated id yields NO review-marker-unused in `lint <file> --db`.
  POSITIVE CONTROLS
    2. the per-file run still reports a self-assignment marker on an unrelated
       line as unused (the reporter is alive in this scope);
    3. lint-all still judges a uses-global-census marker planted on an unrelated
       line (review-marker-unused fires there).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-marker-optin-" + [Guid]::NewGuid().ToString('N')))
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
$src = Join-Path $PSScriptRoot '..\..\src\lint\DRagLint.Lint.ProjectRules.pas'
$ids = [regex]::Matches([IO.File]::ReadAllText($src), "OptedIn\('([a-z-]+)'\)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
Check 'OptedIn-gated ids found in ProjectRules.pas' (@($ids).Count -ge 8) ("count=" + @($ids).Count)
# The ON opt-in rules `lint <file>` opts in itself when the store holds the file
# (CLI.pas LINT_FILE_OPTIN_ON, lane DIRLINT 2026-10-27) ARE evaluated per file, so a
# marker for one with no finding on its line is genuinely unused -- as lint-all says.
$cli = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\src\cli\DRagLint.CLI.pas'))
$onDecl = [regex]::Match($cli, 'LINT_FILE_OPTIN_ON\s*:\s*array\[[^\]]*\]\s*of\s*string\s*=\s*\(([^)]*)\)')
$onIds = @([regex]::Matches($onDecl.Groups[1].Value, "'([a-z-]+)'") | ForEach-Object { $_.Groups[1].Value })
Check 'LINT_FILE_OPTIN_ON found in CLI.pas' ($onIds.Count -ge 1) ("ids=" + ($onIds -join ','))
$ids = @($ids | Where-Object { $onIds -notcontains $_ })

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$db  = Join-Path $WorkDir 'probe.sqlite'
$err = Join-Path $WorkDir 'stderr.txt'
$pas = Join-Path $WorkDir 'uMark.pas'

# Lines 1-10 are the unit skeleton; one marked comment line per id follows.
$body = New-Object System.Collections.Generic.List[string]
$body.AddRange([string[]]@('unit uMark;', '', 'interface', '', 'implementation', '', 'procedure Plain;', 'begin', 'end;', ''))
foreach ($id in $ids) { $body.Add("// dl:ok $id -- REVIEWED 2026-10-25: fixture, marker for a rule this run never evaluates") }
$body.AddRange([string[]]@('', 'end.'))
[IO.File]::WriteAllText($pas, (($body -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

& $Exe index $WorkDir --db $db *> $null
Check 'fixture indexed' ($LASTEXITCODE -eq 0) ''

function LintAll { ((& $Exe lint-all --db $db 2>$err | Out-String) -replace "`r`n", "`n") }
function LintFile([string]$P) { ((& $Exe lint $P --db $db 2>$err | Out-String) -replace "`r`n", "`n") }

Write-Host ''
Write-Host '-- 1. per-file run, index present: no OptedIn-gated marker is called unused' -ForegroundColor Cyan
$r = LintFile $pas
$bad = @($r -split "`n" | Where-Object { $_ -match 'review-marker-unused' })
Check 'no review-marker-unused for any OptedIn-gated rule' ($bad.Count -eq 0) (($bad | Select-Object -First 3) -join ' || ')
$p0 = [IO.File]::ReadAllLines($pas)
[IO.File]::WriteAllLines($pas, [string[]]($p0[0..($p0.Count - 3)] + @($onIds | ForEach-Object { "// dl:ok $_ -- REVIEWED 2026-10-27: fixture, an ON rule this run DOES evaluate" }) + $p0[($p0.Count - 2)..($p0.Count - 1)]), [Text.Encoding]::ASCII)
$r = LintFile $pas
foreach ($on in $onIds) {
  Check "the ON opt-in rule $on IS judged per file (its marker reported unused)" ($r -match "review-marker-unused: dl:ok marker for `"$on`"") ''
}
[IO.File]::WriteAllLines($pas, $p0, [Text.Encoding]::ASCII)

Write-Host ''
Write-Host '-- 2. POSITIVE CONTROL: a file-scope marker on an unrelated line IS unused per file' -ForegroundColor Cyan
$lines = [IO.File]::ReadAllLines($pas)
$lines[1] += '  // dl:ok self-assignment -- planted on an unrelated line'
[IO.File]::WriteAllLines($pas, $lines, [Text.Encoding]::ASCII)
$r = LintFile $pas
Check 'review-marker-unused fires on uMark.pas:2' ($r -match 'uMark\.pas:2:.*review-marker-unused') ''

Write-Host ''
Write-Host '-- 3. POSITIVE CONTROL: lint-all still judges the census marker' -ForegroundColor Cyan
$all = LintAll
$census = @($all -split "`n" | Where-Object { $_ -match 'review-marker-unused' -and $_ -match 'uses-global-census' })
Check 'lint-all reports the uses-global-census marker unused' ($census.Count -ge 1) (($all -split "`n" | Where-Object { $_ -match 'review-marker' } | Select-Object -First 3) -join ' || ')

[IO.Directory]::Delete($WorkDir, $true)
Write-Host ''
if ($script:Failed) { Write-Host 'run_marker_unused_optin_gated_rules: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_marker_unused_optin_gated_rules: PASS' -ForegroundColor Green
exit 0
