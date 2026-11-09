<#
  run_dfm_event_binding_encoding.ps1 -- ExtractDfmEventBindings transcodes per the .dfm encoding (wave 150 DF2).

  149 DF incidental 5: Doc.SymbolFacts.DfmEventMapFor hands the RAW .dfm bytes to ExtractDfmEventBindings. A
  BOM-less Windows-1252 .dfm with a non-ASCII identifier (OnClick = btn<U-umlaut>berClick) reached tree-sitter as an
  invalid UTF-8 byte (U+FFFD), so the handler name was truncated and the 'Handles:' doc fact was lost.
  The function now runs EnsureUtf8Bytes itself (UTF-8 BOM / UTF-16 / BOM-less ANSI), after the binary-DFM check.

  The observable: `document --unit <U.pas> --db <db>` (dry run) prints '<para>Handles: <Object>.<Event></para>'
  for a method wired by the paired .dfm.
  E1. FormAnsi (Windows-1252, no BOM):  Handles: btn<U-umlaut>ber.OnClick      (RED on the 1.49.0-alpha base: no line)
  E2. FormUtf8 (UTF-8 + BOM):           Handles: btn<U-umlaut>ber.OnClick      (positive control: passes before and after)
  E3. Negative control: the same unit indexed WITHOUT its .dfm prints NO Handles line (the assertion can fail).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_dfm_evbind_$PID"
)
try {
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$Fx = Join-Path $PSScriptRoot '..\fixtures\dfm-nonascii'
$Want = 'Handles: btn' + [char]0x00DC + 'ber.OnClick'

$Work = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $Work -Force | Out-Null
Copy-Item (Join-Path $Fx '*') $Work
$Db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $Work --db $Db 2>&1 | Out-Null
Check 'index built' (Test-Path $Db)

function DocOut([string]$Unit) {
  return (& $Exe document --unit (Join-Path $Work $Unit) --db $Db --output-encoding utf8 2>&1) -join "`n"
}
$a = DocOut 'FormAnsi.pas'
Check 'E1 ANSI .dfm: Handles line carries the full non-ASCII object name' ($a.Contains($Want)) ("got: " + ($a -replace "`r",''))
$u = DocOut 'FormUtf8.pas'
Check 'E2 UTF-8/BOM .dfm (positive control): same Handles line' ($u.Contains($Want)) ("got: " + ($u -replace "`r",''))
$Work2 = Join-Path $WorkDir 'fx2'
New-Item -ItemType Directory $Work2 -Force | Out-Null
Copy-Item (Join-Path $Fx 'FormAnsi.pas') $Work2
$Db2 = Join-Path $WorkDir 'fx2.sqlite'
& $Exe index $Work2 --db $Db2 2>&1 | Out-Null
$n = (& $Exe document --unit (Join-Path $Work2 'FormAnsi.pas') --db $Db2 --output-encoding utf8 2>&1) -join "`n"
Check 'E3 negative control: unit without its .dfm -> no Handles line' (-not $n.Contains('Handles:')) ("got: " + ($n -replace "`r",''))

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
