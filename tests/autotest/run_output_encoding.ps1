<#
  run_output_encoding.ps1 -- engine pipe output encoding (--output-encoding) and
  non-ANSI paths on the way IN to the index.

  THE DEFECT (docs\INBOX-engine-output-ansi-and-nonansi-input-lossy.md, 2026-10-26)
  ---------------------------------------------------------------------------
  * stdout/stderr were written in the ANSI code page (CP_ACP): U+00E9 left as a
    lone cp1252 byte E9 (invalid UTF-8 for the LSP, which reads `lint --json` as
    UTF-8) and U+0434 as `?` -- lost.
  * files.path was ALREADY `?` for U+0434 at store time: every string parameter
    was bound with TFDParam.AsString, which FireDAC types ftString (ANSI), so a
    path outside cp1252 was destroyed before it reached SQLite.

  OWNER RULING 2026-10-26: Unicode output is allowed by a user option; the
  DEFAULT stays 7-bit ASCII.
    ascii (default)  every non-ASCII UTF-16 code unit is written as \uXXXX
                     (lower-case hex; a non-BMP char is its surrogate pair).
                     In --json that is the JSON escape itself, so a JSON reader
                     gets the exact string back.
    utf8             UTF-8, no BOM.
    utf16            UTF-16LE, no BOM.
  Precedence: --output-encoding on the command line, else "outputEncoding" in
  the .drag-lint.json defaults file, else ascii.

  Each mode is checked against a fixture whose directory name carries U+00E9
  (cp1252), U+0434 (not in cp1252) and U+1F600 (outside the BMP): a POSITIVE
  check that the path round-trips, and a NEGATIVE control that the bytes are
  the mode's own (escaped / raw UTF-8 / UTF-16) and not some other one -- so a
  run that ignores the flag cannot pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-output-encoding-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# Runs the engine with a Unicode argv (CreateProcessW) and returns the RAW
