<#
  run_v151_STRAY_library_refusals.ps1 -- v151 STRAY (OQ14): a project may not live under a
  library root, and a library database is never a project index's write target.

  Fixture: built under a temp dir; a private manifest names ONE library section (include 'lib')
  and the run uses DRAGLINT_MANIFEST, so no real library or project database is touched.

  Cases
    A1  index --project lib\sub\Bad.dproj exits 2                      (RED before STRAY: exit 0)
    A2  ... and the message names the project path, the library root and the fix
    A3  ... and no database file was created
    B1  index --project ok\Good.dproj --db <dir>\library-Win64.sqlite exits 2   (RED before STRAY)
    B2  ... message says library database and names the path and the resolve-dbs fix
    B3  ... a library-*.sqlite copied from a real file is not modified (size/mtime kept)
    C1  control: index --project ok\Good.dproj --db good.sqlite exits 0 and creates it
    C2  control: index lib --db library-Win64.sqlite (a FOLDER index) still exits 0
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-stray-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [IO.File]::WriteAllText($path, (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object Text.ASCIIEncoding))
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory "$WorkDir\OUT" -Force | Out-Null

$unit = "unit {0};`ninterface`nprocedure {0}Proc;`nimplementation`nprocedure {0}Proc;`nbegin`nend;`nend.`n"
$dpr  = "program {0};`nuses`n  {0}U in '{0}U.pas';`nbegin`nend.`n"
$dproj = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>NAME.dpr</MainSource><Config Condition="'$(Config)'==''">Debug</Config><Base>true</Base></PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="NAME.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="NAMEU.pas"/>
  </ItemGroup>
</Project>
'@
WriteAnsi "$WorkDir\lib\LibU.pas" ($unit -f 'LibU')
foreach ($p in @(@('lib\sub', 'Bad'), @('ok', 'Good'))) {
  $d = Join-Path $WorkDir $p[0]; $n = $p[1]
  WriteAnsi "$d\${n}U.pas" ($unit -f "${n}U")
  WriteAnsi "$d\$n.dpr" ($dpr -f $n)
  WriteAnsi "$d\$n.dproj" ($dproj.Replace('NAME', $n))
}
$manifest = [ordered]@{
  settings = [ordered]@{ defaultPlatform = 'Win64' }
  indexes  = [ordered]@{ outDir = 'OUT'; exclude = @(); sections = @(
    [ordered]@{ name = 'Library'; db = 'library-{platform}.sqlite'; source = 'registry-libraries'; platforms = @('Win64'); include = @('lib') }) }
}
$mf = Join-Path $WorkDir 'drag-lint.json'
[IO.File]::WriteAllText($mf, ($manifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

function Run-Engine([string[]]$EngineArgs) {
  $env:DRAGLINT_MANIFEST = $mf
  Push-Location $WorkDir
  try {
    $o = (& { $ErrorActionPreference = 'Continue'; & $Exe @EngineArgs 2>&1 | ForEach-Object { "$_" } } | Out-String)
    return @{ Out = $o; Code = $LASTEXITCODE }
  } finally { Pop-Location; $env:DRAGLINT_MANIFEST = $null }
}

Write-Host 'A: a project under a library root' -ForegroundColor Cyan
$a = Run-Engine @('index', '--project', "$WorkDir\lib\sub\Bad.dproj", '--db', "$WorkDir\OUT\bad.sqlite")
Check 'A1 exit 2' ($a.Code -eq 2) "code=$($a.Code)"
Check 'A2 names the project, the library root and the fix' (($a.Out -match 'Bad\.dproj') -and ($a.Out -match 'library root') -and ($a.Out -match 'Move the project')) "got: [$($a.Out)]"
Check 'A3 no database created' (-not (Test-Path "$WorkDir\OUT\bad.sqlite"))

Write-Host 'B: a library database as a project DB' -ForegroundColor Cyan
$libDb = "$WorkDir\OUT\library-Win64.sqlite"
[IO.File]::WriteAllBytes($libDb, [byte[]](1..64))
$before = Get-Item $libDb
$b = Run-Engine @('index', '--project', "$WorkDir\ok\Good.dproj", '--db', $libDb)
Check 'B1 exit 2' ($b.Code -eq 2) "code=$($b.Code)"
Check 'B2 says library database, names the path and the resolve-dbs fix' (($b.Out -match 'library database') -and ($b.Out -match 'library-Win64\.sqlite') -and ($b.Out -match 'resolve-dbs --project')) "got: [$($b.Out)]"
$after = Get-Item $libDb
Check 'B3 library file untouched' (($before.Length -eq $after.Length) -and ($before.LastWriteTimeUtc -eq $after.LastWriteTimeUtc))

Write-Host 'C: controls' -ForegroundColor Cyan
$c1 = Run-Engine @('index', '--project', "$WorkDir\ok\Good.dproj", '--db', "$WorkDir\OUT\good.sqlite")
Check 'C1 a normal project index exits 0 and writes its DB' (($c1.Code -eq 0) -and (Test-Path "$WorkDir\OUT\good.sqlite")) "code=$($c1.Code) out=[$($c1.Out)]"
[IO.File]::Delete($libDb)
$c2 = Run-Engine @('index', "$WorkDir\lib", '--db', $libDb)
Check 'C2 a FOLDER index into library-Win64.sqlite still works' (($c2.Code -eq 0) -and (Test-Path $libDb)) "code=$($c2.Code) out=[$($c2.Out)]"
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; $script:Failed = $true }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green; exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
