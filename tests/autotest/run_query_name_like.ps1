<#
  run_query_name_like.ps1 -- `query --name-like` must do the thing `--name`
  cannot, and must not change what `--name` does.

  WHY THIS EXISTS
  ---------------
  Every other drag-lint query assumes you already know the identifier. This is
  the one that gets you TO it: "does this install have anything that rasterises
  an SVG?", asked by someone who does not yet know the answer is TSkSvgBrush.
  Before it existed, `query --name SVG` returned two rows both literally NAMED
  `SVG`, and the real answer was found by guessing candidate names one at a
  time. The fallback was grep over the RTL and DevExpress trees -- exactly what
  the index exists to prevent.

  THE TWO CHECKS THAT CARRY THE WHOLE FILE
  ----------------------------------------
  Check 2 asserts a mid-name substring matches. Check 3 asserts the SAME term
  through `--name` does NOT. Neither is worth anything alone:

    * without check 3, check 2 would still pass if `--name-like` had been
      implemented by quietly widening `--name` -- which would silently change
      what every existing caller gets back, the IDE plugin included;
    * without check 2, check 3 is satisfied by a flag that returns nothing.

  Together they pin the actual contract: a NEW capability beside an UNCHANGED
  one.

  ORDERING IS A FEATURE, NOT A DETAIL
  -----------------------------------
  Shortest name first is the whole reason the output is usable: for a discovery
  question TSkSvg is a far better first row than
  TdxSVGImageCollectionHelperInternal. Check 5 pins it, because an ORDER BY is
  exactly the kind of thing a later refactor drops without any test noticing.

  IT RUNS AGAINST THE SELF-INDEX, AND THAT IS A REAL BOUND
  --------------------------------------------------------
  The symbols asserted here are drag-lint's own (TSQLiteSymbolStore), so the
  runner is independent of which library indexes happen to exist on the machine.
  The cost is that it cannot prove the trigram path is FAST -- that was measured
  by hand on library-Win32.sqlite (3.3 GB): 18,923 ms for a bare LIKE scan
  versus 12 ms driven from symbol_trigrams. Stated here rather than left
  implicit, because a future reader will reasonably ask where the perf claim in
  FindByNameLike's comment is verified, and the answer is "not here".

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_query_name_like.ps1
#>
[CmdletBinding()]
param(
  [string] $Exe    = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string] $DbFile = "$PSScriptRoot\..\..\src\cli\_D-RAG\drag-lint.sqlite"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== query --name-like: substring search over symbol names ==' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
if (-not (Test-Path -LiteralPath $DbFile)) { Write-Host "SKIP: no self-index at $DbFile" -ForegroundColor Yellow; exit 0 }
$DbFile = (Resolve-Path $DbFile).Path

$errFile = Join-Path ([IO.Path]::GetTempPath()) ("draglint-namelike-" + [Guid]::NewGuid().ToString('N') + ".txt")

# The engine prints "(loaded defaults from ...)" on STDERR. The two streams are
# captured separately on purpose: merging them under $ErrorActionPreference =
# 'Stop' turns that banner into an ErrorRecord, which has already corrupted a
# JSON slice in this repo.
function Run([string[]]$A) {
  $out = & $Exe @A 2>$errFile
  $rc  = $LASTEXITCODE
  $err = if (Test-Path -LiteralPath $errFile) { (Get-Content -LiteralPath $errFile -Raw) } else { '' }
  if ($null -eq $err) { $err = '' }
  [pscustomobject]@{ Out = ($out -join "`n"); Err = $err; Code = $rc }
}

# ---------------------------------------------------------------------------
# CHECK 1 -- POSITIVE CONTROL
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 1: the happy path' -ForegroundColor Cyan

$r = Run @('query','--name-like','store','--kind','class','--db',$DbFile,'--limit','10')
Check 'a kind-filtered search exits 0' ($r.Code -eq 0) "exit $($r.Code) / $($r.Err.Trim())"
Check 'it finds our own TSQLiteSymbolStore' ($r.Out -match 'TSQLiteSymbolStore') ''
if ($r.Code -ne 0 -or $r.Out -notmatch 'TSQLiteSymbolStore') {
  Write-Host 'FATAL: positive control failed; every check below would be vacuous.' -ForegroundColor Red
  Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
  exit 1
}

# ---------------------------------------------------------------------------
# CHECK 2/3 -- the new capability, and the OLD contract left alone
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 2/3: a mid-name substring, and --name unchanged' -ForegroundColor Cyan

