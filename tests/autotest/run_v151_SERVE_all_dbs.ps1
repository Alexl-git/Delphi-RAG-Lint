#Requires -Version 7
<#
  run_v151_SERVE_all_dbs.ps1 -- wave v151 lane SERVE (owner OQ3): the MCP server `serve`
  answers from EVERY relevant database -- the project DB plus every library section of the
  platform -- not only the first one.

  Before v151, `serve` with no --db resolved the manifest's list (project DB first, then
  each library section) and kept ONLY the first entry (stderr NOTE "serve uses only the
  FIRST"); `serve --db A --db B` opened A and named B as "ignored". A question about a
  library routine (find_symbol, get_symbol_doc, ...) then answered "nothing found" although
  the configured libraries hold it.

  Hermetic: an engine copy without the machine drag-lint.json (HermeticEngine.ps1) and a
  private manifest published through DRAGLINT_MANIFEST. Fixture: one project section (Proj,
  calls into both libraries) and THREE library sections: Library + LibExtra for Win64,
  LibW32 for Win32 only.

  Cases (RED on the 1.50.0-alpha base: S1, S2, S3, S5, C2, M1, M2 fail):
    S0  control: find_symbol finds the project's own routine
    S1  find_symbol finds a routine of the FIRST library section
    S2  find_symbol finds a routine of the SECOND library section
    S1/S2 path: each row's file comes from the database that holds the symbol (a file id is per DB)
    S3  get_symbol_doc answers for a qname that only the second library holds
    S4  control: find_callers on a library routine lists the project call site (call graph = project DB)
    S5  no "uses only the FIRST" note on stderr; the served databases are named on stderr
    C1  control: a Win32-only library section never leaks into a Win64 serve
    C2  a name in BOTH project and library lists the project's symbol first, then the library's
    C3  control: another project's section (Other) is not served, and stderr says so
    M1  explicit `--db proj --db lib2`: find_symbol answers from the second --db
    M2  ... and stderr no longer calls the second --db "ignored"
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v151-serve-alldbs-$PID",
  [switch]$Keep
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
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
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [IO.File]::WriteAllText($path, $t, (New-Object Text.ASCIIEncoding))
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # no machine drag-lint.json
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
foreach ($d in 'projsrc','othersrc','lib1src','lib2src','lib3src','OUT') { New-Item -ItemType Directory "$WorkDir\$d" -Force | Out-Null }

WriteAnsi "$WorkDir\lib1src\LibOneUnit.pas" @'
unit LibOneUnit;

interface

procedure LibOneRoutine(AValue: Integer);
procedure SharedName;

implementation

procedure LibOneRoutine(AValue: Integer);
begin
end;

procedure SharedName;
begin
end;

end.
'@
WriteAnsi "$WorkDir\lib2src\LibTwoUnit.pas" @'
unit LibTwoUnit;

interface

/// <summary>Only the second library section declares this routine.</summary>
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
procedure SharedName;

implementation

uses
  LibOneUnit, LibTwoUnit;

procedure DriveProject;
begin
  LibOneRoutine(1);
  LibTwoOnlyRoutine(2);
end;

procedure SharedName;
begin
end;

end.
'@

WriteAnsi "$WorkDir\othersrc\OtherUnit.pas" @"
unit OtherUnit;

interface

procedure OtherProjectRoutine;

implementation

procedure OtherProjectRoutine;
begin
end;

end.
"@

$projDb = Join-Path $WorkDir 'OUT\Proj.sqlite'
$otherDb = Join-Path $WorkDir 'OUT\Other.sqlite'
$lib1Db = Join-Path $WorkDir 'OUT\library-Win64.sqlite'
$lib2Db = Join-Path $WorkDir 'OUT\libextra-Win64.sqlite'
$lib3Db = Join-Path $WorkDir 'OUT\libw32-Win32.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index "$WorkDir\projsrc" --db $projDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
& { $ErrorActionPreference = 'Continue'; & $Exe index "$WorkDir\othersrc" --db $otherDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
& { $ErrorActionPreference = 'Continue'; & $Exe index "$WorkDir\lib1src" --db $lib1Db 2>&1 | ForEach-Object { "$_" } } | Out-Null
& { $ErrorActionPreference = 'Continue'; & $Exe index "$WorkDir\lib2src" --db $lib2Db 2>&1 | ForEach-Object { "$_" } } | Out-Null
& { $ErrorActionPreference = 'Continue'; & $Exe index "$WorkDir\lib3src" --db $lib3Db 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'built fixture indexes' ((Test-Path $projDb) -and (Test-Path $lib1Db) -and (Test-Path $lib2Db) -and (Test-Path $lib3Db))

function Section-Lib([string]$Name, [string]$Db, [string[]]$Platforms) {
  return [ordered]@{ name = $Name; db = $Db; source = 'registry-libraries'; platforms = $Platforms; include = @() }
}
$manifest = Join-Path $WorkDir 'all.drag-lint.json'
$m = [ordered]@{
  settings = [ordered]@{ defaultPlatform = 'Win64' }
  indexes  = [ordered]@{ outDir = 'OUT'; exclude = @(); sections = @(
    [ordered]@{ name = 'Proj'; include = @('projsrc') },
    [ordered]@{ name = 'Other'; include = @('othersrc') },
    (Section-Lib 'Library' 'library-{platform}.sqlite' @('Win64')),
    (Section-Lib 'LibExtra' 'libextra-{platform}.sqlite' @('Win64')),
    (Section-Lib 'LibW32' 'libw32-{platform}.sqlite' @('Win32'))) }
}
[IO.File]::WriteAllText($manifest, ($m | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

function Call([int]$Id, [string]$Tool, [hashtable]$Arguments) {
  (@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } } | ConvertTo-Json -Compress -Depth 6)
}
function Text($Reply) { if ($Reply -and $Reply.result -and $Reply.result.content.Count -gt 0) { [string]$Reply.result.content[0].text } else { '' } }
# One serve session: stdin from a file, one JSON reply per line. Returns @{ replies; err }.
function Invoke-Serve([string[]]$ServeArgs, [string[]]$Requests, [string]$Tag) {
  $in  = Join-Path $WorkDir "$Tag.in.jsonl"
  $out = Join-Path $WorkDir "$Tag.out.jsonl"
  $err = Join-Path $WorkDir "$Tag.err.txt"
  $all = @('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}') + $Requests
  [IO.File]::WriteAllText($in, (($all -join "`n") + "`n"), [Text.Encoding]::ASCII)
  $env:DRAGLINT_MANIFEST = $manifest
  try {
    $p = Start-Process $Exe -ArgumentList (@('serve') + $ServeArgs) -WorkingDirectory $WorkDir `
           -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
    if (-not $p.WaitForExit(60000)) { $p.Kill($true) }
  } finally { $env:DRAGLINT_MANIFEST = $null }
  $replies = @{}
  foreach ($line in (Get-Content $out -ErrorAction SilentlyContinue)) {
    if ($line.Trim() -eq '') { continue }
    try { $j = $line | ConvertFrom-Json } catch { continue }
    if ($null -ne $j.id) { $replies[[string]$j.id] = $j }
  }
  return @{ replies = $replies; err = [string](Get-Content $err -Raw -ErrorAction SilentlyContinue) }
}

Write-Host 'S0-S5, C1, C2: serve with no --db (manifest-driven, Win64)' -ForegroundColor Cyan
$r = Invoke-Serve @('--platform', 'Win64') @(
  (Call 1 'find_symbol'    @{ name  = 'DriveProject' }),
  (Call 2 'find_symbol'    @{ name  = 'LibOneRoutine' }),
  (Call 3 'find_symbol'    @{ name  = 'LibTwoOnlyRoutine' }),
  (Call 4 'get_symbol_doc' @{ qname = 'LibTwoUnit.LibTwoOnlyRoutine' }),
  (Call 5 'find_callers'   @{ name  = 'LibTwoOnlyRoutine' }),
  (Call 6 'find_symbol'    @{ name  = 'LibWin32OnlyRoutine' }),
  (Call 7 'find_symbol'    @{ name  = 'SharedName' }),
  (Call 8 'find_symbol'    @{ name  = 'OtherProjectRoutine' })) 'nodb'
$t1 = Text $r.replies['1']; $t2 = Text $r.replies['2']; $t3 = Text $r.replies['3']; $t4 = Text $r.replies['4']
$t5 = Text $r.replies['5']; $t6 = Text $r.replies['6']; $t7 = Text $r.replies['7']
Check 'S0 find_symbol finds the project routine (control)' ($t1 -match 'ProjUnit\.DriveProject') "got: [$t1] err: [$($r.err)]"
Check 'S1 find_symbol finds the FIRST library section''s routine' ($t2 -match 'LibOneUnit\.LibOneRoutine') "got: [$t2]"
Check 'S2 find_symbol finds the SECOND library section''s routine' ($t3 -match 'LibTwoUnit\.LibTwoOnlyRoutine') "got: [$t3]"
Check 'S1/S2 ... each row names the file from ITS OWN database' (($t2 -match 'lib1src[\\/]LibOneUnit\.pas:\d+') -and ($t3 -match 'lib2src[\\/]LibTwoUnit\.pas:\d+')) "got: [$t2] [$t3]"
Check 'S3 get_symbol_doc answers from the second library' ($t4 -match 'Only the second library section') "got: [$t4]"
Check 'S4 find_callers on a library routine lists the project call site (control)' ($t5 -match 'ProjUnit\.pas:\d+') "got: [$t5]"
Check 'S5 no "uses only the FIRST" note' ($r.err -notmatch '(?i)only the first') "err: [$($r.err)]"
Check 'S5 ... and stderr names every served database' (($r.err -match 'Proj\.sqlite') -and ($r.err -match 'library-Win64\.sqlite') -and ($r.err -match 'libextra-Win64\.sqlite')) "err: [$($r.err)]"
Check 'C1 a Win32-only library section does not leak into Win64' (($t6 -notmatch 'LibWin32Unit\.LibWin32OnlyRoutine') -and ($r.err -notmatch 'libw32')) "got: [$t6]"
$t8 = Text $r.replies['8']
Check 'C3 another project''s index in the manifest is not served' (($t8 -notmatch 'OtherUnit\.OtherProjectRoutine') -and ($r.err -notmatch 'Other\.sqlite')) "got: [$t8]"
Check 'C3 ... and stderr says one other database is not served' ($r.err -match '1 other database') "err: [$($r.err)]"
$iP = $t7.IndexOf('ProjUnit.SharedName'); $iL = $t7.IndexOf('LibOneUnit.SharedName')
Check 'C2 a name in project and library lists the project symbol first' (($iP -ge 0) -and ($iL -gt $iP)) "got: [$t7]"

Write-Host 'M1/M2: explicit --db list' -ForegroundColor Cyan
$r2 = Invoke-Serve @('--db', $projDb, '--db', $lib2Db) @(
  (Call 1 'find_symbol' @{ name = 'LibTwoOnlyRoutine' }),
  (Call 2 'find_symbol' @{ name = 'DriveProject' })) 'twodb'
$u1 = Text $r2.replies['1']; $u2 = Text $r2.replies['2']
Check 'M1 find_symbol answers from the second --db' ($u1 -match 'LibTwoUnit\.LibTwoOnlyRoutine') "got: [$u1] err: [$($r2.err)]"
Check 'M1 ... and still from the first (control)' ($u2 -match 'ProjUnit\.DriveProject') "got: [$u2]"
Check 'M2 the second --db is not reported as ignored' ($r2.err -notmatch '(?i)ignored') "err: [$($r2.err)]"

} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
finally { if ((-not $Keep) -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } } }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
