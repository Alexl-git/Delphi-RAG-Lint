# Guard: pp_directives (150 PP) -- the extractor records every $DEFINE / $UNDEF /
# IFDEF / IFNDEF / IF / ELSEIF / $I directive of a file's own text (file,
# ordinal, line, col, offset, symbol, and the pp_regions branch it sits in), and
# the two directive lint rules (ifdef-undefined-symbol, platform-divergent-define)
# read a CURRENT file's own directives from that table instead of re-lexing it.
#
# (a) EXTRACTOR: `index` a fixture project, `sql` the table: the 9 expected rows
#     of U.pas with their symbol / line / col / region / branch. RED on an engine
#     that does not write the table (the 1.49.0-alpha base: no such table).
# (b) CONSUMER, IDENTITY: lint-all with the table (default) and with the scan
#     (DRAGLINT_PP_TABLE=0) gives byte-identical findings for both rules, and the
#     findings are the expected ones (absolute line/col values = the positive
#     control: a table path that got a column wrong fails here, not only in
#     the A/B). DRAGLINT_PP_TRACE=1 proves which path ran: 'table' for U.pas by
#     default, 'scan' under DRAGLINT_PP_TABLE=0, 'scan' once U.pas is touched
#     (stale stamp -> fallback), 'scan' for a file with no directive rows.
# (c) FALLBACK on a DB without the table (indexed by -BaseExe when given):
#     'scan', same findings.
#
# Usage: pwsh -File tests/autotest/run_pp_directives.ps1 [-Exe <path>] [-BaseExe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $BaseExe = '',
    [string] $WorkDir = "$env:TEMP\drag-lint-pp-directives-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# EUREKALOG: Base_Win32 only (divergent, and project-defined for the union).
$dproj = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup><MainSource>P.dpr</MainSource></PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''"><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="('$(Platform)'=='Win32' and '$(Base)'=='true') or '$(Base_Win32)'!=''"><Base_Win32>true</Base_Win32><CfgParent>Base</CfgParent><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Base)'=='true') or '$(Base_Win64)'!=''"><Base_Win64>true</Base_Win64><CfgParent>Base</CfgParent><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="'$(Base_Win32)'!=''"><DCC_Define>EUREKALOG;$(DCC_Define)</DCC_Define></PropertyGroup>
    <ItemGroup><DCCReference Include="U.pas"/><DCCReference Include="U2.pas"/></ItemGroup>
    <ProjectExtensions><BorlandProject><Platforms>
        <Platform value="Win32">True</Platform>
        <Platform value="Win64">True</Platform>
    </Platforms></BorlandProject></ProjectExtensions>
</Project>
'@
# Line numbers and columns are load-bearing (see $expRows / $expUndef).
$unit = @'
unit U;

interface

{$I Defs.inc}
{$IFDEF EUREKALOG}
{$DEFINE LOCALDEF}
{$ELSE}
{$UNDEF GONE}
{$ENDIF}

implementation

{$IFDEF EUREKALGO}
{$ENDIF}
{$IFNDEF LOCALDEF} {$ENDIF}
{$IF defined(INCDEF) or defined(NOWHEREB)}
{$ELSEIF defined(NOWHEREC)}
{$IFEND}
procedure X;
begin
  {$IFDEF NOWHERED} {$ENDIF}
end;

end.
'@
$d = Join-Path $WorkDir 'app'
New-Item -ItemType Directory $d | Out-Null
Write-Ascii (Join-Path $d 'P.dproj') $dproj
Write-Ascii (Join-Path $d 'P.dpr') "program P;`n`nuses`n  U in 'U.pas',`n  U2 in 'U2.pas';`n`nbegin`nend.`n"
Write-Ascii (Join-Path $d 'U.pas') $unit
Write-Ascii (Join-Path $d 'U2.pas') "unit U2;`n`ninterface`n`nimplementation`n`nend.`n"
Write-Ascii (Join-Path $d 'Defs.inc') "{`$DEFINE INCDEF}`n"
$proj = Join-Path $d 'P.dproj'
$upas = Join-Path $d 'U.pas'

function Sql-Rows([string]$Db, [string]$Q) {
  $raw = (& $Exe sql --query $Q --db $Db --json 2>$null) -join "`n"
  $s = $raw.IndexOf('{')
  if ($s -lt 0) { return $null }
  $o = $raw.Substring($s) | ConvertFrom-Json
  return ,@($o.rows)
}
function Lint-All([string]$Db, [string]$Rule, [hashtable]$Env = @{}) {
  foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
  try {
    $errFile = Join-Path $WorkDir 'trace.txt'
    # DRAGLINT_PP_TRACE='1' is ALSO read by the preprocessor as a trace FILE PATH: a file named '1' lands in the cwd (150 H1).
    Push-Location $WorkDir
    try { $raw = (& $Exe lint-all --db $Db --project $proj --rule $Rule --json 2>$errFile) -join "`n" } finally { Pop-Location }
    $trace = if (Test-Path $errFile) { (Get-Content $errFile) -join "`n" } else { '' }
  } finally {
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $null) }
  }
  $start = $raw.IndexOf('[')
  $arr = if ($start -ge 0) { @($raw.Substring($start) | ConvertFrom-Json) } else { @() }
  $f = @($arr | Where-Object { $_.rule -eq $Rule } | ForEach-Object {
    '{0}:{1}:{2} {3}' -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.start_col, $_.message })
  return [pscustomobject]@{ Findings = $f; Text = ($f -join "`n"); Trace = $trace }
}

