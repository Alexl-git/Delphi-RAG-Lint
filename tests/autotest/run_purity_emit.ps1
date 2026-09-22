<#
  run_purity_emit.ps1 -- purity v2 Task 5: the CONSUMER side of the stored
  verdict (plan C6.1; spec docs\superpowers\specs\2026-09-15-interprocedural-
  purity.md sections 11-12).

  WHAT CHANGED AND WHY IT NEEDS A GUARD. Until today the `Pure` fact line was
  DERIVED at render time in TDocRegions.FormatPhase2FactLines from five local
  facts being empty -- BodyLoc > 0 and no WritesFields / MutatesParams /
  Touches / SqlWrites / SqlReads. That is a claim about what this engine
  happened not to detect IN THIS ONE ROUTINE, and it is wrong in both
  directions the moment a routine calls anything: on the fixture below,
  `WriteGlobal` writes a unit-level global (not a FIELD, so WritesFields is
  empty) and `Driver` calls it, and the pre-change engine printed `Pure` for
  BOTH. Measured against the pre-change binary, verbatim, 2026-09-22:

      hover uEmitProbe.WriteGlobal -> "facts":["Pure"]
      hover uEmitProbe.Driver      -> "facts":["Pure"]   (it calls WriteGlobal)

  The line is now READ from symbol_facts.effect_free, written by the `purity`
  resolve stage, and renamed `Effect-free (proven)` because that is what it
  now says: a POSITIVE, interprocedural proof. Its ABSENCE claims nothing.

  THE POSITIVE CONTROLS, stated so no check here can pass vacuously:
    * check 26a fails if the line stops rendering for ANYONE (an always-false
      gate), because AddUp -- genuinely proven -- must carry it;
    * checks 26c/26d fail if the line renders for EVERYONE (an always-true
      gate), because WriteGlobal and Driver must NOT carry it -- and those two
      are exactly the routines the pre-change render-time guess got wrong, so
      they also fail if the old five-fact derivation is still what answers;
    * check 27 clears the verdict behind the engine's back (python sqlite3 --
      `drag-lint sql` is read-only by design) and requires the line to VANISH:
      that is what proves the renderer reads the COLUMN and not a recomputation.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs python (sqlite3) for check 27.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_purity_emit"
)
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# AddUp    -- proven effect-free, and CALLED, so it has a 'Called from:' fact
#             and therefore a managed block ('Effect-free (proven)', like
#             'Pure' before it, never creates a block of its own).
# WriteGlobal -- writes a unit-level GLOBAL. Not a field, so WritesFields stays
#             empty and the OLD five-fact derivation called it Pure.
# Driver   -- calls WriteGlobal, so it is not proven either. The old derivation
#             could not see that at all: it never looked past the routine.
$src  = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
$unit = Join-Path $src 'uEmit.pas'
Write-Ascii $unit @'
unit uEmit;

interface

function AddUp(A, B: Integer): Integer;
procedure WriteGlobal;
procedure Driver;

implementation

var
  G: Integer;

function AddUp(A, B: Integer): Integer;
begin
  Result := A + B;
end;

procedure WriteGlobal;
begin
  G := G + 1;
end;

procedure Driver;
begin
  WriteGlobal;
  AddUp(1, 2);
end;

end.
'@

$db = Join-Path $WorkDir 'e.sqlite'
Push-Location C:\TEMP
try {
  $null = & $Exe index $src --db $db 2>&1
  $code = $LASTEXITCODE
} finally { Pop-Location }
Check '0. index exits 0' ($code -eq 0) "exit=$code"

