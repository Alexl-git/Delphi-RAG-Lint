<#
  run_v152_USESAUD_parity.ps1 -- 1.52 lane USESAUD. `uses-audit` (the verb) and the rule
  unused-unit-in-uses must agree on which PROJECT units a file imports but never needs.
  Cause (docs\INBOX-uses-audit-undercount.md, 5 vs 186): the verb's name fallback for an
  unbound reference credited EVERY unit that merely declares a MEMBER of that name (a field
  `Format` in one class kept that unit alive for every unbound `Format(...)` call), the rule
  credits only what a unit EXPORTS (top-level interface names, enum values).
  Fixture: generated into the work dir (PaA exports TPaA and is used; PaB declares only a
  FIELD named Format; PaC exports PaCProc; PaHost uses all three and calls an unbound
  Format(...)). Expected on both: PaB and PaC unused, PaA kept.
  Optional -YadfDb <copy of a real project DB>: per-file comparison of the two sets over the
  files carrying the most unused-unit-in-uses findings; every difference is printed with its
  documented reason (library units the verb never audits; DFM-only / helper / receiver-type
  uses the rule credits).
  Run from any CWD, pwsh 7.
#>

[CmdletBinding()]
param(
  [string]$Exe = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-usesaud-parity-$PID",
  [string]$YadfDb = '',
  [int]$YadfFiles = 3
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v152_USESAUD_parity: needs pwsh 7' -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
function VerbUnused($db, $file) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe uses-audit $file --db $db 2>$null }
  @($o | ForEach-Object { if ($_ -match '^\s*line \d+: (\S+)\s+-- appears UNUSED') { $Matches[1] } } | Sort-Object -Unique)
}
function Unit($name, $lines) {
  Set-Content -Path (Join-Path $fx "$name.pas") -Value ($lines -join "`r`n") -Encoding Ascii
}

$fx = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory -Force $fx | Out-Null
Unit 'PaA' @('unit PaA;', 'interface', 'type', '  TPaA = class', '  end;', 'implementation', 'end.')
Unit 'PaB' @('unit PaB;', 'interface', 'type', '  TPaB = class', '    Format: Integer;', '  end;', 'implementation', 'end.')
Unit 'PaC' @('unit PaC;', 'interface', 'procedure PaCProc;', 'implementation', 'procedure PaCProc;', 'begin', 'end;', 'end.')
Unit 'PaHost' @('unit PaHost;', 'interface', 'uses PaA, PaB, PaC;', 'procedure Run;', 'implementation', 'procedure Run;', 'var A: TPaA;', 'begin', '  Format(''x'', []);', 'end;', 'end.')
$db = Join-Path $WorkDir 'pa.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> (Join-Path $WorkDir 'index.log') }
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE"

$host1 = Join-Path $fx 'PaHost.pas'
$raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --rule unused-unit-in-uses --json 2>$null }) -join "`n"
$rule = @(@(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) | Where-Object { $_.file_path -like '*\PaHost.pas' } | ForEach-Object { if ($_.message -match "Unit '([^']+)'") { $Matches[1] } } | Sort-Object -Unique)
$verb = VerbUnused $db $host1
Check 'control: the rule flags PaC (exports nothing PaHost names)' ($rule -contains 'PaC') ("rule=" + ($rule -join ','))
Check 'control: neither side flags PaA (PaHost names TPaA)' (($rule -notcontains 'PaA') -and ($verb -notcontains 'PaA')) ("rule=" + ($rule -join ',') + " verb=" + ($verb -join ','))
Check 'verb flags PaC' ($verb -contains 'PaC') ("verb=" + ($verb -join ','))
Check 'verb flags PaB (only a MEMBER named Format; unbound Format call must not credit it)' ($verb -contains 'PaB') ("verb=" + ($verb -join ','))
Check 'verb and rule agree on the fixture' (($verb -join ',') -eq ($rule -join ',')) ("verb=" + ($verb -join ',') + " rule=" + ($rule -join ','))

if ($YadfDb -ne '') {
  Write-Host "  YADF/real DB copy: $YadfDb" -ForegroundColor Cyan
  $q = & { $ErrorActionPreference = 'Continue'; & $Exe sql --db $YadfDb --json --limit 100000 --query 'select path from files' 2>$null } | ConvertFrom-Json | ForEach-Object { $_ }
  $stems = @{}
  foreach ($r in $q.rows) { $stems[[IO.Path]::GetFileNameWithoutExtension($r[0]).ToLowerInvariant()] = $true }
  $all = @(((& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $YadfDb --rule unused-unit-in-uses --json 2>$null }) -join "`n" | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ })
  $top = @($all | Group-Object file_path | Sort-Object Count -Descending | Select-Object -First $YadfFiles)
  if ($top.Count -eq 0) { Write-Host '  (no unused-unit-in-uses findings in this DB: nothing to compare)' -ForegroundColor Yellow }
  foreach ($g in $top) {
    $ruleAll = @($g.Group | ForEach-Object { if ($_.message -match "Unit '([^']+)'") { $Matches[1] } } | Sort-Object -Unique)
    $ruleProj = @($ruleAll | Where-Object { $stems.ContainsKey($_.ToLowerInvariant()) })
    $libOnly = $ruleAll.Count - $ruleProj.Count
    $v = VerbUnused $YadfDb $g.Name
    $onlyRule = @($ruleProj | Where-Object { $v -notcontains $_ })
    $onlyVerb = @($v | Where-Object { $ruleProj -notcontains $_ })
    Write-Host ("  {0}: rule={1} (project units {2}, library units {3} -- documented: the verb audits project units only) verb={4} only-rule={5} only-verb={6}" -f (Split-Path $g.Name -Leaf), $ruleAll.Count, $ruleProj.Count, $libOnly, $v.Count, $onlyRule.Count, $onlyVerb.Count)
    if ($onlyRule.Count -gt 0) { Write-Host ("      only-rule (verb credits via a bound reference the rule ignores): " + ($onlyRule -join ', ')) -ForegroundColor DarkGray }
    if ($onlyVerb.Count -gt 0) { Write-Host ("      only-verb (documented: the rule skips side-effect units and units with no exports, and credits DFM / helper member / receiver-type uses the verb does not look at): " + ($onlyVerb -join ', ')) -ForegroundColor DarkGray }
    Check ("{0}: the verb misses none of the rule's project-unit findings" -f (Split-Path $g.Name -Leaf)) ($onlyRule.Count -eq 0) "only-rule=$($onlyRule.Count) of $($ruleProj.Count)"
  }
}
try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (scratch not removed: $WorkDir)" }
if ($script:Failed) { Write-Host 'run_v152_USESAUD_parity: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_USESAUD_parity: all checks passed' -ForegroundColor Green
exit 0
