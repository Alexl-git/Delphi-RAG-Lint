<#
  Emit-Effects.ps1 -- the `effects` question: what a method actually does to
  state outside its own locals.

  >>> THE HEADLINE IS effect_free, NEVER "effect_summary IS NULL" <<<
  -------------------------------------------------------------------
  `TEffectSummary.Encode` returns '' for an effect-free routine
  (Purity.pas:317-330) and the writer stores '' as NULL
  (DRagLint.Storage.SQLite.pas:8023). So a NULL summary is overwhelmingly the
  PURE case, not the unanalysed one. Measured on the CLIENT clone, 2026-09-23:

      summary          effect_free   rows    means
      tokens           0             7,258   has effects, listed
      NULL             1             2,892   effect-FREE -- pure
      NULL             NULL            855   genuinely not analysed

  Reading absence as ignorance would tell the reader that 2,892 provably pure
  methods were unanalysed -- the exact inversion of the fact. So `effect_free`
  decides the outcome and the summary only fills in the detail.

  Re-measured on the extractor 1.19 clone (2026-09-24): 7,234 / 2,918 / 855
  (1.18 clone: 7,257 / 2,895 / 855). The +23 pure are engine D12's fix: 20 functions whose only `g` was their own
  Result assignment, and 3 BASICSF callers (Magnitude, EqualZero, IsSampleof1)
  whose `g` was inherited from one of them.

  THE LEGEND, READ FROM THE ENGINE, NOT INFERRED FROM THE DATA
  -------------------------------------------------------------
  From TEffectFlag / Encode / Decode (Purity.pas:25, 317, 332):

      g       writes global state
      h       FREES OR RESIZES heap storage   (not "uses the heap")
      s       writes fields of its own instance
      p<k>    writes through parameter k, ZERO-BASED
      ?       this build could not classify something

  `?` IS AN ADMISSION, NOT AN EFFECT. It is the most common token on CLIENT
  (3,148 bare `?`), and it is drawn dashed so `g,s,?` can never read as a
  complete answer. Decode folds ANY unrecognised token to `?`, so a future token
  degrades to "unknown" rather than erroring.

  NAMING THE PARAMETER: mutates_params IS NOT THAT COLUMN
  --------------------------------------------------------
  The plan expected `mutates_params` to name the p-token parameters and treated
  the ~12% of rows where it is empty as unnameable. Measured, it is a different
  fact: it lists parameters declared `var`/`out`, so

      FormKeyUp(Sender; var Key: Word; Shift)  summary g,p1,?  mutates "Key (var)"
      APVDotProduct(V1; I11, I12; V2; ...)     summary g,p0,p3,?  mutates ""
      InjectDataService(const APlan; AContainer) summary p0,?   mutates ""

  EVERY multi-p row on CLIENT has an empty `mutates_params`, and `p0` on
  InjectDataService is a `const` parameter whose MEMBER is written -- a real
  effect with nothing for that column to say. Pairing the two lists positionally
  would have quietly mislabelled those rows.

  So the name comes from parsing `symbols.signature` by ordinal, which handles
  the grouped-parameter form (`I11, I12: AlglibInteger` is TWO ordinals) that
  makes naive counting wrong. When the parse cannot reach ordinal k, the row says
  `parameter #k` and says WHY -- it never guesses and never silently drops.

  THE WITNESS BELONGS TO ONE EFFECT, NOT ALL OF THEM
  ---------------------------------------------------
  `effect_witness` is "the FIRST blocker" (Purity.pas:29-36) and is never
  overwritten, so it explains whichever effect was recorded first -- on
  APVDotProduct it is "calls Assert (unbound)", which is the `?`, not the `p0`.
  Attaching it to every row would caption three effects with one effect's reason.
  It is shown once, labelled as the first recorded witness.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Qname,
  [Parameter(Mandatory)][string] $DbPath,
  [string] $OutDir,
  [string] $Engine     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe',
  [string] $Dot        = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe',
  [string] $FontMono   = 'Consolas',
  [string] $FontSans   = 'Segoe UI',
  # TEST HOOK (R25, fix round 1): replaces the STORED effect facts -- keys ef, es,
  # ew, mp -- so the gate can prove the D12 detector is WIRED into this emitter
  # now that no real row reaches it. A chart drawn from injected facts says so
  # on its focus box, so it can never pass for an index answer.
  [hashtable] $FactOverride
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

