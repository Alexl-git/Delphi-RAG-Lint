# E-UNWITH-EXCLUDE (wave 146 rk): `index --project X.dproj --exclude-under <dir>` must keep
# a search-path unit under <dir> out of the project index. Before, DoIndex registered the
# root but the project scope list went to IndexFile, which never asks the exclude roots.
param([string] $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
try {
$Exe = . "$PSScriptRoot\_manifest_common.ps1" -Exe $Exe
$ErrorActionPreference = 'Continue'
$work = Join-Path $env:TEMP ('draglint_idx_exclude_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$work\app","$work\lib","$work\libx" | Out-Null
$crlf = "`r`n"
[IO.File]::WriteAllText("$work\lib\LibU.pas", "unit LibU;${crlf}interface${crlf}procedure LibProc;${crlf}implementation${crlf}procedure LibProc; begin end;${crlf}end.${crlf}")
[IO.File]::WriteAllText("$work\libx\LibX.pas", "unit LibX;${crlf}interface${crlf}procedure LibXProc;${crlf}implementation${crlf}procedure LibXProc; begin end;${crlf}end.${crlf}")
[IO.File]::WriteAllText("$work\app\App.dpr", "program App;${crlf}uses LibU, LibX;${crlf}begin${crlf} LibProc;${crlf} LibXProc;${crlf}end.${crlf}")
[IO.File]::WriteAllText("$work\app\App.dproj", '<?xml version="1.0" encoding="utf-8"?><Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup><MainSource>App.dpr</MainSource><DCC_UnitSearchPath>..\lib;..\libx;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup><ItemGroup><DelphiCompile Include="App.dpr"><MainSource>MainSource</MainSource></DelphiCompile></ItemGroup></Project>')
function Files($db) { & $Exe sql --db $db --query "select path from files" 2>&1 | Out-String }

$plain = "$work\plain.sqlite"
& $Exe index --project "$work\app\App.dproj" --db $plain 2>&1 | Out-Null
$t = Files $plain
Check 'POSITIVE CONTROL: without the flag both lib units are indexed' (($t -match 'LibU\.pas') -and ($t -match 'LibX\.pas'))

$ex = "$work\ex.sqlite"
& $Exe index --project "$work\app\App.dproj" --db $ex --exclude-under "$work\lib" 2>&1 | Out-Null
$t = Files $ex
Check 'excluded subtree: LibU.pas NOT indexed' ($t -notmatch 'LibU\.pas')
Check 'sibling prefix libx (not under lib\) still indexed' ($t -match 'LibX\.pas')
Check 'project file still indexed' ((Files $ex) -match 'App\.dpr')

# Reindex of the PLAIN db: an already-indexed unit is outside every eviction root, so only --rebuild drops it (existing, documented).
& $Exe index --project "$work\app\App.dproj" --db $plain --rebuild --exclude-under "$work\lib" 2>&1 | Out-Null
Check '--rebuild with the flag drops a previously indexed LibU.pas' ((Files $plain) -notmatch 'LibU\.pas')
} finally { if ($work -and (Test-Path $work)) { [IO.Directory]::Delete($work, $true) } }
if ($script:Failed) { Write-Host 'FAIL run_index_project_exclude_under' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_index_project_exclude_under' -ForegroundColor Green
