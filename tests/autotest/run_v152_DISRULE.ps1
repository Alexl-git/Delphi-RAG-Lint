<#
  run_v152_DISRULE.ps1 -- 1.52 "Disable rule" (ruling B4 part 3, PLAN section 5 D1):
  `drag-lint rules disable|enable --rule <id> --scope line|unit|project`.

  Fixture: two "projects" in a temp folder.
    projA\App.dproj (dummy), projA\FxA.pas, projA\FxB.pas, projA\drag-lint-lint.json (has a
    "disabled" key that must survive every edit); projB\FxC.pas + its own drag-lint-lint.json.
    Every Fx unit has the rule R = empty-except on two lines (18 and 28) and
    try-except-swallowed on the same lines (a second rule that no scope may touch).

  Per scope: the finding is gone, the twin finding OUTSIDE the scope still fires (positive
  control), the written marker / config is 7-bit ASCII + CRLF, and `rules enable` restores.
    line    : marker on FxA:18 (written through the --file alias; every other call uses --in) -> FxA:18 silent, FxA:28 still fires; enable -> FxA byte-identical.
    unit    : exclude_units [FxA] -> FxA silent, FxB still fires; enable -> entry gone.
    project : "enabled": false -> FxA + FxB silent, projB\FxC still fires, the other rule still
              fires in FxA; enable -> both fire again.
  Plus usage errors (exit 2) and "nothing to undo" (exit 1).
  Against the 1.52 FRAME stub every `rules disable` exits 2 -> the first check FAILS (RED).

  Usage: pwsh -File tests\autotest\run_v152_DISRULE.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-disrule-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$ProjA = Join-Path $Work 'projA'
$ProjB = Join-Path $Work 'projB'
[void](New-Item -ItemType Directory -Force $ProjA)
[void](New-Item -ItemType Directory -Force $ProjB)
$R = 'empty-except'
$Other = 'try-except-swallowed'
$Today = (Get-Date).ToString('yyyy-MM-dd')

function UnitText([string]$Name) {
  $L = @("unit $Name;", '', 'interface', '', 'procedure DoIt(A: Integer);', 'procedure DoTwo(A: Integer);', '',
    'implementation', '', 'uses SysUtils;', '',
    'procedure DoIt(A: Integer);', 'var', '  X: Integer;', 'begin', '  try', '    X:= A div 2;', '  except', '  end;', 'end;', '',
    'procedure DoTwo(A: Integer);', 'var', '  X: Integer;', 'begin', '  try', '    X:= A div 3;', '  except', '  end;', 'end;', '',
    'end.', '')
  return ($L -join "`r`n")
}
function WriteAscii([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::ASCII) }

$FxA = Join-Path $ProjA 'FxA.pas'; $FxB = Join-Path $ProjA 'FxB.pas'; $FxC = Join-Path $ProjB 'FxC.pas'
$CfgA = Join-Path $ProjA 'drag-lint-lint.json'; $CfgB = Join-Path $ProjB 'drag-lint-lint.json'
$Dproj = Join-Path $ProjA 'App.dproj'
WriteAscii $FxA (UnitText 'FxA'); WriteAscii $FxB (UnitText 'FxB'); WriteAscii $FxC (UnitText 'FxC')
WriteAscii $Dproj "<Project/>`r`n"
WriteAscii $CfgA "{`r`n  `"disabled`": [`"magic-literal`"]`r`n}`r`n"
WriteAscii $CfgB "{}`r`n"
$FxAOriginal = [IO.File]::ReadAllBytes($FxA)

