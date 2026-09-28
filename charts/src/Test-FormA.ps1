<#
  Test-FormA.ps1 -- executable verification walk for the Form A grammar.

  This is the re-run that charts\form-a-grammar-spec.md section 7 names as a
  GATE on accepting the spec. It is deliberately a checker, not a parser: it
  implements the lexical and layout rules (spec sections 2.1-2.7) far enough to
  answer three questions the spec cannot answer by eye --

    1. Does every line of the golden's Form A block classify under the grammar?
       Any line it cannot classify is a defect in the GRAMMAR, per the spec.
    2. What is the real verb set? The drafted set was derived from the
       pre-correction fixture and is known incomplete.
    3. Do the END TRACE counts recompute? (AC-35, which found the last defect.)

  Exit code 0 = pass. Non-zero = the golden does not satisfy its own spec.
#>
[CmdletBinding()]
param(
  [string] $Fixture = (Join-Path $PSScriptRoot '..\fixtures\golden-operat-name-roundtrip.md'),
  [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$fail = New-Object System.Collections.ArrayList
function Fail([string] $code, [int] $line, [string] $msg) {
  [void]$fail.Add([pscustomobject]@{ Code = $code; Line = $line; Message = $msg })
}

# ---- keyword tables (spec 2.3) ----------------------------------------------
$TIERS     = @('USER','CLIENT','SERVER','DATABASE','PIPE')
$SECTIONS  = @('WRITE','READ','RESPONSE','ANCHOR','ALSO') + $TIERS          # ANCHOR / ALSO: round-trip (spec 2026-09-27)
$ITEMHEADS = @('GUARD','ON','CROSSES','STOPS','WHEN','UNLESS')             # STOPS / WHEN / UNLESS: round-trip
$FACETS1   = @('ONTO','AT','CONTRACT','FROM','TO','OVER','WITH','VIA','SELECTS','RECORDS')
$FACETS2   = @{ 'BOUND' = 'VIA'; 'SOURCED' = 'FROM'; 'LOOKS' = 'UP' }
$HEADERKW  = @('TITLE','INDEX','TIERS','FROM','REGENERATE')                 # FROM / REGENERATE: round-trip header attributes
$RESERVED  = @('OTHERWISE','ONLY','WHEN','AND','AS','INTO','->','+')

# ---- 1. byte-level checks (spec 2.1, AC-29) ---------------------------------
$bytes = [IO.File]::ReadAllBytes($Fixture)
$bad = 0; $i = 0
foreach ($b in $bytes) { if ($b -ne 0x0D -and $b -ne 0x0A -and ($b -lt 0x20 -or $b -gt 0x7E)) { $bad++ } ; $i++ }
if ($bad -gt 0) { Fail 'E-CHARSET' 0 "$bad byte(s) outside 0x20-0x7E/CR/LF" }
$text = [IO.File]::ReadAllText($Fixture)
$bareLf = ([regex]::Matches($text, "(?<!\r)\n")).Count
if ($bareLf -gt 0) { Fail 'E-EOL' 0 "$bareLf bare LF" }

# ---- 2. extract the Form A block --------------------------------------------
$all = [IO.File]::ReadAllLines($Fixture)
$start = ($all | Select-String -Pattern '^TRACE ' | Select-Object -First 1).LineNumber
$endLn = ($all | Select-String -Pattern '^END TRACE' | Select-Object -First 1).LineNumber
if (-not $start -or -not $endLn) { Fail 'E-NO-END' 0 'TRACE or END TRACE not found'; }
$block = $all[($start - 1)..($endLn - 1)]

# ---- 3. classify every line (spec 2.4-2.7) ----------------------------------
$verbs      = New-Object System.Collections.Generic.HashSet[string]
$facets     = New-Object System.Collections.Generic.HashSet[string]
$unknown    = New-Object System.Collections.ArrayList
$steps = 0; $guards = 0; $crossings = 0; $unresolved = 0
$stepNums   = New-Object System.Collections.ArrayList
$anchors    = 0
$classified = 0

for ($k = 0; $k -lt $block.Count; $k++) {
  $raw  = $block[$k]
  $abs  = $start + $k
  $anchors += ([regex]::Matches($raw, '@[A-Za-z0-9_$\\/.\-]+:\d+')).Count

  if ($raw.Trim() -eq '') { $classified++; continue }                      # trivia

  # strip a trailing comment that is NOT inside a string
  $work = $raw
  $inStr = $false
  for ($c = 0; $c -lt $work.Length - 1; $c++) {
    if ($work[$c] -eq '"') { $inStr = -not $inStr }
    elseif (-not $inStr -and $work[$c] -eq '-' -and $work[$c + 1] -eq '-') { $work = $work.Substring(0, $c); break }
  }
  if ($work.Trim() -eq '') { $classified++; continue }                      # comment-only

  # gutter
  $gutter = $null
  # two OR three digits (a generated trace may pass 99 steps)
  if ($work -match '^\[(\d{2,3})\]\s') { $gutter = [int]$Matches[1]; $work = $work -replace '^\[\d{2,3}\]', '    ' }

  # `[by name]` is a two-token certainty marker (round-trip); drop it as a phrase
  # before the split, or its halves would read as a subject and a verb.
  $work = $work.Replace('[by name]', '')
  # @() is load-bearing: a single-token line otherwise yields a string, and
  # indexing a string gives a [char], which has no ToUpper().
  $toks = @($work.Trim() -split '\s+' | Where-Object { $_ -ne '' })
  # Annotations are not part of the phrase (spec 3: a `text` ENDS at the first
  # anchor or certainty marker). Dropping them here is what lets a subject-only
  # step line -- legal per step-core alternative 1 -- classify instead of having
  # its anchor mistaken for the verb.
  $toks = @($toks | Where-Object { $_ -notmatch '^@' -and $_ -ne '[certain]' -and $_ -ne '[inferred]' })
  if ($toks.Count -eq 0) { $classified++; continue }
  $h = $toks[0]

  if ($null -ne $gutter) { $steps++; [void]$stepNums.Add($gutter) }

  # continuation: anchor-only or OTHERWISE-led (spec 2.5)
  if ($h -match '^@' -or $h -eq 'OTHERWISE') { $classified++; continue }

  # a numbered STOPS / CROSSES may stand behind an actor word (`[NN] SERVER STOPS ...`,
  # in ANY section). The gutter line starts at column 1, so without this the check below
  # takes SERVER for a section header and the STOPS is never counted unresolved.
  if ($null -ne $gutter -and $SECTIONS -contains $h -and $toks.Count -gt 1 -and ($toks[1] -ceq 'STOPS' -or $toks[1] -ceq 'CROSSES')) {
    $h = $toks[1]
  }

  # structural at column 1
  if ($raw.Length -gt 0 -and $raw[0] -ne ' ') {
    if ($h -eq 'TRACE' -or $h -eq 'END' -or $SECTIONS -contains $h) { $classified++; continue }
  }
  if ($HEADERKW -contains $h) { $classified++; continue }
  if ($h -eq 'GUARD')   { $guards++;    $classified++; continue }
  if ($h -eq 'WHEN' -or $h -eq 'UNLESS') { $guards++; $classified++; continue }   # a round-trip condition counts where GUARD counts
  if ($h -eq 'STOPS')   { $unresolved++; $classified++; continue }                # numbered (counted above) AND unresolved
  if ($h -eq 'CROSSES') { $crossings++; $classified++; continue }
  if ($h -eq 'UNRESOLVED') { $unresolved++; $classified++; continue }
  if ($h -eq 'ON')      { $classified++; continue }
  # facet heads are NOT verbs -- keep the regenerated verb set honest
  if ($FACETS2.ContainsKey($h) -and $toks.Count -gt 1 -and $toks[1] -eq $FACETS2[$h]) {
    $facets.Add("$h $($toks[1])") | Out-Null; $classified++; continue
  }
  if ($FACETS1 -contains $h) { $facets.Add($h) | Out-Null; $classified++; continue }

  # actor prefix, then the verb is the next token
  $vi = 0
  if ($TIERS -contains $h -and $toks.Count -gt 1) { $vi = 1 }
  $cand = $toks[$vi]

  # a subject (mixed/lower case, qualified name) shifts the verb one further
  if ($cand -cmatch '^[A-Za-z_][A-Za-z0-9_.]*$' -and $cand -cne $cand.ToUpper() -and $toks.Count -gt $vi + 1) {
    $cand = $toks[$vi + 1]
  }

  if ($cand -cmatch '^[A-Z][A-Z]+$') {
    if ($RESERVED -contains $cand) { $classified++; continue }
    $verbs.Add($cand) | Out-Null
    $classified++; continue
  }

  # a subject-only step line (no verb) is legal (spec 3, step-core alt 1)
  if ($cand -cmatch '^[A-Za-z_][A-Za-z0-9_.()"]*') { $classified++; continue }

  [void]$unknown.Add("line $abs : '$raw'")
}

# ---- 4. counts vs declaration (AC-35) ---------------------------------------
$endLine = $all[$endLn - 1]
# the golden's `guards` and the round-trip's `conditions` (WHEN / UNLESS) are one count
if ($endLine -match 'END TRACE\s+(\d+) steps?,\s*(\d+) (?:guards?|conditions?),\s*(\d+) crossings?,\s*(\d+) unresolved') {
  $dS = [int]$Matches[1]; $dG = [int]$Matches[2]; $dC = [int]$Matches[3]; $dU = [int]$Matches[4]
  if ($dS -ne $steps)      { Fail 'E-COUNTS' $endLn "steps: declared $dS, recomputed $steps" }
  if ($dG -ne $guards)     { Fail 'E-COUNTS' $endLn "guards: declared $dG, recomputed $guards" }
  if ($dC -ne $crossings)  { Fail 'E-COUNTS' $endLn "crossings: declared $dC, recomputed $crossings" }
  if ($dU -ne $unresolved) { Fail 'E-COUNTS' $endLn "unresolved: declared $dU, recomputed $unresolved" }
} else { Fail 'E-NO-END' $endLn 'END TRACE line does not match the grammar' }

# ---- 5. step numbering (spec 2.7, E-STEP-ORDER) -----------------------------
for ($n = 1; $n -lt $stepNums.Count; $n++) {
  if ($stepNums[$n] -le $stepNums[$n - 1]) {
    Fail 'E-STEP-ORDER' 0 "step [$($stepNums[$n])] does not exceed [$($stepNums[$n-1])]"
  }
}

# ---- 6. every line must classify --------------------------------------------
foreach ($u in $unknown) { Fail 'E-UNCLASSIFIED' 0 $u }

# ---- report ------------------------------------------------------------------
if (-not $Quiet) {
  Write-Host ""
  Write-Host "Form A verification walk -- $(Split-Path $Fixture -Leaf)"
  Write-Host ("  block            : lines {0}..{1} ({2} lines)" -f $start, $endLn, $block.Count)
  Write-Host ("  classified       : {0}/{1}" -f $classified, ($block.Count - $unknown.Count))
  Write-Host ("  steps/guards/xing: {0} / {1} / {2}" -f $steps, $guards, $crossings)
  Write-Host ("  anchors          : {0}" -f $anchors)
  Write-Host ("  bytes            : {0} non-ascii, {1} bare LF" -f $bad, $bareLf)
  Write-Host ""
  Write-Host ("  VERB SET ({0}) -- regenerated from the corrected fixture:" -f $verbs.Count)
  ($verbs | Sort-Object) -join '  ' -split '(.{1,66}\s)' | Where-Object { $_.Trim() } |
    ForEach-Object { Write-Host "    $($_.Trim())" }
  Write-Host ""
}

if ($fail.Count -eq 0) {
  if (-not $Quiet) { Write-Host "  PASS -- the golden satisfies the grammar's checkable rules." -ForegroundColor Green }
  exit 0
}
Write-Host "  FAIL -- $($fail.Count) problem(s):" -ForegroundColor Red
$fail | ForEach-Object { Write-Host ("    [{0}] line {1}: {2}" -f $_.Code, $_.Line, $_.Message) }
exit 1
