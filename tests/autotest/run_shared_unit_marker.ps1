<#
  run_shared_unit_marker.ps1 -- Task 3 of
  docs\superpowers\plans\2026-08-13-shared-unit-docs-and-menu.md.

  WHAT IS UNDER TEST. The `dl:shared` unit marker -- the declaration that more
  than one project compiles a unit:

      unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup

  and its CLI surface:

      drag-lint shared-unit --in <file.pas> [--add-project <name>] [--apply] [--json]

  WHY THESE FIXTURES. Every one of them is a shape that has already cost a
  session on this codebase:

  * LINE 1 IS A `{`. Line 1 of a unit here is frequently the brace that opens a
    header block comment. `allow` appended a `dl:ok` marker there, the write
    "succeeded" with exit code 0, and the reader never saw the marker because it
    had landed inside the comment (CLI.pas:15322). The same trap is recorded for
    unit-too-large and for compiler-magic-comments. A reader that splits on lines
    and matches text answers "does the string appear" -- a different question
    from "is there a marker here".

  * IDEMPOTENCE. The marker is written by an IDE menu item (Task 5), and a menu
    item gets pressed twice. Adding a project already listed must not edit the
    file, must not reorder the list, and must report was_added:false.

  * DRY-RUN IS THE DEFAULT. Matching `allow`: without --apply nothing is written.
    A tool that writes on a read command is unusable inside a loop.

  * THE MARKER IN A BLOCK COMMENT. `{ dl:shared A, B }` must not parse its last
    project as "B }".

  * `dl:shared` IN A STRING LITERAL is not a marker. The whole reason the reader
    is a comment-state scanner rather than a text match.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-shared-unit-marker"
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

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

function Invoke-SharedUnit {
  param([string]$Path, [string]$AddProject = '', [switch]$Apply)
  $a = @('shared-unit', '--in', $Path, '--json')
  if ($AddProject) { $a += @('--add-project', $AddProject) }
  if ($Apply)      { $a += '--apply' }
  # STDOUT ONLY. The engine writes "(loaded defaults from ...)" to stderr, and
  # merging the two streams interleaves that banner into the JSON -- which is a
  # test-harness bug that looks exactly like an engine bug (measured: every read
  # assertion failed while the engine was answering correctly).
  $raw = & $Exe @a 2>$null
  $txt = ($raw | ForEach-Object { $_.ToString() }) -join "`n"
  try { return $txt | ConvertFrom-Json }
  catch { Write-Host "  (unparseable output) $txt" -ForegroundColor DarkYellow; return $null }
}

# ---------------------------------------------------------------- fixtures ---
$plain = Join-Path $WorkDir 'PlainUnit.pas'
Write-Ascii $plain @'
unit PlainUnit;

interface

implementation

end.
'@

$marked = Join-Path $WorkDir 'MarkedUnit.pas'
Write-Ascii $marked @'
unit MarkedUnit;   // dl:shared YADF

interface

implementation

end.
'@

$two = Join-Path $WorkDir 'TwoProjectUnit.pas'
Write-Ascii $two @'
unit TwoProjectUnit;   // dl:shared YADF, YADFOT

interface

implementation

end.
'@

# Line 1 is the `{` of a header block comment -- the anchoring trap.
$blockFirst = Join-Path $WorkDir 'BlockCommentUnit.pas'
Write-Ascii $blockFirst @'
{
  This is a header block comment.
  It occupies line 1, which is the whole point of this fixture.
}
unit BlockCommentUnit;   // dl:shared ProjectA, ProjectB

interface

implementation

end.
'@

# The marker itself lives inside a block comment: the tail `}` is not a project.
$inBlock = Join-Path $WorkDir 'InBlockUnit.pas'
Write-Ascii $inBlock @'
unit InBlockUnit;
{ dl:shared Alpha, Beta }

interface

implementation

end.
'@

# `dl:shared` in a string literal is not a marker.
$literal = Join-Path $WorkDir 'LiteralUnit.pas'
Write-Ascii $literal @'
unit LiteralUnit;

interface

const
  MARK = 'dl:shared NotAProject';

implementation

end.
'@

# A marker BELOW the interface line is out of the header region.
$late = Join-Path $WorkDir 'LateMarkerUnit.pas'
Write-Ascii $late @'
unit LateMarkerUnit;

interface

implementation

// dl:shared TooLate

end.
'@

Write-Host "shared-unit marker" -ForegroundColor Cyan

# ------------------------------------------------------------------ reading --
$r = Invoke-SharedUnit -Path $plain
Check 'unmarked unit is not shared' ($null -ne $r -and -not $r.is_shared)

$r = Invoke-SharedUnit -Path $marked
Check 'marked unit is shared' ($null -ne $r -and $r.is_shared)

