<#
  run_lint_rule_narrows_checkers.ps1 -- `lint <file> --rule X` runs only the
  checkers that can emit X (D3, docs\INBOX-defects-found-2026-09-23-rule-work.md).

  THE DEFECT. Every heavy checker in DoLint -- the type-aware map, the flow
  analysis, and above all the store-backed project pass -- ran for ANY --rule
  and had its output filtered afterwards. The project pass walks the WHOLE
  store, so `lint ArrayHelper.pas --rule <one id>`, whose index is the 2 GB
  platform library, spun 20+ CPU-minutes before it was killed.

  WHAT IS OBSERVABLE. A skipped checker and a checker that found nothing print
  the same findings, so findings alone cannot pin this. Two observables:
    * DRAGLINT_PROFILE's PROJECT-RULES BREAKDOWN -- printed by the project pass
      itself, pre-existing, so it is the RED-first assertion against the old
      engine;
    * DRAGLINT_DEBUG's `[lint-checker] <name>` trace, one line per heavy
      checker entered.
  Every "did NOT run" assertion is paired with a positive control in the same
  group: the checker DOES run when its own rule is asked for, and the finding
  still arrives. A trace that has died satisfies every silence check ever
  written.

  THE DRIFT GUARD. The gate lists live in CLI.pas (LINT_GATE_*). A list that is
  SHORT of an id its checker emits makes `--rule <that id>` answer 0 silently --
  the D2 shape. So each list is compared, both ways, against the ids its
  checker's source actually emits.

  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Repo    = "$PSScriptRoot\..\..",
  [string]$WorkDir = "$env:TEMP\drag-lint-rule-narrows"
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
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path $Repo).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# One unit, one finding per checker family: unused-local (cheap AST walk, the
# control), used-before-assignment (flow), float-equality-comparison
# (type-aware), unused-public-symbol (store-backed project pass).
Emit 'uNarrow.pas' @'
unit uNarrow;
interface
type
  TNarrow = class
  public
    procedure NeverCalled;
  end;
function IsHalf(const AValue: Double): Boolean;
procedure ReadsUnset;
implementation
function IsHalf(const AValue: Double): Boolean;
begin
  Result:= AValue = 1.5;
end;
procedure ReadsUnset;
var
  X, Y: Integer;
begin
  Y:= X + 1;
  Writeln(Y);
end;
procedure TNarrow.NeverCalled;
var
  Idle: Integer;
begin
end;
end.
'@

$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecNarrow", "db": "narrow.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db  = Join-Path $WorkDir 'out\narrow.sqlite'
$pas = Join-Path $srcDir 'uNarrow.pas'

