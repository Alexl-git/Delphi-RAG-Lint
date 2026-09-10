<#
  run_dfm_prop_all_value_kinds.ps1 -- PLAN A T4/T10, spec 8.1 gap 1.

  WHAT WAS MISSING. WalkProperty emitted a dfm-prop literal ONLY when the value
  node was a `string`. Every other value kind -- integers, booleans, clXxx colour
  identifiers, sets like [akLeft, akTop] -- was indexed nowhere, so
  `query --text clBtnFace --source dfm` returned NOTHING while
  `query --text Hello --source dfm` found the Caption beside it. That reads as
  "the text index is broken", not as "this value kind was never emitted", which
  is why it went unnoticed.

  NODE TYPES ARE MEASURED, NOT GUESSED. The plan listed them as UNMEASURED and
  they had to be dumped -- and dumping them needed a new tool, because
  TAstParseCache dispatches on the DELPHI grammar and hands a .dfm to the wrong
  parser (tools\dumpnode reports `no "property" node` for a file that is nothing
  but properties). tools\dumpdfm parses with tree_sitter_dfm directly. Measured
  2026-09-09:

    Left = 8              -> number       (child: integer)
    Font.Height = -11     -> number
    Visible = False       -> boolean      (child: false)
    Color = clBtnFace     -> identifier_value
    Anchors = [akLeft..]  -> set
    Caption = 'Hello'     -> string       (the only kind emitted before)
    Picture.Data = {..}   -> binary_blob

  binary_blob IS ITS OWN NODE TYPE. That is what makes the blob skip exact
  rather than a size heuristic, and it is the single most important measured
  fact here: without it every glyph and embedded image in the corpus would land
  in string_literals and the FTS index would be tokenising pages of hex.

  CASES
    positive  a number, a boolean, a colour identifier and a set are each
              findable by `query --text ... --source dfm`.
    control   the string value that ALREADY worked still works -- this change
              must not trade one value kind for another.
    negative  the binary blob's hex is NOT findable. Asserted with a distinctive
              token that appears ONLY inside the blob, so a hit could not have
              come from anywhere else.
    cap       a very long set value is TRUNCATED, not dropped: its opening
              tokens are still findable. A dropped row and a capped row look
              identical if you only assert the tail is absent, so the head is
              asserted present.

  MEASURED RED, THEN GREEN -- pre-change engine
  (scratchpad\engine-preA, extractor 1.14.0-alpha,
   sha256 C47510745578EB3C4F501EBEB3BCD832E8B3F9A1F3357F0FF8B28EF847B12C34):
  every positive case returns 0 rows; the string control passes; the blob
  negative passes vacuously (nothing is emitted at all). See the T6 block below.

  VERBATIM RED, captured 2026-09-09 22:49 against that engine:

    engine: extractor=1.14.0-alpha exe=C:\TEMP\claude\c--Projects-Delphi-RAG-lint\46ac75c6-8655-4a1c-9ca4-6ea10187bdad\scratchpad\engine-preA\drag-lint.exe
      [PASS] index exits 0 exit=0
      [FAIL] number      'Left = 8' is findable by its value rows=0
      [FAIL] boolean     'False' is findable rows=0
      [FAIL] identifier  'clZzTestColor' is findable rows=0
      [FAIL] set         'akZzLeft' is findable rows=0
      [PASS] string      'ZzCaptionText' is still findable rows=1
      [PASS] binary_blob hex is NOT in the text index rows=0 (a hit means every glyph in the corpus is being tokenised)
      [FAIL] the HEAD of a long set is still findable (truncated, not dropped) rows=0
      [PASS] the TAIL past the 256-char cap is absent rows=0
    FAIL

#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dfm-value-kinds"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$info = (& $Exe info --json 2>$null) -join "`n" | ConvertFrom-Json
Write-Host ("engine: extractor={0} exe={1}" -f $info.extractor_version, $Exe) -ForegroundColor Cyan

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$work = Join-Path $WorkDir 'fixture'

# A long set, to exercise the 256-char cap. The FIRST element is distinctive and
# well inside the cap; the LAST is distinctive and well past it.
$longSet = (1..80 | ForEach-Object { "akZzMember$_" }) -join ', '

Write-Ascii (Join-Path $work 'uForm.pas') @'
unit uForm;

interface

type
  TForm1 = class(TObject)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'uForm.dfm') @"
object Form1: TForm1
  Left = 8
  Visible = False
  Color = clZzTestColor
  Anchors = [akZzLeft, akZzTop]
  Caption = 'ZzCaptionText'
  Picture.Data = {0954506E67ZZBLOBTOKEN496D616765}
  LongSet = [$longSet]
end
"@

$db = Join-Path $WorkDir 'dfm.sqlite'
$null = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Count-Text([string]$Phrase) {
  $raw = (& $Exe query --text $Phrase --source dfm --db $db --json 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($raw)) { return 0 }
  try { return @($raw | ConvertFrom-Json).Count } catch { return 0 }
}

Write-Host ''
Write-Host 'POSITIVE: every non-string value kind is searchable' -ForegroundColor Cyan
Check "number      'Left = 8' is findable by its value"     ((Count-Text '8')              -ge 1) "rows=$(Count-Text '8')"
Check "boolean     'False' is findable"                     ((Count-Text 'False')          -ge 1) "rows=$(Count-Text 'False')"
Check "identifier  'clZzTestColor' is findable"             ((Count-Text 'clZzTestColor')  -ge 1) "rows=$(Count-Text 'clZzTestColor')"
Check "set         'akZzLeft' is findable"                  ((Count-Text 'akZzLeft')       -ge 1) "rows=$(Count-Text 'akZzLeft')"

Write-Host ''
Write-Host 'CONTROL: the string value that already worked still does' -ForegroundColor Cyan
Check "string      'ZzCaptionText' is still findable" ((Count-Text 'ZzCaptionText') -ge 1) "rows=$(Count-Text 'ZzCaptionText')"

Write-Host ''
Write-Host 'NEGATIVE: a binary blob is NOT indexed' -ForegroundColor Cyan
$blob = Count-Text 'ZZBLOBTOKEN'
Check "binary_blob hex is NOT in the text index" ($blob -eq 0) "rows=$blob (a hit means every glyph in the corpus is being tokenised)"

Write-Host ''
Write-Host 'CAP: a very long value is truncated, not dropped' -ForegroundColor Cyan
$head = Count-Text 'akZzMember1'
$tail = Count-Text 'akZzMember80'
Check "the HEAD of a long set is still findable (truncated, not dropped)" ($head -ge 1) "rows=$head"
Check "the TAIL past the 256-char cap is absent" ($tail -eq 0) "rows=$tail"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
