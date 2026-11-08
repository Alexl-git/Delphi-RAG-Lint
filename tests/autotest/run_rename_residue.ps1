<#
  run_rename_residue.ps1 -- E-RENAME-RESIDUE (wave 147): what lane 146-b3 left refused.

  1. A default / indexed property: the extractor writes 'indexed' (and 'default') into the property's directives, so
     `Bag[0].X` (default property, also inherited), `Bag.Items[0].X` and `Items[0].X` inside the class take the
     property's type as the element; `class(TObjectList<TItem>)` descendants read the element from their heritage.
  2. ResolveTypeNameToSymbol with two types of a name in scope: the unit qualifier picks (`ResA.TPair`), the unit's own
     declaration wins, else the unit listed LAST in the same uses clause wins. Candidates split across the interface
     and implementation uses decline (the section of a type text is not known).
  3. An unbound member whose receiver has a LIBRARY static type (`Lines.Capacity`, ref_types has the text) is decided
     like a library element type.

  POSITIVE CONTROLS: p1 (renaming ResB.TPair.Kind leaves ResA's and ResLocal's Kind alone: a first-wins or any-wins
  resolver would rewrite them), p2 (the split-section TPair still refuses), p3 (the library receiver is never
  rewritten; the split TPair refuses as ambiguous-type, the type text read from ref_types). Each sound case is proved three ways (plan, --apply through the gate, stdout byte-identical).
  RED on 1.46.0-alpha (main b036f2cb): see lanes\147\B5\REPORT.md.
  Needs RAD Studio; SKIPs (exit 0) without it. Works under %TEMP%.

  Usage: pwsh -File tests\autotest\run_rename_residue.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-residue-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx   = Join-Path $Repo 'tests\fixtures\refactor\rename_residue'
$Stub = Join-Path $Repo 'tests\fixtures\refactor\rename\libstub'
$Ascii = [Text.Encoding]::ASCII
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:N = 0

