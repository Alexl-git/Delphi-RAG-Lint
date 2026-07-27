<#
  run_doc_p3_strip_collision.ps1 -- Auto-Document Phase 3 T3d2, D8 review round 1:
  pins the fixes for CRITICAL 1 (region-collision corruption) and IMPORTANT 2
  (writes to files the report never names).

  PART A -- CRITICAL 1: two declarations sharing one qualified name (Delphi
  `overload;`) on CONSECUTIVE source lines, with an engine-owned doc comment
  above only the FIRST of the pair (exactly what `document --qname X --apply`
  produces for an overloaded routine, since it always targets Syms[0] --
  verified directly against this fixture below, not assumed). Doc.Strip.pas's
  gap window ([ADeclLine-2, ADeclLine-1]) does not check that the intervening
  line is blank, so BOTH declaration lines resolve to the SAME physical doc
  region -- confirmed live in fixtures\docp3\strip_collision.pas, not a
  contrived shape: reachable in 311 measured same-file adjacent-overload pairs
  in the real ORM3 index (see task-3d2-report.md). Before the fix,
  DoDocumentStripQName unioned both symbols' delete edits with no
  de-duplication; TTextEditApplier.Apply has no overlap detection, so applying
  the identical delete twice removed whatever shifted up into the freed range
  on the second pass -- the declaration lines themselves. This runner proves
  the fixed de-duplication (on the RESOLVED REGION, not the symbol) reports
  the correct, non-doubled counts and leaves both declarations intact, with a
  byte-identical round-trip back to the pre-apply source.

  PART B -- IMPORTANT 2: a qualified name that resolves across TWO DIFFERENT
  FILES (two units sharing a name, e.g. the same unit duplicated per project
  tree -- 34 such cases measured in the real ORM3 index). Proves --qname
  --strip touches ONLY Syms[0]'s own file and reports exactly that file --
  never a silent edit to a file the report does not name.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\strip_collision.pas')).Path

