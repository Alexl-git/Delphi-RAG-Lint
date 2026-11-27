<#
  run_v156_SBOM2.ps1 -- 1.56 lane SBOM-2 (G-49 slice 2): `drag-lint sbom --map <file.map>` and `--bsi`.

  --map reads a Delphi DETAILED linker map (DCC_MapFile=3, "Detailed map of segments") and marks, per
  component, which of its units are actually linked: drag-lint:linked = yes | partial | no, plus one
  drag-lint:linkedUnit / drag-lint:notLinkedUnit property per unit. A unit of the source closure that the MAP
  does not name is reported as NOT linked; the component is never dropped. Units the MAP names that no indexed
  source reaches are listed in the metadata (drag-lint:sbom:mapUnitNotInClosure).

  --bsi adds the fields the BSI TR-03183-2 profile asks for beyond plain CycloneDX (SBOM creator, component
  filename / executable / archive / structured properties, hash, licence, supplier, version). What cannot be
  filled is NOT invented: it is left out and named on its component as drag-lint:bsi:unfilled = "<field>: <reason>"
  (the count is in metadata drag-lint:sbom:bsiUnfilledCount, a summary goes to stderr).

  FIXTURE tests\fixtures\sbom (SBOM-1's, unchanged) + map\SbomApp.map = a REAL detailed map from linking
  map\src\SbomApp.dpr (dcc32 -GD; AppMain, SharedUnit, SbomApp, System, SysInit, System.SysUtils, ...). The
  runner never compiles anything.

  RED on the base (lane/v156-sbom1 799b168e3): --map / --bsi are not registered, exit 3.

  POSITIVE CONTROLS: M1 a MAP without the M=SharedUnit lines flips SharedUnit (and the application) to not
  linked / partial; M2 a MAP with an extra M=AcmeGrid segment flips the unknown Acme directory to partial; B1
  without --exe the application hash is unfilled (not invented), with --exe it is there; B2 without --creator
  the creator is unfilled, with it metadata.authors carries it; the plain document (no flag) has none of it.

  SCHEMA: every document is validated with Test-Json against the CycloneDX 1.6 schema vendored by SBOM-1
  (two controls prove the schema can fail). Run under pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-sbom2-$PID",
  [string]$Schema  = ''
)
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
$Map     = Join-Path $Fix 'map\SbomApp.map'
$Pe      = Join-Path $WorkDir 'SbomApp.exe'
[IO.File]::WriteAllBytes($Pe, [byte[]](0x4D, 0x5A, 0x90, 0, 3, 0, 0, 0))   # an MZ header: only then may drag-lint call the file an executable

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
function Comp($j, $ref)  { @($j.components) | Where-Object { $_.'bom-ref' -eq $ref } }
function PropVals($c, $name) { @($c.properties | Where-Object name -eq "drag-lint:$name" | ForEach-Object { $_.value }) }
function Same($a, $b)    { (@($a) -join '|') -eq (@($b) -join '|') }
function Sorted($a)      { @($a) | Sort-Object }
function SbomArgs([string[]]$more) { @('sbom', '--project', $Dproj, '--db', $ProjDb, '--library-db', $LibDb) + $more }

$bundle = $null
if ((Get-Command Test-Json -ErrorAction SilentlyContinue) -and ($PSVersionTable.PSVersion.Major -ge 7)) {
  $bundle = Join-Path $WorkDir 'bom-1.6.bundled.schema.json'
  $spdx = [IO.File]::ReadAllText((Join-Path $Schema 'spdx.schema.json')) | ConvertFrom-Json
  $enum = '"type": "string", "enum": ' + (ConvertTo-Json @($spdx.enum) -Compress)
  $text = [IO.File]::ReadAllText((Join-Path $Schema 'bom-1.6.schema.json'))
  $text = $text.Replace('"$ref": "spdx.schema.json"', $enum).Replace('"$ref": "jsf-0.82.schema.json#/definitions/signature"', '"type": "object"')
  [IO.File]::WriteAllText($bundle, $text)
}
function SchemaOk($r, $label) {
  if (-not $bundle) { Write-Host "  [NOTE] $label : Test-Json -SchemaFile needs pwsh 7, schema check skipped" -ForegroundColor Yellow; return }
  $ok = $false
  try { $ok = Test-Json -Json $r.Out -SchemaFile $bundle -ErrorAction Stop } catch { Write-Host "    schema: $_" }
  Check "$label SCHEMA valid against the vendored CycloneDX 1.6 schema" $ok
}

