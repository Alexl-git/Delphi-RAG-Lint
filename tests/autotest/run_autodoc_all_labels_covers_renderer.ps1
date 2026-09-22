<#
  run_autodoc_all_labels_covers_renderer.ps1 -- DRagLint.Doc.SharedFacts.ALL_LABELS
  must not drift from the labels DRagLint.Doc.Regions actually renders.

  THE DEFECT THIS PINS. ALL_LABELS is how ParseBlock/NextLabelPos find where one
  stored fact ENDS in an unwrapped block. Twice a renderer grew a label nobody
  registered ('Implemented by:'/'Extended by:' on 2026-09-16; 'Overridden by:',
  'Deprecated:' and four more found by review-task-1 I1 on 2026-09-22), and each
  time the preceding INBOUND slice swallowed the next fact and MergeInboundFacts
  fed the swallowed names back into 'Used in units:' / 'Called from:' forever.
  Nothing failed when the renderer changed -- silence is the failure mode -- so
  this guard reads BOTH sides statically and fails on the day they part.

  HOW IT READS THE RENDERER. Every label literal that RenderFactsBlock,
  FormatPhase2FactLines or their AppendFact/Lines.Add helpers emit, taken from
  the NoComments projection of Doc.Regions.pas (tests\autotest\lib\
  CliFlagVerbMap.ps1's lexer: comments blanked to spaces, string literals KEPT,
  length preserved). Comments in that unit quote label text freely
  ('Called from:' appears in prose a dozen times), so a raw-text scan would
  over-collect; the projection cannot be fooled by a label inside `{ }`, `(* *)`
  or `//`. A literal is canonicalised to the label ParseBlock would look for:
  cut at the first '%' (Format templates), cut at ' -- ' (the 'UI thread only'
  line), and compared with and without its trailing space.

  THE EXEMPTION LIST IS A DECISION, so it is asserted TWO-WAY: every emitted
  label is registered OR exempt; every exempt label IS emitted and is NOT
  registered; every registered label IS emitted. A stale registration, a
  stale exemption and a missing registration all fail.

  CONTROLS. P1: a planted `AppendFact('Planted label: ' + X)` in a synthetic
  snippet is found by the extractor (it can see). N1: the same call inside a
  `{ }` comment, a `//` comment and a `(* *)` comment is NOT found (it does not
  over-collect). P2: the ALL_LABELS reader finds every literal in a synthetic
  const block and none from the comment above it.
#>
[CmdletBinding()]
param(
  [string]$Regions     = "$PSScriptRoot\..\..\src\doc\DRagLint.Doc.Regions.pas",
  [string]$SharedFacts = "$PSScriptRoot\..\..\src\doc\DRagLint.Doc.SharedFacts.pas"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Regions))     { Write-Host "FATAL: not found: $Regions" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $SharedFacts)) { Write-Host "FATAL: not found: $SharedFacts" -ForegroundColor Red; exit 2 }

# The lib turns on Set-StrictMode for the scope it is dot-sourced into; keep
# that inside a function so the rest of this guard runs under its own mode.
function Get-NoCommentsProjection([string]$Text) {
  . (Join-Path $PSScriptRoot 'lib\CliFlagVerbMap.ps1')
  return (ConvertTo-PascalProjections -Text $Text).NoComments
}

# THE THREE BARE-WORD MARKERS deliberately NOT in ALL_LABELS -- see the
# ALL_LABELS header in Doc.SharedFacts.pas for the ruling: NextLabelPos is a raw
# substring search, so 'virtual' would cut a fact at `Directives: virtual;` and
# 'constructor' at any caller named `...Constructor...`, and since P8 every
# rendered fact is bounded by its own </para> before the label list is consulted.
$Exempt = @('abstract', 'virtual', 'constructor')

# The emit sites, and only those: AppendFact(...) / Lines.Add(...) in the two
# renderers, the RefVerb:= pair that feeds AppendFact for the inbound verb, and
# the RWLine:= pair that builds the one-line 'Reads: ...   Writes: ...' fact.
$SiteRx = "(?:AppendFact\(|Lines\.Add\(|RefVerb\s*:=|RWLine\s*:=(?:\s*RWLine\s*\+)?)\s*(?:Format\()?\s*'([^']*)'"

function ConvertTo-CanonicalLabel([string]$Literal) {
  $l = $Literal
  $p = $l.IndexOf('%');    if ($p -ge 0) { $l = $l.Substring(0, $p) }
  $p = $l.IndexOf(' -- '); if ($p -ge 0) { $l = $l.Substring(0, $p) }
  return $l
}
function Get-EmittedLabels([string]$PascalText) {
  $nc = Get-NoCommentsProjection $PascalText
  $out = @()
  foreach ($m in [regex]::Matches($nc, $SiteRx)) {
    $c = ConvertTo-CanonicalLabel $m.Groups[1].Value
    if ($c.Trim() -eq '') { continue }
    $out += $c
  }
  return @($out | Sort-Object -Unique)
}
function Get-RegisteredLabels([string]$PascalText) {
  $nc = Get-NoCommentsProjection $PascalText
  $m = [regex]::Match($nc, "ALL_LABELS\s*:\s*array\s*\[[^\]]*\]\s*of\s*string\s*=\s*\(([^;]*)\)\s*;")
  if (-not $m.Success) { return @() }
  $out = @()
  foreach ($lit in [regex]::Matches($m.Groups[1].Value, "'([^']*)'")) { $out += $lit.Groups[1].Value }
  return @($out | Sort-Object -Unique)
}
# A registered label R covers an emitted (canonical) label E when R equals E
# exactly or E minus its trailing space ('Called from: ' -> 'Called from:').
function Test-Covers([string]$R, [string]$E) { return ($R -eq $E) -or ($R -eq $E.TrimEnd()) }

