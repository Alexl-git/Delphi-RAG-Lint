#Requires -Version 7
<#
  run_lsp_document_highlight_guard.ps1 -- `textDocument/documentHighlight` (lane 145 lsp).

  Fixture: uHL declares Helper (called twice in uHL) and Helper2 (a decoy, called once); uOther calls
  Helper once.
  Positive controls (a handler answering [] or highlighting every identifier fails them):
    initialize advertises documentHighlightProvider.
    on Helper's declaration -> highlights on the declaration line AND both call lines in uHL, kind 1.
    on a CALL of Helper -> the same line set (the declaration is reached from a use).
    Helper2's line is NOT highlighted (another symbol); uOther's call is NOT in uHL's answer (this file only).
  Honest misses -> [] (never an error): whitespace and a file the index does not hold.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-dochl-$PID"
)
if (-not $Exe) { $Exe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\src\cli\Win64\Debug\drag-lint.exe' }
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lsp_stdio_helpers.ps1')
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uHL.pas'
WriteAnsi $file @'
unit uHL;

interface

procedure Helper;
procedure Helper2;
procedure Driver;

implementation

procedure Helper;
begin
end;

procedure Helper2;
begin
end;

procedure Driver;
begin
  Helper;
  Helper2;
  Helper;
end;

end.
'@
WriteAnsi (Join-Path $src 'uOther.pas') @'
unit uOther;

interface

procedure UseIt;

implementation

uses
  uHL;

procedure UseIt;
begin
  Helper;
end;

end.
'@
$loose = Join-Path $WorkDir 'loose.pas'
WriteAnsi $loose "unit loose;`ninterface`nprocedure Z;`nimplementation`nprocedure Z;`nbegin`nend;`nend.`n"

$db = Join-Path $WorkDir 'hl.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $src --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern, [int]$from = 0) { for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } } return -1 }
$uri = 'file:///' + ($file -replace '\\', '/')
$looseUri = 'file:///' + ($loose -replace '\\', '/')
$lDecl = LineOf '^procedure Helper;$'
$lH2 = LineOf '^  Helper2;$'
$lCall1 = LineOf '^  Helper;$'
$lCall2 = LineOf '^  Helper;$' ($lCall1 + 1)
function HL([int]$line, [int]$col, [string]$u = $uri) { @{ method='textDocument/documentHighlight'; params=(PosParams $u $line $col) } }
$r = LspSession $Exe $WorkDir $db @(
  (HL $lDecl 11),            # 11 on the declaration
  (HL $lCall1 4),            # 12 on a call
  (HL 1 0),                  # 13 whitespace
  (HL 2 5 $looseUri)         # 14 unindexed file
)
Check 'initialize advertises documentHighlightProvider' ($r.init.capabilities.documentHighlightProvider -eq $true)
Check 'documentHighlight answered (not -32601)' ($r.res.ContainsKey(11)) $(if ($r.err.Count) { 'error=' + (($r.err.Values | % { $_.code }) -join ',') })
if (-not $r.res.ContainsKey(11)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }
function Hits([int]$id) { if ($r.res.ContainsKey($id)) { return @($r.res[$id][0]) } else { return @() } }
foreach ($id in 11, 12) {
  $h = @(Hits $id)
  $ls = @($h | % { $_.range.start.line })
  Check "request ${id}: highlights include the declaration and both calls" (($ls -contains $lDecl) -and ($ls -contains $lCall1) -and ($ls -contains $lCall2)) "lines=$($ls -join ',') want-includes=$lDecl,$lCall1,$lCall2"
  Check "request ${id}: the decoy Helper2 line is not highlighted" (-not ($ls -contains $lH2))
  Check "request ${id}: every highlight is kind 1 and the answer is not just the whole file" (@($h | ? { $_.kind -ne 1 }).Count -eq 0 -and $h.Count -lt $lines.Count / 2) "count=$($h.Count)"
  $allowed = @(0..($lines.Count - 1) | ? { $lines[$_] -match '(?<![A-Za-z0-9_])Helper(?![A-Za-z0-9_])' })
  Check "request ${id}: every highlight sits on a line that names Helper in THIS file (uOther's call is not mixed in)" (@($ls | ? { $allowed -notcontains $_ }).Count -eq 0) "lines=$($ls -join ',') allowed=$($allowed -join ',')"
}
Check 'whitespace -> []' ($r.res.ContainsKey(13) -and @(Hits 13).Count -eq 0 -and -not $r.err.ContainsKey(13))
Check 'unindexed file -> []' ($r.res.ContainsKey(14) -and @(Hits 14).Count -eq 0 -and -not $r.err.ContainsKey(14))

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
