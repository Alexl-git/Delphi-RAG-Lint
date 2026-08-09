<#
  run_manifest_parity.ps1 -- the win32 and win64 index manifests must not drift.

  Why this exists
  ---------------
  There are TWO copies of the index manifest:

    third_party\dll-win32\drag-lint.json
    third_party\dll-win64\drag-lint.json

  and BOTH are read at runtime, by different halves of the same product. Nothing
  copies one to the other. On 2026-08-09 they had silently desynced: the win32
  copy was six sections behind, was missing the entire `docs` block, was missing
  two global exclude patterns, and was missing Library.exclude.

  WHY A DRIFT MATTERS, and why "two hashes differ" is not the point
  ----------------------------------------------------------------
  The Delphi IDE is a 32-bit process (bds.exe PE machine 0x014C), so it loads the
  WIN32 design-time BPL, which dclDragLintWizard.dproj builds to
  third_party\dll-win32. Inside that BPL:

    DragLint.Plugin.DbResolver.pas:89-92
      function ManifestPathBesideEngine: string;
      begin
        Result:= ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.json';
      end;

  In a design-time package HInstance is the BPL's OWN module handle, so despite
  the name this resolves the manifest beside the BPL -- the WIN32 copy. That is
  the function ManifestDbForFile (DbResolver.pas:94-178) uses to decide which
  section DB covers the file you are editing.

  Meanwhile every engine process the plugin spawns is the WIN64 CLI
  (DragLint.Plugin.ExeResolver.pas:33 resolves <bpl-dir>\..\dll-win64\drag-lint.exe
  by policy: "the IDE BPL is the only 32-bit artifact"), and that engine loads its
  own global config from <EngineDir>\drag-lint.json
  (DRagLint.Index.Manifest.pas:546-547) -- the WIN64 copy.

  So when the two files disagree, THE IDE AND THE CLI INDEX DIFFERENT SCOPES.
  Hover, Find Usages and the project menu resolve DBs from one manifest while
  `index --all` builds DBs from the other. Neither errors. Nothing turns red. You
  get stale or empty results in the IDE and a perfectly healthy CLI, and the two
  never contradict each other loudly enough to point at the cause. That is the
  bug this file exists to make impossible to reintroduce, and it is why the
  failure text below explains the mechanism instead of printing two hashes.

  WHY BYTE-IDENTITY RATHER THAN SEMANTIC EQUALITY OF `sections`
  -------------------------------------------------------------
  Byte-identity was chosen deliberately over comparing the parsed `sections`
  arrays, on three grounds:

    1. Nothing in this manifest is platform-specific. outDir, every section's
       include/db path, and Library's "platforms": ["Win32","Win64"] are all
       bitness-neutral. Even `defaultPlatform`, the one key that SOUNDS
       platform-specific, is not used that way: it reads "Win32" in the WIN64
       file, and did so before the two were synced.
    2. The drift actually observed was mostly OUTSIDE `sections` -- the missing
       `docs` block, the missing global excludes, the missing Library.exclude. A
       sections-only comparison would have passed on three of those four. The
       stricter check is the one that would have caught the real defect.
    3. The plugin reads the file with TFile.ReadAllText, so an encoding drift (a
       BOM, or one copy rewritten LF-only) is a real hazard that a parsed
       comparison cannot see and a byte comparison catches for free.

  If a key ever LEGITIMATELY has to differ per platform, that is a deliberate
  design change: relax this check to semantic equality of the keys that may
  differ, and record which ones and why. Do not simply let the files desync --
  the desync is invisible, which is the whole problem.

  Checks
  ------
    both manifests exist
    each parses as valid JSON, INDEPENDENTLY and BEFORE the parity check, so a
      syntax error in either surfaces here as a syntax error rather than as a
      mystery at index time (or as a bare hash mismatch)
    each exposes an indexes.sections ARRAY -- "valid JSON" alone is nearly
      vacuous, and a well-formed file of the wrong shape breaks ManifestDbForFile
      just as silently as a desync
    the two files are byte-identical (SHA256)

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_manifest_parity.ps1
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
Write-Host '== index manifest parity (win32 vs win64) ==' -ForegroundColor Cyan

$Rel = [ordered]@{
  'win32' = 'third_party\dll-win32\drag-lint.json'
  'win64' = 'third_party\dll-win64\drag-lint.json'
}

# --- existence -------------------------------------------------------------
$paths   = [ordered]@{}
$allHere = $true
foreach ($k in $Rel.Keys) {
  $p = Join-Path $Repo $Rel[$k]
  $paths[$k] = $p
  $ok = Test-Path -LiteralPath $p -PathType Leaf
  Check ("{0} manifest present" -f $k) $ok $Rel[$k]
  if (-not $ok) { $allHere = $false }
}
if (-not $allHere) {
  Write-Host '        ^ the WIN32 copy is the one the IDE plugin reads (see the header).' -ForegroundColor Yellow
  Write-Host '          A missing file is not a harmless absence: ManifestDbForFile just' -ForegroundColor Yellow
  Write-Host '          returns empty, so the IDE silently falls back to its ancestor-DB' -ForegroundColor Yellow
  Write-Host '          probe instead of using the manifest at all.' -ForegroundColor Yellow
  Write-Host ''
  Write-Host 'MANIFEST PARITY: FAIL' -ForegroundColor Red
  exit 1
}