# 'qlitesymbol' sits in the MIDDLE of TSQLiteSymbolStore: not a prefix, not a
# suffix, and far too short to be reached by edit distance.
$mid = Run @('query','--name-like','qlitesymbol','--db',$DbFile,'--limit','10')
Check 'a mid-name substring matches' `
  (($mid.Code -eq 0) -and ($mid.Out -match 'TSQLiteSymbolStore')) "exit $($mid.Code)"

$viaName = Run @('query','--name','qlitesymbol','--db',$DbFile,'--limit','10')
Check 'the SAME term via --name does NOT match (its contract is intact)' `
  ($viaName.Out -notmatch 'TSQLiteSymbolStore') `
  'if this fails, --name was silently widened and every existing caller changed'

# ---------------------------------------------------------------------------
# CHECK 4 -- the kind filter narrows, and an empty result is not an error
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 4: --kind' -ForegroundColor Cyan

$wide   = Run @('query','--name-like','store','--db',$DbFile,'--limit','200')
$narrow = Run @('query','--name-like','store','--kind','class','--db',$DbFile,'--limit','200')
function MatchCount($t) { if ($t -match '(\d+) match\(es\)') { return [int]$Matches[1] } return -1 }
$nWide   = MatchCount $wide.Out
$nNarrow = MatchCount $narrow.Out
Check 'both searches reported a count' (($nWide -ge 0) -and ($nNarrow -ge 0)) "wide=$nWide narrow=$nNarrow"
Check '--kind narrows the result set' ($nNarrow -lt $nWide) "wide=$nWide narrow=$nNarrow"
Check 'and narrowing is not emptying' ($nNarrow -gt 0) "narrow=$nNarrow"

# A filter that matches nothing is an ANSWER ("there are none"), not a failure.
$none = Run @('query','--name-like','store','--kind','interface,record','--db',$DbFile,'--limit','5')
Check 'a kind filter that matches nothing still exits 0' ($none.Code -eq 0) "exit $($none.Code)"

# ---------------------------------------------------------------------------
# CHECK 5 -- shortest name first
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 5: ordering' -ForegroundColor Cyan

$ord = Run @('query','--name-like','store','--kind','class,type','--db',$DbFile,'--limit','20')
# The text grid is "kind  name  qualified_name", whitespace-separated.
$names = @($ord.Out -split "`n" |
  Where-Object { $_ -match '^\s*\S+\s+(\S+)\s+\S' } |
  ForEach-Object { ($_ -split '\s+' | Where-Object { $_ })[1] } |
  Where-Object { $_ -notmatch '^-+$' -and $_ -ne 'name' })
Check 'the ordering check parsed some names' ($names.Count -ge 2) "parsed $($names.Count)"
if ($names.Count -ge 2) {
  $lens = @($names | ForEach-Object { $_.Length })
  $sorted = $true
  for ($i = 1; $i -lt $lens.Count; $i++) { if ($lens[$i] -lt $lens[$i-1]) { $sorted = $false } }
  Check 'names come back shortest-first' $sorted ("lengths: " + ($lens -join ','))
}

# ---------------------------------------------------------------------------
# CHECK 6 -- the cap announces itself, and only when it truncates
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 6: --limit' -ForegroundColor Cyan

$cap = Run @('query','--name-like','store','--db',$DbFile,'--limit','3')
Check '--limit caps the result set' ((MatchCount $cap.Out) -eq 3) "got $(MatchCount $cap.Out)"
Check 'and SAYS so -- a silent cap reads as the whole answer' ($cap.Out -match 'LIMIT REACHED') ''
# The other direction: it must not cry wolf when nothing was cut off.
$nocap = Run @('query','--name-like','qlitesymbol','--db',$DbFile,'--limit','50')
Check 'no cap notice when the result fits well inside --limit' ($nocap.Out -notmatch 'LIMIT REACHED') ''

# ---------------------------------------------------------------------------
# CHECK 7 -- JSON, and the short-term warning
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 7: --json and the <3 char bound' -ForegroundColor Cyan

$j = Run @('query','--name-like','qlitesymbol','--db',$DbFile,'--limit','5','--json')
$doc = $null
try { $doc = $j.Out | ConvertFrom-Json } catch { }
Check 'stdout is valid JSON (the banner is on stderr)' ($null -ne $doc) $j.Out
Check 'and it carries the match' (($null -ne $doc) -and (($doc | ConvertTo-Json -Depth 6) -match 'TSQLiteSymbolStore')) ''
# `exact` is a claim ABOUT THE NAME -- "this symbol IS what you asked for". It is
# false for a substring hit, and saying it would be exactly the mislabelling
# match_kind was added to prevent.
Check 'rows are labelled match_kind=substring, NOT exact' `
  (($null -ne $doc) -and (@($doc).Count -gt 0) -and (@($doc)[0].match_kind -eq 'substring')) `
  ("got: " + $(if ($null -ne $doc -and @($doc).Count) { @($doc)[0].match_kind } else { '<none>' }))

# Under three characters there is no trigram, so this degrades to a full scan.
# It must SAY so before the wait rather than appear to hang.
$short = Run @('query','--name-like','cx','--db',$DbFile,'--limit','2')
Check 'a term under 3 chars warns that it cannot use the trigram index' `
  ($short.Err -match 'shorter than 3 characters') $short.Err.Trim()
Check 'and it still answers rather than refusing' ($short.Code -eq 0) "exit $($short.Code)"

# ---------------------------------------------------------------------------
# CHECK 8 -- case insensitivity
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 8: case' -ForegroundColor Cyan

$lower = Run @('query','--name-like','qlitesymbol','--db',$DbFile,'--limit','20')
$upper = Run @('query','--name-like','QLITESYMBOL','--db',$DbFile,'--limit','20')
Check 'upper and lower case give the same result count' `
  ((MatchCount $lower.Out) -eq (MatchCount $upper.Out)) `
  ("lower=" + (MatchCount $lower.Out) + " upper=" + (MatchCount $upper.Out))
Check 'and that count is not zero (the comparison must not be vacuous)' `
  ((MatchCount $lower.Out) -gt 0) ''

Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Failed) { Write-Host 'QUERY NAME-LIKE GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'QUERY NAME-LIKE GUARD: PASS' -ForegroundColor Green
exit 0
