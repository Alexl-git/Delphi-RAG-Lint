<#
  run_index_exclude_under_slash_forms.ps1 -- `index --project --exclude-under <dir>`
  recognises a compile-closure unit under <dir> whatever slash form or relative form
  the root is written in (wave 152b R16, lane CLI; W144 REPORT row R16).

  v151 EXCL (owner ruling OQ4): the unit is no longer DROPPED -- a project member is
  every non-library unit reached through uses, folder location counts for platform
  libraries only. The run keeps it and names it in a NOTE; the slash / relative
  normalisation below now decides what that NOTE lists. Cases S2-S4 were "not
  indexed" before 1.51.

  THE DEFECT
  ----------
  W144 reproduced "the flag prunes walks only; ext\ExtU.pas is still indexed"
  with `--exclude-under C:/.../excl/ext`. The cause is the FORWARD slashes:
  DropUnderExcludeRoots (E-UNWITH-EXCLUDE) compared the raw root against the
  closure's backslashed paths, so `C:/x/ext\` never prefixed `c:\x\ext\u.pas`.
  The backslash form already worked on 1.50.0-alpha.

  CASES (fixture: Ex.dproj with DCC_UnitSearchPath=ext, `uses ExtU`)
    S1  no flag                         -> ExtU.pas indexed            (control: the unit IS in the closure)
    S2  --exclude-under C:\..\ext       -> ExtU.pas indexed, named in the NOTE
    S3  --exclude-under C:/../ext       -> ExtU.pas indexed, named in the NOTE
    S4  --exclude-under ext (relative, cwd = fixture) -> indexed, named in the NOTE
    S5  --exclude-under C:/../other     -> ExtU.pas indexed, no NOTE (control: a non-matching root names nothing)

  Run from any CWD, pwsh 7:
    pwsh -File tests\autotest\run_index_exclude_under_slash_forms.ps1 -Exe <drag-lint.exe>
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

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-excl-under-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $Work 'ext')) | Out-Null
$dproj = @(
  '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
  '  <PropertyGroup><MainSource>Ex.dpr</MainSource><Config Condition="''$(Config)''==''''">Debug</Config><Base>true</Base></PropertyGroup>',
  '  <PropertyGroup Condition="''$(Base)''!=''''"><DCC_UnitSearchPath>ext;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>',
  '  <ItemGroup><DelphiCompile Include="Ex.dpr"><MainSource>MainSource</MainSource></DelphiCompile></ItemGroup>',
  '</Project>'
)
[IO.File]::WriteAllText((Join-Path $Work 'Ex.dproj'), (($dproj -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $Work 'Ex.dpr'), "program Ex;`r`nuses ExtU;`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $Work 'ext\ExtU.pas'), "unit ExtU;`r`n`r`ninterface`r`n`r`nprocedure P;`r`n`r`nimplementation`r`n`r`nprocedure P;`r`nbegin`r`nend;`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)

function IndexedExtU([string]$tag, [string[]]$extra) {
  $db = Join-Path $Work "$tag.sqlite"
  $out = (& $Exe index --project (Join-Path $Work 'Ex.dproj') --db $db @extra 2>&1) -join "`n"
  $code = $LASTEXITCODE
  $raw = (& $Exe sql --db $db --query 'SELECT path FROM files' --json 2>$null) -join "`n"
  $paths = @()
  try { $paths = @(($raw | ConvertFrom-Json).rows | ForEach-Object { $_[0] }) } catch { }
  [pscustomobject]@{ Exit = $code; Paths = $paths; ExtU = (@($paths | Where-Object { $_ -match '\\ext\\ExtU\.pas$' }).Count -gt 0)
                     Noted = ($out -match '(?s)NOTE: --exclude-under.*\\ext\\ExtU\.pas') }
}

Push-Location $Work
try {
  $ext   = Join-Path $Work 'ext'
  $s1 = IndexedExtU 's1' @()
  Check 'S1 control: index exit 0 and the DB has rows (non-empty answer)' ($s1.Exit -eq 0 -and $s1.Paths.Count -gt 0) "exit=$($s1.Exit) files=$($s1.Paths.Count)"
  Check 'S1 control: without the flag ExtU.pas is indexed and no NOTE' ($s1.ExtU -and -not $s1.Noted) ($s1.Paths -join ', ')
  $s2 = IndexedExtU 's2' @('--exclude-under', $ext)
  Check 'S2 backslash root: ExtU.pas kept (OQ4) and named in the NOTE' ($s2.ExtU -and $s2.Noted) ($s2.Paths -join ', ')
  $s3 = IndexedExtU 's3' @('--exclude-under', $ext.Replace('\', '/'))
  Check 'S3 forward-slash root: ExtU.pas kept and named in the NOTE' ($s3.ExtU -and $s3.Noted) ($s3.Paths -join ', ')
  $s4 = IndexedExtU 's4' @('--exclude-under', 'ext')
  Check 'S4 relative root (cwd = fixture): ExtU.pas kept and named in the NOTE' ($s4.ExtU -and $s4.Noted) ($s4.Paths -join ', ')
  $s5 = IndexedExtU 's5' @('--exclude-under', (Join-Path $Work 'other').Replace('\', '/'))
  Check 'S5 control: a non-matching root names nothing' ($s5.ExtU -and -not $s5.Noted) ($s5.Paths -join ', ')
} finally {
  Pop-Location
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
