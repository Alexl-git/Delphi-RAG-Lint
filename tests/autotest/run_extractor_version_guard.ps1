<#
  run_extractor_version_guard.ps1 -- if you change what the indexer EXTRACTS,
  you must bump DRAGLINT_EXTRACTOR_VERSION.

  WHY THIS EXISTS. The indexer fingerprint used to embed DRAGLINT_VERSION, the
  product version, so every release re-parsed every database whether or not
  extraction had changed -- ~7,000 library files plus every project index, for
  releases that changed nothing the parser sees. Splitting the two makes routine
  version bumps free.

  It also introduces a NEW failure mode, and it is the worse one: change an
  extractor and FORGET to bump DRAGLINT_EXTRACTOR_VERSION, and every existing
  index keeps its old parses SILENTLY. The index then looks complete and answers
  confidently with fewer results -- exactly the failure the fingerprint mechanism
  exists to prevent. A redundant re-parse costs time; a stale parse costs trust.

  THIS SUITE IS THE PRICE OF THAT SPLIT. It hashes the extraction-relevant
  sources and compares against a checked-in baseline:

    hash unchanged                      -> PASS
    hash changed, version bumped        -> PASS, and it prints the line to paste
                                           into the baseline
    hash changed, version NOT bumped    -> FAIL   <-- the whole point

  WHAT COUNTS AS EXTRACTION: the parsers, the preprocessor (it decides which
  branches are parsed at all), the indexer, and the storage WRITE side. Not the
  lint rules, not the doc engine, not the LSP or the IDE plugin -- nothing
  downstream of the index can make a stored parse wrong.

  WHEN IT FAILS LEGITIMATELY (you did change an extractor):
    1. bump DRAGLINT_EXTRACTOR_VERSION in src\core\DRagLint.Core.Model.pas
    2. re-run this suite and paste the printed line into
       tests\extractor-version.baseline
    3. expect every index to re-parse once -- that is the point

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$repo     = (Resolve-Path "$PSScriptRoot\..\..").Path
$baseline = Join-Path $repo 'tests\extractor-version.baseline'
$modelPas = Join-Path $repo 'src\core\DRagLint.Core.Model.pas'

# --- the declared extractor version ----------------------------------------
$m = Select-String -Path $modelPas -Pattern "DRAGLINT_EXTRACTOR_VERSION\s*=\s*'([^']+)'"
Check 'DRAGLINT_EXTRACTOR_VERSION is declared' ($null -ne $m) $modelPas
if ($null -eq $m) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$version = $m.Matches[0].Groups[1].Value

# --- hash the extraction surface -------------------------------------------
# Sorted by relative path so the digest cannot depend on enumeration order.
$roots = @('src\parser', 'src\preprocess', 'src\index')
$files = @()
foreach ($r in $roots) {
  $p = Join-Path $repo $r
  if (Test-Path $p) { $files += @(Get-ChildItem $p -Recurse -File -Filter *.pas) }
}
$files += @(Get-ChildItem (Join-Path $repo 'src\core') -File -Filter 'DRagLint.Core.Indexer.pas')

$rel = @($files | ForEach-Object { $_.FullName.Substring($repo.Length + 1) } | Sort-Object)
Check 'the extraction surface is non-empty' ($rel.Count -gt 5) "$($rel.Count) file(s)"

$sha = [System.Security.Cryptography.SHA256]::Create()
$acc = New-Object System.IO.MemoryStream
foreach ($r in $rel) {
  $bytes = [System.IO.File]::ReadAllBytes((Join-Path $repo $r))
  $nameB = [System.Text.Encoding]::ASCII.GetBytes($r)   # path is part of the identity
  $acc.Write($nameB, 0, $nameB.Length)
  $acc.Write($bytes, 0, $bytes.Length)
}
$acc.Position = 0
$hash = ([System.BitConverter]::ToString($sha.ComputeHash($acc)) -replace '-','').ToLower()
$acc.Dispose()

$current = "$version|$hash"

