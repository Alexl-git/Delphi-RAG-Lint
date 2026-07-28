<#
  run_encoding_guard.ps1 -- byte-level guard for source files. Register HAZARD H1.

  Why this exists
  ---------------
  T3j's implementer converted two .pas files from CRLF to LF (737 and 918 lone
  LFs) with a scripted edit. Every signal this project relies on missed it:

    * the content diff looked clean -- a line-ending change is invisible in a
      textual diff;
    * git's commit-time normalization would have written a CORRECT blob while
      the on-disk file, which dcc64 actually reads, stayed wrong;
    * the build passed;
    * the full battery passed 185/187.

  It was caught only because that implementer ran a byte-level check by hand.
  This runner is that check, wired into the battery so nobody has to remember.

  c:\Projects\CLAUDE.md: .pas and .dfm are strict CRLF, 7-bit ASCII, no BOM.

  What the rule IS, and how it was settled -- by measurement, twice
  ----------------------------------------------------------------
  Both file classes looked "mixed" and neither was. In each case the drift was
  in ONE WORKING TREE while the repo's declared rule was never in doubt:

    .ps1       89 of 195 were LF on disk, and no directory was uniform either
               way (tests\autotest 44/22, tests\autodoc 30/22; the docp3 family
               20 LF / 3 CRLF, not "one outlier of seven").
    .pas/.dfm  77 LF + 3 MIXED of 550, concentrated in tests\lint and src\config.

  .gitattributes declares `text eol=crlf` for *.pas (:2), *.dfm (:5) and *.ps1
  (:11); core.autocrlf is true; and every one of those files is stored LF in the
  index. So the checkout filter decides what a clone gets, and a scratch clone
  measured it: A FRESH CHECKOUT PRODUCES 195/195 CRLF .ps1, and by the same
  attribute all 550 .pas/.dfm. The drifted files were post-checkout writes by
  tools, invisible to git because the index blob is LF either way.

  T3k renormalized both classes (91 .ps1, then 80 .pas/.dfm), each time proving
  content-invariance three ways: LF-normalized md5 unchanged; `git diff` empty;
  `git hash-object --path` equal to the index sha. Zero committed content change
  resulted -- which is precisely why the drift was invisible in the first place.

  THERE IS DELIBERATELY NO BASELINE FILE
  --------------------------------------
  An earlier version of this runner shipped an 80-entry baseline exempting those
  .pas/.dfm files, on the stated grounds that they "predate that rule being
  enforced by anything" and that rewriting them would be a large untestable
  change. BOTH halves were false, and the second was never measured:

    * the 80 were exactly the drifted set, every one carrying
      `attr/text eol=crlf`, so a fresh clone already produced them as CRLF. The
      baseline asserted something about the repo that the repo's own attributes
      disproved, and on any fresh checkout it would have emitted ~80 "entry is
      now clean, remove it" lines while still passing;
    * NOTHING depends on their on-disk line endings. Measured, not assumed: no
      runner that reads bytes (ReadAllBytes / Get-FileHash / SequenceEqual)
      touches any of them; tests\lint\run_lint_tests.ps1, which owns 42 of the
      80, asserts `rule:start_line` pairs, and line NUMBERS are unchanged when
      LF becomes CRLF; the autofix runners copy fixtures to scratch before
      editing. The full battery was then re-run with all 80 converted.

  So within the scope below there is no allowlist, and a new violation is a
  failure. If you are tempted to add an exemption list: measure first. That is
  what turned this file from an 80-entry allowlist into no allowlist at all.

  SCOPE IS BOUNDED, AND THE BOUND IS SELF-REPORTING
  -------------------------------------------------
  An earlier version of this header claimed "the rule below is universal and a
  new violation ANYWHERE is a failure". It was not: the scan covered .ps1/.pas/
  .dfm while .gitattributes also declares *.dpr, *.dpk and *.inc, and FIVE such
  files were lone-LF drifted at the time -- src\config\drag-lint-config.dpr (34),
  build\phase0_smoke.dpr, tests\fixtures\T59_workspace_config.dpr,
  tests\fixtures\manifest\app\App.dpr and .../uAlpha.inc. H1 realised, in real
  compiled source, uncaught by the guard built to catch it. A universal claim
  over a partial scan is the same defect class as the deleted baseline: text
  that is broader than what ships.

  Fixed two ways. The three Delphi extensions are now scanned and those five
  files renormalized (same three-way content-invariance proof), AND the gap is
  now structural rather than a promise: the $roots table below is checked
  against .gitattributes, and every extension declared `text eol=crlf` that
  $roots does not cover must appear in $DeclaredNotScanned with a reason -- or
  the guard FAILS. A new extension added to .gitattributes is in neither, so it
  surfaces immediately instead of silently widening a claim nobody re-reads.

  The DIRECTORY bound works the same way, and it had to be fixed the same way.
  Round 2 listed unscanned directories in $UnscannedRoots and merely PRINTED
  them, while the header claimed the bound was "stated where it is enforced".
  It was not enforced -- nothing enumerated directories, so unlike the extension
  bound it could not fail -- and the list was incomplete: third_party\ (11
  scannable files, 6 of them violating), tools\ and scratchpad\ were all absent.
  Every top-level directory holding a scannable file is now enumerated and must
  be scanned or excluded with a printed reason.

  Checks
  ------
    .ps1                      under src\ tests\ build\ stats\ tools\
    .pas .dpr .dpk .dfm .inc  under src\ tests\ build\ tools\
        -> zero lone LF, no BOM, zero bytes >127
    every extension .gitattributes declares `text eol=crlf` is either scanned or
    listed in $DeclaredNotScanned with a reason
    every top-level directory holding a scannable file is either scanned or
    listed in $UnscannedRoots with a reason
    .gitattributes still declares the rule this runner asserts

  Both bounds -- EXTENSION and DIRECTORY -- are ASSERTED, not described. Nothing
  here claims coverage of the whole repo, and the parts it does not cover are
  named where they are enforced rather than in prose.

  SCOPE DECISION, flagged rather than left implicit: CLAUDE.md writes the
  7-bit-ASCII / no-BOM rule for .pas and .dfm. This runner applies it to .ps1
  too. That is deliberate and broader than the letter of the rule -- a non-ASCII
  byte in a runner is a real hazard under a different console codepage, and
  run_smoke.ps1 was carrying three UTF-8 em dashes when this was written.
  Recorded so a future reader can reverse it knowingly rather than meet it as an
  accident.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_encoding_guard.ps1
