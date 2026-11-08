<#
  run_output_encoding_written_files.ps1 -- E-OUTENC-WRITTEN-FILES

  The audit of the files a verb WRITES against --output-encoding, beyond what
  run_output_encoding.ps1 pins (query / lint --output): the lint-all report, both
  by --output and at its default path beside the DB, and sql --output, text and
  --json. Every one goes through WriteOutputFile; this pins that per surface.

  ascii (default): 7-bit, the non-ASCII path as \uXXXX.
  utf8: raw UTF-8 bytes, no BOM. utf16: UTF-16LE, the exact path.
  POSITIVE CONTROL: the plain-ASCII query proves the check for raw bytes is not
  true of every file (it holds no non-ASCII byte in any mode but utf16).

  Usage: pwsh -File tests\autotest\run_output_encoding_written_files.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-outenc-files-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
# Unicode argv (CreateProcessW), raw exit code; the output is not the subject here.
function Run([string[]]$ArgList) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $WorkDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $tO = $p.StandardOutput.ReadToEndAsync(); $tE = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit(); $null = $tO.Wait(1000); $null = $tE.Wait(1000)
  return $p.ExitCode
}
function HiCount([byte[]]$b) { @($b | Where-Object { $_ -gt 127 }).Count }
function HasBytes([byte[]]$hay, [byte[]]$needle) { [BitConverter]::ToString($hay).Contains([BitConverter]::ToString($needle)) }
function Bom([byte[]]$b) { ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }

if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$odd = [string][char]0xE9 + [char]0x434 + [char]::ConvertFromUtf32(0x1F600)
$fx  = Join-Path $WorkDir ('fx_' + $odd)
New-Item -ItemType Directory -Path $fx | Out-Null
$src = "unit EncUnit;`r`n`r`ninterface`r`n`r`nprocedure Noisy;`r`n`r`nimplementation`r`n`r`nprocedure Noisy;`r`nvar`r`n  Unused: Integer;`r`nbegin`r`n  WriteLn('hello');`r`nend;`r`n`r`nend.`r`n"
[IO.File]::WriteAllText((Join-Path $fx 'EncUnit.pas'), $src, [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'enc.sqlite'
$null = Run @('index', $fx, '--db', $db)
Check 'fixture indexed' (Test-Path $db)

$BS = [string][char]92
$esc   = $BS + 'u00e9' + $BS + 'u0434' + $BS + 'ud83d' + $BS + 'ude00'
$esc2  = $BS + $BS + 'u00e9'
$utf8  = [Text.Encoding]::UTF8.GetBytes($odd)
$utf16 = [Text.Encoding]::Unicode.GetBytes($odd)
$pathSql = 'select path from files limit 1'

$surfaces = [ordered]@{
  'lint-all --output'        = @('lint-all', '--db', $db)
  'lint-all --json --output' = @('lint-all', '--db', $db, '--json')
  'sql --output'             = @('sql', '--db', $db, '--query', $pathSql)
  'sql --json --output'      = @('sql', '--db', $db, '--query', $pathSql, '--json')
}
$i = 0
foreach ($name in $surfaces.Keys) {
  $i++
  $base = $surfaces[$name]
  Write-Host $name -ForegroundColor Cyan
  $fA = Join-Path $WorkDir "s$i-a.txt"; $fU = Join-Path $WorkDir "s$i-u.txt"; $fW = Join-Path $WorkDir "s$i-w.txt"
  $null = Run ($base + @('--output', $fA))
  $null = Run ($base + @('--output', $fU, '--output-encoding', 'utf8'))
  $null = Run ($base + @('--output', $fW, '--output-encoding', 'utf16'))
  $bA = [IO.File]::ReadAllBytes($fA); $bU = [IO.File]::ReadAllBytes($fU); $bW = [IO.File]::ReadAllBytes($fW)
  $tA = [Text.Encoding]::ASCII.GetString($bA)
  Check "$name default: 7-bit" ((HiCount $bA) -eq 0) "$(HiCount $bA) high byte(s)"
  Check "$name default: escapes the path" ($tA.Contains($esc) -or $tA.Contains($esc2)) $tA.Substring(0, [Math]::Min(300, $tA.Length))
  Check "$name utf8: raw UTF-8, no BOM" ((HasBytes $bU $utf8) -and -not (Bom $bU)) ''
  Check "$name utf16: raw UTF-16LE path" (HasBytes $bW $utf16) ''
}

Write-Host 'lint-all default report path (the current directory; here also the DB folder)' -ForegroundColor Cyan
$stamp = Get-Date -Format 'yyyyMMdd'
$rep = Join-Path $WorkDir "lint-report-$stamp.txt"
$null = Run @('lint-all', '--db', $db)
Check 'default report written' (Test-Path $rep)
$b = [IO.File]::ReadAllBytes($rep)
Check 'default report, default encoding: 7-bit' ((HiCount $b) -eq 0) "$(HiCount $b) high byte(s)"
$null = Run @('lint-all', '--db', $db, '--output-encoding', 'utf8')
$b = [IO.File]::ReadAllBytes($rep)
Check 'default report, utf8: raw UTF-8, no BOM' ((HasBytes $b $utf8) -and -not (Bom $b)) ''
$null = Run @('lint-all', '--db', $db, '--output-encoding', 'utf16')
Check 'default report, utf16: raw UTF-16LE path' (HasBytes ([IO.File]::ReadAllBytes($rep)) $utf16) ''

Write-Host 'positive control' -ForegroundColor Cyan
$fP = Join-Path $WorkDir 'plain.txt'
$null = Run @('sql', '--db', $db, '--query', "select 'plain ascii' as v", '--output', $fP, '--output-encoding', 'utf8')
Check 'a file without the path does not hold the raw bytes' (-not (HasBytes ([IO.File]::ReadAllBytes($fP)) $utf8)) ''

if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'run_output_encoding_written_files: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_output_encoding_written_files: PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "FATAL: $_" -ForegroundColor Red; exit 2 }
