<#
  run_v156_SBOM1.ps1 -- 1.56 lane SBOM-1 (G-49, v1 slice): `drag-lint sbom --project X.dproj [--out F]`.

  The verb writes a CycloneDX 1.6 JSON document from the compile closure: one component per unit group,
  attributed by the library catalogue rules\sbom-libraries.json; a group with no catalogue row is listed
  with the supplier "unknown supplier", never dropped. v1 = source closure only: --map, --bsi and VEX are
  NOT registered (owner ruling Q2) and the document says so itself.

  FIXTURE tests\fixtures\sbom (all text; nothing compiles at test time):
    proj\app\SbomApp.dproj + .dpr + AppMain.pas   the project (first-party: under the project folder)
    proj\shared\SharedUnit.pas                    outside the folder, a .dproj member: first-party
    proj\vendor\VendUnit.pas                      in the project index, no member, no row: unknown directory
    libs\Embarcadero\Studio\37.0\source\rtl\...   System.FixRtl: catalogue row embarcadero-rtl, version from the path
    libs\Spring4D\...\Spring.FixBase.pas          reached ONLY through AcmeCore (the transitive walk)
    libs\AcmeWidgets\AcmeGrid.pas, AcmeCore.pas   a library with source and no catalogue row
    NoSrcLib, cxFixSourceless                     named in AppMain, no source anywhere
    catalogue\acme.json, bad.json                 --catalogue runs;  delivered\SbomApp.exe.txt  --exe run
  proj\ is indexed into a scratch PROJECT index, libs\ into a scratch LIBRARY index.

  RED on the base (lane/v156-w2base 8b4a8ffe2): the verb is a scaffold, exit 2 "not built in this engine yet".

  POSITIVE CONTROLS: P1 `--library-db none` loses Spring4D and turns the Acme units sourceless (the walk
  and the library index are live); P2 another --catalogue changes supplier / version and folds a
  firstParty row into the application (the catalogue is what attributes); P3 --exe / --app-version;
  P4 --out; P5 refusals incl. --map and --bsi (exit 3: not registered); P6 the project index is not written.

  SCHEMA: the document of run 1 is validated with Test-Json against the CycloneDX 1.6 schema vendored in
  tests\fixtures\sbom\schema (bom-1.6.schema.json + spdx.schema.json, Apache-2.0, unchanged). Its two
  external references are resolved in a scratch copy. Two controls prove the schema can fail. Under
  Windows PowerShell 5 (no Test-Json -SchemaFile) the runner falls back to the required-key check and says so.
  Run under pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-sbom1-$PID",
  [string]$Schema  = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot empty inside an advanced script's param block.
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $Schema) { $Schema = "$PSScriptRoot\..\fixtures\sbom\schema" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\sbom").Path
[void](New-Item -ItemType Directory -Force $WorkDir)
$ProjDb  = Join-Path $WorkDir 'proj.sqlite'
$LibDb   = Join-Path $WorkDir 'lib.sqlite'
$ErrFile = Join-Path $WorkDir 'stderr.txt'
$Dproj   = Join-Path $Fix 'proj\app\SbomApp.dproj'
$Deliv   = Join-Path $Fix 'delivered\SbomApp.exe.txt'

function Run([string[]]$a) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>$ErrFile } | Out-String
  $code = $LASTEXITCODE
  $err = if (Test-Path $ErrFile) { [IO.File]::ReadAllText($ErrFile) } else { '' }
  [pscustomobject]@{ Code = $code; Out = $out; Err = $err }
}
function Doc($r) {
  $j = $null
  try { $j = $r.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  $j
}
function Refs($j)        { @($j.components | ForEach-Object { $_.'bom-ref' }) | Sort-Object }
function Comp($j, $ref)  { @($j.components) | Where-Object { $_.'bom-ref' -eq $ref } }
function PropVals($c, $name) { @($c.properties | Where-Object name -eq "drag-lint:$name" | ForEach-Object { $_.value }) }
function Deps($j, $ref)  { @((@($j.dependencies) | Where-Object ref -eq $ref).dependsOn) | Sort-Object }
function Same($a, $b)    { (@($a) -join '|') -eq (@($b) -join '|') }

Write-Host '-- setup: index the project and the library fixture into scratch indexes' -ForegroundColor Cyan
$r = Run @('index', (Join-Path $Fix 'proj'), '--db', $ProjDb)
Check 'setup: project fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index', (Join-Path $Fix 'libs'), '--db', $LibDb)
Check 'setup: library fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$hashBefore = (Get-FileHash -Algorithm SHA256 $ProjDb).Hash

