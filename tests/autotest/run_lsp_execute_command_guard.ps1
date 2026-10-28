#Requires -Version 7
<#
  run_lsp_execute_command_guard.ps1 -- `workspace/executeCommand`
  `draglint.showCallers` (B6), the command B4's code lens runs.

  WHAT THIS PINS, and why each part is here rather than "it returned something":

    THE METHOD IS ANSWERED (RED before B6: -32601 method not found) and
    `initialize` advertises executeCommandProvider.commands containing
    draglint.showCallers.

    THE CALL SITES ARE RIGHT (positive control). On the B4 caller-counts
    fixture, `draglint.showCallers [uri, <Thrice declaration line>]` answers
    exactly three {uri, line, character} rows, one per call-site line of
    `T.Thrice;` (computed here FROM THE FIXTURE TEXT), each in uLens.pas.
    The (file, line) dedup is what keeps it at three: the index holds a 'call'
    AND a 'member-access' ref per site. `Once` answers one row, `Never` [].

    THE LENS CONTRACT: the line passed is the codeLens line (0-based), so the
    count of rows equals the lens title's count.

    ERRORS: an unknown command answers -32601; missing/ill-typed arguments
    answer -32602.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-execcmd-$PID"
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
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uLens.pas'
WriteAnsi $file @'
unit uLens;

interface

type
  TThing = class
  private
    FCount: Integer;
  public
    procedure Thrice;
    procedure Once;
    procedure Never;
    property Count: Integer read FCount write FCount;
  end;

procedure Driver;

implementation

procedure TThing.Thrice;
begin
end;

procedure TThing.Once;
begin
end;

procedure TThing.Never;
begin
end;

procedure Driver;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Thrice;
  T.Thrice;
  T.Thrice;
  T.Once;
end;

end.
'@

$db = Join-Path $WorkDir 'lens.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LinesOf([string]$pattern) {
  $out = @()
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { $out += $i } }
  return ,$out
}

# Every request is one session with ids 10.. ; the result map is id -> @{res; err}.
function Session([object[]]$calls) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $id = 10
  foreach ($c in $calls) {
    $m += Frame @{ jsonrpc='2.0'; id=$id; method='workspace/executeCommand'; params=$c }
    $id++
  }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{}
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($null -eq $o.id) { continue }
    $res = $null
    if ($null -eq $o.error) { $res = ,@($o.result) }
    $r[[int]$o.id] = @{ res = $res; err = $o.error; raw = $o.result }
  }
  return $r
}

$uri = 'file:///' + ($file -replace '\\', '/')
$thriceDecl = (LinesOf '^\s*procedure Thrice;')[0]
$onceDecl   = (LinesOf '^\s*procedure Once;')[0]
$neverDecl  = (LinesOf '^\s*procedure Never;')[0]
$thriceSites = LinesOf '^\s*T\.Thrice;'
$onceSites   = LinesOf '^\s*T\.Once;'

$r = Session @(
  @{ command='draglint.showCallers'; arguments=@($uri, $thriceDecl) },   # 10
  @{ command='draglint.showCallers'; arguments=@($uri, $onceDecl) },     # 11
  @{ command='draglint.showCallers'; arguments=@($uri, $neverDecl) },    # 12
  @{ command='draglint.nosuch'; arguments=@() },                         # 13
  @{ command='draglint.showCallers'; arguments=@($uri) },                # 14
  @{ command='draglint.showCallers'; arguments=@(5, 'x') }               # 15
)
$cmds = @($r[1].raw.capabilities.executeCommandProvider.commands)
Check 'initialize advertises executeCommandProvider.commands with draglint.showCallers' ($cmds -contains 'draglint.showCallers') "caps=$($r[1].raw.capabilities | ConvertTo-Json -Compress -Depth 3)"

$t = $r[10]
Check 'the method answered (not -32601)' ($null -ne $t -and $null -eq $t.err) $(if ($t.err) { "error=$($t.err.code) $($t.err.message)" } else { '' })
if ($null -eq $t -or $null -ne $t.err) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }
$rows = @($t.res[0])
Check 'Thrice: exactly three call-site rows (file,line dedup)' ($rows.Count -eq 3) "got=$($rows.Count) $($rows | ConvertTo-Json -Compress -Depth 4)"
$gotLines = @($rows | ForEach-Object { [int]$_.line } | Sort-Object)
Check "Thrice: the rows are the call-site lines ($($thriceSites -join ','))" (($gotLines -join ',') -eq ($thriceSites -join ',')) "got=$($gotLines -join ',')"
Check 'Thrice: every row names uLens.pas and has a character' (-not @($rows | Where-Object { -not (([string]$_.uri) -like 'file:*uLens.pas') -or $null -eq $_.character }).Count)
$o = @($r[11].res[0])
Check "Once: one row on line $($onceSites[0])" ($o.Count -eq 1 -and [int]$o[0].line -eq $onceSites[0]) "got=$($o | ConvertTo-Json -Compress -Depth 4)"
Check 'Never: []' ($null -ne $r[12].res -and @($r[12].res[0]).Count -eq 0 -and $null -eq $r[12].err)
Check 'unknown command answers -32601' ($null -ne $r[13].err -and $r[13].err.code -eq -32601) "got=$($r[13] | ConvertTo-Json -Compress -Depth 4)"
Check 'one argument answers -32602' ($null -ne $r[14].err -and $r[14].err.code -eq -32602) "got=$($r[14] | ConvertTo-Json -Compress -Depth 4)"
Check 'ill-typed arguments answer -32602' ($null -ne $r[15].err -and $r[15].err.code -eq -32602) "got=$($r[15] | ConvertTo-Json -Compress -Depth 4)"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
