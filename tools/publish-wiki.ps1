<#
  publish-wiki.ps1 -- push docs\wiki\*.md to the GitHub wiki.

  WHY THIS IS A SCRIPT AND NOT SOMETHING THE AGENT ALREADY DID:

  GitHub creates the wiki's git repository LAZILY. Enabling wikis on the repo is
  not enough -- `<repo>.wiki.git` does not exist until the FIRST page has been
  created through the web UI, and GitHub's REST API has no endpoint for writing
  wiki pages. So the first page is a manual, one-time, 30-second step that
  nothing can automate. After that this script owns the content.

  ONE-TIME SETUP (once ever, in a browser):
    1. https://github.com/Alexl-git/Delphi-RAG-Lint/wiki
    2. "Create the first page" -> title it exactly `Home` -> put anything in the
       body (this script overwrites it) -> Save.

  THEN, and on every later change:
    pwsh -File tools\publish-wiki.ps1

  It clones the wiki repo to a temp folder, copies docs\wiki\*.md over it,
  commits only if something actually changed, and pushes.

  PAGE NAMES ARE FILE NAMES. `IDE-Menu-Reference.md` is reachable as
  .../wiki/IDE-Menu-Reference, and `[[IDE-Menu-Reference]]`-style links in the
  pages resolve on that basis. Renaming a file renames the page and breaks
  inbound links.
#>
[CmdletBinding()]
param(
  [string]$Repo    = 'https://github.com/Alexl-git/Delphi-RAG-Lint.wiki.git',
  [string]$Source  = "$PSScriptRoot\..\docs\wiki",
  [string]$Work    = "$env:TEMP\draglint-wiki",
  [string]$Message = ''
)

$ErrorActionPreference = 'Stop'

$src = (Resolve-Path $Source).Path
$pages = @(Get-ChildItem $src -Filter *.md)
if ($pages.Count -eq 0) { throw "no pages found in $src" }
Write-Host ("{0} page(s) to publish:" -f $pages.Count) -ForegroundColor Cyan
$pages | ForEach-Object { "   {0}" -f $_.Name }

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }

Write-Host "cloning the wiki repo ..." -ForegroundColor Cyan
git clone --quiet $Repo $Work 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $Work '.git'))) {
  Write-Host ''
  Write-Host '  The wiki repository does not exist yet.' -ForegroundColor Red
  Write-Host '  GitHub creates it only after the FIRST page is made in the browser:' -ForegroundColor Red
  Write-Host '    https://github.com/Alexl-git/Delphi-RAG-Lint/wiki  ->  Create the first page' -ForegroundColor Yellow
  Write-Host '    Title it exactly `Home`, save anything, then re-run this script.' -ForegroundColor Yellow
  exit 1
}

Copy-Item (Join-Path $src '*.md') $Work -Force

Push-Location $Work
try {
  $dirty = @(git status --porcelain)
  if ($dirty.Count -eq 0) {
    Write-Host 'wiki already up to date -- nothing to push.' -ForegroundColor Green
    exit 0
  }
  Write-Host ("{0} change(s):" -f $dirty.Count) -ForegroundColor Cyan
  $dirty | ForEach-Object { "   $_" }

  if ($Message -eq '') {
    $ver = (Select-String -Path "$PSScriptRoot\..\src\core\DRagLint.Core.Model.pas" `
                          -Pattern "DRAGLINT_VERSION\s*=\s*'([^']+)'").Matches[0].Groups[1].Value
    $Message = "docs(wiki): publish from docs\wiki at v$ver"
  }
  git add -A
  git commit -m $Message | Out-Null
  git push --quiet
  Write-Host ''
  Write-Host 'published: https://github.com/Alexl-git/Delphi-RAG-Lint/wiki' -ForegroundColor Green
} finally { Pop-Location }