$RefRtl = 'lib:embarcadero-rtl'; $RefSpring = 'lib:spring4d'; $RefDx = 'lib:devexpress-vcl'
$RefAcme = 'unknown-dir:libs/AcmeWidgets'; $RefVendor = 'unknown-dir:proj/vendor'; $RefNoSrc = 'unknown-unit:NoSrcLib'
$RefApp = 'app:SbomApp'

Write-Host '-- 1: the document (project index + library index, shipped catalogue)' -ForegroundColor Cyan
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb)
Check '1 exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Err)"
$j = Doc $r
Check '1 stdout parses as JSON' ($null -ne $j)
if ($j) {
  Check '1 bomFormat CycloneDX' ($j.bomFormat -ceq 'CycloneDX') "$($j.bomFormat)"
  Check '1 specVersion 1.6' ($j.specVersion -ceq '1.6') "$($j.specVersion)"
  Check '1 serialNumber is urn:uuid' ($j.serialNumber -cmatch '^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') "$($j.serialNumber)"
  Check '1 version 1' ($j.version -eq 1) "$($j.version)"
  $ts = $j.metadata.timestamp
  if ($ts -is [datetime]) { $ts = $ts.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") }
  Check '1 metadata.timestamp is ISO 8601 UTC' ("$ts" -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$') "$ts"
  Check '1 metadata.tools names drag-lint with a version' (($j.metadata.tools.components[0].name -eq 'drag-lint') -and ($j.metadata.tools.components[0].version -match '^\d+\.\d+')) "$($j.metadata.tools.components[0].version)"
  $app = $j.metadata.component
  Check '1 metadata.component is the application' (($app.type -eq 'application') -and ($app.name -eq 'SbomApp') -and ($app.'bom-ref' -eq $RefApp)) "$($app.type) $($app.name) $($app.'bom-ref')"
  Check '1 no version and no hash invented for the application' (($null -eq $app.version) -and ($null -eq $app.hashes))
  Check '1 application units = AppMain, SbomApp, SharedUnit' (Same (PropVals $app 'unit') @('AppMain', 'SbomApp', 'SharedUnit')) "$(PropVals $app 'unit')"
  Check '1 lifecycle pre-build' ($j.metadata.lifecycles[0].phase -eq 'pre-build')
  Check '1 metadata says v1 / no MAP input' (((PropVals $j.metadata 'sbom:slice') -eq 'v1') -and ("$(PropVals $j.metadata 'sbom:scope')" -match 'no MAP input'))
  Check '1 metadata says the library index was read' ("$(PropVals $j.metadata 'sbom:libraryIndex')" -like 'read*')
  Check '1 compositions: incomplete' (($j.compositions[0].aggregate -eq 'incomplete') -and (@($j.compositions[0].assemblies) -contains $RefApp))

  $want = @($RefDx, $RefRtl, $RefSpring, $RefAcme, $RefVendor, $RefNoSrc) | Sort-Object
  Check '1 one component per unit group (6)' (Same (Refs $j) $want) "$(Refs $j)"
  $bad = @($j.components | Where-Object { -not ($_.type -eq 'library' -and $_.name -and $_.'bom-ref' -and $_.supplier.name) })
  Check '1 required keys on every component (type, name, bom-ref, supplier.name)' ($bad.Count -eq 0) "$($bad.Count) bad"

  $rtl = Comp $j $RefRtl
  Check '1 RTL: supplier from the catalogue' ($rtl.supplier.name -like 'Embarcadero*') "$($rtl.supplier.name)"
  Check '1 RTL: version 37.0 read from the path' ($rtl.version -ceq '37.0') "$($rtl.version)"
  Check '1 RTL: System.FixRtl (bare FixRtl + unit scope) and the implicit System, SysInit' (Same (PropVals $rtl 'unit') @('SysInit', 'System', 'System.FixRtl')) "$(PropVals $rtl 'unit')"
  Check '1 RTL: mixed evidence, path+unit-name attribution' (((PropVals $rtl 'evidence') -eq 'mixed') -and ((PropVals $rtl 'attribution') -eq 'path+unit-name')) "$(PropVals $rtl 'evidence') $(PropVals $rtl 'attribution')"
  Check '1 RTL: licence by name' ($rtl.licenses[0].license.name -like 'Embarcadero*')

  $spr = Comp $j $RefSpring
  Check '1 Spring4D: present though the project never names it (transitive)' ($null -ne $spr)
  Check '1 Spring4D: SPDX id + purl + path attribution' (($spr.licenses[0].license.id -ceq 'Apache-2.0') -and ($spr.purl -like 'pkg:*') -and ((PropVals $spr 'attribution') -eq 'path'))
  Check '1 Spring4D: no version claimed' ($null -eq $spr.version)

  $dx = Comp $j $RefDx
  Check '1 sourceless cxFixSourceless attributed by NAME, said so' (((PropVals $dx 'attribution') -eq 'unit-name') -and ((PropVals $dx 'evidence') -eq 'sourceless') -and (Same (PropVals $dx 'unit') @('cxFixSourceless')))

  $acme = Comp $j $RefAcme
  Check '1 library root with no catalogue row: listed, "unknown supplier"' ($acme.supplier.name -ceq 'unknown supplier') "$($acme.supplier.name)"
  Check '1 unknown root: both units, no version, no licence' ((Same (PropVals $acme 'unit') @('AcmeCore', 'AcmeGrid')) -and ($null -eq $acme.version) -and ($null -eq $acme.licenses)) "$(PropVals $acme 'unit')"
  Check '1 unknown root: unitCount = 2' ((PropVals $acme 'unitCount') -eq '2')
  Check '1 project-index unit outside the project, no row: unknown directory' ((Comp $j $RefVendor).supplier.name -ceq 'unknown supplier')
  Check '1 unit with no source and no row: its own unknown component' (((Comp $j $RefNoSrc).supplier.name -ceq 'unknown supplier') -and ((PropVals (Comp $j $RefNoSrc) 'evidence') -eq 'sourceless'))

  Check '1 dependencies: one entry per component + the application (7)' (@($j.dependencies).Count -eq 7) "$(@($j.dependencies).Count)"
  Check '1 application depends on what it names, not on Spring4D' (Same (Deps $j $RefApp) (@($RefDx, $RefRtl, $RefAcme, $RefVendor, $RefNoSrc) | Sort-Object)) "$(Deps $j $RefApp)"
  Check '1 Acme -> Spring4D + RTL' (Same (Deps $j $RefAcme) (@($RefRtl, $RefSpring) | Sort-Object)) "$(Deps $j $RefAcme)"
  Check '1 Spring4D -> RTL' (Same (Deps $j $RefSpring) @($RefRtl)) "$(Deps $j $RefSpring)"
  Check '1 RTL depends on nothing' (@(Deps $j $RefRtl | Where-Object { $_ }).Count -eq 0)
  $all = @(Refs $j) + $RefApp
  $dangling = @($j.dependencies | ForEach-Object { $_.ref; $_.dependsOn } | Where-Object { $_ -and ($all -notcontains $_) })
  Check '1 every dependency ref is a bom-ref of the document' ($dangling.Count -eq 0) "$dangling"
  Check '1 stderr names every component without a catalogue row' (($r.Err -match 'AcmeWidgets') -and ($r.Err -match 'NoSrcLib') -and ($r.Err -match 'vendor')) $r.Err

  # SCHEMA: the vendored CycloneDX 1.6 schema, with its two external references resolved in a scratch copy
  # (the SPDX id list inlined, the JSF signature reference replaced: drag-lint writes no signature).
  if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue) -or ($PSVersionTable.PSVersion.Major -lt 7)) {
    Write-Host '  [NOTE] Test-Json with -SchemaFile needs pwsh 7: required-key check only in this shell' -ForegroundColor Yellow
  } else {
    $bundle = Join-Path $WorkDir 'bom-1.6.bundled.schema.json'
    $spdx = [IO.File]::ReadAllText((Join-Path $Schema 'spdx.schema.json')) | ConvertFrom-Json
    $enum = '"type": "string", "enum": ' + (ConvertTo-Json @($spdx.enum) -Compress)
    $text = [IO.File]::ReadAllText((Join-Path $Schema 'bom-1.6.schema.json'))
    $text = $text.Replace('"$ref": "spdx.schema.json"', $enum).Replace('"$ref": "jsf-0.82.schema.json#/definitions/signature"', '"type": "object"')
    [IO.File]::WriteAllText($bundle, $text)
    Check '1 SCHEMA setup: both external references were replaced' (($text -notmatch 'spdx\.schema\.json"') -and ($text -notmatch 'jsf-0\.82\.schema\.json#'))
    $ok = $false
    try { $ok = Test-Json -Json $r.Out -SchemaFile $bundle -ErrorAction Stop } catch { Write-Host "    schema: $_" }
    Check '1 SCHEMA: the document is valid against the vendored CycloneDX 1.6 schema' $ok
    # positive control: the same schema must REJECT a broken document (else the check above proves nothing)
    $broken = $r.Out.Replace('"bomFormat": "CycloneDX"', '"bomFormat": "SomethingElse"')
    $rej = $true
    try { $rej = -not (Test-Json -Json $broken -SchemaFile $bundle -ErrorAction SilentlyContinue) } catch { $rej = $true }
    Check '1 SCHEMA control: a document with another bomFormat is rejected' ($rej -and ($broken -ne $r.Out))
    $broken2 = $r.Out.Replace('"id": "Apache-2.0"', '"id": "Not-A-Licence-Id"')
    $rej2 = $true
    try { $rej2 = -not (Test-Json -Json $broken2 -SchemaFile $bundle -ErrorAction SilentlyContinue) } catch { $rej2 = $true }
    Check '1 SCHEMA control: an unknown SPDX licence id is rejected (the inlined list is live)' ($rej2 -and ($broken2 -ne $r.Out))
  }
}