# --- each parses as JSON, and has the shape the readers assume -------------
# Deliberately BEFORE the parity check and per-file: if someone breaks the JSON
# in one copy, "hashes differ" is a useless diagnosis of "you typed a stray
# comma". Both readers (DbResolver's hand-rolled TJSONObject walk and
# DRagLint.Index.Manifest) fail soft on malformed JSON -- they return empty
# rather than raising -- so nothing else in the product will tell you either.
foreach ($k in $paths.Keys) {
  $doc = $null
  $err = ''
  try {
    $doc = Get-Content -LiteralPath $paths[$k] -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    $err = $_.Exception.Message
  }
  Check ("{0} manifest parses as valid JSON" -f $k) ($null -ne $doc) $err

  $sections = $null
  if ($null -ne $doc -and $null -ne $doc.indexes) { $sections = $doc.indexes.sections }
  Check ("{0} manifest exposes indexes.sections as an array" -f $k) `
    ($null -ne $sections -and $sections -is [System.Array]) `
    $(if ($null -ne $sections -and $sections -is [System.Array]) { "($($sections.Count) sections)" } else { '' })
}

# --- byte-identity ---------------------------------------------------------
$h32 = (Get-FileHash -LiteralPath $paths['win32'] -Algorithm SHA256).Hash
$h64 = (Get-FileHash -LiteralPath $paths['win64'] -Algorithm SHA256).Hash
$len32 = (Get-Item -LiteralPath $paths['win32']).Length
$len64 = (Get-Item -LiteralPath $paths['win64']).Length

Check 'win32 and win64 manifests are byte-identical (SHA256)' ($h32 -eq $h64) `
  $(if ($h32 -eq $h64) { "($h32, $len64 bytes)" } else { "win32=$h32 ($len32 b)  win64=$h64 ($len64 b)" })

if ($h32 -ne $h64) {
  Write-Host '' -ForegroundColor Yellow
  Write-Host '        ^ THE IDE AND THE CLI ARE NOW INDEXING DIFFERENT SCOPES.' -ForegroundColor Yellow
  Write-Host '' -ForegroundColor Yellow
  Write-Host '          This is not a tidiness failure. The Delphi IDE is 32-bit, so it' -ForegroundColor Yellow
  Write-Host '          loads the WIN32 BPL, and DbResolver.pas:89-92 resolves the manifest' -ForegroundColor Yellow
  Write-Host '          beside the BPL via GetModuleName(HInstance) -- i.e. the win32 copy.' -ForegroundColor Yellow
  Write-Host '          Every engine the plugin spawns is the win64 CLI (ExeResolver.pas:33)' -ForegroundColor Yellow
  Write-Host '          and reads the win64 copy (Index.Manifest.pas:546).' -ForegroundColor Yellow
  Write-Host '' -ForegroundColor Yellow
  Write-Host '          So a drift means Hover / Find Usages / the project menu resolve DBs' -ForegroundColor Yellow
  Write-Host '          from one manifest while `index --all` BUILDS them from the other.' -ForegroundColor Yellow
  Write-Host '          Neither side errors. Nothing turns red. You get stale or empty' -ForegroundColor Yellow
  Write-Host '          results in the IDE and a healthy CLI, with nothing to point at.' -ForegroundColor Yellow
  Write-Host '' -ForegroundColor Yellow
  Write-Host '          FIX: copy the intended file over the other so both are identical.' -ForegroundColor Yellow
  Write-Host '          Edit BOTH from now on, or add a copy step. Do NOT silence this by' -ForegroundColor Yellow
  Write-Host '          loosening the check: nothing in this manifest is platform-specific' -ForegroundColor Yellow
  Write-Host '          (defaultPlatform reads "Win32" in the WIN64 file), so there is no' -ForegroundColor Yellow
  Write-Host '          legitimate reason for the two to differ. If that ever changes, make' -ForegroundColor Yellow
  Write-Host '          it a deliberate design change and record which keys may differ.' -ForegroundColor Yellow
  Write-Host '' -ForegroundColor Yellow
  Write-Host '          To see WHAT drifted:' -ForegroundColor Yellow
  Write-Host '            git diff --no-index third_party\dll-win32\drag-lint.json third_party\dll-win64\drag-lint.json' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'MANIFEST PARITY: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'MANIFEST PARITY: PASS' -ForegroundColor Green
exit 0
