<#
  run_comment_corpus.ps1 -- M1b: comment prose is searchable via `query --text`.

  THE GAP IT CLOSES. From the DataCopy `marposs` grep-fallback audit
  (docs\INBOX-2026-09-02-grep-fallback-audit-datacopy-marposs.md):

      drag-lint query --text "Mahr program" --db DataCopy.sqlite

  wanted the four stale occurrences in uMicroniteFormat.pas and returned three
  unrelated STRING LITERALS. Every doc-comment and inline-comment occurrence was
  invisible, because no comment text was written at index time. Stale-doc defects
  live in exactly that text, so the one query you would reach for could not see
  them and the session fell back to grep.

  WHAT SHIPPED. Comment nodes are harvested into `string_literals` alongside
  literals, so the EXISTING string_literals_ai trigger mirrors them into both
  string_fts (unicode61) and string_fts_tri (trigram). No new table, no new
  trigger, and NO SCHEMA_VERSION bump -- comments are searchable by phrase,
  any-order and substring for free. `kind` separates them: 'doc' for ///,
  'comment' for // { } and (* *).

  IT IS AN EXTRACTOR CHANGE and rides the DRAGLINT_EXTRACTOR_VERSION bump with
  the lone-CR fix; both are rows of INBOX-extractor-change-bank.md.

  THE FOUR COMMENT FORMS ARE ASSERTED SEPARATELY, on purpose. They are lexically
  different and a harvest that handles `//` while silently dropping `(* *)` would
  pass a single combined check. Each phrase below appears in EXACTLY ONE place in
  the fixture, so a hit can only have come from the construct being tested.

  THE CONTROLS ARE THE POINT:
   * a string-literal phrase must STILL be found -- this change must not
     displace what `--text` already did;
   * `--kind literal` must NOT find a comment phrase, and `--kind comment` must
     not find a literal one. Without these, "comments are searchable" would pass
     equally against an engine that indexed every comment as kind 'literal',
     which would corrupt every existing --kind literal query;
   * a `{$...}` COMPILER DIRECTIVE must not be indexed. Probed with dumpnode:
     directives are not `comment` nodes, so this asserts the grammar boundary
     rather than a filter -- if the grammar ever reclassifies them, `--text`
     would fill with {$R *.dfm} noise and this goes red.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("cmtcorp_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$db = Join-Path $WorkDir 'corpus.sqlite'

# Each marker phrase occurs exactly ONCE, in exactly one construct.
$src = @(
  'unit CommentCorpus;',
  '{$R zebrafish_directive_marker.dfm}',
  '',
  'interface',
  '',
  'type',
  '  /// <summary>quokka doc marker for the corpus test</summary>',
  '  TCorpus = class',
  '    FValue: Integer;   // narwhal trailing marker',
  '    procedure Run;',
  '  end;',
  '',
  'implementation',
  '',
  'procedure TCorpus.Run;',
  'begin',
  '  // axolotl body slash marker',
  '  { pangolin brace block marker }',
  '  (* capybara paren star marker *)',
  '  WriteLn(''okapi literal marker'');',
  '  FValue := 1;',
  'end;',
  '',
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $WorkDir 'CommentCorpus.pas'), $src + "`r`n", [Text.Encoding]::ASCII)

# A DIRECTORY target against a fresh scratch DB is the LIBRARY-shaped scan and is
# correct here. The rule this repo enforces -- never `index <dir> --db <projectDb>`
# -- is about widening an existing PROJECT database, which this is not.
$idxOut = & $exePath index $WorkDir --db $db 2>&1
$idxExit = $LASTEXITCODE
Check 'the fixture indexed' ($idxExit -eq 0 -and (Test-Path $db)) "exit=$idxExit"
if (-not (Test-Path $db)) {
  Write-Host ($idxOut -join "`n") -ForegroundColor DarkGray
  Write-Host 'FAIL' -ForegroundColor Red; exit 1
}

# Returns the matches for a phrase as objects, honouring an optional --kind.
# Returns the kind of the first hit, or an empty string -- and NEVER indexes
# an empty array. Under $ErrorActionPreference = 'Stop', indexing an empty array
# THROWS and kills the runner mid-file, so a guard written that way reports
# nothing after its first failure. That is exactly what this guard did on its own
# RED run: one FAIL, then silence for every remaining assertion.
function KindOf($Hits) {
  if ($null -eq $Hits) { return '' }
  $a = @($Hits)
  if ($a.Count -lt 1) { return '' }
  return [string]$a[0].kind
}