# ---- controls ---------------------------------------------------------------
Write-Host 'Controls' -ForegroundColor Cyan
$synthetic = @(
  'procedure Render;',
  'begin',
  "  { AppendFact('Ghost in brace: ' + X); }",
  "  // AppendFact('Ghost in slashes: ' + X);",
  "  (* AppendFact('Ghost in paren: ' + X); *)",
  "  AppendFact('Planted label: ' + EscXml(X));",
  "  Lines.Add(Format('Planted count %d of %d', [A, B]));",
  "  if C then RefVerb:= 'Planted verb: ' else RefVerb:= 'Other verb: ';",
  "  RWLine:= 'Planted reads: ' + R;",
  "  RWLine:= RWLine + 'Planted writes: ' + W;",
  "  Lines.Add('Planted marker -- touches ' + T);",
  'end;'
) -join "`r`n"
$pl = Get-EmittedLabels $synthetic
Check 'P1 the extractor finds a planted AppendFact label' ($pl -contains 'Planted label: ') ("got: " + ($pl -join ' | '))
Check 'P1 the extractor finds a planted Format label, cut at its first %' ($pl -contains 'Planted count ') ''
Check 'P1 the extractor finds both RefVerb:= literals' (($pl -contains 'Planted verb: ') -and ($pl -contains 'Other verb: ')) ''
Check 'P1 the extractor finds both RWLine:= literals (plain and RWLine + ...)' (($pl -contains 'Planted reads: ') -and ($pl -contains 'Planted writes: ')) ''
Check 'P1 the extractor cuts a label at " -- "' ($pl -contains 'Planted marker') ''
$ghosts = @($pl | Where-Object { $_ -like 'Ghost*' })
Check 'N1 a label inside { }, // or (* *) is NOT collected' ($ghosts.Count -eq 0) ("ghosts: " + ($ghosts -join ' | '))
Check 'N1 the synthetic yields exactly the 7 planted labels' ($pl.Count -eq 7) "count=$($pl.Count)"

$syntheticConst = @(
  "  { the comment quotes 'Not a label:' and 'Nor this:' }",
  "  ALL_LABELS: array[0..2] of string = (",
  "    'Alpha:', 'Beta:',",
  "    'Gamma ');",
  "  OTHER: array[0..0] of string = ('Delta:');"
) -join "`r`n"
$pr = Get-RegisteredLabels $syntheticConst
Check 'P2 the ALL_LABELS reader finds every literal in the array and nothing else' `
      (($pr.Count -eq 3) -and ($pr -contains 'Alpha:') -and ($pr -contains 'Beta:') -and ($pr -contains 'Gamma ')) ("got: " + ($pr -join ' | '))

# ---- the real comparison ----------------------------------------------------
Write-Host ''
Write-Host 'Doc.Regions emitted labels vs Doc.SharedFacts ALL_LABELS' -ForegroundColor Cyan
$emitted    = Get-EmittedLabels ([System.IO.File]::ReadAllText($Regions))
$registered = Get-RegisteredLabels ([System.IO.File]::ReadAllText($SharedFacts))
Write-Host ("  emitted    ({0}): {1}" -f $emitted.Count,    (($emitted    | ForEach-Object { "[$_]" }) -join ' ')) -ForegroundColor DarkGray
Write-Host ("  registered ({0}): {1}" -f $registered.Count, (($registered | ForEach-Object { "[$_]" }) -join ' ')) -ForegroundColor DarkGray
Check 'E0 the renderer scan found labels at all' ($emitted.Count -gt 0) ''
Check 'E0 the ALL_LABELS array was found and is non-empty' ($registered.Count -gt 0) ''

$unregistered = @()
foreach ($e in $emitted) {
  $covered = $false
  foreach ($r in $registered) { if (Test-Covers $r $e) { $covered = $true; break } }
  if (-not $covered -and ($Exempt -notcontains $e.TrimEnd())) { $unregistered += $e }
}
Check 'E1 every emitted label is registered in ALL_LABELS or on the exemption list' ($unregistered.Count -eq 0) `
      ("unregistered: " + (($unregistered | ForEach-Object { "[$_]" }) -join ' '))

$stale = @()
foreach ($r in $registered) {
  $hit = $false
  foreach ($e in $emitted) { if (Test-Covers $r $e) { $hit = $true; break } }
  if (-not $hit) { $stale += $r }
}
Check 'E2 every registered label is still emitted by the renderer (no stale registration)' ($stale.Count -eq 0) `
      ("stale: " + (($stale | ForEach-Object { "[$_]" }) -join ' '))

$badExempt = @()
foreach ($x in $Exempt) {
  $isEmitted    = ($emitted | Where-Object { $_.TrimEnd() -eq $x }).Count -gt 0
  $isRegistered = ($registered | Where-Object { $_ -eq $x }).Count -gt 0
  if (-not $isEmitted -or $isRegistered) { $badExempt += "$x(emitted=$isEmitted registered=$isRegistered)" }
}
Check 'E3 every exempt bare word IS emitted and is NOT registered (the exemption is live, two-way)' ($badExempt.Count -eq 0) `
      ("bad: " + ($badExempt -join ' '))

Write-Host ''
if ($script:Failed) { Write-Host 'ALL-LABELS GUARD: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'ALL-LABELS GUARD: PASS' -ForegroundColor Green; exit 0 }
