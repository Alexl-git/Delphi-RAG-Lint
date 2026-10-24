<#
  run_mcp_rename_refusals.ps1 -- the MCP rename_symbol tool must refuse exactly
  where the CLI rename refuses (same TRenameRefactoring reasons).

  DEFECT: rename_symbol applied BinaryDfmReason and StaleEditReason but not
  ConflictReason (new name collides) nor IncludeUseReason (name used inside an
  {$I} include) -- it returned a partial / colliding rename as success.

  FIXTURE: uHost.pas declares Helper and Other and {$I body.inc}; body.inc
  calls Helper.  ASSERT over `serve` stdio (dry_run, so nothing is written):
    1. Helper -> Other  : applied=false, error says cannot rename (collision)
    2. Helper -> Helper2: applied=false, error names body.inc
    3. positive control (separate fixture, include only mentions the name in a
       comment): Helper -> Helper2 returns a non-empty edits array.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-mcp-rename-refusals-$PID"
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
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
$HostUnit = @'
unit uHost;

interface

function Helper: Integer;
function Other: Integer;
procedure DoWork;

implementation

function Helper: Integer;
begin
  Result:= 1;
end;

function Other: Integer;
begin
  Result:= 2;
end;

procedure DoWork;
var
  X: Integer;
begin
  {$I body.inc}
end;

end.
'@
function New-Fixture([string]$Name, [string]$IncBody) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  Write-Ascii (Join-Path $src 'uHost.pas') $HostUnit
  Write-Ascii (Join-Path $src 'body.inc')  $IncBody
  $db = Join-Path $dir 'idx.sqlite'
  Push-Location $dir
  try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
  Check "$Name index exits 0" ($LASTEXITCODE -eq 0)
  [pscustomobject]@{ Dir = $dir; Db = $db }
}
# One serve session; returns the parsed tools/call payload per request id.
function Invoke-Rename($fx, [string[]]$Targets) {
  $lines = @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"guard","version":"1"}}}',
             '{"jsonrpc":"2.0","method":"notifications/initialized"}')
  $i = 2
  foreach ($t in $Targets) {
    $lines += ('{"jsonrpc":"2.0","id":' + $i + ',"method":"tools/call","params":{"name":"rename_symbol","arguments":{"qname":"uHost.Helper","to":"' + $t + '","dry_run":"true"}}}')
    $i++
  }
  $req = Join-Path $fx.Dir 'req.jsonl'
  [IO.File]::WriteAllText($req, ($lines -join "`n") + "`n", [Text.Encoding]::ASCII)
  $so = Join-Path $fx.Dir 'out.txt'; $se = Join-Path $fx.Dir 'err.txt'
  Start-Process $Exe -ArgumentList 'serve','--db',$fx.Db -WorkingDirectory $fx.Dir `
    -RedirectStandardInput $req -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $res = @{}
  foreach ($ln in (Get-Content $so)) {
    try { $o = $ln | ConvertFrom-Json } catch { continue }
    if ($o.id -ge 2 -and $o.result) { $res[[int]$o.id] = ($o.result.content[0].text | ConvertFrom-Json) }
  }
  $res
}

Write-Host 'Fixture A: collision + include use' -ForegroundColor Cyan
$a = New-Fixture 'A' "  X:= Helper;`r`n"
$ra = Invoke-Rename $a @('Other', 'Helper2')
$c = $ra[2]; $n = $ra[3]
Check 'conflict: replied' ($null -ne $c)
Check 'conflict: applied=false' ($c.applied -eq $false)
Check 'conflict: error says cannot rename' ("$($c.error)" -match 'cannot rename') "error=$($c.error)"
Check 'conflict: no edits' (@($c.edits).Count -eq 0)
Check 'include: replied' ($null -ne $n)
Check 'include: applied=false' ($n.applied -eq $false)
Check 'include: error names body.inc' ("$($n.error)" -match 'body\.inc') "error=$($n.error)"

Write-Host 'Fixture B (positive control): include mentions the name only in a comment' -ForegroundColor Cyan
$b = New-Fixture 'B' "  // Helper`r`n  X:= 1;`r`n"
$rb = Invoke-Rename $b @('Helper2')
$p = $rb[2]
Check 'clean rename: replied' ($null -ne $p)
Check 'clean rename: no error' ([string]::IsNullOrEmpty("$($p.error)")) "error=$($p.error)"
Check 'clean rename: returns edits' (@($p.edits).Count -gt 0) "edits=$(@($p.edits).Count)"

} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  $script:Failed = $true
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:Failed) { Write-Host 'run_mcp_rename_refusals: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_mcp_rename_refusals: PASS' -ForegroundColor Green
exit 0
