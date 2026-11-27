<#
  run_v156_EXTATTR.ps1 -- 1.56 lane EXT-ATTR: the `attribute` ref of a unit-qualified attribute.

  Indexes tests\fixtures\v156-extattr into a scratch DB and checks, through `sql --json` (rows are
  POSITIONAL arrays; mapped onto columns[].name below) and `query find-callers --json` (a bare
  ARRAY, line field `start_line`):
    A1  every form gives exactly ONE `attribute` ref per attribute, name_text = the attribute's own
        name (no unit qualifier), bound to the attribute class:
        [Inject], [Unit.Inject], [Named('x')], [Unit.Named('x')], [A, B], [Unit.A, Unit.B(arg)],
        [InjectAttribute], [Unit.InjectAttribute].
    A2  the arguments keep their ordinary refs (the dotted constant inside a qualified attribute's
        argument list is still a bound member-access); no attribute line carries a `call` ref.
    A3  find-callers --name InjectAttribute answers the four Inject sites (short and full name,
        bare and qualified); --name Inject the two short ones.
    A4  NEGATIVE: an attribute naming no indexed class keeps its ref, unbound; an unrelated dotted
        expression in a routine body emits no `attribute` ref and exactly the refs it had.
    A5  the attributes table is untouched: one row per attribute.
  Positive control: run with -Exe <the engine built from the lane base d0977a170> -- A1 and A3 FAIL
  (no ref for the qualified bare form, the whole dotted text as the name of the qualified one with
  arguments, nothing bound), A2 / A4 control / A5 pass.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_EXTATTR: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_EXTATTR: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-extattr'
$work  = Join-Path $env:TEMP ('dl-v156-extattr-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name); a failed query returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $Query --db $Db --json 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()
}
# find-callers --json -> the sorted start_line list of the sites in the consumer unit.
function Caller-Lines([string]$Db, [string]$Name) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe query find-callers --name $Name --db $Db --json 2>$null }
  if (-not $raw) { return ,@() }
  try { $j = @(($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) } catch { return ,@() }
  return ,@($j | Where-Object { $_.file_path -like '*uExtAttrUse.pas' } | ForEach-Object { [int]$_.start_line } | Sort-Object)
}