Write-Host '(a) extractor: pp_directives rows of U.pas' -ForegroundColor Cyan
$db = Join-Path $WorkDir 'p.sqlite'
& $Exe index --project $proj --db $db 2>&1 | Out-Null
$rows = Sql-Rows $db ("SELECT d.ordinal, d.directive, d.symbol, d.line, d.col, d.region, d.branch FROM pp_directives d " +
  "JOIN files f ON f.id = d.file_id WHERE f.path LIKE '%U.pas' ORDER BY d.ordinal")
Check 'table exists and U.pas has rows' ($null -ne $rows -and $rows.Count -gt 0) ("rows=" + $(if ($rows) { $rows.Count } else { 'none' }))
# ordinal|directive|symbol|line|col|region|branch (rows are positional arrays)
$expRows = @(
  '0|i||5|1|-1|-1', '1|ifdef|EUREKALOG|6|1|0|0', '2|define|LOCALDEF|7|1|0|0', '3|undef|GONE|9|1|0|1',
  '4|ifdef|EUREKALGO|14|1|1|0', '5|ifndef|LOCALDEF|16|1|2|0', '6|if||17|1|3|0', '7|elseif||18|1|3|1',
  '8|ifdef|NOWHERED|22|3|4|0')
$got = if ($rows) { @($rows | ForEach-Object { ($_ | ForEach-Object { "$_" }) -join '|' }) } else { @() }
foreach ($g in $got) { Write-Host "    $g" -ForegroundColor DarkGray }
Check 'the 9 expected rows (directive, symbol, line, col, region, branch)' ((($got -join ';') -eq ($expRows -join ';'))) ''
$u2 = Sql-Rows $db "SELECT COUNT(*) FROM pp_directives d JOIN files f ON f.id = d.file_id WHERE f.path LIKE '%U2.pas'"
Check 'a file with no directive has no rows' ($null -ne $u2 -and "$($u2[0][0])" -eq '0') ''

Write-Host '(b) consumer: lint-all table path == scan path' -ForegroundColor Cyan
$expUndef = @(
  'U.pas:14:1 *EUREKALGO*EUREKALOG*', 'U.pas:17:1 *NOWHEREB*', 'U.pas:18:1 *NOWHEREC*', 'U.pas:22:3 *NOWHERED*')
foreach ($rule in @('ifdef-undefined-symbol', 'platform-divergent-define')) {
  $t = Lint-All $db $rule @{ DRAGLINT_PP_TRACE = '1' }
  $s = Lint-All $db $rule @{ DRAGLINT_PP_TRACE = '1'; DRAGLINT_PP_TABLE = '0' }
  foreach ($x in $t.Findings) { Write-Host "    $x" -ForegroundColor DarkGray }
  Check "$rule : findings identical, table vs scan" ($t.Text -eq $s.Text -and $t.Findings.Count -gt 0) ("n=" + $t.Findings.Count)
  Check "$rule : U.pas read from the table" ($t.Trace -match 'pp-directives: table \S*U\.pas rows=9') ''
  Check "$rule : U2.pas (no rows) scanned" ($t.Trace -match 'pp-directives: scan \S*U2\.pas rows=0') ''
  Check "$rule : DRAGLINT_PP_TABLE=0 scans U.pas" ($s.Trace -match 'pp-directives: scan \S*U\.pas' -and $s.Trace -notmatch 'pp-directives: table') ''
  if ($rule -eq 'ifdef-undefined-symbol') {
    $ok = $t.Findings.Count -eq $expUndef.Count
    for ($i = 0; $ok -and $i -lt $expUndef.Count; $i++) { $ok = $t.Findings[$i] -like $expUndef[$i] }
    Check 'ifdef-undefined-symbol : the 4 expected findings at their line:col' $ok ''
    $ifdefTable = $t
  } else {
    Check 'platform-divergent-define : EUREKALOG at U.pas:6:1' ($t.Findings.Count -eq 1 -and $t.Findings[0] -like 'U.pas:6:1 *EUREKALOG*') ''
  }
}
# A stale stamp falls back to the scan (touch U.pas: same bytes, new mtime).
(Get-Item $upas).LastWriteTime = (Get-Date).AddMinutes(5)
$st = Lint-All $db 'ifdef-undefined-symbol' @{ DRAGLINT_PP_TRACE = '1' }
Check 'stale U.pas -> scan fallback, same findings' ($st.Trace -match 'pp-directives: scan \S*U\.pas' -and $st.Text -eq $ifdefTable.Text) ''

if ($BaseExe -and (Test-Path $BaseExe)) {
  Write-Host '(c) a DB without pp_directives (indexed by -BaseExe): scan, same findings' -ForegroundColor Cyan
  $db0 = Join-Path $WorkDir 'p0.sqlite'
  & $BaseExe index --project $proj --db $db0 2>&1 | Out-Null
  $b = Lint-All $db0 'ifdef-undefined-symbol' @{ DRAGLINT_PP_TRACE = '1' }
  Check 'no table -> scan' ($b.Trace -match 'pp-directives: scan \S*U\.pas' -and $b.Trace -notmatch 'pp-directives: table') ''
  Check 'no table -> same findings' ($b.Text -eq $ifdefTable.Text) ''
}

if ($script:Failed) { Write-Host 'FAIL run_pp_directives' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_pp_directives' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
