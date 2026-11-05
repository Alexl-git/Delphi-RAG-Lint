<#
  run_closure_project_bindings.ps1 -- GH #13: the compile closure gives the
  project's own unit bindings precedence over any path search.

  dcc never path-searches a unit the project lists. The walk did: B.pas `uses Lib`,
  the search found Other\Lib.pas and added it beside the Shared\Lib.pas the .dpr
  names, so one unit had two files in the index.

  A binding is unit name -> file. .dpr `uses X in 'path'` entries bind first, as
  dcc reads them, DCCReference entries after them; the first binding of a name
  wins, and a different second one is a WARN line. A binding whose file is missing
  is not a binding: the next listing, then the path search, still answers.

  Second defect, same output: a rooted `in` path holding `..` joined the closure
  unnormalised, so the printed count held a second spelling of a listed file.

  Everything is driven through `index --project --dry-run` with a --db and a
  --library-db in this guard's own temp folder; a dry run writes neither. Group 9
  (an unlisted unit still resolves through the path) is the positive control: it
  fails if the walk stops searching, or if the listing parser below stops matching.
#>
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Continue'
$Exe = (Resolve-Path $Exe).Path
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) ("dl-closbind-" + [Guid]::NewGuid().ToString('N')) }
[void][IO.Directory]::CreateDirectory($Scratch)
$OwnCwd = Get-Location
Set-Location $Scratch
$script:fail = 0
$script:pass = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name" }
  else { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function WriteText([string]$Path, [string]$Text) {
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function WriteUnit([string]$Path, [string]$Name, [string]$UsesList = '') {
  $u = if ($UsesList) { "uses $UsesList;`n" } else { '' }
  WriteText $Path "unit $Name;`ninterface`n$($u)implementation`nend.`n"
}
function WriteDproj([string]$Dir, [string]$Search, [string[]]$Refs) {
  $sp = if ($Search) { "<PropertyGroup><DCC_UnitSearchPath>$Search</DCC_UnitSearchPath></PropertyGroup>" } else { '' }
  $items = ($Refs | ForEach-Object { "<DCCReference Include=`"$_`"/>" }) -join ''
  WriteText "$Dir\P.dproj" "<Project><PropertyGroup><MainSource>P.dpr</MainSource><ProjectVersion>20.1</ProjectVersion></PropertyGroup>$sp<ItemGroup><DelphiCompile Include=`"P.dpr`"/>$items</ItemGroup></Project>`n"
}
# The closure as printed: the 2-space-indented lines after "Compile closure: N file(s):".
function Closure([string]$Dir, [string]$File = 'P.dproj') {
  $db = Join-Path $Scratch ("dry-" + [Guid]::NewGuid().ToString('N') + '.sqlite')
  $raw = & $Exe index --project "$Dir\$File" --db $db --library-db "$Scratch\no-library.sqlite" --dry-run 2>&1 | Out-String
  $lines = @($raw -split "`r?`n")
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^Compile closure: (\d+) file') { $start = $i; break } }
  $files = @()
  $count = -1
  if ($start -ge 0) {
    $count = [int]([regex]::Match($lines[$start], '\d+').Value)
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -notmatch '^  \S') { break }
      $files += $lines[$i].Trim()
    }
  }
  return [pscustomobject]@{ Raw = $raw; Count = $count; Files = $files; DbWritten = (Test-Path $db) }
}
function Has($C, [string]$Path) { return @($C.Files | Where-Object { $_ -ieq $Path }).Count -gt 0 }
function LeafCount($C, [string]$Leaf) { return @($C.Files | Where-Object { [IO.Path]::GetFileName($_) -ieq $Leaf }).Count }

# --- group 1: the issue's repro, with Other on the search path ---------------
Write-Host '[1] GH #13 repro: the .dpr names Shared\Lib.pas, Other is on the search path'
$d = Join-Path $Scratch 'g1'
WriteText "$d\P.dpr" "program P;`nuses`n  A in 'A.pas',`n  Lib in 'Shared\Lib.pas',`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\A.pas" 'A'
WriteUnit "$d\Shared\Lib.pas" 'Lib'
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'Lib'
WriteDproj $d 'Other' @('A.pas', 'Shared\Lib.pas', 'Other\B.pas')
$c = Closure $d
Check 'the listing parser found files (raw shape)' ($c.Files.Count -ge 4) $c.Raw
Check 'Shared\Lib.pas is listed' (Has $c "$d\Shared\Lib.pas") ($c.Files -join ' | ')
Check 'Other\Lib.pas is NOT listed' (-not (Has $c "$d\Other\Lib.pas")) ($c.Files -join ' | ')
Check 'the unit has one file' ((LeafCount $c 'Lib.pas') -eq 1) ($c.Files -join ' | ')
Check 'a dry run wrote no DB' (-not $c.DbWritten)

# --- group 2: without the search path: the unit-directory fallback found it ---
Write-Host '[2] the same without DCC_UnitSearchPath (the unit''s own folder held the shadow)'
$d = Join-Path $Scratch 'g2'
WriteText "$d\P.dpr" "program P;`nuses`n  Lib in 'Shared\Lib.pas',`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Shared\Lib.pas" 'Lib'
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'Lib'
WriteDproj $d '' @('Shared\Lib.pas', 'Other\B.pas')
$c = Closure $d
Check 'Shared\Lib.pas is listed' (Has $c "$d\Shared\Lib.pas") ($c.Files -join ' | ')
Check 'Other\Lib.pas is NOT listed' (-not (Has $c "$d\Other\Lib.pas")) ($c.Files -join ' | ')

# --- group 3: names match case-insensitively ----------------------------------
Write-Host '[3] a binding matches the name in any case'
$d = Join-Path $Scratch 'g3'
WriteText "$d\P.dpr" "program P;`nuses`n  lib in 'Shared\Lib.pas',`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Shared\Lib.pas" 'Lib'
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'LIB'
WriteDproj $d 'Other' @()
$c = Closure $d
Check 'only Shared\Lib.pas' ((Has $c "$d\Shared\Lib.pas") -and (LeafCount $c 'Lib.pas') -eq 1) ($c.Files -join ' | ')

# --- group 4: dotted names ------------------------------------------------------
Write-Host '[4] a dotted unit name binds whole'
$d = Join-Path $Scratch 'g4'
WriteText "$d\P.dpr" "program P;`nuses`n  My.Lib in 'Shared\My.Lib.pas',`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Shared\My.Lib.pas" 'My.Lib'
WriteUnit "$d\Other\My.Lib.pas" 'My.Lib'
WriteUnit "$d\Other\B.pas" 'B' 'My.Lib'
WriteDproj $d 'Other' @()
$c = Closure $d
Check 'only Shared\My.Lib.pas' ((Has $c "$d\Shared\My.Lib.pas") -and (LeafCount $c 'My.Lib.pas') -eq 1) ($c.Files -join ' | ')

# --- group 5: an absolute DCCReference, dpr silent about the unit ---------------
Write-Host '[5] an absolute DCCReference binds, with no `in` in the .dpr'
$d = Join-Path $Scratch 'g5'
WriteText "$d\P.dpr" "program P;`nuses`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Elsewhere\Lib.pas" 'Lib'
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'Lib'
WriteDproj $d 'Other' @("$d\Elsewhere\Lib.pas", 'Other\B.pas')
$c = Closure $d
Check 'only Elsewhere\Lib.pas' ((Has $c "$d\Elsewhere\Lib.pas") -and (LeafCount $c 'Lib.pas') -eq 1) ($c.Files -join ' | ')

# --- group 6: a conflicting `in` beats DCCReference, as dcc does, and says so -----
Write-Host '[6] DCCReference and `in` disagree: the .dpr wins, one WARN names both'
$d = Join-Path $Scratch 'g6'
$pd = "$d\App"
WriteText "$pd\P.dpr" "program P;`nuses`n  A in 'A.pas',`n  Y in '..\Shared\Y.pas';`nbegin`nend.`n"
WriteUnit "$pd\A.pas" 'A' 'Y'
WriteUnit "$d\Shared\Y.pas" 'Y'
WriteUnit "$d\Dup\Y.pas" 'Y'
WriteDproj $pd '' @('A.pas', '..\Dup\Y.pas')
$c = Closure $pd
Check '.dproj entry: Shared\Y.pas is listed' (Has $c "$d\Shared\Y.pas") ($c.Files -join ' | ')
Check '.dproj entry: Dup\Y.pas is NOT listed' (-not (Has $c "$d\Dup\Y.pas")) ($c.Files -join ' | ')
Check 'one WARN line: the .dpr file wins, the DCCReference file is left out' ((@($c.Raw -split "`r?`n" | Where-Object { $_ -match 'WARN: unit Y is listed twice: \S*\\Shared\\Y\.pas wins, \S*\\Dup\\Y\.pas is left out' })).Count -eq 1) $c.Raw
$c = Closure $pd 'P.dpr'
Check '.dpr entry: Shared\Y.pas is listed' (Has $c "$d\Shared\Y.pas") ($c.Files -join ' | ')
Check '.dpr entry: Dup\Y.pas is NOT listed' (-not (Has $c "$d\Dup\Y.pas")) ($c.Files -join ' | ')

# --- group 7: `in` paths are relative to the .dpr -------------------------------
Write-Host '[7] an `in` path is relative to the .dpr, wherever the using unit sits'
$d = Join-Path $Scratch 'g7'
$pd = "$d\App\Proj"
WriteText "$pd\P.dpr" "program P;`nuses`n  Lib in '..\Shared\Lib.pas',`n  B in '..\Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\App\Shared\Lib.pas" 'Lib'
WriteUnit "$d\App\Other\Lib.pas" 'Lib'
WriteUnit "$d\App\Other\B.pas" 'B' 'Lib'
WriteDproj $pd '..\Other' @()
$c = Closure $pd
Check 'only App\Shared\Lib.pas' ((Has $c "$d\App\Shared\Lib.pas") -and (LeafCount $c 'Lib.pas') -eq 1) ($c.Files -join ' | ')

# --- group 8: a listed file that is missing ------------------------------------
Write-Host '[8] a binding whose file is missing does not bind: the search still answers'
$d = Join-Path $Scratch 'g8'
WriteText "$d\P.dpr" "program P;`nuses`n  Lib in 'Gone\Lib.pas',`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'Lib'
WriteDproj $d 'Other' @('Gone\Lib.pas', 'Other\B.pas')
$c = Closure $d
Check 'Other\Lib.pas answers for the missing listing' (Has $c "$d\Other\Lib.pas") ($c.Files -join ' | ')
Check 'the missing file is not listed' (-not (Has $c "$d\Gone\Lib.pas")) ($c.Files -join ' | ')
$d = Join-Path $Scratch 'g8b'
WriteText "$d\P.dpr" "program P;`nuses`n  Lib in 'Gone\Lib.pas',`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Listed\Lib.pas" 'Lib'
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'Lib'
WriteDproj $d 'Other' @('Listed\Lib.pas', 'Other\B.pas')
$c = Closure $d
Check 'the .dpr''s `in` file missing: the DCCReference binds' ((Has $c "$d\Listed\Lib.pas") -and (LeafCount $c 'Lib.pas') -eq 1) ($c.Files -join ' | ')

# --- group 9: positive control ---------------------------------------------------
Write-Host '[9] positive control: a unit the project does not list still resolves through the path'
$d = Join-Path $Scratch 'g9'
WriteText "$d\P.dpr" "program P;`nuses`n  Lib in 'Shared\Lib.pas',`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Shared\Lib.pas" 'Lib'
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'Lib, Helper'
WriteUnit "$d\Paths\Helper.pas" 'Helper' 'Deep'
WriteUnit "$d\Paths\Deep.pas" 'Deep'
WriteDproj $d 'Other;Paths' @()
$c = Closure $d
Check 'Paths\Helper.pas came through the path' (Has $c "$d\Paths\Helper.pas") ($c.Files -join ' | ')
Check 'its own use Paths\Deep.pas too' (Has $c "$d\Paths\Deep.pas") ($c.Files -join ' | ')
Check 'and the listed unit still has one file' ((LeafCount $c 'Lib.pas') -eq 1) ($c.Files -join ' | ')

# --- group 10: the .dpr arm binds but never seeds --------------------------------
Write-Host '[10] resolving the .dpr: DCCReference binds a USED unit, never seeds an unused one'
$d = Join-Path $Scratch 'g10'
WriteText "$d\P.dpr" "program P;`nuses`n  B in 'Other\B.pas';`nbegin`nend.`n"
WriteUnit "$d\Listed\Lib.pas" 'Lib'
WriteUnit "$d\Other\Lib.pas" 'Lib'
WriteUnit "$d\Other\B.pas" 'B' 'Lib'
WriteUnit "$d\Listed\NeverUsed.pas" 'NeverUsed'
WriteDproj $d 'Other' @('Listed\Lib.pas', 'Listed\NeverUsed.pas', 'Other\B.pas')
$raw = & $Exe selftest closure --project "$d\P.dpr" 2>&1 | Out-String
Check 'the used unit binds to the listed file' (($raw -match [regex]::Escape("$d\Listed\Lib.pas")) -and -not ($raw -match [regex]::Escape("$d\Other\Lib.pas"))) $raw
Check 'the listed but unused unit is not seeded (reconcile''s EXTRA stays honest)' (-not ($raw -match 'NeverUsed')) $raw

# --- group 11: FIX 2, one spelling per file --------------------------------------
Write-Host '[11] a rooted `in` path holding `..` joins normalised; the count is distinct files'
$d = Join-Path $Scratch 'g11'
$pd = "$d\Proj"
WriteText "$pd\P.dpr" "program P;`nuses`n  A in 'A.pas',`n  X in '..\Shared\X.pas',`n  Y in '$pd\..\Shared\Y.pas',`n  Y2 in '$pd\..\SHARED\Y2.pas';`nbegin`nend.`n"
WriteUnit "$pd\A.pas" 'A' 'X, Y, Y2, Z'
WriteUnit "$d\Shared\X.pas" 'X' 'Y'
WriteUnit "$d\Shared\Y.pas" 'Y'
WriteUnit "$d\Shared\Y2.pas" 'Y2'
WriteUnit "$d\Shared\Z.pas" 'Z'
WriteDproj $pd '..\Shared' @('A.pas', '..\Shared\X.pas')
$c = Closure $pd
Check 'no listed path holds a ..' (@($c.Files | Where-Object { $_ -match '\\\.\.\\' }).Count -eq 0) ($c.Files -join ' | ')
Check 'Y.pas is listed once' ((LeafCount $c 'Y.pas') -eq 1) ($c.Files -join ' | ')
$distinct = @($c.Files | ForEach-Object { [IO.Path]::GetFullPath($_).ToLowerInvariant() } | Sort-Object -Unique).Count
Check 'the printed count equals the distinct files' (($c.Count -eq $distinct) -and ($c.Count -eq $c.Files.Count)) "count=$($c.Count) distinct=$distinct listed=$($c.Files.Count)"

# --- group 12: the same through the library tail (an older target's search path) --
Write-Host '[12] the same when the older target''s library path holds the `..`'
$d = Join-Path $Scratch 'g12'
$pd = "$d\Proj"
WriteText "$pd\P.dpr" "program P;`nuses`n  A in 'A.pas',`n  Y in '..\Shared\Y.pas';`nbegin`nend.`n"
WriteUnit "$pd\A.pas" 'A' 'Y, TailOnly'
WriteUnit "$d\Shared\Y.pas" 'Y'
WriteUnit "$d\Shared\TailOnly.pas" 'TailOnly' 'Y'
WriteText "$pd\P.dproj" "<Project><PropertyGroup><MainSource>P.dpr</MainSource><ProjectVersion>20.1</ProjectVersion></PropertyGroup></Project>`n"
$s23 = "$d\Studio\23.0"; $s37 = "$d\Studio\37.0"
[void][IO.Directory]::CreateDirectory($s23); [void][IO.Directory]::CreateDirectory($s37)
$lib = @{ Win32 = @{ 'Search Path' = "$pd\..\Shared"; 'Browsing Path' = '' }; Win64 = @{ 'Search Path' = "$pd\..\Shared"; 'Browsing Path' = '' } }
$none = @{ Win32 = @{ 'Search Path' = ''; 'Browsing Path' = '' }; Win64 = @{ 'Search Path' = ''; 'Browsing Path' = '' } }
$reg = "$d\registry.json"
[IO.File]::WriteAllText($reg, (@{ '23.0' = @{ RootDir = $s23; Library = $lib; 'Environment Variables' = @{} }; '37.0' = @{ RootDir = $s37; Library = $none; 'Environment Variables' = @{} } } | ConvertTo-Json -Depth 8), [Text.Encoding]::ASCII)
$env:DRAGLINT_TEST_BDS_REGISTRY = $reg
$c = Closure $pd
$env:DRAGLINT_TEST_BDS_REGISTRY = ''
Check 'the tail unit came through (positive control)' (Has $c "$d\Shared\TailOnly.pas") $c.Raw
Check 'no listed path holds a ..' (@($c.Files | Where-Object { $_ -match '\\\.\.\\' }).Count -eq 0) ($c.Files -join ' | ')
Check 'Y.pas is listed once' ((LeafCount $c 'Y.pas') -eq 1) ($c.Files -join ' | ')

Write-Host ''
Write-Host ("run_closure_project_bindings: {0} passed, {1} failed" -f $script:pass, $script:fail)
Set-Location $OwnCwd
try { [IO.Directory]::Delete($Scratch, $true) } catch { Write-Host "note: could not delete $Scratch" }
if ($script:fail -gt 0) { exit 1 }
exit 0
