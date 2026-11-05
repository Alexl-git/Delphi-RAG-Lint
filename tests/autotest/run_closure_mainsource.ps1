<#
  run_closure_mainsource.ps1 -- B12: the compile closure of a .dproj starts from the
  program file the project names in <MainSource>, not from the sibling <name>.dpr.

  The walk derived the .dpr by swapping the .dproj extension, so a project whose
  MainSource is another file (other.dpr, sub\Main.dpr, a .dpk) indexed the wrong
  program's members -- or none, when no sibling existed.

  Driven through `index --project --dry-run` into this guard's own temp folder; a dry run
  writes no DB. Group 4 (no MainSource: sibling .dpr) and group 5 (MainSource names a
  missing file: sibling fallback) are the unchanged-behaviour positive controls; they must
  pass on the old engine too, which proves the closure parser below still matches.
#>
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Continue'
$Exe = (Resolve-Path $Exe).Path
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) ("dl-closmain-" + [Guid]::NewGuid().ToString('N')) }
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
function WriteUnit([string]$Path, [string]$Name) {
  WriteText $Path "unit $Name;`ninterface`nimplementation`nend.`n"
}
function WriteDproj([string]$Dir, [string]$Main) {
  $ms = if ($Main) { "<MainSource>$Main</MainSource>" } else { '' }
  WriteText "$Dir\P.dproj" "<Project><PropertyGroup>$ms<ProjectVersion>20.1</ProjectVersion></PropertyGroup></Project>`n"
}
function Closure([string]$Dir) {
  $db = Join-Path $Scratch ("dry-" + [Guid]::NewGuid().ToString('N') + '.sqlite')
  $raw = & $Exe index --project "$Dir\P.dproj" --db $db --library-db "$Scratch\no-library.sqlite" --dry-run 2>&1 | Out-String
  $lines = @($raw -split "`r?`n")
  $files = @()
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^Compile closure: (\d+) file') { $start = $i; break } }
  if ($start -ge 0) {
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -notmatch '^  \S') { break }
      $files += $lines[$i].Trim()
    }
  }
  return [pscustomobject]@{ Raw = $raw; Files = $files }
}
function Has($C, [string]$Leaf) { return @($C.Files | Where-Object { [IO.Path]::GetFileName($_) -ieq $Leaf }).Count -gt 0 }

Write-Host '[1] MainSource names other.dpr; a decoy sibling P.dpr holds different units'
$d = Join-Path $Scratch 'g1'
WriteText "$d\other.dpr" "program Other;`nuses`n  RealA in 'RealA.pas';`nbegin`nend.`n"
WriteText "$d\P.dpr" "program P;`nuses`n  DecoyA in 'DecoyA.pas';`nbegin`nend.`n"
WriteUnit "$d\RealA.pas" 'RealA'
WriteUnit "$d\DecoyA.pas" 'DecoyA'
WriteDproj $d 'other.dpr'
$c = Closure $d
Check 'the closure printed (raw shape)' ($c.Files.Count -ge 1) $c.Raw
Check 'RealA.pas (member of other.dpr) is in the closure' (Has $c 'RealA.pas') ($c.Files -join ' | ')
Check 'DecoyA.pas (member of the sibling P.dpr) is not' (-not (Has $c 'DecoyA.pas')) ($c.Files -join ' | ')

Write-Host '[2] MainSource in a subfolder, `in` paths relative to that program'
$d = Join-Path $Scratch 'g2'
WriteText "$d\sub\Main.dpr" "program Main;`nuses`n  SubA in 'SubA.pas';`nbegin`nend.`n"
WriteUnit "$d\sub\SubA.pas" 'SubA'
WriteDproj $d 'sub\Main.dpr'
$c = Closure $d
Check 'SubA.pas is in the closure' (Has $c 'SubA.pas') ($c.Files -join ' | ')

Write-Host '[3] MainSource names a .dpk and no sibling program exists'
$d = Join-Path $Scratch 'g3'
WriteText "$d\Pkg.dpk" "package Pkg;`ncontains`n  PkgA in 'PkgA.pas';`nend.`n"
WriteUnit "$d\PkgA.pas" 'PkgA'
WriteDproj $d 'Pkg.dpk'
$c = Closure $d
Check 'PkgA.pas is in the closure' (Has $c 'PkgA.pas') ($c.Files -join ' | ')

Write-Host '[4] control: no MainSource, sibling P.dpr (unchanged)'
$d = Join-Path $Scratch 'g4'
WriteText "$d\P.dpr" "program P;`nuses`n  SibA in 'SibA.pas';`nbegin`nend.`n"
WriteUnit "$d\SibA.pas" 'SibA'
WriteDproj $d ''
$c = Closure $d
Check 'SibA.pas is in the closure' (Has $c 'SibA.pas') ($c.Files -join ' | ')

Write-Host '[5] control: MainSource names a missing file, sibling P.dpr answers (unchanged)'
$d = Join-Path $Scratch 'g5'
WriteText "$d\P.dpr" "program P;`nuses`n  SibA in 'SibA.pas';`nbegin`nend.`n"
WriteUnit "$d\SibA.pas" 'SibA'
WriteDproj $d 'gone.dpr'
$c = Closure $d
Check 'SibA.pas is in the closure' (Has $c 'SibA.pas') ($c.Files -join ' | ')

Write-Host ''
Write-Host ("run_closure_mainsource: {0} passed, {1} failed" -f $script:pass, $script:fail)
Set-Location $OwnCwd
try { [IO.Directory]::Delete($Scratch, $true) } catch { Write-Host "note: could not delete $Scratch" }
if ($script:fail -gt 0) { exit 1 }
exit 0