Write-Host '-- setup: index the project and the library fixture into scratch indexes' -ForegroundColor Cyan
$r = Run @('index', (Join-Path $Fix 'proj'), '--db', $ProjDb)
Check 'setup: project fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index', (Join-Path $Fix 'libs'), '--db', $LibDb)
Check 'setup: library fixture indexed' ($r.Code -eq 0) "exit $($r.Code)"

$RefRtl = 'lib:embarcadero-rtl'; $RefSpring = 'lib:spring4d'; $RefDx = 'lib:devexpress-vcl'
$RefAcme = 'unknown-dir:libs/AcmeWidgets'; $RefVendor = 'unknown-dir:proj/vendor'; $RefNoSrc = 'unknown-unit:NoSrcLib'

Write-Host '-- map fixture sanity: a real detailed linker map' -ForegroundColor Cyan
$mapText = [IO.File]::ReadAllText($Map)
Check 'map: detailed segment list present, names AppMain / SharedUnit / SbomApp' (($mapText -match 'Detailed map of segments') -and ($mapText -match 'M=AppMain ') -and ($mapText -match 'M=SharedUnit ') -and ($mapText -match 'M=SbomApp '))

Write-Host '-- M: --map' -ForegroundColor Cyan
$r = Run (SbomArgs @('--map', $Map))
Check 'M exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Err)"
$j = Doc $r
Check 'M stdout parses as JSON' ($null -ne $j)
if ($j) {
  SchemaOk $r 'M'
  Check 'M the six components are all still there (nothing dropped)' (@($j.components).Count -eq 6) "$(@($j.components).Count)"
  Check 'M metadata names the map file and says MAP input was read' (((PropVals $j.metadata 'sbom:map') -eq 'SbomApp.map') -and ("$(PropVals $j.metadata 'sbom:scope')" -match 'linker MAP'))
  $app = $j.metadata.component
  Check 'M application: linked = yes, its three units linked, none not linked' (((PropVals $app 'linked') -eq 'yes') -and (Same (Sorted (PropVals $app 'linkedUnit')) @('AppMain', 'SbomApp', 'SharedUnit')) -and (@(PropVals $app 'notLinkedUnit').Count -eq 0)) "$(PropVals $app 'linked') $(PropVals $app 'linkedUnit')"
  $rtl = Comp $j $RefRtl
  Check 'M RTL: partial; System + SysInit linked, System.FixRtl NOT linked' (((PropVals $rtl 'linked') -eq 'partial') -and (Same (Sorted (PropVals $rtl 'linkedUnit')) @('SysInit', 'System')) -and (Same (PropVals $rtl 'notLinkedUnit') @('System.FixRtl'))) "$(PropVals $rtl 'linked') / $(PropVals $rtl 'linkedUnit') / $(PropVals $rtl 'notLinkedUnit')"
  $spr = Comp $j $RefSpring
  Check 'M Spring4D: linked = no, its unit listed as not linked, component kept' (((PropVals $spr 'linked') -eq 'no') -and (Same (PropVals $spr 'notLinkedUnit') @('Spring.FixBase')) -and (@(PropVals $spr 'linkedUnit').Count -eq 0)) "$(PropVals $spr 'linked') $(PropVals $spr 'notLinkedUnit')"
  Check 'M Acme directory and the sourceless units: linked = no' (((PropVals (Comp $j $RefAcme) 'linked') -eq 'no') -and ((PropVals (Comp $j $RefDx) 'linked') -eq 'no') -and ((PropVals (Comp $j $RefNoSrc) 'linked') -eq 'no') -and ((PropVals (Comp $j $RefVendor) 'linked') -eq 'no'))
  $extra = @(PropVals $j.metadata 'sbom:mapUnitNotInClosure')
  Check 'M units the MAP names that no indexed source reaches are listed (System.SysUtils); closure units are not' (($extra -contains 'System.SysUtils') -and ($extra -notcontains 'AppMain') -and ($extra -notcontains 'System')) "$($extra.Count) listed"
  Check 'M stderr NOTE counts the not-linked units' ($r.Err -match 'not linked') $r.Err
  Check 'M the document still says what the MAP cannot see (compositions incomplete)' ($j.compositions[0].aggregate -eq 'incomplete')
}

