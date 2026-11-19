<#
  run_v152_RENFACT.ps1 -- drag-lint 1.52 lane RENFACT (backlog E-RENAME-RESIDUE, the extractor half).

  THE GAP. A default property is reached WITHOUT its name: `Bag[0]` reads TBag.Items, `Bag[0]:= X`
  writes it through SetItem. Until 1.52 the extractor wrote no ref for that site, so `usages` of
  TBag.Items counted only the two sites that spell `Items`, find-callers of the getter / setter missed
  every implicit call, and rename / unused-public-symbol saw a default property as barely used.

  THE FACT. The parser emits one 'index-access' ref (name_text '[]', receiver_text = the subscripted
  expression) per `X[...]` subscript; the resolver types the receiver and, when the subscript reaches
  a DEFAULT array property (own, inherited, interface), binds the ref to it with a member_accesses row
  (read / write + accessor). An array, a string, a library list and an indexed property's OWN index
  stay unbound (a '[]' ref never matches an identifier, so rename never edits one).

  Fixture tests\autotest\fixtures\v152-RENFACT (compiles with dcc64; prints 13 lines).
  Every index run passes --db into a private work folder: no real DB is touched. `sql --json` rows are
  POSITIONAL arrays and are mapped by column index.

  Cases: d1-d12 bound sites; c1-c7 positive controls that must stay unbound; u1-u2 usages of
  TBag.Items (reads 11 / writes 1, was 2 / 0); f1 find-callers of the setter; r1 the rename plan of
  TBag.Items still edits exactly the three sites that spell the name.

  Usage: pwsh -File tests\autotest\run_v152_RENFACT.ps1 [-Exe <drag-lint.exe>]
  Exit 0 = all pass, 1 = a check failed, 2 = setup failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\draglint_v152_renfact_$PID",
  [switch]$KeepWorkDir
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Passed = 0; $script:Failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host ("  [PASS] {0}" -f $Name) }
  else     { $script:Failed++; Write-Host ("  [FAIL] {0} {1}" -f $Name, $Detail) -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\v152-RENFACT')).Path
$Ascii = [Text.Encoding]::ASCII

New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Code = Join-Path $WorkDir 'code'
New-Item -ItemType Directory -Force $Code | Out-Null
Copy-Item "$Fx\*" $Code
$Db = Join-Path $WorkDir 'rf.sqlite'
Push-Location $WorkDir
try { $log = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe index $Code --db $Db --library-db none 2>&1 | ForEach-Object { "$_" } } | Out-String); $ec = $LASTEXITCODE } finally { Pop-Location }
if ($ec -ne 0) { Write-Host "FATAL: index exit $ec" -ForegroundColor Red; $log; exit 2 }

function Invoke-Sql([string]$Query) {
  Push-Location $WorkDir
  try { $raw = $null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe sql --db $Db --query $Query --json --limit 0 2>$null } } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { throw "sql failed: $Query" }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json
  $list = [System.Collections.Generic.List[object]]::new()
  foreach ($r in $j.rows) { $list.Add($r) }
  return ,$list
}
function Line-Of([string]$File, [string]$Literal) {
  $i = 0
  foreach ($l in ([IO.File]::ReadAllText((Join-Path $Code $File), $Ascii) -split "`r`n")) { $i++; if ($l.Contains($Literal)) { return $i } }
  throw "fixture line not found: $Literal"
}
# The index-access refs on the line holding ALiteral, left to right: 'qname/mode' per ref, '-' = unbound.
function Subscripts-At([string]$File, [string]$Literal) {
  $line = Line-Of $File $Literal
  $q = "SELECT COALESCE(s.qualified_name, '-'), COALESCE(ma.mode, '') FROM refs r JOIN files f ON f.id = r.file_id " +
       "LEFT JOIN symbols s ON s.id = r.symbol_id LEFT JOIN member_accesses ma ON ma.ref_id = r.id " +
       "WHERE r.kind = 'index-access' AND r.start_line = $line AND f.path LIKE '%$File' ORDER BY r.start_col"
  $out = @()
  foreach ($r in (Invoke-Sql $q)) { $out += if ($r[0] -eq '-') { '-' } else { "$($r[0])/$($r[1])" } }
  return ($out -join ' ')
}

