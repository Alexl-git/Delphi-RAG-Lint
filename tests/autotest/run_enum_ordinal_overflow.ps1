<#
  run_enum_ordinal_overflow.ps1 -- finding A: an enum-ordinal overflow made NINE
  units SILENTLY ABSENT from every index since 2026-07-26 (18bbbc8).

  THE DEFECT. TryWalkEnum (src\parser\DRagLint.Parser.Delphi13.pas) kept the
  running enum ordinal in an Integer. The `= $7FFFFFFF` / `= 2147483647`
  terminal-member idiom -- the FORCE_DWORD pattern that pins a Delphi enum to
  32 bits -- sets the counter to High(Integer); the value is EMITTED correctly,
  and the unconditional `Inc(EnumOrd)` on the next line then raises EIntOverflow
  because the deployed engine is Win64 DEBUG with DCC_IntegerOverflowCheck=true
  (src\cli\drag-lint.dproj:87). The counter represents "last ordinal + 1", whose
  range is Low(Integer)..High(Integer)+1 -- it does not fit an Integer by exactly
  one value, and that one value is the one these headers hit.

  WHY THE FILE VANISHES RATHER THAN ERRORING. The exception leaves Parser.Parse
  BEFORE Core.Indexer.pas:981 OpenFileTx, so the file gets NO `files` row -- no
  symbols, no refs, no literals, no docs. Two catch sites (Core.Indexer.pas:1290
  folder walk, CLI.pas:2755 IndexOneFileTolerant) print
  `SKIP <path>: EIntOverflow: Integer overflow`, increment no error counter, and
  leave the exit code at 0. Because the file has no row it is never "up to date",
  so every later run re-attempts and re-SKIPs it. Nine units were affected:
  Winapi.D3D10, Winapi.D3DCommon, Winapi.D3DCompiler, Winapi.D3DX10,
  Winapi.DXGI1_2, WinAPI.Media, WinAPI.UI.Core and dxFontFile (x2 platforms).

  EXIT CODE IS NOT THE SIGNAL. `index` exits 0 on BOTH engines. A guard that
  asserted only the exit code would have been green throughout the defect's life.
  The signals are the SKIP line and the absence of the file's symbols.

  WHY IT MUST GO THROUGH `index`. TryWalkEnum is reached only via
  TDelphi13Parser.Parse, the INDEXER entry point. `lint` holds its own TTSParser
  and emits no symbols, so no lint-path guard can see this. A DIRECTORY target
  against a FRESH scratch DB is the library-shaped scan and is correct here; the
  repo rule "never `index <dir> --db <projectDb>`" is about widening an EXISTING
  project database, which this is not.

  THE CONTROLS ARE THE POINT. Checks 6-9 (uCtl.pas, and a symbol that does not
  exist) must PASS on the PRE-FIX engine. If they do not, this runner is
  measuring the query path rather than the parser, and every FAIL below is
  meaningless. uCtl also pins the reset-then-continue ordinal semantics
  (ctA=0, ctB=128, ctC=129) that the fix must not disturb.

  MEASURED RED, THEN GREEN.

  RED -- 2026-09-09 against the PRE-FIX engine copy taken before any edit
  (C:\TEMP\draglint-prefix-engine-2026-09-09, extractor_version 1.13.0-alpha),
  8 PASS / 8 FAIL, verbatim:

    [PASS] index exits 0 and the DB exists exit=0
    [FAIL] no EIntOverflow SKIP for uOvfMax.pas found 1
    [PASS] no SKIP of any kind for uCtl.pas found 0
    [PASS] ctA -> 0 hits=1 signature='0'
    [PASS] ctB -> 128 hits=1 signature='128'
    [PASS] ctC -> 129 hits=1 signature='129'
    [PASS] --exact does not match a symbol that does not exist hits=0
    [FAIL] ohA -> 0 hits=0 signature=''
    [FAIL] ohB -> 5 hits=0 signature=''
    [FAIL] ohForce -> 2147483647 hits=0 signature=''
    [FAIL] olForce -> 2147483647 hits=0 signature=''
    [FAIL] odOnly -> 2147483647 hits=0 signature=''
    [FAIL] OvfMarkerConst is present hits=0
    [FAIL] the uOvfMax unit row is present hits=0

  Note what that RED reading proves beyond "the enum broke": ohA and ohB are
  ordinary members declared BEFORE the hazard, and OvfMarkerConst is not in an
  enum at all. All three are missing, because the unit of loss is the FILE.

  GREEN -- 2026-09-09, SAME runner, against the fixed engine deployed to
  third_party\dll-win64 (extractor_version 1.14.0-alpha): 16 PASS / 0 FAIL.
  Every line above that read FAIL now reads PASS with hits=1 and the expected
  signature (ohForce/olForce/odOnly all signature='2147483647'), and every
  control still passes -- so the two runs differ in the ENGINE and nothing else.

  Run from a NEUTRAL CWD, pwsh 7.
    pwsh -File tests\autotest\run_enum_ordinal_overflow.ps1
    pwsh -File tests\autotest\run_enum_ordinal_overflow.ps1 -Exe <pre-fix engine>
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'

