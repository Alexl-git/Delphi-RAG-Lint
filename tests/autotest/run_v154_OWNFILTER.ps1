<#
  run_v154_OWNFILTER.ps1 -- 1.54 lane OWNFILTER: a project lint-all drops the findings located in
  third-party code the project compiles, says how many and why, and never drops the owner's own
  shared units. Wiki: docs\wiki\v154-own-filter.md.

  FIXTURE (repo\app\App.dpr; every unit carries an unused local -- a per-file finding -- and a dead
  public routine -- a project-wide one):
    app\UApp.pas               own
    COMMON\UCommon.pas         own shared unit beside the project (no declaration names it)
    third_party\UTp.pas        vendored folder name, outside the project folder
    app\thirdparty\UTpIn.pas   vendored folder name, inside the project folder
    app\vendor\UVend.pas       'vendor' is not a default name (a vendor is also a supplier)
    lib\ULib.pas               under a manifest Library "include" folder
    reglib\UReg.pas            app2: under a registry library path, reached by the search path, not listed
    reglib\URegListed.pas      same folder, listed in App.dpr and Reg.dpr; includes RegInc.inc
  Run with pwsh 7 from any cwd.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v154-ownfilter-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:N = 0
function Check($n, $ok, $d = '') {
  $script:N++
  Write-Host ("  [{0}] {1} {2}" -f @('FAIL', 'PASS')[[int][bool]$ok], $n, $(if ($ok) { '' } else { $d })) -ForegroundColor @('Red', 'Green')[[int][bool]$ok]
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
function W([string]$Path, [string]$Body) {
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
  [IO.File]::WriteAllText($Path, (($Body -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Unit([string]$Name) { "unit $Name;`n`ninterface`n`nprocedure Do$Name;`n`nimplementation`n`nprocedure Do$Name;`nvar`n  Idle: Integer;`nbegin`nend;`n`nend.`n" }
if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$repo = Join-Path $WorkDir 'repo'; $app = Join-Path $repo 'app'
W "$app\UApp.pas" (Unit 'UApp')
W "$repo\COMMON\UCommon.pas" (Unit 'UCommon')
W "$repo\third_party\UTp.pas" (Unit 'UTp')
W "$app\thirdparty\UTpIn.pas" (Unit 'UTpIn')
W "$app\vendor\UVend.pas" (Unit 'UVend')
W "$repo\lib\ULib.pas" (Unit 'ULib')
W "$repo\reglib\UReg.pas" (Unit 'UReg')
# the include beside a listed unit carries its own unused local
W "$repo\reglib\RegInc.inc" "procedure IncludedDead;`nvar`n  IdleInInc: Integer;`nbegin`nend;`n"
W "$repo\reglib\URegListed.pas" ((Unit 'URegListed') -replace "implementation`n", "implementation`n`n{`$I RegInc.inc}`n")
W "$app\App.dpr" @"
program App;

uses
  UApp in 'UApp.pas',
  UCommon in '..\COMMON\UCommon.pas',
  UTp in '..\third_party\UTp.pas',
  UTpIn in 'thirdparty\UTpIn.pas',
  UVend in 'vendor\UVend.pas',
  ULib in '..\lib\ULib.pas',
  URegListed in '..\reglib\URegListed.pas';

begin
end.
"@
$db   = Join-Path $app '_D-RAG\App.sqlite'
$decl = Join-Path $app '_D-RAG\drag-lint-project.json'
$cfg  = Join-Path $WorkDir 'lint.json'
$rep  = Join-Path $WorkDir 'rep.txt'
W $cfg '{}'
W "$WorkDir\.drag-lint.json" '{ "indexes": { "sections": [ { "name": "Library", "source": "registry-libraries", "platforms": ["Win64"], "include": ["repo\\lib"] } ] } }'
function Run([string[]]$Argv) {
  Push-Location $WorkDir
  try { return (& { $ErrorActionPreference = 'Continue'; & $Exe @Argv 2>&1 | ForEach-Object { "$_" } } | Out-String) } finally { Pop-Location }
}
function LintAll([string[]]$More = @()) { Run (@('lint-all', '--db', $db, '--config', $cfg, '--output', $rep, '--quiet') + $More) }
# 'unused-local' (per file) / 'unused-public-symbol' (project-wide) findings located in unit U
function Hits([string]$Out, [string]$U) { @($Out -split "`r?`n" | Where-Object { $_ -match ('\\' + $U + '\.pas:\d+:\d+\s+\[\w+\]\s+(unused-local|unused-public-symbol)') }).Count }
function NoDecl { if (Test-Path -LiteralPath $decl) { [IO.File]::Delete($decl) } }

$idx = Run @('index', '--project', "$app\App.dpr", '--db', $db)
if (-not (Test-Path -LiteralPath $db)) { Write-Host "FATAL: no index: $idx" -ForegroundColor Red; exit 2 }

Write-Host 'A. nothing declared' -ForegroundColor Cyan
$a = LintAll
Check 'A1 CONTROL own unit: both findings' ((Hits $a 'UApp') -eq 2) "n=$(Hits $a 'UApp')"
Check 'A2 the COMMON folder beside the project is reported' ((Hits $a 'UCommon') -eq 2) "n=$(Hits $a 'UCommon')"
Check 'A3 a third_party folder outside the project is dropped' ((Hits $a 'UTp') -eq 0)
Check 'A4 a thirdparty folder inside the project is dropped' ((Hits $a 'UTpIn') -eq 0)
Check 'A5 a folder named vendor is kept (ambiguous name)' ((Hits $a 'UVend') -eq 2) "n=$(Hits $a 'UVend')"
Check 'A6 a manifest Library include folder is dropped' ((Hits $a 'ULib') -eq 0)
Check 'A7 the summary says files and findings' ($a -match 'third-party: 3 file\(s\) not scanned, 6 project-wide finding\(s\) dropped') $a
Check 'A8 and names each reason with its counts' (($a -match "vendored folder 'third_party': 1 file\(s\), 2 finding\(s\)") -and ($a -match "vendored folder 'thirdparty': 1 file\(s\), 2 finding\(s\)") -and ($a -match 'library path .*\\lib: 1 file\(s\), 2 finding\(s\)')) $a
Check 'A9 the rules of the dropped findings are counted' ($a -match 'unused-public-symbol 3') $a
Check 'A10 the summary line carries the skip' ($a -match 'lint-all: \d+ finding\(s\) .*; 3 third-party file\(s\) skipped') $a
Check 'A11 it names the switch' ($a -match '--lint-third-party')
$rt = [IO.File]::ReadAllText($rep)
Check 'A12 the report file has the same lines' (($rt -match 'third-party: 3 file\(s\) not scanned') -and ($rt -match "vendored folder 'third_party'"))
Check 'A13 the note says the unrecognised outside files ARE linted' ($a -match 'NOTE: .*drag-lint-project\.json does not exist.*ARE linted') $a

Write-Host 'B. --lint-third-party shows everything' -ForegroundColor Cyan
$b = LintAll @('--lint-third-party')
foreach ($u in 'UApp', 'UCommon', 'UTp', 'UTpIn', 'UVend', 'ULib', 'URegListed') { Check "B1 $u reported" ((Hits $b $u) -eq 2) "n=$(Hits $b $u)" }
# the dropped count is what --lint-third-party then reports for those rules
$shown = @($b -split "`r?`n" | Where-Object { $_ -match '\\(UTp|UTpIn|ULib)\.pas:\d+:\d+\s+\[\w+\]\s+(\S+):' } | ForEach-Object { [regex]::Match($_, '\]\s+(\S+):').Groups[1].Value } | Group-Object | ForEach-Object { '{0} {1}' -f $_.Name, $_.Count })
$said = @([regex]::Match($a, 'dropped by rule: ([^\r\n]+)').Groups[1].Value -split ', ')
Check 'B3 every rule count said to be dropped is what this run reports' (($said.Count -gt 0) -and (@($said | Where-Object { $shown -notcontains $_ }).Count -eq 0)) (($said -join ';') + ' vs ' + ($shown -join ';'))
Check 'B2 nothing is said to be skipped' ($b -notmatch 'third-party: \d+ file')

Write-Host 'C. --json' -ForegroundColor Cyan
function Json([string[]]$More = @()) {
  Push-Location $WorkDir
  try { $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --config $cfg --quiet --json @More 2>$null } | Out-String } finally { Pop-Location }
  return , @($raw | ConvertFrom-Json | ForEach-Object { $_ })
}
$c = Json
$row = @($c | Where-Object { $_.rule -eq 'third-party-skipped' })
Check 'C1 one third-party-skipped row' ($row.Count -eq 1) "n=$($row.Count)"
Check 'C2 with the totals' ($row.Count -eq 1 -and $row[0].files_skipped -eq 3 -and $row[0].findings_dropped -eq 6) ($row | ConvertTo-Json -Compress -Depth 5)
$rs = if ($row.Count) { @($row[0].reasons | ForEach-Object { '{0}|{1}|{2}' -f $_.reason, $_.files, $_.findings }) } else { @() }
Check 'C3 and the reasons' (($rs -contains 'vendored-folder|1|2') -and ($rs -contains 'library-path|1|2')) ($rs -join ' ; ')
Check 'C4 and the rule counts' ($row.Count -eq 1 -and $row[0].rules.'unused-public-symbol' -eq 3)
$plain = @($c | Where-Object { $_.rule -ne 'third-party-skipped' })
Check 'C5 no finding of the array is located in third-party code' (@($plain | Where-Object { $_.file_path -match 'third_?party\\|repo\\lib\\' }).Count -eq 0)
Check 'C6 CONTROL findings of own code are there' (@($plain | Where-Object { $_.file_path -match 'UCommon' }).Count -ge 2)
Check 'C7 no row with --lint-third-party' (@((Json @('--lint-third-party')) | Where-Object { $_.rule -eq 'third-party-skipped' }).Count -eq 0)
$one = Json @('--rule', 'unused-local')
Check 'C8 a one-rule run counts only that rule' (@($one | Where-Object { $_.rule -eq 'third-party-skipped' -and $_.findings_dropped -eq 0 -and $_.files_skipped -eq 3 }).Count -eq 1) ($one | ConvertTo-Json -Compress -Depth 4)

Write-Host 'D. declarations and config' -ForegroundColor Cyan
W $decl '{ "ownRoots": [".."] }'
$d = LintAll
Check 'D1 a vendored folder inside a declared root is dropped' ((Hits $d 'UTp') -eq 0)
Check 'D2 a declared root wins over a library path' ((Hits $d 'ULib') -eq 2) "n=$(Hits $d 'ULib')"
Check 'D3 COMMON stays' ((Hits $d 'UCommon') -eq 2)
W $decl '{ "ownRoots": ["..", "../third_party"] }'
Check 'D4 a root declared AT the vendored folder owns it' ((Hits (LintAll) 'UTp') -eq 2)
W $decl '{ "ownRoots": ["."] }'
$d5 = LintAll
Check 'D5 a declared set still skips what lies outside it' ((Hits $d5 'UCommon') -eq 0)
Check 'D6 and says so' ($d5 -match 'outside the declared ownRoots: \d+ file\(s\)') $d5
W $decl '{ "excludeRoots": ["../COMMON"] }'
$d7 = LintAll
Check 'D7 excludeRoots drops a folder outside the project' ((Hits $d7 'UCommon') -eq 0)
Check 'D8 and names the reason' ($d7 -match 'excludeRoots .*COMMON: 1 file\(s\), 2 finding\(s\)') $d7
NoDecl
W $cfg '{ "vendored_folders": ["vendor", "-thirdparty"] }'
$d9 = LintAll
Check 'D9 vendored_folders adds a name' ((Hits $d9 'UVend') -eq 0)
Check 'D10 and "-name" takes a default out' ((Hits $d9 'UTpIn') -eq 2) "n=$(Hits $d9 'UTpIn')"
W $cfg '{ "own_paths": ["*\\third_party\\*", "*\\lib\\*"] }'
$d11 = LintAll
Check 'D11 own_paths keeps a vendored folder' ((Hits $d11 'UTp') -eq 2)
Check 'D12 own_paths keeps a library folder' ((Hits $d11 'ULib') -eq 2)
Check 'D13 CONTROL the rest is still dropped' ((Hits $d11 'UTpIn') -eq 0)
W $cfg '{ "own_paths": ["*\\third_party\\*"], "exclude_paths": ["*\\third_party\\*"] }'
$d14 = LintAll
Check 'D14 exclude_paths wins over own_paths' ((Hits $d14 'UTp') -eq 0)
Check 'D15 exclude_paths is counted too' ($d14 -match 'exclude_paths: 1 file\(s\), 2 finding\(s\)') $d14
W $cfg '{}'

Write-Host 'E. a project that itself lives under a vendored folder name' -ForegroundColor Cyan
$e1 = Join-Path $WorkDir 'third_party\mine'
W "$e1\UMine.pas" (Unit 'UMine')
W "$e1\Mine.dpr" "program Mine;`n`nuses`n  UMine in 'UMine.pas',`n  UBeside in '..\beside\UBeside.pas';`n`nbegin`nend.`n"
W "$WorkDir\third_party\beside\UBeside.pas" (Unit 'UBeside')
$dbE = Join-Path $e1 '_D-RAG\Mine.sqlite'
Run @('index', '--project', "$e1\Mine.dpr", '--db', $dbE) | Out-Null
$eo = Run @('lint-all', '--db', $dbE, '--config', $cfg, '--output', $rep, '--quiet')
Check 'E1 the project is linted' ((Hits $eo 'UMine') -eq 2) $eo
Check 'E2 so is its sibling' ((Hits $eo 'UBeside') -eq 2)

Write-Host 'F. a file the user names is always reported' -ForegroundColor Cyan
foreach ($f in "$repo\third_party\UTp.pas", "$repo\lib\ULib.pas") {
  $fo = Run @('lint', $f, '--db', $db, '--config', $cfg)
  Check "F1 lint $(Split-Path $f -Leaf)" ($fo -match 'unused-local') $fo
}

Write-Host 'G. --fix never writes outside the own roots by default' -ForegroundColor Cyan
$before = [IO.File]::ReadAllText("$repo\COMMON\UCommon.pas")
$g = LintAll @('--fix', '--apply', '--no-compile-gate', '--rule', 'unused-local')
Check 'G1 a fix run keeps to the project folder' (($g -notmatch 'UCommon\.pas') -and ($g -match 'outside the own roots \(a --fix run')) $g
Check 'G2 the file is unchanged' ([IO.File]::ReadAllText("$repo\COMMON\UCommon.pas") -eq $before)

$afterG = [IO.File]::ReadAllText("$app\UApp.pas")
Check 'G3 CONTROL the own unit was rewritten by the fix run' (-not $afterG.Contains('Idle: Integer')) $afterG
W $cfg '{ "own_paths": ["*\\COMMON\\*"] }'
$g4 = LintAll @('--fix', '--apply', '--no-compile-gate', '--rule', 'unused-local')
Check 'G4 own_paths does not widen the write scope: the file outside the own roots is unchanged' ([IO.File]::ReadAllText("$repo\COMMON\UCommon.pas") -eq $before) $g4
Check 'G5 CONTROL without --fix own_paths still reports the file' ((Hits (LintAll) 'UCommon') -eq 2)
W $cfg '{}'

Write-Host 'H. registry library path' -ForegroundColor Cyan
# a project of its own: UReg comes in over the .dproj search path (unlisted), URegListed is listed
$app2 = Join-Path $repo 'app2'
W "$app2\Reg.dpr" "program Reg;`n`nuses`n  UReg,`n  URegListed in '..\reglib\URegListed.pas';`n`nbegin`nend.`n"
W "$app2\Reg.dproj" '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup><MainSource>Reg.dpr</MainSource><DCC_UnitSearchPath>..\reglib</DCC_UnitSearchPath></PropertyGroup><ItemGroup><DelphiCompile Include="Reg.dpr"><MainSource>MainSource</MainSource></DelphiCompile><DCCReference Include="..\reglib\URegListed.pas"/></ItemGroup></Project>'
$db = Join-Path $app2 '_D-RAG\Reg.sqlite'
$wi = Run @('index', '--project', "$app2\Reg.dproj", '--db', $db)
$ctlH = LintAll @('--lint-third-party')
Check 'H0 CONTROL UReg is in the index' ((Hits $ctlH 'UReg') -eq 2) $wi
Check 'H1 CONTROL without a library path UReg is reported' ((Hits (LintAll) 'UReg') -eq 2)
$lib = @{ 'Search Path' = "$repo\reglib"; 'Browsing Path' = '' }
$regFix = Join-Path $WorkDir 'bds.json'
W $regFix (@{ '37.0' = @{ RootDir = 'C:\NoStudio'; Library = @{ Win32 = $lib; Win64 = $lib }; 'Environment Variables' = @{} } } | ConvertTo-Json -Depth 6)
$env:DRAGLINT_TEST_BDS_REGISTRY = $regFix
try { $h = LintAll } finally { $env:DRAGLINT_TEST_BDS_REGISTRY = '' }
Check 'H2 a unit under a library path, not listed by the project, is dropped' (((Hits $h 'UReg') -eq 0) -and ($h -match 'library path .*reglib: 1 file')) $h
Check 'H3 a LISTED unit of the same folder stays own' ((Hits $h 'URegListed') -eq 2) "n=$(Hits $h 'URegListed')"
Check 'H5 the include beside a listed unit stays own' ($h -match 'RegInc\.inc:\d+:\d+\s+\[\w+\]\s+unused-local') $h
$wide = @{ 'Search Path' = "$repo"; 'Browsing Path' = '' }
W $regFix (@{ '37.0' = @{ RootDir = 'C:\NoStudio'; Library = @{ Win32 = $wide; Win64 = $wide }; 'Environment Variables' = @{} } } | ConvertTo-Json -Depth 6)
$env:DRAGLINT_TEST_BDS_REGISTRY = $regFix
try { $h2 = LintAll } finally { $env:DRAGLINT_TEST_BDS_REGISTRY = '' }
Check 'H4 a library path that holds the project itself is no signal' ((Hits $h2 'UReg') -eq 2)
Write-Host 'I. a malformed declaration says so' -ForegroundColor Cyan
$db = Join-Path $app '_D-RAG\App.sqlite'   # H left $db on app2; $decl belongs to app
W $decl '{ "ownRoots": [ ".." '
$i1 = LintAll
Check 'I1 text warns about the malformed file' ($i1 -match 'drag-lint-project\.json .*malformed|malformed .*drag-lint-project\.json') $i1
Check 'I2 and says it defaulted to the project folder' ($i1 -match 'defaulted to the project folder')
$ij = Json
$irow = @($ij | Where-Object { $_.rule -eq 'own-roots-malformed' })
Check 'I3 one own-roots-malformed JSON row' ($irow.Count -eq 1) "n=$($irow.Count)"
Check 'I4 it is a note, with the file and a reason' (($irow.Count -eq 1) -and ($irow[0].severity -eq 'info') -and ($irow[0].file_path -like '*drag-lint-project.json') -and ($irow[0].message)) ($irow | ConvertTo-Json -Compress)
W $decl '["a"]'
Check 'I5 a non-object root warns too' ((LintAll) -match 'defaulted to the project folder')
W $decl '{ "ownRoots": [".."] }'
$ic = LintAll
Check 'I6 CONTROL a valid declaration: no warning' (($ic -notmatch 'malformed') -and (@((Json) | Where-Object { $_.rule -eq 'own-roots-malformed' }).Count -eq 0))
[IO.File]::WriteAllText($decl, '{ "excludeRoots": ["../COMMON"] }', [Text.UTF8Encoding]::new($true))
$ib = LintAll
Check 'I8 a UTF-8 BOM declaration with only excludeRoots is not malformed' ($ib -notmatch 'malformed') $ib
Check 'I9 CONTROL and it is honoured' ($ib -match 'excludeRoots .*COMMON: 1 file') $ib
NoDecl
Check 'I7 CONTROL no declaration: no warning' ((LintAll) -notmatch 'malformed')

Write-Host 'J. a listed unit with a non-ASCII name' -ForegroundColor Cyan
$nm = 'UReg' + [char]0xE4 + 'b'
$app3 = Join-Path $repo 'app3'
[IO.File]::WriteAllText("$repo\reglib\$nm.pas", ((Unit $nm) -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($true))
foreach ($bom in $true, $false) {
  if ([IO.Directory]::Exists($app3)) { [IO.Directory]::Delete($app3, $true) }
  [IO.Directory]::CreateDirectory($app3) | Out-Null
  [IO.File]::WriteAllText("$app3\Uni.dpr", "program Uni;`r`n`r`nuses`r`n  $nm in '..\reglib\$nm.pas';`r`n`r`nbegin`r`nend.`r`n", [Text.UTF8Encoding]::new($bom))
  $db = Join-Path $app3 '_D-RAG\Uni.sqlite'
  $ji = Run @('index', '--project', "$app3\Uni.dpr", '--db', $db)
  W $regFix (@{ '37.0' = @{ RootDir = 'C:\NoStudio'; Library = @{ Win32 = $lib; Win64 = $lib }; 'Environment Variables' = @{} } } | ConvertTo-Json -Depth 6)
  $ctlJ = LintAll
  $env:DRAGLINT_TEST_BDS_REGISTRY = $regFix
  try { $j = LintAll } finally { $env:DRAGLINT_TEST_BDS_REGISTRY = '' }
  $jRe = 'UReg.{1,8}b\.pas:\d+:\d+\s+\[\w+\]\s+unused-local'
  Check "J1 CONTROL (BOM $bom) the unit is indexed and reported" ($ctlJ -match $jRe) "$ji $ctlJ"
  Check "J2 (BOM $bom) a listed non-ASCII unit under a library path stays own" ($j -match $jRe) $j
}

Write-Host 'K. --project on a shared index counts only the files of that project' -ForegroundColor Cyan
$shared = Join-Path $WorkDir 'shared'
W "$shared\one\UOne.pas" (Unit 'UOne')
W "$shared\third_party\UVendored.pas" (Unit 'UVendored')
W "$shared\one\One.dpr" "program One;`n`nuses`n  UOne in 'UOne.pas';`n`nbegin`nend.`n"
W "$shared\two\UTwo.pas" (Unit 'UTwo')
W "$shared\two\Two.dpr" "program Two;`n`nuses`n  UTwo in 'UTwo.pas',`n  UVendored in '..\third_party\UVendored.pas';`n`nbegin`nend.`n"
$db = Join-Path $WorkDir 'sharedidx\All.sqlite'
[IO.Directory]::CreateDirectory((Split-Path -Parent $db)) | Out-Null
$ki = Run @('index', $shared, '--db', $db)
$k1 = LintAll @('--project', "$shared\one\One.dpr")
Check 'K1 CONTROL the project is linted' ((Hits $k1 'UOne') -eq 2) "$ki $k1"
Check 'K2 a vendored file outside the closure is not counted' (($k1 -notmatch 'third-party: ') -and ($k1 -notmatch 'third-party file\(s\) skipped') -and ($k1 -notmatch 'own roots skipped')) $k1
$k2 = LintAll @('--project', "$shared\two\Two.dpr")
Check 'K3 CONTROL the project that compiles it counts it' ($k2 -match 'third-party: 1 file\(s\) not scanned, 1 project-wide finding\(s\) dropped|third-party: 1 file\(s\) not scanned, 2 project-wide finding\(s\) dropped') $k2
W $cfg '{ "exclude_paths": ["*\\two\\*", "*\\third_party\\*"] }'
$k4 = LintAll @('--project', "$shared\one\One.dpr")
Check 'K4 exclude_paths outside the closure is not counted' (($k4 -notmatch 'skipped by exclude_paths') -and ($k4 -notmatch 'exclude_paths: \d+ file')) $k4
Check 'K5 CONTROL inside the closure it is' ((LintAll @('--project', "$shared\two\Two.dpr")) -match '2 file\(s\) skipped by exclude_paths|3 file\(s\) skipped by exclude_paths')
W $cfg '{}'

Write-Host 'L. capture_rule_baseline.ps1 counts findings, not note rows' -ForegroundColor Cyan
$fake = Join-Path $WorkDir 'fake-engine.ps1'
W $fake @"
if (`$args[0] -eq 'lint-all') {
  '[{"rule":"unused-local","severity":"warning","file_path":"C:\\x.pas","start_line":3},{"rule":"third-party-skipped","severity":"info","file_path":"C:\\x","start_line":0},{"rule":"own-roots-malformed","severity":"info","file_path":"C:\\x","start_line":0}]'
} elseif (`$args[0] -eq 'sql') { 'v=1;schema=1' } else { '[]' }
"@
$capOut = Join-Path $WorkDir 'cap'
W "$WorkDir\fake.sqlite" 'x'
$cap = (& { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File "$PSScriptRoot\..\..\tools\measure\capture_rule_baseline.ps1" -Tag before -Exe $fake -OutDir $capOut -CorpusDb "$WorkDir\fake.sqlite" 2>&1 | ForEach-Object { "$_" } } | Out-String)
$rows = if (Test-Path "$capOut\rule_counts_before.csv") { @(Import-Csv "$capOut\rule_counts_before.csv") } else { @() }
Check 'L1 CONTROL the finding is counted' (@($rows | Where-Object { $_.rule -eq 'unused-local' -and $_.count -eq '1' }).Count -eq 1) $cap
Check 'L2 no note row is counted as a rule' (($rows.Count -gt 0) -and (@($rows | Where-Object { $_.rule -match 'third-party-skipped|own-roots-malformed' }).Count -eq 0)) ($rows | Out-String)
Check 'L3 nor in the total' (@($rows | Where-Object { $_.rule -eq '__TOTAL__' -and $_.count -eq '1' }).Count -eq 1) ($rows | Out-String)
Write-Host ''
Write-Host ("{0} check(s)" -f $script:N)
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { $null = $_ } }
}