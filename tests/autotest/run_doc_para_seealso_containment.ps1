<#
  run_doc_para_seealso_containment.ps1 -- session 74.

  A managed <para> must never contain a <seealso> tag. The two are SIBLINGS
  inside the AUTO_BEGIN..AUTO_END fence; a <seealso> appearing between <para>
  and </para> means the fact-line content parse ran past the end of the fact and
  swallowed the tags below it.

  THE DEFECT. Reproduced on real source by the 91-file sweep (b42a7e7):
  DRagLint.Index.IgnoreFiles.pas came back with

      <para>Used in units: X, X <seealso .../> <seealso .../> ...</para>

  -- five sibling <seealso> tags pulled inside the para, AND the unit name
  duplicated, because the swallowed blob was then re-parsed as an existing list
  member. It ACCUMULATES: a second apply appends the whole set again, five
  becoming ten, with no fixed point.

  WHY A TREE-WIDE SCAN AND NOT ONLY A FIXTURE. This survived a sweep whose
  verification was a word-multiset metric over the AUTHORED core -- which
  deliberately excludes <para> and <seealso> as engine-owned, and so was blind to
  it by construction. The engine's own output needs a check that looks AT the
  engine's own output. A fixture pins the mechanism; this pins the tree.

  IT IS ALSO A REGRESSION, NOT A NEW BUG. DRagLint.Doc.SharedFacts.LabelContent
  already carries the fix ("STOP AT THE NEXT TAG AS WELL AS THE NEXT LABEL"),
  but only on the dl:shared carry-over path. IgnoreFiles.pas is not a dl:shared
  unit, so the ordinary path rendered it -- and that path has no equivalent
  clause. See INBOX-autodoc-para-swallows-the-seealso-tags-below-it.md.

  SCOPED TO /// LINES DELIBERATELY. DRagLint.Doc.SharedFacts.pas contains a
  brace comment that QUOTES the broken shape verbatim while explaining the fix.
  A naive text scan flags it and the guard becomes a liar about its own repo --
  the exact "a text scan cannot read comments" failure this project has hit
  repeatedly. Only DocInsight lines carry generated output, so only they are
  checked.

  Runs from anywhere, pwsh 7.
#>
[CmdletBinding()]
param([string]$Root = "$PSScriptRoot\..\..\src")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

# A DocInsight line whose <para> is still open when a <seealso> starts.
# Anchored on '///' so brace comments and string literals describing the shape
# are out of scope by construction, not by an exclusion list that would rot.
function Get-Violations([string[]]$lines, [string]$file) {
  $out = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l.TrimStart() -notmatch '^///') { continue }
    if ($l -notmatch '<para>')           { continue }
    $p = $l.IndexOf('<para>')
    $close = $l.IndexOf('</para>', $p)
    $see = $l.IndexOf('<seealso', $p)
    if ($see -lt 0) { continue }
    if ($close -lt 0 -or $see -lt $close) {
      $out += ("{0}:{1}" -f $file, ($i + 1))
    }
  }
  return ,$out
}

# SHAPE 2 (session 76) -- a fact line that could only have come from a human's
# prose. A generated inbound entry is a qualified name and an optional
# '(file.pas)'; it can never contain a backtick, and it can never contain a
# marker comment. Both mean the fact parse ran outside the fence and merged the
# human's words in as entries -- which reaches a FIXED POINT on the first apply
# and so never heals on its own.
#
# SCOPED TO THE FENCE, not to '///'. That is a stronger boundary than shape 1's
# and it is required here: DRagLint.Doc.SharedFacts.pas quotes this very shape
# on a '///'-prefixed line INSIDE a brace comment while explaining the fix
# (search 'YadfMain'), so a '///'-anchored scan flags the explanation and the
# guard becomes a liar about its own repo. Only text between AUTO_BEGIN and
# AUTO_END is engine-owned, and the quoted example is not inside a real fence.
function Get-FenceViolations([string[]]$lines, [string]$file) {
  $out = @(); $inFence = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match '///.*drag-lint:auto BEGIN') { $inFence = $true; continue }

    # A line that is BOTH a fact and a terminator is the YADF shape -- the END
    # marker swallowed into the fact's own content -- so it must be judged
    # BEFORE it is allowed to close the fence, or the worst case is the one case
    # that escapes. (Caught by this guard's own positive control.)
    #
    # It must still be inside an OPENED fence to count. The brace comment at
    # DRagLint.Doc.SharedFacts.pas:1031 quotes exactly this shape, END marker
    # and all, with no BEGIN above it -- judging a stray END line on its own
    # flags that explanation and the guard starts lying about its own repo.
    $isEnd = $l -match '///.*drag-lint:auto END'
    $hit = $false
    if ($inFence -and ($l.TrimStart() -match '^///')) {
      $text = ($l -replace '^\s*///\s*', '') -replace '^<para>', ''
      if ($text -match '^(Called from|Used by|Used in units):') {
        if ($text -match '[`]' -or $text -match '<!--') { $hit = $true }
      }
    }
    if ($hit) { $out += ("{0}:{1}" -f $file, ($i + 1)) }
    if ($isEnd) { $inFence = $false }
  }
  return , $out
}

