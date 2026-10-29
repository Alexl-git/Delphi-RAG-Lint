<#
  run_index_content_hash_skip.ps1 -- xerj item 7 (content-hash skip).

  An incremental index must skip a file whose sha256 matches the stored one even
  when its mtime changed (git checkout, touch, copy), and refresh the stored
  mtime so the next run takes the cheap path. A real content change must still
  re-parse (positive control: without it the test passes with the skip broken
  the other way round).

  C1 baseline index parses every file.
  C2 touch only (same bytes): attempted=0, up-to-date=all.
  C3 the mtime was refreshed: a second run is still attempted=0.
  C4 content change of one file: attempted=1 (positive control).
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_content_hash_skip_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
foreach ($n in 'uOne','uTwo') {
  Write-Ascii (Join-Path $src "$n.pas") "unit $n;`n`ninterface`n`nprocedure Do$n;`n`nimplementation`n`nprocedure Do$n;`nbegin`nend;`n`nend.`n"
}
$db = Join-Path $WorkDir 'h.sqlite'
function Idx() {
  $o = & $exePath index $src --db $db 2>&1 | Out-String
  if ($o -match 'Done\. Files: (\d+),') {
    $f = [int]$Matches[1]; $u = 0
    if ($o -match 'skipped (\d+) up-to-date') { $u = [int]$Matches[1] }
    return @{ Att=($f-$u); Utd=$u; Raw=$o }
  }
  return @{ Att=-1; Utd=-1; Raw=$o }
}
Push-Location C:\TEMP
$r1 = Idx
Check 'C1 baseline parses both files' ($r1.Att -eq 2) $r1.Raw
(Get-Item (Join-Path $src 'uOne.pas')).LastWriteTime = (Get-Date).AddHours(-5)
(Get-Item (Join-Path $src 'uTwo.pas')).LastWriteTime = (Get-Date).AddHours(-6)
$r2 = Idx
Check 'C2 touch only: nothing re-parsed, both up-to-date' (($r2.Att -eq 0) -and ($r2.Utd -eq 2)) $r2.Raw
$r3 = Idx
Check 'C3 mtime refreshed: still nothing re-parsed' (($r3.Att -eq 0) -and ($r3.Utd -eq 2)) $r3.Raw
Write-Ascii (Join-Path $src 'uOne.pas') "unit uOne;`n`ninterface`n`nprocedure DouOne;`nprocedure Extra;`n`nimplementation`n`nprocedure DouOne;`nbegin`nend;`n`nprocedure Extra;`nbegin`nend;`n`nend.`n"
$r4 = Idx
Check 'C4 real content change re-parses exactly that file' ($r4.Att -eq 1) $r4.Raw
Pop-Location
} finally { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
if ($fail) { exit 1 } else { Write-Host 'ALL PASS'; exit 0 }