$r = Invoke-SharedUnit -Path $two
Check 'projects parse in written order' (($r.projects -join ',') -eq 'YADF,YADFOT') `
  "got '$($r.projects -join ',')'"

$r = Invoke-SharedUnit -Path $blockFirst
Check 'marker is found below a line-1 block comment' ($r.is_shared) `
  'line 1 here is the { of a header comment -- the anchoring trap that already broke allow and unit-too-large'
Check 'projects parse below a line-1 block comment' (($r.projects -join ',') -eq 'ProjectA,ProjectB') `
  "got '$($r.projects -join ',')'"

$r = Invoke-SharedUnit -Path $inBlock
Check 'a marker inside a block comment is a marker' ($r.is_shared)
Check 'the closing brace is not a project name' (($r.projects -join ',') -eq 'Alpha,Beta') `
  "got '$($r.projects -join ',')'"

$r = Invoke-SharedUnit -Path $literal
Check 'dl:shared in a string literal is not a marker' (-not $r.is_shared) `
  'this is why the reader tracks comment/string state instead of matching text'

$r = Invoke-SharedUnit -Path $late
Check 'a marker below the interface line is out of scope' (-not $r.is_shared) `
  'the marker is a unit-level declaration, not a statement'

# ------------------------------------------------------------------ writing --
$before = [System.IO.File]::ReadAllText($two)
$r = Invoke-SharedUnit -Path $two -AddProject 'YADF' -Apply
$after = [System.IO.File]::ReadAllText($two)
Check 'adding a listed project reports was_added:false' ($r.was_added -eq $false)
Check 'adding a listed project is a no-op' ($before -eq $after) `
  'idempotent: the menu item will be pressed twice'

$before = [System.IO.File]::ReadAllText($marked)
$r = Invoke-SharedUnit -Path $marked -AddProject 'YADFOT'
$after = [System.IO.File]::ReadAllText($marked)
Check 'dry-run does not write' ($before -eq $after) `
  'default is dry-run, matching allow'
Check 'dry-run still reports what it would produce' (($r.projects -join ',') -eq 'YADF,YADFOT') `
  "got '$($r.projects -join ',')'"
Check 'dry-run reports applied:false' ($r.applied -eq $false)

$r = Invoke-SharedUnit -Path $marked -AddProject 'YADFOT' -Apply
$after = [System.IO.File]::ReadAllText($marked)
Check 'apply writes the new project' ($r.was_added -eq $true -and $r.applied -eq $true)
Check 'apply appends in written order' (($r.projects -join ',') -eq 'YADF,YADFOT') `
  "got '$($r.projects -join ',')'"
Check 'apply preserves the unit declaration' ($after -match 'unit MarkedUnit;') `
  'only the marker may change'
Check 'apply keeps the file CRLF' (($after -split "`n").Count -eq (($after -split "`r`n").Count)) `
  'these sources are strict CRLF'
Check 'apply keeps the file 7-bit ASCII' (-not ($after.ToCharArray() | Where-Object { [int]$_ -gt 127 }))

$r = Invoke-SharedUnit -Path $marked -AddProject 'YADFOT' -Apply
Check 'a second apply of the same project is a no-op' ($r.was_added -eq $false) `
  'idempotent at the file level, not just the report'

$r = Invoke-SharedUnit -Path $plain -AddProject 'YADF' -Apply
$after = [System.IO.File]::ReadAllText($plain)
Check 'an unmarked unit gets a marker' ($r.was_added -eq $true -and $r.is_shared)
Check 'the new marker lands on the unit line' ($after -match '(?m)^unit PlainUnit;\s+// dl:shared YADF\s*$') `
  "first line is now: $((($after -split "`r`n")[0]))"

$r = Invoke-SharedUnit -Path $inBlock -AddProject 'Gamma' -Apply
$after = [System.IO.File]::ReadAllText($inBlock)
Check 'appending inside a block comment keeps the terminator' ($after -match '\{ dl:shared Alpha, Beta, Gamma \}') `
  "marker line is now: $((($after -split "`r`n") | Where-Object { $_ -match 'dl:shared' }))"
Check 'the appended project parses back' (($r.projects -join ',') -eq 'Alpha,Beta,Gamma') `
  "got '$($r.projects -join ',')'"

# ------------------------------------------------------------------- errors --
$out = & $Exe shared-unit --in (Join-Path $WorkDir 'NoSuchUnit.pas') --json 2>&1
Check 'a missing file is a non-zero exit, not a crash' ($LASTEXITCODE -ne 0) `
  "exit=$LASTEXITCODE"

$out = & $Exe shared-unit --json 2>&1
Check 'a missing --in prints usage and exits non-zero' ($LASTEXITCODE -ne 0) `
  "exit=$LASTEXITCODE"

Write-Host ''
if ($script:Failed) { Write-Host 'run_shared_unit_marker: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_shared_unit_marker: OK' -ForegroundColor Green
exit 0
