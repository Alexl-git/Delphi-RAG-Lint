<#
  run_asm_quotes.ps1 -- v1.2.1 preprocessor port change #4: lexer quote handling.

  Two behaviors ported from lexer.js (mirroring preprocessor/test-asm-quotes.js):

  (a) MASM double-quoted asm strings: dcc's built-in assembler accepts operands
      like  CMP AL,"'"  (System.AnsiStrings X86ASM arms). The apostrophe INSIDE
      "..." must NOT open a phantom '-string -- otherwise its mis-pairing
      swallows the region's {$ENDIF} and blanks the rest of the unit. So the
      lexer now SKIPS a "..." run (line-bounded).

  (b) Line-bounded quote skips: Pascal strings cannot span lines, so BOTH the
      '...' and "..." skips stop at end-of-line (byte 10). A stray unpaired quote
      can no longer hide directives on later lines.

  Every fixture is oracle-diffed byte-for-byte against the real v1.2.1 JS
  preprocess() via lib\render.js -- the strongest check. Plus content assertions
  that the {$ENDIF}-guarded / post-stray-quote code stays ACTIVE.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath  = (Resolve-Path $Exe).Path
$fixDir   = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures')).Path
$renderJs = (Resolve-Path (Join-Path $PSScriptRoot 'lib\render.js')).Path

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
function Run-Oracle([string]$fixture, [string[]]$oracleArgs) {
  $nodeExe = (Get-Command node).Source
  return ,(Run-Redirected (@((Q $nodeExe), (Q $renderJs), (Q $fixture)) + $oracleArgs))
}
function BytesEqual($a, $b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($k = 0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { return $false } }
  return $true
}
function AsciiOf($bytes) { return [System.Text.Encoding]::ASCII.GetString($bytes, 0, $bytes.Length) }

Push-Location C:\TEMP
try {
  # ============================================================
  # (a) asm_quotes.pas -- X86ASM undefined => asm block blanked. The dquoted
  #     apostrophe must not swallow the {$ENDIF}; var ok1 stays active.
  # ============================================================
  $f1 = Join-Path $fixDir 'asm_quotes.pas'
  $in1  = [System.IO.File]::ReadAllBytes($f1)
  $out1 = Run-Pascal $f1 @()
  $orc1 = Run-Oracle $f1 @()
  Check 'asm_quotes: Length(output) == Length(input)' ($out1.Length -eq $in1.Length)
  Check 'asm_quotes: ORACLE-DIFF Pascal bytes === JS bytes' (BytesEqual $out1 $orc1)
  Check 'asm_quotes: dquoted apostrophe does NOT swallow {$ENDIF} (var ok1 survives)' ((AsciiOf $out1).Contains('var ok1'))

  # ============================================================
  # (b) stray_quote.pas -- an unpaired ' is line-bounded; {$DEFINE AFTER} and its
  #     {$IFDEF AFTER} on later lines still fire => var ok3 survives.
  # ============================================================
  $f2 = Join-Path $fixDir 'stray_quote.pas'
  $in2  = [System.IO.File]::ReadAllBytes($f2)
  $out2 = Run-Pascal $f2 @()
  $orc2 = Run-Oracle $f2 @()
  Check 'stray_quote: Length(output) == Length(input)' ($out2.Length -eq $in2.Length)
  Check 'stray_quote: ORACLE-DIFF Pascal bytes === JS bytes' (BytesEqual $out2 $orc2)
  Check 'stray_quote: stray quote is line-bounded (var ok3 survives)' ((AsciiOf $out2).Contains('var ok3'))

  # ============================================================
  # (c) dir_in_string.pas -- a directive INSIDE a '...' string is still NOT
  #     interpreted: {$IFDEF NOPE} is false, 'bad' must not survive, ok2 does.
  #     (Regression guard for the line-bounding change.)
  # ============================================================
  $f3 = Join-Path $fixDir 'dir_in_string.pas'
  $in3  = [System.IO.File]::ReadAllBytes($f3)
  $out3 = Run-Pascal $f3 @()
  $orc3 = Run-Oracle $f3 @()
  Check 'dir_in_string: Length(output) == Length(input)' ($out3.Length -eq $in3.Length)
  Check 'dir_in_string: ORACLE-DIFF Pascal bytes === JS bytes' (BytesEqual $out3 $orc3)
  Check 'dir_in_string: directive inside ''...'' still ignored (bad absent)' (-not (AsciiOf $out3).Contains('var bad'))
  Check 'dir_in_string: post-string code active (ok2 present)' ((AsciiOf $out3).Contains('var ok2'))

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