Write-Host '-- M1/M2: positive controls, the MAP decides' -ForegroundColor Cyan
$lines = [IO.File]::ReadAllLines($Map)
$MapNoShared = Join-Path $WorkDir 'noshared.map'
[IO.File]::WriteAllLines($MapNoShared, @($lines | Where-Object { $_ -notmatch 'M=SharedUnit\s' }))
Check 'M1 setup: the lines of M=SharedUnit were removed' (([IO.File]::ReadAllLines($MapNoShared)).Count -lt $lines.Count)
$r = Run (SbomArgs @('--map', $MapNoShared))
$j1 = Doc $r
Check 'M1 exit 0, parses' (($r.Code -eq 0) -and $j1) "exit $($r.Code) $($r.Err)"
if ($j1) {
  $app = $j1.metadata.component
  Check 'M1 SharedUnit flips to not linked, the application to partial' (((PropVals $app 'linked') -eq 'partial') -and (Same (PropVals $app 'notLinkedUnit') @('SharedUnit')) -and (Same (Sorted (PropVals $app 'linkedUnit')) @('AppMain', 'SbomApp'))) "$(PropVals $app 'linked') $(PropVals $app 'notLinkedUnit')"
}
$MapAcme = Join-Path $WorkDir 'acme.map'
$i = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match 'M=SharedUnit\s' })
$acmeLine = $lines[$i].Replace('M=SharedUnit', 'M=AcmeGrid')
[IO.File]::WriteAllLines($MapAcme, @($lines[0..$i]) + @($acmeLine) + @($lines[($i + 1)..($lines.Count - 1)]))
$r = Run (SbomArgs @('--map', $MapAcme))
$j2 = Doc $r
Check 'M2 exit 0, parses' (($r.Code -eq 0) -and $j2) "exit $($r.Code) $($r.Err)"
if ($j2) {
  $a = Comp $j2 $RefAcme
  Check 'M2 an extra M=AcmeGrid segment flips the Acme directory to partial' (((PropVals $a 'linked') -eq 'partial') -and (Same (PropVals $a 'linkedUnit') @('AcmeGrid')) -and (Same (PropVals $a 'notLinkedUnit') @('AcmeCore'))) "$(PropVals $a 'linked') $(PropVals $a 'linkedUnit')"
}

Write-Host '-- M3: the plain document has no MAP properties' -ForegroundColor Cyan
$r = Run (SbomArgs @())
$j3 = Doc $r
Check 'M3 no --map: exit 0, no linked / notLinkedUnit property anywhere' (($r.Code -eq 0) -and $j3 -and (-not ($r.Out -match 'drag-lint:linked')) -and (-not ($r.Out -match 'notLinkedUnit')))