try {
  $src = Join-Path $work 'src'
  Copy-Item $fxSrc $src -Recurse
  $M = @{}
  $ln = 0
  foreach ($line in [IO.File]::ReadAllLines((Join-Path $src 'uExtAttrUse.pas'))) {
    $ln++
    $hit = [regex]::Match($line, '\{ (M-[A-Z-]+) \}')
    if ($hit.Success) { $M[$hit.Groups[1].Value] = $ln }
  }
  Check 'fixture markers found (fixture input)' ($M.Count -eq 10) "markers=$($M.Count)"

  $db  = Join-Path $work 'a.sqlite'
  $log = Join-Path $work 'index.log'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db *> $log }
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "rc=$LASTEXITCODE"

  $refs = @(Lane-Sql $db ("SELECT r.kind, r.name_text, r.start_line, r.start_col, r.end_col, s.name AS target, s.kind AS target_kind " +
    "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
    "WHERE f.path LIKE '%uExtAttrUse.pas' ORDER BY r.start_line, r.start_col LIMIT 100000"))
  $attr = @($refs | Where-Object { $_.kind -eq 'attribute' })
  Check 'the consumer unit has attribute refs at all (POSITIVE CONTROL for every negative below)' ($attr.Count -gt 0) "attribute refs=$($attr.Count) all refs=$($refs.Count)"
  function At([string]$Marker) { @($attr | Where-Object { $_.start_line -eq $M[$Marker] }) }
  # exactly one ref of that name on the marker's line, bound to that class
  function One([string]$Marker, [string]$Name, [string]$Class) {
    $t = @((At $Marker) | Where-Object { $_.name_text -eq $Name })
    ($t.Count -eq 1) -and ($t[0].target -eq $Class) -and ($t[0].target_kind -eq 'class') -and
      (($t[0].end_col - $t[0].start_col) -eq $Name.Length)
  }
  function Shown([string]$Marker) { ((At $Marker) | ForEach-Object { "$($_.name_text)->$($_.target)" }) -join ', ' }

  Write-Host 'A1 one attribute ref per attribute, bound to its class' -ForegroundColor Cyan
  Check '[Inject] -> InjectAttribute' ((One 'M-BARE' 'Inject' 'InjectAttribute') -and (At 'M-BARE').Count -eq 1) (Shown 'M-BARE')
  Check '[ExtAttr.Common.Attrs.Inject] -> InjectAttribute, name_text Inject' ((One 'M-QUAL' 'Inject' 'InjectAttribute') -and (At 'M-QUAL').Count -eq 1) (Shown 'M-QUAL')
  Check '[Named(''one'')] -> NamedAttribute' ((One 'M-ARGS' 'Named' 'NamedAttribute') -and (At 'M-ARGS').Count -eq 1) (Shown 'M-ARGS')
  Check '[ExtAttr.Common.Attrs.Named(''two'')] -> NamedAttribute, name_text Named' ((One 'M-QUAL-ARGS' 'Named' 'NamedAttribute') -and (At 'M-QUAL-ARGS').Count -eq 1) (Shown 'M-QUAL-ARGS')
  Check '[WeakRef, Tag] -> one ref each' ((One 'M-LIST' 'WeakRef' 'WeakRefAttribute') -and (One 'M-LIST' 'Tag' 'TagAttribute') -and (At 'M-LIST').Count -eq 2) (Shown 'M-LIST')
  Check '[Unit.WeakRef, Unit.Named(arg)] -> one ref each' ((One 'M-QUAL-LIST' 'WeakRef' 'WeakRefAttribute') -and (One 'M-QUAL-LIST' 'Named' 'NamedAttribute') -and (At 'M-QUAL-LIST').Count -eq 2) (Shown 'M-QUAL-LIST')
  Check '[InjectAttribute] -> InjectAttribute' ((One 'M-FULL' 'InjectAttribute' 'InjectAttribute') -and (At 'M-FULL').Count -eq 1) (Shown 'M-FULL')
  Check '[ExtAttr.Common.Attrs.InjectAttribute] -> InjectAttribute' ((One 'M-QUAL-FULL' 'InjectAttribute' 'InjectAttribute') -and (At 'M-QUAL-FULL').Count -eq 1) (Shown 'M-QUAL-FULL')
  Check 'eleven attribute refs in the unit, none carries a dotted name' ($attr.Count -eq 11 -and @($attr | Where-Object { $_.name_text -like '*.*' }).Count -eq 0) "refs=$($attr.Count) dotted=$(@($attr | Where-Object { $_.name_text -like '*.*' }).Count)"

  Write-Host 'A2 arguments keep their refs' -ForegroundColor Cyan
  $argRefs = @($refs | Where-Object { $_.start_line -eq $M.'M-QUAL-LIST' -and $_.kind -ne 'attribute' })
  Check 'the dotted constant in the argument list is a bound member-access' (@($argRefs | Where-Object { $_.kind -eq 'member-access' -and $_.name_text -eq 'DefaultName' -and $_.target -eq 'DefaultName' }).Count -eq 1) "non-attribute refs on the line=$($argRefs.Count)"
  $attrLines = @($M.Keys | Where-Object { $_ -ne 'M-CONTROL' } | ForEach-Object { $M[$_] })
  Check 'no attribute line carries a call ref' (@($refs | Where-Object { $_.kind -eq 'call' -and $_.start_line -in $attrLines }).Count -eq 0)

  Write-Host 'A3 find-callers' -ForegroundColor Cyan
  $want = @($M.'M-BARE', $M.'M-QUAL', $M.'M-FULL', $M.'M-QUAL-FULL' | Sort-Object)
  $got  = Caller-Lines $db 'InjectAttribute'
  Check 'find-callers --name InjectAttribute = the four Inject sites' (($got -join ',') -eq ($want -join ',')) "got=$($got -join ',') want=$($want -join ',')"
  $want = @($M.'M-BARE', $M.'M-QUAL' | Sort-Object)
  $got  = Caller-Lines $db 'Inject'
  Check 'find-callers --name Inject = the two short-name sites' (($got -join ',') -eq ($want -join ',')) "got=$($got -join ',') want=$($want -join ',')"
  $want = @($M.'M-ARGS', $M.'M-QUAL-ARGS', $M.'M-QUAL-LIST' | Sort-Object)
  $got  = Caller-Lines $db 'NamedAttribute'
  Check 'find-callers --name NamedAttribute = the three Named sites' (($got -join ',') -eq ($want -join ',')) "got=$($got -join ',') want=$($want -join ',')"

  Write-Host 'A4 negatives' -ForegroundColor Cyan
  $t = @(At 'M-UNKNOWN')
  Check 'an attribute naming no indexed class: one ref, unbound' ($t.Count -eq 1 -and $t[0].name_text -eq 'NotIndexed' -and -not $t[0].target) (Shown 'M-UNKNOWN')
  $c = @($refs | Where-Object { $_.start_line -eq $M.'M-CONTROL' })
  $shape = ($c | ForEach-Object { "$($_.kind):$($_.name_text)" }) -join ' '
  Check 'control: the dotted expression in a body has exactly its old refs, no attribute ref' ($shape -eq 'write:Result read:ExtAttr member-access:Common member-access:Attrs member-access:DefaultName') $shape

  Write-Host 'A5 attributes table' -ForegroundColor Cyan
  $rows = @(Lane-Sql $db ("SELECT a.attr_name, a.line FROM attributes a JOIN files f ON f.id = a.file_id WHERE f.path LIKE '%uExtAttrUse.pas' LIMIT 1000"))
  Check 'one attributes row per attribute (11)' ($rows.Count -eq 11) "rows=$($rows.Count)"

  Write-Host ''
  Write-Host "run_v156_EXTATTR: pass=$($script:pass) fail=$($script:fail)"
  if ($script:fail -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
}
finally {
  if (-not $KeepScratch -and (Test-Path -LiteralPath $work)) { [IO.Directory]::Delete($work, $true) }
}
