<#
  run_rename_element_type.ps1 -- E-RENAME-ELEMENT-TYPE (wave 146): `A[i].X` is decided by the static type of the element.

  YADF's main rename refusal was receiver-untyped on `ATokens[i].Kind` (25 of 68 targets). TTokenList is an alias of
  TList<TToken>: the selector chain could read arrays, not a library list, so the ref stayed unbound and had no receiver.
  Now the chain reads TList / TObjectList / IList / IReadOnlyList and the dictionaries, and a type text is resolved in the
  unit that wrote it. What is still unbound gets a row in ref_element_types, read by rename's proof.

  POSITIVE CONTROLS: p1 (the element is the DECLARING unit's TTok, not the TTok the site sees), p2 (TList<T> inside TBox<T>
  never binds to the record spelled T, so its rename refuses), p3 (a subscript on a call: typed since resolver 1.23, renamed through the gate), each sound
  case proved three ways (plan, --apply through the gate, stdout byte-identical to the untouched build).
  RED on lane/145-int 1efa0c35: 0 bound, no table, every rename refused.
  Needs RAD Studio; SKIPs (exit 0) without it. Works under %TEMP%.

  Usage: pwsh -File tests\autotest\run_rename_element_type.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-element-$PID",
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
$Fx   = Join-Path $Repo 'tests\fixtures\refactor\rename_element'
$Stub = Join-Path $Repo 'tests\fixtures\refactor\rename\libstub'
$Ascii = [Text.Encoding]::ASCII
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:N = 0

