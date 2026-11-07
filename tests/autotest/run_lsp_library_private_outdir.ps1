<#
  run_lsp_library_private_outdir.ps1 -- E-PLATLIB-PRIVATE-OUTDIR

  Measured 2026-11-06 (lane lspsmoke): a private engine copy with its own
  drag-lint.json (indexes.outDir = its scratch) and a garbage --db still opened
  C:\Projects\.drag-lint\library-Win64.sqlite, read-only: the LSP's library fallback
  (1.39) takes libraries.<platform>.libraryDb from the per-USER central defaults.

  A private engine (not at a deployed location) whose own drag-lint.json declares
  an outDir ignores a defaults library outside that outDir.

  a  private json, outDir elsewhere: no library answer, no fallback notice, one stderr line.
  b  POSITIVE CONTROL: private json, outDir holds the defaults library: it is used.
  c  POSITIVE CONTROL: no json beside the engine: the 1.39 fallback is unchanged.
  a is RED on 1.44.1.

  Hermetic: DRAGLINT_CONTEXT_DEFAULTS + engine copies under the work folder.
  Usage: pwsh -File tests\autotest\run_lsp_library_private_outdir.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-private-outdir-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), (New-Object Text.ASCIIEncoding)) }
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 12
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
foreach ($d in 'libsrc','projsrc','loose','libhome','elsewhere') { New-Item -ItemType Directory "$WorkDir\$d" -Force | Out-Null }
WriteAnsi "$WorkDir\libsrc\FarAwayLib.pas" "unit FarAwayLib;`n`ninterface`n`nprocedure LibraryOnlyRoutine(AValue: Integer);`n`nimplementation`n`nprocedure LibraryOnlyRoutine(AValue: Integer);`nbegin`nend;`n`nend.`n"
WriteAnsi "$WorkDir\projsrc\ProjUnit.pas" "unit ProjUnit;`n`ninterface`n`nprocedure DriveProject;`n`nimplementation`n`nprocedure DriveProject;`nbegin`nend;`n`nend.`n"
$looseText = "unit LooseUnit;`r`n`r`ninterface`r`n`r`nprocedure DriveLoose;`r`n`r`nimplementation`r`n`r`nuses`r`n  FarAwayLib;`r`n`r`nprocedure DriveLoose;`r`nbegin`r`n  LibraryOnlyRoutine(2);`r`nend;`r`n`r`nend.`r`n"
$looseFile = "$WorkDir\loose\LooseUnit.pas"
WriteAnsi $looseFile $looseText
$DefLib = "$WorkDir\libhome\dctx-win64.sqlite"
$projDb = "$WorkDir\proj.sqlite"
& $Exe index "$WorkDir\libsrc"  --db $DefLib 2>&1 | Out-Null
& $Exe index "$WorkDir\projsrc" --db $projDb 2>&1 | Out-Null
Check 'built fixture indexes' ((Test-Path $DefLib) -and (Test-Path $projDb))
$lines = $looseText -split "`r?`n"
$ln  = [Array]::FindIndex($lines, [Predicate[string]]{ param($x) $x -like '*LibraryOnlyRoutine(2);*' })
$col = $lines[$ln].IndexOf('LibraryOnlyRoutine') + 4

$dfile = "$WorkDir\defaults.json"
[IO.File]::WriteAllText($dfile, (@{ libraries = @{ Win64 = @{ libraryDb = $DefLib } } } | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$env:DRAGLINT_CONTEXT_DEFAULTS = $dfile

function New-Engine([string]$Tag, [string]$OutDir) {
  $dir = "$WorkDir\eng-$Tag"
  New-Item -ItemType Directory $dir | Out-Null
  Copy-Item $Exe $dir
  Copy-Item (Join-Path (Split-Path $Exe) '*.dll') $dir
  if ($OutDir) {
    $o = $OutDir.Replace('\', '/')
    [IO.File]::WriteAllText("$dir\drag-lint.json", "{ `"settings`": { `"defaultPlatform`": `"Win64`" }, `"indexes`": { `"outDir`": `"$o`" } }", (New-Object Text.ASCIIEncoding))
  }
  return "$dir\drag-lint.exe"  # exe-freshness: absent -- a private copy of the engine under test, made above
}
function Run-Case([string]$Tag, [string]$Engine) {
  $uri = 'file:///' + ($looseFile -replace '\\', '/')
  $msgs  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $msgs += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $msgs += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$looseText } } }
  $msgs += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/hover'; params=@{ textDocument=@{ uri=$uri }; position=@{ line=$ln; character=$col } } }
  $msgs += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF = "$WorkDir\$Tag-in.txt"; $outF = "$WorkDir\$Tag-out.txt"; $errF = "$WorkDir\$Tag-err.txt"
  [IO.File]::WriteAllText($inF, $msgs, (New-Object Text.ASCIIEncoding))
  $p = Start-Process $Engine -ArgumentList @('lsp', '--db', $projDb) -WorkingDirectory $WorkDir -RedirectStandardInput $inF `
    -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -PassThru
  if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { }; throw "lsp $Tag timed out" }
  $raw = [IO.File]::ReadAllText($outF)
  $hover = ''; $notice = ''
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $null -ne $o.result) { $hover = [string]$o.result.contents.value }
    if ($o.method -eq 'draglint/context') { $notice += [string]$o.params.notice + ' ' }
  }
  return @{ Hover = $hover; Notice = $notice; Err = [IO.File]::ReadAllText($errF) }
}

Write-Host 'a: private json, outDir elsewhere' -ForegroundColor Cyan
$ra = Run-Case 'a' (New-Engine 'a' "$WorkDir\elsewhere")
Check 'a: no library answer' ($ra.Hover -notmatch 'FarAwayLib\.LibraryOnlyRoutine') "got: [$($ra.Hover)]"
Check 'a: no fallback notice' ($ra.Notice -notmatch 'library from context defaults') "got: [$($ra.Notice)]"
Check 'a: stderr names the ignored library' ($ra.Err -match 'private engine: defaults library .*dctx-win64\.sqlite ignored') "got: [$($ra.Err)]"

Write-Host 'b: private json, outDir holds the defaults library (positive control)' -ForegroundColor Cyan
$rb = Run-Case 'b' (New-Engine 'b' "$WorkDir\libhome")
Check 'b: hover resolves from the defaults library' ($rb.Hover -match 'FarAwayLib\.LibraryOnlyRoutine') "got: [$($rb.Hover)]"
Check 'b: fallback notice' ($rb.Notice -match 'library from context defaults') "got: [$($rb.Notice)]"

Write-Host 'c: no json beside the engine (positive control)' -ForegroundColor Cyan
$rc = Run-Case 'c' (New-Engine 'c' '')
Check 'c: hover resolves from the defaults library' ($rc.Hover -match 'FarAwayLib\.LibraryOnlyRoutine') "got: [$($rc.Hover)]"
$env:DRAGLINT_CONTEXT_DEFAULTS = $null
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'run_lsp_library_private_outdir: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lsp_library_private_outdir: PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