Write-Host ''
Write-Host '=== a managed <para> never contains a <seealso> ===' -ForegroundColor Cyan

$root = (Resolve-Path $Root).Path
$files = Get-ChildItem -Path $root -Recurse -Filter *.pas -File
Check 'found .pas files to scan (guard is not vacuous)' ($files.Count -gt 0) "$($files.Count) file(s)"

$violations = @()
$fenceViolations = @()
foreach ($f in $files) {
  $lines = [IO.File]::ReadAllLines($f.FullName)
  $violations      += Get-Violations      $lines $f.FullName
  $fenceViolations += Get-FenceViolations $lines $f.FullName
}
Check 'no <seealso> is swallowed inside a <para>' ($violations.Count -eq 0) `
  ($(if ($violations.Count) { "`n        " + ($violations -join "`n        ") } else { '' }))
Check 'no fact line inside a fence carries a backtick or a marker' ($fenceViolations.Count -eq 0) `
  ($(if ($fenceViolations.Count) { "`n        " + ($fenceViolations -join "`n        ") } else { '' }))

# --- POSITIVE CONTROL -------------------------------------------------------
# The scan must be able to SEE the shape, or "0 violations" means nothing. Both
# arms matter: the broken line is caught, and the well-formed sibling layout
# (para closed, seealso on its own line) is NOT caught.
$bad = @(
  '  /// <para>Used in units: X, X <seealso cref="A"/> <seealso cref="B"/></para>'
)
$good = @(
  '  /// <para>Used in units: X</para>',
  '  /// <seealso cref="A"/>',
  '  /// <seealso cref="B"/>',
  '  { <para>Covered by: X <seealso/></para> -- a comment DESCRIBING the bug }'
)
Check 'POSITIVE CONTROL: the swallowed shape IS detected' `
  ((Get-Violations $bad 'synthetic').Count -eq 1)
Check 'POSITIVE CONTROL: correct sibling layout and a brace comment are NOT flagged' `
  ((Get-Violations $good 'synthetic').Count -eq 0)

# Shape 2 needs its own controls: the scan must SEE a junk fact line, must not
# flag the same text outside a fence, and must not flag a clean fact line.
$badFence = @(
  '  /// <!-- drag-lint:auto BEGIN -->',
  '  /// Used by: `',
  '  /// <para>Called from: A.B.Foo (A.B.pas), `</para>',
  '  /// Used in units: X <!-- drag-lint:auto END -->',
  '  /// <!-- drag-lint:auto END -->'
)
$goodFence = @(
  '  /// <!-- drag-lint:auto BEGIN -->',
  '  /// <para>Called from: A.B.Foo (A.B.pas)</para>',
  '  /// <para>Used in units: A.B</para>',
  '  /// <!-- drag-lint:auto END -->',
  '  /// <para>Prose that mentions `Used by:` AFTER the fence is the human''s.</para>',
  '      /// Used by: ` -- quoted inside a brace comment, no fence around it'
)
Check 'POSITIVE CONTROL: a junk fact line inside a fence IS detected' `
  ((Get-FenceViolations $badFence 'synthetic').Count -eq 3) `
  ("got " + (Get-FenceViolations $badFence 'synthetic').Count + ' of 3')
Check 'POSITIVE CONTROL: clean facts, and label text OUTSIDE a fence, are NOT flagged' `
  ((Get-FenceViolations $goodFence 'synthetic').Count -eq 0)

if($script:Failed){ Write-Host 'PARA/SEEALSO CONTAINMENT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PARA/SEEALSO CONTAINMENT: PASS' -ForegroundColor Green; exit 0 }