# A drag-lint `query` with ZERO matches EXITS 1 (measured 2026-09-09). pwsh 7.4+
# can promote a native non-zero exit to a terminating error, which would kill
# this runner at its first legitimate empty result -- the NEGATIVE CONTROL, and
# every RED reading below. Pin it off so an exit code is never read as a failure.
$PSNativeCommandUseErrorActionPreference = $false

$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("enumovf_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$db = Join-Path $WorkDir 'enumovf.sqlite'

# WHICH ENGINE WAS MEASURED. A RED reading that reports the POST-fix extractor
# version is not a RED reading -- it is the new engine run by mistake.
$infoRaw = (& $exePath info --json 2>$null) -join "`n"
$extractorVersion = '(unknown)'
try {
  $line = ($infoRaw -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -First 1)
  if ($line) { $extractorVersion = ([string]($line | ConvertFrom-Json).extractor_version) }
} catch { }
Write-Host ''
Write-Host ("engine : {0}" -f $exePath) -ForegroundColor Cyan
Write-Host ("extractor_version : {0}" -f $extractorVersion) -ForegroundColor Cyan

# --- Fixtures (inline, ASCII, CRLF -- no .pas files are committed) ----------

# The three real-world spellings of the idiom, one enum each, PLUS a const that
# sits OUTSIDE any enum. The const is what proves the WHOLE FILE committed, not
# merely that the enum walk survived.
$srcOvf = @(
  'unit uOvfMax;',
  'interface',
  'const',
  '  OvfMarkerConst = 1;',
  'type',
  '  TOvfHexUpper = (ohA, ohB = 5, ohForce = $7FFFFFFF);',
  '  TOvfHexLower = (olForce = $7fffffff);',
  '  TOvfDecimal  = (odOnly = 2147483647);',
  'implementation',
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $WorkDir 'uOvfMax.pas'), $srcOvf + "`r`n", [Text.Encoding]::ASCII)

# POSITIVE CONTROL: no overflow, and it exercises reset-then-continue ordinals.
$srcCtl = @(
  'unit uCtl;',
  'interface',
  'type',
  '  TCtl = (ctA, ctB = 128, ctC);',
  'implementation',
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $WorkDir 'uCtl.pas'), $srcCtl + "`r`n", [Text.Encoding]::ASCII)

# --- 1-2. Fixture sanity: the fixtures are what this guard claims -----------

$ovfText = [IO.File]::ReadAllText((Join-Path $WorkDir 'uOvfMax.pas'))
$ctlText = [IO.File]::ReadAllText((Join-Path $WorkDir 'uCtl.pas'))

# Case-SENSITIVE counts: the upper- and lower-case hex spellings are two distinct
# real-world forms (D3DCommon vs D3D10) and a case-insensitive count would let one
# stand in for the other.
function CountC([string]$Haystack, [string]$Pattern) {
  return @([regex]::Matches($Haystack, $Pattern, [Text.RegularExpressions.RegexOptions]::None)).Count
}

Write-Host ''
Write-Host 'FIXTURE SANITY -- the fixtures carry the idiom this guard is about' -ForegroundColor Cyan
$nUpper = CountC $ovfText '\$7FFFFFFF'
$nLower = CountC $ovfText '\$7fffffff'
$nDec   = CountC $ovfText '2147483647'
Check 'uOvfMax.pas carries the UPPER-case hex form exactly once' ($nUpper -eq 1) "count=$nUpper"
Check 'uOvfMax.pas carries the lower-case hex form exactly once' ($nLower -eq 1) "count=$nLower"
Check 'uOvfMax.pas carries the decimal form exactly once'        ($nDec   -eq 1) "count=$nDec"
Check 'uCtl.pas carries NONE of the three forms' `
  ((CountC $ctlText '\$7FFFFFFF') -eq 0 -and (CountC $ctlText '\$7fffffff') -eq 0 -and (CountC $ctlText '2147483647') -eq 0) `
  'the control must not contain the hazard, or it cannot control for it'

# --- 3-5. The index run ------------------------------------------------------

$idxOut  = & $exePath index $WorkDir --db $db 2>&1
$idxExit = $LASTEXITCODE
$idxText = ($idxOut | Out-String)

