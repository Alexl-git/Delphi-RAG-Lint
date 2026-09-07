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

Write-Host ''
Write-Host '=== a managed <para> never contains a <seealso> ===' -ForegroundColor Cyan

$root = (Resolve-Path $Root).Path
$files = Get-ChildItem -Path $root -Recurse -Filter *.pas -File
Check 'found .pas files to scan (guard is not vacuous)' ($files.Count -gt 0) "$($files.Count) file(s)"

$violations = @()
foreach ($f in $files) {
  $violations += Get-Violations ([IO.File]::ReadAllLines($f.FullName)) $f.FullName
}
Check 'no <seealso> is swallowed inside a <para>' ($violations.Count -eq 0) `
  ($(if ($violations.Count) { "`n        " + ($violations -join "`n        ") } else { '' }))

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

if($script:Failed){ Write-Host 'PARA/SEEALSO CONTAINMENT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PARA/SEEALSO CONTAINMENT: PASS' -ForegroundColor Green; exit 0 }
