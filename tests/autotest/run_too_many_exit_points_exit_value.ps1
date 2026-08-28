<#
  run_too_many_exit_points_exit_value.ps1 --
  docs\INBOX-too-many-exit-points-counts-exit-value-twice.md

  THE DEFECT. `CountExits` in DRagLint.Diagnostics.AstChecks.pas matched an
  `exprCall` whose `entity` text is `Exit` (+1), then recursed into ALL of its
  children -- INCLUDING that same entity `identifier`, whose text is also
  `Exit` (+1 again). A bare `exit;` is a plain identifier with no entity child,
  so it counted once. Net: `Exit(Value)` counted DOUBLE and bare `exit` counted
  right, in the same routine, silently.

  WHY IT MATTERS MORE THAN "info severity" SUGGESTS. The effective threshold for
  a routine written in the modern `Exit(Value)` guard-clause style -- the style
  Delphi 13 code and this owner's own DataCopy code use -- was ~2.5 instead of
  5. The rule therefore fired hardest on the CLEANEST code, which is how a rule
  teaches people to ignore it.

  MEASURED on the unfixed build (2026-08-28), C:\Projects\DataCopy\
  uMahrMarformMMQ.pas:
      MahrMatchesShape  3 x `exit(False)`  -> reported "6 Exit statements"
      MahrParseHeader   8 x bare `exit;`   -> reported "8"   (correct)
  The first is a FALSE finding outright: 3 is under the threshold of 5.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_tmep_exitvalue"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# One unit, five routines, each isolating ONE counting shape. The threshold is
# 5, so ThreeValued (3) must be SILENT and the six-exit routines must report
# exactly 6 -- a count of 12 is the pre-fix answer for the valued forms.
$fixture = @'
unit uExits;

interface

function ThreeValued(A: Integer): Boolean;
function SixValued(A: Integer): Boolean;
function SixBare(A: Integer): Boolean;
function SixMixed(A: Integer): Boolean;
function OuterWithNested(A: Integer): Boolean;

implementation

function ThreeValued(A: Integer): Boolean;
begin
  if A = 1 then Exit(False);
  if A = 2 then Exit(False);
  if A = 3 then Exit(False);
  Result := True;
end;

function SixValued(A: Integer): Boolean;
begin
  if A = 1 then Exit(True);
  if A = 2 then Exit(True);
  if A = 3 then Exit(True);
  if A = 4 then Exit(True);
  if A = 5 then Exit(True);
  if A = 6 then Exit(True);
  Result := False;
end;

function SixBare(A: Integer): Boolean;
begin
  Result := False;
  if A = 1 then exit;
  if A = 2 then exit;
  if A = 3 then exit;
  if A = 4 then exit;
  if A = 5 then exit;
  if A = 6 then exit;
  Result := True;
end;

function SixMixed(A: Integer): Boolean;
begin
  Result := False;
  if A = 1 then exit;
  if A = 2 then exit;
  if A = 3 then exit;
  if A = 4 then Exit(True);
  if A = 5 then Exit(True);
  if A = 6 then Exit(True);
  Result := True;
end;

function OuterWithNested(A: Integer): Boolean;

  function Inner(B: Integer): Boolean;
  begin
    if B = 1 then Exit(False);
    if B = 2 then Exit(False);
    if B = 3 then Exit(False);
    if B = 4 then Exit(False);
    if B = 5 then Exit(False);
    if B = 6 then Exit(False);
    Result := True;
  end;

begin
  if A = 1 then Exit(False);
  if A = 2 then Exit(False);
  Result := Inner(A);
end;

end.
'@

$file = Join-Path $WorkDir 'uExits.pas'
Write-Ascii $file $fixture

Push-Location C:\TEMP
try {
  $out = (& $exePath lint $file --rules-dir $rules 2>&1 | Out-String)
  $lines = @($out -split "`r?`n" | Where-Object { $_ -match 'too-many-exit-points' })
  Write-Host '  reported:' -ForegroundColor DarkGray
  foreach ($l in $lines) { Write-Host ("    " + $l.Trim()) -ForegroundColor DarkGray }

  # Map each finding line back to its routine by the line number it reports.
  $srcLines = [System.IO.File]::ReadAllLines($file)
  function CountFor([string]$Routine) {
    foreach ($l in $lines) {
      if ($l -match ':(\d+):\d+\s' ) {
        $ln = [int]$Matches[1]
        # the finding anchors on the routine header line (1-based)
        if ($srcLines[$ln - 1] -match [regex]::Escape($Routine)) {
          if ($l -match 'has (\d+) Exit statements') { return [int]$Matches[1] }
        }
      }
    }
    return 0   # 0 = not reported at all
  }

  # ---- THE DEFECT. Three valued exits is under the threshold of 5, so the
  #      routine must not be reported at all. Pre-fix it reports "6".
  Check 'K1 three `Exit(V)` is BELOW the threshold and is NOT reported' `
        ((CountFor 'ThreeValued') -eq 0) "reported count: $(CountFor 'ThreeValued') (expected: no finding)"

  # ---- The count itself, where the routine legitimately fires.
  Check 'K2 six `Exit(V)` counts 6, not 12' `
        ((CountFor 'SixValued') -eq 6) "reported count: $(CountFor 'SixValued')"

  # ---- POSITIVE CONTROLS. K3 fires before AND after the fix. Without it, a
  #      "fix" that simply stopped counting the valued form -- or stopped
  #      counting altogether -- would pass K1 and K2 perfectly.
  Check 'K3 CONTROL six bare `exit;` still counts 6' `
        ((CountFor 'SixBare') -eq 6) "reported count: $(CountFor 'SixBare')"
  Check 'K4 CONTROL mixed 3 bare + 3 valued counts 6' `
        ((CountFor 'SixMixed') -eq 6) "reported count: $(CountFor 'SixMixed')"

  # ---- The nested-routine exclusion must survive. Inner has 6 exits and is
  #      counted as its own routine; Outer has 2 and must stay silent. A fix
  #      that flattened the walk would merge them into 8 and report Outer.
  Check 'K5 CONTROL a nested routine`s exits are NOT counted into its parent' `
        ((CountFor 'function OuterWithNested') -eq 0) `
        "outer reported: $(CountFor 'function OuterWithNested') (expected: no finding)"
  Check 'K5 CONTROL the nested routine IS reported on its own, with 6' `
        ((CountFor 'function Inner') -eq 6) "inner reported: $(CountFor 'function Inner')"

  Check 'VACUITY the rule ran at all' ($lines.Count -gt 0) `
        'no too-many-exit-points findings whatsoever -- the rule may be disabled'
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