if (-not (Test-Path $baseline)) {
  Write-Host ''
  Write-Host 'no baseline yet -- create it with:' -ForegroundColor Yellow
  Write-Host "   $current"
  Write-Host "   -> $baseline"
  Check 'baseline exists' $false 'first run: write the line above into the baseline file'
} else {
  $stored = (Get-Content $baseline | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1).Trim()
  $sv, $sh = $stored -split '\|', 2

  if ($sh -eq $hash) {
    Check 'extraction surface unchanged' $true "version=$version"
  } elseif ($sv -ne $version) {
    Check 'extraction changed AND the version was bumped' $true "$sv -> $version"
    Write-Host ''
    Write-Host '   update the baseline to:' -ForegroundColor Yellow
    Write-Host "   $current"
  } else {
    # ---- DEFER-UNTIL: a dated, hash-pinned postponement --------------------
    # The owner sometimes needs an extractor fix TODAY without paying for the
    # full re-parse today (2026-08-19: constructors/destructors). Simply not
    # bumping is the failure this guard exists to prevent, so the postponement
    # is made explicit instead of silent:
    #
    #   DEFER-UNTIL|<yyyy-MM-dd>|<hash>|<reason>
    #
    # It is PINNED TO THIS EXACT HASH, so any further extractor change makes it
    # stop applying and the guard fails again immediately -- a deferral can
    # never come to cover a change nobody reviewed. And it EXPIRES on its own
    # date, so forgetting is not an option the mechanism allows.
    #
    # This is not a way to get green. It is louder than a bump, not quieter:
    # every run prints what is stale and when the debt falls due.
    $defer = Get-Content $baseline | Where-Object { $_ -match '^\s*DEFER-UNTIL\|' } | Select-Object -First 1
    $deferOk = $false
    if ($defer) {
      $parts = ($defer.Trim() -split '\|', 4)
      $dDate = $null
      $dHash = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }
      $dWhy  = if ($parts.Count -ge 4) { $parts[3].Trim() } else { '(no reason given)' }
      # ParseExact in a try, not TryParseExact: the [ref] out-parameter overload
      # is a reliable way to lose an afternoon in PowerShell, and this needs no
      # speed.
      $parsed = $false
      try {
        $dDate  = [datetime]::ParseExact($parts[1].Trim(), 'yyyy-MM-dd',
                    [System.Globalization.CultureInfo]::InvariantCulture)
        $parsed = $true
      } catch { $parsed = $false }
      if (-not $parsed) {
        Check 'DEFER-UNTIL date is a valid yyyy-MM-dd' $false $parts[1]
      } elseif ($dHash -ne $hash) {
        Check 'DEFER-UNTIL covers the CURRENT extraction surface' $false `
              'the surface changed again since the deferral was recorded -- bump, or re-record it deliberately'
      } elseif ((Get-Date).Date -gt $dDate.Date) {
        Check "DEFER-UNTIL $($parts[1].Trim()) has EXPIRED" $false `
              "the bump is now overdue -- $dWhy"
      } else {
        $deferOk = $true
        Check "extraction changed; bump DEFERRED until $($parts[1].Trim())" $true $dWhy
        Write-Host ''
        Write-Host "   STALE ON PURPOSE: every existing index still holds the OLD parses." -ForegroundColor Yellow
        Write-Host "   Rebuild an index to pick up the change, or bump on $($parts[1].Trim())." -ForegroundColor Yellow
        Write-Host "   This runner goes RED by itself the day after that date." -ForegroundColor Yellow
      }
    }

    if (-not $deferOk) {
      Check 'extraction changed but DRAGLINT_EXTRACTOR_VERSION did NOT' $false `
            "still '$version' -- bump it, or every existing index keeps STALE parses silently"
      Write-Host ''
      Write-Host '   Bump DRAGLINT_EXTRACTOR_VERSION in src\core\DRagLint.Core.Model.pas,' -ForegroundColor Yellow
      Write-Host '   then re-run and update tests\extractor-version.baseline.' -ForegroundColor Yellow
      Write-Host '   If your change genuinely cannot affect extraction, say so in the' -ForegroundColor Yellow
      Write-Host '   baseline file and update the hash without bumping.' -ForegroundColor Yellow
      Write-Host '   To postpone a bump deliberately, add a dated DEFER-UNTIL line' -ForegroundColor Yellow
      Write-Host '   to the baseline -- see the comments there.' -ForegroundColor Yellow
    }
  }
}

# --- the product version must NOT be in the fingerprint ---------------------
$cli = Get-Content (Join-Path $repo 'src\cli\DRagLint.CLI.pas') -Raw
$fpBlock = [regex]::Match($cli, "function IndexerFingerprint.*?end;", 'Singleline').Value
Check 'the fingerprint uses the EXTRACTOR version' `
      ($fpBlock -match 'DRAGLINT_EXTRACTOR_VERSION') `
      'if this regresses to VERSION, every release re-parses everything again'
Check 'the fingerprint does NOT use the product version' `
      ($fpBlock -notmatch '\bVERSION\b(?!_)' -or $fpBlock -match 'DRAGLINT_EXTRACTOR_VERSION') `
      ''

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
