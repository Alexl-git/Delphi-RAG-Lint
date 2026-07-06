<#
  run_preprocess_core.ps1 -- TDD harness for PP-Task-4: the chunk processor
  (defines + conditionals, no includes yet). Port of preprocess.js:45-147,188-193.

  Exercises Preprocess() through the staged exe via the preprocess-file
  diagnostic verb. That verb reads --file as raw BYTES, builds a TDefineProfile
  from repeatable --define / --numeric, calls Preprocess, and writes the
  resulting BYTES to stdout VERBATIM (no newline translation, no re-encoding).

  THE CRITICAL PROPERTY is the offset-identity invariant:
      Length(output) == Length(input)   (in BYTES)
  which is what makes the design source-map-free (tree-sitter spans map 1:1 to
  the original file). Every assertion below is byte-level.

  ORACLE-DIFF (the strongest check): for each fixture, we also render the SAME
  input through the real tree-sitter-delphi13 preprocess() function via
  lib\render.js and require the Pascal bytes === the JS bytes, byte-for-byte.

  Byte-exact capture: PowerShell text pipelines mangle bytes (CRLF<->LF,
  encoding). So BOTH sides write to a temp FILE via cmd.exe redirection
  (> file), and we compare the two files' raw byte arrays. render.js and the
  Pascal verb both do a single raw stdout write of a UTF-8 buffer, so the only
  bytes on stdout are the resolved output -- no trailing newline is added by
  either side (neither uses console.log / Writeln for the payload). No newline
  normalization is applied to the payload; if the two differ by even one byte
  (including a stray CR or trailing LF) the test FAILS.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath  = (Resolve-Path $Exe).Path
$fixDir   = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures')).Path
$renderJs = (Resolve-Path (Join-Path $PSScriptRoot 'lib\render.js')).Path

# Quote one token for a cmd.exe command line.
function Q([string]$s) { return '"' + $s + '"' }

# Run a command line via cmd.exe /c, redirecting stdout to a temp file so no
# PowerShell text translation touches the bytes, and return the raw byte array.
# cmd.exe /c with a program path that contains spaces needs the ENTIRE command
# line passed as a SINGLE quoted argument (cmd's own outer-quote stripping rule),
# so we assemble one string and hand it to cmd via -ArgumentList "/c","<line>".
function Run-Redirected([string[]]$tokens) {
  $tmp = [System.IO.Path]::GetTempFileName()
  $line = ($tokens -join ' ') + ' > ' + (Q $tmp)
  $p = Start-Process cmd.exe -ArgumentList '/c', ('"' + $line + '"') -NoNewWindow -Wait -PassThru
  $bytes = [System.IO.File]::ReadAllBytes($tmp)
  Remove-Item $tmp -Force
  return ,$bytes
}

# Run preprocess-file, capturing RAW stdout bytes. Returns the byte array.
function Run-Pascal([string]$fixture, [string[]]$verbArgs) {
  return ,(Run-Redirected (@((Q $exePath), 'preprocess-file', '--file', (Q $fixture)) + $verbArgs))
}

# Run the JS oracle (real preprocess()), capturing RAW stdout bytes.
function Run-Oracle([string]$fixture, [string[]]$oracleArgs) {
  $nodeExe = (Get-Command node).Source
  return ,(Run-Redirected (@((Q $nodeExe), (Q $renderJs), (Q $fixture)) + $oracleArgs))
}

function BytesEqual($a, $b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($k = 0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { return $false } }
  return $true
}

# Decode a byte range to an ASCII string (fixtures are 7-bit ASCII).
function AsciiOf($bytes, $start, $len) {
  return [System.Text.Encoding]::ASCII.GetString($bytes, $start, $len)
}

# True iff every byte in [start,end) is a space (32) or LF (10) -- i.e. the span
# was blanked (all non-newline bytes replaced by spaces, newlines preserved).
function IsBlanked($bytes, $start, $end) {
  for ($k = $start; $k -lt $end; $k++) {
    if ($bytes[$k] -ne 32 -and $bytes[$k] -ne 10) { return $false }
  }
  return $true
}

