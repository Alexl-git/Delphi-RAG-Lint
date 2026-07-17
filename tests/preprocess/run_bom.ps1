<#
  run_bom.ps1 -- v1.2.1 preprocessor port change #3: a decoded UTF-8 BOM
  (the 3 bytes EF BB BF) at the START of the input is BLANKED offset-preservingly
  (each BOM byte -> a space, byte 32) so it never survives into the resolved
  source. Mirrors preprocess.js:57 (input.charCodeAt(0)===0xFEFF -> ' '+slice),
  adapted to the Pascal BYTE model: the JS blanks ONE decoded U+FEFF char to ONE
  space; in the byte world the UTF-8 BOM is THREE bytes, and the offset-identity
  invariant (Length(out)==Length(in) in BYTES) requires blanking all three to
  three spaces.

  NOTE ON THE ORACLE: this change is NOT oracle-diffed through lib\render.js,
  because Node's fs.readFileSync(file,'utf8') strips a UTF-8 BOM before
  preprocess() ever sees it -- so the JS side would never exercise the blank.
  The assertions here are therefore Pascal-only byte checks (the same style the
  core harness uses for the directive-blanking spans).

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures')).Path

function Q([string]$s) { return '"' + $s + '"' }

function Run-Redirected([string[]]$tokens) {
  $tmp = [System.IO.Path]::GetTempFileName()
  $line = ($tokens -join ' ') + ' > ' + (Q $tmp)
  Start-Process cmd.exe -ArgumentList '/c', ('"' + $line + '"') -NoNewWindow -Wait | Out-Null
  $bytes = [System.IO.File]::ReadAllBytes($tmp)
  Remove-Item $tmp -Force
  return ,$bytes
}

function Run-Pascal([string]$fixture, [string[]]$verbArgs) {
  return ,(Run-Redirected (@((Q $exePath), 'preprocess-file', '--file', (Q $fixture)) + $verbArgs))
}

function AsciiOf($bytes, $start, $len) {
  return [System.Text.Encoding]::ASCII.GetString($bytes, $start, $len)
}

Push-Location C:\TEMP
try {
  # ============================================================
  # bom_main.pas begins with EF BB BF, then "unit withbom; ...".
  # ============================================================
  $f = Join-Path $fixDir 'bom_main.pas'
  $in  = [System.IO.File]::ReadAllBytes($f)
  $out = Run-Pascal $f @()

  Check 'bom: input actually starts with EF BB BF (fixture sanity)' ($in.Length -ge 3 -and $in[0] -eq 0xEF -and $in[1] -eq 0xBB -and $in[2] -eq 0xBF)

  # THE offset-identity invariant: byte length unchanged.
  Check 'bom: Length(output) == Length(input) [OFFSET-IDENTITY INVARIANT]' ($out.Length -eq $in.Length)

  # The 3 leading BOM bytes are now spaces (byte 32), not EF/BB/BF.
  Check 'bom: leading 3 BOM bytes blanked to spaces' ($out.Length -ge 3 -and $out[0] -eq 32 -and $out[1] -eq 32 -and $out[2] -eq 32)

  # No BOM byte survives anywhere in the output.
  $anyBom = $false
  for ($k = 0; $k -lt $out.Length; $k++) { if ($out[$k] -eq 0xEF -or $out[$k] -eq 0xBB -or $out[$k] -eq 0xBF) { $anyBom = $true; break } }
  Check 'bom: no BOM byte survives anywhere in output' (-not $anyBom)

  # The real content (past the BOM) is intact -- 'off' mode + no directives, so
  # the whole file after the BOM is active text copied verbatim.
  $outText = AsciiOf $out 3 ($out.Length - 3)
  Check 'bom: content after BOM intact (unit withbom;)' ($outText.Contains('unit withbom;'))
  Check 'bom: content after BOM intact (const X = 1;)'  ($outText.Contains('const X = 1;'))

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
