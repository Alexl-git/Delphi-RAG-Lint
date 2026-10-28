#Requires -Version 7
<#
  run_lsp_context_isolation_guard.ps1 -- LSP-1 CORE (SPEC lsp-context 1b / 3,
  owner ruling D1): the LSP answers a file from ITS project's DB + ITS platform's
  library DB only -- like the Delphi IDE -- never from another project's store.

  Fixture (all under $WorkDir; the real user context-defaults file is never read:
  DRAGLINT_CONTEXT_DEFAULTS points at a fixture path):
    A\A.dproj + uA.pas  (declares OnlyInA; calls OnlyInB + LibOnly)  -> A.sqlite
    B\B.dproj + uB.pas  (declares OnlyInB)                            -> B.sqlite
    lib\uLib.pas        (declares LibOnly)                            -> library-Win64.sqlite
    loose\uLoose.pas    no project anywhere above it
    C\C.dproj + uC.pas  a project with no index (unowned file)
    L\L.dpr + L.dlcontext.json (platform Linux64, no .dproj) + uL.pas
  Every session: lsp --db A.sqlite --db B.sqlite --db library-Win64.sqlite.

  ISO  hover OnlyInB in A        -> null (B is another project)      PC: OnlyInA answers + footer names A.dproj
  UNK  hover OnlyInA in loose    -> null + showMessage "no project"   PC: LibOnly answers; footer "context: none"
  UNO  hover OnlyInA in C        -> null; diagnostics "(unowned)"     PC: LibOnly answers
  LNX  hover LibOnly in L        -> null + "no library index ... Linux64"  PC: OwnL answers (its own unit)
  CLI  draglint.setContext / initializationOptions / didChangeConfiguration(dragLint)
       -> draglint/context {project, platform, config, source, notice}; source = client

  RUN RED FIRST on the deployed engine: ISO, UNK, UNO, LNX and CLI fail; every PC passes.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-ctx-iso-$PID"
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
function Lines([string[]]$a) { ($a -join "`r`n") + "`r`n" }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
foreach ($d in 'A', 'B', 'lib', 'loose', 'C', 'L') { New-Item -ItemType Directory -Force "$WorkDir\$d" | Out-Null }
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"   # never the user's real file

