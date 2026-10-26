<#
  run_index_nonansi_identifiers.ps1 -- INBOX-conv-enc-nonansi-identifiers-lossy
  item 1: a Delphi identifier with non-ANSI letters (Cyrillic here) was stored
  in the index as '?' per letter (`TDst` + three Cyrillic letters -> 'TDst???'),
  so `query --name` could not find it by its real spelling and a #convert to
  such a class could not be expressed.

  The fixture is generated (this script stays 7-bit ASCII): the identifier is
  built from code points, written as UTF-8 WITHOUT a BOM (uEncNoBom.pas) and
  WITH a BOM (uEncBom.pas). Both go through EnsureUtf8Bytes on the way in, so
  both must land in symbols.name / qualified_name as the same UTF-8 bytes.

  CONTROL: an ASCII identifier in the same files (TPlainAscii.Go) is stored and
  found unchanged -- it passes on the pre-fix engine, so a FAIL elsewhere is
  about the non-ASCII letters, not the harness.

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

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_nonansi_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$src  = Join-Path $work 'src'
New-Item -ItemType Directory -Path $src | Out-Null
$db = Join-Path $work 'nonansi.sqlite'

# U+0434 U+0430 U+043D (Cyrillic de, a, en) -- not representable in Windows-1252.
$cy = [string]::new([char[]](0x0434, 0x0430, 0x043D))

function UnitText([string]$UnitName, [string]$Cls) {
  return ("unit $UnitName;`r`n`r`ninterface`r`n`r`ntype`r`n" +
          "  $Cls = class`r`n  public`r`n    procedure Run$cy;`r`n  end;`r`n`r`n" +
          "  TPlainAscii$UnitName = class`r`n  public`r`n    procedure Go;`r`n  end;`r`n`r`n" +
          "implementation`r`n`r`nprocedure $Cls.Run$cy;`r`nbegin`r`nend;`r`n`r`n" +
          "procedure TPlainAscii$UnitName.Go;`r`nbegin`r`nend;`r`n`r`nend.`r`n")
}
$noBomCls = "TDst$cy"
$bomCls   = "TBom$cy"
[IO.File]::WriteAllText((Join-Path $src 'uEncNoBom.pas'), (UnitText 'uEncNoBom' $noBomCls), (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText((Join-Path $src 'uEncBom.pas'),   (UnitText 'uEncBom'   $bomCls),   (New-Object Text.UTF8Encoding $true))

function Utf8Hex([string]$s) { return ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($s)) -replace '-', '') }

Push-Location $env:TEMP
try {
  & $exePath index $src --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  $q = "select name, hex(name), qualified_name, hex(qualified_name) from symbols"
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n" | ConvertFrom-Json
  $byHex = @{}
  foreach ($row in $j.rows) { $byHex[[string]$row[3]] = $row }   # keyed by hex(qualified_name); rows are POSITIONAL arrays

  function StoredAs($Name, $QName) {
    $row = $byHex[(Utf8Hex $QName)]
    Check "qualified_name stored as UTF-8 '$(Utf8Hex $QName)'" ($null -ne $row) "qnames=$(@($j.rows | ForEach-Object { $_[3] }) -join ',')"
    if ($row) { Check "name of that row is UTF-8 '$(Utf8Hex $Name)'" ([string]$row[1] -eq (Utf8Hex $Name)) "actual=$($row[1])" }
  }
  # The row is identified by its id (from hex(name)), not by the JSON "name"
  # text: the CLI's stdout is still written in the ANSI code page, so a
  # non-ANSI name PRINTS as '?' even when the lookup is right (a separate,
  # output-side issue -- see the INBOX note).
  function FoundBy($Name) {
    $ids = (& $exePath sql --db $db --query "select id from symbols where hex(name) = '$(Utf8Hex $Name)'" --json 2>$null) -join "`n" | ConvertFrom-Json
    $id  = if ($ids.rows.Count -ge 1) { [long]$ids.rows[0][0] } else { -1 }
    $r = @((& $exePath query --name $Name --db $db --json 2>$null) -join "`n" | ConvertFrom-Json)
    $hit = @($r | Where-Object { ([long]$_.id -eq $id) -and ($_.match_kind -eq 'exact') })
    Check "query --name finds $(Utf8Hex $Name) by its real spelling (exact, id $id)" (($id -ge 0) -and ($hit.Count -eq 1)) "rows=$($r.Count)"
  }

  Write-Host 'CONTROL (passes on the pre-fix engine):' -ForegroundColor Cyan
  StoredAs 'TPlainAsciiuEncNoBom' 'uEncNoBom.TPlainAsciiuEncNoBom'
  FoundBy  'TPlainAsciiuEncBom'

  Write-Host 'UTF-8 without BOM:' -ForegroundColor Cyan
  StoredAs $noBomCls "uEncNoBom.$noBomCls"
  StoredAs "Run$cy"  "uEncNoBom.$noBomCls.Run$cy"
  FoundBy  $noBomCls

  Write-Host 'UTF-8 with BOM:' -ForegroundColor Cyan
  StoredAs $bomCls "uEncBom.$bomCls"
  FoundBy  $bomCls

  $qm = (& $exePath sql --db $db --query "select count(*) from symbols where instr(name, '?') > 0 or instr(qualified_name, '?') > 0" --json 2>$null) -join "`n" | ConvertFrom-Json
  Check 'no stored symbol name holds a literal ?' ([long]$qm.rows[0][0] -eq 0) "count=$($qm.rows[0][0])"
} finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
