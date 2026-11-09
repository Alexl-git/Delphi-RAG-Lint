#Requires -Version 7
<#
  run_lsp_file_context_guard.ps1 -- 1.44 lane lspctx. Owner's report: "drag-lint: no
  platform is known for DRagLint.Report.CyclePlan.pas -- using the default Win64".

  Reproduced on 1.43: the main-tree file answers (its DB holds the path); the SAME unit
  in a worktree, or a member no DB holds yet, finds nothing, because a unit's project was
  only (a) an index holding that exact path or (b) a sole .dproj in the unit's OWN folder.
  drag-lint.dproj is in src\cli, the unit in src\report. And a project known only as a
  .dpr, or a .dproj without the $(Platform) marker, had no platform at all.

  Every session has its own fixture, explicit --db, no user defaults file:
    MEMB  repo\app\App.dproj lists ..\shared\uMember.pas, no index holds it  -> App.dproj + Win32
    NEAR  a .dproj elsewhere in the repo does NOT list the unit              -> not picked
    STOP  a .dproj above the repository root is never searched               -> unknown
    DPLAT a .dproj with no marker: EffectiveIndexPlatform's order (149 LX, a3 + b76a5e20): the
          manifest defaultPlatform (the exe's drag-lint.json), else Win32 -- whatever it targets;
          the marker still decides (Marked32 / Marked64 controls)       -> no notice
    DPR   a manifest section's bare .dpr + its .dlcontext.json / sibling .dproj -> their platform
    MANY  two indexes hold the file -> the first in order, and the message says which
    UNK   two files of one folder, truly unknown -> one message per folder, type 3, what to do
    CLI   initializationOptions project + platform beat all of it
  Positive controls (PC): an index-held unit keeps its owner, on 1.43 too; a second folder
  still gets its own message; a marker still beats the declared platform.

  RUN RED FIRST on the deployed 1.43 engine: MEMB, DPLAT, DPR, MANY, UNK fail; PCs pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-filectx-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0; $script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
function Write-Ascii($p, $t) {
  New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
  [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII)
}
function Lines([string[]]$a) { ($a -join "`r`n") + "`r`n" }
function PasUnit($p) {
  $n = [IO.Path]::GetFileNameWithoutExtension($p)
  Write-Ascii $p (Lines @("unit $n;", 'interface', "procedure Do$n;", 'implementation', "procedure Do$n;", 'begin', 'end;', 'end.'))
}
function Dproj($p, [string[]]$body) {
  Write-Ascii $p (Lines (@('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">', '  <PropertyGroup>',
    "    <Config Condition=`"'`$(Config)'==''`">Debug</Config>") + $body + @('</Project>')))
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"
$env:DRAGLINT_LSP_REINDEX_EXE = $env:ComSpec   # a pending fixture DB must never start a real run

$Marker32 = "    <Platform Condition=`"'`$(Platform)'==''`">Win32</Platform>"
$R = "$WorkDir\repo"
New-Item -ItemType Directory -Force "$R\.git" | Out-Null
Dproj "$R\app\App.dproj" @($Marker32, '  </PropertyGroup>', '  <ItemGroup>',
  '    <DCCReference Include="..\shared\uMember.pas"/>', '  </ItemGroup>')
Dproj "$R\other\Other.dproj" @($Marker32, '  </PropertyGroup>', '  <ItemGroup>',
  '    <DCCReference Include="..\shared\uOtherMember.pas"/>', '  </ItemGroup>')
PasUnit "$R\shared\uMember.pas"
PasUnit "$R\shared\uOrphan.pas"
# A .dproj ABOVE the repository root lists a unit inside it: never searched.
Dproj "$WorkDir\Above.dproj" @($Marker32, '  </PropertyGroup>', '  <ItemGroup>',
  '    <DCCReference Include="repo\shared\uOrphan.pas"/>', '  </ItemGroup>')

# DPLAT: no $(Platform) marker in any of these.
function PlatProj($name, [string[]]$b) {
  Dproj "$WorkDir\plat\$name\$name.dproj" (@('  </PropertyGroup>') + $b)
  PasUnit "$WorkDir\plat\$name\u$name.pas"
}
PlatProj 'Both'   @('  <ProjectExtensions><BorlandProject><Platforms><Platform value="Win32">True</Platform><Platform value="Win64">True</Platform></Platforms></BorlandProject></ProjectExtensions>')
PlatProj 'Only32' @('  <ProjectExtensions><BorlandProject><Platforms><Platform value="Win32">True</Platform><Platform value="Win64">False</Platform></Platforms></BorlandProject></ProjectExtensions>')
PlatProj 'Tp3'    @('  <PropertyGroup><TargetedPlatforms>3</TargetedPlatforms></PropertyGroup>')
PlatProj 'Tp1'    @('  <PropertyGroup><TargetedPlatforms>1</TargetedPlatforms></PropertyGroup>')
PlatProj 'Marked64' @(($Marker32 -replace 'Win32', 'Win64'), '  <ProjectExtensions><BorlandProject><Platforms><Platform value="Win32">True</Platform></Platforms></BorlandProject></ProjectExtensions>')
PlatProj 'Marked' @($Marker32, '  <ProjectExtensions><BorlandProject><Platforms><Platform value="Win64">True</Platform></Platforms></BorlandProject></ProjectExtensions>')

# UNK: two files in one folder, one in another; nothing owns them. .git stops the search.
New-Item -ItemType Directory -Force "$WorkDir\nowhere\.git" | Out-Null
PasUnit "$WorkDir\nowhere\f1\uA1.pas"
PasUnit "$WorkDir\nowhere\f1\uA2.pas"
PasUnit "$WorkDir\nowhere\f2\uB1.pas"

# MANY: the same file in two indexes (each with its project by the _D-RAG convention).
New-Item -ItemType Directory -Force "$WorkDir\many\.git" | Out-Null
PasUnit "$WorkDir\many\s\uShared.pas"
foreach ($n in 'First', 'Second') {
  Dproj "$WorkDir\many\$n\$n.dproj" @(($Marker32 -replace 'Win32', 'Win64'), '  </PropertyGroup>')
  New-Item -ItemType Directory -Force "$WorkDir\many\$n\_D-RAG" | Out-Null
  & $Exe index "$WorkDir\many\s" --db "$WorkDir\many\$n\_D-RAG\$n.sqlite" 2>&1 | Out-Null
}
New-Item -ItemType Directory -Force "$R\app\_D-RAG" | Out-Null
$dbApp = "$R\app\_D-RAG\App.sqlite"
$dbLib = "$WorkDir\library-Win64.sqlite"
New-Item -ItemType Directory -Force "$WorkDir\lib" | Out-Null
PasUnit "$WorkDir\lib\uLib.pas"
$held = "$R\heldroot"; PasUnit "$held\uHeld.pas"
& $Exe index $held --db $dbApp 2>&1 | Out-Null
& $Exe index "$WorkDir\lib" --db $dbLib 2>&1 | Out-Null
Check 'SETUP: fixture indexes built' ((Test-Path $dbApp) -and (Test-Path $dbLib) -and (Test-Path "$WorkDir\many\First\_D-RAG\First.sqlite"))

function Uri($p) { 'file:///' + ($p -replace '\\', '/') }
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function Read-Frames([string]$Out) {
  $res = @(); $i = 0
  while ($true) {
    $m = [regex]::Match($Out.Substring($i), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $m.Success) { break }
    $start = $i + $m.Index + $m.Length
    $len = [int]$m.Groups[1].Value
    if ($start + $len -gt $Out.Length) { break }
    $res += ($Out.Substring($start, $len) | ConvertFrom-Json)
    $i = $start + $len
  }
  return $res
}
# One session: didOpen every file; returns context per file + the showMessage frames.
function Session([string[]]$files, [string[]]$dbs, $initOptions = $null, $cwd = $WorkDir) {
  $init = @{ processId = $null; rootUri = $null; capabilities = @{} }
  if ($initOptions) { $init.initializationOptions = $initOptions }
  $msgs = (Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = $init }) +
          (Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} })
  foreach ($f in $files) {
    $msgs += (Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = (Uri $f); languageId = 'pascal'; version = 1; text = [System.IO.File]::ReadAllText($f) } } })
  }
  $msgs += (Frame @{ jsonrpc = '2.0'; id = 99; method = 'shutdown'; params = @{} }) + (Frame @{ jsonrpc = '2.0'; method = 'exit'; params = @{} })
  $in = "$WorkDir\in.txt"; $so = "$WorkDir\out.txt"; $se = "$WorkDir\err.txt"
  [System.IO.File]::WriteAllText($in, $msgs, (New-Object System.Text.UTF8Encoding($false)))
  $a = @('lsp'); foreach ($d in $dbs) { $a += @('--db', $d) }
  Start-Process $Exe -ArgumentList $a -WorkingDirectory $cwd `
    -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $frames = @(Read-Frames ([System.IO.File]::ReadAllText($so)))
  $ctx = @{}
  foreach ($f in $files) {
    $c = @($frames | Where-Object { $_.method -eq 'draglint/context' -and $_.params.uri -eq (Uri $f) })
    if ($c.Count -gt 0) { $ctx[$f] = $c[-1].params }
  }
  return @{ Ctx = $ctx; Messages = @($frames | Where-Object { $_.method -eq 'window/showMessage' } | ForEach-Object { $_.params }) }
}
function Texts($s) { ($s.Messages | ForEach-Object { "[$($_.type)] $($_.message)" }) -join ' | ' }
function NoPlatformMsg($s) { @($s.Messages | Where-Object { $_.message -match 'no platform is known' }).Count -eq 0 }

Write-Host 'MEMB: a unit its project lists, in no index, in a folder without a .dproj' -ForegroundColor Cyan
$f = "$R\shared\uMember.pas"
$s = Session @($f) @($dbApp, $dbLib)
Check 'MEMB: project = the .dproj that lists it' ($s.Ctx[$f].project -like '*\app\App.dproj') ($s.Ctx[$f] | ConvertTo-Json -Compress)
Check 'MEMB: platform = its marker, source dproj' ($s.Ctx[$f].platform -eq 'Win32' -and $s.Ctx[$f].source -eq 'dproj') ($s.Ctx[$f] | ConvertTo-Json -Compress)
Check 'MEMB: neither "no project" nor "no platform"' ((NoPlatformMsg $s) -and @($s.Messages | Where-Object { $_.message -match 'no project is known' }).Count -eq 0) (Texts $s)

Write-Host 'NEAR/STOP: never a project that does not list the unit' -ForegroundColor Cyan
$f = "$R\shared\uOrphan.pas"
$s = Session @($f) @($dbApp, $dbLib)
Check 'NEAR+STOP: no project for a unit no project in the repository lists' ($s.Ctx[$f].project -eq '') ($s.Ctx[$f] | ConvertTo-Json -Compress)

Write-Host 'PC: an index-held unit keeps the index owner' -ForegroundColor Cyan
$f = "$held\uHeld.pas"
$s = Session @($f) @($dbApp, $dbLib)
Check 'PC: DB membership owner App.dproj, Win32' ($s.Ctx[$f].project -like '*\app\App.dproj' -and $s.Ctx[$f].platform -eq 'Win32') ($s.Ctx[$f] | ConvertTo-Json -Compress)

Write-Host 'DPLAT: a .dproj without the $(Platform) marker' -ForegroundColor Cyan
# 149 LX: a marker-less project is what the index makes of it (manifest default, else a3 Win32),
# not 'Win64 if targeted'. Read the default the engine will read, so the expectation follows it.
$ManDef = ''
try { $ManDef = [string]((Get-Content (Join-Path (Split-Path $Exe) 'drag-lint.json') -Raw | ConvertFrom-Json).settings.defaultPlatform) } catch { }
$A3 = if ($ManDef) { $ManDef } else { 'Win32' }
foreach ($t in @(@('Both', $A3), @('Only32', $A3), @('Tp3', $A3), @('Tp1', $A3), @('Marked', 'Win32'), @('Marked64', 'Win64'))) {
  $f = "$WorkDir\plat\$($t[0])\u$($t[0]).pas"
  $s = Session @($f) @($dbLib)
  Check "DPLAT $($t[0]): platform $($t[1]), no notice about it" ($s.Ctx[$f].platform -eq $t[1] -and (NoPlatformMsg $s)) (($s.Ctx[$f] | ConvertTo-Json -Compress) + ' ' + (Texts $s))
}

Write-Host 'DPR: a project known only as a .dpr (manifest section)' -ForegroundColor Cyan
$D = "$WorkDir\dpr"
$mk = {
  param($name, $withDproj, $withCtx)
  $dir = "$D\$name"; PasUnit "$dir\u$name.pas"
  Write-Ascii "$dir\$name.dpr" (Lines @("program $name;", "uses u$name in 'u$name.pas';", 'begin', 'end.'))
  if ($withDproj) { Dproj "$dir\$name.dproj" @($Marker32, '  </PropertyGroup>') }
  if ($withCtx) {
    Write-Ascii "$dir\$name.dlcontext.json" ((@{ schema = 1; project = "$dir\$name.dpr"; platform = 'Linux64'; config = 'Release'
      source = @{ file = "$dir\$name.dpr"; sha1 = '' } } | ConvertTo-Json -Depth 5))
  }
  New-Item -ItemType Directory -Force "$dir\_D-RAG" | Out-Null
  & $Exe index "$dir\u$name.pas" --db "$dir\_D-RAG\$name.sqlite" 2>&1 | Out-Null
}
& $mk 'WithDproj' $true $false
& $mk 'WithCtx' $false $true
& $mk 'Bare' $false $false
$sec = @(foreach ($n in 'WithDproj', 'WithCtx', 'Bare') {
  @{ name = $n; db = "$D\$n\_D-RAG\$n.sqlite"; include = @("$D\$n\$n.dpr"); useIgnoreFiles = $true; sqlOnlyMS = $true } })
Write-Ascii "$D\.drag-lint.json" (@{ settings = @{ defaultPlatform = 'Win64' }; indexes = @{ outDir = "$D\out"; sections = $sec } } | ConvertTo-Json -Depth 6)
$f = "$D\WithCtx\uWithCtx.pas"
$s = Session @($f) @("$D\WithCtx\_D-RAG\WithCtx.sqlite", $dbLib) $null $D
Check 'DPR: the .dpr''s own .dlcontext.json names the platform' ($s.Ctx[$f].platform -eq 'Linux64' -and (NoPlatformMsg $s)) (($s.Ctx[$f] | ConvertTo-Json -Compress) + ' ' + (Texts $s))
$f = "$D\WithDproj\uWithDproj.pas"
$s = Session @($f) @("$D\WithDproj\_D-RAG\WithDproj.sqlite", $dbLib) $null $D
Check 'DPR: the .dpr''s sibling .dproj names the platform' ($s.Ctx[$f].platform -eq 'Win32' -and (NoPlatformMsg $s)) (($s.Ctx[$f] | ConvertTo-Json -Compress) + ' ' + (Texts $s))

$f = "$D\Bare\uBare.pas"
$s = Session @($f) @("$D\Bare\_D-RAG\Bare.sqlite", $dbLib) $null $D
Check 'DPR: a bare .dpr keeps its project and says what to do, at info level' ($s.Ctx[$f].project -like '*\Bare\Bare.dpr' -and @($s.Messages | Where-Object { $_.message -match 'no platform is known' -and $_.message -match 'dragLint\.selectPlatform' -and $_.type -eq 3 }).Count -eq 1) (($s.Ctx[$f] | ConvertTo-Json -Compress) + ' ' + (Texts $s))

Write-Host 'WT: a checkout no index holds: the project is named, its index is not borrowed' -ForegroundColor Cyan
New-Item -ItemType Directory -Force "$WorkDir\wt\.git" | Out-Null
Dproj "$WorkDir\wt\src\cli\Tool.dproj" @(($Marker32 -replace 'Win32', 'Win64'), '  </PropertyGroup>', '  <ItemGroup>', '    <DCCReference Include="..\report\uRep.pas"/>', '  </ItemGroup>')
PasUnit "$WorkDir\wt\src\report\uRep.pas"
$f = "$WorkDir\wt\src\report\uRep.pas"
$s = Session @($f) @($dbLib)
Check 'WT: src\report finds src\cli\Tool.dproj, Win64' ($s.Ctx[$f].project -like '*\wt\src\cli\Tool.dproj' -and $s.Ctx[$f].platform -eq 'Win64' -and (NoPlatformMsg $s)) (($s.Ctx[$f] | ConvertTo-Json -Compress) + ' ' + (Texts $s))

Write-Host 'MANY: two indexes hold the file' -ForegroundColor Cyan
$f = "$WorkDir\many\s\uShared.pas"
$s = Session @($f) @("$WorkDir\many\First\_D-RAG\First.sqlite", "$WorkDir\many\Second\_D-RAG\Second.sqlite", $dbLib)
Check 'MANY: the first in order is used' ($s.Ctx[$f].project -like '*\First\First.dproj') ($s.Ctx[$f] | ConvertTo-Json -Compress)
$m = @($s.Messages | Where-Object { $_.message -match 'First\.dproj' -and $_.message -match 'Second' -and $_.message -match 'dragLint\.selectProject' })
Check 'MANY: an info message says which, and names the other' ($m.Count -eq 1 -and $m[0].type -eq 3) (Texts $s)
Check 'MANY: not in the per-file notice (a shared unit is normal)' ($s.Ctx[$f].notice -eq '') $s.Ctx[$f].notice

Write-Host 'UNK: truly unknown' -ForegroundColor Cyan
$a1 = "$WorkDir\nowhere\f1\uA1.pas"; $a2 = "$WorkDir\nowhere\f1\uA2.pas"; $b1 = "$WorkDir\nowhere\f2\uB1.pas"
$s = Session @($a1, $a2, $b1) @($dbLib)
$pl = @($s.Messages | Where-Object { $_.message -match 'no platform is known' })
$pr = @($s.Messages | Where-Object { $_.message -match 'no project is known' })
Check 'UNK: the platform message once per folder, not per file (3 files, 2 folders)' ($pl.Count -eq 2) (Texts $s)
Check 'UNK: the project message once per folder' ($pr.Count -eq 2) (Texts $s)
Check 'UNK: info level (type 3)' (@($pl + $pr | Where-Object { $_.type -ne 3 }).Count -eq 0) (Texts $s)
Check 'UNK: the platform message says what to do' (@($pl | Where-Object { $_.message -match 'dragLint\.selectPlatform' -and $_.message -match '\.dlcontext\.json' }).Count -eq 2) (Texts $s)
Check 'UNK: the project message says what to do' (@($pr | Where-Object { $_.message -match 'dragLint\.selectProject' -and $_.message -match '\.dlcontext\.json' }).Count -eq 2) (Texts $s)
Check 'UNK: the status notice is marked level=info' ($s.Ctx[$a1].level -eq 'info' -and $s.Ctx[$a1].notice -match 'no platform is known') ($s.Ctx[$a1] | ConvertTo-Json -Compress)
Check 'PC: the second file still has its notice text' ($s.Ctx[$a2].notice -match 'no platform is known') ($s.Ctx[$a2] | ConvertTo-Json -Compress)

Write-Host 'CLI: the settings the extension passes win' -ForegroundColor Cyan
$s = Session @($a1) @($dbLib) @{ platform = 'Win32' }
Check 'CLI: dragLint.platform -> that platform, no platform notice' ($s.Ctx[$a1].platform -eq 'Win32' -and (NoPlatformMsg $s)) (($s.Ctx[$a1] | ConvertTo-Json -Compress) + ' ' + (Texts $s))
$s = Session @($a1) @($dbLib) @{ project = "$R\other\Other.dproj"; platform = 'Win64' }
Check 'CLI: dragLint.project -> that project, source client' ($s.Ctx[$a1].project -like '*\other\Other.dproj' -and $s.Ctx[$a1].source -eq 'client') ($s.Ctx[$a1] | ConvertTo-Json -Compress)
$f = "$R\shared\uMember.pas"
$s = Session @($f) @($dbLib) @{ project = "$R\other\Other.dproj"; platform = 'Win64' }
Check 'CLI: a set project beats the source search' ($s.Ctx[$f].project -like '*\other\Other.dproj' -and $s.Ctx[$f].platform -eq 'Win64') ($s.Ctx[$f] | ConvertTo-Json -Compress)

Write-Host ("RESULT: {0} pass, {1} fail" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Failed) { 'Red' } else { 'Green' })
if ($script:Failed) { exit 1 }
exit 0
} finally {
  $env:DRAGLINT_CONTEXT_DEFAULTS = $null; $env:DRAGLINT_LSP_REINDEX_EXE = $null
  try { if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) } } catch { Write-Host "note: $WorkDir left behind: $_" }
}