function Build-Lab([string]$Root) {
  $bat = "$Root.bld.bat"
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$Root`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal ElemRen.dproj`r`nexit /b %ERRORLEVEL%`r`n", $Ascii)
  $p = Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$Root.bld.log" -RedirectStandardError "$Root.bld.err"
  return ($p.ExitCode -eq 0)
}
function Stdout-Of([string]$Root) {
  $x = Get-ChildItem $Root -Recurse -Filter ElemRen.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
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
  try { $null | & $Exe index --project (Join-Path $root 'ElemRen.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'ElemRen.dproj'); Db = $db; Use = (Join-Path $root 'ElemUse.pas'); Types = (Join-Path $root 'ElemTypes.pas') }
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
Check 'fixture prints' ($script:Expected -match 'nested 6')

Write-Host '--- bindings'
$TokKind = 'ElemTypes.TTok.Kind'
$ThingKind = 'ElemTypes.TThing.Kind'
foreach ($c in @(
    @('alias param',      'pTokens[i].Kind',          'Kind', $TokKind),
    @('unit var alias',   "'unit alias ', GToks[0]",  'Kind', $TokKind),
    @('unit var list',    "'unit direct ', GDirect",  'Kind', $TokKind),
    @('inline list',      "'other ', Others[0]",      'Kind', 'ElemTypes.TOtherRec.Kind'),
    @('object list',      'Things[0].Kind:= 4',       'Kind', $ThingKind),
    @('method no parens', 'Things[0].Ping;',          'Ping', 'ElemTypes.TThing.Ping'),
    @('method parens',    'Things[0].Ping();',        'Ping', 'ElemTypes.TThing.Ping'),
    @('dictionary value', "Dict['a'].Kind",           'Kind', $ThingKind),
    @('property',         'Holder.Toks[0].Kind',      'Kind', $TokKind),
    @('field',            'Holder.FToks[0].Kind',     'Kind', $TokKind),
    @('list then member', 'Holders[0].Toks[0].Kind',  'Kind', $TokKind),
    @('list of arrays',   'GNested[0][0].Kind',        'Kind', $TokKind))) {
  $got = Bound-At $base $base.Use $c[1] $c[2]
  Check ("{0}: {1} -> {2}" -f $c[0], $c[1], $c[3]) ($got -eq $c[3]) "got '$got'"
}
$got = Bound-At $base $base.Types 'FL[0].Tally' 'Tally'
Check 'p2 TList<T> in TBox<T>: not the record spelled T' ($got -eq '') "got '$got'"
$got = Bound-At $base $base.Use "'string ', Names[0]" 'Length'
Check 'string element: no project member binds' ($got -eq '') "got '$got'"

Write-Host '--- the fact'
$rows = Sql $base ("SELECT e.type_qname AS q, e.type_symbol_id AS id FROM ref_element_types e JOIN refs r ON r.id = e.ref_id WHERE r.start_line = " +
  (Line-Of $base.Use "'string ', Names[0]") + " AND r.name_text = 'Length'")
Check 'library element: a row with the text and no symbol' ($rows.Count -eq 1 -and $rows[0].q -eq 'string' -and $null -eq $rows[0].id) ($rows | Out-String)
$rows = Sql $base ("SELECT s.qualified_name AS q FROM ref_element_types e JOIN refs r ON r.id = e.ref_id JOIN symbols s ON s.id = e.type_symbol_id WHERE r.start_line = " +
  (Line-Of $base.Use 'pTokens[i].Kind') + " AND r.name_text = 'Kind'")
Check 'project element: a row with the symbol' ($rows.Count -eq 1 -and $rows[0].q -eq 'ElemTypes.TTok') ($rows | Out-String)
$rows = Sql $base ("SELECT e.type_qname AS q FROM ref_element_types e JOIN refs r ON r.id = e.ref_id WHERE r.start_line = " +
  (Line-Of $base.Types 'FL[0].Tally') + " AND r.name_text = 'Tally'")
Check 'p2 no row for a generic parameter' ($rows.Count -eq 0) ($rows | Out-String)

Write-Host '--- rename'
Sound 'c1 TTok.Kind' 'ElemTypes.TTok.Kind' 'KindX' 9 {
  param($p)
  $u = Text-Of $p.Use
  Check 'c1 the element reads are rewritten' ($u.Contains('pTokens[i].KindX') -and $u.Contains('GNested[0][0].KindX') -and $u.Contains('Holders[0].Toks[0].KindX') -and $u.Contains('GDirect[0].KindX'))
  Check 'p1 c1 another TThing / TOtherRec / shadow Kind stays' ($u.Contains('Things[0].Kind:= 4') -and $u.Contains('Others[0].Kind') -and $u.Contains("Dict['a'].Kind") -and (Text-Of (Join-Path $p.Root 'ElemShadow.pas')).Contains('Shadow.Kind:= '))
}
Sound 'c2 ElemShadow.TTok.Kind' 'ElemShadow.TTok.Kind' 'ShadowKind' 3 {
  param($p)
  $u = Text-Of $p.Use
  Check 'p1 c2 only the shadow record moved' ((Text-Of (Join-Path $p.Root 'ElemShadow.pas')).Contains('Shadow.ShadowKind:= ') -and $u.Contains('pTokens[i].Kind') -and $u.Contains('GDirect[0].Kind'))
}
Sound 'c3 TThing.Length' 'ElemTypes.TThing.Length' 'Span' 2 {
  param($p)
  $u = Text-Of $p.Use
  Check 'c3 the string element Length is decided, not touched' ($u.Contains('Names[0].Length') -and $u.Contains('Things[0].Span'))
}
Refused 'p2 record T.Tally' 'ElemGeneric.T.Tally' 'Tally2' 'receiver-untyped'
Refused 'p2 TThing.Tally' 'ElemTypes.TThing.Tally' 'Tally2' 'receiver-untyped'
# 149 INT: resolver 1.23 (lane RB1, selector-chain call heads) types `GetList()[0]`, so p3 is now a SOUND
# rename through the compile gate (stdout identical) instead of a receiver-untyped refusal.
Sound 'p3 a subscript on a call: TTok.Hard' 'ElemTypes.TTok.Hard' 'Hard2' 3 {
  param($p)
  Check 'p3 the call-subscript read is rewritten' ((Text-Of $p.Use).Contains('GetList()[0].Hard2'))
}

if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("rename-element-type: {0} passed, {1} failed" -f $script:Passed, $script:FailCount)
if ($script:Failed) { exit 1 }
exit 0