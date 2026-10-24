<#
  run_include_sites.ps1 -- N-06 T1: Preprocess reports its include SITES.

  The 3-arg Preprocess(AUtf8, AOptions, out ASites) overload records every
  active, resolved {$I} it met, with the child output bytes the recursion
  produced. Observed through preprocess-file --include-sites (one TSV line per
  site: site, depth, line, col, byte count, MD5 of the resolved bytes, path).

  Checks:
    1. host.pas -> exactly ONE site: live.inc at line 7 col 3, depth 0.
    2. the inactive-branch {$I dead.inc} -> no site.
    3. site bytes = the child output: byte count and MD5 equal
       preprocess-file --include-mode defines-only over live.inc itself, and
       with --define HOST_FLAG the MD5 changes (the host's live defines reach
       the child) -- POSITIVE CONTROL that the digest is not a constant.
    4. without --include-sites the output is byte-identical to the plain
       defines-only run (the non-site overloads are unchanged).
    5. --include-mode off -> no site (nothing is resolved).
  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\include_sites')).Path
$host_   = Join-Path $fixDir 'host.pas'
$live    = Join-Path $fixDir 'live.inc'

function Q([string]$s) { return '"' + $s + '"' }
function Run-Bytes([string[]]$verbArgs) {
  $tmp = [System.IO.Path]::GetTempFileName()
  $line = ((@((Q $exePath), 'preprocess-file') + $verbArgs) -join ' ') + ' > ' + (Q $tmp) + ' 2>NUL'
  $null = Start-Process cmd.exe -ArgumentList '/c', ('"' + $line + '"') -NoNewWindow -Wait -PassThru
  $b = [System.IO.File]::ReadAllBytes($tmp)
  [System.IO.File]::Delete($tmp)
  return ,$b
}
function Md5Hex($bytes) {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  return (($md5.ComputeHash([byte[]]$bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Sites([string[]]$extra) {
  $b = Run-Bytes (@('--file', (Q $host_), '--include-mode', 'defines-only', '--include-sites') + $extra)
  $txt = [System.Text.Encoding]::ASCII.GetString($b)
  return ,@($txt -split "`r?`n" | Where-Object { $_ -like "site`t*" })
}
function BytesEqual($a, $b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($k = 0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { return $false } }
  return $true
}

Push-Location C:\TEMP
try {
  $s = Sites @()
  Check "one site reported (got $($s.Count))" ($s.Count -eq 1)
  $f = if ($s.Count -ge 1) { $s[0] -split "`t" } else { @('','','','','','','') }
  Check "site depth 0, line 7, col 3 (got $($f[1]),$($f[2]),$($f[3]))" (($f[1] -eq '0') -and ($f[2] -eq '7') -and ($f[3] -eq '3'))
  Check "site path is live.inc (got '$($f[6])')" ($f[6] -eq $live)
  Check 'inactive-branch dead.inc gives no site' (-not ($s -match 'dead\.inc'))

  $child = Run-Bytes @('--file', (Q $live), '--include-mode', 'defines-only')
  Check "site byte count = child output ($($f[4]) vs $($child.Length))" ($f[4] -eq [string]$child.Length)
  Check 'site MD5 = MD5 of the child output' ($f[5] -eq (Md5Hex $child))

  $sFlag = Sites @('--define', 'HOST_FLAG')
  $fFlag = if ($sFlag.Count -ge 1) { $sFlag[0] -split "`t" } else { @('','','','','','','') }
  $childFlag = Run-Bytes @('--file', (Q $live), '--include-mode', 'defines-only', '--define', 'HOST_FLAG')
  Check 'positive control: HOST_FLAG changes the site MD5' (($fFlag[5] -ne '') -and ($fFlag[5] -ne $f[5]))
  Check 'with HOST_FLAG the site MD5 = that child output' ($fFlag[5] -eq (Md5Hex $childFlag))

  $plain = Run-Bytes @('--file', (Q $host_), '--include-mode', 'defines-only')
  $orig  = [System.IO.File]::ReadAllBytes($host_)
  Check 'plain run keeps offset identity' ($plain.Length -eq $orig.Length)
  Check 'plain run has no site lines' (-not ([System.Text.Encoding]::ASCII.GetString($plain) -match "(?m)^site`t"))

  $off = Run-Bytes @('--file', (Q $host_), '--include-mode', 'off', '--include-sites')
  Check '--include-mode off reports no site' (-not ([System.Text.Encoding]::ASCII.GetString($off) -match "(?m)^site`t"))
} finally { Pop-Location }

if ($fail) { Write-Host 'run_include_sites: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_include_sites: PASS' -ForegroundColor Green; exit 0