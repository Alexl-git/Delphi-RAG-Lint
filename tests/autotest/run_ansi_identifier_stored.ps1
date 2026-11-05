<#
  run_ansi_identifier_stored.ps1 --
  A non-ASCII identifier read from a Windows-1252 source file is stored un-garbled (1.44 C16 item 4).

  MEASUREMENT GUARD, not a fix: 1.44 measured that the index already stores `Gr<F6><DF>e` and
  `Z<E4>hler` (cp1252 bytes in the .pas) as the UTF-8 of the same letters. This pins that, so a
  parser or reader change that turns them into `?` or mojibake fails here.

  The fixture is generated at run time as cp1252 bytes (repo sources stay 7-bit ASCII).
  POSITIVE CONTROL: the ASCII-only symbol of the same unit is stored too, so an empty index cannot pass.

  Usage: pwsh -NoProfile -File tests\autotest\run_ansi_identifier_stored.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-ansi-ident-$PID"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
try {
  $exePath = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory -Path "$WorkDir\src" -Force | Out-Null
  $enc = [Text.Encoding]::GetEncoding(1252)
  $o = [string][char]0xF6; $ss = [string][char]0xDF; $a = [string][char]0xE4
  $text = "unit uAnsi;`r`n`r`ninterface`r`n`r`ntype`r`n  TKlasse = class`r`n  public`r`n    procedure Gr$o${ss}e;`r`n    function Z${a}hler: Integer;`r`n    procedure PlainName;`r`n  end;`r`n`r`nimplementation`r`n`r`n" +
          "procedure TKlasse.Gr$o${ss}e;`r`nbegin`r`nend;`r`n`r`nfunction TKlasse.Z${a}hler: Integer;`r`nbegin`r`n  Result := 1;`r`nend;`r`n`r`nprocedure TKlasse.PlainName;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllBytes("$WorkDir\src\uAnsi.pas", $enc.GetBytes($text))
  $db = "$WorkDir\a.sqlite"
  & $exePath index "$WorkDir\src" --db $db 2>&1 | Out-Null
  Check 'V the fixture index was built' (Test-Path $db)
  $json = (& $exePath sql --db $db --json --query "select name, hex(name) as h from symbols where name in ('PlainName') or name like 'Gr%e' or name like 'Z%hler'" 2>$null) -join "`n"
  $doc = $json.Substring($json.IndexOf('{')) | ConvertFrom-Json
  $rows = @($doc.rows | ForEach-Object { ,@($_) })   # positional rows: [name, hex]
  $hexes = @($rows | ForEach-Object { [string]$_[1] })
  Check 'V2 POSITIVE CONTROL the ASCII symbol PlainName is stored' ($hexes -contains '506C61696E4E616D65') ($hexes -join ',')
  # Gr + ??(C3B6) + ??(C39F) + e   and   Z + ??(C3A4) + hler  -- UTF-8 of the same letters
  Check 'C16.4 Gr<o-umlaut><sharp-s>e is stored as UTF-8 of the same letters' ($hexes -contains '4772C3B6C39F65') ($hexes -join ',')
  Check 'C16.4 Z<a-umlaut>hler is stored as UTF-8 of the same letters' ($hexes -contains '5AC3A4686C6572') ($hexes -join ',')
  Check 'C16.4 no replacement character (EFBFBD) or literal ? in any stored name' (@($hexes | Where-Object { $bytes = @([regex]::Matches($_, '..') | ForEach-Object { $_.Value }); ($bytes -contains '3F') -or ($_ -match '^(..)*EFBFBD') }).Count -eq 0) ($hexes -join ',')
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 } else { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
