<#
  run_doc_p3_residual_lines.ps1 -- Auto-Document Phase 3, Task 3f: the repair
  path must preserve what it does not model.

  MergeComment's repair path rebuilds a doc comment from the TParsedDoc fields
  it models, so anything it does not model is destroyed. Three loss classes
  were reproduced against the shipped exe and traced to root cause in
  docs\lint\URGENT-TODO-2026-07-26-index-doc-tag-coverage.md ("New finding");
  fixtures\docp3\residual_lines.pas carries one shape per class, each with a
  caller so Facts is non-empty and the repair branch (never the Merged=''
  early exit) is what runs.

    L1  an unmodeled tag is deleted. TWO shapes:
          ValueBesideSummary  -- a whole line the engine models nothing on.
          ParaWithInlineSee   -- the MIXED line: an unmodeled <para> wrapping
                                 a <see cref> the engine DOES model. Before
                                 the fix the <para> and its prose were deleted
                                 and the bare <see cref> re-emitted as if the
                                 author had written a standalone entry.
    L2  MultiLineExample -- a multi-line <example>'s interior indentation is
        flattened and its open tag folded onto the first content line.
    L3  TrailingProseBesideSince -- trailing author prose beside a modeled tag
        on the SAME line is deleted and replaced by a fabricated, empty
        <summary></summary>.

  FullyModeledControl is the control in the other direction: an entirely
  modeled comment must be completely unaffected. Without it, an
  implementation that simply dumped every source line back out verbatim would
  pass every preservation assertion above.

  Method, per shape: an ISOLATED scratch copy, then 3 x (index -> document
  --qname --apply), which is the idempotency sweep's own methodology. Asserts

    1. the hand-written text survives EXACTLY -- for L2 the four example lines
       are matched as a contiguous run WITH their original indentation, not
       merely "the words are somewhere in the file";
    2. nothing is fabricated (no invented <summary>, no hoisted duplicate of
       the inline <see cref>);
    3. a real facts block was written, so Merged was genuinely computed;
    4. the cycle-1 action is pinned per shape, so a fresh<->repair branch flip
       is visible rather than silent (same rule as the sweep's own pins);
    5. a 3-cycle md5 FIXED POINT from cycle 1, with cycles 2 and 3 reporting
       edits=0 -- the binding acceptance criterion;
    6. a `document --strip` round-trip gives the author's lines back, with no
       engine residue left behind. For the two shapes whose pristine tag order
       already matches the emitter's own fixed order, the stripped block must
       be byte-identical to pristine.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\residual_lines.pas')).Path

# The contiguous run of ///-prefixed lines immediately above the FIRST line
# matching $declPattern, returned RAW (never trimmed) so indentation INSIDE the
# comment is assertable. Same scan-upward idiom the other docp3 runners use,
# scoped to one declaration so a check cannot bleed into a neighbouring block.
function Get-DocBlockLines([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i])
  }
  return $acc.ToArray()
}

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash.Substring(0,8) }

# 3 --qname-scoped apply cycles in an isolated scratch copy, reindexing before
# each. Returns the per-cycle action/edits and whole-file md5.
function Invoke-ShapeSweep([string]$root, [string]$qname, [string]$slug) {
  $scratch = Join-Path $root $slug
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch -Force | Out-Null
  $target = Join-Path $scratch 'residual_lines.pas'
  $db     = Join-Path $scratch 'q.sqlite'
  Copy-Item $fixture $target -Force
  $md5s = @( Get-FileMd5 $target )
  $acts = @()
  for ($cycle = 1; $cycle -le 3; $cycle++) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    $j = (& $exePath document --qname $qname --db $db --apply --json 2>$null) -join ' '
    if ($j -match '"action":"(\w+)"') { $a = $Matches[1] } else { $a = '?' }
    if ($j -match '"edits":(\d+)')    { $a = "$a/$($Matches[1])" }
    $acts += $a
    $md5s += Get-FileMd5 $target
  }
  return [pscustomobject]@{ Scratch = $scratch; Target = $target; Db = $db; Md5s = $md5s; Actions = $acts }
}

