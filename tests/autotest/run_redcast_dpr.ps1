<#
  run_redcast_dpr.ps1 -- wave 150 Y3: redundant-cast on a .dpr, and the implementation-only
  overload twins it depends on.

  The fixture tests\fixtures\refactor\redcast-dpr\Gx.dpr says on each cast line what must happen
  (FIX / REFUSE <kind>, markers as in redcast\RcUse.pas). Its GxOv pair is declared ONLY by two
  bodies in the program (no interface, no forward): before Y3 the extractor deduplicated the second
  body against the first by NAME (FreeRoutineSymbolExists), so the index held one GxOv, HasOverloads
  counted one, and `TGxBase(GxOv(1))` was planned as a FIX instead of REFUSE overloaded-operand.

  S-checks pin the symbol shape on a generated unit: impl-only overload twins are two symbols; a
  forward declaration + its body, an interface declaration + its body and a declared overload pair
  stay one symbol per routine (the dedup still works); a free routine that shares its name with an
  earlier NESTED routine is its own symbol.

  Positive controls: C1 the marker reader finds FIX and REFUSE overloaded-operand (a reader that
  finds nothing passes vacuously); S2/S3/S4 fail if the dedup is removed instead of narrowed
  (duplicate symbols); D1 fails on the pre-Y3 build (line 28 planned as FIX).
#>
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\redcast-dpr").Path
$Tmp = Join-Path $env:TEMP ("redcast_dpr_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function Sql-Rows([string]$Db, [string]$Query) {
  $o = & $Exe sql --db $Db --query $Query --json 2> (Join-Path $Tmp 'sql.err')
  $j = ($o -join "`n") | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $rows = @()
  foreach ($r in $j.rows) {
    $h = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $rows += [pscustomobject]$h
  }
  return , $rows
}
function Read-Markers([string]$Path) {
  $map = @{}
  $n = 0
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    $n++
    $m = [regex]::Match($l, '//\s*((FIX|NONE|REFUSE\s+[a-z-]+)(\s+(FIX|REFUSE\s+[a-z-]+))*)\s*$')
    if ($m.Success) { $map[$n] = @([regex]::Matches($m.Groups[1].Value, 'FIX|NONE|REFUSE\s+[a-z-]+') | ForEach-Object { ($_.Value -replace '\s+', ' ') }) }
  }
  return $map
}

