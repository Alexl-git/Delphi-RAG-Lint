<#
  run_ansi_line_columns.ps1 -- in a CP1252 unit, a call that FOLLOWS an accented
  character on the same line still types its receiver.

  THE PROBLEM (evaluation on ProjectA, 2026-09-28). A ref's column is 1 + a BYTE
  offset into the UTF-8 buffer the indexer parsed (EnsureUtf8Bytes transcodes a
  CP1252 file first). The call resolver re-read the file as ANSI text, where an
  accented letter is ONE character but TWO UTF-8 bytes. So after every accented
  letter earlier on the line, Line[StartCol] pointed one character further right
  than the call, the receiver scan read the wrong text, and the call was left
  unresolved -- in Portuguese source, where strings and comments are full of
  accents, that is not rare.

  THE FIX (resolver 1.14.0-alpha). LinesOf builds its lines from the indexer's
  own UTF-8 buffer, one byte to one character, so Line[Col] is the byte the
  column names. The staleness probe still hashes the ANSI text, unchanged.

  The fixture is written as CP1252 bytes on purpose: this script itself stays
  7-bit ASCII, and the two accented letters are inserted as raw bytes.

  Usage: pwsh -File tests/callresolve/run_ansi_line_columns.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_ansi_columns_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src | Out-Null

# '@@' marks where the CP1252 bytes go: 0xE7 (c-cedilla) 0xE3 (a-tilde) = "ca" as in "acao".
$text = @'
unit uAnsi;

interface

type
  TWidget = class(TObject)
  public
    procedure Run;
  end;

procedure Show(const S: string);
procedure UseIt;

implementation

procedure TWidget.Run;
begin
end;

procedure Show(const S: string);
begin
end;

procedure UseIt;
var
  W: TWidget;
begin
  W := nil;
  Show('a@@o a@@o a@@o'); W.Run;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$ascii = [System.Text.Encoding]::ASCII.GetBytes($text)
$bytes = New-Object System.Collections.Generic.List[byte]
for ($i = 0; $i -lt $ascii.Length; $i++) {
  if ($i + 1 -lt $ascii.Length -and $ascii[$i] -eq 64 -and $ascii[$i + 1] -eq 64) {
    $bytes.Add(0xE7); $bytes.Add(0xE3); $i++
  } else { $bytes.Add($ascii[$i]) }
}
[System.IO.File]::WriteAllBytes((Join-Path $src 'uAnsi.pas'), $bytes.ToArray())
Check 'precondition: the fixture carries non-ASCII CP1252 bytes' (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 6) ''

$db = Join-Path $WorkDir 'ansi.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$c = ((& $exePath find-callees --qname uAnsi.UseIt --db $db 2>$null) -join "`n")
Check 'ASSERT: W.Run after six accented bytes on the same line binds [certain]' `
  ($c -match 'uAnsi\.TWidget\.Run\s+\[certain\]') "callees: $c"
Check 'CONTROL: the call before the accents (Show) binds too' ($c -match 'uAnsi\.Show') "callees: $c"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_ansi_columns_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
