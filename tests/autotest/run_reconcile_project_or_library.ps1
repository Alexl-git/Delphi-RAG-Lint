<#
  run_reconcile_project_or_library.ps1 -- T-22 owner ruling 1 (2026-10-25):
  every unit a project USES that is neither IN THE PROJECT nor IN THE LIBRARY
  is listed, judged, and fixable two ways.

  WHAT THE RULING ASKS
  --------------------
  * list every used unit that is neither a project member nor in the library;
  * offer two fixes: DEFAULT add the unit to the project (.dpr + .dproj),
    ALTERNATIVE add its folder to the library;
  * judge each one: a unit under the project's own roots is a missed PROJECT
    unit, anything else is third-party and belongs in the LIBRARY;
  * be part of lint-all (rule `unit-not-in-library`, the third-party half --
    the own-roots half is unit-not-in-dpr's third direction, unchanged).

  "IN THE LIBRARY" = under a registry library path (as before) OR under a folder
  the manifest's library section lists in "include" (new). The alternative fix
  WRITES that "include" entry, so the next run no longer reports the unit.

  FIXTURE (built here, under a scratch folder of this runner's own):
      repo\proj\App.dpr/.dproj   uses uMain; search path reaches the three below
      repo\proj\_D-RAG\drag-lint-project.json   ownRoots [".."]  (= repo)
      repo\common\uOwn.pas       ours          -> project
      vendor\VendorUnit.pas      third-party   -> library
      libvendor\LibUnit.pas      third-party, but its folder is in the manifest
                                 library "include" -> NOT reported at all
  POSITIVE CONTROL: the same run against a manifest WITHOUT that include must
  report LibUnit -- otherwise "LibUnit is absent" proves nothing.

  Usage: pwsh -File tests\autotest\run_reconcile_project_or_library.ps1
#>
try {
$Exe = . "$PSScriptRoot\_manifest_common.ps1"

$work = "$env:TEMP\drag-lint-reconcile-ownlib-$PID"
if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }

function W([string]$Path, [string]$Text) {
  $dir = Split-Path $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

$proj   = "$work\repo\proj"
$dpr    = "$proj\App.dpr"
$dproj  = "$proj\App.dproj"
$vendor = "$work\vendor"
$libv   = "$work\libvendor"

W $dpr @'
program App;

uses
  uMain in 'uMain.pas';

begin
end.
'@
W $dproj @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <DCC_UnitSearchPath>..\common;..\..\vendor;..\..\libvendor</DCC_UnitSearchPath>
  </PropertyGroup>
  <ItemGroup>
    <DCCReference Include="uMain.pas"/>
  </ItemGroup>
</Project>
'@
W "$proj\uMain.pas" @'
unit uMain;

interface

uses
  uOwn, VendorUnit, LibUnit;

implementation

end.
'@
W "$work\repo\common\uOwn.pas"  "unit uOwn;`n`ninterface`n`nimplementation`n`nend.`n"
W "$vendor\VendorUnit.pas"       "unit VendorUnit;`n`ninterface`n`nimplementation`n`nend.`n"
W "$libv\LibUnit.pas"            "unit LibUnit;`n`ninterface`n`nimplementation`n`nend.`n"
W "$proj\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".."] }'

$libJson = ($libv -replace '\\', '\\')
$cfg     = "$work\.drag-lint.json"
$cfgNoLib = "$work\nolib\drag-lint.json"
W $cfg @"
{
  "_comment": "kept verbatim by the library write (SaveEdits)",
  "indexes": {
    "sections": [
      { "name": "Library", "source": "registry-libraries", "platforms": ["Win64"],
        "include": ["$libJson"] }
    ]
  }
}
"@
W $cfgNoLib @'
{
  "indexes": {
    "sections": [
      { "name": "Library", "source": "registry-libraries", "platforms": ["Win64"] }
    ]
  }
}
'@

function Missing($Doc, [string]$Unit) { @($Doc.missing | Where-Object { $_.unit -eq $Unit }) }

Write-Host '== reconcile-project: project unit or library unit (T-22) ==' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1 -- the JSON judges each MISSING unit
# ---------------------------------------------------------------------------
$raw = & $Exe reconcile-project $dproj --json --config $cfg 2>$null | Out-String
$doc = $null; try { $doc = $raw | ConvertFrom-Json } catch { $doc = $null }
Check '1a --json parses' ($null -ne $doc) "got:`n$raw"
$own = Missing $doc 'uOwn'
$ven = Missing $doc 'VendorUnit'
Check '1b uOwn is MISSING, owner=project, suggestedFix=project' `
  (($own.Count -eq 1) -and ($own[0].owner -eq 'project') -and ($own[0].suggestedFix -eq 'project')) `
  "got: $($own | ConvertTo-Json -Compress)"
Check '1c VendorUnit is MISSING, owner=third-party, suggestedFix=library' `
  (($ven.Count -eq 1) -and ($ven[0].owner -eq 'third-party') -and ($ven[0].suggestedFix -eq 'library')) `
  "got: $($ven | ConvertTo-Json -Compress)"
Check '1d VendorUnit carries the folder the library fix would add' `
  (($ven.Count -eq 1) -and ("$($ven[0].folder)".TrimEnd('\') -ieq $vendor)) `
  "got folder: $($ven[0].folder)"
Check '1e LibUnit is NOT reported (its folder is a manifest library include)' `
  ((Missing $doc 'LibUnit').Count -eq 0) "missing: $(($doc.missing | ForEach-Object unit) -join ', ')"

# 1f -- POSITIVE CONTROL for 1e.
$rawNo = & $Exe reconcile-project $dproj --json --config $cfgNoLib 2>$null | Out-String
$docNo = $null; try { $docNo = $rawNo | ConvertFrom-Json } catch { $docNo = $null }
$libNo = Missing $docNo 'LibUnit'
Check '1f control: WITHOUT the include, LibUnit IS reported as third-party' `
  (($libNo.Count -eq 1) -and ($libNo[0].suggestedFix -eq 'library')) `
  "missing: $(($docNo.missing | ForEach-Object unit) -join ', ')"

# ---------------------------------------------------------------------------
# 2 -- the text report says which fix each unit wants and prints both commands
# ---------------------------------------------------------------------------
$txt = & $Exe reconcile-project $dproj --config $cfg 2>&1 | Out-String
$venLine = ($txt -split "`r?`n" | Where-Object { $_ -match '^\s+VendorUnit ' }) -join ''
$ownLine = ($txt -split "`r?`n" | Where-Object { $_ -match '^\s+uOwn ' }) -join ''
Check '2a the VendorUnit line is marked third-party -> library' ($venLine -match 'third-party.*library') "line: $venLine"
Check '2b the uOwn line is marked project unit' ($ownLine -match 'project unit') "line: $ownLine"
Check '2c the report prints the library fix command for the third-party units' `
  ($txt -match '--only VendorUnit --apply --to library') "report:`n$txt"
Check '2d the report prints the default fix command for the project units' `
  ($txt -match '--only uOwn --apply(?! --to)') "report:`n$txt"

# ---------------------------------------------------------------------------
# 3 -- a bad --to value is refused before anything is written
# ---------------------------------------------------------------------------
& $Exe reconcile-project $dproj --apply --to nowhere --config $cfg 2>&1 | Out-Null
Check '3 --to <bogus> exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"

# ---------------------------------------------------------------------------
# 4 -- the ALTERNATIVE fix: --apply --to library writes the manifest, not the project
# ---------------------------------------------------------------------------
$dprBefore   = (Get-FileHash $dpr).Hash
$dprojBefore = (Get-FileHash $dproj).Hash
$rawLib = & $Exe reconcile-project $dproj --only VendorUnit --apply --to library --json --config $cfg 2>$null | Out-String
$exitLib = $LASTEXITCODE
$docLib = $null; try { $docLib = $rawLib | ConvertFrom-Json } catch { $docLib = $null }
Check '4a exit 0 and applied=true' (($exitLib -eq 0) -and ($docLib.applied -eq $true)) "exit=$exitLib; got:`n$rawLib"
$cfgDoc = Get-Content $cfg -Raw | ConvertFrom-Json
$incl = @($cfgDoc.indexes.sections | Where-Object { $_.name -eq 'Library' } | ForEach-Object { $_.include })
Check '4b the vendor folder is now in the Library section include' `
  (@($incl | Where-Object { "$_".TrimEnd('\') -ieq $vendor }).Count -eq 1) "include: $($incl -join ' | ')"
Check '4c the existing include and the unmodelled _comment survived' `
  ((@($incl | Where-Object { $_ -ieq $libv }).Count -eq 1) -and ($cfgDoc._comment -match 'verbatim')) "cfg:`n$(Get-Content $cfg -Raw)"
Check '4d a .bak of the manifest was taken and is named in backups' `
  ((Test-Path "$cfg.bak") -and (@($docLib.backups) -contains "$cfg.bak")) "backups: $($docLib.backups -join ', ')"
Check '4e edited names the manifest' (@($docLib.edited) -contains $cfg) "edited: $($docLib.edited -join ', ')"
Check '4f the project files were NOT touched' `
  (((Get-FileHash $dpr).Hash -eq $dprBefore) -and ((Get-FileHash $dproj).Hash -eq $dprojBefore)) 'dpr/dproj changed'

$raw2 = & $Exe reconcile-project $dproj --json --config $cfg 2>$null | Out-String
$doc2 = $null; try { $doc2 = $raw2 | ConvertFrom-Json } catch { $doc2 = $null }
Check '4g rescan: VendorUnit is no longer reported, uOwn still is' `
  (((Missing $doc2 'VendorUnit').Count -eq 0) -and ((Missing $doc2 'uOwn').Count -eq 1)) `
  "missing: $(($doc2.missing | ForEach-Object unit) -join ', ')"

# ---------------------------------------------------------------------------
# 5 -- the DEFAULT fix is unchanged: --apply adds the unit to the project
# ---------------------------------------------------------------------------
& $Exe reconcile-project $dproj --only uOwn --apply --config $cfg 2>&1 | Out-Null
Check '5a --apply (no --to) adds uOwn to the .dpr' ((Get-Content $dpr -Raw) -match 'uOwn') (Get-Content $dpr -Raw)
Check '5b and to the .dproj' ((Get-Content $dproj -Raw) -match 'uOwn\.pas') ''

# ---------------------------------------------------------------------------
# 6 -- lint: unit-not-in-library (the lint-all half of the feature)
# ---------------------------------------------------------------------------
# Fresh project files (5 added uOwn) and the no-include manifest as the LOCAL
# .drag-lint.json the cwd walk finds, so lint sees LibUnit AND VendorUnit.
W $dpr "program App;`n`nuses`n  uMain in 'uMain.pas';`n`nbegin`nend.`n"
Copy-Item $cfgNoLib $cfg -Force
Push-Location $proj
try {
  $lint = (& $Exe lint --project $dproj --rule unit-not-in-library 2>&1) -join "`n"
  $db = "$work\app.sqlite"
  & $Exe index --project $dproj --db $db 2>&1 | Out-Null
  $la = (& $Exe lint-all --db $db --project $dproj --rule unit-not-in-library 2>&1) -join "`n"
} finally { Pop-Location }
Check '6a lint --project reports VendorUnit' ($lint -match 'unit-not-in-library' -and $lint -match 'VendorUnit') "got:`n$lint"
Check '6b and LibUnit (no include in this manifest)' ($lint -match 'LibUnit') "got:`n$lint"
Check '6c and NOT uOwn (ours: that is unit-not-in-dpr''s job)' ($lint -notmatch '"uOwn"') "got:`n$lint"
Check '6d lint-all reports the same third-party units' `
  (($la -match 'unit-not-in-library') -and ($la -match 'VendorUnit') -and ($la -match 'LibUnit') -and ($la -notmatch '"uOwn"')) "got:`n$la"
Check '6e the finding names the library fix command' ($lint -match '--apply --to library') "got:`n$lint"

# ---------------------------------------------------------------------------
# 7 -- `index --all` walks a library "include" folder as a library root, so the
#      folder the library fix writes is actually indexed with the library.
#      Measured on the pre-change engine: 148 roots with AND without the include.
# ---------------------------------------------------------------------------
$planInc = "$work\plan-inc.json"
$planNo  = "$work\plan-no.json"
$outJson = ($work -replace '\\', '\\')
W $planInc "{ `"indexes`": { `"outDir`": `"$outJson`", `"sections`": [ { `"name`": `"Library`", `"source`": `"registry-libraries`", `"platforms`": [`"Win64`"], `"include`": [`"$libJson`"] } ] } }"
W $planNo  "{ `"indexes`": { `"outDir`": `"$outJson`", `"sections`": [ { `"name`": `"Library`", `"source`": `"registry-libraries`", `"platforms`": [`"Win64`"] } ] } }"
$rcInc = $null; $rcNo = $null
try { $rcInc = (& $Exe index --all --dry-run --json --config $planInc 2>$null | Out-String | ConvertFrom-Json).sections[0].rootsCount } catch { }
try { $rcNo  = (& $Exe index --all --dry-run --json --config $planNo  2>$null | Out-String | ConvertFrom-Json).sections[0].rootsCount } catch { }
Check '7 a library include adds exactly one library root to the plan' `
  (($null -ne $rcInc) -and ($null -ne $rcNo) -and ($rcInc -eq $rcNo + 1)) "with include=$rcInc without=$rcNo"

if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
if ($script:Failed) { exit 1 } else { exit 0 }
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
