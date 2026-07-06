<#
  run_doc_since.ps1 -- <since> doc-source (`document --unit ... --since`).

  Uses fixtures\docsince\since.pas: class TSvc whose DoIt calls Helper(..)
  (parenthesized so the body-scan registers a Calls fact -> facts-only default
  keeps the managed block). The <since> date is git-derived from the commit that
  introduced DoIt's declaration line.

  SCENARIO 1 -- GIT PRESENT (date emitted):
    * Create a scratch dir, `git init`, write the fixture, `git add` + commit
      (deterministic author via -c user.name/-c user.email).
    * Index it, run `document --unit <fixture> --apply --since` with the git
      repo root as --base-dir.
    * Assert DoIt's managed block has a /// <since>YYYY-MM-DD</since> line
      (date shape \d{4}-\d{2}-\d{2}).
    * Idempotent: a second --apply --since leaves the file byte-identical.
    * WITHOUT --since: no <since> line (opt-in gate).

  SCENARIO 2 -- GIT ABSENT (silent degradation -- absence over a wrong fact):
    * A scratch dir with NO .git (plain non-repo folder), same fixture.
    * Run `document --unit <fixture> --apply --since`.
    * Assert NO <since> line appears AND the command does NOT crash (exit 0,
      the managed block still renders).

  Requires git on PATH for scenario 1 (this repo is a git repo, so it is).
  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docsince\since.pas')).Path

# Returns JUST DoIt's own doc-comment block (the /// lines immediately preceding
# its declaration), so an assertion never bleeds into Helper's comment.
function Get-DoItBlock($file) {
  $lines = [IO.File]::ReadAllLines($file)
  $idx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*procedure DoIt;') { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $block = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $block.Insert(0, $lines[$i])
  }
  return [string]::Join("`n", $block.ToArray())
}

Push-Location C:\TEMP
try {
  # === SCENARIO 1: GIT PRESENT (date emitted) ===
  $scratch = Join-Path C:\TEMP 'draglint_docsince'
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $target = Join-Path $scratch 'since.pas'
  $db     = Join-Path $scratch 'docsince.sqlite'
  Copy-Item $fixture $target -Force

  # scratch git repo with a deterministic committed fixture.
  Push-Location $scratch
  try {
    & git init -q 2>$null | Out-Null
    & git add since.pas 2>$null | Out-Null
    & git -c user.name='drag-lint test' -c user.email='test@drag-lint.local' `
        -c commit.gpgsign=false commit -q -m 'fixture' `
        --date='2020-01-15T12:00:00' 2>$null | Out-Null
  } finally { Pop-Location }

  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply --since --base-dir $scratch 2>$null | Out-Null
  $ec1 = $LASTEXITCODE
  Check 'apply #1 (--since, git present): exit 0' ($ec1 -eq 0)

  $blk = Get-DoItBlock $target
  Check 'DoIt decl + doc-comment found' ($null -ne $blk -and $blk -ne '')
  Check 'DoIt has managed facts block' ($blk -match '<!-- drag-lint:auto BEGIN -->')
  Check 'DoIt has <since> line with date shape' ($blk -match '<since>\d{4}-\d{2}-\d{2}</since>')

  # --- idempotency: second --apply --since leaves file byte-identical ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply --since --base-dir $scratch 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical on 2nd --since run' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  # === SCENARIO 1b: WITHOUT --since (opt-in gate) ===
  $scratchOff = Join-Path C:\TEMP 'draglint_docsince_off'
  if (Test-Path $scratchOff) { Remove-Item $scratchOff -Recurse -Force }
  New-Item -ItemType Directory -Path $scratchOff | Out-Null
  $targetOff = Join-Path $scratchOff 'since.pas'
  $dbOff     = Join-Path $scratchOff 'docsince_off.sqlite'
  Copy-Item $fixture $targetOff -Force
  Push-Location $scratchOff
  try {
    & git init -q 2>$null | Out-Null
    & git add since.pas 2>$null | Out-Null
    & git -c user.name='drag-lint test' -c user.email='test@drag-lint.local' `
        -c commit.gpgsign=false commit -q -m 'fixture' 2>$null | Out-Null
  } finally { Pop-Location }

  & $exePath index $scratchOff --db $dbOff 2>$null | Out-Null
  & $exePath document --unit $targetOff --db $dbOff --apply --base-dir $scratchOff 2>$null | Out-Null
  $ecOff = $LASTEXITCODE
  Check 'apply (no --since): exit 0' ($ecOff -eq 0)
  $blkOff = Get-DoItBlock $targetOff
  Check 'DoIt (no --since) still has managed block' ($blkOff -match '<!-- drag-lint:auto BEGIN -->')
  Check 'DoIt (no --since) has NO <since> line' ($blkOff -notmatch '<since>')

  # === SCENARIO 2: GIT ABSENT (silent degradation) ===
  $scratch2 = Join-Path C:\TEMP 'draglint_docsince_nogit'
  if (Test-Path $scratch2) { Remove-Item $scratch2 -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch2 | Out-Null
  $target2 = Join-Path $scratch2 'since.pas'
  $db2     = Join-Path $scratch2 'docsince_nogit.sqlite'
  Copy-Item $fixture $target2 -Force
  # NO git init: this is a plain non-repo folder.

  & $exePath index $scratch2 --db $db2 2>$null | Out-Null
  & $exePath document --unit $target2 --db $db2 --apply --since --base-dir $scratch2 2>$null | Out-Null
  $ec2 = $LASTEXITCODE
  Check 'apply (--since, git ABSENT): exit 0 (no crash)' ($ec2 -eq 0)

  $blk2 = Get-DoItBlock $target2
  Check 'DoIt (git absent) still has managed block' ($blk2 -match '<!-- drag-lint:auto BEGIN -->')
  Check 'DoIt (git absent) has NO <since> line (silent degradation)' ($blk2 -notmatch '<since>')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
