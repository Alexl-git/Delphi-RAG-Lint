<#
  run_doc_p3_wrap.ps1 -- PHASE C, item B8: generated /// prose wraps, and only
  ENGINE-OWNED prose wraps.

  THE DEFECT (filed by YADF 2026-08-07, INBOX-autodoc-2026-08-07, item B8)
  --------------------------------------------------------------------------------
  68 emitted /// lines exceed 120 characters while the hand-written ones wrap at
  ~100. Two were extreme -- YADF.Layout.pas:103 at 759 characters on one line and
  YADFOT.Wizard.pas:33 at 659 -- because the harvester JOINS a source comment's
  wrapped lines with single spaces (that join is deliberate, see
  run_doc_p3_harvest_text.ps1) and nothing ever re-wraps the result. An
  unreviewable diff is the consequence: one changed word rewrites a 759-column
  line.

  WHY THIS RUNNER PINS THE OWNERSHIP RULE, NOT JUST THE WIDTH
  --------------------------------------------------------------------------------
  B8 was implemented once before and DELIBERATELY REVERTED, because wrapping
  applied indiscriminately changed what the merge re-parses and doc blocks
  DISAPPEARED from run_doc_p3_decayrouting's fixtures. The rule that makes
  wrapping safe is that it is keyed on OWNERSHIP: EmitTagged wraps a value only
  when its OPEN TAG carries AUTO_MARK, i.e. only when the engine generated that
  text and will regenerate it next run. A hand-written value reaches the same
  emitter through the preserve arm (MergeComment line ~2536 for <returns>, ~2371
  for <summary>) with NO marker in the open tag, and must come back byte-for-byte
  -- reflowing an author's words is a destructive edit dressed as formatting.

  So assertion 3 (the author's 200-column line SURVIVES) is not a nicety. It is
  the assertion that distinguishes this implementation from the reverted one, and
  a wrap that ignores ownership fails it.

  IDEMPOTENCY IS THE OTHER HALF. Engine-owned values are re-mined from facts on
  every run, so wrapping is a pure function of freshly-mined text and cannot
  accumulate. Assertion 4 holds that: a second apply must be a zero-byte diff.
  Progressive re-wrapping (wrap of an already-wrapped value) is the failure mode
  it catches.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_docp3wrap'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The width the emitted /// lines must respect. 100 matches what YADF's
# hand-written comments use and what B8 asked for. A line may EXCEED it only
# when it holds no wrap opportunity (a single token longer than the budget) --
# Test-WidthOk below encodes that exemption rather than pretending it cannot
# happen, because a long qualified name in a fact list genuinely cannot break.
$WRAP = 100

# The fixture's banner is ONE paragraph of ordinary short words, so every
# emitted line has somewhere to break and the exemption never fires here.
$banner = (1..40 | ForEach-Object { "word$_" }) -join ' '

# NOTE both documented routines CALL Helper. That is load-bearing, not
# decoration: the batch modes (--unit/--project) are facts-only and DROP a fresh
# comment that carries no facts block, so a routine trivial enough to have no
# 'Calls:' fact is silently skipped and the width assertions below would pass
# vacuously against an empty file. Verified directly: the identical fixture
# without the Helper call reports "1 public decl(s), nothing to document".
Write-Ascii (Join-Path $scratch 'wrapme.pas') @"
unit wrapme;

interface

function Helper(const AInput: string): string;

// $banner
function LongHarvest(const AInput: string): string;

/// <summary>An author wrote this on one very long line on purpose and it must come back byte for byte because reflowing a human's words is a destructive edit dressed up as formatting and this line is deliberately more than two hundred characters long.</summary>
function HandWritten(const AInput: string): string;

implementation

function Helper(const AInput: string): string;
begin
  Result := AInput;
end;

function LongHarvest(const AInput: string): string;
begin
  Result := Helper(AInput);
end;

function HandWritten(const AInput: string): string;
begin
  Result := Helper(AInput);
end;

end.
"@

# True when every ///-line in $lines fits $WRAP, ignoring lines whose content
# after the prefix is a single unbreakable token. Returns the offenders too, so
# a failure names the line instead of just counting it.
function Get-WideLines([string[]]$lines, [int]$max) {
  $bad = @()
  foreach ($l in $lines) {
    if ($l -notmatch '^\s*///') { continue }
    # The author's own <summary> is deliberately over-width and assertion 3
    # REQUIRES it to stay that way, so it can never be an offender here. The
    # width rule governs ENGINE-emitted prose only -- that is the whole
    # ownership split this runner exists to pin -- and without this exemption
    # assertions 1 and 3 would contradict each other.
    if ($l -match 'An author wrote this on one very long line') { continue }
    if ($l.Length -le $max) { continue }
    $content = ($l -replace '^\s*///\s?', '' -replace '</?para>','').Trim()
    # strip the marker before judging breakability -- it is one glued token
    $content = $content -replace '<!--\s*drag-lint:auto\s*-->', ''
    if ($content.Trim() -match '\s') { $bad += $l }   # had a break opportunity and did not use it
  }
  return ,$bad
}

$target = Join-Path $scratch 'wrapme.pas'
$db     = Join-Path $scratch 'wrap.sqlite'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- 1. the generated prose respects the width -------------------------------
  $wide = Get-WideLines $lines $WRAP
  Check "no breakable /// line exceeds $WRAP chars" ($wide.Count -eq 0) `
    ("offenders={0}{1}" -f $wide.Count, $(if ($wide.Count) { " longest=" + (($wide | Measure-Object -Property Length -Maximum).Maximum) } else { '' }))

  # --- 2. wrapping preserves the WORDS, not just the width ---------------------
  # Flatten the whole doc region back to one line and confirm the banner's word
  # sequence survived intact. A wrap that drops or reorders a word passes a pure
  # width check.
  $flat = (($lines | Where-Object { $_ -match '^\s*///' }) -replace '^\s*///\s?', '' -replace '</?para>','') -join ' '
  $flat = $flat -replace '<!--[^>]*-->', ' ' -replace '\s+', ' '
  Check 'every harvested word survives the wrap' ($flat -match ([regex]::Escape($banner))) `
    'the banner must still read as one uninterrupted word sequence'

  # --- 3. THE OWNERSHIP CONTROL: the author's long line is NOT reflowed --------
  $authorLine = @($lines | Where-Object { $_ -match "An author wrote this on one very long line" })
  Check 'the hand-written <summary> is still exactly ONE line' ($authorLine.Count -eq 1) `
    'a wrap that ignores ownership splits it and fails here'
  Check 'the hand-written <summary> still exceeds the wrap width (untouched)' `
    (($authorLine.Count -eq 1) -and ($authorLine[0].Length -gt $WRAP)) `
    'it is the author''s formatting; the engine must not own it'

  # --- 4. idempotency ----------------------------------------------------------
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after)) `
    'progressive re-wrapping of an already-wrapped value shows up here'
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
