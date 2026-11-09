<#
  run_file_facts_149.ps1 -- wave 149 lane EX2: the schema v24 file-fact tables
  (file_includes, dfm_objects, pp_regions) and the `uses <$I x.inc>` uses-list
  include (F4: the entries and the closing semicolon live in the include).

  Indexes tests\fixtures\file-facts-149\facts and \control into scratch DBs
  under $env:TEMP and checks, through `sql --json` (rows are POSITIONAL arrays;
  mapped onto columns[].name below):
    F4  FfIncA's uses edge to FfIncB is taken from FfIncUses.inc (origin_path),
        no garbage entry (`type`, `TFfIncA`) and no DLINC placeholder survives,
        TFfIncA is extracted, `cycles` sees FfIncA <-> FfIncB; the comma case
        (FfComma: `FfIncB, <$I FfCommaMid.inc> FfRegions;`) keeps all three;
        file_includes rows carry section / in_uses / depth.
    F5  dfm_objects: name, class, parent, kind, depth, and symbol_id joins the
        block's symbol by name (contract with lane DF).
    F6  pp_regions: every branch of FfRegions.pas with its active flag.
    CONTROL  a project with none of the constructs writes 0 rows in all three.
  Positive control: run with -Exe <a 1.48 engine> -- every F4/F5/F6 check FAILS
  (no tables, the uses clause swallows `type`).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_file_facts_149: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_file_facts_149: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fx      = Join-Path $repo 'tests\fixtures\file-facts-149'
$work    = Join-Path $env:TEMP ('dl-file-facts-149-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$dbFacts = Join-Path $work 'facts.sqlite'
$dbCtl   = Join-Path $work 'control.sqlite'

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name). A failed query
# (e.g. no such table on an older engine) returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query) {
  $raw = & $Exe sql --query $Query --db $Db --json 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()   # callers wrap in @(); 0 rows -> nothing -> @()
}

Write-Host "run_file_facts_149: engine $Exe" -ForegroundColor Cyan
& $Exe index (Join-Path $fx 'facts')   --db $dbFacts *> (Join-Path $work 'index-facts.log')
& $Exe index (Join-Path $fx 'control') --db $dbCtl   *> (Join-Path $work 'index-control.log')

$ver = @(Lane-Sql $dbFacts "SELECT value FROM schema_meta WHERE key = 'schema_version'")
Check 'schema_version is 24' (($ver.Count -eq 1) -and ($ver[0].value -eq '24')) "($($ver | ForEach-Object value))"

# ---- F4 ---------------------------------------------------------------------
$usesA = @(Lane-Sql $dbFacts "SELECT u.unit_name, u.section, u.origin_path FROM unit_uses u JOIN files f ON f.id = u.file_id WHERE f.path LIKE '%\FfIncA.pas' ORDER BY u.start_line")
Check 'F4 FfIncA uses exactly FfIncB' (($usesA.Count -eq 1) -and ($usesA[0].unit_name -eq 'FfIncB')) "($(($usesA | ForEach-Object unit_name) -join ','))"
Check 'F4 the edge comes from FfIncUses.inc, interface' (($usesA.Count -eq 1) -and ("$($usesA[0].origin_path)" -like '*\FfIncUses.inc') -and ($usesA[0].section -eq 'interface')) ''
$junk = @(Lane-Sql $dbFacts "SELECT unit_name FROM unit_uses WHERE unit_name IN ('type', 'TFfIncA', 'TFfComma') OR unit_name LIKE 'DLINC%'")
Check 'F4 no swallowed section, no placeholder entry' ($junk.Count -eq 0) "($(($junk | ForEach-Object unit_name) -join ','))"
$cls = @(Lane-Sql $dbFacts "SELECT name FROM symbols WHERE name IN ('TFfIncA', 'TFfComma') AND kind = 'class'")
Check 'F4 the host sections after the uses clause are extracted' ($cls.Count -eq 2) "($(($cls | ForEach-Object name) -join ','))"
$usesC = @(Lane-Sql $dbFacts "SELECT u.unit_name FROM unit_uses u JOIN files f ON f.id = u.file_id WHERE f.path LIKE '%\FfComma.pas' ORDER BY u.unit_name")
Check 'F4 comma case keeps FfIncA (include), FfIncB, FfRegions' ((($usesC | ForEach-Object unit_name) -join ',') -eq 'FfIncA,FfIncB,FfRegions') "($(($usesC | ForEach-Object unit_name) -join ','))"
$incA = @(Lane-Sql $dbFacts "SELECT i.inc_path, i.section, i.in_uses, i.depth, i.host_line FROM file_includes i JOIN files f ON f.id = i.file_id WHERE f.path LIKE '%\FfIncA.pas' ORDER BY i.ordinal")
Check 'F4 file_includes: FfIncA has 2 rows' ($incA.Count -eq 2) "($($incA.Count))"
if ($incA.Count -eq 2) {
  Check 'F4 file_includes: uses-list include = interface, in_uses 1, line 6' (("$($incA[0].inc_path)" -like '*\FfIncUses.inc') -and ($incA[0].section -eq 'interface') -and ($incA[0].in_uses -eq 1) -and ($incA[0].host_line -eq 6) -and ($incA[0].depth -eq 0)) ''
  Check 'F4 file_includes: defines include = implementation, in_uses 0' (("$($incA[1].inc_path)" -like '*\FfDefs.inc') -and ($incA[1].section -eq 'implementation') -and ($incA[1].in_uses -eq 0)) ''
}
$cyc = (& $Exe cycles --db $dbFacts 2>&1) -join "`n"
Check 'F4 cycles sees FfIncA <-> FfIncB' (($cyc -match '(?i)ffinca') -and ($cyc -match '(?i)ffincb')) ''

