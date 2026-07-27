<#
  run_doc_p3_indent.ps1 -- Auto-Document Phase 3, Task 3g: `document --apply`
  must write a doc comment at the DECLARATION's own indentation.

  THE DEFECT
  ----------
  TDocumenter.BuildForSymbol handed TDocRegions.MergeComment the hardcoded
  literal '/// ' as its line prefix, so every emitted line landed at column 0
  no matter how deeply the declaration was indented. For a unit-level routine
  that is invisible; for a class member -- four spaces in this codebase, two or
  eight or a tab elsewhere -- the first `--apply` silently re-formatted the
  author's documentation:

      TThing = class
        /// <summary>Does the thing.</summary>      became    /// <summary>...
        procedure Run;                                          procedure Run;

  Nothing in the battery could see it. Both idempotency compares run through
  NormalizeCommentLines, which Trims every line, so they are indentation-blind
  by construction; the 2026-07-24 YADF run was declared clean on byte-identical
  declaration counts plus a 7-bit-ASCII sweep, and neither of those can detect
  an indentation change either.

  WHAT THIS RUNNER PINS
  ---------------------
  One shape per edge case, from fixtures\docp3\indent.pas. For each, the EXACT
  leading-whitespace run of every emitted /// line is compared to the
  declaration's own -- exact equality, never "starts with" or "contains",
  because "starts with" passes on a DOUBLE-indented block and "contains"
  passes on almost anything.

    UnitLevelControl  column 0. The control in the other direction: a fix that
                      indents unconditionally would otherwise go unnoticed.
    TwoSpaceMember    TWO spaces (its class is declared at column 0 on purpose)
    DeepMember        EIGHT spaces, a nested type's member
    TabMember         a TAB -- copied verbatim, never normalized to spaces
    ResidualMember    the v(ADP3 T3f) carry-through: an unmodeled author line
                      keeps its interior text verbatim AND lands at the
                      member's indent, neither doubled nor left at column 0
    GappedMember      a doc region separated from its declaration by a blank
                      line: the DECLARATION's indentation governs, not the
                      comment's own (the fixture mis-indents the comment to six
                      spaces so the answer cannot be read both ways)
    FreshMember       the fresh-insert branch, no prior comment at all
    DamagedMember     option (B): a block an EARLIER build already flattened to
                      column 0 is deliberately RE-INDENTED, and still converges

  Plus, for every shape: a 3-cycle md5 fixed point with cycles 2 and 3
  reporting edits=0 (the binding acceptance criterion), the pinned cycle-1
  branch action, a `document --strip` round-trip, and 7-bit ASCII.

  Method: one ISOLATED scratch copy per shape, then 3 x (index -> document
  --qname --apply) -- the idempotency sweep's own methodology.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\indent.pas')).Path

# The contiguous run of ///-prefixed lines above the FIRST line matching
# $declPattern, returned RAW (never trimmed) so indentation is assertable --
# trimming here is exactly the blindness this runner exists to remove. ONE
# leading blank line is tolerated before the scan starts, mirroring
# FindDocRegionAbove's own AllowGap=1, so the gapped shape is found the same
# way an abutting one is.
function Get-DocBlockLines([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -cmatch $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $i = $idx - 1
  if (($i -ge 0) -and ($lines[$i].Trim() -eq '')) { $i-- }
  $acc = New-Object System.Collections.Generic.List[string]
  for (; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i])
  }
  return $acc.ToArray()
}

# True when $declPattern matches some line of $lines. A SEPARATE test from
# Get-DocBlockLines, deliberately: that function returns an EMPTY array for a
# declaration that is present but undocumented (FreshMember), and PowerShell
# unrolls an empty array to $null, so "the block is $null" cannot distinguish
# "no such declaration" from "no comment yet".
function Test-DeclPresent([string[]]$lines, [string]$declPattern) {
  foreach ($l in $lines) { if ($l -cmatch $declPattern) { return $true } }
  return $false
}

# $a as a real array with $null entries removed -- see Test-DeclPresent for why
# a bare .Count on a Get-DocBlockLines result cannot be trusted.
function Get-Lines($a) { return @(@($a) | Where-Object { $null -ne $_ }) }

# The EXACT leading-whitespace run of $s (tabs and spaces kept as-is).
function Get-Indent([string]$s) { return $s.Substring(0, $s.Length - $s.TrimStart().Length) }

