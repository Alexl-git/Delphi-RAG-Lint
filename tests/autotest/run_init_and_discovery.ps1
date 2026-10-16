<#
  run_init_and_discovery.ps1 -- `drag-lint init` and the repository config
  (<root>\_D-RAG\config.json) found by walking UP, like git (E3a, 2026-10-07).

  Why this exists
  ---------------
  Until E3a the configuration was spread over six files with six search rules
  (a manifest beside the exe and in every sibling folder of it, a dotted
  .drag-lint.json walked up from the CWD, drag-lint-lint.json,
  drag-lint-layers.json, drag-lint-project.json, .drag-lint-workspace.json), so
  the same command answered differently depending on the folder the shell stood
  in. The owner's ruling: ONE config per repository, in _D-RAG at its root,
  found from wherever the command runs inside it -- or from the path it names.

  What is checked
  ---------------
    I1  init creates config.json (both projects, relative dproj, the Delphi from
        each ProjectVersion), the .gitignore, and the .cvsignore line in a CVS
        working copy;
    I2  a second init refuses, and leaves the file alone; --project adds one and
        KEEPS the keys the user wrote; --force rediscovers;
    X1  `index` with no target, from a SUBFOLDER, builds every project into
        <root>\_D-RAG\<name>.sqlite -- and nothing beside the projects;
    X2  the project's "delphi" decides the target (cv= in the fingerprint),
        over the .dproj's ProjectVersion;
    Q1  the same query answers the same from the root, a subfolder and a
        sibling project folder; and from OUTSIDE the repo when given --in;
    Q2  a planted .drag-lint.json whose "db" points at a decoy is ignored
        inside a configured repository;
    L1  the config.json "lint" block is the lint config (a rule it disables
        stops firing) -- CONTROL: without the block the rule fires;
    N1  outside any repository, `index` with no target exits 2 naming init;
    D1  a run with no project takes the Delphi every configured project agrees
        on (its library index folder); disagreeing projects leave the default;
    B1  a config.json that is not JSON stops the run (exit 2, names the file).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_init_discovery_$PID"
)
try {

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
function Run-In([string]$cwd, [string[]]$argv, [int]$timeoutSec = 180) {
  $o = Join-Path $WorkDir 'out.txt'; $e = Join-Path $WorkDir 'err.txt'
  $quoted = $argv | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
  $p = Start-Process $Exe -ArgumentList $quoted -WorkingDirectory $cwd `
         -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit($timeoutSec * 1000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ Code = -1; Text = 'TIMEOUT' } }
  $t = ((Get-Content $o -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $e -Raw -ErrorAction SilentlyContinue))
  return [pscustomobject]@{ Code = $p.ExitCode; Text = $t }
}
function Fingerprint([string]$db) {
  $r = Run-In $WorkDir @('sql', '--db', $db, '--format', 'text', '--query', "select value from schema_meta where key='indexer_fingerprint'")
  return $r.Text
}

Write-Host '== init and repository config discovery ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path

$installed = @(Get-ChildItem HKCU:\Software\Embarcadero\BDS -ErrorAction SilentlyContinue |
               Where-Object { $_.GetValue('RootDir') } | ForEach-Object PSChildName)
$have20 = $installed -contains '20.0'
$have37 = $installed -contains '37.0'
if (-not ($have20 -and $have37)) { Write-Host "SKIP: needs BDS 20.0 and 37.0 installed (have: $($installed -join ', '))"; exit 77 }

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
$root = Join-Path $WorkDir 'repo'
$app  = Join-Path $root 'App'
$tool = Join-Path $root 'Tool'
$sub  = Join-Path $app 'sub'
foreach ($d in @($root, $app, $tool, $sub, (Join-Path $root 'CVS'))) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

Write-Ascii (Join-Path $app 'uWidget.pas') @'
unit uWidget;
interface
type
  TWidget = class
    procedure Ping;
  end;
implementation
procedure TWidget.Ping;
begin
end;
end.
'@
Write-Ascii (Join-Path $app 'uUser.pas') @'
unit uUser;
interface
procedure UseWidget;
implementation
uses uWidget;
procedure UseWidget;
var
  W: TWidget;
begin
  W:= TWidget.Create;
  try
    W.Ping;
  finally
    W.Free;
  end;
end;
end.
'@
Write-Ascii (Join-Path $app 'App.dpr') "program App;`nuses`n  uWidget in 'uWidget.pas',`n  uUser in 'uUser.pas';`nbegin`nend.`n"
Write-Ascii (Join-Path $app 'App.dproj') "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>18.8</ProjectVersion>`n    <MainSource>App.dpr</MainSource>`n  </PropertyGroup>`n</Project>`n"
Write-Ascii (Join-Path $tool 'uTool.pas') "unit uTool;`ninterface`nprocedure ToolRun;`nimplementation`nprocedure ToolRun;`nbegin`nend;`nend.`n"
Write-Ascii (Join-Path $tool 'Tool.dpr') "program Tool;`nuses`n  uTool in 'uTool.pas';`nbegin`n  ToolRun;`nend.`n"
Write-Ascii (Join-Path $tool 'Tool.dproj') "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>20.4</ProjectVersion>`n    <MainSource>Tool.dpr</MainSource>`n  </PropertyGroup>`n</Project>`n"

$home_ = Join-Path $root '_D-RAG'
$cfgFile = Join-Path $home_ 'config.json'

# --- I1 -----------------------------------------------------------------------
Write-Host 'I1 -- init' -ForegroundColor Cyan
$i1 = Run-In $WorkDir @('init', $root)
Check 'I1 init exits 0' ($i1.Code -eq 0) $i1.Text
Check 'I1 config.json written' (Test-Path $cfgFile) ''
$cfg = $null
if (Test-Path $cfgFile) { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json }
$pApp  = @($cfg.projects | Where-Object name -eq 'App')
$pTool = @($cfg.projects | Where-Object name -eq 'Tool')
Check 'I1 two projects, App and Tool' (($pApp.Count -eq 1) -and ($pTool.Count -eq 1)) ($cfg | ConvertTo-Json -Depth 5)
Check 'I1 dproj is RELATIVE to the root' (($pApp.Count -eq 1) -and ($pApp[0].dproj -eq 'App\App.dproj')) "$($pApp.dproj)"
Check 'I1 App (ProjectVersion 18.8) is delphi 20.0' (($pApp.Count -eq 1) -and ($pApp[0].delphi -eq '20.0')) "$($pApp.delphi)"
Check 'I1 Tool (ProjectVersion 20.4) is delphi 37.0' (($pTool.Count -eq 1) -and ($pTool[0].delphi -eq '37.0')) "$($pTool.delphi)"
$gi = Join-Path $home_ '.gitignore'
$giText = if (Test-Path $gi) { Get-Content $gi -Raw } else { '' }
Check 'I1 .gitignore ignores everything but itself and config.json' `
  (($giText -match '(?m)^\*\s*$') -and ($giText -match '(?m)^!\.gitignore\s*$') -and ($giText -match '(?m)^!config\.json\s*$')) $giText
$cvsi = Join-Path $root '.cvsignore'
Check 'I1 a CVS root gets _D-RAG in .cvsignore' ((Test-Path $cvsi) -and ((Get-Content $cvsi -Raw) -match '(?m)^_D-RAG\s*$')) ''

# --- I2 -----------------------------------------------------------------------
Write-Host 'I2 -- init again, --project, --force' -ForegroundColor Cyan
# the user's own keys, which every rewrite must keep
$cfg | Add-Member -NotePropertyName docs -NotePropertyValue ([pscustomobject]@{ max_callers = 3 }) -Force
[System.IO.File]::WriteAllText($cfgFile, ($cfg | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
$before = Get-Content $cfgFile -Raw
$i2 = Run-In $WorkDir @('init', $root)
Check 'I2 a second init refuses (exit 2)' ($i2.Code -eq 2) $i2.Text
Check 'I2 ... and leaves config.json alone' ((Get-Content $cfgFile -Raw) -eq $before) ''
$extra = Join-Path $root 'Extra'
New-Item -ItemType Directory -Force -Path $extra | Out-Null
Copy-Item (Join-Path $tool 'Tool.dproj') (Join-Path $extra 'Extra.dproj')
Write-Ascii (Join-Path $extra 'Extra.dpr') "program Extra;`nbegin`nend.`n"
$i3 = Run-In $WorkDir @('init', $root, '--project', (Join-Path $extra 'Extra.dproj'))
$cfg3 = Get-Content $cfgFile -Raw | ConvertFrom-Json
Check 'I2 --project adds the project' ($i3.Code -eq 0 -and @($cfg3.projects).Count -eq 3) $i3.Text
Check 'I2 --project keeps the user''s keys' ($cfg3.docs.max_callers -eq 3) ''
Remove-Item -Recurse -Force $extra
$i4 = Run-In $WorkDir @('init', $root, '--force')
$cfg4 = Get-Content $cfgFile -Raw | ConvertFrom-Json
Check 'I2 --force rediscovers (Extra is gone with its folder)' ($i4.Code -eq 0 -and @($cfg4.projects).Count -eq 2) $i4.Text
Check 'I2 --force keeps the user''s keys' ($cfg4.docs.max_callers -eq 3) ''

# --- X1 -----------------------------------------------------------------------
Write-Host 'X1 -- index with no target, from a subfolder' -ForegroundColor Cyan
$x1 = Run-In $sub @('index', '--platform', 'win32')
Check 'X1 index exits 0' ($x1.Code -eq 0) $x1.Text
$appDb  = Join-Path $home_ 'App.sqlite'
$toolDb = Join-Path $home_ 'Tool.sqlite'
Check 'X1 App indexed into <root>\_D-RAG\App.sqlite' (Test-Path $appDb) ''
Check 'X1 Tool indexed into <root>\_D-RAG\Tool.sqlite' (Test-Path $toolDb) ''
Check 'X1 no _D-RAG beside the projects' ((-not (Test-Path (Join-Path $app '_D-RAG'))) -and (-not (Test-Path (Join-Path $tool '_D-RAG')))) ''

# --- X2 -----------------------------------------------------------------------
Write-Host 'X2 -- the project''s "delphi" decides the target' -ForegroundColor Cyan
$fpApp  = Fingerprint $appDb
$fpTool = Fingerprint $toolDb
Check 'X2 App (delphi 20.0) is stamped cv=33' ($fpApp -match 'cv=33') $fpApp
Check 'X2 Tool (delphi 37.0) has no cv= limb' (($fpTool -match 'v=') -and ($fpTool -notmatch 'cv=')) $fpTool
$cfg5 = Get-Content $cfgFile -Raw | ConvertFrom-Json
($cfg5.projects | Where-Object name -eq 'App').delphi = '37.0'
[System.IO.File]::WriteAllText($cfgFile, ($cfg5 | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
$x2 = Run-In $root @('index', '--only', 'App', '--platform', 'win32')
$fpApp2 = Fingerprint $appDb
Check 'X2 "delphi": "37.0" over ProjectVersion 18.8 re-targets App (no cv= limb)' (($x2.Code -eq 0) -and ($fpApp2 -notmatch 'cv=')) "$fpApp2 / $($x2.Text)"
($cfg5.projects | Where-Object name -eq 'App').delphi = '20.0'
[System.IO.File]::WriteAllText($cfgFile, ($cfg5 | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
$null = Run-In $root @('index', '--only', 'App', '--platform', 'win32')
$x3 = Run-In $root @('index', '--only', 'Nope')
Check 'X2 --only with an unknown project exits 2 naming the projects' (($x3.Code -eq 2) -and ($x3.Text -match 'App') -and ($x3.Text -match 'Tool')) $x3.Text

# --- Q1 -----------------------------------------------------------------------
Write-Host 'Q1 -- same answer from anywhere inside the repo' -ForegroundColor Cyan
$q = @('query', 'find-callers', '--name', 'Ping', '--resolved')
$qr = Run-In $root $q
$qs = Run-In $sub  $q
$qt = Run-In $tool $q
Check 'Q1 from the root: finds the caller UseWidget' (($qr.Code -eq 0) -and ($qr.Text -match 'UseWidget')) $qr.Text
Check 'Q1 from a subfolder: the same output' ($qs.Text -eq $qr.Text) $qs.Text
Check 'Q1 from a sibling project folder: the same output' ($qt.Text -eq $qr.Text) $qt.Text
$outside = Join-Path $WorkDir 'outside'
New-Item -ItemType Directory -Force -Path $outside | Out-Null
$qo = Run-In $outside @('query', '--name', 'TWidget', '--exact', '--in', (Join-Path $app 'uWidget.pas'))
Check 'Q1 from OUTSIDE the repo, --in anchors the search' (($qo.Code -eq 0) -and ($qo.Text -match 'uWidget\.TWidget')) $qo.Text

# --- Q2 -----------------------------------------------------------------------
Write-Host 'Q2 -- a planted .drag-lint.json is not consulted' -ForegroundColor Cyan
$decoy = Join-Path $WorkDir 'decoy.sqlite'
$null = Run-In $WorkDir @('index', $tool, '--db', $decoy)
Write-Ascii (Join-Path $root '.drag-lint.json') "{ `"db`": `"$($decoy -replace '\\','\\')`" }`n"
$q2 = Run-In $root @('query', '--name', 'TWidget', '--exact')
Check 'Q2 the query still answers from the repo index, not the decoy' (($q2.Code -eq 0) -and ($q2.Text -match 'uWidget\.TWidget')) $q2.Text
Remove-Item (Join-Path $root '.drag-lint.json')

# --- L1 -----------------------------------------------------------------------
Write-Host 'L1 -- the config.json "lint" block is the lint config' -ForegroundColor Cyan
$userPas = Join-Path $app 'uUser.pas'
$l0 = Run-In $root @('lint', $userPas, '--enable', 'magic-literal', '--json')
$cfg6 = Get-Content $cfgFile -Raw | ConvertFrom-Json
$cfg6 | Add-Member -NotePropertyName lint -NotePropertyValue ([pscustomobject]@{ disabled = @('unused-public-symbol') }) -Force
[System.IO.File]::WriteAllText($cfgFile, ($cfg6 | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
$rulesBefore = @([regex]::Matches($l0.Text, '"rule"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$target = @($rulesBefore | Where-Object { $_ -in @('unused-public-symbol') })
$l1 = Run-In $root @('lint', $userPas, '--enable', 'magic-literal', '--json')
$rulesAfter = @([regex]::Matches($l1.Text, '"rule"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if ($target.Count -gt 0) {
  Check "L1 CONTROL: without the block, $($target -join ',') fires" $true ''
  Check 'L1 with the block, the disabled rule no longer fires' (@($rulesAfter | Where-Object { $_ -in $target }).Count -eq 0) ($rulesAfter -join ',')
} else {
  Check 'L1 CONTROL: unused-public-symbol fires on uUser.pas without the block (needed to prove the block works)' $false ($rulesBefore -join ',')
}

# --- N1 -----------------------------------------------------------------------
Write-Host 'N1 -- outside any repository' -ForegroundColor Cyan
$n1 = Run-In $outside @('index')
Check 'N1 index with no target exits 2' ($n1.Code -eq 2) $n1.Text
Check 'N1 ... and names drag-lint init' ($n1.Text -match 'drag-lint init') $n1.Text

# --- D1 -----------------------------------------------------------------------
Write-Host 'D1 -- a run with no project takes the Delphi the repository agrees on' -ForegroundColor Cyan
$d0 = Run-In $root @('resolve-dbs', '--platform', 'win32')
Check 'D1 CONTROL: App (20.0) and Tool (37.0) disagree -> the newest Studio (library\37.0)' ($d0.Text -match '\\library\\37\.0\\') $d0.Text
$cfg7 = Get-Content $cfgFile -Raw | ConvertFrom-Json
$cfg7.projects = @($cfg7.projects | Where-Object name -eq 'App')
[System.IO.File]::WriteAllText($cfgFile, ($cfg7 | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
$d1 = Run-In $root @('resolve-dbs', '--platform', 'win32')
Check 'D1 only App (20.0): the library index is the 20.0 one (library\20.0)' ($d1.Text -match '\\library\\20\.0\\') $d1.Text

# --- B1 -----------------------------------------------------------------------
Write-Host 'B1 -- a broken config.json stops the run' -ForegroundColor Cyan
Write-Ascii $cfgFile "{ not json`n"
$b1 = Run-In $sub @('query', '--name', 'TWidget')
Check 'B1 exit 2' ($b1.Code -eq 2) $b1.Text
Check 'B1 the message names the file' ($b1.Text -match [regex]::Escape($cfgFile)) $b1.Text

Write-Host ''
if ($script:Failed) { Write-Host 'INIT AND DISCOVERY: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'INIT AND DISCOVERY: PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path -LiteralPath "$env:TEMP\draglint_init_discovery_$PID") { Remove-Item -LiteralPath "$env:TEMP\draglint_init_discovery_$PID" -Recurse -Force -ErrorAction SilentlyContinue }
}
