<#
  run_lint_config_file_anchor.ps1 -- docs\PLAN-SESSION-47.md T3

  `LoadLintConfig` discovers drag-lint-lint.json beside a --project (and in its
  _D-RAG folder), but bare `lint <file>` falls through to

      if (Path = '') and TFile.Exists('drag-lint-lint.json') then ...

  a RELATIVE name, resolved against the CURRENT DIRECTORY. The IDE plugin spawns
  the engine with lpCurrentDirectory = nil (CreateProcessW, LiveDiagnostics.pas
  :126), so it inherits whatever directory the IDE happens to be sitting in. A
  project's disabled-rules and severity rulings therefore applied to lint-all
  and only by luck to the per-file runs the user actually sees.

  THIS REPO ALREADY CARRIES THE WORKAROUND, which is the best evidence the
  defect is real. Its own drag-lint-lint.json says, verbatim:

      "Pass with --config when linting this repo from a neutral CWD (the
       pipeline runs from C:\TEMP, so the auto-discovery of a CWD-local
       drag-lint-lint.json does not find this file)."

  C2 IS THE POSITIVE CONTROL and it is not optional: without it, C1 passes for a
  build where the rule simply stopped firing -- which is indistinguishable from
  "the config was honoured" by looking at the output alone. C3 pins the opposite
  error, a config that suppresses everything rather than the one named rule.

  Runs from a NEUTRAL, EMPTY directory created here, so a stray
  drag-lint-lint.json in the caller's cwd cannot decide the outcome either way.

  pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_cfg_anchor"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$proj    = Join-Path $WorkDir 'proj'
$neutral = Join-Path $WorkDir 'neutral'
New-Item -ItemType Directory -Path $proj    -Force | Out-Null
New-Item -ItemType Directory -Path $neutral -Force | Out-Null

# Two DIFFERENT rules fire here on purpose: empty-except is the one the config
# disables, try-except-swallowed is the one that must survive it.
$fixture = @'
unit uCfgAnchor;

interface

procedure Risky;

implementation

procedure Risky;
begin
  try
    Risky;
  except
  end;
end;

end.
'@

$file = Join-Path $proj 'uCfgAnchor.pas'
Write-Ascii $file $fixture

$cfg = Join-Path $proj 'drag-lint-lint.json'
Write-Ascii $cfg '{ "disabled": ["empty-except"] }'

function RuleHits($text, $id) {
  @($text -split "`r?`n" | Where-Object { $_ -match ("\[\w+\]\s+" + [regex]::Escape($id) + ":") }).Count
}

Push-Location $neutral
try {
  $withCfg = & $exePath lint $file --rules-dir $rules 2>&1 | Out-String

  Check 'C1  a config beside the FILE is honoured from an unrelated cwd' `
        ((RuleHits $withCfg 'empty-except') -eq 0) `
        "empty-except is disabled in $cfg but still reported: $(($withCfg -split "`r?`n" | Where-Object { $_ -match 'empty-except' }) -join ' | ')"

  Check 'C3  the config disables ONLY the rule it names' `
        ((RuleHits $withCfg 'try-except-swallowed') -ge 1) `
        "try-except-swallowed is not in the disabled list and must survive -- if it is gone, discovery is suppressing everything"

  # POSITIVE CONTROL: take the config away and the rule must come back. Without
  # this, C1 is satisfied by a build in which empty-except simply never fires.
  Remove-Item $cfg -Force
  $noCfg = & $exePath lint $file --rules-dir $rules 2>&1 | Out-String

  Check 'C2  CONTROL: with the config REMOVED, the same run reports the rule again' `
        ((RuleHits $noCfg 'empty-except') -ge 1) `
        "the rule must be alive for C1 to mean anything; if this is 0 the fixture stopped triggering it"
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'run_lint_config_file_anchor: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_config_file_anchor: PASS' -ForegroundColor Green
exit 0
