<#
  run_lint_all_config_db_anchor.ps1 --
  docs\INBOX-ide-per-unit-view-omits-79pct-of-lint-all.md (the REVERSE direction)

  `lint-all --db <db>` must honour the config that belongs to the INDEXED
  PROJECT, not the config that happens to sit in whatever directory the operator
  is standing in.

  HOW THIS WAS FOUND, because it says what the guard is really protecting.
  Session 47's T3 anchored config discovery to the FILE for the per-file verb,
  and the parity work then reported "9 of 10 rule ids, nothing extra the other
  way" -- measured on DataCopy. Re-measured on ORM3, the per-file verb reported
  TWELVE rule ids that `lint-all` did not, and the first reading was that the
  per-file verb had started over-reporting.

  It had not. Every one of those twelve -- fan-out, instability, feature-envy,
  magic-literal, boolean-flag-parameter, loop-control-flag,
  mutable-global-variable, public-writable-field, default-encoding-io,
  multiple-statements-per-line, repeated-type-switch, exhaustive-enum-case -- is
  in ORM3's OWN `enabled` list. The per-file verb was right; `lint-all` was
  reading this repo's config instead of ORM3's, because it was launched from
  this repo's directory.

  WHY IT MATTERS RATHER THAN BEING A CURIOSITY: an owner ruling recorded as a
  config file did nothing, silently, and the only symptom was findings the owner
  believed were enabled (or disabled) behaving as though they were not. The
  battery itself runs from C:\TEMP on purpose, and CLAUDE.md instructs every
  session to invoke the engine by full path from wherever it stands -- so the
  wrong-config path was the NORMAL one, not the exotic one.

  A1 IS A DIFFERENTIAL, WHICH IS THE ONLY HONEST SHAPE HERE. Asserting "the rule
  fires" from the project directory proves nothing about anchoring -- the CWD
  fallback would pass it too. The claim is that the answer does not DEPEND on
  the current directory, so the same --db is run from two directories and the
  two results are required to agree.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_cfg_db_anchor"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory -Path $proj -Force | Out-Null

# magic-literal is OFF by default, so it can only appear if the project's own
# config was actually read. A rule that is on by default would prove nothing.
Write-Ascii (Join-Path $proj 'uMagic.pas') @'
unit uMagic;

interface

function Scale(AValue: Integer): Integer;

implementation

function Scale(AValue: Integer): Integer;
begin
  Result := AValue * 8675309;
end;

end.
'@

Write-Ascii (Join-Path $proj 'drag-lint-lint.json') '{ "enabled": ["magic-literal"] }'

# The documented layout: <project folder>\_D-RAG\<name>.sqlite. The anchor walk
# relies on it, so the fixture must reproduce it rather than putting the DB
# somewhere convenient.
$db = Join-Path (Join-Path $proj '_D-RAG') 'p.sqlite'
& $exePath index $proj --db $db 2>&1 | Out-Null

function LintFrom([string]$Cwd) {
  Push-Location $Cwd
  try   { return (& $exePath lint-all --db $db --rules-dir $rules 2>$null | Out-String) }
  finally { Pop-Location }
}
function FindingsOnly([string]$T) {
  ,@(($T -split "`r?`n") | Where-Object { $_ -match ':\d+:\d+\s+\[(error|warning|info|hint)\]' } | Sort-Object)
}

$fromProj    = LintFrom $proj
$fromForeign = LintFrom 'C:\TEMP'

$fP = FindingsOnly $fromProj
$fF = FindingsOnly $fromForeign

Check 'VACUITY the fixture produces findings from the project directory' ($fP.Count -gt 0) `
      'no findings at all -- A1 would be comparing two empty sets, which is how a guard in this repo once passed against an unfixed build'

Check 'CONTROL the project config is actually in effect somewhere' `
      ($fromProj -match 'magic-literal') `
      'magic-literal never fired even from the project directory -- the fixture config is not being read at all, so A1 cannot mean anything'

# ---- A1: the answer must not depend on the current directory ---------------
Check 'A1 lint-all reports magic-literal from a FOREIGN cwd (config anchored to --db)' `
      ($fromForeign -match 'magic-literal') `
      'the project config was ignored because the run was launched elsewhere -- an owner ruling recorded in drag-lint-lint.json silently does nothing'

Check 'A1 the finding SET is identical from both directories' `
      (($fP -join "`n") -eq ($fF -join "`n")) `
      "project cwd=$($fP.Count) foreign cwd=$($fF.Count) -- lint-all's answer must not depend on where it was launched"

# ---- A2: a more specific anchor still wins --------------------------------
# The DB anchor is LAST. An explicit --config must override it, or the fix has
# quietly promoted a fallback above the thing it is a fallback for.
$otherCfg = Join-Path $WorkDir 'other-lint.json'
Write-Ascii $otherCfg '{ "disabled": ["magic-literal"] }'
Push-Location 'C:\TEMP'
try   { $withCfg = & $exePath lint-all --db $db --rules-dir $rules --config $otherCfg 2>$null | Out-String }
finally { Pop-Location }
Check 'A2 an explicit --config still overrides the --db anchor' `
      (-not ($withCfg -match 'magic-literal')) `
      'the DB anchor overrode an explicitly named config -- precedence is inverted'

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
