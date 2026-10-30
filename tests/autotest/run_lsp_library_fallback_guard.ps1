#Requires -Version 7
<#
  run_lsp_library_fallback_guard.ps1 -- LSP 1.39 lsp-libfb: explicit --db and the library.

  With explicit --db only a listed library-<platform> store counts as the library
  (battery-138). A VS Code user whose dragLint.databases lists only project DBs
  would then get NO library. The fix: when no listed library-<active platform>
  store exists, fall back to the central defaults' library for the ACTIVE platform
  only, and say so in the draglint/context notice ("library from context defaults").

  Hermetic: a private defaults file (DRAGLINT_CONTEXT_DEFAULTS) + a private library DB.
  Cases:
    a  --db project only + defaults Win64 library -> library hover answers + notice
    b  --db project + listed library-Win64        -> listed one answers, NO fallback notice
    c  defaults has only a Win32 library, active Win64 -> no library answer, no notice, no leak
  Positive control: case b proves the hover probe can answer from a library at all.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-libfb-guard-$PID"
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
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
foreach ($d in 'libsrc','projsrc','loose','listed') { New-Item -ItemType Directory "$WorkDir\$d" -Force | Out-Null }

WriteAnsi "$WorkDir\libsrc\FarAwayLib.pas" @'
unit FarAwayLib;

interface

procedure LibraryOnlyRoutine(AValue: Integer);

implementation

procedure LibraryOnlyRoutine(AValue: Integer);
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
  FarAwayLib;

procedure DriveLoose;
begin
  LibraryOnlyRoutine(2);
end;

end.
'@
$looseFile = Join-Path $WorkDir 'loose\LooseUnit.pas'
WriteAnsi $looseFile $looseText

# the DEFAULTS library is deliberately NOT named library-<platform> (dctx-*.sqlite):
# only the fallback can bring it in. The listed library of case b is library-Win64.sqlite.
$DefLib = Join-Path $WorkDir 'dctx-win64.sqlite'
$Lib32  = Join-Path $WorkDir 'dctx-win32.sqlite'
$Listed = Join-Path $WorkDir 'listed\library-Win64.sqlite'
$projDb = Join-Path $WorkDir 'proj.sqlite'
& $Exe index "$WorkDir\libsrc"  --db $DefLib  2>&1 | Out-Null
& $Exe index "$WorkDir\libsrc"  --db $Lib32   2>&1 | Out-Null
& $Exe index "$WorkDir\libsrc"  --db $Listed  2>&1 | Out-Null
& $Exe index "$WorkDir\projsrc" --db $projDb  2>&1 | Out-Null
Check 'built fixture indexes' ((Test-Path $DefLib) -and (Test-Path $Lib32) -and (Test-Path $Listed) -and (Test-Path $projDb))

$lines = $looseText -split "`r?`n"
$ln  = [Array]::FindIndex($lines, [Predicate[string]]{ param($x) $x -like '*LibraryOnlyRoutine(2);*' })
$col = $lines[$ln].IndexOf('LibraryOnlyRoutine') + 4

function Run-Case([string]$Tag, [string[]]$Dbs, [hashtable]$Defaults) {
  $dfile = Join-Path $WorkDir "$Tag-defaults.json"
  [IO.File]::WriteAllText($dfile, ($Defaults | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
  $env:DRAGLINT_CONTEXT_DEFAULTS = $dfile
  $uri = 'file:///' + ($looseFile -replace '\\', '/')
  $msgs  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $msgs += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $msgs += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$looseText } } }
  $msgs += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/hover'; params=@{ textDocument=@{ uri=$uri }; position=@{ line=$ln; character=$col } } }
  $msgs += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF = Join-Path $WorkDir "$Tag-in.txt"; $outF = Join-Path $WorkDir "$Tag-out.txt"; $errF = Join-Path $WorkDir "$Tag-err.txt"
  [IO.File]::WriteAllText($inF, $msgs, (New-Object Text.ASCIIEncoding))
  $a = @('lsp'); foreach ($d in $Dbs) { $a += @('--db', $d) }
  Start-Process $Exe -ArgumentList $a -WorkingDirectory $WorkDir -RedirectStandardInput $inF `
    -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait | Out-Null
  $raw = [IO.File]::ReadAllText($outF)
  $hover = ''; $notice = ''
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $null -ne $o.result) { $hover = [string]$o.result.contents.value }
    if ($o.method -eq 'draglint/context') { $notice += [string]$o.params.notice + ' ' }
  }
  return @{ Hover = $hover; Notice = $notice }
}

Write-Host 'a: --db project only, defaults library for Win64' -ForegroundColor Cyan
$ra = Run-Case 'a' @($projDb) @{ libraries = @{ Win64 = @{ libraryDb = $DefLib } } }
Check 'a: hover resolves from the defaults library' ($ra.Hover -match 'FarAwayLib\.LibraryOnlyRoutine') "got: [$($ra.Hover)]"
Check 'a: draglint/context notice says "library from context defaults"' ($ra.Notice -match 'library from context defaults') "got: [$($ra.Notice)]"

Write-Host 'b: --db project + listed library-Win64 (positive control)' -ForegroundColor Cyan
$rb = Run-Case 'b' @($projDb, $Listed) @{ libraries = @{ Win64 = @{ libraryDb = $DefLib } } }
Check 'b: hover resolves from the listed library' ($rb.Hover -match 'FarAwayLib\.LibraryOnlyRoutine') "got: [$($rb.Hover)]"
Check 'b: no fallback notice (listed library wins)' ($rb.Notice -notmatch 'library from context defaults') "got: [$($rb.Notice)]"

Write-Host 'c: defaults has only a Win32 library, active platform Win64' -ForegroundColor Cyan
$rc = Run-Case 'c' @($projDb) @{ libraries = @{ Win32 = @{ libraryDb = $Lib32 } } }
Check 'c: no library answer (no wrong-platform leak)' ($rc.Hover -notmatch 'FarAwayLib\.LibraryOnlyRoutine') "got: [$($rc.Hover)]"
Check 'c: no fallback notice' ($rc.Notice -notmatch 'library from context defaults') "got: [$($rc.Notice)]"
Check 'c: the existing no-library notice is still given' ($rc.Notice -match 'no library index') "got: [$($rc.Notice)]"
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
