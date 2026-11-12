#Requires -Version 7
<#
  run_dbselect_all_library_sections.ps1 -- wave 152b DBS / O4: TDbSelect.Resolve returns EVERY
  library section of the platform, not only the first one.

  Before 152b, TDbSelect.Resolve kept the FIRST library section that matched the platform
  ("If multiple library sections somehow match, keep the first"), so a manifest with two
  library sections (registry libraries + a vendor library, say) hid the second one from every
  manifest-driven consumer: query, resolve-dbs and the LSP. ResolveLibraryDbs
  (lint's redundant-cast path) already walked all of them (151 RC); the two paths disagreed.

  Hermetic: an engine copy without the machine drag-lint.json (HermeticEngine.ps1) and a private
  manifest published through DRAGLINT_MANIFEST. Fixture: one project section (Proj) and TWO
  library sections for Win64 (Library -> library-Win64.sqlite, LibExtra -> libextra-Win64.sqlite).
  LibOneRoutine lives only in the first library, LibTwoOnlyRoutine only in the second.

  MCP (`serve`) is NOT a consumer of this list: with no --db it opens only the FIRST resolved
  DB (its own stderr NOTE says so) and reads a library only through a per-call library_db
  argument, so it is out of O4's reach by design (REPORT: DBS, owner question).
  The LSP also reads %LOCALAPPDATA%\drag-lint\context-defaults.json, whose library outranks the
  manifest's: the guard points DRAGLINT_CONTEXT_DEFAULTS at an empty private file.

  Cases (RED on the 1.50.0-alpha base: R1, R2, L1 fail):
    P1  positive control: query finds LibOneRoutine (section 1) -- the manifest route works at all
    R1  resolve-dbs --json lists libextra-Win64.sqlite, AFTER library-Win64.sqlite (manifest order)
    R2  query --name LibTwoOnlyRoutine finds it through the manifest
    L0  LSP hover on a LibOneRoutine call answers (positive control for the hover probe)
    L1  LSP hover on a LibTwoOnlyRoutine call answers from the second library
    C1  control: with the LibExtra section removed, query / resolve-dbs do NOT see it
    C2  control: a Win32-only third library section never leaks into a Win64 answer
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dbselect-libs-$PID",
  [switch]$Keep
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
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [IO.File]::WriteAllText($path, $t, (New-Object Text.ASCIIEncoding))
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 12
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # no machine drag-lint.json
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
foreach ($d in 'projsrc','lib1src','lib2src','lib3src','loose','OUT') { New-Item -ItemType Directory "$WorkDir\$d" -Force | Out-Null }

WriteAnsi "$WorkDir\lib1src\LibOneUnit.pas" @'
unit LibOneUnit;

interface

procedure LibOneRoutine(AValue: Integer);

implementation

procedure LibOneRoutine(AValue: Integer);
begin
end;

end.
'@
WriteAnsi "$WorkDir\lib2src\LibTwoUnit.pas" @'
unit LibTwoUnit;

interface

procedure LibTwoOnlyRoutine(AValue: Integer);

implementation

procedure LibTwoOnlyRoutine(AValue: Integer);
begin
end;

end.
'@
WriteAnsi "$WorkDir\lib3src\LibWin32Unit.pas" @'
unit LibWin32Unit;

interface

procedure LibWin32OnlyRoutine(AValue: Integer);

implementation

procedure LibWin32OnlyRoutine(AValue: Integer);
begin
end;

end.
'@
WriteAnsi "$WorkDir\projsrc\ProjUnit.pas" @'
unit ProjUnit;

interface

procedure DriveProject;

implementation

procedure DriveProject;
begin
end;

end.
'@
$looseText = @'
unit LooseUnit;

interface

procedure DriveLoose;

implementation

uses
  LibOneUnit, LibTwoUnit;

procedure DriveLoose;
begin
  LibOneRoutine(1);
  LibTwoOnlyRoutine(2);
end;

end.
'@
$looseFile = Join-Path $WorkDir 'loose\LooseUnit.pas'
WriteAnsi $looseFile $looseText

$projDb = Join-Path $WorkDir 'OUT\Proj.sqlite'
$lib1Db = Join-Path $WorkDir 'OUT\library-Win64.sqlite'
$lib2Db = Join-Path $WorkDir 'OUT\libextra-Win64.sqlite'
$lib3Db = Join-Path $WorkDir 'OUT\libw32-Win32.sqlite'
& $Exe index "$WorkDir\projsrc" --db $projDb 2>&1 | Out-Null
& $Exe index "$WorkDir\lib1src" --db $lib1Db 2>&1 | Out-Null
& $Exe index "$WorkDir\lib2src" --db $lib2Db 2>&1 | Out-Null
& $Exe index "$WorkDir\lib3src" --db $lib3Db 2>&1 | Out-Null
Check 'built fixture indexes' ((Test-Path $projDb) -and (Test-Path $lib1Db) -and (Test-Path $lib2Db) -and (Test-Path $lib3Db))

function Section-Lib([string]$Name, [string]$Db, [string[]]$Platforms) {
  return [ordered]@{ name = $Name; db = $Db; source = 'registry-libraries'; platforms = $Platforms; include = @() }
}
function Write-Manifest([string]$Path, [object[]]$Sections) {
  $m = [ordered]@{
    settings = [ordered]@{ defaultPlatform = 'Win64' }
    indexes  = [ordered]@{ outDir = 'OUT'; exclude = @(); sections = $Sections }
  }
  [IO.File]::WriteAllText($Path, ($m | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}
$projSec = [ordered]@{ name = 'Proj'; include = @('projsrc') }
$both    = Join-Path $WorkDir 'both.drag-lint.json'
$oneOnly = Join-Path $WorkDir 'one.drag-lint.json'
Write-Manifest $both    @($projSec, (Section-Lib 'Library' 'library-{platform}.sqlite' @('Win64')),
                          (Section-Lib 'LibExtra' 'libextra-{platform}.sqlite' @('Win64')),
                          (Section-Lib 'LibW32' 'libw32-{platform}.sqlite' @('Win32')))
Write-Manifest $oneOnly @($projSec, (Section-Lib 'Library' 'library-{platform}.sqlite' @('Win64')))

function Run-Engine([string]$Manifest, [string[]]$EngineArgs) {
  $env:DRAGLINT_MANIFEST = $Manifest
  Push-Location $WorkDir
  try { return (& $Exe @EngineArgs 2>&1 | Out-String) } finally { Pop-Location; $env:DRAGLINT_MANIFEST = $null }
}

Write-Host 'P1/R1/R2: query + resolve-dbs through a two-library manifest' -ForegroundColor Cyan
$q1 = Run-Engine $both @('query', '--name', 'LibOneRoutine', '--platform', 'Win64')
Check 'P1 query finds the FIRST library section''s symbol (control)' ($q1 -match 'LibOneUnit\.LibOneRoutine') "got: [$q1]"
$rd = Run-Engine $both @('resolve-dbs', '--platform', 'Win64', '--json')
$rdList = @()
try { $rdList = @(($rd -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('[') } | Select-Object -Last 1) | ConvertFrom-Json) } catch { $rdList = @() }
$i1 = [Array]::FindIndex([string[]]$rdList, [Predicate[string]]{ param($x) $x -like '*library-Win64.sqlite' })
$i2 = [Array]::FindIndex([string[]]$rdList, [Predicate[string]]{ param($x) $x -like '*libextra-Win64.sqlite' })
Check 'R1 resolve-dbs lists libextra-Win64 after library-Win64' (($i1 -ge 0) -and ($i2 -gt $i1)) "got: [$($rdList -join ' | ')]"
Check 'R1 resolve-dbs lists the project DB first' (($rdList.Count -gt 0) -and ($rdList[0] -like '*Proj.sqlite')) "got: [$($rdList -join ' | ')]"
$q2 = Run-Engine $both @('query', '--name', 'LibTwoOnlyRoutine', '--platform', 'Win64')
Check 'R2 query finds the SECOND library section''s symbol' ($q2 -match 'LibTwoUnit\.LibTwoOnlyRoutine') "got: [$q2]"

Write-Host 'C1/C2: controls' -ForegroundColor Cyan
$c1q = Run-Engine $oneOnly @('query', '--name', 'LibTwoOnlyRoutine', '--platform', 'Win64')
Check 'C1 without the LibExtra section the symbol is absent' ($c1q -notmatch 'LibTwoUnit\.LibTwoOnlyRoutine') "got: [$c1q]"
$c1r = Run-Engine $oneOnly @('resolve-dbs', '--platform', 'Win64', '--json')
Check 'C1 ... and resolve-dbs does not list libextra' (($c1r -notmatch 'libextra') -and ($c1r -match 'library-Win64')) "got: [$c1r]"
$c2q = Run-Engine $both @('query', '--name', 'LibWin32OnlyRoutine', '--platform', 'Win64')
Check 'C2 a Win32-only library section does not leak into Win64' ($c2q -notmatch 'LibWin32Unit\.LibWin32OnlyRoutine') "got: [$c2q]"
Check 'C2 ... and resolve-dbs Win64 does not list it' ($rd -notmatch 'libw32') "got: [$rd]"

Write-Host 'L0/L1: LSP hover, no --db (manifest-driven)' -ForegroundColor Cyan
$lines = $looseText -split "`r?`n"
$noDefaults = Join-Path $WorkDir 'no-context-defaults.json'
[IO.File]::WriteAllText($noDefaults, '{"libraries":{}}', (New-Object Text.UTF8Encoding($false)))
function Hover-At([string]$Needle, [string]$Tag) {
  $ln  = [Array]::FindIndex($lines, [Predicate[string]]{ param($x) $x -like "*$Needle(*" })
  $col = $lines[$ln].IndexOf($Needle) + 3
  $uri = 'file:///' + ($looseFile -replace '\\', '/')
  $msgs  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $msgs += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $msgs += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$looseText } } }
  $msgs += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/hover'; params=@{ textDocument=@{ uri=$uri }; position=@{ line=$ln; character=$col } } }
  $msgs += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF = Join-Path $WorkDir "$Tag-in.txt"; $outF = Join-Path $WorkDir "$Tag-out.txt"; $errF = Join-Path $WorkDir "$Tag-err.txt"
  [IO.File]::WriteAllText($inF, $msgs, (New-Object Text.ASCIIEncoding))
  $env:DRAGLINT_MANIFEST = $both
  $env:DRAGLINT_CONTEXT_DEFAULTS = $noDefaults
  try {
    $p = Start-Process $Exe -ArgumentList @('lsp', '--platform', 'Win64') -WorkingDirectory $WorkDir -RedirectStandardInput $inF `
      -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -PassThru
    if (-not $p.WaitForExit(60000)) { $p.Kill($true) }
  } finally { $env:DRAGLINT_MANIFEST = $null; $env:DRAGLINT_CONTEXT_DEFAULTS = $null }
  $raw = [IO.File]::ReadAllText($outF)
  $hover = ''
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $null -ne $o.result) { $hover = [string]$o.result.contents.value }
  }
  return $hover
}
$h0 = Hover-At 'LibOneRoutine' 'l0'
Check 'L0 LSP hover answers from the first library (control)' ($h0 -match 'LibOneUnit\.LibOneRoutine') "got: [$h0]"
$h1 = Hover-At 'LibTwoOnlyRoutine' 'l1'
Check 'L1 LSP hover answers from the second library' ($h1 -match 'LibTwoUnit\.LibTwoOnlyRoutine') "got: [$h1]"

} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
finally { if ((-not $Keep) -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } } }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