try {
  # ---- the .dpr plan -----------------------------------------------------------------------------
  Write-Host 'redundant-cast plan on the .dpr fixture'
  $d = Join-Path $Tmp 'dpr'
  Copy-Item $Fx $d -Recurse
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'Gx.dproj') --db $db --library-db none *> (Join-Path $Tmp 'dpr.index.log')
  Check 'I1 index of the fixture exits 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $ov = Sql-Rows $db "SELECT s.name, p.kind AS pkind FROM symbols s JOIN symbols p ON p.id = s.parent_id JOIN files f ON f.id = s.file_id WHERE f.path LIKE '%Gx.dpr' AND s.name = 'GxOv' AND s.kind = 'function'"
  Check 'S1 the .dpr GxOv bodies are two symbols, both parented to the program' (($ov.Count -eq 2) -and (@($ov | Where-Object { $_.pkind -eq 'program' }).Count -eq 2)) "got $($ov.Count): $(($ov | ForEach-Object { $_.pkind }) -join ',')"
  $o = & $Exe lint --fix --fix-rule redundant-cast --library-db none --db $db --project (Join-Path $d 'Gx.dproj') --format json 2> (Join-Path $Tmp 'plan.err')
  Check 'D0 the dry run exits 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $plan = ($o -join "`n") | ConvertFrom-Json
  $want = Read-Markers (Join-Path $d 'Gx.dpr')
  $flat = @($want.Values | ForEach-Object { $_ })
  Check 'C1 control: the markers hold FIX and REFUSE overloaded-operand' (($flat -contains 'FIX') -and ($flat -contains 'REFUSE overloaded-operand')) ($flat -join ' ')
  $got = @{}
  foreach ($f in $plan.fixes) { if ((Split-Path $f.file -Leaf) -eq 'Gx.dpr') { $got[[int]$f.line] = @($got[[int]$f.line]) + 'FIX' | Where-Object { $_ } } }
  foreach ($f in $plan.refused) { if ((Split-Path $f.file -Leaf) -eq 'Gx.dpr') { $got[[int]$f.line] = @($got[[int]$f.line]) + "REFUSE $($f.kind)" | Where-Object { $_ } } }
  $bad = @()
  foreach ($k in $want.Keys) {
    $w = @($want[$k]) -join ','
    $g = if ($got.ContainsKey($k)) { @($got[$k]) -join ',' } else { '' }
    if ($w -cne $g) { $bad += "line ${k}: want [$w] got [$g]" }
  }
  foreach ($k in $got.Keys) { if (-not $want.ContainsKey($k)) { $bad += "line ${k}: unmarked [$(@($got[$k]) -join ',')]" } }
  Check 'D1 every .dpr cast line gets the marked outcome (GxOv(1) is REFUSE overloaded-operand)' ($bad.Count -eq 0) ("`n    " + ($bad -join "`n    "))

  # ---- symbol shape on a generated unit ----------------------------------------------------------
  Write-Host 'implementation-only overload twins vs the dedup'
  $u = Join-Path $Tmp 'unit'
  [IO.Directory]::CreateDirectory($u) | Out-Null
  $src = @(
    'unit OvU;', '', 'interface', '',
    'procedure IntOnly;', 'function IntOv(pAt: Integer): Integer; overload;', 'function IntOv(const pAt: string): Integer; overload;', '',
    'implementation', '',
    'procedure Fw; forward;', '',
    'function IOv(pAt: Integer): Integer; overload;', 'begin', '  Result:= pAt;', 'end;', '',
    'function IOv(const pAt: string): Integer; overload;', 'begin', '  Result:= Length(pAt);', 'end;', '',
    'procedure Fw;', 'begin', 'end;', '',
    'procedure IntOnly;', 'begin', 'end;', '',
    'function IntOv(pAt: Integer): Integer;', 'begin', '  Result:= pAt;', 'end;', '',
    'function IntOv(const pAt: string): Integer;', 'begin', '  Result:= Length(pAt);', 'end;', '',
    'procedure Outer;', '  procedure Nest;', '  begin', '  end;', 'begin', '  Nest;', 'end;', '',
    'procedure Nest;', 'begin', 'end;', '',
    'end.')
  [IO.File]::WriteAllText((Join-Path $u 'OvU.pas'), (($src -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $udb = Join-Path $u 'u.sqlite'
  & $Exe index $u --db $udb --library-db none *> (Join-Path $Tmp 'unit.index.log')
  Check 'I2 index of the generated unit exits 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $rows = Sql-Rows $udb "SELECT s.name, s.start_line AS line, p.kind AS pkind FROM symbols s JOIN symbols p ON p.id = s.parent_id WHERE s.kind IN ('procedure', 'function')"
  function Count-Of([string]$Name) { return @($rows | Where-Object { $_.name -eq $Name }).Count }
  Check 'S2 impl-only overload twins IOv are two symbols' ((Count-Of 'IOv') -eq 2) "got $(Count-Of 'IOv')"
  Check 'S3 a forward declaration + its body stay ONE symbol (Fw)' ((Count-Of 'Fw') -eq 1) "got $(Count-Of 'Fw')"
  Check 'S4 interface declarations + their bodies stay one symbol each (IntOnly 1, IntOv 2)' (((Count-Of 'IntOnly') -eq 1) -and ((Count-Of 'IntOv') -eq 2)) "got IntOnly=$(Count-Of 'IntOnly') IntOv=$(Count-Of 'IntOv')"
  $nest = @($rows | Where-Object { $_.name -eq 'Nest' })
  Check 'S5 a free Nest after a nested Nest is its own symbol (parents: routine + unit)' (($nest.Count -eq 2) -and (@($nest | Where-Object { $_.pkind -eq 'unit' }).Count -eq 1)) "got $($nest.Count): $(($nest | ForEach-Object { $_.pkind }) -join ',')"
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "  note: temp left at $Tmp" }
}
if ($script:Failed) { Write-Host 'run_redcast_dpr: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_redcast_dpr: PASS'
exit 0