function Show-Ws([string]$s) { return ($s -replace "`t",'<TAB>' -replace ' ','<SP>') }

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash.Substring(0,8) }

# 3 --qname-scoped apply cycles in an isolated scratch copy, reindexing before
# each. Returns per-cycle action/edits and whole-file md5.
function Invoke-ShapeSweep([string]$root, [string]$qname, [string]$slug) {
  $scratch = Join-Path $root $slug
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch -Force | Out-Null
  $target = Join-Path $scratch 'indent.pas'
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

# Per shape: the qualified name, the declaration line's own regex, that line's
# EXACT leading whitespace, and the pinned cycle-1 branch action. The Indent
# column is the whole point of this runner -- it is the ANSWER, written down
# independently of the engine, not read back out of it.
$shapes = [ordered]@{
  UnitLevelControl = @{ QName='indent.UnitLevelControl';             Decl='^procedure UnitLevelControl;';    Indent='';          Act='extended' }
  TwoSpaceMember   = @{ QName='indent.TTwoSpace.TwoSpaceMember';     Decl='^  procedure TwoSpaceMember;';    Indent='  ';        Act='extended' }
  DeepMember       = @{ QName='indent.TOuter.TInner.DeepMember';     Decl='^        procedure DeepMember;';  Indent='        ';  Act='extended' }
  TabMember        = @{ QName='indent.TTabbed.TabMember';            Decl="^`tprocedure TabMember;";         Indent="`t";        Act='extended' }
  ResidualMember   = @{ QName='indent.TResidual.ResidualMember';     Decl='^    procedure ResidualMember;';  Indent='    ';      Act='extended' }
  GappedMember     = @{ QName='indent.TGapped.GappedMember';         Decl='^    procedure GappedMember;';    Indent='    ';      Act='extended' }
  DamagedMember    = @{ QName='indent.TDamaged.DamagedMember';       Decl='^    procedure DamagedMember;';   Indent='    ';      Act='extended' }
  FreshMember      = @{ QName='indent.TFresh.FreshMember';           Decl='^    procedure FreshMember;';     Indent='    ';      Act='created'  }
}

$pristineLines = [IO.File]::ReadAllLines($fixture)
$pristine = @{}
foreach ($nm in $shapes.Keys) { $pristine[$nm] = Get-DocBlockLines $pristineLines $shapes[$nm].Decl }

$root = Join-Path C:\TEMP 'draglint_docp3indent'
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
New-Item -ItemType Directory -Path $root | Out-Null

Push-Location C:\TEMP
try {

# Every declaration this runner names must actually be found in the fixture,
# or every "block indent" assertion below would be asserting over $null and
# could pass vacuously.
foreach ($nm in $shapes.Keys) {
  Check "FIXTURE $nm : the declaration line is present and matched" `
    (Test-DeclPresent $pristineLines $shapes[$nm].Decl) $shapes[$nm].Decl
}
# ...and the fixture really does carry the indentation this runner claims for
# it. Without this, a fixture edit that silently re-indented a declaration
# would quietly redefine what every assertion below is testing.
foreach ($nm in $shapes.Keys) {
  $declLine = @($pristineLines | Where-Object { $_ -cmatch $shapes[$nm].Decl })[0]
  Check "FIXTURE $nm : the declaration's own indent is the one this runner asserts" `
    ((Get-Indent $declLine) -ceq $shapes[$nm].Indent) `
    ("declared=[" + (Show-Ws (Get-Indent $declLine)) + "] asserted=[" + (Show-Ws $shapes[$nm].Indent) + "]")
}

$res  = @{}
$slug = 0
foreach ($nm in $shapes.Keys) {
  $slug++
  $r = Invoke-ShapeSweep $root $shapes[$nm].QName ('s{0:d2}' -f $slug)
  $res[$nm] = $r
  $blk = Get-DocBlockLines ([IO.File]::ReadAllLines($r.Target)) $shapes[$nm].Decl
  $r | Add-Member -NotePropertyName Block -NotePropertyValue $blk
  Write-Host ('  {0,-18} md5={1}  actions={2}' -f $nm, ($r.Md5s -join ' '), ($r.Actions -join ' '))
}

Write-Host ''
Write-Host '--- INDENTATION: every emitted line sits at the DECLARATION s own indent ------'

foreach ($nm in $shapes.Keys) {
  $want = $shapes[$nm].Indent
  $blk  = Get-Lines $res[$nm].Block
  Check "INDENT $nm : a doc block was written at all" ($blk.Count -gt 0) ("count=" + $blk.Count)
  if ($blk.Count -eq 0) { continue }
  # EXACT equality on the whole leading-whitespace run: 'starts with' would
  # pass on a DOUBLE-indented block, and a regex on \s+ would treat a tab and
  # spaces as interchangeable. Both are failure modes this task can produce.
  $wrong = @($blk | Where-Object { (Get-Indent $_) -cne $want })
  Check "INDENT $nm : every /// line's leading whitespace is EXACTLY the declaration's" `
    ($wrong.Count -eq 0) `
    ("want=[" + (Show-Ws $want) + "] offenders=" + (($wrong | ForEach-Object { '[' + (Show-Ws (Get-Indent $_)) + ']' + $_.Trim() }) -join ' | '))
}

# The tab shape gets its own explicit assertion: a fix that measured the indent
# as a COLUMN COUNT and rebuilt it out of spaces satisfies "leading whitespace
# is 1 char" for nothing, but a fix that expanded the tab to spaces would still
# have to be caught by something that names tabs specifically.
$blk = $res['TabMember'].Block
Check 'TAB TabMember : the indentation is a literal TAB, not spaces' `
  ((@($blk | Where-Object { $_.StartsWith("`t") })).Count -eq @($blk).Count) `
  (($blk | ForEach-Object { '[' + (Show-Ws (Get-Indent $_)) + ']' }) -join ' ')
Check 'TAB TabMember : no emitted line was tab-expanded into spaces' `
  ((@($blk | Where-Object { $_ -match '^ ' })).Count -eq 0) (($blk | ForEach-Object { '[' + (Show-Ws (Get-Indent $_)) + ']' }) -join ' ')

Write-Host ''
Write-Host '--- CONTROL: a column-0 declaration must NOT gain indentation ------------------'

$blk = $res['UnitLevelControl'].Block
Check 'CONTROL UnitLevelControl : the block is still flush at column 0' `
  ((@($blk | Where-Object { $_ -cmatch '^\s' })).Count -eq 0) ($blk -join ' | ')
Check 'CONTROL UnitLevelControl : the hand-written summary survived verbatim' `
  ($blk -ccontains '/// <summary>Unit-level control: this comment sits at column 0 and must STAY') ($blk -join ' | ')

Write-Host ''
Write-Host '--- v(ADP3 T3f) INTERACTION: a carried-through residual line -------------------'

# Verbatim means verbatim: the interior text must be untouched AND the line
# must carry the member's indent exactly once. The single -ccontains below
# fails on BOTH failure modes (a column-0 line and a double-indented one), and
# the count check rules out the carry-through emitting it twice.
$blk = $res['ResidualMember'].Block
Check 'RESIDUAL ResidualMember : the unmodeled <value> line is carried through at the member indent, verbatim' `
  ($blk -ccontains '    /// <value>Hand-written value tag; unmodeled, must survive verbatim.</value>') ($blk -join ' | ')
Check 'RESIDUAL ResidualMember : it is NOT double-indented (no 8-space copy)' `
  (-not ($blk -ccontains '        /// <value>Hand-written value tag; unmodeled, must survive verbatim.</value>')) ($blk -join ' | ')
Check 'RESIDUAL ResidualMember : it appears EXACTLY once' `
  ((@($blk | Where-Object { $_ -match [regex]::Escape('<value>Hand-written value tag') })).Count -eq 1) ($blk -join ' | ')
Check 'RESIDUAL ResidualMember : the real <summary> is there too, at the member indent' `
  ($blk -ccontains '    /// <summary>Carries an unmodeled tag beside a real summary.</summary>') ($blk -join ' | ')

Write-Host ''
Write-Host '--- GAPPED: the DECLARATION s indentation governs, not the comment s own -------'

# The fixture writes this comment at SIX spaces above a FOUR-space declaration,
# so "unchanged" and "declaration-anchored" give different answers and the
# assertion below can only pass for one of them.
$blk = $res['GappedMember'].Block
Check 'GAPPED GappedMember : re-indented to the declaration s four spaces (not left at the comment s six)' `
  ((@($blk | Where-Object { (Get-Indent $_) -cne '    ' })).Count -eq 0) `
  (($blk | ForEach-Object { '[' + (Show-Ws (Get-Indent $_)) + ']' + $_.Trim() }) -join ' | ')
Check 'GAPPED GappedMember : the blank line between comment and declaration survives' `
  (($res['GappedMember'].Target | ForEach-Object { [IO.File]::ReadAllText($_) }) -cmatch '(?m)^\r?\n    procedure GappedMember;') ''

Write-Host ''
Write-Host '--- FRESH: the fresh-insert branch indents too ---------------------------------'

$blk = $res['FreshMember'].Block
Check 'FRESH FreshMember : a facts block was genuinely written' `
  (($blk -join "`n") -match '(?s)<!-- drag-lint:auto BEGIN -->.*Called from:.*indent\.CallsMembers') ($blk -join ' | ')
Check 'FRESH FreshMember : every line of the NEW block sits at the member s four spaces' `
  ((@($blk | Where-Object { (Get-Indent $_) -cne '    ' })).Count -eq 0) `
  (($blk | ForEach-Object { '[' + (Show-Ws (Get-Indent $_)) + ']' }) -join ' ')

Write-Host ''
Write-Host '--- BRANCH PINS + FIXED POINT --------------------------------------------------'

foreach ($nm in $shapes.Keys) {
  $r = $res[$nm]
  Check "$nm cycle-1 action is pinned ($($shapes[$nm].Act))" `
    ($r.Actions[0] -match ('^' + [regex]::Escape($shapes[$nm].Act) + '/')) ("actual=" + $r.Actions[0])
  Check "$nm reaches a FIXED POINT from cycle 1 (c1 == c2 == c3)" `
    (($r.Md5s[1] -eq $r.Md5s[2]) -and ($r.Md5s[2] -eq $r.Md5s[3])) ("md5=" + ($r.Md5s -join ' '))
  Check "$nm cycle-2 apply makes NO edit (the binding criterion: a 2nd apply is a zero-byte diff)" `
    ($r.Actions[1] -match '/0$') ($r.Actions -join ' ')
  Check "$nm cycle-3 apply makes NO edit" ($r.Actions[2] -match '/0$') ($r.Actions -join ' ')
  Check "$nm a real facts block with Called from: was written" `
    (($r.Block -join "`n") -match '(?s)<!-- drag-lint:auto BEGIN -->.*Called from:') ($r.Block -join ' | ')
}

Write-Host ''
Write-Host '--- OPTION (B): a block an EARLIER build flattened is deliberately re-indented --'

# DamagedMember's converged block is de-indented to column 0 here, in place --
# exactly the state a pre-fix `--apply` left every class member in, YADF's
# included. Under option (A) (indent-on-write only) the repair branch's
# CommentLinesEqual guard is indentation-blind, so this reports unchanged/0 and
# the damage is permanent. Option (B) emits the replace anyway.
$dr        = $res['DamagedMember']
$goodBlock = $dr.Block
$all       = [IO.File]::ReadAllLines($dr.Target)
$declIx    = -1
for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -cmatch $shapes['DamagedMember'].Decl) { $declIx = $i; break } }
Check 'DAMAGE SETUP: the DamagedMember declaration was located for the de-indent' ($declIx -ge 0) "declIx=$declIx"
$flattened = 0
for ($i = $declIx - 1; $i -ge 0; $i--) {
  if ($all[$i] -notmatch '^\s*///') { break }
  $all[$i] = $all[$i].TrimStart(); $flattened++
}
Check 'DAMAGE SETUP: the block was flattened to column 0 (simulating a pre-fix build)' `
  (($flattened -gt 0) -and ($flattened -eq @($goodBlock).Count)) "flattened=$flattened blockCount=$(@($goodBlock).Count)"
[IO.File]::WriteAllLines($dr.Target, $all, (New-Object Text.UTF8Encoding $false))

& $exePath index $dr.Scratch --db $dr.Db 2>$null | Out-Null
$j = (& $exePath document --qname $shapes['DamagedMember'].QName --db $dr.Db --apply --json 2>$null) -join ' '
Check 'DAMAGE REPAIR: the engine EMITS an edit for a body-identical but de-indented block' `
  ($j -match '"action":"extended"' -and $j -notmatch '"edits":0') $j
$after = Get-DocBlockLines ([IO.File]::ReadAllLines($dr.Target)) $shapes['DamagedMember'].Decl
Check 'DAMAGE REPAIR: the restored block is BYTE-IDENTICAL to the correctly-indented one' `
  ((($after -join "`n")) -ceq (($goodBlock -join "`n"))) `
  ("want=[" + ($goodBlock -join ' | ') + "] got=[" + ($after -join ' | ') + "]")

# ...and it still CONVERGES: the re-indent is a one-time rewrite, not a new
# non-idempotent shape. Without this, option (B) could "fix" the damage by
# rewriting the same block on every single run forever.
$md5AfterRepair = Get-FileMd5 $dr.Target
& $exePath index $dr.Scratch --db $dr.Db 2>$null | Out-Null
$j2 = (& $exePath document --qname $shapes['DamagedMember'].QName --db $dr.Db --apply --json 2>$null) -join ' '
Check 'DAMAGE CONVERGES: the very next apply makes NO edit' ($j2 -match '"edits":0') $j2
Check 'DAMAGE CONVERGES: ...and the file is byte-unchanged by it' `
  ((Get-FileMd5 $dr.Target) -eq $md5AfterRepair) "before=$md5AfterRepair after=$(Get-FileMd5 $dr.Target)"

Write-Host ''
Write-Host '--- STRIP ROUND-TRIP: an INDENTED engine block must still be strippable --------'

foreach ($nm in $shapes.Keys) {
  if ($nm -eq 'DamagedMember') { continue }   # its scratch was hand-edited above
  $r = $res[$nm]
  & $exePath index $r.Scratch --db $r.Db 2>$null | Out-Null
  & $exePath document --qname $shapes[$nm].QName --db $r.Db --strip --apply 2>$null | Out-Null
  $after = Get-DocBlockLines ([IO.File]::ReadAllLines($r.Target)) $shapes[$nm].Decl
  Check "STRIP $nm : no engine residue survives the strip (an indented block is still fully strippable)" `
    (-not (($after -join "`n") -match 'drag-lint:auto')) ($after -join ' | ')
  Check "STRIP $nm : no leftover <remarks> wrapper" `
    (-not (($after -join "`n") -match '<remarks>')) ($after -join ' | ')
  $res[$nm] | Add-Member -NotePropertyName Stripped -NotePropertyValue $after
}