#>
[CmdletBinding()]
param(
  [string] $Repo = "$PSScriptRoot\..\.."
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

# --- fixtures that violate the rule ON PURPOSE ------------------------------
# The ONLY exemptions. Each is a load-bearing test input that must never be
# "fixed", and each names the runner that depends on it. This is not a baseline:
# a baseline records drift and is supposed to shrink; these are permanent.
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
$roots = [ordered]@{
  '.ps1' = @('src', 'tests', 'build', 'stats', 'tools')
  '.pas' = @('src', 'tests', 'build', 'tools')
  '.dpr' = @('src', 'tests', 'build', 'tools')
  '.dpk' = @('src', 'tests', 'build', 'tools')
  '.dfm' = @('src', 'tests', 'build', 'tools')
  '.inc' = @('src', 'tests', 'build', 'tools')
}

# Extensions .gitattributes declares `text eol=crlf` that this runner does NOT
# scan, each with the reason. Checked against .gitattributes below, so this list
# cannot quietly fall out of date and the header cannot claim more than the scan
# delivers. To scan one, delete its entry and add it to $roots.
$DeclaredNotScanned = [ordered]@{
  '.bat' = 'MEASURED, deliberately deferred (register K8). Tracked: 19 drifted of 88 (16 pure LF + 3 MIXED) -- build\ 9, tests\ 8, src\ 1, repo root 1. Whole working tree incl. untracked: 26 drifted of 95, 5 MIXED (build\ 9, tests\ 8, repo root 5, scratchpad\ 3, src\ 1). Commands: `git ls-files --eol -- "*.bat" "*.cmd"` and a byte scan of every .bat/.cmd in the tree. cmd.exe is not merely tolerant of line endings the way dcc is -- label and goto handling can differ -- so "does anything depend on these bytes" needs its own measurement before a bulk rewrite. That measurement is exactly what the deleted baseline skipped; not repeating the mistake in the other direction.'
  '.cmd' = 'Same family as .bat and the same open measurement. Note there are ZERO tracked .cmd files in the repo, so this entry is forward-looking rather than covering anything that exists today.'
}

# Directories holding scannable extensions that are deliberately OUT of $roots.
# ASSERTED below, not merely printed: the extension bound was over-claimed once
# (see the header) and a bound that cannot fail is not a bound. Every top-level
# directory containing a scannable extension must be either scanned or listed
# here with a reason, or the guard FAILS.
$UnscannedRoots = [ordered]@{
  'docs'        = 'docs\examples\ holds third-party reproduction material, some of it UNTRACKED (the DevExpress printer-crash repro, whose PrinterCrashRepro.dpr is lone-LF), whose bytes are part of the reproduction and are not this repo''s to normalize. The two TRACKED units under docs\examples\circular-uses-demo\ were renormalized by T3k anyway, since they are ordinary repo content.'
  'third_party' = 'VENDORED UPSTREAM CODE (delphi-tree-sitter, 16 tracked files). Normalizing it would diverge this copy from upstream and make every future sync a conflict. Named rather than silently omitted, because 6 of its 11 scannable files DO violate the rule: ConsoleReadPasFile.dpr, VCLDemo\DelphiTreeSitterVCLDemo.dpr, VCLDemo\frmDTSLanguage.pas, VCLDemo\frmDTSMain.pas and VCLDemo\frmDTSQuery.pas each carry a UTF-8 BOM, and TreeSitterLib.pas carries one high byte. That is upstream''s encoding choice, not drift in this repo.'
  'scratchpad'  = 'GITIGNORED working scratch (.gitignore:71). Nothing in it is tracked, so there is no repo state to protect; dumptree.dpr and test-ast.pas are both lone-LF and that is harmless.'
}
$badLf  = New-Object System.Collections.Generic.List[string]
$badBom = New-Object System.Collections.Generic.List[string]
$badHi  = New-Object System.Collections.Generic.List[string]
$scanned = 0

foreach ($ext in $roots.Keys) {
  foreach ($r in $roots[$ext]) {
    $dir = Join-Path $Repo $r
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Recurse -File -Filter "*$ext" -ErrorAction SilentlyContinue | ForEach-Object {
      $rel = $_.FullName.Substring($Repo.Length + 1).Replace('\', '/')
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
      if ($lone -gt 0) { $badLf.Add(("{0}  ({1} lone LF)" -f $rel, $lone)) }
      if ($bom) { $badBom.Add($rel) }
      # The BOM itself is three high bytes; do not double-report it.
      if ($hi -gt 0 -and -not ($bom -and $hi -le 3)) { $badHi.Add(("{0}  ({1} bytes >127)" -f $rel, $hi)) }
    }
  }
}

Check 'files scanned' ($scanned -gt 0) "($scanned)"

# --- assertions ------------------------------------------------------------
Check 'no file has a lone LF' ($badLf.Count -eq 0) "($($badLf.Count) offender(s))"
foreach ($x in $badLf) { Write-Host "        $x" -ForegroundColor Red }
if ($badLf.Count -gt 0) {
  Write-Host '        ^ a CRLF file became LF. A scripted or regex-based edit does this' -ForegroundColor Yellow
  Write-Host '          silently, and neither the diff, the build, nor a green battery' -ForegroundColor Yellow
  Write-Host '          will tell you -- git normalizes on commit, so the COMMITTED blob' -ForegroundColor Yellow
  Write-Host '          is correct while the on-disk file dcc reads is wrong.' -ForegroundColor Yellow
  Write-Host '          Convert it back to CRLF. Do NOT add an exemption list:' -ForegroundColor Yellow
  Write-Host '          .gitattributes already makes CRLF what a fresh clone produces, so' -ForegroundColor Yellow
  Write-Host '          an exemption would assert something untrue about the repo.' -ForegroundColor Yellow
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

# --- the rule this runner asserts must still be the declared rule ----------
# Without this, someone could relax .gitattributes and the assertions above
# would quietly be enforcing a convention the repo no longer claims.
$ga = Join-Path $Repo '.gitattributes'
$gaText = if (Test-Path $ga) { Get-Content $ga -Raw } else { '' }
Check '.gitattributes present' (Test-Path $ga)

foreach ($ext in $roots.Keys) {
  Check ".gitattributes still declares *$ext text eol=crlf" `
    ($gaText -match ("(?m)^\*{0}\s+text\s+eol=crlf" -f [regex]::Escape($ext)))
}

# --- the scan's BOUND must match what the repo declares --------------------
# Without this the header could once again claim more than the scan delivers --
# which is exactly how five drifted .dpr/.inc files sat uncaught. Every
# extension .gitattributes declares must be either scanned or listed as a
# deliberate exclusion WITH a reason; a new one is neither, so it fails here.
$declared = @([regex]::Matches($gaText, '(?m)^\*(\.\w+)\s+text\s+eol=crlf') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
Check 'declared eol=crlf extensions parsed from .gitattributes' ($declared.Count -gt 0) "($($declared -join ' '))"
$unaccounted = @($declared | Where-Object { -not $roots.Contains($_) -and -not $DeclaredNotScanned.Contains($_) })
Check 'every declared eol=crlf extension is scanned or excluded with a reason' ($unaccounted.Count -eq 0) `
  $(if ($unaccounted.Count -gt 0) { "unaccounted: $($unaccounted -join ' ')" } else { '' })
if ($unaccounted.Count -gt 0) {
  Write-Host '        ^ .gitattributes declares an extension this runner neither scans nor' -ForegroundColor Yellow
  Write-Host '          deliberately excludes. Add it to $roots, or to $DeclaredNotScanned' -ForegroundColor Yellow
  Write-Host '          with the reason. Do NOT leave the header claiming coverage it lacks.' -ForegroundColor Yellow
}
foreach ($k in $DeclaredNotScanned.Keys) {
  Write-Host ("  [NOTE] declared but NOT scanned: *{0}" -f $k) -ForegroundColor DarkGray
  Write-Host ("         {0}" -f $DeclaredNotScanned[$k]) -ForegroundColor DarkGray
}

# --- the ROOT bound, asserted the same way the extension bound is -----------
# This used to be a printed list and a sentence in the header claiming the bound
# was "stated where it is enforced". It was not enforced at all: nothing
# enumerated directories, so unlike the extension bound it could not fail, and
# the list was incomplete -- third_party\ (11 scannable files, 6 of them
# violating), tools\ and scratchpad\ were all missing while the header implied
# full coverage. A bound that cannot fail is not a bound.
$scannedDirs = @($roots.Values | ForEach-Object { $_ } | Sort-Object -Unique)
$dirsWithScannable = New-Object System.Collections.Generic.List[string]
foreach ($d in (Get-ChildItem -LiteralPath $Repo -Directory -ErrorAction SilentlyContinue)) {
  if ($d.Name.StartsWith('.')) { continue }   # .git, .superpowers -- no build inputs
  $hit = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Include $($roots.Keys | ForEach-Object { "*$_" }) `
           -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $hit) { $dirsWithScannable.Add($d.Name) }
}
Check 'top-level directories holding scannable files enumerated' ($dirsWithScannable.Count -gt 0) `
  "($($dirsWithScannable -join ' '))"

$unaccountedDirs = @($dirsWithScannable | Where-Object { ($scannedDirs -notcontains $_) -and (-not $UnscannedRoots.Contains($_)) })
Check 'every directory holding scannable files is scanned or excluded with a reason' ($unaccountedDirs.Count -eq 0) `
  $(if ($unaccountedDirs.Count -gt 0) { "unaccounted: $($unaccountedDirs -join ' ')" } else { '' })
if ($unaccountedDirs.Count -gt 0) {
  Write-Host '        ^ a directory holds .pas/.dpr/.dfm/.inc/.dpk/.ps1 files that this' -ForegroundColor Yellow
  Write-Host '          guard never looks at. Add it to $roots, or to $UnscannedRoots with' -ForegroundColor Yellow
  Write-Host '          the reason. Do NOT leave it merely unmentioned -- that is how' -ForegroundColor Yellow
  Write-Host '          third_party''s 6 violating files stayed invisible.' -ForegroundColor Yellow
}
foreach ($k in $UnscannedRoots.Keys) {
  Write-Host ("  [NOTE] directory NOT scanned: {0}\" -f $k) -ForegroundColor DarkGray
  Write-Host ("         {0}" -f $UnscannedRoots[$k]) -ForegroundColor DarkGray
}

Write-Host ''
if ($script:Failed) { Write-Host 'ENCODING GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ENCODING GUARD: PASS' -ForegroundColor Green
exit 0