$Pass = 0; $Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
# lint --json is a bare ARRAY; the rule field is "rule", the line "start_line".
function Lines([string]$File, [string]$Cfg, [string]$Rule) {
  Push-Location $Work
  try { $Out = & { $ErrorActionPreference = 'Continue'; & $Exe lint $File --config $Cfg --json 2>$null } } finally { Pop-Location }
  $Txt = ($Out -join "`n")
  if ($Txt.Trim() -eq '') { return ,@() }
  return ,@(@($Txt | ConvertFrom-Json) | Where-Object { [string]$_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
}
function Dl([string[]]$A) {
  Push-Location $Work
  try { $Out = & { $ErrorActionPreference = 'Continue'; & $Exe @A 2>&1 | ForEach-Object { "$_" } }; $Code = $LASTEXITCODE } finally { Pop-Location }
  $script:LastOut = ($Out | ForEach-Object { "$_" }) -join "`n"
  return $Code
}
# 7-bit ASCII, every LF preceded by CR, no BOM.
function IsAsciiCrlf([string]$Path) {
  $B = [IO.File]::ReadAllBytes($Path)
  for ($i = 0; $i -lt $B.Length; $i++) {
    if ($B[$i] -gt 127) { return $false }
    if (($B[$i] -eq 10) -and (($i -eq 0) -or ($B[$i - 1] -ne 13))) { return $false }
  }
  return $true
}

try {
  # --- baseline (positive control for everything below) ---
  $BaseA = Lines $FxA $CfgA $R
  Check 'baseline: R fires on FxA:18 and FxA:28' ((($BaseA -contains 18) -and ($BaseA -contains 28))) "got $($BaseA -join ',')"
  Check 'baseline: R fires on FxB' ((Lines $FxB $CfgA $R).Count -eq 2) ''
  Check 'baseline: the other rule fires on FxA' ((Lines $FxA $CfgA $Other).Count -gt 0) ''

  # --- line scope ---
  $C = Dl @('rules', 'disable', '--rule', $R, '--scope', 'line', '--file', $FxA, '--line', '18', '--reason', 'probe reviewed')
  Check 'line: disable exits 0' ($C -eq 0) "exit $C out: $LastOut"
  $Line18 = ([IO.File]::ReadAllText($FxA) -split "`r`n")[17]
  Check 'line: marker written on line 18 with the v2 hash' ($Line18 -match ('dl:ok ' + [regex]::Escape($R) + '@[0-9a-f]{4}')) "line: $Line18"
  Check 'line: marker carries REVIEWED <today> and the reason' ($Line18 -match ('REVIEWED ' + $Today + '.*probe reviewed')) "line: $Line18"
  Check 'line: file stays 7-bit ASCII + CRLF' (IsAsciiCrlf $FxA) ''
  $AfterA = Lines $FxA $CfgA $R
  Check 'line: R on FxA:18 gone' (-not ($AfterA -contains 18)) "got $($AfterA -join ',')"
  Check 'line: twin R on FxA:28 still fires' ($AfterA -contains 28) "got $($AfterA -join ',')"
  Check 'line: config untouched by a line-scope disable' (-not ([IO.File]::ReadAllText($CfgA) -match 'rule_overrides')) ''
  $C = Dl @('rules', 'enable', '--rule', $R, '--scope', 'line', '--in', $FxA, '--line', '18')
  Check 'line: enable exits 0' ($C -eq 0) "exit $C out: $LastOut"
  Check 'line: enable restores FxA byte-identical' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($FxA)) -eq [Convert]::ToBase64String($FxAOriginal)) ''
  Check 'line: R on FxA:18 fires again' ((Lines $FxA $CfgA $R) -contains 18) ''
  $C = Dl @('rules', 'enable', '--rule', $R, '--scope', 'line', '--in', $FxA, '--line', '18')
  Check 'line: enable with no marker -> exit 1 (nothing to undo)' ($C -eq 1) "exit $C"

  # --- unit scope (config found by walking up from --file) ---
  $C = Dl @('rules', 'disable', '--rule', $R, '--scope', 'unit', '--in', $FxA, '--reason', 'unit probe')
  Check 'unit: disable exits 0' ($C -eq 0) "exit $C out: $LastOut"
  Check 'unit: config stays 7-bit ASCII + CRLF' (IsAsciiCrlf $CfgA) ''
  $J = Get-Content $CfgA -Raw | ConvertFrom-Json
  $E = $J.rule_overrides.$R
  Check 'unit: entry lists FxA in exclude_units' (@($E.exclude_units) -contains 'FxA') ($J | ConvertTo-Json -Depth 5 -Compress)
  Check 'unit: entry stores reason and date' (($E.reason -eq 'unit probe') -and ($E.date -eq $Today)) ''
  Check 'unit: entry has no enabled key' ($null -eq $E.enabled) ''
  Check 'unit: existing "disabled" key preserved' (@($J.disabled) -contains 'magic-literal') ''
  Check 'unit: source not touched' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($FxA)) -eq [Convert]::ToBase64String($FxAOriginal)) ''
  Check 'unit: R gone in FxA' ((Lines $FxA $CfgA $R).Count -eq 0) ''
  Check 'unit: twin R in FxB still fires' ((Lines $FxB $CfgA $R).Count -eq 2) ''
  $C = Dl @('rules', 'enable', '--rule', $R, '--scope', 'unit', '--in', $FxA)
  Check 'unit: enable exits 0' ($C -eq 0) "exit $C out: $LastOut"
  $J = Get-Content $CfgA -Raw | ConvertFrom-Json
  Check 'unit: enable removes the emptied entry' ($null -eq $J.rule_overrides) ($J | ConvertTo-Json -Depth 5 -Compress)
  Check 'unit: "disabled" still preserved' (@($J.disabled) -contains 'magic-literal') ''
  Check 'unit: R in FxA fires again' ((Lines $FxA $CfgA $R).Count -eq 2) ''

  # --- project scope (config beside --project) ---
  $C = Dl @('rules', 'disable', '--rule', $R, '--scope', 'project', '--project', $Dproj, '--reason', 'project probe', '--json')
  Check 'project: disable exits 0' ($C -eq 0) "exit $C out: $LastOut"
  $JOut = $null; try { $JOut = $LastOut | ConvertFrom-Json } catch { }
  Check 'project: --json answer names rule, scope and config' (($null -ne $JOut) -and ($JOut.rule -eq $R) -and ($JOut.scope -eq 'project') -and ([string]$JOut.config -like '*drag-lint-lint.json')) "out: $LastOut"
  Check 'project: config stays 7-bit ASCII + CRLF' (IsAsciiCrlf $CfgA) ''
  $J = Get-Content $CfgA -Raw | ConvertFrom-Json
  $E = $J.rule_overrides.$R
  Check 'project: entry says enabled=false with reason and date' (($E.enabled -eq $false) -and ($E.reason -eq 'project probe') -and ($E.date -eq $Today)) ''
  Check 'project: R gone in FxA' ((Lines $FxA $CfgA $R).Count -eq 0) ''
  Check 'project: R gone in FxB' ((Lines $FxB $CfgA $R).Count -eq 0) ''
  Check 'project: the other rule still fires in FxA' ((Lines $FxA $CfgA $Other).Count -gt 0) ''
  Check 'project: twin R in another project still fires' ((Lines $FxC $CfgB $R).Count -eq 2) ''
  $C = Dl @('rules', 'enable', '--rule', $R, '--scope', 'project', '--project', $Dproj)
  Check 'project: enable exits 0' ($C -eq 0) "exit $C out: $LastOut"
  Check 'project: R fires again in FxA and FxB' (((Lines $FxA $CfgA $R).Count -eq 2) -and ((Lines $FxB $CfgA $R).Count -eq 2)) ''
  $J = Get-Content $CfgA -Raw | ConvertFrom-Json
  Check 'project: enable leaves no override behind' ($null -eq $J.rule_overrides) ''
  Check 'project: "disabled" still preserved' (@($J.disabled) -contains 'magic-literal') ''
  # a rule the Lint Options dock wrote into "disabled" is re-enabled too
  $C = Dl @('rules', 'enable', '--rule', 'magic-literal', '--scope', 'project', '--project', $Dproj)
  Check 'project: enable clears the rule from "disabled"' (($C -eq 0) -and -not (@((Get-Content $CfgA -Raw | ConvertFrom-Json).disabled) -contains 'magic-literal')) "exit $C"
  $C = Dl @('rules', 'enable', '--rule', $R, '--scope', 'project', '--project', $Dproj)
  Check 'project: enable with nothing to undo -> exit 1' ($C -eq 1) "exit $C"

  # --- usage errors ---
  Check 'usage: no --rule -> 2' ((Dl @('rules', 'disable', '--scope', 'project', '--project', $Dproj, '--reason', 'x')) -eq 2) ''
  Check 'usage: bad --scope -> 2' ((Dl @('rules', 'disable', '--rule', $R, '--scope', 'world', '--project', $Dproj, '--reason', 'x')) -eq 2) ''
  Check 'usage: line scope without --line -> 2' ((Dl @('rules', 'disable', '--rule', $R, '--scope', 'line', '--in', $FxA, '--reason', 'x')) -eq 2) ''
  Check 'usage: unknown rule -> 2' ((Dl @('rules', 'disable', '--rule', 'no-such-rule-xyz', '--scope', 'project', '--project', $Dproj, '--reason', 'x')) -eq 2) ''
  Check 'usage: disable without --reason -> 2' ((Dl @('rules', 'disable', '--rule', $R, '--scope', 'project', '--project', $Dproj)) -eq 2) ''
  Check 'usage: refused calls wrote nothing' ($null -eq (Get-Content $CfgA -Raw | ConvertFrom-Json).rule_overrides) ''
}
catch { $Fail++; Write-Host "  FAIL  exception: $($_.Exception.Message)" }
finally { try { [IO.Directory]::Delete($Work, $true) } catch { } }

Write-Host "$Pass passed, $Fail failed"
if ($Fail -gt 0) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