# Pristine per-shape blocks, read once from the fixture itself.
$pristineLines = [IO.File]::ReadAllLines($fixture)
$decl = @{
  ValueBesideSummary       = '^procedure ValueBesideSummary;'
  ParaWithInlineSee        = '^procedure ParaWithInlineSee;'
  MultiLineExample         = '^procedure MultiLineExample;'
  TrailingProseBesideSince = '^procedure TrailingProseBesideSince;'
  FullyModeledControl      = '^function FullyModeledControl\(AValue: Integer\): Integer;'
}
$decl['ExceptionNoCrefBesideSummary'] = '^procedure ExceptionNoCrefBesideSummary;'
$decl['ParamNoNameBesideSummary']     = '^procedure ParamNoNameBesideSummary\(AValue: Integer\);'
$decl['AttributedRemarks']            = '^procedure AttributedRemarks;'
$decl['AttributedExample']            = '^procedure AttributedExample;'
$decl['FencedRemarksTailValue']       = '^procedure FencedRemarksTailValue;'
$decl['MarkedReturnsTail']            = '^function MarkedReturnsTail: Integer;'
$pristine = @{}
foreach ($k in $decl.Keys) { $pristine[$k] = Get-DocBlockLines $pristineLines $decl[$k] }

# Pinned cycle-1 action per shape. Every one of these reaches the REPAIR
# branch on the FIRST apply (ExistingHasAnyTag is True from the original parse
# alone for all five: HasSummaryTag for the two L1 shapes and the control,
# HasContent via HasExampleTag for L2 and via HasSinceTag for L3). A value
# here that DIFFERS from the pin is a branch flip -- understand it before
# updating the pin, same rule as the idempotency sweep's own pins.
$expectedCycle1 = @{
  ValueBesideSummary          = 'extended'
  ParaWithInlineSee           = 'extended'
  MultiLineExample            = 'extended'
  TrailingProseBesideSince    = 'extended'
  FullyModeledControl         = 'extended'
  ExceptionNoCrefBesideSummary= 'extended'
  ParamNoNameBesideSummary    = 'extended'
  AttributedRemarks           = 'extended'
  AttributedExample           = 'extended'
  FencedRemarksTailValue      = 'extended'
  MarkedReturnsTail           = 'extended'
}

$root = Join-Path C:\TEMP 'draglint_docp3residual'
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
New-Item -ItemType Directory -Path $root | Out-Null