Push-Location C:\TEMP
try {

# ===========================================================================
# PART A -- CRITICAL 1: same-file, consecutive-line overload collision
# ===========================================================================
Write-Host ''
Write-Host '=== PART A: CRITICAL 1 -- consecutive-line overloads sharing one doc region ===' -ForegroundColor Cyan

$scratchA = Join-Path C:\TEMP 'draglint_docp3stripcollision_a'
if (Test-Path $scratchA) { Remove-Item $scratchA -Recurse -Force }
New-Item -ItemType Directory -Path $scratchA | Out-Null
$targetA = Join-Path $scratchA 'strip_collision.pas'
$dbA     = Join-Path $scratchA 'a.sqlite'
Copy-Item $fixture $targetA -Force
$pristineBytes = [IO.File]::ReadAllBytes($targetA)

& $exePath index $scratchA --db $dbA 2>$null | Out-Null
Check 'A: index exits 0' ($LASTEXITCODE -eq 0)

# document --qname always targets Syms[0] only (TDocumenter.BuildFor takes a
# bare qualified name, not a resolved row -- see TDocBatch.DocumentUnit's own
# "Bug A" comment for why the BATCH path had to change this). For an
# overloaded routine that means only the FIRST overload's declaration ever
# gets an engine-written comment through --qname -- which, for two
# declarations on consecutive lines, is exactly the shape that collides.
& $exePath document --qname strip_collision.Combine --db $dbA --apply --json 2>$null | Out-Null
Check 'A: document --qname --apply exits 0' ($LASTEXITCODE -eq 0)

$afterApplyLines = [IO.File]::ReadAllLines($targetA)
$declAIx = -1; $declBIx = -1
for ($i = 0; $i -lt $afterApplyLines.Count; $i++) {
  if ($afterApplyLines[$i] -match '^function Combine\(A: Integer\): Integer; overload;') { $declAIx = $i }
  if ($afterApplyLines[$i] -match '^function Combine\(A, B: Integer\): Integer; overload;') { $declBIx = $i }
}
Check 'A FIXTURE: both overload declarations are present after --apply' ($declAIx -ge 0 -and $declBIx -ge 0) "declAIx=$declAIx declBIx=$declBIx"
Check 'A FIXTURE: the two declarations are on CONSECUTIVE lines (no blank/comment between them)' `
  ($declAIx -ge 0 -and $declBIx -eq $declAIx + 1) "declAIx=$declAIx declBIx=$declBIx"
# The collision precondition, proven rather than assumed: an engine comment
# sits directly above the FIRST overload, and NOTHING sits directly above
# the second.
Check 'A FIXTURE: an engine-owned comment sits directly above the FIRST overload' `
  ($declAIx -ge 1 -and $afterApplyLines[$declAIx - 1].TrimStart().StartsWith('///'))
Check 'A FIXTURE: the SECOND overload has NO comment line directly above it (its own declaration line is what sits there)' `
  ($declBIx -ge 1 -and (-not $afterApplyLines[$declBIx - 1].TrimStart().StartsWith('///')))

# --- The fix under test: --qname --strip --apply must not corrupt either decl ---
& $exePath index $scratchA --db $dbA 2>$null | Out-Null
Check 'A: re-index before strip exits 0' ($LASTEXITCODE -eq 0)

$stripOut = (& $exePath document --qname strip_collision.Combine --db $dbA --strip --apply --json 2>$null) -join ' '
Check 'A: document --qname --strip --apply exits 0' ($LASTEXITCODE -eq 0)

# CRITICAL: the exact counts must be 1/1/1 -- NOT doubled. A regression back
# to the union-with-no-dedup shape would report tagsRemoved:2, blocksRemoved:2.
Check 'A CRITICAL: reports the NON-DOUBLED counts (tagsRemoved:1, blocksRemoved:1, edits:1)' `
  ($stripOut -match '"tagsRemoved":1' -and $stripOut -match '"blocksRemoved":1' -and $stripOut -match '"edits":1') $stripOut

$afterStripText = [IO.File]::ReadAllText($targetA)
Check 'A CRITICAL: the FIRST overload declaration SURVIVES intact' `
  ($afterStripText.Contains('function Combine(A: Integer): Integer; overload;'))
Check 'A CRITICAL: the SECOND overload declaration SURVIVES intact (this is what the un-deduplicated union deleted)' `
  ($afterStripText.Contains('function Combine(A, B: Integer): Integer; overload;'))
Check 'A CRITICAL: the implementation keyword SURVIVES (the doubled delete ate past it in the unfixed code)' `
  ($afterStripText.Contains('implementation'))
Check 'A CRITICAL: both implementation bodies SURVIVE' `
  ($afterStripText.Contains('Result := A;') -and $afterStripText.Contains('Result := A + B;'))

# The strongest statement available: byte-identical round-trip back to the
# pristine, pre-apply source.
$afterStripBytes = [IO.File]::ReadAllBytes($targetA)
Check 'A ROUND-TRIP: file is BYTE-IDENTICAL to the pre-apply pristine fixture' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineBytes, [byte[]]$afterStripBytes))