# Refuse a live corpus DB (see Get-CloneDb): charts run against the frozen clones.
$DbPath = Get-CloneDb $DbPath

$PAL = @{
  pureBorder  = '#0F766E'; pureFill  = '#E2F1EF'; pureHdr  = '#0F766E'
  fxBorder    = '#B45309'; fxFill    = '#FEF6EC'; fxHdr    = '#B45309'
  unkBorder   = '#6B7280'; unkFill   = '#F3F4F6'; unkHdr   = '#6B7280'
  naBorder    = '#9AA3AF'; naFill    = '#F3F4F6'; naHdr    = '#6B7280'
  focusBorder = '#3B5BDB'; focusFill = '#EDF2FF'; focusHdr = '#3B5BDB'
  rowInk      = '#1F2933'; lineInk   = '#8A94A6'
}

Write-Host "effects: $Qname"

# ---- 1. resolve ------------------------------------------------------------------
$sel = Resolve-MemberSelection $Qname @('method', 'function', 'procedure', 'constructor', 'destructor') `
         -Hint 'effects selects a METHOD -- ask class-surface for a type'

$fact = Invoke-IndexQuery @"
SELECT sf.effect_free AS ef, sf.effect_summary AS es, sf.effect_witness AS ew,
       sf.mutates_params AS mp, s.signature AS sig
  FROM symbol_facts sf JOIN symbols s ON s.id = sf.symbol_id
 WHERE sf.symbol_id = $($sel.Id)
"@
if ($fact.Count -eq 0) {
  throw ("$($sel.Qname) has no symbol_facts row at all -- the purity stage never saw it. " +
         'That is a different answer from "not analysed"; report it rather than reading it as pure.')
}
$ef  = $fact[0].ef
$es  = [string]$fact[0].es
$ew  = [string]$fact[0].ew
$mp  = [string]$fact[0].mp
$sig = [string]$fact[0].sig
if ($FactOverride) {
  if ($FactOverride.ContainsKey('ef')) { $ef = $FactOverride.ef }
  if ($FactOverride.ContainsKey('es')) { $es = [string]$FactOverride.es }
  if ($FactOverride.ContainsKey('ew')) { $ew = [string]$FactOverride.ew }
  if ($FactOverride.ContainsKey('mp')) { $mp = [string]$FactOverride.mp }
  Write-Host "  TEST: stored facts replaced by -FactOverride (ef=$ef es='$es' ew='$ew')"
}

# ---- 2. parameter names by ORDINAL, from the signature ----------------------------
# Delphi groups parameters: `I11, I12: AlglibInteger` is TWO ordinals sharing one
# type. Split the list on top-level ';', then each group on ',', stripping the
# var/out/const modifier from the group's first name.
function Get-ParamNames([string] $Signature) {
  if ([string]::IsNullOrWhiteSpace($Signature)) { return , @() }
  $open = $Signature.IndexOf('(')
  if ($open -lt 0) { return , @() }
  $depth = 0; $endAt = -1
  for ($i = $open; $i -lt $Signature.Length; $i++) {
    $ch = $Signature[$i]
    if ($ch -eq '(' -or $ch -eq '[') { $depth++ }
    elseif ($ch -eq ')' -or $ch -eq ']') { $depth--; if ($depth -eq 0) { $endAt = $i; break } }
  }
  if ($endAt -lt 0) { return , @() }
  $inner = $Signature.Substring($open + 1, $endAt - $open - 1)
  if ([string]::IsNullOrWhiteSpace($inner)) { return , @() }

  # split on ';' at depth 0
  $groups = New-Object System.Collections.ArrayList
  $buf = New-Object System.Text.StringBuilder
  $depth = 0
  foreach ($ch in $inner.ToCharArray()) {
    if ($ch -eq '(' -or $ch -eq '[') { $depth++ }
    elseif ($ch -eq ')' -or $ch -eq ']') { $depth-- }
    if ($ch -eq ';' -and $depth -eq 0) { [void]$groups.Add($buf.ToString()); [void]$buf.Clear(); continue }
    [void]$buf.Append($ch)
  }
  [void]$groups.Add($buf.ToString())

  $names = New-Object System.Collections.ArrayList
  foreach ($g in $groups) {
    $decl = $g
    # drop the type and any default value; the names are before the first ':'
    $colon = $decl.IndexOf(':')
    if ($colon -ge 0) { $decl = $decl.Substring(0, $colon) }
    $decl = $decl.Trim()
    if (-not $decl) { continue }
    # strip a leading parameter modifier
    $decl = [regex]::Replace($decl, '^(?i)\s*(var|out|const|constref)\s+', '')
    foreach ($n in ($decl -split ',')) {
      $nm = $n.Trim()
      if ($nm) { [void]$names.Add($nm) }
    }
  }
  , $names.ToArray()
}
$paramNames = Get-ParamNames $sig

# ---- 3. decode, mirroring TEffectSummary.Decode -----------------------------------
# Same folding rule as the engine: lowercase, trim, and ANY unrecognised token
# becomes `?` rather than an error.
$effects = New-Object System.Collections.ArrayList
$unnamed = 0
if ($es) {
  foreach ($raw in ($es -split ',')) {
    $tok = $raw.Trim().ToLowerInvariant()
    if (-not $tok) { continue }
    switch -Regex ($tok) {
      '^g$' { [void]$effects.Add([pscustomobject]@{ Kind = 'g'; Text = 'writes global state'; Unknown = $false }); break }
      '^h$' { [void]$effects.Add([pscustomobject]@{ Kind = 'h'; Text = 'frees or resizes heap storage'; Unknown = $false }); break }
      '^s$' { [void]$effects.Add([pscustomobject]@{ Kind = 's'; Text = 'writes fields of its own instance'; Unknown = $false }); break }
      '^p\d+$' {
        $k = [int]$tok.Substring(1)
        if ($k -lt $paramNames.Count) {
          [void]$effects.Add([pscustomobject]@{ Kind = 'p'; Text = "writes through parameter #$k ($($paramNames[$k]))"; Unknown = $false })
        } else {
          $unnamed++
          $why = $(if ($paramNames.Count -eq 0) { 'no parameter list recorded for this symbol' }
                   else { "the recorded signature lists only $($paramNames.Count) parameter(s)" })
          [void]$effects.Add([pscustomobject]@{ Kind = 'p'; Text = "writes through parameter #$k (not named: $why)"; Unknown = $false })
        }
        break
      }
      default { [void]$effects.Add([pscustomobject]@{ Kind = '?'; Text = 'something this build could not classify'; Unknown = $true }) }
    }
  }
}

# ---- 4. the three outcomes ---------------------------------------------------------
$outcome = $(if ($null -eq $ef) { 'not-analysed' } elseif ([int]$ef -eq 1) { 'pure' } else { 'effects' })

# A shape the crosstab says should not exist. Say so rather than picking one.
if ($outcome -eq 'pure' -and $effects.Count -gt 0) {
  Write-Host "  NOTE: effect_free=1 yet the summary carries tokens ('$es') -- reporting BOTH, this shape is not in the measured crosstab"
}

# ENGINE D12 (INBOX-defects-found-2026-09-23-rule-work.md). A function that sets
# its result through its OWN NAME (`AP_FP_Greater_Eq := X >= Y`) is scored as a
# GLOBAL write: the witness reads "writes AP_FP_Greater_Eq (non-local)". Measured
# on the CLIENT clone 2026-09-23: 31 functions carry exactly that witness, 20 of
# them with summary `g` alone -- effect-free routines the stored fact calls
# impure. Drawing that `g` as "writes global state" would repeat the engine's
# false claim, so it is moved to a dashed disclosure instead.
#
# Detectable only when the WITNESS names the routine. The witness is the FIRST
# blocker only, so a D12 write recorded after a genuine one (witness names the
# genuine one) cannot be told apart and is still drawn as `g` -- the docs say so.
#
# ENGINE FIX (extractor 1.19, re-baseline 2026-09-24): purity now scores the
# own-name assignment as a local. 0 functions carry that witness on any clone
# (CLIENT 31 -> 0, SERVER 30 -> 0, TestMicroniteObjects 30 -> 0), and
# AP_FP_Greater_Eq is now pure. The detector stays (R25) as a guard against a
# regression, and Test-D12OwnNameWrite (Emit-Common) is driven on synthetic
# rows by the gate, since no real row can reach it any more.
$ownName = [string]$sel.Name
$d12 = Test-D12OwnNameWrite $ownName $ew $effects
if ($d12) {
  $effects = [System.Collections.ArrayList]@($effects | Where-Object { $_.Kind -ne 'g' })
}

$known = @($effects | Where-Object { -not $_.Unknown })
$unk   = @($effects | Where-Object { $_.Unknown })

Write-Host ("  outcome={0}  effect_free={1}  summary='{2}'  effects={3} (unknown {4})" -f `
            $outcome, $(if ($null -eq $ef) { 'NULL' } else { $ef }), $es, $known.Count, $unk.Count)