Push-Location C:\TEMP
try {

$shapes = @('ValueBesideSummary','ParaWithInlineSee','MultiLineExample','TrailingProseBesideSince','FullyModeledControl',
            'ExceptionNoCrefBesideSummary','ParamNoNameBesideSummary','AttributedRemarks','AttributedExample',
            'FencedRemarksTailValue','MarkedReturnsTail')
$res = @{}
$slug = 0
foreach ($nm in $shapes) {
  $slug++
  $r = Invoke-ShapeSweep $root "residual_lines.$nm" ('s{0:d2}' -f $slug)
  $res[$nm] = $r
  Write-Host ('  {0,-26} md5={1}  actions={2}' -f $nm, ($r.Md5s -join ' '), ($r.Actions -join ' '))

  # 4 + 5: branch pin and the 3-cycle fixed point (cycle 1 does the work; a
  # second apply must be a zero-byte diff).
  Check "$nm cycle-1 action is pinned ($($expectedCycle1[$nm]))" `
    ($r.Actions[0] -match ('^' + [regex]::Escape($expectedCycle1[$nm]) + '/')) ("actual=" + $r.Actions[0])
  Check "$nm reaches a FIXED POINT from cycle 1 (c1 == c2 == c3)" `
    (($r.Md5s[1] -eq $r.Md5s[2]) -and ($r.Md5s[2] -eq $r.Md5s[3])) ("md5=" + ($r.Md5s -join ' '))
  Check "$nm cycle-2 apply makes NO edit" ($r.Actions[1] -match '/0$') ($r.Actions -join ' ')
  Check "$nm cycle-3 apply makes NO edit" ($r.Actions[2] -match '/0$') ($r.Actions -join ' ')

  # 3: Merged was genuinely computed (this is the repair branch doing work,
  # not an early-exit no-op).
  $blk = Get-DocBlockLines ([IO.File]::ReadAllLines($r.Target)) $decl[$nm]
  Check "$nm a real facts block with Called from: was written" `
    (($blk -join "`n") -match '(?s)<!-- drag-lint:auto BEGIN -->.*Called from:.*residual_lines\.Calls') (($blk -join ' | '))
  $res[$nm] | Add-Member -NotePropertyName Block -NotePropertyValue $blk
}

Write-Host ''
Write-Host '--- L1: an unmodeled tag must survive the repair path -------------------------'

# L1a -- a whole line the engine models nothing on.
$b = $res['ValueBesideSummary'].Block
Check 'L1a ValueBesideSummary: the unmodeled <value> line survives VERBATIM' `
  ($b -ccontains '/// <value>Hand-written value tag; unmodeled, must survive verbatim.</value>') ($b -join ' | ')
Check 'L1a ValueBesideSummary: it appears EXACTLY once (preserved, not duplicated)' `
  ((@($b | Where-Object { $_ -match [regex]::Escape('<value>Hand-written value tag') })).Count -eq 1) ($b -join ' | ')
Check 'L1a ValueBesideSummary: the real <summary> is still there too' `
  ($b -ccontains '/// <summary>Has a real summary alongside an unmodeled tag.</summary>') ($b -join ' | ')

# L1b -- the MIXED line: unmodeled container wrapping a modeled tag.
$b = $res['ParaWithInlineSee'].Block
Check 'L1b ParaWithInlineSee: the whole <para> line survives VERBATIM, inline <see cref> included' `
  ($b -ccontains '/// <para>Body with an inline <see cref="residual_lines.CallsParaWithInlineSee"/> reference.</para>') ($b -join ' | ')
Check 'L1b ParaWithInlineSee: the author prose around the inline tag is NOT mangled' `
  (-not (($b -join "`n") -match 'Body with an inline\s+reference')) ($b -join ' | ')
Check 'L1b ParaWithInlineSee: the inline <see cref> is NOT hoisted into a fabricated standalone entry' `
  (([regex]::Matches(($b -join "`n"), [regex]::Escape('<see cref="residual_lines.CallsParaWithInlineSee"/>'))).Count -eq 1) ($b -join ' | ')
Check 'L1b ParaWithInlineSee: the real <summary> is still there too' `
  ($b -ccontains '/// <summary>Real summary, so the region reaches the repair path.</summary>') ($b -join ' | ')

Write-Host ''
Write-Host '--- L2: a multi-line <example> keeps its interior indentation ------------------'

$b = $res['MultiLineExample'].Block
$want = @('/// <example>', '///   Foo := TBar.Create;', '///     Foo.Run;', '/// </example>')
# Contiguous-run match: the four lines must appear IN ORDER, ADJACENT, and with
# their EXACT original leading whitespace. A per-line -contains would pass on a
# block that had reordered or re-indented them.
$hit = -1
for ($i = 0; $i -le ($b.Count - $want.Count); $i++) {
  $ok = $true
  for ($k = 0; $k -lt $want.Count; $k++) { if ($b[$i + $k] -cne $want[$k]) { $ok = $false; break } }
  if ($ok) { $hit = $i; break }
}
Check 'L2 MultiLineExample: the four example lines survive as a contiguous run with EXACT indentation' `
  ($hit -ge 0) ($b -join ' | ')
Check 'L2 MultiLineExample: the open tag is NOT folded onto the first content line' `
  (-not (($b -join "`n") -match [regex]::Escape('<example>Foo'))) ($b -join ' | ')

Write-Host ''
Write-Host '--- L3: trailing author prose beside a modeled tag -----------------------------'

$b = $res['TrailingProseBesideSince'].Block
Check 'L3 TrailingProseBesideSince: the whole line survives VERBATIM, trailing prose included' `
  ($b -ccontains '/// <since>1.0</since> Trailing prose the author wrote.') ($b -join ' | ')
Check 'L3 TrailingProseBesideSince: no FABRICATED empty <summary></summary> appears' `
  (-not (($b -join "`n") -match [regex]::Escape('<summary></summary>'))) ($b -join ' | ')
Check 'L3 TrailingProseBesideSince: the <since> is not ALSO re-emitted as a separate tag' `
  (([regex]::Matches(($b -join "`n"), [regex]::Escape('<since>1.0</since>'))).Count -eq 1) ($b -join ' | ')

Write-Host ''
Write-Host '--- CONTROL: an entirely modeled comment must be untouched ---------------------'

$b = $res['FullyModeledControl'].Block
Check 'CONTROL FullyModeledControl: <summary> preserved verbatim' `
  ($b -ccontains '/// <summary>Plain, fully modeled comment; nothing here is residual.</summary>') ($b -join ' | ')
Check 'CONTROL FullyModeledControl: <param> preserved verbatim' `
  ($b -ccontains '/// <param name="AValue">The input value.</param>') ($b -join ' | ')
Check 'CONTROL FullyModeledControl: <returns> preserved verbatim' `
  ($b -ccontains '/// <returns>The doubled value.</returns>') ($b -join ' | ')
Check 'CONTROL FullyModeledControl: each modeled tag appears EXACTLY once (nothing carried through twice)' `
  ((([regex]::Matches(($b -join "`n"), '<summary>')).Count -eq 1) -and `
   (([regex]::Matches(($b -join "`n"), '<param ')).Count -eq 1) -and `
   (([regex]::Matches(($b -join "`n"), '<returns>')).Count -eq 1)) ($b -join ' | ')
Check 'CONTROL FullyModeledControl: exactly the pristine tag lines plus ONE facts <remarks> block' `
  ((@($b | Where-Object { $_ -notmatch '<remarks>|</remarks>|drag-lint:auto|Called from:|Returns:|Used in units:|Calls:' })).Count -eq $pristine['FullyModeledControl'].Count) ($b -join ' | ')

Write-Host ''
Write-Host '--- IMPORTANT 1: the accounted-span mask must agree with the MODEL -------------'

# The mask used to match containers with StripElement's attribute-TOLERANT
# pattern while the parser is STRICT. Anything in that gap was accounted (never
# carried through) but unrepresented (never re-emitted) -> DELETED. Two of these
# four are perfectly valid XML doc comments.
$maskCases = @{
  ExceptionNoCrefBesideSummary = '/// <exception>Missing the required cref attribute.</exception>'
  ParamNoNameBesideSummary     = '/// <param>Missing the required name attribute.</param>'
  AttributedRemarks            = '/// <remarks xml:lang="en">Attributed remarks prose must survive.</remarks>'
  AttributedExample            = '/// <example lang="pascal">Attributed example body must survive.</example>'
}
foreach ($nm in $maskCases.Keys | Sort-Object) {
  $b = $res[$nm].Block
  Check "MASK $nm : the unrepresentable-by-the-parser tag survives VERBATIM" `
    ($b -ccontains $maskCases[$nm]) ($b -join ' | ')
  Check "MASK $nm : ...and EXACTLY once" `
    ((@($b | Where-Object { $_ -ceq $maskCases[$nm] })).Count -eq 1) ($b -join ' | ')
  Check "MASK $nm : the real <summary> beside it survives too" `
    ((($b -join "`n") -match '<summary>Real summary')) ($b -join ' | ')
}
# The attributed <remarks> necessarily coexists with the engine's own facts
# <remarks> -- the author's element is unrepresentable, so preserving it means
# two <remarks> in one comment. Pinned so the consequence is explicit and a
# future change to it is visible.
$b = $res['AttributedRemarks'].Block
Check 'MASK AttributedRemarks: the engine still writes its OWN facts <remarks> beside the attributed one (pinned consequence)' `
  ((([regex]::Matches(($b -join "`n"), '<remarks')).Count) -eq 2) ($b -join ' | ')

