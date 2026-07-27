<#
  run_doc_p3_drift_fixable.ps1 -- Auto-Document Phase 3, Task 3d, GROUP A:
  the doc-drift "false promise" class (register D2 + D3) and the doc-drift
  POPULATION divergence (register D4).

  A Fixable=True diagnostic that no fixer can satisfy is worse than no
  diagnostic at all: it sends `lint-all --fix --apply` into a no-op loop and
  erodes trust in every other fixable flag. ddParamMissing was flipped to
  report-only for exactly that reason in v(ADP3 T3); these are its siblings.

  D2 -- ddValueButNoReturns claimed Fixable=True for EVERY instance. The fix
    that would satisfy it is MergeComment's engine-owned <returns> arm, which
    since v(ADP3 T3)'s omit-when-empty rule emits the tag ONLY when a return
    case is minable. Fixable is now a per-FINDING answer:
      * MinableReturn    -- Result is assigned -> a case is minable -> True.
      * NoMinableReturn  -- nothing is assigned -> nothing to write -> False.
      * BlankReturnsSlot -- a HUMAN's empty <returns></returns> is preserved
        verbatim on every repair, so the tag stays empty forever -> False,
        even though a return case IS minable for that routine (which is what
        makes this shape discriminating: a fix keyed on the mined cases alone
        would wrongly promise here).
    Flipping the whole kind to False was REJECTED: unlike <param>, this
    finding IS mechanically satisfiable, and that path is load-bearing in
    run_doc_drift_rule.ps1. The defect was the inaccurate promise, not the
    existence of the fix.

  D3 -- since v(ADP3 T1) every engine-written <returns> carries the
    provenance marker immediately after the opening tag, and the parser keeps
    the marker in ReturnsText, so Trim(ReturnsText) is never '' for a managed
    tag and ddValueButNoReturns silently stopped firing on one. Ruled
    DELIBERATE and correct here, and pinned: the finding's own claim is "has
    no <returns> tag", which for a marked tag is factually false.

  D4 -- RunDocDrift's population is ListDocumentedSymbols, which filtered on
    'summary IS NOT NULL'. UpsertSymbolDoc writes NULL (not '') for an empty
    column, so a decl documented ONLY by <remarks> had a symbol_docs row with
    a NULL summary: "documented" for missing-doc (which keys on the row
    existing) and "undocumented" for doc-drift. It was reported by NEITHER
    rule, and `lint-all --fix --apply` could not clean its stale facts block
    even though `document --apply` cleaned the identical block correctly.
    RemarksOnlyStaleFacts is that shape; the filter is gone.

  Fixture: fixtures\docp3\driftfixable.pas. Nothing in it calls anything else
  in it, so every symbol renders an EMPTY facts block -- which is what makes
  RemarksOnlyStaleFacts' hand-written fence unambiguously stale.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\driftfixable.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3driftfixable'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'driftfixable.pas'
$db     = Join-Path $scratch 'docp3driftfixable.sqlite'
Copy-Item $fixture $target -Force

# The contiguous run of ///-prefixed lines immediately above the FIRST line
# matching $declPattern, joined with "`n". $null when the decl is not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $lines[$i])
  }
  return [string]::Join("`n", $blockLines.ToArray())
}

# doc-drift --qname rows (one JSON object per line): .kind/.detail/.fixable/.line
function Get-Drift($qname) {
  $out = & $exePath doc-drift --qname $qname --db $db --json 2>$null
  Check "doc-drift --qname $qname exits 0" ($LASTEXITCODE -eq 0)
  $rows = @()
  foreach ($ln in $out) { $t = "$ln".Trim(); if ($t.StartsWith('{')) { $rows += ($t | ConvertFrom-Json) } }
  return ,$rows
}
# True when a row of kind $k exists whose fixable flag equals $fx.
function HasKind($rows,$k,$fx) {
  foreach ($r in $rows) { if ($r.kind -eq $k -and [bool]$r.fixable -eq $fx) { return $true } }
  return $false
}
function LacksKind($rows,$k) {
  foreach ($r in $rows) { if ($r.kind -eq $k) { return $false } }
  return $true
}
# The IMPLEMENTATION body of routine $name, with // line comments removed:
# from the 'begin' after its LAST 'function <name>(' heading (the interface
# heading comes first) to the next top-level 'end;'. Used only by the FIXTURE
# DISCRIMINATION checks, which must read the routine's OWN body -- a
# whole-file regex would happily satisfy "assigns Result" from a NEIGHBOURING
# routine and make the check vacuous. Comments are stripped because the miner
# being characterised (MineReturnExpressions) strips them too, so a body whose
# COMMENT merely mentions Result or Exit must read as "assigns nothing" here
# exactly as it does to the engine.
function Get-ImplBody([string]$text, [string]$name) {
  $m = [regex]::Matches($text, "(?m)^function $([regex]::Escape($name))\(")
  if ($m.Count -lt 1) { return $null }
  $start    = $m[$m.Count-1].Index
  $beginIdx = $text.IndexOf("`r`nbegin", $start)
  if ($beginIdx -lt 0) { return $null }
  $endIdx = $text.IndexOf("`r`nend;", $beginIdx)
  if ($endIdx -lt 0) { return $null }
  $body = $text.Substring($beginIdx, $endIdx - $beginIdx)
  return (($body -split "`r?`n" | ForEach-Object { ($_ -split '//',2)[0] }) -join "`n")
}
# The 1-based source line of the FIRST /// line of the doc block above the
# first line matching $declPattern. doc-drift anchors its finding there.
function Get-DocStartLine([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return -1 }
  $first = $idx
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $first = $i
  }
  if ($first -eq $idx) { return -1 }
  return $first + 1
}
# The single pretty-printed JSON array inside lint-all --json output.
function Get-Findings($raw) {
  $arrStart = $raw.IndexOf('[')
  $arrEnd   = $raw.LastIndexOf(']')
  if ($arrStart -ge 0 -and $arrEnd -gt $arrStart) {
    return @(ConvertFrom-Json ($raw.Substring($arrStart, $arrEnd - $arrStart + 1)))
  }
  return @()
}