Write-Host '-- P1: positive control, --library-db none' -ForegroundColor Cyan
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', 'none')
$j1 = Doc $r
Check 'P1 exit 0, parses' (($r.Code -eq 0) -and $j1) "exit $($r.Code)"
if ($j1) {
  Check 'P1 Spring4D is gone (nothing walked the library)' ($null -eq (Comp $j1 $RefSpring))
  Check 'P1 AcmeGrid is a unit without source now' ($null -ne (Comp $j1 'unknown-unit:AcmeGrid')) "$(Refs $j1)"
  Check 'P1 bare FixRtl stays unresolved, listed as unknown' ($null -ne (Comp $j1 'unknown-unit:FixRtl')) "$(Refs $j1)"
  Check 'P1 the document says no library index was read' ("$(PropVals $j1.metadata 'sbom:libraryIndex')" -like 'none*')
  Check 'P1 stderr NOTE: no library index' ($r.Err -match 'no library index was read')
}

Write-Host '-- P2: positive control, another --catalogue' -ForegroundColor Cyan
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb, '--catalogue', (Join-Path $Fix 'catalogue\acme.json'))
$j2 = Doc $r
Check 'P2 exit 0, parses' (($r.Code -eq 0) -and $j2) "exit $($r.Code) $($r.Err)"
if ($j2) {
  $a2 = Comp $j2 'lib:acme'
  Check 'P2 Acme row: supplier, fixed version, licence name' (($a2.supplier.name -ceq 'Acme GmbH') -and ($a2.version -ceq '4.2') -and ($a2.licenses[0].license.name -ceq 'Acme EULA')) "$($a2.supplier.name) $($a2.version)"
  Check 'P2 firstParty row folds proj\vendor into the application' (($null -eq (Comp $j2 $RefVendor)) -and (@(PropVals $j2.metadata.component 'unit') -contains 'VendUnit')) "$(PropVals $j2.metadata.component 'unit')"
  Check 'P2 without its row the RTL directory is unknown, not dropped' (($null -eq (Comp $j2 $RefRtl)) -and ((Comp $j2 'unknown-dir:rtl/common').supplier.name -ceq 'unknown supplier')) "$(Refs $j2)"
}