Write-Host '-- M4: refusals' -ForegroundColor Cyan
$r = Run (SbomArgs @('--map', (Join-Path $WorkDir 'none.map')))
Check 'M4 a MAP that does not exist: exit 1, named, no document' (($r.Code -eq 1) -and ($r.Err -match 'none\.map') -and ($r.Out.Trim() -eq '')) "exit $($r.Code) $($r.Err)"
$MapShort = Join-Path $WorkDir 'segments-only.map'
[IO.File]::WriteAllLines($MapShort, @($lines | Select-Object -First 8))
$r = Run (SbomArgs @('--map', $MapShort))
Check 'M4 a MAP without the detailed segment list: exit 1, says so, no document' (($r.Code -eq 1) -and ($r.Err -match 'Detailed map of segments') -and ($r.Out.Trim() -eq '')) "exit $($r.Code) $($r.Err)"
$r = Run (SbomArgs @('--map'))
Check 'M4 --map without a value: usage, exit 2' (($r.Code -eq 2) -and ($r.Err -match '--map')) "exit $($r.Code)"

Write-Host '-- B: --bsi' -ForegroundColor Cyan
$r = Run (SbomArgs @('--bsi', '--exe', $Pe, '--app-version', '1.2.3', '--creator', 'Test Maker', '--creator-email', 'sbom@example.org', '--map', $Map))
Check 'B exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Err)"
$jb = Doc $r
Check 'B stdout parses as JSON' ($null -ne $jb)
if ($jb) {
  SchemaOk $r 'B'
  Check 'B metadata names the profile' ("$(PropVals $jb.metadata 'sbom:profile')" -match 'BSI TR-03183-2')
  Check 'B SBOM creator: metadata.authors name + email' ((@($jb.metadata.authors).Count -eq 1) -and ($jb.metadata.authors[0].name -ceq 'Test Maker') -and ($jb.metadata.authors[0].email -ceq 'sbom@example.org'))
  $app = $jb.metadata.component
  $sha = (Get-FileHash -Algorithm SHA512 $Pe).Hash.ToLowerInvariant()
  Check 'B application: SHA-512, version, filename / executable / archive / structured' (($app.hashes[0].content -ceq $sha) -and ($app.version -ceq '1.2.3') -and ((@($app.properties | Where-Object name -eq 'bsi:component:filename').value) -eq 'SbomApp.exe') -and ((@($app.properties | Where-Object name -eq 'bsi:component:executable').value) -eq 'executable') -and ((@($app.properties | Where-Object name -eq 'bsi:component:archive').value) -eq 'no archive') -and ((@($app.properties | Where-Object name -eq 'bsi:component:structured').value) -eq 'unstructured'))
  Check 'B application licence is unfilled with a reason, none invented' (($null -eq $app.licenses) -and (@(PropVals $app 'bsi:unfilled') -match '^licence: '))
  $rtl = Comp $jb $RefRtl
  Check 'B RTL: supplier, version and licence filled from the catalogue, so NOT in the unfilled list' (($rtl.supplier.name -like 'Embarcadero*') -and ($rtl.version -ceq '37.0') -and $rtl.licenses -and (-not (@(PropVals $rtl 'bsi:unfilled') -match '^(supplier|version|licence): ')))
  Check 'B RTL: no deployable file of its own: filename and hash are unfilled with the reason' ((@(PropVals $rtl 'bsi:unfilled') -match '^filename: .*linked') -and (@(PropVals $rtl 'bsi:unfilled') -match '^hash: ') -and ($null -eq $rtl.hashes))
  $acme = Comp $jb $RefAcme
  Check 'B Acme (no catalogue row): no supplier object invented, supplier / version / licence unfilled' (($null -eq $acme.supplier) -and ($null -eq $acme.version) -and ($null -eq $acme.licenses) -and (@(PropVals $acme 'bsi:unfilled') -match '^supplier: ') -and (@(PropVals $acme 'bsi:unfilled') -match '^version: ') -and (@(PropVals $acme 'bsi:unfilled') -match '^licence: ')) "$(PropVals $acme 'bsi:unfilled')"
  $cnt = [int](PropVals $jb.metadata 'sbom:bsiUnfilledCount')
  $real = @($jb.components + @($app) + @($jb.metadata) | ForEach-Object { @(PropVals $_ 'bsi:unfilled').Count } | Measure-Object -Sum).Sum
  Check 'B the unfilled count in the metadata equals the unfilled properties in the document' (($cnt -gt 0) -and ($cnt -eq $real)) "$cnt vs $real"
  Check 'B stderr summarises the unfilled fields' ($r.Err -match 'BSI' -and $r.Err -match 'unfilled')
  Check 'B --map still applies together with --bsi' ((PropVals $app 'linked') -eq 'yes')
}