Write-Host ''
Write-Host '--- IMPORTANT 2 + 3: a span the engine REGENERATES is never retracted ----------'

# Retracting such a span froze the engine's own fact text as un-maintained,
# un-strippable author prose AND emitted a second <remarks>/<returns>. The fix
# fails closed: the whole carry-through aborts for the region and it falls back
# to pre-v(ADP3 T3f) behaviour, which drops the tail. That drop is PINNED below
# as a deliberate, disclosed non-improvement -- chosen over a duplicate element
# plus a permanently stale fact.
$b = $res['FencedRemarksTailValue'].Block
Check 'FENCE FencedRemarksTailValue: EXACTLY ONE <remarks> element (no duplicate beside a frozen copy)' `
  ((([regex]::Matches(($b -join "`n"), '<remarks>')).Count) -eq 1) ($b -join ' | ')
Check 'FENCE FencedRemarksTailValue: the stale ghost fact is GONE (facts are still maintained, not frozen)' `
  (-not (($b -join "`n") -match 'STALE_GHOST')) ($b -join ' | ')
Check 'FENCE FencedRemarksTailValue: the regenerated fence names the REAL caller' `
  ((($b -join "`n") -match 'Called from:.*residual_lines\.CallsFencedRemarksTailValue')) ($b -join ' | ')
Check 'FENCE FencedRemarksTailValue: exactly ONE facts fence' `
  ((([regex]::Matches(($b -join "`n"), [regex]::Escape('<!-- drag-lint:auto BEGIN -->'))).Count) -eq 1) ($b -join ' | ')