function LintRun([string[]]$Extra, [string]$EnvName) {
  $old = [Environment]::GetEnvironmentVariable($EnvName)
  [Environment]::SetEnvironmentVariable($EnvName, '1')
  try {
    # --library-db names a file that does not exist, so no run here ever opens
    # the machine's real 2 GB platform library (it degrades to project-only).
    $argv = @('lint', $pas, '--db', $db, '--library-db', (Join-Path $WorkDir 'no-library.sqlite')) + $Extra
    return (& $Exe @argv 2>&1 | Out-String)
  } finally { [Environment]::SetEnvironmentVariable($EnvName, $old) }
}
function Ran([string]$Out, [string]$Name) { $Out -match ('\[lint-checker\] ' + [regex]::Escape($Name) + '\r?\n') }

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecNarrow --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }

  Write-Host ''
  Write-Host 'P: the pre-existing observable -- the project pass profiles itself' -ForegroundColor Cyan
  $pAll = LintRun @() 'DRAGLINT_PROFILE'
  Check 'P0 CONTROL: a bare run enters the project pass (breakdown printed)' `
    ($pAll -match 'PROJECT-RULES BREAKDOWN') 'if this fails, P1 below proves nothing'
  $pOne = LintRun @('--rule', 'unused-local') 'DRAGLINT_PROFILE'
  Check 'P1 --rule unused-local does NOT enter the whole-store project pass' `
    (-not ($pOne -match 'PROJECT-RULES BREAKDOWN')) 'RED means every --rule still pays for the whole store'
  Check 'P2 and still reports its own finding' ($pOne -match 'unused-local') ''

  Write-Host ''
  Write-Host 'T: the trace -- which heavy checker each --rule enters' -ForegroundColor Cyan
  $heavy = @('with-hiding', 'type-aware', 'flow', 'project-rules', 'used-unit-resolvable', 'class-metrics')
  $tAll = LintRun @() 'DRAGLINT_DEBUG'
  foreach ($h in $heavy) {
    Check "T0 CONTROL: a bare run enters $h" (Ran $tAll $h) 'the trace is alive'
  }

  $t1 = LintRun @('--rule', 'unused-local') 'DRAGLINT_DEBUG'
  foreach ($h in $heavy + @('library-store')) {
    Check "T1 --rule unused-local skips $h" (-not (Ran $t1 $h)) ''
  }
  Check 'T1 and still reports unused-local' ($t1 -match 'unused-local') ''

  # Each positive: the rule's own checker runs, the others do not, the finding arrives.
  $cases = @(
    @{ rule = 'used-before-assignment';    runs = 'flow';                 finding = $true },
    @{ rule = 'float-equality-comparison'; runs = 'type-aware';           finding = $true },
    @{ rule = 'string-equality-comparison';runs = 'type-aware';           finding = $false },
    @{ rule = 'unused-public-symbol';      runs = 'project-rules';        finding = $true },
    @{ rule = 'fan-out';                   runs = 'class-metrics';        finding = $false },
    @{ rule = 'used-unit-not-resolvable';  runs = 'used-unit-resolvable'; finding = $false },
    @{ rule = 'with-hides-outer-symbol';   runs = 'with-hiding';          finding = $false }
  )
  foreach ($c in $cases) {
    $o = LintRun @('--rule', $c.rule) 'DRAGLINT_DEBUG'
    Check ("T2 --rule {0} enters {1}" -f $c.rule, $c.runs) (Ran $o $c.runs) ''
    $others = @($heavy | Where-Object { $_ -ne $c.runs -and (Ran $o $_) })
    Check ("T2 --rule {0} enters nothing else" -f $c.rule) ($others.Count -eq 0) ("also entered: " + ($others -join ' '))
    if ($c.finding) {
      Check ("T2 --rule {0} still reports its finding" -f $c.rule) `
        ($o -match [regex]::Escape($c.rule)) 'a gate that drops the checker it needs'
    }
  }
} finally { Pop-Location }

Write-Host ''
Write-Host 'D: the gate lists match what each checker emits (both ways)' -ForegroundColor Cyan
$cli = [IO.File]::ReadAllText((Join-Path $Repo 'src\cli\DRagLint.CLI.pas'))
function GateList([string]$Name) {
  $m = [regex]::Match($cli, "(?s)\b$Name\s*:\s*array\[[^\]]*\]\s*of\s*string\s*=\s*\((.*?)\);")
  if (-not $m.Success) { return @() }
  return @([regex]::Matches($m.Groups[1].Value, "'([a-z0-9-]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}
function IdsIn([string]$RelPath, [string]$Rx, [string]$SpanRx = '') {
  $t = [IO.File]::ReadAllText((Join-Path $Repo $RelPath))
  if ($SpanRx) { $t = [regex]::Match($t, $SpanRx).Value }
  return @([regex]::Matches($t, $Rx) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}
$catalog = @((& $Exe rules --json 2>$null | Out-String | ConvertFrom-Json).rules | ForEach-Object { $_.id })
Check 'D0 CONTROL: the rule catalogue parsed' ($catalog.Count -gt 100) "($($catalog.Count) rule(s))"

$typeSpan = '(?s)class function TAstChecker\.CheckTypeAware\(.*?(?=\r?\nclass function TAstChecker\.)'
$emitted = [ordered]@{
  'LINT_GATE_TYPE_AWARE'    = @(IdsIn 'src\diagnostics\DRagLint.Diagnostics.AstChecks.pas' "'([a-z0-9]+(?:-[a-z0-9]+)+)'" $typeSpan | Where-Object { $catalog -contains $_ })
  'LINT_GATE_FLOW'          = IdsIn 'src\diagnostics\DRagLint.Diagnostics.FlowChecks.pas' "\bEmit\('([a-z0-9-]+)'"
  'LINT_GATE_PROJECT_RULES' = IdsIn 'src\lint\DRagLint.Lint.ProjectRules.pas' "\bWantRule\('([a-z0-9-]+)'\)"
  'LINT_GATE_CLASS_METRICS' = IdsIn 'src\lint\DRagLint.Lint.ClassMetrics.pas' "\bWantRule\('([a-z0-9-]+)'\)"
}
foreach ($k in $emitted.Keys) {
  $gate = GateList $k
  $emit = @($emitted[$k])
  Check "D1 $k parsed from CLI.pas" ($gate.Count -gt 0) "($($gate.Count) id(s))"
  Check "D1 $k emit sites found" ($emit.Count -gt 0) "($($emit.Count) id(s))"
  $short = @($emit | Where-Object { $gate -notcontains $_ })
  $extra = @($gate | Where-Object { $emit -notcontains $_ })
  Check "D2 $k carries every id its checker emits" ($short.Count -eq 0) `
    ("missing -> --rule answers 0 for: " + ($short -join ' '))
  Check "D3 $k names no id its checker never emits" ($extra.Count -eq 0) ("phantom: " + ($extra -join ' '))
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