# stdout / stderr bytes -- no PowerShell decoding in between.
function Invoke-Raw([string[]]$ArgList, [string]$Cwd = $WorkDir) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory       = $Cwd
  $psi.UseShellExecute        = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $msOut = New-Object System.IO.MemoryStream
  $msErr = New-Object System.IO.MemoryStream
  $tOut = $p.StandardOutput.BaseStream.CopyToAsync($msOut)
  $tErr = $p.StandardError.BaseStream.CopyToAsync($msErr)
  $p.WaitForExit()
  $tOut.Wait(); $tErr.Wait()
  [pscustomobject]@{ Out = $msOut.ToArray(); Err = $msErr.ToArray(); Code = $p.ExitCode }
}
# rows[0][0] of a sql --json document; $null when it does not parse.
function Row0([byte[]]$b, $enc) { try { ($enc.GetString($b) | ConvertFrom-Json).rows[0][0] } catch { $null } }
function HiCount([byte[]]$b) { @($b | Where-Object { $_ -gt 127 }).Count }
function HasBytes([byte[]]$hay, [byte[]]$needle) {
  $h = [BitConverter]::ToString($hay); $n = [BitConverter]::ToString($needle)
  return $h.Contains($n)
}
# The text-mode escape, reversed: \uXXXX -> the UTF-16 code unit.
function Unescape([string]$s) {
  [regex]::Replace($s, '\\u([0-9a-f]{4})', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
}

if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory $WorkDir | Out-Null

$odd  = [string][char]0xE9 + [char]0x434 + [char]::ConvertFromUtf32(0x1F600)
$fx   = Join-Path $WorkDir ('fx_' + $odd)
New-Item -ItemType Directory -Path $fx | Out-Null
$src = "unit EncUnit;`r`n`r`ninterface`r`n`r`nprocedure Noisy;`r`n`r`nimplementation`r`n`r`nprocedure Noisy;`r`nbegin`r`n  WriteLn('hello');`r`nend;`r`n`r`nend.`r`n"
$unit = Join-Path $fx 'EncUnit.pas'
[System.IO.File]::WriteAllText($unit, $src, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'enc.sqlite'

$BS = [string][char]92   # a literal backslash: keeps the escapes out of this file's own text
$escOdd = $BS + 'u00e9' + $BS + 'u0434' + $BS + 'ud83d' + $BS + 'ude00'
$utf8Odd = [System.Text.Encoding]::UTF8.GetBytes($odd)
$u16Odd  = [System.Text.Encoding]::Unicode.GetBytes($odd)

Write-Host 'Input: a non-ANSI path survives into the index' -ForegroundColor Cyan
$r = Invoke-Raw @('index', $fx, '--db', $db, '--quiet')
Check 'index exits 0' ($r.Code -eq 0) "(exit $($r.Code))"
$r = Invoke-Raw @('sql', '--query', 'select hex(path) from files', '--db', $db, '--json')
$hex = ([System.Text.Encoding]::ASCII.GetString($r.Out) | ConvertFrom-Json).rows[0][0]
$want = ([BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($unit))).Replace('-', '')
Check 'files.path holds the exact UTF-8 of the path' ($hex -eq $want) "(got $hex)"
Check 'NEGATIVE: files.path has no ? where U+0434 was' (-not $hex.Contains('C3A93F')) ''

Write-Host ''
Write-Host 'Default (ascii): JSON' -ForegroundColor Cyan
$q = @('sql', '--query', 'select path from files', '--db', $db, '--json')
$r = Invoke-Raw $q
Check 'stdout is 7-bit ASCII' ((HiCount $r.Out) -eq 0) "($(HiCount $r.Out) byte(s) >127)"
$txt = [System.Text.Encoding]::ASCII.GetString($r.Out)
Check 'the escape is \uXXXX, surrogate pair for U+1F600' ($txt.Contains($escOdd)) ''
Check 'the JSON decodes back to the exact path' ((Row0 $r.Out ([System.Text.Encoding]::ASCII)) -ceq $unit) ''
$rA = Invoke-Raw ($q + @('--output-encoding', 'ascii'))
Check '--output-encoding ascii is byte-identical to the default' ([BitConverter]::ToString($rA.Out) -eq [BitConverter]::ToString($r.Out)) ''

Write-Host ''
Write-Host 'Default (ascii): text (stdout) and stderr' -ForegroundColor Cyan
$r = Invoke-Raw @('lint', $unit, '--db', $db)
$txt = [System.Text.Encoding]::ASCII.GetString($r.Out)
Check 'lint text fired on the fixture' ($txt -match 'writeln-in-source') '(else this asserts nothing)'
Check 'lint text stdout is 7-bit ASCII' ((HiCount $r.Out) -eq 0) ''
Check 'lint text unescapes back to the path' ((Unescape $txt).Contains($unit)) ''
$r = Invoke-Raw @('index', $fx, '--db', (Join-Path $WorkDir 'enc2.sqlite'))
$etxt = [System.Text.Encoding]::ASCII.GetString($r.Err)
Check 'stderr (index progress) is 7-bit ASCII' ((HiCount $r.Err) -eq 0) "($(HiCount $r.Err) byte(s) >127)"
Check 'stderr carries the escaped path' ($etxt.Contains('fx_' + $escOdd)) ''

Write-Host ''
Write-Host 'lint --json (the LSP reader: UTF-8 decode)' -ForegroundColor Cyan
$r = Invoke-Raw @('lint', $unit, '--db', $db, '--json')
$js = [System.Text.Encoding]::UTF8.GetString($r.Out) | ConvertFrom-Json
$paths = @($js | ForEach-Object { $_.file_path } | Where-Object { $_ })
Check 'lint --json has findings' ($paths.Count -gt 0) ''
Check 'a UTF-8 reader gets the exact path back' ($paths.Count -gt 0 -and ($paths | Where-Object { $_ -ceq $unit }).Count -eq $paths.Count) "($($paths[0]))"

Write-Host ''
Write-Host 'utf8' -ForegroundColor Cyan
$r = Invoke-Raw ($q + @('--output-encoding', 'utf8'))
Check 'no BOM' (-not ($r.Out.Length -ge 3 -and $r.Out[0] -eq 0xEF -and $r.Out[1] -eq 0xBB -and $r.Out[2] -eq 0xBF)) ''
Check 'carries the raw UTF-8 bytes of the path' (HasBytes $r.Out $utf8Odd) ''
Check 'NEGATIVE: no \u escape in utf8 mode' (-not [System.Text.Encoding]::UTF8.GetString($r.Out).Contains($BS + 'u00e9')) ''
Check 'decodes back to the exact path' ((Row0 $r.Out ([System.Text.Encoding]::UTF8)) -ceq $unit) ''
$r = Invoke-Raw @('index', $fx, '--db', (Join-Path $WorkDir 'enc3.sqlite'), '--output-encoding', 'utf8')
Check 'stderr in utf8 carries the raw UTF-8 path' (HasBytes $r.Err $utf8Odd) ''

Write-Host ''
Write-Host 'utf16' -ForegroundColor Cyan
$r = Invoke-Raw ($q + @('--output-encoding', 'utf16'))
Check 'no BOM' (-not ($r.Out.Length -ge 2 -and $r.Out[0] -eq 0xFF -and $r.Out[1] -eq 0xFE)) ''
Check 'carries the UTF-16LE bytes of the path' (HasBytes $r.Out $u16Odd) ''
Check 'even byte count' (($r.Out.Length % 2) -eq 0) "($($r.Out.Length))"
Check 'decodes back to the exact path' ((Row0 $r.Out ([System.Text.Encoding]::Unicode)) -ceq $unit) ''

Write-Host ''
Write-Host 'ASCII-only output is identical in every mode but utf16' -ForegroundColor Cyan
$qa = @('sql', '--query', "select 'plain ascii' as v", '--db', $db, '--json')
$a1 = Invoke-Raw $qa
$a2 = Invoke-Raw ($qa + @('--output-encoding', 'utf8'))
Check 'ascii == utf8 byte for byte on ASCII content' ([BitConverter]::ToString($a1.Out) -eq [BitConverter]::ToString($a2.Out)) ''

Write-Host ''
Write-Host 'Configuration and refusal' -ForegroundColor Cyan
$r = Invoke-Raw @('sql', '--query', 'select 1', '--db', $db, '--output-encoding', 'latin1')
Check 'an unknown value is an argument error (exit 3)' ($r.Code -eq 3) "(exit $($r.Code))"
Check 'the error names the accepted values' ([System.Text.Encoding]::ASCII.GetString($r.Err + $r.Out) -match 'ascii\|utf8\|utf16') ''
$cfgDir = Join-Path $WorkDir 'cfg'
New-Item -ItemType Directory $cfgDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $cfgDir '.drag-lint.json'), '{ "outputEncoding": "utf8" }', [System.Text.Encoding]::ASCII)
$r = Invoke-Raw ($q + @('--quiet')) $cfgDir
Check 'the .drag-lint.json "outputEncoding" key selects utf8' (HasBytes $r.Out $utf8Odd) ''
$r = Invoke-Raw ($q + @('--quiet', '--output-encoding', 'ascii')) $cfgDir
Check 'the command line beats the defaults file' ((HiCount $r.Out) -eq 0 -and [System.Text.Encoding]::ASCII.GetString($r.Out).Contains($escOdd)) ''

