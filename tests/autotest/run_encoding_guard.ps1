<#
  run_encoding_guard.ps1 -- byte-level guard for source files. Register HAZARD H1.

  Why this exists
  ---------------
  T3j's implementer converted two .pas files from CRLF to LF (737 and 918 lone
  LFs) with a scripted edit, and EVERY signal this project relies on missed it:

    * the content diff looked clean -- a line-ending change is invisible in a
      textual diff;
    * git's commit-time normalization would have written a CORRECT blob while
      the on-disk file, which dcc64 actually reads, stayed wrong;
    * the build passed;
    * the full battery passed 185/187.

  It was caught only because that implementer ran a byte-level check by hand.
  This runner is that check, wired into the battery so nobody has to remember.

  c:\Projects\CLAUDE.md: .pas and .dfm are strict CRLF, 7-bit ASCII, no BOM.

  The .ps1 line-ending convention, and how it was settled
  ------------------------------------------------------
  This looked mixed: at the time T3k ran, 89 of 195 tracked .ps1 files were LF
  on disk and 106 were CRLF, with NO directory uniform either way (tests\autotest
  was 44 LF / 22 CRLF, tests\autodoc 30 / 22). An earlier reading called the LF
  files "a convention". They are not.

  .gitattributes:11 declares `*.ps1 text eol=crlf` REPO-WIDE, core.autocrlf is
  true, and every tracked .ps1 is stored LF in the index. A scratch clone settled
  it by measurement rather than argument: a FRESH CHECKOUT produces 195/195 CRLF.
  The LF files were post-checkout drift written by tools, invisible to git
  because the index blob is LF either way -- so "LF by convention" was true of
  one working tree and of no clone anyone else would ever make.

  T3k therefore renormalized (option (a)): 91 files converted to CRLF, proved
  content-invariant three ways (LF-normalized md5 unchanged; `git diff` empty;
  `git hash-object --path` equal to the index sha for all but the 3 files T3k
  genuinely edited), and byte-identical to the scratch clone afterwards. So the
  rule asserted below is the repo's own declared rule, and it now holds on disk.

  Checks
  ------
    .ps1  under src\ tests\ build\ stats\ : zero lone LF, no BOM, zero bytes >127
    .pas
    .dfm  under src\ tests\               : no BOM, zero bytes >127, and zero
                                            lone LF unless the file is listed in
                                            encoding_guard_baseline.txt
    .gitattributes still declares the rule this runner asserts

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_encoding_guard.ps1
#>
[CmdletBinding()]
param(
  [string] $Repo     = "$PSScriptRoot\..\..",
  [string] $Baseline = "$PSScriptRoot\encoding_guard_baseline.txt"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

$Repo = (Resolve-Path $Repo).Path
Write-Host '== source byte guard (H1) ==' -ForegroundColor Cyan

# --- the exempt list -------------------------------------------------------
$exempt = @{}
if (Test-Path $Baseline) {
  foreach ($line in [System.IO.File]::ReadAllLines($Baseline)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $exempt[($t -split "`t")[0].ToLowerInvariant()] = $true
  }
}
Check 'baseline file present' (Test-Path $Baseline) "($($exempt.Count) exempt paths)"

# --- fixtures that violate the rule ON PURPOSE ------------------------------
# Kept here rather than in the baseline file: the baseline records accidental
# history that should shrink, whereas these are load-bearing test inputs that
# must never be "fixed". Each needs the runner that depends on it named.
$DeliberateFixtures = [ordered]@{
  'tests/preprocess/fixtures/bom_main.pas' =
    'tests\preprocess\run_bom.ps1 asserts this file STARTS with EF BB BF and that the preprocessor blanks those 3 bytes without moving any offset. Removing the BOM deletes the test.'
}
foreach ($k in $DeliberateFixtures.Keys) {
  Write-Host ("  [NOTE] deliberate violation, exempt: {0}" -f $k) -ForegroundColor DarkGray
  Write-Host ("         {0}" -f $DeliberateFixtures[$k]) -ForegroundColor DarkGray
}

# --- scan ------------------------------------------------------------------
# One pass over the bytes per file: this has to stay fast enough that nobody is
# tempted to skip it. Measured well under 10 s for the whole tree.
$roots = @{
  '.ps1' = @('src', 'tests', 'build', 'stats')
  '.pas' = @('src', 'tests')
  '.dfm' = @('src', 'tests')
}
$badLf = New-Object System.Collections.Generic.List[string]
$badBom = New-Object System.Collections.Generic.List[string]
$badHi = New-Object System.Collections.Generic.List[string]
$scanned = 0
$exemptSeen = @{}

foreach ($ext in $roots.Keys) {
  foreach ($r in $roots[$ext]) {
    $dir = Join-Path $Repo $r
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Recurse -File -Filter "*$ext" -ErrorAction SilentlyContinue | ForEach-Object {
      $rel = $_.FullName.Substring($Repo.Length + 1).Replace('\', '/')
      $key = $rel.ToLowerInvariant()
      $scanned++
      if ($DeliberateFixtures.Contains($rel)) { return }
      $b = [System.IO.File]::ReadAllBytes($_.FullName)
      $lone = 0; $hi = 0
      for ($i = 0; $i -lt $b.Length; $i++) {
        $c = $b[$i]
        if ($c -eq 10) { if ($i -eq 0 -or $b[$i - 1] -ne 13) { $lone++ } }
        elseif ($c -gt 127) { $hi++ }
      }
      $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) -or
             ($b.Length -ge 2 -and (($b[0] -eq 0xFF -and $b[1] -eq 0xFE) -or ($b[0] -eq 0xFE -and $b[1] -eq 0xFF)))
      if ($exempt.ContainsKey($key)) {
        $exemptSeen[$key] = $true
        # An exempt file is exempt from the LINE-ENDING check only. A BOM or a
        # non-ASCII byte in it is still a failure -- those were never tolerated.
        if ($lone -eq 0) { Write-Host ("  [INFO] baseline entry is now clean, remove it: {0}" -f $rel) -ForegroundColor DarkGray }
      }
      elseif ($lone -gt 0) { $badLf.Add(("{0}  ({1} lone LF)" -f $rel, $lone)) }
      if ($bom) { $badBom.Add($rel) }
      # The BOM itself is three high bytes; do not double-report it.
      if ($hi -gt 0 -and -not ($bom -and $hi -le 3)) { $badHi.Add(("{0}  ({1} bytes >127)" -f $rel, $hi)) }
    }
  }
}

Check 'files scanned' ($scanned -gt 0) "($scanned)"

# --- assertions ------------------------------------------------------------
Check 'no unbaselined file has a lone LF' ($badLf.Count -eq 0) "($($badLf.Count) offender(s))"
foreach ($x in $badLf) { Write-Host "        $x" -ForegroundColor Red }
if ($badLf.Count -gt 0) {
  Write-Host '        ^ a CRLF file became LF. A scripted or regex-based edit does this' -ForegroundColor Yellow
  Write-Host '          silently, and neither the diff, the build, nor a green battery' -ForegroundColor Yellow
  Write-Host '          will tell you. Convert it back to CRLF -- do NOT add it to the' -ForegroundColor Yellow
  Write-Host '          baseline, which records history, not new damage.' -ForegroundColor Yellow
}

Check 'no BOM in any source file' ($badBom.Count -eq 0) "($($badBom.Count) offender(s))"
foreach ($x in $badBom) { Write-Host "        $x" -ForegroundColor Red }

Check 'no byte >127 in any source file' ($badHi.Count -eq 0) "($($badHi.Count) offender(s))"
foreach ($x in $badHi) { Write-Host "        $x" -ForegroundColor Red }
if ($badHi.Count -gt 0) {
  Write-Host '        ^ dcc reads a BOM-less .pas as ANSI, so a UTF-8 character in a' -ForegroundColor Yellow
  Write-Host '          STRING LITERAL ships as mojibake. That was not hypothetical:' -ForegroundColor Yellow
  Write-Host '          before T3k the MCP tools/list response emitted an em dash as' -ForegroundColor Yellow
  Write-Host '          \u00E2\u20AC\u201D. Replace with 7-bit ASCII.' -ForegroundColor Yellow
}

# --- the baseline must not rot ---------------------------------------------
$stale = @($exempt.Keys | Where-Object { -not $exemptSeen.ContainsKey($_) })
foreach ($x in $stale) { Write-Host ("  [INFO] baseline names a file that no longer exists: {0}" -f $x) -ForegroundColor DarkGray }

# --- the rule this runner asserts must still be the declared rule ----------
# Without this, someone could relax .gitattributes and the assertion above would
# quietly be enforcing a convention the repo no longer claims.
$ga = Join-Path $Repo '.gitattributes'
$gaOk = (Test-Path $ga) -and ((Get-Content $ga -Raw) -match '(?m)^\*\.ps1\s+text\s+eol=crlf')
Check '.gitattributes still declares *.ps1 text eol=crlf' $gaOk
$gaPas = (Test-Path $ga) -and ((Get-Content $ga -Raw) -match '(?m)^\*\.pas\s+text\s+eol=crlf')
Check '.gitattributes still declares *.pas text eol=crlf' $gaPas

Write-Host ''
if ($script:Failed) { Write-Host 'ENCODING GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ENCODING GUARD: PASS' -ForegroundColor Green
exit 0
