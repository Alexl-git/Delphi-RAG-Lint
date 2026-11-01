<#
  run_output_file_encoding.ps1 -- files a verb WRITES (--output) follow --output-encoding exactly as
  stdout does (ENC-OUT remainder, owner ruling 2026-10-26, lane 140-out).

  Before: `butterfly --output` (text/json/dot) wrote TEncoding.UTF8 WITH a BOM whatever the mode, and
  `uses-report`, `export-enums`-style writers, the per-unit docs export and the diagram writer did the
  same. Now they go through WriteOutputFile: ascii (default) -> 7-bit, non-ASCII as \uXXXX;
  utf8 -> UTF-8 without BOM; utf16 -> UTF-16LE without BOM.

  Fixture: a unit file whose NAME carries U+00E9 and U+0434 (butterfly text/json print "Name.pas:line").
  Controls: (1) each mode asserts its own bytes AND the other modes' bytes are absent, so a run that
  ignores the flag cannot pass; (2) `sql --output` (already converted) is checked the same way;
  (3) the file is non-empty and the odd name is present at all (else nothing was proved).
  Usage: pwsh -File tests\autotest\run_output_file_encoding.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-output-file-enc-$PID")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
function HasBytes([byte[]]$hay, [byte[]]$needle) { [BitConverter]::ToString($hay).Contains([BitConverter]::ToString($needle)) }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
[void][IO.Directory]::CreateDirectory($WorkDir)
try {
  $odd = [string][char]0xE9 + [char]0x434
  $fx  = Join-Path $WorkDir 'fx'
  [void][IO.Directory]::CreateDirectory($fx)
  $src = "unit EncUnit;`r`ninterface`r`nprocedure Noisy;`r`nprocedure Caller;`r`nimplementation`r`nprocedure Noisy;`r`nbegin`r`nend;`r`nprocedure Caller;`r`nbegin`r`n  Noisy;`r`nend;`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $fx "Enc$odd.pas"), $src, [Text.Encoding]::ASCII)
  $db = Join-Path $WorkDir 'e.sqlite'
  Push-Location $fx
  try { & $Exe index . --db $db --quiet *> $null } finally { Pop-Location }
  $BS = [string][char]92
  $esc = $BS + 'u00e9' + $BS + 'u0434'
  $u8  = [Text.Encoding]::UTF8.GetBytes($odd)
  $u16 = [Text.Encoding]::Unicode.GetBytes($odd)
  $bom8 = [byte[]](0xEF, 0xBB, 0xBF)
  $verbs = @(
    @{ n = 'butterfly text'; a = @('butterfly', '--qname', 'EncUnit.Noisy', '--format', 'text', '--db', $db) },
    @{ n = 'butterfly json'; a = @('butterfly', '--qname', 'EncUnit.Noisy', '--format', 'json', '--db', $db) },
    @{ n = 'sql --output';   a = @('sql', '--query', "select '$odd'", '--db', $db, '--json') }
  )
  foreach ($v in $verbs) {
    foreach ($mode in 'default', 'ascii', 'utf8', 'utf16') {
      $f = Join-Path $WorkDir ('o-' + ($v.n -replace '\W', '_') + "-$mode.out")
      $al = @($v.a) + @('--output', $f)
      if ($mode -ne 'default') { $al += @('--output-encoding', $mode) }
      $null = & $Exe @al 2>$null
      $nm = "$($v.n) --output [$mode]"
      if (-not (Test-Path -LiteralPath $f)) { Check "$nm : file written" $false; continue }
      $b = [IO.File]::ReadAllBytes($f)
      Check "$nm : non-empty" ($b.Length -gt 0)
      switch ($mode) {
        { $_ -in 'default', 'ascii' } {
          Check "$nm : 7-bit ASCII" (@($b | Where-Object { $_ -gt 127 }).Count -eq 0)
          Check "$nm : carries the \uXXXX escape (positive control)" ([Text.Encoding]::ASCII.GetString($b).Contains($esc))
        }
        'utf8' {
          Check "$nm : UTF-8 bytes of the name" (HasBytes $b $u8)
          Check "$nm : no BOM" (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF))
          Check "$nm : no \uXXXX escape (negative control)" (-not [Text.Encoding]::UTF8.GetString($b).Contains($esc))
        }
        'utf16' {
          Check "$nm : UTF-16LE bytes of the name" (HasBytes $b $u16)
          Check "$nm : no BOM" (-not ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE))
        }
      }
    }
  }
} finally { if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