# ---- F5 ---------------------------------------------------------------------
$dfm = @(Lane-Sql $dbFacts "SELECT o.name, o.class_name, o.parent_name, o.obj_kind, o.depth, s.name AS sym_name FROM dfm_objects o JOIN files f ON f.id = o.file_id LEFT JOIN symbols s ON s.id = o.symbol_id WHERE f.path LIKE '%\FfForm.dfm' ORDER BY o.ordinal")
$dfmText = ($dfm | ForEach-Object { "$($_.name):$($_.class_name):$($_.parent_name):$($_.obj_kind):$($_.depth)" }) -join ' '
Check 'F5 dfm_objects of FfForm.dfm' ($dfmText -eq 'FfForm:TFfForm::object:0 Panel1:TPanel:FfForm:object:1 Button1:TButton:Panel1:object:2 Frame1:TFfFrame:FfForm:inline:1') "($dfmText)"
Check 'F5 symbol_id joins the block symbol by name' (($dfm.Count -eq 4) -and (@($dfm | Where-Object { $_.sym_name -ne $_.name }).Count -eq 0)) ''
$inh = @(Lane-Sql $dbFacts "SELECT o.obj_kind FROM dfm_objects o JOIN files f ON f.id = o.file_id WHERE f.path LIKE '%\FfInh.dfm' ORDER BY o.ordinal")
Check 'F5 inherited blocks' ((($inh | ForEach-Object obj_kind) -join ',') -eq 'inherited,inherited') ''

# ---- F6 ---------------------------------------------------------------------
$pp = @(Lane-Sql $dbFacts "SELECT r.region, r.branch, r.parent, r.directive, r.condition, r.start_line, r.end_line, r.active FROM pp_regions r JOIN files f ON f.id = r.file_id WHERE f.path LIKE '%\FfRegions.pas' ORDER BY r.region, r.branch")
$ppText = ($pp | ForEach-Object { "$($_.region).$($_.branch)/$($_.parent):$($_.directive)($($_.condition))$($_.start_line)-$($_.end_line)=$($_.active)" }) -join ' '
Check 'F6 pp_regions of FfRegions.pas' ($ppText -eq '0.0/-1:ifdef(FF_ON)6-13=1 0.1/-1:else()13-15=0 1.0/0:ifdef(FF_OFF)8-10=0 1.1/0:else()10-12=1 2.0/-1:if(FF_UNDEFINED_NAME)16-18=0 2.1/-1:elseif(Defined(FF_ON))18-20=1') "($ppText)"

# ---- CONTROL ----------------------------------------------------------------
$files = @(Lane-Sql $dbCtl "SELECT COUNT(*) AS n FROM files")
Check 'CONTROL the control project was indexed' (($files.Count -eq 1) -and ($files[0].n -ge 1)) ''
foreach ($t in 'file_includes', 'dfm_objects', 'pp_regions') {
  $n = @(Lane-Sql $dbCtl "SELECT COUNT(*) AS n FROM $t")
  Check "CONTROL $t has 0 rows" (($n.Count -eq 1) -and ($n[0].n -eq 0)) "($(if ($n.Count) { $n[0].n } else { 'no table' }))"
}

try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (scratch $work left: $($_.Exception.Message))" }
Write-Host ("run_file_facts_149: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