function Get-HoverFacts([string]$QName) {
  $raw = (& $Exe hover --qname $QName --db $db --format json 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  return @(($raw | ConvertFrom-Json).facts)
}
function Get-HoverJson([string]$QName) {
  $raw = (& $Exe hover --qname $QName --db $db --format json 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return ($raw | ConvertFrom-Json)
}
function Count-Exact([string[]]$Facts, [string]$Text) {
  return @($Facts | Where-Object { $_.Trim() -eq $Text }).Count
}

Write-Host ''
Write-Host 'THE FACT LINE (hover, the CLI surface that renders without a doc row)' -ForegroundColor Cyan
$fa = Get-HoverFacts 'uEmit.AddUp'
$fw = Get-HoverFacts 'uEmit.WriteGlobal'
$fd = Get-HoverFacts 'uEmit.Driver'
Check '26a. proven routine hover carries "Effect-free (proven)" exactly once' `
  ((Count-Exact $fa 'Effect-free (proven)') -eq 1) ("AddUp facts: " + ($fa -join ' | '))
# @(...) around each: a one-element array RETURNS as a bare string, and then
# `$fa + $fw + $fd` is STRING CONCATENATION -- 'PurePurePure', which matches
# nothing and makes this check pass exactly when it should fail. Measured while
# writing this guard, against the pre-change engine, which really did emit
# 'Pure' for all three.
$allFacts = @($fa) + @($fw) + @($fd)
Check '26b. "Pure" is never emitted on any of the three' `
  ((Count-Exact $allFacts 'Pure') -eq 0) ($allFacts -join ' | ')
Check '26c. CONTROL a global write is NOT proven, so it has NO effect line' `
  ((@($fw | Where-Object { $_ -match 'Effect-free' })).Count -eq 0) ("WriteGlobal facts: " + ($fw -join ' | '))
Check '26d. CONTROL its CALLER is not proven either (the verdict is interprocedural)' `
  ((@($fd | Where-Object { $_ -match 'Effect-free' })).Count -eq 0) ("Driver facts: " + ($fd -join ' | '))

Write-Host ''
Write-Host 'THE STRUCTURED VERDICT (hover JSON)' -ForegroundColor Cyan
$jw = Get-HoverJson 'uEmit.WriteGlobal'
Check '12a. hover JSON exposes effect_free / effect_summary / effect_witness' `
  (($null -ne $jw) -and ($jw.effect_free -eq 0) -and ($jw.effect_summary -eq 'g') -and ($jw.effect_witness -match 'writes')) `
  ("ef=[$($jw.effect_free)] es=[$($jw.effect_summary)] ew=[$($jw.effect_witness)]")
$ja = Get-HoverJson 'uEmit.AddUp'
Check '12b. proven: effect_free 1, empty summary, empty witness' `
  (($null -ne $ja) -and ($ja.effect_free -eq 1) -and ($ja.effect_summary -eq '') -and ($ja.effect_witness -eq '')) `
  ("ef=[$($ja.effect_free)] es=[$($ja.effect_summary)] ew=[$($ja.effect_witness)]")

Write-Host ''
Write-Host 'THE MANAGED DOC BLOCK (document --apply)' -ForegroundColor Cyan
Push-Location $src
try { $null = & $Exe document --unit $unit --db $db --apply --no-backup 2>&1 } finally { Pop-Location }
$text = [System.IO.File]::ReadAllText($unit)
# The line keeps the slot 'Pure' held -- last of the Phase 3 lines, before
# 'Directives:'. AddUp renders no seealso, so on ITS block the fact is the last
# line before the END marker. Matched in the <para>-WRAPPED form, which is what
# the renderer has emitted since P8 (2026-08-24).
Check '29a. the managed block carries the new line in the fixed slot (last Phase 3 line)' `
  ($text -match '///\s*<para>Effect-free \(proven\)</para>\r?\n\s*///\s*<!-- drag-lint:auto END -->') `
  ''
Check '29b. no <para>Pure</para> survives anywhere in the regenerated file' `
  ($text -notmatch '<para>Pure</para>') ''
# CONTROL for 29a: the two NOT-proven routines got blocks too (Called from: /
# Calls:), so "no effect line there" is a real absence, not a missing block.
Check '29c. CONTROL all three routines got a managed block' `
  ((([regex]::Matches($text, [regex]::Escape('drag-lint:auto BEGIN'))).Count) -eq 3) `
  ("begins=" + ([regex]::Matches($text, [regex]::Escape('drag-lint:auto BEGIN'))).Count)

Write-Host ''
Write-Host 'NULL = NOT COMPUTED, AND NOT COMPUTED PRINTS NOTHING' -ForegroundColor Cyan
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
  Check '27. control available: python (sqlite3) to clear the verdict' $false 'python not on PATH'
} else {
  # `drag-lint sql` is read-only by design, so the verdict is cleared behind the
  # engine's back. This is what separates "reads the column" from "recomputes
  # the old five-fact guess and happens to agree".
  $clear = "import sqlite3; c = sqlite3.connect(r'$db'); n = c.execute('UPDATE symbol_facts SET effect_free=NULL, effect_summary=NULL, effect_witness=NULL').rowcount; c.commit(); c.close(); print(n)"
  $rows  = (& python -c $clear 2>&1) -join "`n"
  Check '27a. the verdict was cleared on every facts row' ($rows.Trim() -match '^[1-9]\d*$') "rows=[$($rows.Trim())]"
  $fn = Get-HoverFacts 'uEmit.AddUp'
  Check '27b. a NULL verdict prints no effect line (and no Pure)' `
    ((@($fn | Where-Object { $_ -match 'Effect-free' -or $_.Trim() -eq 'Pure' })).Count -eq 0) ($fn -join ' | ')
  $jn = Get-HoverJson 'uEmit.AddUp'
  Check '27c. JSON effect_free is -1 ("not computed"), never 0 ("not proven")' `
    (($null -ne $jn) -and ($jn.effect_free -eq -1)) "ef=[$($jn.effect_free)]"
}

Write-Host ''
if ($script:Failed) { Write-Host 'PURITY EMIT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PURITY EMIT: PASS' -ForegroundColor Green; exit 0 }