Push-Location C:\TEMP
try {
  # ============================================================
  # Fixture 1: simple_ifdef.pas  (--define WIN64)
  # ============================================================
  $f1 = Join-Path $fixDir 'simple_ifdef.pas'
  $in1 = [System.IO.File]::ReadAllBytes($f1)
  $out1 = Run-Pascal $f1 @('--define', 'WIN64')

  # THE critical assertion: byte-length identity (offset-identity invariant).
  Check 'simple_ifdef: Length(output) == Length(input) [OFFSET-IDENTITY INVARIANT]' ($out1.Length -eq $in1.Length)

  # Active branch present: the Win64 const line survives verbatim.
  $win64Line = "const PlatformName = 'Win64';"
  $outText1 = AsciiOf $out1 0 $out1.Length
  Check "simple_ifdef: active branch line present ($win64Line)" ($outText1.Contains($win64Line))

  # Inactive ELSE branch blanked: the 'Other' const line span is all spaces/LF.
  # In the fixture, the Other const line lives at input bytes [85,118).
  Check "simple_ifdef: inactive 'Other' branch blanked (bytes 85..118 all space/LF)" (IsBlanked $out1 85 118)
  # And its text (Other) must NOT appear anywhere in the output.
  Check "simple_ifdef: 'Other' text does NOT survive" (-not $outText1.Contains("'Other'"))

  # Directive bytes blanked: {$IFDEF WIN64} [31,45), {$ELSE} [78,85), {$ENDIF} [118,126).
  Check 'simple_ifdef: {$IFDEF WIN64} directive blanked [31,45)'  (IsBlanked $out1 31 45)
  Check 'simple_ifdef: {$ELSE} directive blanked [78,85)'          (IsBlanked $out1 78 85)
  Check 'simple_ifdef: {$ENDIF} directive blanked [118,126)'       (IsBlanked $out1 118 126)

  # ORACLE-DIFF.
  $orc1 = Run-Oracle $f1 @('--define', 'win64')
  Check 'simple_ifdef: ORACLE-DIFF Pascal bytes === JS bytes' (BytesEqual $out1 $orc1)

  # ============================================================
  # Fixture 2: nested_if.pas  (--define A) -- nested conditionals
  # A defined, B not: outer THEN active, inner ELSE active.
  # ============================================================
  $f2 = Join-Path $fixDir 'nested_if.pas'
  $in2 = [System.IO.File]::ReadAllBytes($f2)
  $out2 = Run-Pascal $f2 @('--define', 'A')
  $outText2 = AsciiOf $out2 0 $out2.Length
  Check 'nested_if: Length(output) == Length(input)' ($out2.Length -eq $in2.Length)
  Check 'nested_if: outer-A active line present (OuterA)'   ($outText2.Contains('const OuterA = 1;'))
  Check 'nested_if: inner-not-B active line present (InnerNotB)' ($outText2.Contains('const InnerNotB = 3;'))
  Check 'nested_if: inner-B line blanked (InnerB absent)'   (-not $outText2.Contains('const InnerB = 2;'))
  Check 'nested_if: no-A line blanked (NoA absent)'         (-not $outText2.Contains('const NoA = 4;'))
  $orc2 = Run-Oracle $f2 @('--define', 'a')
  Check 'nested_if: ORACLE-DIFF Pascal bytes === JS bytes' (BytesEqual $out2 $orc2)

  # ============================================================
  # Fixture 3: if_expr.pas  ({$IF CompilerVersion >= 37}) -- evaluator path
  # ============================================================
  $f3 = Join-Path $fixDir 'if_expr.pas'
  $in3 = [System.IO.File]::ReadAllBytes($f3)
  $out3 = Run-Pascal $f3 @('--numeric', 'CompilerVersion=37')
  $outText3 = AsciiOf $out3 0 $out3.Length
  Check 'if_expr: Length(output) == Length(input)' ($out3.Length -eq $in3.Length)
  Check 'if_expr: {$IF} THEN branch active (Modern present)'  ($outText3.Contains('const Modern = True;'))
  Check 'if_expr: {$ELSE} branch blanked (Legacy absent)'     (-not $outText3.Contains('const Legacy = True;'))
  $orc3 = Run-Oracle $f3 @('--numeric', 'CompilerVersion=37')
  Check 'if_expr: ORACLE-DIFF Pascal bytes === JS bytes' (BytesEqual $out3 $orc3)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
