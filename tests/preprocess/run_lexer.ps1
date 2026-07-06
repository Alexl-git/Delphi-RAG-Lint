<#
  run_lexer.ps1 -- TDD harness for PP-Task-2: the directive lexer (port of lexer.js).

  Exercises LexDirectives through the staged exe via the dump-pp-lex diagnostic
  verb. dump-pp-lex prints ONE LINE PER CHUNK in a stable parseable format:
    kind|dir|srcStart|srcEnd|line|value-escaped
  (newline bytes in value are escaped to a literal backslash-n marker so each
  chunk stays on one output line).

  Fixture simple_ifdef.pas (CRLF, 148 bytes) exercises the three core forms:
    {$IFDEF WIN64}  -> directive dir=ifdef args=WIN64
    {$ELSE}         -> directive dir=else
    {$ENDIF}        -> directive dir=endif
  with plain-text const lines between them.

  Asserts the directive chunks, the surrounding text-chunk spans, and the
  strongest structural check: the FULL RECONSTRUCTION invariant -- concatenating
  every chunk's source span sliced from the original file bytes, in order,
  reproduces the ENTIRE file exactly (no gaps, no overlaps).

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\simple_ifdef.pas')).Path

# Raw fixture bytes -- the reconstruction oracle. Read as a byte array so the
# spans (which are BYTE offsets) index it directly.
$bytes = [System.IO.File]::ReadAllBytes($fixture)

# Each parsed chunk: a PSObject with Kind/Dir/SrcStart/SrcEnd/Line.
$chunks = @()

Push-Location C:\TEMP
try {
  $out = & $exePath dump-pp-lex --file $fixture 2>$null | Out-String
  $lines = $out -split "`r?`n" | Where-Object { $_ -ne '' }
  foreach ($ln in $lines) {
    # Split into exactly 6 fields; the value field may itself contain '|', so
    # cap the split at 6 and let the 6th field absorb any remainder.
    $p = $ln -split '\|', 6
    if ($p.Count -lt 6) { continue }
    $chunks += [pscustomobject]@{
      Kind = $p[0]; Dir = $p[1]; SrcStart = [int]$p[2]; SrcEnd = [int]$p[3]; Line = [int]$p[4]; Value = $p[5]
    }
  }

  Check 'lexer emitted at least one chunk' ($chunks.Count -gt 0)

  # --- directive {$IFDEF WIN64} ---
  $ifdef = $chunks | Where-Object { $_.Kind -eq 'directive' -and $_.Dir -eq 'ifdef' } | Select-Object -First 1
  Check 'directive dir=ifdef present'          ($null -ne $ifdef)
  Check 'ifdef args=WIN64'                      ($null -ne $ifdef -and $ifdef.Value -eq 'WIN64')
  Check 'ifdef span = [31,45)'                  ($null -ne $ifdef -and $ifdef.SrcStart -eq 31 -and $ifdef.SrcEnd -eq 45)
  Check 'ifdef line = 2 (0-based)'              ($null -ne $ifdef -and $ifdef.Line -eq 2)

  # --- directive {$ELSE} ---
  $else = $chunks | Where-Object { $_.Kind -eq 'directive' -and $_.Dir -eq 'else' } | Select-Object -First 1
  Check 'directive dir=else present'            ($null -ne $else)
  Check 'else span = [78,85)'                   ($null -ne $else -and $else.SrcStart -eq 78 -and $else.SrcEnd -eq 85)
  Check 'else line = 4 (0-based)'               ($null -ne $else -and $else.Line -eq 4)

  # --- directive {$ENDIF} ---
  $endif = $chunks | Where-Object { $_.Kind -eq 'directive' -and $_.Dir -eq 'endif' } | Select-Object -First 1
  Check 'directive dir=endif present'           ($null -ne $endif)
  Check 'endif span = [118,126)'                ($null -ne $endif -and $endif.SrcStart -eq 118 -and $endif.SrcEnd -eq 126)
  Check 'endif line = 6 (0-based)'              ($null -ne $endif -and $endif.Line -eq 6)

  # --- a const text chunk with a known span ---
  # The first Win64 const line lives in the text chunk [45,78).
  $t1 = $chunks | Where-Object { $_.Kind -eq 'text' -and $_.SrcStart -eq 45 -and $_.SrcEnd -eq 78 } | Select-Object -First 1
  Check 'text chunk [45,78) for Win64 const line' ($null -ne $t1)
  $t2 = $chunks | Where-Object { $_.Kind -eq 'text' -and $_.SrcStart -eq 85 -and $_.SrcEnd -eq 118 } | Select-Object -First 1
  Check 'text chunk [85,118) for Other const line' ($null -ne $t2)

  # --- FULL RECONSTRUCTION INVARIANT ---
  # Concatenate every chunk's [SrcStart,SrcEnd) slice of the raw fixture bytes,
  # in emitted order, and require byte-for-byte identity with the whole file.
  $recon = New-Object System.Collections.Generic.List[byte]
  foreach ($c in $chunks) {
    for ($k = $c.SrcStart; $k -lt $c.SrcEnd; $k++) { $recon.Add($bytes[$k]) }
  }
  $reconArr = $recon.ToArray()
  $identical = ($reconArr.Length -eq $bytes.Length)
  if ($identical) { for ($k = 0; $k -lt $bytes.Length; $k++) { if ($reconArr[$k] -ne $bytes[$k]) { $identical = $false; break } } }
  Check 'FULL RECONSTRUCTION: concatenated spans == whole file (no gaps/overlaps)' $identical
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
