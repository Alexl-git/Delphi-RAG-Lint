<#
  run_include_modes.ps1 -- TDD harness for PP-Task-6: include handling in the
  chunk processor (defines-only + off modes). Port of preprocess.js:149-186
  (the {$I}/{$INCLUDE} block), MINUS 'expand' (body splice is forbidden -- it
  would break the offset-identity invariant).

  Exercises Preprocess() through the staged exe via the preprocess-file verb
  extended with --include-mode <off|defines-only>. BaseDir is derived from the
  --file argument's directory so a {$I config.inc} resolves next to main.pas.

  THE defines-only CORRECTNESS PROOF (the whole point of this task):
    fixtures/uses_inc/config.inc  = {$DEFINE FEATURE_X}
    fixtures/uses_inc/main.pas    = {$I config.inc} then {$IFDEF FEATURE_X}...
  In defines-only mode the .inc's {$DEFINE FEATURE_X} must mutate the PARENT's
  live defines set (shared by reference through the recursion), so the parent's
  later {$IFDEF FEATURE_X} takes the THEN branch:
      HasX = True  PRESENT, HasX = False BLANKED.
  In off mode the .inc is ignored, FEATURE_X stays undefined, so the ELSE wins:
      HasX = True  BLANKED, HasX = False PRESENT.
  Either way the {$I} directive is BLANKED (never spliced) so:
      Length(output) == Length(input of main.pas)  (offset-identity invariant).

  ORACLE-DIFF: the same file is rendered through the REAL tree-sitter-delphi13
  preprocess() via lib\render.js (which passes includeMode + baseDir), and the
  Pascal bytes must equal the JS bytes byte-for-byte, in BOTH modes.

  Byte-exact capture: PowerShell text pipelines mangle bytes. BOTH sides write
  to a temp FILE via cmd.exe redirection (> file); we compare raw byte arrays.

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
function AsciiOf($bytes) {
  return [System.Text.Encoding]::ASCII.GetString($bytes, 0, $bytes.Length)
}

# True iff the literal ASCII $needle appears as a contiguous run of bytes in
# $bytes -- used to prove a line SURVIVED verbatim in the resolved output.
function ContainsLine($bytes, [string]$needle) {
  return (AsciiOf $bytes).Contains($needle)
}

Push-Location C:\TEMP
try {
  $main = Join-Path $fixDir 'uses_inc\main.pas'
  $inBytes = [System.IO.File]::ReadAllBytes($main)

  # ============================================================
  # defines-only: config.inc's {$DEFINE FEATURE_X} propagates to the parent.
  # THE defines-only correctness proof.
  # ============================================================
  $do = Run-Pascal $main @('--include-mode', 'defines-only', '--define', 'win64')
  $doText = AsciiOf $do

  Check 'defines-only: HasX = True line PRESENT (config.inc FEATURE_X propagated -> THEN branch)' ($doText.Contains('const HasX = True;'))
  Check 'defines-only: HasX = False line BLANKED (ELSE branch inactive)' (-not $doText.Contains('const HasX = False;'))
  Check 'defines-only: Length(output) == Length(input) [OFFSET-IDENTITY INVARIANT -- {$I} blanked, NO body splice]' ($do.Length -eq $inBytes.Length)

  $doOrc = Run-Oracle $main @('--include-mode', 'defines-only', '--define', 'win64')
  Check 'defines-only: ORACLE-DIFF Pascal bytes === JS bytes (byte-for-byte)' (BytesEqual $do $doOrc)

  # ============================================================
  # off: config.inc is ignored -> FEATURE_X undefined -> the ELSE branch wins.
  # Proves off vs defines-only differ CORRECTLY.
  # ============================================================
  $off = Run-Pascal $main @('--include-mode', 'off', '--define', 'win64')
  $offText = AsciiOf $off

  Check 'off: HasX = False line PRESENT (config.inc ignored -> FEATURE_X undefined -> ELSE branch)' ($offText.Contains('const HasX = False;'))
  Check 'off: HasX = True line BLANKED (THEN branch inactive)' (-not $offText.Contains('const HasX = True;'))
  Check 'off: Length(output) == Length(input) [offset-identity invariant]' ($off.Length -eq $inBytes.Length)

  $offOrc = Run-Oracle $main @('--include-mode', 'off', '--define', 'win64')
  Check 'off: ORACLE-DIFF Pascal bytes === JS bytes (byte-for-byte)' (BytesEqual $off $offOrc)

  # off vs defines-only must differ (proves the mode actually changes behaviour).
  Check 'off vs defines-only: outputs DIFFER (mode selection is real)' (-not (BytesEqual $do $off))

  # ============================================================
  # v1.2.1 port change #1 (transitive): a {$DEFINE} in a NESTED include
  # (main -> outer.inc -> inner.inc) must propagate all the way up to the top
  # parent's later {$IFDEF}. The Delphi port has no 'expand' body-splice mode
  # (that would break offset-identity), so #1's "propagate in expand mode" JS fix
  # maps here to the defines-only recursion sharing the parent's define
  # dictionary BY REFERENCE through every nesting level. inner.inc defines
  # NESTED_OK; main's {$IFDEF NESTED_OK} must therefore take the THEN branch.
  # ============================================================
  $nmain = Join-Path $fixDir 'uses_inc_nested\main.pas'
  $nIn   = [System.IO.File]::ReadAllBytes($nmain)
  $nDo   = Run-Pascal $nmain @('--include-mode', 'defines-only')
  $nText = AsciiOf $nDo

  Check 'nested defines-only: Nested = True PRESENT (inner.inc NESTED_OK propagated 2 levels up)' ($nText.Contains('const Nested = True;'))
  Check 'nested defines-only: Nested = False BLANKED (ELSE inactive)' (-not $nText.Contains('const Nested = False;'))
  Check 'nested defines-only: Length(output) == Length(input) [offset-identity, no splice]' ($nDo.Length -eq $nIn.Length)

  $nOrc = Run-Oracle $nmain @('--include-mode', 'defines-only')
  Check 'nested defines-only: ORACLE-DIFF Pascal bytes === JS bytes (byte-for-byte)' (BytesEqual $nDo $nOrc)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