Write-Host '-- B1/B2: positive controls, nothing is invented' -ForegroundColor Cyan
$r = Run (SbomArgs @('--bsi'))
$jc = Doc $r
Check 'B1 exit 0, parses' (($r.Code -eq 0) -and $jc) "exit $($r.Code) $($r.Err)"
if ($jc) {
  SchemaOk $r 'B1'
  $app = $jc.metadata.component
  Check 'B1 without --exe the application has no hash, and says why' (($null -eq $app.hashes) -and (@(PropVals $app 'bsi:unfilled') -match '^hash: .*--exe') -and (@(PropVals $app 'bsi:unfilled') -match '^filename: '))
  Check 'B1 without --app-version no version is invented' (($null -eq $app.version) -and (@(PropVals $app 'bsi:unfilled') -match '^version: .*--app-version'))
  Check 'B2 without --creator the SBOM creator is unfilled, metadata.authors is absent' (($null -eq $jc.metadata.authors) -and (@(PropVals $jc.metadata 'bsi:unfilled') -match '^creator: .*--creator'))
}
$r = Run (SbomArgs @('--bsi', '--exe', $Deliv))
$jt = Doc $r
Check 'B5 a --exe without an MZ header: filename and hash filled, executable / archive / structured NOT claimed' ($jt -and ($r.Code -eq 0) -and ((@($jt.metadata.component.properties | Where-Object name -eq 'bsi:component:filename').value) -eq 'SbomApp.exe.txt') -and ($null -ne $jt.metadata.component.hashes) -and ($null -eq ($jt.metadata.component.properties | Where-Object name -eq 'bsi:component:executable')) -and (@(PropVals $jt.metadata.component 'bsi:unfilled') -match '^file-properties: .*MZ'))
$r = Run (SbomArgs @())
$jp = Doc $r
Check 'B3 the plain document (no --bsi) has no bsi properties, and keeps the "unknown supplier" component' ($jp -and (-not ($r.Out -match 'bsi:')) -and ((Comp $jp $RefAcme).supplier.name -ceq 'unknown supplier'))

Write-Host '-- B4: refusals' -ForegroundColor Cyan
$r = Run (SbomArgs @('--creator'))
Check 'B4 --creator without a value: usage, exit 2' (($r.Code -eq 2) -and ($r.Err -match '--creator')) "exit $($r.Code)"
$r = Run (SbomArgs @('--bsi', '--creator-email', 'not-an-address'))
Check 'B4 --creator-email that is not an address: exit 2, named, no document' (($r.Code -eq 2) -and ($r.Err -match 'creator-email') -and ($r.Out.Trim() -eq '')) "exit $($r.Code) $($r.Err)"

Write-Host '-- P7: catalogue purls follow the purl spec' -ForegroundColor Cyan
$cat = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\..\rules\sbom-libraries.json') | ConvertFrom-Json
$purls = @($cat.PSObject.Properties.Value | ForEach-Object { $_ } | ForEach-Object { $_.purl } | Where-Object { $_ })
$badPurl = @($purls | Where-Object { $_ -cmatch '^pkg:(github|bitbucket)/' -and $_ -cne $_.ToLowerInvariant() })
Check 'B6 github/bitbucket purls are lowercase (purl spec: type, namespace and name)' (($purls.Count -gt 0) -and ($badPurl.Count -eq 0)) ($badPurl -join ' ')

Write-Host ("RESULT: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Failed) { exit 1 } else { exit 0 }
