<#
  run_oracle_corpus.ps1 -- PP-Task-5: oracle-diff corpus test hardening the
  port (lexer T2 / expr T3 / processor T4) against tricky lexer/processor
  corner cases BEFORE includes/wiring are added (Tasks 6-10).

  Modeled on run_preprocess_core.ps1. For EACH fixture below, runs BOTH the
  Pascal preprocess-file verb and the REAL JS oracle (lib\render.js, which
  calls tree-sitter-delphi13's preprocess() directly) under a FIXED profile
  (--define win64 --define unicode), then asserts:
    1. the two raw stdout byte streams are BYTE-FOR-BYTE identical (zero
       payload normalization -- a stray CR or trailing LF fails the check), and
    2. Length(pascalOutput) == Length(fixtureInputBytes) (the offset-identity
       invariant: the whole point of the design is that resolved output maps
       1:1 back onto the original file with no source map).

  Byte-exact capture: PowerShell text pipelines mangle bytes (CRLF<->LF,
  encoding). So BOTH sides write to a temp FILE via cmd.exe redirection
  (> file), and we compare the two files' raw byte arrays -- same technique as
  run_preprocess_core.ps1.

  Fixtures (tests/preprocess/fixtures/):
    undef.pas               -- {$DEFINE}/{$UNDEF} then {$IFDEF} on the same
                               symbol: FOO must be INACTIVE after the undef.
    elseif_chain.pas        -- {$IF}/{$ELSEIF}/{$ELSEIF}/{$ELSE}/{$ENDIF}:
                               only the FIRST true branch (the middle ELSEIF,
                               defined(BBB)) wins.
    ifopt.pas               -- {$IFOPT R+}: always false in this port, so the
                               {$ELSE} branch is active.
    passthrough_dir.pas     -- unknown directives {$WARN ...}/{$INLINE ON}
                               pass through as TEXT: verbatim in the active
                               branch, blanked to spaces in the inactive one.
    strings_with_braces.pas -- a string literal containing the TEXT
                               '{$IFDEF}' (must not be parsed as a directive)
                               + a doubled-quote escape ('it''s a test') +
                               a `{ not a directive }` brace comment (no `$`).
    comment_dollar.pas      -- `// {$IFDEF X}` inside a LINE comment: the `//`
                               makes the whole line passthrough text, not a
                               directive.

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

# Run preprocess-file under the FIXED profile, capturing RAW stdout bytes.
function Run-Pascal([string]$fixture) {
  return ,(Run-Redirected @((Q $exePath), 'preprocess-file', '--file', (Q $fixture), '--define', 'win64', '--define', 'unicode'))
}

# Run the JS oracle (real preprocess()) under the SAME fixed profile.
function Run-Oracle([string]$fixture) {
  $nodeExe = (Get-Command node).Source
  return ,(Run-Redirected @((Q $nodeExe), (Q $renderJs), (Q $fixture), '--define', 'win64', '--define', 'unicode'))
}

function BytesEqual($a, $b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($k = 0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { return $false } }
  return $true
}

# One fixture's corpus check: offset-identity invariant + oracle byte-diff.
function CheckFixture([string]$name) {
  $f = Join-Path $fixDir "$name.pas"
  $inBytes  = [System.IO.File]::ReadAllBytes($f)
  $pascal   = Run-Pascal $f
  $oracle   = Run-Oracle $f

  Check "$name`: Length(Pascal output) == Length(input) [OFFSET-IDENTITY INVARIANT]" ($pascal.Length -eq $inBytes.Length)
  Check "$name`: ORACLE-DIFF Pascal bytes === JS bytes (byte-for-byte)" (BytesEqual $pascal $oracle)
}

$fixtures = @('undef', 'elseif_chain', 'ifopt', 'passthrough_dir', 'strings_with_braces', 'comment_dollar')

Push-Location C:\TEMP
try {
  foreach ($name in $fixtures) { CheckFixture $name }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
