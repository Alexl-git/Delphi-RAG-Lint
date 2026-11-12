<#
  run_cq_library_defaults.ps1 -- lane 150 CQ items 1 and 3 (RQ-6b, RT redundant-cast library default).

  Hermetic: the engine is COPIED to a temp dir with its own drag-lint.json (library sections), run from a
  neutral cwd, so no machine manifest is read.

  RQ-6b  A library is recognised by its manifest library SECTION, never by a `library-` file-name prefix.
    A1  a project DB named library-Fixture.sqlite (no section names it) is NOT a library: `lint` of a
        cycle unit against it runs the project-rules pass and reports circular-uses.
    A2  POSITIVE CONTROL: the section's db (stdlib.sqlite, no prefix) IS a library: same lint, no
        project-rules pass, no circular-uses.
    A3  the framework-context tie-break (ResolveFrameworkContextDb): a VCL project DB + the manifest's
        library-Pair.sqlite section resolves a VCL context (Vcl TEdit first); a library-Stray.sqlite that no
        section names is a second project DB, so no single context (SQL order, FMX first).
  RT-3   `lint --fix --fix-rule redundant-cast --platform win32` without --library-db loads the manifest
        library for the platform and says so on stderr.
    B1  the NOTE names the library DB; B2 the plan equals the one --library-db <same db> gives;
    B3  POSITIVE CONTROL: --library-db none still refuses the library class cast (fewer fixes).
  -Exe: the engine to test (default: the wt build).
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\claude\lanes\150\CQ\scratch\cqlib_$PID"
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # 152 HG3: no machine drag-lint.json
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d = '') { Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok]); if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true } }
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$eng = Join-Path $WorkDir 'eng'; $out = Join-Path $WorkDir 'out'; $neutral = Join-Path $WorkDir 'cwd'
foreach ($d in $eng, $out, $neutral) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
Copy-Item $exeSrc (Join-Path $eng 'drag-lint.exe') -Force
Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
Get-ChildItem $exeSrcDir -Filter '*.castlib' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng $_.Name) -Force }
if (Test-Path (Join-Path $exeSrcDir 'rules')) { Copy-Item (Join-Path $exeSrcDir 'rules') (Join-Path $eng 'rules') -Recurse -Force }
$exe = Join-Path $eng 'drag-lint.exe'
$o = $out.Replace('\', '/')
Write-Ascii (Join-Path $eng 'drag-lint.json') @"
{
  "settings": { "defaultPlatform": "Win32", "maxJobs": 1 },
  "indexes": { "outDir": "$o", "sections": [
    { "name": "Lib", "db": "stdlib.sqlite", "source": "registry-libraries", "platforms": ["Win32"] },
    { "name": "LibPair", "db": "library-Pair.sqlite", "source": "registry-libraries", "platforms": ["Win32"] },
    { "name": "LibW32", "db": "library-Win32.sqlite", "source": "registry-libraries", "platforms": ["Win32"] }
  ] }
}
"@
Push-Location $neutral
try {
  # ---- A: lint of a cycle unit ----
  $src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory -Path $src -Force | Out-Null
  Write-Ascii (Join-Path $src 'uCycA.pas') "unit uCycA;`n`ninterface`n`nuses`n  uCycB;`n`n/// <summary>Fixture routine.</summary>`nfunction A1: Integer;`n`nimplementation`n`nfunction A1: Integer;`nbegin`n  Result:= B1;`nend;`n`nend.`n"
  Write-Ascii (Join-Path $src 'uCycB.pas') "unit uCycB;`n`ninterface`n`nuses`n  uCycA;`n`n/// <summary>Fixture routine.</summary>`nfunction B1: Integer;`n`nimplementation`n`nfunction B1: Integer;`nbegin`n  Result:= 1;`nend;`n`nend.`n"
  $fileA = Join-Path $src 'uCycA.pas'
  $prefixDb = Join-Path $WorkDir 'library-Fixture.sqlite'
  $sectionDb = Join-Path $out 'stdlib.sqlite'
  foreach ($d in $prefixDb, $sectionDb) { $null = & $exe index $src --db $d 2>&1; Check "SANITY: indexed $(Split-Path $d -Leaf)" ($LASTEXITCODE -eq 0) }
  function LintDbg($db) { $env:DRAGLINT_DEBUG = '1'; try { & $exe lint $fileA --db $db 2>&1 | Out-String } finally { Remove-Item Env:\DRAGLINT_DEBUG } }
  $p = LintDbg $prefixDb
  Check 'A1  project DB named library-*.sqlite (no section): project-rules pass runs' ($p -match '\[lint-checker\] project-rules') ''
  Check 'A1b same: circular-uses is reported' ($p -match '\] circular-uses:') ''
  $s = LintDbg $sectionDb
  Check 'A2  CONTROL: a manifest library section db (no library- prefix): no project-rules pass' ($s -notmatch '\[lint-checker\] project-rules') ''
  Check 'A2b CONTROL: same: no circular-uses finding' ($s -notmatch '\] circular-uses:') ''
  Check 'A2c CONTROL: same: the store still serves the per-file checkers' ($s -match 'store=True') ''

  # ---- A3: framework context ----
  $fx = Join-Path $WorkDir 'fw'; New-Item -ItemType Directory -Path "$fx\lib", "$fx\vcl" -Force | Out-Null
  Write-Ascii "$fx\lib\Vcl.StdCtrls.pas" "unit Vcl.StdCtrls;`ninterface`ntype`n  TEdit = class end;`nimplementation`nend.`n"
  Write-Ascii "$fx\lib\FMX.Edit.pas" "unit FMX.Edit;`ninterface`ntype`n  TEdit = class end;`nimplementation`nend.`n"
  Write-Ascii "$fx\vcl\uVclApp.pas" "unit uVclApp;`ninterface`nuses`n  Vcl.StdCtrls;`nimplementation`nend.`n"
  $pairDb = Join-Path $out 'library-Pair.sqlite'; $vclDb = Join-Path $WorkDir 'vcl.sqlite'
  $null = & $exe index "$fx\lib" --db $pairDb 2>&1; $null = & $exe index "$fx\vcl" --db $vclDb 2>&1
  function TEditOrder($dbs) {
    $a = @('query', '--name', 'TEdit', '--json', '--quiet'); foreach ($d in $dbs) { $a += @('--db', $d) }
    $raw = (@(& $exe @a 2>&1) | ForEach-Object { "$_" } | Where-Object { -not $_.TrimStart().StartsWith('(') }) -join "`n"
    if (-not $raw.Trim()) { return @() }
    return @(($raw | ConvertFrom-Json) | ForEach-Object { $_.qualified_name })
  }
  $plain = TEditOrder @($pairDb)
  Check 'SANITY A3: both TEdit rows exist' ($plain.Count -ge 2) ($plain -join ',')
  $ctx = TEditOrder @($vclDb, $pairDb)
  Check 'A3  manifest names library-Pair as a library: the VCL project context puts Vcl.StdCtrls.TEdit first' ($ctx.Count -ge 2 -and $ctx[0] -eq 'Vcl.StdCtrls.TEdit') ($ctx -join ',')
  $stray = Join-Path $WorkDir 'library-Stray.sqlite'; Copy-Item $pairDb $stray
  $ctx2 = TEditOrder @($vclDb, $stray)
  Check 'A3b CONTROL: a library-*.sqlite no section names is a project DB: two project DBs give no single context (SQL order, FMX first)' ($ctx2.Count -ge 2 -and $ctx2[0] -eq 'FMX.Edit.TEdit') ($ctx2 -join ',')

  # ---- B: redundant-cast default library ----
  # B has ONE library section for the platform (a second would make the default ambiguous).
  Write-Ascii (Join-Path $eng 'drag-lint.json') ("{ `"settings`": { `"defaultPlatform`": `"Win32`", `"maxJobs`": 1 }, `"indexes`": { `"outDir`": `"$o`", `"sections`": [ { `"name`": `"LibW32`", `"db`": `"library-Win32.sqlite`", `"source`": `"registry-libraries`", `"platforms`": [`"Win32`"] } ] } }")
  $fxr = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\redcastlib").Path
  $d = Join-Path $WorkDir 'rc'; Copy-Item $fxr $d -Recurse
  $lib = Join-Path $out 'library-Win32.sqlite'; $db = Join-Path $d 'p.sqlite'; $proj = Join-Path $d 'RcLib.dproj'
  $null = & $exe index (Join-Path $d 'lib') --db $lib --library-db none 2>&1; Check 'SANITY B: library indexed' ($LASTEXITCODE -eq 0)
  $null = & $exe index --project $proj --db $db --library-db $lib 2>&1; Check 'SANITY B: project indexed' ($LASTEXITCODE -eq 0)
  function Plan($extra) {
    $e = Join-Path $WorkDir 'plan.err'
    $o = & $exe lint --fix --fix-rule redundant-cast --db $db --project $proj --platform win32 --format json @extra 2> $e
    $pl = $null; try { $pl = ($o -join "`n") | ConvertFrom-Json } catch { }
    [pscustomobject]@{ Plan = $pl; Err = [string](Get-Content $e -Raw -ErrorAction SilentlyContinue) }
  }
  $dflt = Plan @(); $expl = Plan @('--library-db', $lib); $none = Plan @('--library-db', 'none')
  $nf = { param($r) if ($r.Plan) { @($r.Plan.fixes).Count } else { -1 } }
  Check 'SANITY B: explicit --library-db yields fixes' ((& $nf $expl) -gt 0) "fixes=$(& $nf $expl) err=$($expl.Err)"
  Check 'B1  default (no --library-db): NOTE names the manifest library db' ($dflt.Err -match 'NOTE:.*manifest platform library' -and $dflt.Err -match [regex]::Escape('library-Win32.sqlite')) $dflt.Err
  Check 'B2  default plan has the same fixes as the explicit --library-db plan' ((& $nf $dflt) -eq (& $nf $expl)) "default=$(& $nf $dflt) explicit=$(& $nf $expl)"
  Check 'B3  CONTROL: --library-db none refuses the library class cast (fewer fixes)' ((& $nf $none) -ge 0 -and (& $nf $none) -lt (& $nf $expl)) "none=$(& $nf $none) explicit=$(& $nf $expl)"
} finally { Pop-Location }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