Write-Host ''
Write-Host 'THE INDEX RUN -- exit code is NOT the signal for this defect' -ForegroundColor Cyan
Check 'index exits 0 and the DB exists' ($idxExit -eq 0 -and (Test-Path $db)) `
  "exit=$idxExit -- THIS PASSES ON BOTH ENGINES; the defect never changed the exit code"

if (-not (Test-Path $db)) {
  Write-Host $idxText -ForegroundColor DarkGray
  Write-Host 'FAIL' -ForegroundColor Red; exit 1
}

$skipOvf = @([regex]::Matches($idxText, 'SKIP[^\r\n]*uOvfMax\.pas: EIntOverflow')).Count
$skipCtl = @([regex]::Matches($idxText, 'SKIP[^\r\n]*uCtl\.pas')).Count
Check 'no EIntOverflow SKIP for uOvfMax.pas' ($skipOvf -eq 0) `
  "found $skipOvf -- pre-fix this is 1 and the file gets no files row at all"
Check 'no SKIP of any kind for uCtl.pas' ($skipCtl -eq 0) "found $skipCtl"

# --- Query helper ------------------------------------------------------------

function Find-Sym([string]$Name) {
  $raw = (& $exePath query --name $Name --exact --db $db --json 2>$null) -join "`n"
  if (-not $raw.Trim()) { return @() }
  try { $d = $raw | ConvertFrom-Json } catch { return @() }
  return @($d | Where-Object { $null -ne $_ })
}

# Returns the first hit's signature, or '' -- and NEVER indexes an empty array.
# Under ErrorActionPreference Stop, indexing an empty array THROWS and kills the
# runner mid-file, so every assertion after the first failure would report
# nothing. That is a recorded scar of run_comment_corpus.ps1's own RED run.
function SigOf($Hits) {
  if ($null -eq $Hits) { return '' }
  $a = @($Hits)
  if ($a.Count -lt 1) { return '' }
  return [string]$a[0].signature
}

function CheckOrd([string]$Name, [string]$Expected, [string]$Note = '') {
  $h = Find-Sym $Name
  $sig = SigOf $h
  Check ("{0} -> {1}" -f $Name, $Expected) ($h.Count -eq 1 -and $sig -eq $Expected) `
    ("hits={0} signature='{1}' {2}" -f $h.Count, $sig, $Note)
}

# --- 6-9. POSITIVE / NEGATIVE CONTROLS -- must PASS on the PRE-FIX engine ----

Write-Host ''
Write-Host 'CONTROLS -- these must PASS on the PRE-FIX engine too' -ForegroundColor Cyan
Write-Host '  (if any of these fails, this runner is measuring the QUERY path, not the parser -- STOP)' -ForegroundColor DarkGray
CheckOrd 'ctA' '0'   'positional ordinal'
CheckOrd 'ctB' '128' 'explicit initializer resets the counter'
CheckOrd 'ctC' '129' 'reset-then-continue semantics -- the fix must not disturb this'
$none = Find-Sym 'NoSuchSymbolZq'
Check '--exact does not match a symbol that does not exist' ($none.Count -eq 0) `
  "hits=$($none.Count) -- without this, every 'hits=1' below could be --exact matching everything"

# --- 10-15. THE FIX: RED pre-fix, GREEN post-fix -----------------------------

Write-Host ''
Write-Host 'THE DEFECT -- every one of these is RED on the pre-fix engine' -ForegroundColor Cyan
CheckOrd 'ohA'     '0'          'members BEFORE the terminal one were lost WITH THE FILE, not just the terminal one'
CheckOrd 'ohB'     '5'          'explicit initializer, still below the hazard'
CheckOrd 'ohForce' '2147483647' 'UPPER-case hex -- the D3DCommon / dxFontFile form'
CheckOrd 'olForce' '2147483647' 'lower-case hex -- the Winapi.D3D10 form'
CheckOrd 'odOnly'  '2147483647' 'decimal -- the WinAPI.Media / WinAPI.UI.Core form'

$marker = Find-Sym 'OvfMarkerConst'
Check 'OvfMarkerConst is present' ($marker.Count -eq 1) `
  "hits=$($marker.Count) -- a const OUTSIDE the enum: this is what proves the WHOLE FILE committed"

$unitRow = Find-Sym 'uOvfMax'
Check 'the uOvfMax unit row is present' ($unitRow.Count -eq 1) `
  "hits=$($unitRow.Count) -- a project/library DB holds only indexed members, so a hit IS membership"

try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
Write-Host ("measured against extractor_version {0}" -f $extractorVersion) -ForegroundColor DarkGray
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