function Find-Text([string]$Phrase, [string]$Kind = '') {
  $a = @('query', '--text', $Phrase, '--db', $db, '--json')
  if ($Kind -ne '') { $a += @('--kind', $Kind) }
  $raw = (& $exePath @a 2>$null) -join "`n"
  if (-not $raw.Trim()) { return @() }
  try { $d = $raw | ConvertFrom-Json } catch { return @() }
  return @($d | Where-Object { $null -ne $_ })
}

Write-Host ''
Write-Host 'Each comment FORM is searchable (four lexically different constructs)' -ForegroundColor Cyan
$slash = Find-Text 'axolotl body slash marker'
Check 'a // comment inside a routine BODY is found' ($slash.Count -ge 1) "hits=$($slash.Count)"
Check '  ...and is reported as kind comment' `
  ($slash.Count -ge 1 -and (KindOf $slash) -eq 'comment') "kind=$((KindOf $slash))"

$brace = Find-Text 'pangolin brace block marker'
Check 'a { } block comment is found' ($brace.Count -ge 1) "hits=$($brace.Count)"

$paren = Find-Text 'capybara paren star marker'
Check 'a (* *) comment is found' ($paren.Count -ge 1) "hits=$($paren.Count)"

$trail = Find-Text 'narwhal trailing marker'
Check 'a trailing // comment after a field declaration is found' ($trail.Count -ge 1) "hits=$($trail.Count)"

$doc = Find-Text 'quokka doc marker'
Check 'a /// doc comment is found' ($doc.Count -ge 1) "hits=$($doc.Count)"
Check '  ...and is reported as kind doc, NOT comment' `
  ($doc.Count -ge 1 -and (KindOf $doc) -eq 'doc') `
  "kind=$((KindOf $doc)) -- /// is already reachable via find --doc-contains, so it stays distinguishable here"

Write-Host ''
Write-Host 'REGRESSION CONTROL -- string literals still behave exactly as before' -ForegroundColor Cyan
$lit = Find-Text 'okapi literal marker'
Check 'a string literal is still found' ($lit.Count -ge 1) "hits=$($lit.Count)"
Check '  ...still as kind literal' `
  ($lit.Count -ge 1 -and (KindOf $lit) -eq 'literal') "kind=$((KindOf $lit))"

Write-Host ''
Write-Host 'THE --kind FILTER SEPARATES THEM (else kind is decorative)' -ForegroundColor Cyan
Check '--kind literal does NOT return a comment phrase' `
  ((Find-Text 'axolotl body slash marker' 'literal').Count -eq 0) `
  'if this fails, comments were indexed as literals and every existing --kind literal query is now wrong'
Check '--kind comment does NOT return a literal phrase' `
  ((Find-Text 'okapi literal marker' 'comment').Count -eq 0) ''
Check '--kind comment DOES return the comment phrase' `
  ((Find-Text 'axolotl body slash marker' 'comment').Count -ge 1) ''
Check '--kind literal still returns the literal phrase' `
  ((Find-Text 'okapi literal marker' 'literal').Count -ge 1) `
  '--kind literal is the documented way to get the pre-comment behaviour back'

Write-Host ''
Write-Host 'A COMPILER DIRECTIVE IS NOT PROSE' -ForegroundColor Cyan
Check '{$R ...} is NOT indexed as comment text' `
  ((Find-Text 'zebrafish_directive_marker').Count -eq 0) `
  'directives are not comment nodes in the grammar (probed with dumpnode); if they become so, --text fills with {$R} noise'

Write-Host ''
Write-Host 'Substring and any-order reach comment text too' -ForegroundColor Cyan
$sub = @()
$rawSub = (& $exePath query --text 'pangolin brace' --substring --db $db --json 2>$null) -join "`n"
if ($rawSub.Trim()) { try { $sub = @(($rawSub | ConvertFrom-Json) | Where-Object { $null -ne $_ }) } catch { $sub = @() } }
Check '--substring finds a fragment of a comment' ($sub.Count -ge 1) "hits=$($sub.Count)"

try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
