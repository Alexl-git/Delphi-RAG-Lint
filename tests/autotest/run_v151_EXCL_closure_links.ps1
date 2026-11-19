<#
  run_v151_EXCL_closure_links.ps1 -- lane v151 EXCL (owner rulings OQ4 + OQ13).

  OQ4: a project's members are the units its project files list PLUS every
  non-library unit reached through `uses`. Folder location counts for platform
  libraries only, so `index --project --exclude-under <dir>` must NOT drop a
  compile-closure unit under <dir>; it keeps it and says so. Closure units the
  project files do not list are reported at index time for adding.

  OQ13: a unit nobody reaches through `uses` is not in the project, but one
  reached by another link IS, and is reported as a missing uses entry plus a
  missing project entry:
    * a .dfm of a closure unit streams a class declared only in that unit;
    * a closure unit names the unit explicitly (`UGlob.GlobalCounter`, here in
      an inactive conditional branch) or looks a class of it up by name
      (`GetClass('TPlugin')`).

  Fixture: tests\autotest\fixtures\v151-EXCL\links (copied to a temp folder).
  CASES
    E1  index exit 0; ExtU.pas (closure unit under the --exclude-under root) IS indexed
    E2  index prints a note naming the kept unit under the excluded root
    E3  index reports the unlisted closure units UHelper and ExtU
    L1  lint-all unit-not-in-dpr: UPane reported via UFormA.dfm (class TPaneBox)
    L2  ... UPlugin reported via the by-name class lookup in UMain
    L3  ... UGlob reported via the explicit qualified use in UMain
    N1  UOrphan (no link; its name only inside a string literal) is NOT reported
    N2  Cfg (a local variable shares the unit name) is NOT reported
    P1  positive control: --disable unit-not-in-dpr -> none of L1-L3 fire

  pwsh -File tests\autotest\run_v151_EXCL_closure_links.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$Fixture = Join-Path $PSScriptRoot 'fixtures\v151-EXCL\links'
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v151-excl-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
Copy-Item -Path (Join-Path $Fixture '*') -Destination $Work -Recurse
$Dproj = Join-Path $Work 'App.dproj'
$Db = Join-Path $Work 'app.sqlite'

function LinkFindings([string[]]$extra) {
  $raw = (& $Exe lint-all --db $Db --project $Dproj --rule unit-not-in-dpr --json @extra 2>$null) -join "`n"
  Write-Host ('  raw[0..200]: ' + $raw.Substring(0, [Math]::Min(200, $raw.Length)))
  $arr = @()
  try { $arr = @($raw | ConvertFrom-Json) } catch { }
  return ,$arr
}

try {
  $idxOut = (& $Exe index --project $Dproj --db $Db --exclude-under (Join-Path $Work 'ext') 2>&1) -join "`n"
  $code = $LASTEXITCODE
  $raw = (& $Exe sql --db $Db --query 'SELECT path FROM files' --json 2>$null) -join "`n"
  $paths = @()
  try { $paths = @(($raw | ConvertFrom-Json).rows | ForEach-Object { $_[0] }) } catch { }
  Check 'E1 index exit 0 and ExtU.pas kept in the project index' ($code -eq 0 -and @($paths | Where-Object { $_ -match '\\ext\\ExtU\.pas$' }).Count -eq 1) ("exit=$code files=" + ($paths -join ', '))
  Check 'E2 index notes the closure unit kept under the excluded root' ($idxOut -match '(?s)exclude-under.*ExtU\.pas') ''
  Check 'E3 index reports the unlisted closure units UHelper and ExtU' (($idxOut -match 'unit-not-in-dpr.*"UHelper"') -and ($idxOut -match 'unit-not-in-dpr.*"ExtU"')) ''

  $f = LinkFindings @()
  $msgs = @($f | ForEach-Object { '' + $_.message })
  $msgs | ForEach-Object { Write-Host "    $_" }
  Check 'L1 UPane reported via UFormA.dfm (TPaneBox)' (@($msgs | Where-Object { $_ -match '"UPane"' -and $_ -match 'TPaneBox' }).Count -eq 1)
  Check 'L1b the dfm link is anchored on UFormA.dfm line 7' (@($f | Where-Object { ('' + $_.message) -match '"UPane"' -and ('' + $_.file_path) -match 'UFormA\.dfm$' -and $_.start_line -eq 7 }).Count -eq 1) (($f | Where-Object { ('' + $_.message) -match '"UPane"' } | ForEach-Object { "$($_.file_path):$($_.start_line)" }) -join ', ')
  Check 'L2 UPlugin reported via the by-name class lookup' (@($msgs | Where-Object { $_ -match '"UPlugin"' -and $_ -match 'TPlugin' }).Count -eq 1)
  Check 'L3 UGlob reported via the explicit qualified use' (@($msgs | Where-Object { $_ -match '"UGlob"' -and $_ -match 'GlobalCounter' }).Count -eq 1)
  Check 'N1 UOrphan (no link; named only inside a string literal) not reported' (@($msgs | Where-Object { $_ -match 'UOrphan' }).Count -eq 0)
  Check 'N2 Cfg (local variable of that name) not reported' (@($msgs | Where-Object { $_ -match '"Cfg"' }).Count -eq 0)

  $off = LinkFindings @('--disable', 'unit-not-in-dpr')
  Check 'P1 positive control: rule disabled -> no link findings' (@($off | Where-Object { ('' + $_.message) -match 'UPane|UPlugin|UGlob' }).Count -eq 0) ("n=$($off.Count)")
} finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