# --- Idempotency: a second strip --apply is a no-op ---
& $exePath index $scratchA --db $dbA 2>$null | Out-Null
& $exePath document --qname strip_collision.Combine --db $dbA --strip --apply --json 2>$null | Out-Null
$afterStrip2Bytes = [IO.File]::ReadAllBytes($targetA)
Check 'A IDEMPOTENT: a second strip --apply is byte-identical (no further change)' `
  ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterStripBytes, [byte[]]$afterStrip2Bytes))

foreach ($l in [IO.File]::ReadAllLines($targetA)) {
  if ($l -match '^\s*///') { foreach ($ch in $l.ToCharArray()) { if ([int]$ch -gt 126) { Check 'A: every /// line is 7-bit ASCII' $false $l; break } } }
}

# ===========================================================================
# PART B -- IMPORTANT 2: a qname spanning two DIFFERENT files
# ===========================================================================
Write-Host ''
Write-Host '=== PART B: IMPORTANT 2 -- a qname that resolves across two files ===' -ForegroundColor Cyan

$scratchB = Join-Path C:\TEMP 'draglint_docp3stripcollision_b'
if (Test-Path $scratchB) { Remove-Item $scratchB -Recurse -Force }
$dirX = Join-Path $scratchB 'projX'
$dirY = Join-Path $scratchB 'projY'
New-Item -ItemType Directory -Path $dirX -Force | Out-Null
New-Item -ItemType Directory -Path $dirY -Force | Out-Null

# Two DIFFERENT files, same unit name, same routine name -- the real-world
# shape (a shared unit duplicated per project tree, e.g. the ORM3 index's
# EExtraExceptionInfo.pas under CLIENT/SERVER/TESTER).
$dupUnit = @'
unit dup;

interface

function Widget: Integer;

implementation

function Widget: Integer;
begin
  Result := 1;
end;

end.
'@
$dupUnitCrlf = $dupUnit -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $dirX 'dup.pas'), $dupUnitCrlf, (New-Object Text.ASCIIEncoding))
[IO.File]::WriteAllText((Join-Path $dirY 'dup.pas'), $dupUnitCrlf, (New-Object Text.ASCIIEncoding))
$pristineX = [IO.File]::ReadAllBytes((Join-Path $dirX 'dup.pas'))
$pristineY = [IO.File]::ReadAllBytes((Join-Path $dirY 'dup.pas'))

$dbB = Join-Path $scratchB 'b.sqlite'
& $exePath index $scratchB --db $dbB 2>$null | Out-Null
Check 'B: index exits 0' ($LASTEXITCODE -eq 0)

$queryOut = (& $exePath query --name Widget --db $dbB --json 2>$null) -join "`n"
Check 'B FIXTURE: dup.Widget resolves across exactly TWO files' `
  ((([regex]::Matches($queryOut, '"qualified_name"\s*:\s*"dup\.Widget"')).Count) -eq 2) $queryOut

# Write an engine comment on EACH file's copy independently (--unit is scoped
# to one file, so this cannot itself cross files).
& $exePath document --unit (Join-Path $dirX 'dup.pas') --db $dbB --stubs --apply --json 2>$null | Out-Null
Check 'B: document --unit (X) --apply exits 0' ($LASTEXITCODE -eq 0)
& $exePath document --unit (Join-Path $dirY 'dup.pas') --db $dbB --stubs --apply --json 2>$null | Out-Null
Check 'B: document --unit (Y) --apply exits 0' ($LASTEXITCODE -eq 0)

$xAfterApply = [IO.File]::ReadAllText((Join-Path $dirX 'dup.pas'))
$yAfterApply = [IO.File]::ReadAllText((Join-Path $dirY 'dup.pas'))
Check 'B FIXTURE: BOTH files independently gained an engine marker' `
  ($xAfterApply.Contains('drag-lint:auto') -and $yAfterApply.Contains('drag-lint:auto'))

& $exePath index $scratchB --db $dbB 2>$null | Out-Null
Check 'B: re-index before strip exits 0' ($LASTEXITCODE -eq 0)

$whichFirst = (& $exePath query --name Widget --db $dbB --json 2>$null) -join "`n" | ConvertFrom-Json
$firstFile = $whichFirst[0].file
$strippedIsX = $firstFile -like '*projX*'

$stripOutB = (& $exePath document --qname dup.Widget --db $dbB --strip --apply --json 2>$null) -join ' '
Check 'B: document --qname --strip --apply exits 0' ($LASTEXITCODE -eq 0)
Check 'B: the report names exactly ONE file (Syms[0]''s own)' `
  ($stripOutB -match '"file":"[^"]*dup\.pas"' -and (([regex]::Matches($stripOutB, 'dup\.pas')).Count -eq 1)) $stripOutB

$xAfterStrip = [IO.File]::ReadAllBytes((Join-Path $dirX 'dup.pas'))
$yAfterStrip = [IO.File]::ReadAllBytes((Join-Path $dirY 'dup.pas'))
if ($strippedIsX) {
  Check 'B IMPORTANT 2: the NAMED file (X) was stripped back to pristine' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineX, [byte[]]$xAfterStrip))
  Check 'B IMPORTANT 2: the OTHER file (Y) was NOT touched -- still carries its own marker, byte-identical to right after its own --apply' `
    ([System.Linq.Enumerable]::SequenceEqual([Text.Encoding]::ASCII.GetBytes($yAfterApply), [byte[]]$yAfterStrip))
} else {
  Check 'B IMPORTANT 2: the NAMED file (Y) was stripped back to pristine' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$pristineY, [byte[]]$yAfterStrip))
  Check 'B IMPORTANT 2: the OTHER file (X) was NOT touched -- still carries its own marker, byte-identical to right after its own --apply' `
    ([System.Linq.Enumerable]::SequenceEqual([Text.Encoding]::ASCII.GetBytes($xAfterApply), [byte[]]$xAfterStrip))
}

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
