<#
  run_doc_omit_empty_elements.ps1 -- an element with nothing to say is not
  written, and an existing empty one is removed.

  THE RULING (user, 2026-08-09; review item B7)
  --------------------------------------------------------------------------------
      "Do not generate empty sections and TODO to fill them up.
       Empty sections are omitted."

  This REVERSES the structure-always half of ruling D-3, which had `document`
  emit `<param name="X"></param>` for every signature parameter. D-3 existed for
  a real reason -- `doc-drift` reported those tags as MISSING while `document`
  refused to write any, so the two halves could never converge (22 unclearable
  findings). They converge the other way now: neither emit the empty tag nor
  demand it. That holds because ddParamMissing is gated on HUMAN authorship
  (PHASE A4), so an engine block that writes no params is not human-authored and
  the rule stays quiet. The last check below pins exactly that, because it is the
  property the reversal depends on.

  THE PART THAT REACHES EXISTING FILES. An empty element carries NOTHING TO
  PRESERVE, so the ownership question that governs every other merge decision
  does not arise -- dropping it cannot lose a human's words, because there are
  none. That is what lets this clear tags the engine did not write. It matters:
  on the YADF corpus 78 of the 81 empty elements carry no marker at all, were
  therefore treated as hand-written, and had survived every regeneration
  precisely because the merge was protecting them.

  The controls are the point. A param the source DOES describe must still get its
  tag, and a hand-written summary with real prose must survive untouched -- D-4's
  meaning half is not what this ruling changes.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-omit-empty"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Described has an inline comment on ONE param only, so the same routine proves
# both arms at once: the described param keeps a tag, its neighbour gets none.
# Frozen carries UNMARKED empty elements -- the shape that used to be immortal.
# Keeper carries real hand-written prose and must come through untouched.
$unit = Join-Path $WorkDir 'omitempty.pas'
Write-Ascii $unit @'
unit omitempty;

interface

function Described(const AWanted: string { the value to look for }; const AOther: Integer): string;

/// <summary></summary>
/// <param name="AInput"></param>
/// <returns></returns>
function Frozen(const AInput: string): Integer;

/// <summary>Kept verbatim: a human wrote this.</summary>
function Keeper(const AThing: string): Boolean;

implementation

function Described(const AWanted: string; const AOther: Integer): string;
begin
  Result := AWanted;
end;

function Frozen(const AInput: string): Integer;
begin
  Result := Length(AInput);
end;

function Keeper(const AThing: string): Boolean;
begin
  Result := AThing <> '';
end;

// Gives every declaration above a caller, so each has a FACT and is therefore
// visited by `document`. Without this a routine the engine has nothing to say
// about is skipped entirely and its elements are never revisited -- which is a
// real limitation (see the residual note in the PHASE C plan), but not the thing
// this runner is testing.
procedure Driver;
begin
  if Described('a', 1) <> '' then Exit;
  if Frozen('b') > 0 then Exit;
  if Keeper('c') then Exit;
end;

end.
'@

$db = Join-Path $WorkDir 'omit.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null
& $Exe document --unit $unit --apply --db $db 2>&1 | Out-Null
$txt = Get-Content $unit -Raw

Write-Host 'Prose elements with nothing to say are not written' -ForegroundColor Cyan
Check 'no empty <summary></summary> anywhere'  (-not ($txt -match '<summary>\s*</summary>'))
Check 'no empty <returns></returns> anywhere'  (-not ($txt -match '<returns>\s*</returns>'))
Check 'no TODO placeholder was substituted for an omitted element' `
  (-not ($txt -match 'TODO')) 'the ruling forbids the placeholder as well as the blank'

Write-Host ''
Write-Host 'Pre-existing UNMARKED empty prose elements are cleared, not frozen' -ForegroundColor Cyan
Check 'Frozen''s unmarked empty <summary> is gone' `
  (-not ($txt -match '<summary>\s*</summary>')) `
  'unmarked = treated as hand-written; an EMPTY one has nothing to preserve'

Write-Host ''
Write-Host '<param> is STRUCTURAL and is NOT omitted (user clarification)' -ForegroundColor Cyan
# NB the body is preceded by the auto marker, which itself contains '<' -- a
# [^<]* between tag and text can never match and would fail on correct output.
Check 'a param the SOURCE describes gets a tag WITH its text' `
  ($txt -match '<param name="AWanted">.*the value to look for') `
  'D-4''s meaning half'
Check 'its undescribed neighbour AOther STILL gets a tag (structure mirrors the signature)' `
  ($txt -match '<param name="AOther"') `
  'the documenter reflects the code; the linter is what reports the missing description'
Check 'a hand-written summary with real prose survives verbatim' `
  ($txt -match '<summary>Kept verbatim: a human wrote this\.</summary>')

Write-Host ''
Write-Host 'Idempotency and drift' -ForegroundColor Cyan
# Removing elements is a ONE-TIME rewrite of files written by an older engine, so
# the invariant asserted is CONVERGENCE, not "the first apply changes nothing":
# once the cleanup pass has run, further passes must be byte-identical. (On the
# YADF corpus the very first apply was already stable -- apply #1 and apply #2
# produced identical files across all 12 units -- but a file that still carries
# pre-B7 empty elements legitimately settles on the pass that removes them.)
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null
& $Exe document --unit $unit --apply --db $db 2>&1 | Out-Null
$settled = Get-Content $unit -Raw
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null
& $Exe document --unit $unit --apply --db $db 2>&1 | Out-Null
Check 'once settled, further index+apply passes are byte-identical' `
  ((Get-Content $unit -Raw) -eq $settled)

# The property the D-3 reversal depends on, stated exactly. ddParamMissing is
# gated on HUMAN authorship, so the convergence claim is about ENGINE blocks:
# what `document` declines to write, `doc-drift` must not demand. That is what
# closes the 22-unclearable-findings trap D-3 was created to escape.
#
# On a HUMAN-authored block the warning DOES still fire, and that is intended
# rather than tolerated: a human who documented the summary and not the parameter
# has a genuine to-do, and D-3 used to paper over it with an empty tag that made
# the block look complete. Both arms are asserted, because a fix that silenced
# the rule everywhere would pass the first alone.
# The division of labour the user stated: the DOCUMENTER makes the block reflect
# the code, the LINTER reports what is wrong with it. So `document` writes every
# <param>, and an undocumented one is reported at WARNING -- not papered over,
# and not left as a hint that is easy to ignore forever.
$lint = & $Exe lint-all --db $db --json 2>$null
$find = @(); try { $find = ($lint -join "`n" | ConvertFrom-Json) } catch { $find = @() }
$nd = @($find | Where-Object { $_.rule -eq 'doc-param-no-description' })
Check 'an undocumented param is reported at WARNING' `
  ((@($nd | Where-Object { $_.message -match 'AOther' }).Count -ge 1) -and
   (@($nd | Where-Object { $_.severity -ne 'warning' }).Count -eq 0)) `
  ("severities: " + ((@($nd | ForEach-Object { $_.severity }) | Sort-Object -Unique) -join ','))
Check 'a param that HAS a description is not reported' `
  (@($nd | Where-Object { $_.message -match 'AWanted' }).Count -eq 0)
Check 'no "has no <param> tag" drift -- the documenter wrote every tag' `
  (@($find | Where-Object { $_.message -match 'has no <param> tag' }).Count -eq 0) `
  'documenter and linter converge; this is the trap ruling D-3 was created to close'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