function Build-Lab([string]$Root) {
  $bat = "$Root.bld.bat"
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$Root`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal ResRen.dproj`r`nexit /b %ERRORLEVEL%`r`n", $Ascii)
  $p = Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$Root.bld.log" -RedirectStandardError "$Root.bld.err"
  return ($p.ExitCode -eq 0)
}
function Stdout-Of([string]$Root) {
  $x = Get-ChildItem $Root -Recurse -Filter ResRen.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $x) { return '<no exe>' }
  return (& $x.FullName 2>&1 | Out-String)
}
function New-Lab {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  Copy-Item "$Fx\*.pas", "$Fx\*.dpr", "$Fx\*.dproj" $root
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'ResRen.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'ResRen.dproj'); Db = $db; Use = (Join-Path $root 'ResUse.pas'); Types = (Join-Path $root 'ResTypes.pas'); Local = (Join-Path $root 'ResLocal.pas'); Split = (Join-Path $root 'ResSplit.pas') }
}
function Plan($P, [string]$Q, [string]$To) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $script:Lib --plan --json 2>$null | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  return @{ Exit = $c; Json = $j; Out = $o; Kinds = @($j.refusals | ForEach-Object { $_.kind }); Edits = @($j.edits) }
}
function Apply($P, [string]$Q, [string]$To) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $script:Lib --project $P.Dproj --build-timeout 600 --apply --no-backup 2>&1 | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  return @{ Exit = $c; Out = $o }
}
# sql --json rows are positional: map them onto the column names.
function Sql($P, [string]$Query) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe sql --db $P.Db --query $Query --json 2>$null | Out-String) } finally { Pop-Location }
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  if (-not $j) { return , @() }
  $names = @($j.columns | ForEach-Object { $_.name })
  $out = foreach ($r in @($j.rows)) {
    $h = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    [pscustomobject]$h
  }
  return , @($out)
}
function Line-Of([string]$Path, [string]$Literal) {
  $i = 0
  foreach ($l in ([IO.File]::ReadAllText($Path, $Ascii) -split "`r`n")) { $i++; if ($l.Contains($Literal)) { return $i } }
  throw "fixture line not found: $Literal"
}
# What the ref of AName on the source line holding ALiteral is bound to; '' = unbound. The LAST ref of that name wins.
function Bound-At($P, [string]$Path, [string]$Literal, [string]$Name) {
  $line = Line-Of $Path $Literal
  $q = "SELECT COALESCE(s.qualified_name, '') AS q FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
       "WHERE r.start_line = $line AND r.name_text = '$Name' AND f.path LIKE '%$([IO.Path]::GetFileName($Path))' ORDER BY r.start_col DESC LIMIT 1"
  $rows = Sql $P $q
  if ($rows.Count -eq 0) { return '<no ref>' }
  return [string]$rows[0].q
}
function Sound($Name, [string]$Q, [string]$To, [int]$MinEdits, [scriptblock]$Text) {
  $p = New-Lab
  $pl = Plan $p $Q $To
  Check "$Name plan: every occurrence decided" ($pl.Exit -eq 0 -and $pl.Json -and @($pl.Json.refusals).Count -eq 0) ($pl.Out)
  Check "$Name plan: at least $MinEdits edits" ($pl.Edits.Count -ge $MinEdits) ("edits=" + $pl.Edits.Count)
  $a = Apply $p $Q $To
  Check "$Name apply: through the gate, exit 0" ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
  Check "$Name stdout identical to the untouched build" ((Stdout-Of $p.Root) -ceq $script:Expected) (Stdout-Of $p.Root)
  & $Text $p
}
function Refused($Name, [string]$Q, [string]$To, [string]$Kind) {
  $p = New-Lab
  $pl = Plan $p $Q $To
  Check "$Name plan names [$Kind]" ($pl.Exit -eq 0 -and $pl.Kinds -contains $Kind) ($pl.Out)
}
function Text-Of([string]$Path) { return [IO.File]::ReadAllText($Path, $Ascii) }

# The miniature library and the expected stdout.
$libDir = Join-Path $WorkDir 'libsrc'
New-Item -ItemType Directory -Force $libDir | Out-Null
Copy-Item "$Stub\LibStub.pas" $libDir
$script:Lib = Join-Path $WorkDir 'lib.sqlite'
Push-Location $WorkDir; try { $null | & $Exe index $libDir --db $script:Lib --library-db none *> "$script:Lib.log" } finally { Pop-Location }
$base = New-Lab
Check 'fixture compiles untouched' (Build-Lab $base.Root) (Get-Content "$($base.Root).bld.log" -Tail 8 | Out-String)
$script:Expected = Stdout-Of $base.Root
Check 'fixture prints' ($script:Expected -match 'library 4')

Write-Host '--- the fact'
function Dir-Of([string]$Q) {
  $rows = Sql $base "SELECT COALESCE(directives, '') AS d FROM symbols WHERE qualified_name = '$Q' AND kind = 'property'"
  if ($rows.Count -ne 1) { return "<$($rows.Count) rows>" }
  return [string]$rows[0].d
}
Check 'default indexed property: directives "indexed default"' ((Dir-Of 'ResTypes.TBag.Items') -eq 'indexed default') (Dir-Of 'ResTypes.TBag.Items')
Check 'indexed property: directives "indexed"' ((Dir-Of 'ResTypes.TShelf.Slots') -eq 'indexed') (Dir-Of 'ResTypes.TShelf.Slots')
Check 'plain property: no directive' ((Dir-Of 'ResTypes.TShelf.Bag') -eq '') (Dir-Of 'ResTypes.TShelf.Bag')

Write-Host '--- bindings'
$ItemKind = 'ResTypes.TItem.Kind'
foreach ($c in @(
    @('default property',         "'default ', Bag[0]",         'Kind',     $ItemKind,                 'Use'),
    @('indexed property',         "'items ', Bag.Items[0]",     'Kind',     $ItemKind,                 'Use'),
    @('own indexed property',     'Result:= Items[0].Kind',     'Kind',     $ItemKind,                 'Types'),
    @('inherited default',        "'inherited ', Child[0]",     'Kind',     $ItemKind,                 'Use'),
    @('non-default indexed',      'Shelf.Slots[0].Kind',        'Kind',     $ItemKind,                 'Use'),
    @('property then default',    'Shelf.Bag[0].Kind',          'Kind',     $ItemKind,                 'Use'),
    @('list descendant',          "'descendant ', List[0].Kind", 'Kind',    $ItemKind,                 'Use'),
    @('list descendant 2',        'List[0].Capacity',           'Capacity', 'ResTypes.TItem.Capacity', 'Use'),
    @('last unit wins',           'Last.OnlyB:= 2',             'OnlyB',    'ResB.TPair.OnlyB',        'Use'),
    @('last unit wins 2',         'Last.Kind:= 1',              'Kind',     'ResB.TPair.Kind',         'Use'),
    @('unit qualifier',           'First.OnlyA:= 4',            'OnlyA',    'ResA.TPair.OnlyA',        'Use'),
    @('unit qualifier 2',         'First.Kind:= 3',             'Kind',     'ResA.TPair.Kind',         'Use'),
    @('own unit wins',            'Own.Kind:= 8',               'Kind',     'ResLocal.TPair.Kind',     'Local'),
    @('qualifier past own unit',  'Used.Kind:= 9',              'Kind',     'ResA.TPair.Kind',         'Local'),
    @('p2 split sections decline', 'Split.Spare:= 10',          'Spare',    '',                        'Split'))) {
  $got = Bound-At $base $base[$c[4]] $c[1] $c[2]
  Check ("{0}: {1} -> {2}" -f $c[0], $c[1], $(if ($c[3]) { $c[3] } else { '<unbound>' })) ($got -eq $c[3]) "got '$got'"
}

Write-Host '--- rename'
Sound 'c1 TItem.Kind' 'ResTypes.TItem.Kind' 'KindX' 9 {
  param($p)
  $u = Text-Of $p.Use
  Check 'c1 every element read is rewritten' ($u.Contains('Bag[0].KindX') -and $u.Contains('Bag.Items[0].KindX') -and $u.Contains('Child[0].KindX') -and $u.Contains('Shelf.Slots[0].KindX') -and $u.Contains('Shelf.Bag[0].KindX') -and $u.Contains('List[0].KindX') -and (Text-Of $p.Types).Contains('Items[0].KindX'))
  Check 'p1 c1 the TPair Kinds stay' ($u.Contains('Last.Kind:= 1') -and $u.Contains('First.Kind:= 3'))
}
Sound 'c2 ResB.TPair.Kind' 'ResB.TPair.Kind' 'KindB' 3 {
  param($p)
  $u = Text-Of $p.Use
  Check 'c2 the last-listed unit''s reads move' ($u.Contains('Last.KindB:= 1') -and $u.Contains("'pairs ', Last.KindB"))
  Check 'p1 c2 ResA / ResLocal Kind stays' ($u.Contains('First.Kind:= 3') -and (Text-Of $p.Local).Contains('Own.Kind:= 8') -and (Text-Of $p.Local).Contains('Used.Kind:= 9'))
}
Sound 'c3 ResLocal.TPair.Kind' 'ResLocal.TPair.Kind' 'KindL' 3 {
  param($p)
  $l = Text-Of $p.Local
  Check 'c3 own TPair moves, the qualified one stays' ($l.Contains('Own.KindL:= 8') -and $l.Contains('Used.Kind:= 9'))
}
Sound 'c4 TItem.Capacity' 'ResTypes.TItem.Capacity' 'Room' 3 {
  param($p)
  $u = Text-Of $p.Use
  Check 'c4 the element read moves' ($u.Contains('List[0].Room'))
  Check 'p3 c4 the library receiver stays' ($u.Contains('Lines.Capacity:= 4') -and $u.Contains("'library ', Lines.Capacity"))
}
Refused 'p2 split-section TPair.Spare' 'ResB.TPair.Spare' 'Spare2' 'ambiguous-type'

if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("rename-residue: {0} passed, {1} failed" -f $script:Passed, $script:FailCount)
if ($script:Failed) { exit 1 }
exit 0