Check 'FENCE FencedRemarksTailValue: the hand-written <summary> is untouched' `
  ($b -ccontains '/// <summary>Has a LIVE facts fence with an unmodeled tail on its close line.</summary>') ($b -join ' | ')
Check 'FENCE FencedRemarksTailValue: PINNED FALLBACK -- the unmodeled tail is NOT preserved (pre-T3f behaviour; see the task report)' `
  (-not (($b -join "`n") -match 'tail value')) ($b -join ' | ')

$b = $res['MarkedReturnsTail'].Block
Check 'MARKED MarkedReturnsTail: EXACTLY ONE <returns> element (no duplicate beside a frozen copy)' `
  ((([regex]::Matches(($b -join "`n"), '<returns>')).Count) -eq 1) ($b -join ' | ')
Check 'MARKED MarkedReturnsTail: the stale marked text is GONE (the engine still regenerates it)' `
  (-not (($b -join "`n") -match 'STALE cases')) ($b -join ' | ')
Check 'MARKED MarkedReturnsTail: the regenerated <returns> carries the freshly mined case' `
  ((($b -join "`n") -match [regex]::Escape('<returns><!-- drag-lint:auto -->Observed: 42.</returns>'))) ($b -join ' | ')
Check 'MARKED MarkedReturnsTail: PINNED FALLBACK -- the hand tail is NOT preserved (pre-T3f behaviour; see the task report)' `
  (-not (($b -join "`n") -match 'hand tail')) ($b -join ' | ')
Check 'MARKED MarkedReturnsTail: the hand-written <summary> is untouched' `
  ($b -ccontains '/// <summary>Has an engine-marked returns with a hand-written tail outside it.</summary>') ($b -join ' | ')

Write-Host ''
Write-Host '--- STRIP ROUND-TRIP: what is preserved must also come back out ----------------'

# The two fail-closed shapes are excluded: nothing on their tail line is
# preserved in the first place (pinned above), so a "pristine lines come back"
# assertion would be asserting the fallback, not the round-trip.
$preservedShapes = $shapes | Where-Object { $_ -notin @('FencedRemarksTailValue','MarkedReturnsTail') }
foreach ($nm in $preservedShapes) {
  $r = $res[$nm]
  & $exePath index $r.Scratch --db $r.Db 2>$null | Out-Null
  & $exePath document --qname "residual_lines.$nm" --db $r.Db --strip --apply 2>$null | Out-Null
  $after = Get-DocBlockLines ([IO.File]::ReadAllLines($r.Target)) $decl[$nm]
  Check "STRIP $nm : every pristine /// line is back, verbatim" `
    ((@($pristine[$nm] | Where-Object { $after -cnotcontains $_ })).Count -eq 0) `
    ("missing=" + (@($pristine[$nm] | Where-Object { $after -cnotcontains $_ }) -join ' | '))
  Check "STRIP $nm : no engine residue survives the strip" `
    (-not (($after -join "`n") -match 'drag-lint:auto')) ($after -join ' | ')
  Check "STRIP $nm : no leftover empty <remarks> wrapper" `
    (-not (($after -join "`n") -match '<remarks>')) ($after -join ' | ')
}

# The two shapes whose pristine tag order already matches the emitter's own
# fixed order round-trip BYTE-IDENTICALLY. (The other three legitimately come
# back reordered: the emitter has always written tags in one fixed order --
# summary -> deprecated -> params -> returns -> exceptions -> example ->
# seealso -> since -> carried-through residual -> remarks -- regardless of the
# order the author used, and `--strip` is marker-keyed so it cannot and must
# not undo an ordering change nothing marked.)
foreach ($nm in @('MultiLineExample','TrailingProseBesideSince','FullyModeledControl')) {
  $after = Get-DocBlockLines ([IO.File]::ReadAllLines($res[$nm].Target)) $decl[$nm]
  Check "STRIP $nm : the stripped block is BYTE-IDENTICAL to pristine" `
    ((($after -join "`n")) -ceq (($pristine[$nm] -join "`n"))) `
    ("pristine=[" + ($pristine[$nm] -join ' | ') + "] after=[" + ($after -join ' | ') + "]")
}

# Everything emitted stays 7-bit ASCII.
foreach ($nm in $shapes) {
  $bad = @()
  foreach ($l in [IO.File]::ReadAllLines($res[$nm].Target)) {
    if ($l -match '^\s*///') { foreach ($ch in $l.ToCharArray()) { if ([int]$ch -gt 126) { $bad += $l; break } } }
  }
  Check "ASCII $nm : every emitted /// line is 7-bit ASCII" ($bad.Count -eq 0) ($bad -join ' | ')
}

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
