# Guard: pp_trace_env (151 PP) -- DRAGLINT_PP_TRACE has ONE reader (PPTracePath in
# DRagLint.Preprocess) used by BOTH callers (the IF evaluator and the directive
# lint rules). '' = off; 1 / true / yes (any case) = a FLAG: the trace goes to
# %TEMP%\drag-lint-pp-trace.log (+ one stderr NOTE); anything else = a file path.
#
# Arms (each in a private cwd and a private TEMP):
#  (flag) value '1' / 'TRUE': NO file of that name in cwd; the TEMP log holds BOTH an
#         IF line (index) and a 'pp-directives:' line (lint-all); a stderr NOTE.
#         RED on the 1.49 base: file '1' created in cwd, nothing in TEMP.
#  (path) value = a path: both kinds of line land in THAT file; no TEMP log, no NOTE.
#  (off)  unset: no trace anywhere. Positive control: the other arms DO write, so an
#         empty result here is not vacuous.
# Usage: pwsh -File tests/autotest/run_pp_trace_env.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-pp-trace-env-$PID"
)
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
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
$proj = Join-Path $WorkDir 'P.dproj'
Write-Ascii $proj @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup><MainSource>P.dpr</MainSource></PropertyGroup>
    <ItemGroup><DCCReference Include="U.pas"/></ItemGroup>
    <ProjectExtensions><BorlandProject><Platforms>
        <Platform value="Win64">True</Platform>
    </Platforms></BorlandProject></ProjectExtensions>
</Project>
'@
Write-Ascii (Join-Path $WorkDir 'P.dpr') "program P;`nuses U in 'U.pas';`nbegin`nend."
Write-Ascii (Join-Path $WorkDir 'U.pas') @'
unit U;

interface

{$IF Defined(NOWHERE_A) and (CompilerVersion > 20)}
const A = 1;
{$ENDIF}
{$IFDEF NOWHERE_B}
const B = 2;
{$ENDIF}

implementation

end.
'@

# Runs index + lint-all with the env value; reports cwd listing, TEMP log, path file, stderr.
function Run-Arm([string]$Name, [string]$Value, [string]$PathFile = '') {
  $cwd = Join-Path $WorkDir "cwd-$Name"; $tmp = Join-Path $WorkDir "tmp-$Name"
  New-Item -ItemType Directory $cwd, $tmp | Out-Null
  $db = Join-Path $cwd 'p.sqlite'
  $errFile = Join-Path $cwd 'stderr.txt'
  $savedTemp = $env:TEMP; $savedTmp = $env:TMP
  $env:TEMP = $tmp; $env:TMP = $tmp
  [Environment]::SetEnvironmentVariable('DRAGLINT_PP_TRACE', $(if ($Value -ne '') { $Value } else { $null }))
  Push-Location $cwd
  try {
    & $Exe index --project $proj --db $db 2>>$errFile | Out-Null
    & $Exe lint-all --db $db --project $proj --rule ifdef-undefined-symbol --json 2>>$errFile | Out-Null
  } finally {
    Pop-Location
    [Environment]::SetEnvironmentVariable('DRAGLINT_PP_TRACE', $null)
    $env:TEMP = $savedTemp; $env:TMP = $savedTmp
  }
  $log = Join-Path $tmp 'drag-lint-pp-trace.log'
  [pscustomobject]@{
    CwdFiles = @(Get-ChildItem $cwd -File | ForEach-Object Name)
    TempLog  = $(if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { $null })
    PathText = $(if ($PathFile -and (Test-Path $PathFile)) { [IO.File]::ReadAllText($PathFile) } else { $null })
    Stderr   = $(if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' })
  }
}
function Has-Both($Text) { $null -ne $Text -and $Text -match 'pp-directives: ' -and $Text -match 'NOWHERE_A' }

foreach ($v in @('1', 'TRUE')) {
  Write-Host "(flag) DRAGLINT_PP_TRACE=$v" -ForegroundColor Cyan
  $r = Run-Arm "flag$v" $v
  Check "no file named '$v' in cwd" ($r.CwdFiles -notcontains $v) ("cwd=" + ($r.CwdFiles -join ','))
  Check 'TEMP log has an IF line (index) and a pp-directives line (lint-all)' (Has-Both $r.TempLog) ''
  Check 'a stderr NOTE names the log' ($r.Stderr -match 'NOTE: DRAGLINT_PP_TRACE' -and $r.Stderr -match 'drag-lint-pp-trace\.log') ''
}
Write-Host '(path) DRAGLINT_PP_TRACE=<file>' -ForegroundColor Cyan
$pf = Join-Path $WorkDir 'mytrace.tsv'
$r = Run-Arm 'path' $pf $pf
Check 'trace file has an IF line and a pp-directives line' (Has-Both $r.PathText) ''
Check 'no TEMP log, no NOTE' ($null -eq $r.TempLog -and $r.Stderr -notmatch 'NOTE: DRAGLINT_PP_TRACE') ''
Write-Host '(off) unset' -ForegroundColor Cyan
$r = Run-Arm 'off' ''
Check 'no TEMP log, no trace file in cwd' ($null -eq $r.TempLog -and @($r.CwdFiles | Where-Object { $_ -match 'trace' -and $_ -ne 'stderr.txt' }).Count -eq 0) ''

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'FAIL run_pp_trace_env' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_pp_trace_env' -ForegroundColor Green