# ---- 5. dot -------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('digraph effects {')
[void]$sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;')
[void]$sb.AppendLine('  nodesep=0.3; ranksep=1.2; splines=spline;')
[void]$sb.AppendLine("  graph [fontname=`"$FontSans`"];")
[void]$sb.AppendLine("  node  [shape=plaintext, fontname=`"$FontMono`", fontsize=14];")
[void]$sb.AppendLine("  edge  [fontname=`"$FontMono`", fontsize=11, color=`"$($PAL.lineInk)`", penwidth=1.4, arrowsize=0.7];")
[void]$sb.AppendLine('')

$nodeId = 0; $clusters = 0; $anchored = 0

# FOCUS: the method
$nodeId++; $clusters++
$fnid = "n$nodeId"
$ftbl = New-Object System.Text.StringBuilder
[void]$ftbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
[void]$ftbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$($PAL.focusHdr)`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $(ConvertTo-XmlText $sel.Name) </B></FONT></TD></TR>")
$anchored++
[void]$ftbl.Append("<TR><TD PORT=`"p1`" ALIGN=`"LEFT`" HREF=`"$(New-RowHref $sel.Path $sel.FocusLine)`" TITLE=`"$(ConvertTo-XmlText $sel.Qname)`">")
[void]$ftbl.Append("<FONT COLOR=`"$($PAL.rowInk)`">$(ConvertTo-XmlText (Get-UnitName $sel.Path))</FONT>")
[void]$ftbl.Append("  <FONT COLOR=`"$($PAL.lineInk)`" POINT-SIZE=`"12`">:$($sel.FocusLine)</FONT></TD></TR>")
if ($FactOverride) { Add-DisclosureRow $ftbl 'TEST CHART: the effect facts below were INJECTED (-FactOverride), not read from the index' $PAL.lineInk }
if ($sig) { Add-DisclosureRow $ftbl $sig $PAL.lineInk 11 }
Add-DisclosureRow $ftbl "effect_free = $(if ($null -eq $ef) { 'NULL' } else { $ef })  &#183;  stored summary = $(if ($es) { $es } else { '(empty)' })" $PAL.lineInk
if ($ew) { Add-DisclosureRow $ftbl "first recorded witness: $ew" $PAL.lineInk }
if ($mp) { Add-DisclosureRow $ftbl "declared var/out parameters mutated: $mp" $PAL.lineInk }
if ($unnamed -gt 0) { Add-DisclosureRow $ftbl "$unnamed parameter effect(s) could not be named from the signature" $PAL.lineInk }
[void]$ftbl.Append('</TABLE>')
[void]$sb.AppendLine("  subgraph cluster_focus_$nodeId {")
[void]$sb.AppendLine("    style=`"rounded,filled`"; color=`"$($PAL.focusBorder)`"; fillcolor=`"$($PAL.focusFill)`"; penwidth=2;")
[void]$sb.AppendLine('    label=""; margin=10;')
[void]$sb.AppendLine("    $fnid [label=<$($ftbl.ToString())>];")
[void]$sb.AppendLine('  }')

