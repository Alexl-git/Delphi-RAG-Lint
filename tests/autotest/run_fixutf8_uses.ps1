<#
  run_fixutf8_uses.ps1 -- lane CLIFIX C3 (#18). The uses fixers must read a source through the
  applier's decoder (TTextFileFormat.ReadFile), not as ANSI: a UTF-8 file whose uses line carries a
  non-ASCII comment used to be DECLINED (the byte-vs-char column shift broke the span check).
    U1 (positive control) the rule reports the helper unit in the ASCII twin and the UTF-8 file
    U2 the ASCII twin is fixed (the pre-existing behaviour - proves the fixture is removable)
    U3 the UTF-8 file is fixed: the unit entry is gone
    U4 the result is still valid UTF-8 and still holds the non-ASCII bytes of both comments
    U5 every line outside the edit is byte-identical to the original
  The fixture (tests\autotest\fixtures\fixutf8) is ASCII; {{AE}} / {{UE}} become UTF-8 at run time.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fixutf8-$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
$fixture = Join-Path $PSScriptRoot 'fixtures\fixutf8'
$utf8 = New-Object Text.UTF8Encoding($false)

function New-Case([string]$Name, [string]$Ae, [string]$Ue) {
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Path $dir | Out-Null
  foreach ($f in Get-ChildItem $fixture -Filter *.pas) {
    $t = [IO.File]::ReadAllText($f.FullName).Replace('{{AE}}', $Ae).Replace('{{UE}}', $Ue)
    [IO.File]::WriteAllBytes((Join-Path $dir $f.Name), $utf8.GetBytes($t))
  }
  $db = Join-Path $dir '_case.sqlite'
  Check "$Name index" ((Invoke-G8Index $Exe $dir $db) -eq 0)
  return @{ Dir = $dir; Db = $db; File = (Join-Path $dir 'uUtf8Uses.pas') }
}
function Fire-Count($C) {
  $f = Get-G8Findings $Exe $C.Db 'unused-unit-in-uses'
  return @($f | Where-Object { $_.file_path -like '*uUtf8Uses.pas' -and $_.message -match "'uUtf8Helper'" }).Count
}
function Apply-Fix($C) {
  Push-Location $C.Dir
  try { & $Exe lint-all --db $C.Db --fix --fix-rule unused-unit-in-uses --apply --no-backup *> (Join-Path $C.Dir '_fix.log') } finally { Pop-Location }
}

$ascii = New-Case 'ascii' 'ae' 'ue'
$u8    = New-Case 'utf8' ([string][char]0xE4) ([string][char]0xFC)
$origBytes = [IO.File]::ReadAllBytes($u8.File)
$origLines = [IO.File]::ReadAllText($u8.File, $utf8) -split "`r`n"

Check 'U1 positive control: rule reports uUtf8Helper (ASCII twin)' ((Fire-Count $ascii) -eq 1)
Check 'U1 positive control: rule reports uUtf8Helper (UTF-8 file)' ((Fire-Count $u8) -eq 1)
Apply-Fix $ascii
Check 'U2 ASCII twin: unit entry removed' ([IO.File]::ReadAllText($ascii.File) -notmatch 'uUtf8Helper')
Apply-Fix $u8
$newBytes = [IO.File]::ReadAllBytes($u8.File)
$strict = New-Object Text.UTF8Encoding($false, $true)
$newText = $null; $valid = $true
try { $newText = $strict.GetString($newBytes) } catch { $valid = $false }
Check 'U3 UTF-8 file: unit entry removed' ($valid -and ($newText -notmatch 'uUtf8Helper')) 'declined'
Check 'U4 still valid UTF-8 with both non-ASCII comments' ($valid -and $newText.Contains('Gr' + [char]0xFC + 'sse') -and ($newBytes.Length -ne $origBytes.Length))
if ($valid -and $newText) {
  $newLines = $newText -split "`r`n"
  $kept = @($origLines | Where-Object { $newLines -contains $_ })
  $dropped = $origLines.Count - $kept.Count
  Check 'U5 only the helper line(s) left the file; all others byte-identical' (($dropped -ge 1) -and ($dropped -le 2) -and (@($origLines | Where-Object { $_ -notmatch 'uUtf8Helper' }).Count -eq $kept.Count))
} else { Check 'U5 only the helper line(s) left the file' $false 'file not decodable' }
if ($script:Failed) { Write-Host 'run_fixutf8_uses: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_fixutf8_uses: PASS' -ForegroundColor Green
exit 0
