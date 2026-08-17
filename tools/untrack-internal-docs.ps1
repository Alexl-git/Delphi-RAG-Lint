<#
  untrack-internal-docs.ps1 -- stop publishing the internal engineering notes.

  The repository is PUBLIC. It carries the working notes of the project --
  INBOX items, session resume docs, plans, triage, reviews, agent specs, raw
  build/lint output -- which name client projects and quote strings from client
  source. Owner instruction 2026-08-17: publish "only the source and building
  instructions and commands and manuals".

  WHAT THIS DOES:  `git rm --cached` on those paths, so they are removed from
  the REPOSITORY but LEFT ON DISK. They are the project's working memory; they
  keep working locally, they just stop being published. It then adds them to
  .gitignore so they cannot drift back in.

  WHAT THIS DOES *NOT* DO -- read this, it matters:
  **It does not remove anything from git HISTORY.** Every one of these files
  remains in earlier commits, in the source archives of every existing release,
  and in any clone anyone already made. This script stops the bleeding; it does
  not undo the publication. Removing them from history means rewriting it
  (`git filter-repo`) and force-pushing, which breaks every clone and requires
  deleting the old releases too. That is a separate decision -- see the report
  this script prints at the end.

  USAGE:
    pwsh -File tools\untrack-internal-docs.ps1            # DRY RUN, shows the list
    pwsh -File tools\untrack-internal-docs.ps1 -Apply     # actually untrack + commit
#>
[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..").Path
Push-Location $repo
try {
  # INTERNAL -- process and session artefacts, not product.
  $internal = @(
    'docs/INBOX-*', 'docs/INBOX-Done/*', 'docs/OPEN-ITEMS.md',
    'docs/RESUME-*', 'docs/PLAN-*', 'docs/NEXT-SESSION-PLAN-*',
    'docs/QUESTIONS-*', 'docs/TRIAGE-*', 'docs/BACKLOG-*', 'docs/TODO-URGENT-*',
    'docs/DESIGN-2026-*', 'docs/FIX-2026-*', 'docs/IDE-POLISH-*',
    'docs/marathon-*', 'docs/test-findings-*', 'docs/Z14SLCT-*', 'docs/probe-*',
    'docs/superpowers/*', 'docs/reviews/*',
    '.superpowers/*', 'stats/*',
    'AGENT_USAGE_NOTES.md',
    # raw tool output that was committed by accident
    'build-output.txt', 'build_result.txt', 'clean_rebuild_result.txt',
    'rebuild_result.txt', 'test_reconcile.txt', 'lint-report-*.txt',
    'FEATURES.txt', 'Lint Features report.txt'
  )

  # core.quotePath=false: without it git returns non-ASCII names OCTAL-ESCAPED
  # ("C\357\200\272TEMP..."), and every later Test-Path on such a name fails
  # against a file that is perfectly present. The first run of this script threw
  # its own safety check on exactly that, having deleted nothing.
  $all = @(git -c core.quotePath=false ls-files)
  $hit = @()
  foreach ($p in $internal) { $hit += ($all | Where-Object { $_ -like $p }) }
  # a stray capture file whose name contains escaped path characters
  $hit += ($all | Where-Object { $_ -match 'stderrcap' })
  $hit = @($hit | Sort-Object -Unique)

  Write-Host ''
  Write-Host ("{0} tracked file(s) are internal:" -f $hit.Count) -ForegroundColor Cyan
  $hit | Group-Object { $d = ($_ -split '/'); if ($d.Count -gt 1) { "$($d[0])/$($d[1])" } else { $d[0] } } |
    Sort-Object Count -Descending | Select-Object -First 14 Count, Name | Format-Table -AutoSize

  Write-Host 'KEPT (product surface):' -ForegroundColor Green
  @('src/','rules/','build/','tests/','tools/','editors/','third_party/','convrules/',
    'README.md','INSTALL.md','CHANGELOG.md','LICENSE',
    'docs/wiki/  (the manual)','docs/USER-GUIDE.md','docs/EDITORS.md','docs/AI-*.md',
    'docs/INDEX-SCHEMA.md','docs/INDEXING-AND-DB-ARCHITECTURE.md','docs/lint/  (design reports)',
    'docs/release-notes-*.md') | ForEach-Object { "   $_" }

  if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN. Nothing changed. Re-run with -Apply to untrack and commit.' -ForegroundColor Yellow
    exit 0
  }

  $listFile = Join-Path $env:TEMP 'draglint-untrack.txt'
  [System.IO.File]::WriteAllLines($listFile, $hit)
  git rm --cached --quiet --pathspec-from-file=$listFile
  if ($LASTEXITCODE -ne 0) { throw "git rm --cached failed ($LASTEXITCODE)" }

  # Keep them out for good.
  $marker = '# --- internal working notes: local only, never published ---'
  $gi = Get-Content .gitignore -Raw -ErrorAction SilentlyContinue
  if ($null -eq $gi -or $gi -notmatch [regex]::Escape($marker)) {
    $add = @('', $marker) + $internal + @('*stderrcap.txt', '')
    Add-Content .gitignore ($add -join "`r`n")
    git add .gitignore
    Write-Host 'added the internal paths to .gitignore' -ForegroundColor Cyan
  }

  # Sanity: the files must still be on disk. Untracking must not delete work.
  # -LiteralPath, because these paths are data: some contain characters that
  # PowerShell would otherwise treat as wildcards.
  $missing = @($hit | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repo $_)) })
  if ($missing.Count -gt 0) {
    Write-Host ("*** {0} file(s) vanished from disk -- STOP and investigate" -f $missing.Count) -ForegroundColor Red
    $missing | Select-Object -First 5 | ForEach-Object { "   $_" }
    throw 'untracking removed files from disk; expected --cached to keep them'
  }
  Write-Host ("all {0} file(s) still present on disk" -f $hit.Count) -ForegroundColor Green

  git commit -m @"
chore(repo): stop publishing internal engineering notes

The repository is public. It carried the project's working notes -- INBOX
items, session resume docs, plans, triage, reviews, agent specs and raw
build/lint output -- which name client projects and quote strings from client
source. Owner instruction: publish only the source, build instructions,
commands and manuals.

git rm --cached only: every file stays on disk and keeps working locally. They
are added to .gitignore so they cannot drift back in.

THIS DOES NOT REMOVE THEM FROM HISTORY. They remain in earlier commits, in the
source archives of existing releases, and in any clone already taken. Undoing
the publication itself needs a history rewrite and the deletion of old
releases, which is a separate decision.
"@ | Select-Object -First 3

  Write-Host ''
  Write-Host 'NEXT:' -ForegroundColor Cyan
  Write-Host '   git push origin main'
  Write-Host ''
  Write-Host 'STILL EXPOSED after that push -- decide separately:' -ForegroundColor Yellow
  Write-Host '   * git history (every earlier commit)'
  Write-Host '   * the source archive of every release, including v1.4.0-alpha'
  Write-Host '   Fixing those means rewriting history and re-cutting releases.'
} finally { Pop-Location }