$linkTo = New-Object System.Collections.ArrayList

# PURE
if ($outcome -eq 'pure') {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_pure_$nodeId" -Nid $nid `
           -Title 'pure' -Subtitle 'no effects recorded' `
           -Rows @((New-NoteRow 'effect_free = 1: this routine writes no global, no field, no parameter'),
                   (New-NoteRow 'the stored summary is empty, which is how the engine encodes pure')) `
           -Border $PAL.pureBorder -Fill $PAL.pureFill -Hdr $PAL.pureHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
  [void]$linkTo.Add(@($nid, $PAL.pureBorder))
}

# NOT ANALYSED
if ($outcome -eq 'not-analysed') {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_na_$nodeId" -Nid $nid `
           -Title 'not analysed' -Subtitle 'effect_free is NULL' `
           -Rows @((New-NoteRow 'the purity stage recorded no verdict for this routine'),
                   (New-NoteRow 'this is NOT the same as pure -- nothing is claimed either way')) `
           -Border $PAL.naBorder -Fill $PAL.naFill -Hdr $PAL.naHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style 'rounded,filled,dashed')
  [void]$linkTo.Add(@($nid, $PAL.naBorder))
}

# THE EFFECTS, one row each
if ($known.Count -gt 0) {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  $rows = @($known | ForEach-Object { New-NoteRow $_.Text })
  [void](Add-RowCluster -Sb $sb -Cid "cluster_fx_$nodeId" -Nid $nid `
           -Title 'effects' -Subtitle "$($known.Count) recorded" -Rows $rows `
           -Border $PAL.fxBorder -Fill $PAL.fxFill -Hdr $PAL.fxHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans)
  [void]$linkTo.Add(@($nid, $PAL.fxBorder))
}

