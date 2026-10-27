<#
  run_index_nonansi_path.ps1 -- a unit whose FOLDER and FILE NAME hold non-ANSI
  (Cyrillic) letters. Companion of run_index_nonansi_identifiers.ps1 (INBOX
  conv-enc-nonansi-identifiers-lossy item 1): text parameters bound with
  FireDAC AsString (ftString = ANSI) wrote such a path as '?' per letter, so the
  file row named a file that does not exist, a path lookup (outline --in,
  incremental reindex) could not find its own row, and a reindex inserted a
  SECOND row for the same file.

  The fixture is generated (this script stays 7-bit ASCII): <work>\src\<cyr>\
  u<cyr>.pas, UTF-8 without a BOM, declaring an ASCII class TPathProbe.

  Checks: files.path is stored as the real UTF-8 path; query --name TPathProbe
  finds the symbol (CONTROL: ASCII name, passes before the fix); outline --in
  <the path> lists TPathProbe; a second index run keeps exactly ONE files row
  for the unit and reports it up to date (no duplicate row).

  Run from a NEUTRAL CWD. pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function Utf8Hex([string]$s) { return ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($s)) -replace '-', '') }

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_nonansi_path_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
# U+043F U+0443 U+0442 U+044C (Cyrillic "put'") -- not representable in Windows-1252.
$cy   = [string]::new([char[]](0x043F, 0x0443, 0x0442, 0x044C))
$src  = Join-Path $work 'src'
$dir  = Join-Path $src $cy
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$unitName = "u$cy"
$pas  = Join-Path $dir "$unitName.pas"
$db   = Join-Path $work 'nonansi_path.sqlite'
$text = "unit $unitName;`r`n`r`ninterface`r`n`r`ntype`r`n  TPathProbe = class`r`n  public`r`n    procedure Go;`r`n  end;`r`n`r`n" +
        "implementation`r`n`r`nprocedure TPathProbe.Go;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
[IO.File]::WriteAllText($pas, $text, (New-Object Text.UTF8Encoding $false))
# CONTROL unit on an ASCII path beside it: indexed and found before the fix too.
New-Item -ItemType Directory -Path (Join-Path $src 'ascii') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $src 'ascii\uAsciiPath.pas'), ($text.Replace($unitName, 'uAsciiPath').Replace('TPathProbe', 'TAsciiProbe')), [Text.Encoding]::ASCII)

function FileRows {
  $j = (& $exePath sql --db $db --query "select id, hex(path) from files" --json 2>$null) -join "`n" | ConvertFrom-Json
  return ,@($j.rows)  # POSITIONAL arrays: [id, hex(path)]; the comma keeps a 1-row result an array of rows
}

Push-Location $env:TEMP
try {
  & $exePath index $src --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  $rows = FileRows
  $want = Utf8Hex ($cy + '\' + $unitName + '.pas')
  $mine = @($rows | Where-Object { ([string]$_[1]).EndsWith($want) })
  Check 'files.path stored as the real UTF-8 path' ($mine.Count -eq 1) "paths=$(@($rows | ForEach-Object { $_[1] }) -join ',')"
  Check 'no files.path holds a literal ?' (@($rows | Where-Object { ([string]$_[1]) -match '^(..)*?3F' }).Count -eq 0)

  Write-Host 'CONTROL (ASCII path; passes before the fix):' -ForegroundColor Cyan
  $c = @((& $exePath query --name TAsciiProbe --db $db --json 2>$null) -join "`n" | ConvertFrom-Json)
  Check 'query --name TAsciiProbe finds the ASCII-path class' (@($c | Where-Object { $_.kind -eq 'class' }).Count -eq 1) "rows=$($c.Count)"

  Write-Host 'NON-ANSI PATH:' -ForegroundColor Cyan
  $q = @((& $exePath query --name TPathProbe --db $db --json 2>$null) -join "`n" | ConvertFrom-Json)
  Check 'query --name TPathProbe finds the class in the non-ANSI unit' (@($q | Where-Object { $_.kind -eq 'class' }).Count -eq 1) "rows=$($q.Count)"

  Write-Host 'PATH LOOKUPS:' -ForegroundColor Cyan
  $o = (& $exePath outline --in $pas --db $db 2>&1) -join "`n"
  Check 'outline --in <non-ANSI path> lists TPathProbe' ($o -match 'TPathProbe') "out=$($o.Substring(0, [Math]::Min(160, $o.Length)))"

  & $exePath index $src --db $db 2>&1 | Out-Null
  Check 'second index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $rows2 = FileRows
  Check 'reindex keeps ONE files row (no duplicate)' ($rows2.Count -eq $rows.Count) "before=$($rows.Count) after=$($rows2.Count)"
  $mine2 = @($rows2 | Where-Object { ([string]$_[1]).EndsWith($want) })
  Check 'reindex keeps the same file id' (($mine.Count -eq 1) -and ($mine2.Count -eq 1) -and ([long]$mine2[0][0] -eq [long]$mine[0][0])) "ids=$(@($rows2 | ForEach-Object { $_[0] }) -join ',')"
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
