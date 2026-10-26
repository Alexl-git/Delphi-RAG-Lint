<#
  run_parsecache_profile_resolver_guard.ps1 -- TAstParseCache consults a per-file
  profile resolver (LSP C10 / A7-L, Task 2; wired into `lint` by Task 3).

  Fixture: proj\App.dproj marks Config=Debug and Debug defines MYFEATURE; proj\uUnit.pas
  is in the project and holds garbage inside {$IFNDEF MYFEATURE}; other\uLoose.pas has
  the same body but no project. Via `lint <file> --json --db proj\_D-RAG\App.sqlite`
  (NO --project):
    a  uUnit.pas  -> 0 parser-error (MYFEATURE is on under the active Debug config)
    b  uLoose.pas -> >= 1 parser-error (POSITIVE CONTROL: built-ins, MYFEATURE off)
    c  uUnit.pas --project App.dproj --no-preprocess -> >= 1 (SETUP: the fixture needs
       the preprocessor)
    d  with-statement still on its original line in (a) (length-preserving)
  Task 2 adds only the hook, so this guard is EXPECTED RED until Task 3 installs the
  resolver in `lint`; it is GREEN after Task 3.

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-pc-resolver-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force "$WorkDir\proj\_D-RAG", "$WorkDir\other" | Out-Null

$dproj = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{11111111-2222-3333-4444-555555555555}</ProjectGuid>
        <Config Condition="'`$(Config)'==''">Debug</Config>
        <Platform Condition="'`$(Platform)'==''">Win32</Platform>
        <MainSource>App.dpr</MainSource>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Base' or '`$(Base)'!=''">
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Debug' or '`$(Cfg_1)'!=''">
        <CfgParent>Base</CfgParent>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Release' or '`$(Cfg_2)'!=''">
        <CfgParent>Base</CfgParent>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_1)'!=''">
        <DCC_Define>MYFEATURE;`$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_2)'!=''">
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="uUnit.pas"/>
    </ItemGroup>
</Project>
"@
Write-Ascii "$WorkDir\proj\App.dproj" ($dproj -replace "`r?`n", "`r`n")
Write-Ascii "$WorkDir\proj\App.dpr" "program App;`r`nuses uUnit in 'uUnit.pas';`r`nbegin`r`nend.`r`n"

function New-Body([string]$Unit) {
  $lines = @(
    "unit $Unit;", '', 'interface', '', 'function CurDir: string;', 'procedure Other(X: TObject);', '',
    'implementation', '', 'function CurDir: string;', 'begin',
    '{$IFNDEF MYFEATURE}', '  Result := := ) ;', '{$ENDIF}', "  Result := 'C:\';", 'end;', '',
    'procedure Other(X: TObject);', 'begin', '  X.Free;', '  X := nil;', '', '', '', '',
    '  with X do Free;', 'end;', '', 'end.'
  )
  return (($lines -join "`r`n") + "`r`n")
}
Write-Ascii "$WorkDir\proj\uUnit.pas"   (New-Body 'uUnit')
Write-Ascii "$WorkDir\other\uLoose.pas" (New-Body 'uLoose')
$WithLine = ((Get-Content "$WorkDir\proj\uUnit.pas") | Select-String -SimpleMatch 'with X do Free').LineNumber
$Db = "$WorkDir\proj\_D-RAG\App.sqlite"

$idx = (& $Exe index --project "$WorkDir\proj\App.dproj" --db $Db 2>&1 | Out-String)
$files = if ($idx -match 'Files:\s*(\d+)') { [int]$Matches[1] } else { 0 }
Check 'SETUP project index built' ($files -ge 2) "files=$files"

function LintRule([string]$File, [string]$Rule, [string[]]$Extra = @()) {
  $out = & $Exe lint $File --json --db $Db @Extra 2>$null | Out-String
  $j = @($out | ConvertFrom-Json)
  return @($j | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
}

$a = LintRule "$WorkDir\proj\uUnit.pas" 'parser-error'
Check 'a uUnit.pas: 0 parser-error (active Debug config)' ($a.Count -eq 0) "lines=$($a -join ',')"
$b = LintRule "$WorkDir\other\uLoose.pas" 'parser-error'
Check 'b uLoose.pas: >= 1 parser-error (POSITIVE CONTROL)' ($b.Count -ge 1) "lines=$($b -join ',')"
$c = LintRule "$WorkDir\proj\uUnit.pas" 'parser-error' @('--project', "$WorkDir\proj\App.dproj", '--no-preprocess')
Check 'c --no-preprocess: >= 1 parser-error (SETUP)' ($c.Count -ge 1) "lines=$($c -join ',')"
$d = LintRule "$WorkDir\proj\uUnit.pas" 'with-statement'
Check "d with-statement on line $WithLine" ($d -contains $WithLine) "lines=$($d -join ',')"
}
catch { Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red; $script:Failed = $true }
finally {
  try { if ($WorkDir -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { Write-Host 'run_parsecache_profile_resolver_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_parsecache_profile_resolver_guard: PASS' -ForegroundColor Green
exit 0