# D12: the suspect global write, dashed, never in the effects cluster
if ($d12) {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  # Claims only what the data shows: `g` is ONE token however many global
  # writes there are, and the witness names only the first blocker -- so the
  # chart cannot say whether a genuine global write also exists.
  $alone = 'no other global write is visible in the witness (it names only the first blocker)'
  [void](Add-RowCluster -Sb $sb -Cid "cluster_d12_$nodeId" -Nid $nid `
           -Title 'engine D12' -Subtitle 'global write NOT shown' `
           -Rows @((New-NoteRow "the stored g's witness is this routine's OWN NAME: '$ew'"),
                   (New-NoteRow "that is a Result assignment ($ownName := ...), which this engine build scores as a global write"),
                   (New-NoteRow $alone)) `
           -Border $PAL.unkBorder -Fill $PAL.unkFill -Hdr $PAL.unkHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style 'rounded,filled,dashed')
  [void]$linkTo.Add(@($nid, $PAL.unkBorder, $true))
}

# THE ADMISSION, always its own dashed cluster so it cannot read as an effect
if ($unk.Count -gt 0) {
  $nodeId++; $clusters++
  $nid = "n$nodeId"
  [void](Add-RowCluster -Sb $sb -Cid "cluster_unk_$nodeId" -Nid $nid `
           -Title 'unclassified' -Subtitle "$($unk.Count) token" `
           -Rows @((New-NoteRow 'this build could not classify part of this routine'),
                   (New-NoteRow 'the effect list above is therefore INCOMPLETE, not final')) `
           -Border $PAL.unkBorder -Fill $PAL.unkFill -Hdr $PAL.unkHdr `
           -RowInk $PAL.rowInk -LineInk $PAL.lineInk -FontSans $FontSans -Style 'rounded,filled,dashed')
  [void]$linkTo.Add(@($nid, $PAL.unkBorder))
}

[void]$sb.AppendLine('')
foreach ($t in $linkTo) {
  $style = $(if ($t.Count -gt 2 -or $t[0] -match 'unk|na') { ', style=dashed' } else { '' })
  [void]$sb.AppendLine("  ${fnid}:p1 -> $($t[0]) [color=`"$($t[1])`"$style];")
}
[void]$sb.AppendLine('}')

# ---- 6. lay out ----------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $PSScriptRoot '..\scratch' }
$base = 'effects_' + ($sel.Qname -replace '[^A-Za-z0-9]', '_')
$lay = Invoke-DotLayout $sb.ToString() $OutDir $base

[pscustomobject]@{
  Dot          = $lay.Dot
  Svg          = $lay.Svg
  Plain        = $lay.Plain
  Png          = $lay.Png
  Pdf          = $lay.Pdf
  Qname        = $sel.Qname
  Outcome      = $outcome
  EffectFree   = $(if ($null -eq $ef) { 'NULL' } else { [string]$ef })
  Summary      = $es
  Effects      = $known.Count
  Unknown      = $unk.Count
  Unnamed      = $unnamed
  D12Suspect   = $d12
  ParamCount   = $paramNames.Count
  Witness      = $ew
  Clusters     = $clusters
  ClickTargets = $lay.Anchors
  Expected     = $anchored
  AllClickable = ($lay.Anchors -ge $anchored)
}
