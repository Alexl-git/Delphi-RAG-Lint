<#
  run_cycles_suffix_mapping.ps1 -- N-08 + A3-b: `cycles` and the `circular-uses` lint rule agree on
  a bare uses name, and both bind it the way dcc does: an exact unit name wins, otherwise the
  FIRST unit scope of the project (.dproj DCC_Namespace, Delphi defaults when none) that makes a
  project unit of it; a name that matches neither is an external unit (no project edge).

  Fixture tests\fixtures\cyclefix\suffix: Proj.Storage.SQLite (interface uses Proj.App) and
  Proj.App (implementation uses SQLite -- the bare last segment). This runner writes a
  Suffix.dproj per case with the DCC_Namespace under test.

  (a) scope `Proj.Storage` in DCC_Namespace: lint-all reports circular-uses AND `cycles --format
      json` reports the 2-unit group proj.app + proj.storage.sqlite (positive control).
  (n) DCC_Namespace without `Proj.Storage` (A3-b, the plugin's `uses DockForm`): dcc never reads
      `SQLite` as Proj.Storage.SQLite, so NEITHER surface reports a cycle. Before A3-b the
      unique-last-segment rule bound it anyway.
  (b) a second unit Other.Lib.SQLite, DCC_Namespace `Other.Lib;Proj.Storage`: the first scope
      wins -> Other.Lib.SQLite -> no cycle on either surface.
  (o) same files, DCC_Namespace `Proj.Storage;Other.Lib`: the first scope wins ->
      Proj.Storage.SQLite -> the cycle on both surfaces (before A3-b: "ambiguous" -> nothing).
  (c) control: in (b) the extra unit really is indexed (so (b) is not vacuous).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cycles-suffix-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Invoke-Engine([string[]]$Arguments, [string]$Tag) {
  $o = Join-Path $WorkDir "$Tag.out"; $e = Join-Path $WorkDir "$Tag.err"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList $Arguments -RedirectStandardOutput $o -RedirectStandardError $e
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}

# Returns @{ Lint = <circular-uses finding count>; Groups = <cycles json groups> }
function Measure-Both([string]$Root, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $ix = Invoke-Engine @('index', ('"' + $Root + '"'), '--db', ('"' + $db + '"'), '--library-db', 'none') "$Tag-index"
  Check "$Tag indexed" ($ix.Exit -eq 0) "exit=$($ix.Exit)"
  $li = Invoke-Engine @('lint-all', '--db', ('"' + $db + '"'), '--rule', 'circular-uses', '--json') "$Tag-lint"
  $cy = Invoke-Engine @('cycles', '--db', ('"' + $db + '"'), '--library-db', 'none', '--format', 'json') "$Tag-cycles"
  $lint = @(); $groups = @()
  try { $lint = @($li.Out | ConvertFrom-Json | Where-Object { $_.rule -eq 'circular-uses' }) } catch { Check "$Tag lint json parses" $false $li.Out }
  try { $groups = @($cy.Out | ConvertFrom-Json) } catch { Check "$Tag cycles json parses" $false $cy.Out }
  $qs = Invoke-Engine @('query', '--name', 'Other.Lib.SQLite', '--db', ('"' + $db + '"')) "$Tag-q"
  return @{ Lint = $lint.Count; Groups = $groups; LintMsg = (($lint | ForEach-Object { $_.message }) -join ' | '); Query = $qs.Out }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $root = Join-Path $WorkDir 'suffix'
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\cyclefix\suffix') -File |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) -Force }

  function Set-Scopes([string]$Ns) {
    $pg = if ($Ns) { "<DCC_Namespace>$Ns</DCC_Namespace>" } else { '' }
    [IO.File]::WriteAllText((Join-Path $root 'Suffix.dproj'),
      "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`r`n" +
      "  <PropertyGroup><MainSource>Suffix.dpr</MainSource>$pg</PropertyGroup>`r`n" +
      "  <ItemGroup>`r`n    <DelphiCompile Include=`"Suffix.dpr`"><MainSource>MainSource</MainSource></DelphiCompile>`r`n" +
      "    <DCCReference Include=`"Proj.App.pas`"/>`r`n    <DCCReference Include=`"Proj.Storage.SQLite.pas`"/>`r`n" +
      "  </ItemGroup>`r`n</Project>`r`n")
  }
  function Test-Cycle($M) {
    return @($M.Groups | Where-Object { $u = @($_.units | ForEach-Object { "$_".ToLower() }); ($u -contains 'proj.app') -and ($u -contains 'proj.storage.sqlite') }).Count -eq 1
  }

  Write-Host '== (a) scope Proj.Storage in DCC_Namespace' -ForegroundColor Cyan
  Set-Scopes 'Proj.Storage;System;Vcl'
  $a = Measure-Both $root 'a'
  Check 'a1 control: lint-all reports circular-uses' ($a.Lint -ge 1) $a.LintMsg
  Check 'a2 cycles reports the group proj.app + proj.storage.sqlite' (Test-Cycle $a) ("groups=" + ($a.Groups | ConvertTo-Json -Compress -Depth 4))

  Write-Host '== (n) DCC_Namespace without Proj.Storage' -ForegroundColor Cyan
  Set-Scopes 'System;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;$(DCC_Namespace)'
  $n = Measure-Both $root 'n'
  Check 'n1 lint-all reports no circular-uses' ($n.Lint -eq 0) $n.LintMsg
  Check 'n2 cycles reports no group' ($n.Groups.Count -eq 0) ("groups=" + ($n.Groups | ConvertTo-Json -Compress -Depth 4))

  Write-Host '== (b) Other.Lib.SQLite, DCC_Namespace Other.Lib first' -ForegroundColor Cyan
  [IO.File]::WriteAllText((Join-Path $root 'Other.Lib.SQLite.pas'),
    "unit Other.Lib.SQLite;`r`n`r`ninterface`r`n`r`nfunction OtherName: string;`r`n`r`nimplementation`r`n`r`nfunction OtherName: string;`r`nbegin`r`n  Result := 'other';`r`nend;`r`n`r`nend.`r`n")
  Set-Scopes 'Other.Lib;Proj.Storage;System'
  $b = Measure-Both $root 'b'
  Check 'c1 control: Other.Lib.SQLite is indexed' ($b.Query -match 'Other\.Lib\.SQLite') ''
  Check 'b1 lint-all reports no circular-uses' ($b.Lint -eq 0) $b.LintMsg
  Check 'b2 cycles reports no group' ($b.Groups.Count -eq 0) ("groups=" + ($b.Groups | ConvertTo-Json -Compress -Depth 4))

  Write-Host '== (o) same files, DCC_Namespace Proj.Storage first' -ForegroundColor Cyan
  Set-Scopes 'Proj.Storage;Other.Lib;System'
  $o = Measure-Both $root 'o'
  Check 'o1 lint-all reports circular-uses' ($o.Lint -ge 1) $o.LintMsg
  Check 'o2 cycles reports the group proj.app + proj.storage.sqlite' (Test-Cycle $o) ("groups=" + ($o.Groups | ConvertTo-Json -Compress -Depth 4))} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
