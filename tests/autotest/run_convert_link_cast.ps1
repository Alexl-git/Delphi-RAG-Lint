<#
  run_convert_link_cast.ps1 -- a `: CastName` suffix on a #link must be SPLIT OFF
  the FromPath, not swallowed into it.

  THE DEFECT (docs\INBOX-URGENT-engine-never-reads-castlib.md, raised by the
  converter side 2026-09-04, measured against drag-lint 1.9.0-alpha).
  `#link To <- From : CastName` is the DSL's documented cast syntax. The engine's
  rule parser had no cast field, so `Size : Round` became the literal FromPath,
  which resolves against nothing -- and validation reported the user's VALID line
  as a missing path:

      line 6: link FromPath not found in --from tree: Size : Round

  It fired on `convrules\sample.rules`, a file this repo SHIPS.

  Spec item G6.3 had recorded this as "the engine never reads .castlib", which
  UNDERSTATED it: the engine did not ignore the cast, it corrupted the path and
  then blamed the user's file.

  AND THE PRINTER HID IT. `--print-parsed` echoed `link Size <- Size : Round`,
  which reads exactly like a captured cast. It was echoing the corruption. That
  is why case 2 below asserts the cast is shown as a SEPARATE LABELLED field --
  a reader must be able to tell "captured" from "swallowed", or this defect can
  survive a review of the very output meant to reveal it.

  THE PREDICATE IS THE EDITOR'S. ConvRules.Model.pas already parsed and re-emitted
  this suffix correctly, and the editor ROUND-TRIPS rule books, so two different
  notions of "is this a cast" would mean silent DATA LOSS on save. Cases 4 and 5
  pin the editor's exact rule: split on the LAST colon, accept the tail only if it
  is a bare identifier (no space, no dot, no '<').

  CASES
    1. the SHIPPED sample no longer reports a false error on its cast line
    2. --print-parsed shows FromPath and Cast as SEPARATE fields
    3. CONTROL: a genuinely missing FromPath IS still reported (validator alive)
    4. CONTROL: a tail with a DOT is not a cast -- path left intact
    5. CONTROL: a tail with a SPACE is not a cast -- path left intact
    6. CONTROL: a link with no colon at all is unchanged

  RED-CHECK (run 2026-09-04): with the SplitCastSuffix call removed from the
  #link branch, cases 1 and 2 FAIL and 3, 4, 5, 6 PASS.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

$repo   = (Resolve-Path "$PSScriptRoot\..\..").Path
$sample = Join-Path $repo 'convrules\sample.rules'
$libDb  = 'C:\Projects\.drag-lint\library-Win64.sqlite'

# ---------------------------------------------------------------------------
# 1 + 2. THE SHIPPED SAMPLE. Deliberately the real file, not a copy: the note's
#        whole point is that the defect fires on what we ship, and a private
#        fixture would let sample.rules drift back into the broken shape unseen.
# ---------------------------------------------------------------------------
Check 'the shipped sample still carries the cast line this pins' `
  ((Get-Content $sample -Raw) -match '#link\s+Size\s+<-\s+Size\s*:\s*Round') `
  "if sample.rules changed, re-point this guard rather than deleting it"

if (Test-Path $libDb) {
  $val = (& $Exe convert-validate --rules $sample --from Vcl.Graphics.TFont --to Vcl.Graphics.TFont --db $libDb 2>&1) -join "`n"
  # Scoped to the CAST LINE. The same run reports line 15/16 errors, which are an
  # artifact of passing one --from/--to pair against a two-block rule book and are
  # NOT this defect -- asserting "no errors at all" would fail against correct code.
  Check '1. no false "FromPath not found" on the cast line (line 6)' `
    ($val -notmatch 'line 6: link FromPath not found') `
    "got: $(($val -split "`n" | Where-Object { $_ -match 'line 6' }) -join ' | ')"
  Check '1b. and the corrupted path text appears nowhere in the output' `
    ($val -notmatch 'Size\s*:\s*Round') 'the swallowed form must be gone entirely'
} else {
  Write-Host "  [SKIP] library db not present at $libDb -- cases 1/1b need it" -ForegroundColor Yellow
}

$parsed = (& $Exe convert-validate --rules $sample --print-parsed 2>&1) -join "`n"
$line6  = ($parsed -split "`n" | Where-Object { $_ -match '^line 6:' }) -join ''
Check '2. --print-parsed shows Cast as a SEPARATE labelled field' `
  (($line6 -match '\[cast\s+Round\]') -and ($line6 -notmatch 'Size\s*:\s*Round')) `
  "got: '$line6'  -- re-joining it onto FromPath is exactly how the printer hid this bug"

# ---------------------------------------------------------------------------
# 3-6. CONTROLS, on a temp rule book. Without these, cases 1/2 also pass if the
#      parser started dropping every colon it sees, or stopped validating at all.
# ---------------------------------------------------------------------------
$WorkDir = Join-Path $env:TEMP ("convcast_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$rules = Join-Path $WorkDir 'cast.rules'
[System.IO.File]::WriteAllText($rules, ((@'
#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont
#link Height <- NoSuchProperty
#link Name <- Inner.Shade : A.B
#link Color <- Color : Not An Ident
#link Pitch <- Pitch
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))

$p2 = (& $Exe convert-validate --rules $rules --print-parsed 2>&1) -join "`n"
function ParsedLine($n) { return (($p2 -split "`n" | Where-Object { $_ -match "^line ${n}:" }) -join '') }

if (Test-Path $libDb) {
  $v2 = (& $Exe convert-validate --rules $rules --from Vcl.Graphics.TFont --to Vcl.Graphics.TFont --db $libDb 2>&1) -join "`n"
  Check '3. CONTROL: a genuinely missing FromPath IS still reported' `
    ($v2 -match 'line 2: link FromPath not found') `
    'if this went silent the validator is dead and cases 1/1b prove nothing'
}

$l3 = ParsedLine 3
Check '4. CONTROL: a tail containing a DOT is not a cast' `
  (($l3 -match 'Inner\.Shade\s*:\s*A\.B') -and ($l3 -notmatch '\[cast')) "got: '$l3'"

$l4 = ParsedLine 4
Check '5. CONTROL: a tail containing a SPACE is not a cast' `
  (($l4 -match 'Color\s*:\s*Not An Ident') -and ($l4 -notmatch '\[cast')) "got: '$l4'"

$l5 = ParsedLine 5
Check '6. CONTROL: a link with no colon is untouched' `
  (($l5 -match 'link Pitch <- Pitch') -and ($l5 -notmatch '\[cast')) "got: '$l5'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