$patMinable = '^function MinableReturn\(Key: Integer\): string;'
$patNoMin   = '^function NoMinableReturn\(Key: Integer\): string;'
$patBlank   = '^function BlankReturnsSlot\(Key: Integer\): string;'
$patMarked  = '^function MarkedReturns\(Key: Integer\): string;'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --- FIXTURE DISCRIMINATION -----------------------------------------------
  # Every assertion below about "fixable=False on NoMinableReturn" is only
  # meaningful while that routine genuinely has no minable return case, and
  # every assertion about BlankReturnsSlot is only discriminating while that
  # routine DOES have one (otherwise it would report False for the OTHER
  # conjunct and the test would pass for the wrong reason). Pin both against
  # the pristine fixture so an edit cannot silently make them vacuous.
  $srcText = [IO.File]::ReadAllText($target)
  $noMinBody = Get-ImplBody $srcText 'NoMinableReturn'
  $blankBody = Get-ImplBody $srcText 'BlankReturnsSlot'
  Check 'FIXTURE: both implementation bodies were located (the two checks below cannot pass vacuously)' `
    ($null -ne $noMinBody -and $null -ne $blankBody)
  Check 'FIXTURE: NoMinableReturn''s BODY assigns neither Result nor Exit(value)' `
    ($null -ne $noMinBody -and $noMinBody -notmatch '(?i)Result\s*:=' -and $noMinBody -notmatch '(?i)\bExit\(')
  Check 'FIXTURE: BlankReturnsSlot''s BODY DOES assign Result (so its False verdict is the blank-slot conjunct, not the mining one)' `
    ($null -ne $blankBody -and $blankBody -match '(?i)Result\s*:=')

  # --- D2: the per-finding Fixable verdict ----------------------------------
  $minable = Get-Drift 'driftfixable.MinableReturn'
  Check 'D2 MinableReturn: ddValueButNoReturns present and FIXABLE (a return case is minable)' `
    (HasKind $minable 'ddValueButNoReturns' $true)

  $noMin = Get-Drift 'driftfixable.NoMinableReturn'
  Check 'D2 NoMinableReturn: ddValueButNoReturns present but REPORT-ONLY (nothing minable -> no fix exists)' `
    (HasKind $noMin 'ddValueButNoReturns' $false)

  $blank = Get-Drift 'driftfixable.BlankReturnsSlot'
  Check 'D2 BlankReturnsSlot: ddValueButNoReturns present but REPORT-ONLY (a human blank slot is preserved verbatim)' `
    (HasKind $blank 'ddValueButNoReturns' $false)

  # --- D3: the deliberate non-firing on an engine-written <returns> ---------
  $marked = Get-Drift 'driftfixable.MarkedReturns'
  Check 'D3 MarkedReturns: emits at least one row (so the LacksKind check below is not vacuous on an empty result)' `
    ($marked.Count -ge 1)
  Check 'D3 MarkedReturns: NO ddValueButNoReturns at all -- the marked tag demonstrably exists' `
    (LacksKind $marked 'ddValueButNoReturns')

  # --- D4: the widened doc-drift population ---------------------------------
  $remarksOnlyDocLine = Get-DocStartLine ([IO.File]::ReadAllLines($target)) '^procedure RemarksOnlyStaleFacts;'
  Check 'D4 FIXTURE: the remarks-only doc block was located' ($remarksOnlyDocLine -gt 0) "line=$remarksOnlyDocLine"
  $rawBefore = (& $exePath lint-all --db $db --json 2>$null) -join "`n"
  # v(ADP3 T3d2): NOT "exits 0" -- bare `lint-all` (no --fix, no --fail-on)
  # returns ExitCodeFor(Survivors, '', IfThen(Survivors.Count>0, 1, 0))
  # (DRagLint.Output.ExitCode.pas), i.e. 1 whenever findings survive, which
  # this fixture always has at this point (that is what D4 exists to check,
  # asserted immediately below). 1 is therefore the correct expectation, not
  # a failure -- checking for it still catches a genuine engine crash, which
  # would not reliably land on exactly 1 either.
  Check 'D4 lint-all --json (before --fix) exits 1 (findings present, no --fail-on override)' ($LASTEXITCODE -eq 1)
  $driftBefore = @((Get-Findings $rawBefore) | Where-Object { $_.rule -eq 'doc-drift' })
  Check 'D4 lint-all reports the stale facts block on the REMARKS-ONLY decl (summary is NULL there)' `
    (@($driftBefore | Where-Object { $_.message -like '*managed facts block is out of date*' }).Count -ge 1) `
    ("doc-drift findings=" + $driftBefore.Count)
  Check 'D4 the stale-block finding is anchored on the REMARKS-ONLY decl''s own line, in the fixture file' `
    (@($driftBefore | Where-Object { $_.message -like '*managed facts block is out of date*' -and $_.file_path -like '*driftfixable.pas' -and $_.start_line -eq $remarksOnlyDocLine }).Count -ge 1) `
    "expected doc line $remarksOnlyDocLine"

  # --- Apply the fixable subset ---------------------------------------------
  $before = [IO.File]::ReadAllLines($target)
  $noMinBefore  = Get-DocBlockAbove $before $patNoMin
  $blankBefore  = Get-DocBlockAbove $before $patBlank
  $markedBefore = Get-DocBlockAbove $before $patMarked
  Check 'pre-apply: all three protected doc blocks were located' `
    ($null -ne $noMinBefore -and $null -ne $blankBefore -and $null -ne $markedBefore)

  & $exePath lint-all --db $db --fix --apply --no-backup 2>$null | Out-Null
  Check 'lint-all --fix --apply (fixable subset) exits 0' ($LASTEXITCODE -eq 0)
  $after = [IO.File]::ReadAllLines($target)

  # The promise that WAS made is kept.
  $minableAfter = Get-DocBlockAbove $after $patMinable
  Check 'D2 kept promise: MinableReturn GAINED an engine-written <returns> with the provenance marker' `
    ($null -ne $minableAfter -and $minableAfter -match [regex]::Escape('<returns><!-- drag-lint:auto -->'))
  Check 'D2 kept promise: the mined case is the one that was written' `
    ($null -ne $minableAfter -and $minableAfter -match [regex]::Escape('IntToStr(Key)'))

  # The promises that were NOT made cost nothing: those decls are not touched
  # at all (FixEditsForDocDrift's AnyFix gate skips a decl with no fixable
  # signal), so there is no churn and no rewrite of hand-written text.
  Check 'D2 no false promise: NoMinableReturn''s doc block is byte-identical after --fix' `
    ((Get-DocBlockAbove $after $patNoMin) -ceq $noMinBefore)
  Check 'D2 no false promise: BlankReturnsSlot''s empty <returns></returns> survives byte-identical' `
    ((Get-DocBlockAbove $after $patBlank) -ceq $blankBefore)
  Check 'D3 MarkedReturns'' doc block is byte-identical after --fix' `
    ((Get-DocBlockAbove $after $patMarked) -ceq $markedBefore)

  # D4: the stale fence really is cleaned by the LINT route now, not just by
  # `document --apply`.
  $afterText = [IO.File]::ReadAllText($target)
  Check 'D4 the stale hand-written fact line is GONE after lint-all --fix --apply' `
    ($afterText -notmatch [regex]::Escape('NoSuchCallerAnyMore'))

  # --- Re-analyse: the promise is measurably discharged, and the honest
  # --- report-only finding measurably survives -------------------------------
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 're-index after --fix exits 0' ($LASTEXITCODE -eq 0)
  $minable2 = Get-Drift 'driftfixable.MinableReturn'
  Check 'D2 after --fix: MinableReturn has NO ddValueButNoReturns left (the fix discharged it)' `
    (LacksKind $minable2 'ddValueButNoReturns')

  $noMin2 = Get-Drift 'driftfixable.NoMinableReturn'
  Check 'D2 after --fix: NoMinableReturn STILL reports ddValueButNoReturns, still report-only (honest, and no fix loop)' `
    (HasKind $noMin2 'ddValueButNoReturns' $false)
  $noMin2Fixable = @($noMin2 | Where-Object { [bool]$_.fixable -eq $true })
  Check 'D2 after --fix: NoMinableReturn has ZERO fixable findings, so --fix will never revisit it' `
    ($noMin2Fixable.Count -eq 0)

  # --- Idempotency ----------------------------------------------------------
  $bytes1 = [IO.File]::ReadAllBytes($target)
  & $exePath lint-all --db $db --fix --apply --no-backup 2>$null | Out-Null
  Check 'idempotency: 2nd lint-all --fix --apply exits 0' ($LASTEXITCODE -eq 0)
  $bytes2 = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: a 2nd lint-all --fix --apply is byte-identical' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes1,[byte[]]$bytes2))

  # --- Encoding -------------------------------------------------------------
  $bad = @([IO.File]::ReadAllBytes($target) | Where-Object { $_ -gt 127 }).Count
  Check 'every byte written back is 7-bit ASCII' ($bad -eq 0) "nonascii=$bad"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
