<#
run_dpk_project_target.ps1 -- a .dpk is a project target wherever a .dpr/.dproj
is, and a POSITIONAL project file beats a .drag-lint.json "project" key (X-11).

Measured on 1.33.x (2026-10-25):
  * `index --project P.dpk` resolved a closure of ONE file -- the .dpk itself.
    The closure reader looked for `uses`; a package lists its units under
    `contains`, so every member unit was silently left out of the index.
  * `resolve-dbs --project P.dpk` (and `--in` a unit beside it) did not see a
    manifest section whose include is the .dpk: only .dpr/.dproj includes could
    name a project, although SectionProjectFile already accepted .dpk.
  * `index App.dpr` run under a .drag-lint.json holding "project": "Other.dpr"
    indexed Other's closure: the defaults key landed in ProjectPath and every
    `if ProjectPath <> ''` test let it beat the file typed on the command line.

Arms:
  A  index --project P.dpk --dry-run: closure lists the `contains` unit U1.pas
  A+ positive control: index --project App.dpr --dry-run lists its `uses` unit
  A- negative control: a .dpk's `requires` packages are NOT read as units
  B  resolve-dbs --project P.dpk under a section including P.dpk prints its DB
  C  resolve-dbs --in U1.pas (beside the .dpk) prints that DB
  D  index App.dpr under "project": "Other.dpr" scans App, not Other
  D+ positive control: index with NO positional still takes the config project
  E  explicit --project beats the config key too

Usage: pwsh -NoProfile -File tests\autotest\run_dpk_project_target.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-dpk-target-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) {'PASS'} else {'FAIL'}
  $color  = if ($Ok) {'Green'} else {'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red
  exit 1
}
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$Ascii = [Text.Encoding]::ASCII
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), $Ascii)
}
function Invoke-Dl([string]$Cwd, [string[]]$Arguments) {
  $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
  $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -WorkingDirectory $Cwd `
         -RedirectStandardOutput $o -RedirectStandardError $e
  [pscustomobject]@{
    Exit = $p.ExitCode
    Out  = [IO.File]::ReadAllText($o)
    Err  = [IO.File]::ReadAllText($e)
  }
}
try {
  # pkg\ : no defaults file anywhere above (TEMP); cfg\ : holds a .drag-lint.json
  New-Item -ItemType Directory -Path "$WorkDir\pkg", "$WorkDir\cfg\other", "$WorkDir\out" -Force | Out-Null
  Write-Ascii "$WorkDir\pkg\P.dpk" @'
package P;

requires
  rtl,
  ReqPkgUnit;

contains
  U1 in 'U1.pas';

end.
'@
  Write-Ascii "$WorkDir\pkg\U1.pas"         "unit U1;`ninterface`nimplementation`nend.`n"
  # a unit named like a REQUIRED package: it must never join the closure
  Write-Ascii "$WorkDir\pkg\ReqPkgUnit.pas" "unit ReqPkgUnit;`ninterface`nimplementation`nend.`n"
  Write-Ascii "$WorkDir\pkg\App.dpr"        "program App;`nuses`n  U1 in 'U1.pas';`nbegin`nend.`n"

  # --- A / A+ / A- : the closure of a package --------------------------------
  $a = Invoke-Dl "$WorkDir\pkg" @('index', '--project', "$WorkDir\pkg\P.dpk", '--db', "$WorkDir\out\a.sqlite", '--dry-run')
  Check 'A: index --project P.dpk -- closure lists the contains unit U1.pas' ($a.Out -match '(?m)^\s+.*\\U1\.pas\s*$') "exit=$($a.Exit)"
  Check 'A-: index --project P.dpk -- a requires entry is not read as a unit' ($a.Out -notmatch 'ReqPkgUnit\.pas')
  $ap = Invoke-Dl "$WorkDir\pkg" @('index', '--project', "$WorkDir\pkg\App.dpr", '--db', "$WorkDir\out\ap.sqlite", '--dry-run')
  Check 'A+: index --project App.dpr -- closure lists its uses unit U1.pas' ($ap.Out -match '(?m)^\s+.*\\U1\.pas\s*$') "exit=$($ap.Exit)"

  # --- B / C : manifest ownership of a .dpk ----------------------------------
  $esc = $WorkDir -replace '\\', '\\'
  $cfg = "$WorkDir\m.json"
  [IO.File]::WriteAllText($cfg,
    ('{"indexes":{"outDir":"' + $esc + '\\out","sections":[{"name":"Pkg","include":["' + $esc + '\\pkg\\P.dpk"]}]}}'), $Ascii)
  $b = Invoke-Dl "$WorkDir\pkg" @('resolve-dbs', '--project', "$WorkDir\pkg\P.dpk", '--config', $cfg)
  Check 'B: resolve-dbs --project P.dpk -- prints the owning DB' ($b.Exit -eq 0 -and $b.Out -match '\.sqlite') "exit=$($b.Exit) out='$($b.Out.Trim())' err='$($b.Err.Trim())'"
  $c = Invoke-Dl "$WorkDir\pkg" @('resolve-dbs', '--in', "$WorkDir\pkg\U1.pas", '--config', $cfg)
  Check 'C: resolve-dbs --in U1.pas beside P.dpk -- prints that DB' ($c.Out -match '\.sqlite') "out='$($c.Out.Trim())' err='$($c.Err.Trim())'"

  # --- D / D+ / E : positional project file vs the "project" defaults key -----
  Write-Ascii "$WorkDir\cfg\App.dpr"         "program App;`nuses`n  U1 in 'U1.pas';`nbegin`nend.`n"
  Write-Ascii "$WorkDir\cfg\U1.pas"          "unit U1;`ninterface`nimplementation`nend.`n"
  Write-Ascii "$WorkDir\cfg\other\Other.dpr" "program Other;`nuses`n  O1 in 'O1.pas';`nbegin`nend.`n"
  Write-Ascii "$WorkDir\cfg\other\O1.pas"    "unit O1;`ninterface`nimplementation`nend.`n"
  [IO.File]::WriteAllText("$WorkDir\cfg\.drag-lint.json", ('{"project":"' + $esc + '\\cfg\\other\\Other.dpr"}'), $Ascii)

  $d = Invoke-Dl "$WorkDir\cfg" @('index', "$WorkDir\cfg\App.dpr", '--db', "$WorkDir\out\d.sqlite", '--dry-run')
  Check 'D: index App.dpr under config project Other.dpr -- Other is not scanned' ($d.Out -notmatch 'Other\.dpr|O1\.pas') "out='$($d.Out.Trim() -replace '\s+',' ')'"
  Check 'D: index App.dpr under config project Other.dpr -- stderr names the override' ($d.Err -match 'positional') "err='$($d.Err.Trim())'"
  $dp = Invoke-Dl "$WorkDir\cfg" @('index', '--db', "$WorkDir\out\dp.sqlite", '--dry-run')
  Check 'D+: index with no positional -- the config project still applies' ($dp.Out -match 'Project: .*Other\.dpr') "exit=$($dp.Exit)"
  $e = Invoke-Dl "$WorkDir\cfg" @('index', '--project', "$WorkDir\cfg\App.dpr", '--db', "$WorkDir\out\e.sqlite", '--dry-run')
  Check 'E: explicit --project App.dpr beats the config key' ($e.Out -match 'Project: .*\\cfg\\App\.dpr' -and $e.Out -notmatch 'Other\.dpr') "exit=$($e.Exit)"
}
finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'run_dpk_project_target: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_dpk_project_target: PASS' -ForegroundColor Green
exit 0