Write-Host ''
Write-Host ''
Write-Host 'Files a verb writes (--output) and the lossy-output warning' -ForegroundColor Cyan
$qf = @('sql', '--query', 'select path from files', '--db', $db, '--json')
$fA = Join-Path $WorkDir 'out-ascii.json'
$r = Invoke-Raw ($qf + @('--output', $fA))
$b = [System.IO.File]::ReadAllBytes($fA)
Check 'default: --output file is 7-bit ASCII' ((HiCount $b) -eq 0) "($(HiCount $b) byte(s) >127)"
Check 'default: --output file carries the \uXXXX escape' ([System.Text.Encoding]::ASCII.GetString($b).Contains($escOdd)) ''
$etxt = [System.Text.Encoding]::ASCII.GetString($r.Err)
$warn = [regex]::Matches($etxt, 'non-ASCII character\(s\) were written')
Check 'default: the warning appears exactly once' ($warn.Count -eq 1) "($($warn.Count))"
$m = [regex]::Match($etxt, '(\d+) non-ASCII character')
Check 'default: the warning count is positive' ($m.Success -and [int]$m.Groups[1].Value -gt 0) "($($m.Groups[1].Value))"
Check 'default: the warning names the switch and the config key' ($etxt.Contains('--output-encoding utf8') -and $etxt.Contains('outputEncoding')) ''
$doc = [System.Text.Encoding]::ASCII.GetString($b) | ConvertFrom-Json
Check 'default: a JSON file gains lossy_output > 0' ($doc.lossy_output -gt 0) "($($doc.lossy_output))"
$fU = Join-Path $WorkDir 'out-utf8.json'
$r = Invoke-Raw ($qf + @('--output', $fU, '--output-encoding', 'utf8'))
$b = [System.IO.File]::ReadAllBytes($fU)
Check 'utf8: --output file holds the raw UTF-8 path' (HasBytes $b $utf8Odd) ''
Check 'utf8: --output file round-trips the exact path' ((Row0 $b ([System.Text.Encoding]::UTF8)) -ceq $unit) ''
Check 'utf8: NEGATIVE no \u escape in the file' (-not [System.Text.Encoding]::UTF8.GetString($b).Contains($BS + 'u00e9')) ''
Check 'utf8: NEGATIVE no warning, no lossy_output' (([System.Text.Encoding]::ASCII.GetString($r.Err) -notmatch 'non-ASCII character') -and ([System.Text.Encoding]::UTF8.GetString($b) -notmatch 'lossy_output')) ''
$fW = Join-Path $WorkDir 'out-utf16.json'
$r = Invoke-Raw ($qf + @('--output', $fW, '--output-encoding', 'utf16'))
$b = [System.IO.File]::ReadAllBytes($fW)
Check 'utf16: --output file round-trips the exact path' ((Row0 $b ([System.Text.Encoding]::Unicode)) -ceq $unit) ''
$fR = Join-Path $WorkDir 'lint-report.txt'
$r = Invoke-Raw @('lint', $unit, '--db', $db, '--json', '--output', $fR, '--output-encoding', 'utf8')
Check 'lint --output (utf8) writes the raw UTF-8 path' (HasBytes ([System.IO.File]::ReadAllBytes($fR)) $utf8Odd) ''
$r = Invoke-Raw @('sql', '--query', "select 'plain ascii' as v", '--db', $db, '--json', '--output', (Join-Path $WorkDir 'plain.json'))
Check 'pure-ASCII run: NEGATIVE control, no warning on stderr' ([System.Text.Encoding]::ASCII.GetString($r.Err) -notmatch 'non-ASCII character') ''
Check 'pure-ASCII run: no lossy_output in the file' (-not [System.IO.File]::ReadAllText((Join-Path $WorkDir 'plain.json')).Contains('lossy_output')) ''
$r = Invoke-Raw $q
Check 'stdout-only default run also warns once' ([regex]::Matches([System.Text.Encoding]::ASCII.GetString($r.Err), 'non-ASCII character\(s\) were written').Count -eq 1) ''

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-output-encoding-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