$Items = 'RfTypes.TBag.Items'
Write-Host '--- the fact: one index-access ref per subscript'
$n = (Invoke-Sql "SELECT COUNT(*) FROM refs WHERE kind = 'index-access' AND name_text = '[]'")[0][0]
Check "f0 index-access refs are written (got $n)" ([int]$n -ge 20) "count=$n"

Write-Host '--- bound: the subscript reaches a default property'
foreach ($c in @(
    @('d1 default read',               'RfUse.pas',   "'default ', Bag[0]",          "$Items/read"),
    @('d2 default write',              'RfUse.pas',   'Bag[0]:= TItem.Create(6)',    "$Items/write"),
    @('d3 inherited default',          'RfUse.pas',   "'inherited ', Child[0]",      "$Items/read"),
    @('d4 property then default',      'RfUse.pas',   'Shelf.Bag[0].Kind',           "$Items/read"),
    @('d5 own index then default',     'RfUse.pas',   'Shelf.Bags[0][0].Kind',       "- $Items/read"),
    @('d6 two-index default',          'RfUse.pas',   'N:= Grid[1, 2]',              'RfTypes.TGrid.Cells/read'),
    @('d7 nested defaults',            'RfUse.pas',   'Rack[0][0].Kind',             "RfTypes.TRack.Bags/read $Items/read"),
    @('d8 interface default',          'RfUse.pas',   'Row[3]',                      'RfTypes.IRow.Values/read'),
    @('d9 Self default',               'RfTypes.pas', 'Result:= Self[0].Kind',       "$Items/read"),
    @('d10 field default',             'RfTypes.pas', 'Result:= FBag[pIndex]',       "$Items/read"),
    @('d11 default as an argument',    'RfUse.pas',   'List.Add(Bag[0])',            "$Items/read"),
    @('d12 array target, default rhs', 'RfUse.pas',   'Arr[0]:= Bag[0]',             "- $Items/read"))) {
  $got = Subscripts-At $c[1] $c[2]
  Check ("{0}: {1} -> {2}" -f $c[0], $c[2], $c[3]) ($got -eq $c[3]) "got '$got'"
}

Write-Host '--- controls: no default property is reached'
foreach ($c in @(
    @('c1 named indexed property',     'RfUse.pas',   'Bag.Items[0].Kind',           '-'),
    @('c2 own index only',             'RfUse.pas',   'Shelf.Bags[0].FirstKind',     '-'),
    @('c3 non-default indexed',        'RfUse.pas',   'Shelf.Slots[0].Kind',         '-'),
    @('c4 array and string',           'RfUse.pas',   "'array ', Arr[0].Kind",       '- -'),
    @('c5 library list heritage',      'RfUse.pas',   'List[0].Kind',                '-'),
    @('c6 own property by name',       'RfTypes.pas', 'Result:= Items[0].Kind',      '-'),
    @('c7 library field',              'RfTypes.pas', 'Result:= FList[pIndex]',      '-'))) {
  $got = Subscripts-At $c[1] $c[2]
  Check ("{0}: {1} -> {2}" -f $c[0], $c[2], $c[3]) ($got -eq $c[3]) "got '$got'"
}

Write-Host '--- consumers'
Push-Location $WorkDir
try {
  $u = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe usages --name $Items --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-String)
  $fc = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe query find-callers --name SetItem --db $Db --resolved 2>&1 | ForEach-Object { "$_" } } | Out-String)
  $rp = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe rename --kind symbol --name $Items --to Elems --db $Db --library-db none --plan 2>&1 | ForEach-Object { "$_" } } | Out-String)
} finally { Pop-Location }
$reads  = if ($u -match 'reads:\s*(\d+)')  { [int]$Matches[1] } else { -1 }
$writes = if ($u -match 'writes:\s*(\d+)') { [int]$Matches[1] } else { -1 }
Check "u1 usages $Items reads 11 (got $reads)"  ($reads -eq 11)  $u
Check "u2 usages $Items writes 1 (got $writes)" ($writes -eq 1)  $u
Check 'f1 find-callers SetItem names RunAll (the implicit write)' ($fc -match 'RfUse\.RunAll') $fc
$edits = @([regex]::Matches($rp, '(?m)^\s+L\d+:C\d+\s+Items -> Elems'))
Check "r1 rename plan edits exactly the 3 named sites (got $($edits.Count))" ($edits.Count -eq 3 -and $rp -notmatch '\[\]') $rp

if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("v152-RENFACT: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
exit $(if ($script:Failed -gt 0) { 1 } else { 0 })