# FreshMember had no comment at all, so its whole block is engine-owned and
# strip must remove it entirely -- there is no "pristine" to come back to.
Check 'STRIP FreshMember : the entire engine-written block is gone (nothing was left behind)' `
  ((Get-Lines $res['FreshMember'].Stripped).Count -eq 0) (($res['FreshMember'].Stripped) -join ' | ')

# The four shapes whose pristine indentation is ALREADY correct and whose
# pristine tag order already matches the emitter's own fixed order round-trip
# BYTE-IDENTICALLY -- which is the strongest available statement that the
# indentation the engine wrote is the indentation the author had.
# ResidualMember is excluded (the emitter re-orders <value> after <summary>)
# and GappedMember is excluded deliberately: its pristine comment sat at SIX
# spaces above a FOUR-space declaration, the engine re-indented it to four, and
# `--strip` is marker-keyed -- it cannot and must not undo a change nothing
# marked. That is pinned as its own assertion just below.
foreach ($nm in @('UnitLevelControl','TwoSpaceMember','DeepMember','TabMember')) {
  Check "STRIP $nm : the stripped block is BYTE-IDENTICAL to pristine (indentation included)" `
    ((($res[$nm].Stripped -join "`n")) -ceq (($pristine[$nm] -join "`n"))) `
    ("pristine=[" + ($pristine[$nm] -join ' | ') + "] after=[" + ($res[$nm].Stripped -join ' | ') + "]")
}
Check 'STRIP ResidualMember : the author s unmodeled <value> line comes back, at the member indent' `
  ($res['ResidualMember'].Stripped -ccontains '    /// <value>Hand-written value tag; unmodeled, must survive verbatim.</value>') `
  ($res['ResidualMember'].Stripped -join ' | ')
Check 'STRIP GappedMember : PINNED -- strip does NOT restore the pristine six-space indent (marker-keyed strip cannot undo a re-indent)' `
  ((@($res['GappedMember'].Stripped | Where-Object { (Get-Indent $_) -cne '    ' })).Count -eq 0) `
  (($res['GappedMember'].Stripped | ForEach-Object { '[' + (Show-Ws (Get-Indent $_)) + ']' }) -join ' ')

Write-Host ''
foreach ($nm in $shapes.Keys) {
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