Write-Host '-- P3: --exe and --app-version' -ForegroundColor Cyan
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb, '--exe', $Deliv, '--app-version', '1.2.3')
$j3 = Doc $r
Check 'P3 exit 0, parses' (($r.Code -eq 0) -and $j3) "exit $($r.Code) $($r.Err)"
if ($j3) {
  $sha = (Get-FileHash -Algorithm SHA512 $Deliv).Hash.ToLowerInvariant()
  $h = $j3.metadata.component.hashes
  Check 'P3 SHA-512 of the delivered file' ((@($h).Count -eq 1) -and ($h[0].alg -ceq 'SHA-512') -and ($h[0].content -ceq $sha)) "$($h[0].content)"
  Check 'P3 the hashed file is named' ((PropVals $j3.metadata.component 'hashedFile') -eq 'SbomApp.exe.txt')
  Check 'P3 application version as given' ($j3.metadata.component.version -ceq '1.2.3')
}
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb, '--exe', (Join-Path $WorkDir 'no-such.exe'))
Check 'P3 a missing --exe is a failure with no document' (($r.Code -eq 1) -and ($r.Out.Trim() -eq '') -and ($r.Err -match 'not found')) "exit $($r.Code)"

Write-Host '-- P4: --out' -ForegroundColor Cyan
$OutFile = Join-Path $WorkDir 'SbomApp.cdx.json'
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb, '--out', $OutFile)
Check 'P4 exit 0, file written' (($r.Code -eq 0) -and (Test-Path $OutFile)) "exit $($r.Code) $($r.Err)"
if (Test-Path $OutFile) {
  $bytes = [IO.File]::ReadAllBytes($OutFile)
  Check 'P4 UTF-8 without BOM' (-not (($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB)))
  $j4 = $null
  try { $j4 = [IO.File]::ReadAllText($OutFile) | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
  Check 'P4 the file parses and carries the same components' ($j4 -and $j -and (Same (Refs $j4) (Refs $j)))
  Check 'P4 stdout is one summary line, not the document' (($r.Out -match 'CycloneDX 1\.6 written to') -and ($r.Out -notmatch 'bomFormat')) $r.Out.Trim()
}

Write-Host '-- P5: refusals' -ForegroundColor Cyan
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--map', 'x.map')
Check 'P5 --map is not registered in v1 (exit 3, no document)' (($r.Code -eq 3) -and ($r.Out -notmatch 'bomFormat')) "exit $($r.Code)"
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--bsi')
Check 'P5 --bsi is not registered in v1 (exit 3, no document)' (($r.Code -eq 3) -and ($r.Out -notmatch 'bomFormat')) "exit $($r.Code)"
$r = Run @('sbom', '--db', $ProjDb)
Check 'P5 no --project: usage, exit 2' (($r.Code -eq 2) -and ($r.Err -match '--project')) "exit $($r.Code)"
$r = Run @('sbom', '--project', $Dproj, '--db', (Join-Path $WorkDir 'none.sqlite'))
Check 'P5 no index: exit 2, names the index command' (($r.Code -eq 2) -and ($r.Err -match 'index --project') -and ($r.Out.Trim() -eq '')) "exit $($r.Code)"
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', (Join-Path $WorkDir 'nolib.sqlite'))
Check 'P5 a --library-db that does not exist: exit 1, no document' (($r.Code -eq 1) -and ($r.Out.Trim() -eq '')) "exit $($r.Code)"
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb, '--catalogue', (Join-Path $Fix 'catalogue\bad.json'))
Check 'P5 a catalogue row with an unknown member: exit 1, named, no document' (($r.Code -eq 1) -and ($r.Err -match 'pathz') -and ($r.Out.Trim() -eq '')) "exit $($r.Code) $($r.Err)"
$r = Run @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb, '--catalogue', (Join-Path $WorkDir 'no-catalogue.json'))
Check 'P5 a missing catalogue: exit 1, no document' (($r.Code -eq 1) -and ($r.Out.Trim() -eq '')) "exit $($r.Code)"

Write-Host '-- P6: read-only' -ForegroundColor Cyan
Check 'P6 the project index is byte-identical after every run' ((Get-FileHash -Algorithm SHA256 $ProjDb).Hash -eq $hashBefore)

Write-Host ("run_v156_SBOM1: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Failed) { exit 1 } else { exit 0 }
