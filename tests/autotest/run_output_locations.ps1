<#
  run_output_locations.ps1 -- every symbol / caller answer says WHERE, as a path
  that can be opened.

  THE PROBLEM (evaluation on ProjectA, 2026-09-28). Three answers named a thing
  without a usable location, so each one needed a second search to open it:
    * `query --name X` (text) printed kind, name, qualified name, signature --
      never the file or the line;
    * `query find-callers --resolved` printed and emitted the file NAME only
      (`UImageStore.pas:628`, JSON `"file": "UImageStore.pas"`);
    * the MCP `find_symbol` tool, whose description promises file:line:col,
      returned `line L:C` and no file.

  THE FIX. The text row gains `(path:line)` BEFORE the [impl-only] / forward
  suffixes; the resolved JSON gains a `path` key LAST (the pinned key order and
  the file-name `file` key are unchanged) and the text form prints the full
  path; find_symbol returns `path:line:col`.

  Usage: pwsh -File tests/autotest/run_output_locations.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-output-locations-$PID"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
$unit = Join-Path $src 'uWhere.pas'
Write-Ascii $unit @'
unit uWhere;

interface

procedure Target;
procedure Caller;

implementation

procedure Hidden;
begin
end;

procedure Target;
begin
  Hidden;
end;

procedure Caller;
begin
  Target;
end;

end.
'@
# Line numbers of the fixture above, stated once.
$targetDecl = 5
$hiddenDecl = 10
$callSite   = 21

$db = Join-Path $WorkDir 'where.sqlite'
& $Exe index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$esc = [regex]::Escape($unit)

Write-Host 'query --name (text)' -ForegroundColor Cyan
$q = @(& $Exe query --name Target --db $db --exact 2>$null)
$row = @($q | Where-Object { $_ -match 'uWhere\.Target' })
Check 'the row is present' ($row.Count -eq 1) "rows: $($q -join ' | ')"
Check 'ASSERT: the row names (full path:declaration line)' `
  (($row.Count -eq 1) -and ($row[0] -match ('\(' + $esc + ':' + $targetDecl + '\)'))) "got: $row"
$qi = @(& $Exe query --name Hidden --db $db --exact 2>$null) | Where-Object { $_ -match 'uWhere\.Hidden' }
Check 'CONTROL: the location sits BEFORE the [impl-only] suffix, which stays at the end' `
  (($qi -match ('\(' + $esc + ':' + $hiddenDecl + '\)')) -and ($qi -match '\[impl-only\]\s*$')) "got: $qi"

Write-Host ''
Write-Host 'find-callers --resolved' -ForegroundColor Cyan
$j = (& $Exe query find-callers --name Target --resolved --json --db $db 2>$null) -join "`n"
$rows = @(ConvertFrom-Json -InputObject $j)
Check 'one resolved caller' ($rows.Count -eq 1) "json: $j"
if ($rows.Count -eq 1) {
  Check 'ASSERT: json carries the FULL path under `path`' ($rows[0].path -eq $unit) "path=$($rows[0].path)"
  Check 'CONTROL: `file` is still the file NAME (the contract consumers diff on)' ($rows[0].file -eq 'uWhere.pas') "file=$($rows[0].file)"
  Check 'CONTROL: `path` is the LAST key, so the pinned order is untouched' `
    ((@($rows[0].PSObject.Properties.Name) | Select-Object -Last 1) -eq 'path') "keys=$(@($rows[0].PSObject.Properties.Name) -join ',')"
}
$t = (& $Exe query find-callers --name Target --resolved --db $db 2>$null) -join "`n"
Check 'ASSERT: the text row prints (full path:site line)' ($t -match ('\(' + $esc + ':' + $callSite + '\)')) "got: $t"

Write-Host ''
Write-Host 'MCP find_symbol' -ForegroundColor Cyan
$req = Join-Path $WorkDir 'mcp.json'
Write-Ascii $req ('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"find_symbol","arguments":{"name":"Target"}}}' + "`n")
$mcp = (Get-Content -Raw $req | & $Exe serve --db $db 2>$null) -join "`n"
$text = ''
try { $text = ((ConvertFrom-Json -InputObject (@($mcp -split "`n" | Where-Object { $_ -match '"id":1' })[0])).result.content[0].text) } catch {}
Check 'find_symbol answered' ($text -match 'uWhere\.Target') "raw: $mcp"
Check 'ASSERT: find_symbol returns path:line:col, as its description promises' `
  ($text -match ($esc + ':' + $targetDecl + ':\d+')) "text: $text"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-output-locations-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