function Dproj($main) {
  Lines @('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">', '  <PropertyGroup>',
    "    <MainSource>$main</MainSource>",
    "    <Config Condition=`"'`$(Config)'==''`">Debug</Config>",
    "    <Platform Condition=`"'`$(Platform)'==''`">Win64</Platform>", '  </PropertyGroup>', '</Project>')
}
Write-Ascii "$WorkDir\A\A.dproj" (Dproj 'A.dpr')
Write-Ascii "$WorkDir\B\B.dproj" (Dproj 'B.dpr')
Write-Ascii "$WorkDir\C\C.dproj" (Dproj 'C.dpr')
Write-Ascii "$WorkDir\A\uA.pas" (Lines @('unit uA;', 'interface', 'procedure OnlyInA;', 'implementation',
  'procedure OnlyInA;', 'begin', '  OnlyInB;', '  LibOnly;', 'end;', 'end.'))
Write-Ascii "$WorkDir\B\uB.pas" (Lines @('unit uB;', 'interface', 'procedure OnlyInB;', 'implementation',
  'procedure OnlyInB;', 'begin', 'end;', 'end.'))
Write-Ascii "$WorkDir\lib\uLib.pas" (Lines @('unit uLib;', 'interface', 'procedure LibOnly;', 'implementation',
  'procedure LibOnly;', 'begin', 'end;', 'end.'))
$userBody = @('begin', '  OnlyInA;', '  LibOnly;', 'end;')
Write-Ascii "$WorkDir\loose\uLoose.pas" (Lines (@('unit uLoose;', 'interface', 'procedure UseLoose;', 'implementation', 'procedure UseLoose;') + $userBody + @('end.')))
Write-Ascii "$WorkDir\C\uC.pas" (Lines (@('unit uC;', 'interface', 'procedure UseC(X: TObject);', 'implementation', 'procedure UseC(X: TObject);',
  'begin', '  with X do', '    Free;', '  OnlyInA;', '  LibOnly;', 'end;', 'end.')))
Write-Ascii "$WorkDir\L\uL.pas" (Lines @('unit uL;', 'interface', 'procedure OwnL;', 'implementation', 'procedure OwnL;',
  'begin', '  LibOnly;', '  OwnL;', 'end;', 'end.'))
Write-Ascii "$WorkDir\L\L.dpr" (Lines @('program L;', 'uses uL;', 'begin', 'end.'))
Write-Ascii "$WorkDir\L\L.dlcontext.json" ((@{ schema = 1; project = "$WorkDir\L\L.dpr"; platform = 'Linux64'; config = 'Release'
  source = @{ file = "$WorkDir\L\L.dpr"; sha1 = '' } } | ConvertTo-Json -Depth 5))

$dbA = "$WorkDir\A.sqlite"; $dbB = "$WorkDir\B.sqlite"; $dbL = "$WorkDir\library-Win64.sqlite"
& $Exe index "$WorkDir\A" --db $dbA 2>&1 | Out-Null
& $Exe index "$WorkDir\B" --db $dbB 2>&1 | Out-Null
& $Exe index "$WorkDir\lib" --db $dbL 2>&1 | Out-Null
Check 'SETUP: three fixture indexes built' ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path $dbL))

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
function Pos($file, $needle) {
  $ls = [System.IO.File]::ReadAllLines($file)
  for ($i = $ls.Count - 1; $i -ge 0; $i--) { $c = $ls[$i].IndexOf($needle); if ($c -ge 0) { return @{ line = $i; character = $c + 1 } } }
  throw "needle $needle not in $file"
}
# One session: open $file, hover each needle (ids 10..), optional extra frames before the hovers.
function Session($file, [string[]]$needles, $initOptions = $null, [object[]]$extra = @()) {
  $u = Uri $file
  $init = @{ processId = $null; rootUri = $null; capabilities = @{} }
  if ($initOptions) { $init.initializationOptions = $initOptions }
  $msgs = (Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = $init }) +
          (Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }) +
          (Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $u; languageId = 'pascal'; version = 1; text = [System.IO.File]::ReadAllText($file) } } })
  foreach ($x in $extra) { $msgs += (Frame $x) }
  $id = 10
  foreach ($n in $needles) {
    $msgs += (Frame @{ jsonrpc = '2.0'; id = $id; method = 'textDocument/hover'; params = @{ textDocument = @{ uri = $u }; position = (Pos $file $n) } })
    $id++
  }
  $msgs += (Frame @{ jsonrpc = '2.0'; id = 99; method = 'shutdown'; params = @{} }) + (Frame @{ jsonrpc = '2.0'; method = 'exit'; params = @{} })
  $in = "$WorkDir\in.txt"; $so = "$WorkDir\out.txt"; $se = "$WorkDir\err.txt"
  [System.IO.File]::WriteAllText($in, $msgs, (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $dbA, '--db', $dbB, '--db', $dbL) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $frames = @(Read-Frames ([System.IO.File]::ReadAllText($so)))
  $hov = @{}
  for ($k = 0; $k -lt $needles.Count; $k++) {
    $r = @($frames | Where-Object { $_.id -eq (10 + $k) })
    $hov[$needles[$k]] = if ($r.Count -gt 0 -and $null -ne $r[0].result) { [string]$r[0].result.contents.value } else { $null }
  }
  return @{ Hover = $hov; Frames = $frames
    Messages = @($frames | Where-Object { $_.method -eq 'window/showMessage' } | ForEach-Object { [string]$_.params.message })
    Context  = @($frames | Where-Object { $_.method -eq 'draglint/context' })
    Diags    = @($frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' }) }
}

Write-Host 'ISO: a file in project A never answers from project B' -ForegroundColor Cyan
$s = Session "$WorkDir\A\uA.pas" @('OnlyInB;', 'OnlyInA;', 'LibOnly;')
Check 'PC: OnlyInA (own project) answers' ($null -ne $s.Hover['OnlyInA;'])
Check 'PC: LibOnly (Win64 library) answers' ($null -ne $s.Hover['LibOnly;'])
Check 'ISO: OnlyInB (project B) does NOT answer' ($null -eq $s.Hover['OnlyInB;']) "got=[$($s.Hover['OnlyInB;'])]"
Check 'ISO: hover footer names A.dproj -- Win64' ([string]$s.Hover['OnlyInA;'] -match 'context: A\.dproj -- Win64')
$ctx = @($s.Context | Where-Object { $_.params.uri -eq (Uri "$WorkDir\A\uA.pas") })
Check 'ISO: draglint/context {project A.dproj, Win64, Debug, source dproj, notice ""}' ($ctx.Count -ge 1 -and
  $ctx[-1].params.project -like '*\A\A.dproj' -and $ctx[-1].params.platform -eq 'Win64' -and $ctx[-1].params.config -eq 'Debug' -and
  $ctx[-1].params.source -eq 'dproj' -and $ctx[-1].params.notice -eq '') ($ctx | ConvertTo-Json -Depth 5 -Compress)
Check 'ISO: no notice for a fully known context' ($s.Messages.Count -eq 0) ($s.Messages -join ' | ')

Write-Host 'UNK: no project anywhere -> library only + notice' -ForegroundColor Cyan
$s = Session "$WorkDir\loose\uLoose.pas" @('OnlyInA;', 'LibOnly;')
Check 'PC: LibOnly (library) answers' ($null -ne $s.Hover['LibOnly;'])
Check 'UNK: OnlyInA (project A) does NOT answer' ($null -eq $s.Hover['OnlyInA;']) "got=[$($s.Hover['OnlyInA;'])]"
Check 'UNK: showMessage names the unknown project, once' (@($s.Messages | Where-Object { $_ -match 'no project is known' }).Count -eq 1) ($s.Messages -join ' | ')
Check 'UNK: footer "context: none -- Win64 [default]"' ([string]$s.Hover['LibOnly;'] -match 'context: none -- Win64 \[default\]')

Write-Host 'UNO: project C has no index -> ephemeral + library, "(unowned)" label' -ForegroundColor Cyan
$s = Session "$WorkDir\C\uC.pas" @('OnlyInA;', 'LibOnly;')
Check 'PC: LibOnly (library) answers' ($null -ne $s.Hover['LibOnly;'])
Check 'UNO: OnlyInA (project A) does NOT answer' ($null -eq $s.Hover['OnlyInA;']) "got=[$($s.Hover['OnlyInA;'])]"
$src = @($s.Diags | Select-Object -Last 1 | ForEach-Object { $_.params.diagnostics } | Where-Object { $_.code -eq 'with-statement' } | ForEach-Object { [string]$_.source })
Check 'UNO: with-statement finding labelled "drag-lint (unowned)"' ($src.Count -ge 1 -and @($src | Where-Object { $_ -ne 'drag-lint (unowned)' }).Count -eq 0) "sources=[$($src -join ',')]"

Write-Host 'LNX: Linux64 context (dlcontext, no .dproj), no Linux64 library -> refused + notice' -ForegroundColor Cyan
$s = Session "$WorkDir\L\uL.pas" @('LibOnly;', 'OwnL;')
Check 'PC: OwnL (its own unit) answers' ($null -ne $s.Hover['OwnL;'])
Check 'LNX: LibOnly (Win64 library) does NOT answer' ($null -eq $s.Hover['LibOnly;']) "got=[$($s.Hover['LibOnly;'])]"
Check 'LNX: showMessage refuses the Linux64 library' (@($s.Messages | Where-Object { $_ -match 'no library index for platform Linux64' }).Count -eq 1) ($s.Messages -join ' | ')
Check 'LNX: footer "context: L.dpr -- Linux64"' ([string]$s.Hover['OwnL;'] -match 'context: L\.dpr -- Linux64')
$ctx = @($s.Context | Select-Object -Last 1)
Check 'LNX: draglint/context source dlcontext, notice set' ($ctx.Count -eq 1 -and $ctx[0].params.source -eq 'dlcontext' -and
  [string]$ctx[0].params.notice -match 'Linux64') ($ctx | ConvertTo-Json -Depth 5 -Compress)

Write-Host 'CLI: the client names the context' -ForegroundColor Cyan
$set = @{ jsonrpc = '2.0'; id = 5; method = 'workspace/executeCommand'
  params = @{ command = 'draglint.setContext'; arguments = @(@{ project = "$WorkDir\B\B.dproj"; platform = 'Win64'; config = 'Release' }) } }
$s = Session "$WorkDir\loose\uLoose.pas" @('LibOnly;') -extra @($set)
$r5 = @($s.Frames | Where-Object { $_.id -eq 5 })
Check 'CLI: setContext answers without error' ($r5.Count -eq 1 -and $null -eq $r5[0].error) ($r5 | ConvertTo-Json -Depth 5 -Compress)
$ctx = @($s.Context | Select-Object -Last 1)
Check 'CLI: draglint/context after setContext = B.dproj / Win64 / Release / client' ($ctx.Count -eq 1 -and $ctx[0].params.project -like '*\B\B.dproj' -and
  $ctx[0].params.platform -eq 'Win64' -and $ctx[0].params.config -eq 'Release' -and $ctx[0].params.source -eq 'client') ($ctx | ConvertTo-Json -Depth 5 -Compress)
Check 'CLI: footer follows setContext' ([string]$s.Hover['LibOnly;'] -match 'context: B\.dproj -- Win64') "got=[$($s.Hover['LibOnly;'])]"
$s = Session "$WorkDir\loose\uLoose.pas" @('LibOnly;') -initOptions @{ project = "$WorkDir\L\L.dlcontext.json" }
$ctx = @($s.Context | Select-Object -Last 1)
Check 'CLI: initializationOptions.project = a .dlcontext.json -> its project + platform' ($ctx.Count -eq 1 -and $ctx[0].params.project -like '*\L\L.dpr' -and
  $ctx[0].params.platform -eq 'Linux64' -and $ctx[0].params.source -eq 'client') ($ctx | ConvertTo-Json -Depth 5 -Compress)
Write-Ascii "$WorkDir\A\A.delphilsp.json" '{"settings":{"dllname":"dcc64370.dll","dccOptions":"-DDEBUG"}}'
$s = Session "$WorkDir\loose\uLoose.pas" @('LibOnly;') -initOptions @{ settingsFile = (Uri "$WorkDir\A\A.delphilsp.json") }
$ctx = @($s.Context | Select-Object -Last 1)
Check 'CLI: the IDE''s settingsFile (.delphilsp.json) names A.dproj, client' ($ctx.Count -eq 1 -and $ctx[0].params.project -like '*\A\A.dproj' -and
  $ctx[0].params.source -eq 'client') ($ctx | ConvertTo-Json -Depth 5 -Compress)
$cfg = @{ jsonrpc = '2.0'; method = 'workspace/didChangeConfiguration'; params = @{ settings = @{ dragLint = @{ project = "$WorkDir\A\A.dproj"; platform = 'Win64' } } } }
$s = Session "$WorkDir\loose\uLoose.pas" @('LibOnly;') -extra @($cfg)
$ctx = @($s.Context | Select-Object -Last 1)
Check 'CLI: didChangeConfiguration section dragLint -> A.dproj, client' ($ctx.Count -eq 1 -and $ctx[0].params.project -like '*\A\A.dproj' -and
  $ctx[0].params.source -eq 'client') ($ctx | ConvertTo-Json -Depth 5 -Compress)
$init = @($s.Frames | Where-Object { $_.id -eq 1 })
Check 'CLI: executeCommandProvider advertises draglint.setContext' ($init.Count -eq 1 -and
  @($init[0].result.capabilities.executeCommandProvider.commands) -contains 'draglint.setContext')

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  $env:DRAGLINT_CONTEXT_DEFAULTS = $null
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
