<#
  run_redundant_cast_multi_library.ps1 -- lane 151 RC: the platform library that
  `lint --fix --fix-rule redundant-cast` reads when no --library-db is given.

  Hermetic: the engine is COPIED to a temp dir with its own drag-lint.json, run from a
  neutral cwd, so no machine manifest is read.

  Origin: 149 RT measured the Micronite casts OperatorList:380 / sgSManager:675 /
  uJobList:659 as type-not-indexed without --library-db. 151 RC reproduced that
  exactly with an engine that has NO drag-lint.json beside it (a wt build dir) --
  not with the machine manifest (5 fixes, same as --library-db). This guard pins both
  halves:

    M0  no manifest beside the engine: the NOTE says no platform library is named and
        the library cast stays refused (the 149 RT condition, made visible by 150 CQ).
    M1  a manifest with TWO library sections for Win32, the cast's type declared only
        in the SECOND: the default plan fixes it (all library sections of the platform
        are read, not the first existing one).
    M2  the default plan equals the explicit `--library-db A --library-db B` plan.
    M3  the NOTE names every library read.
    M4  section order does not change the plan (deterministic).
    M5  POSITIVE CONTROL: --library-db none refuses the library cast; a cast that is
        not redundant (string(N) of an Integer) is never a fix in any run.

  -Exe: the engine to test (default: the wt build).
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-redcast-multilib_$PID"
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
$manifest = Join-Path $eng 'drag-lint.json'
function Set-Manifest([string[]]$dbs) {
  $secs = @(); $i = 0
  foreach ($x in $dbs) { $i++; $secs += "{ `"name`": `"Lib$i`", `"db`": `"$x`", `"source`": `"registry-libraries`", `"platforms`": [`"Win32`"] }" }
  Write-Ascii $manifest ("{ `"settings`": { `"defaultPlatform`": `"Win32`", `"maxJobs`": 1 }, `"indexes`": { `"outDir`": `"$o`", `"sections`": [ " + ($secs -join ', ') + " ] } }")
}
Push-Location $neutral
try {
  $fxr = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\redcastlib").Path
  $d = Join-Path $WorkDir 'rc'; Copy-Item $fxr $d -Recurse
  # Split the stand-in library across two sections: LibOther (TLibTwin) in the FIRST,
  # LibTypes (TLibCls, TLibTwin) in the SECOND. TLibCls exists only in the second.
  $l1 = Join-Path $WorkDir 'l1'; $l2 = Join-Path $WorkDir 'l2'
  New-Item -ItemType Directory -Path $l1, $l2 -Force | Out-Null
  Copy-Item (Join-Path $d 'lib\LibOther.pas') $l1; Copy-Item (Join-Path $d 'lib\LibTypes.pas') $l2
  $libA = Join-Path $out 'libfirst.sqlite'; $libB = Join-Path $out 'library-Win32.sqlite'
  $db = Join-Path $d 'p.sqlite'; $proj = Join-Path $d 'RcLib.dproj'
  Set-Manifest @()
  $null = & $exe index $l1 --db $libA --library-db none 2>&1; Check 'SANITY: library A indexed' ($LASTEXITCODE -eq 0)
  $null = & $exe index $l2 --db $libB --library-db none 2>&1; Check 'SANITY: library B indexed' ($LASTEXITCODE -eq 0)
  $null = & $exe index --project $proj --db $db --library-db $libA --library-db $libB 2>&1; Check 'SANITY: project indexed' ($LASTEXITCODE -eq 0)
  $use = Join-Path $d 'RcLibUse.pas'
  $castLine = (Select-String -Path $use -Pattern 'TLibCls\(LC\)').LineNumber
  $noneLine = (Select-String -Path $use -Pattern 'string\(N\)').LineNumber
  function Plan($extra) {
    $e = Join-Path $WorkDir 'plan.err'
    $po = & $exe lint --fix --fix-rule redundant-cast --db $db --project $proj --platform win32 --format json @extra 2> $e
    $pl = $null; try { $pl = ($po -join "`n") | ConvertFrom-Json } catch { }
    $lines = if ($pl) { @($pl.fixes | ForEach-Object { [int]$_.line } | Sort-Object) } else { $null }
    [pscustomobject]@{ Plan = $pl; Lines = $lines; Err = [string](Get-Content $e -Raw -ErrorAction SilentlyContinue) }
  }
  $has = { param($r, $ln) $null -ne $r.Lines -and ($r.Lines -contains $ln) }

  # M0: no manifest beside the engine.
  [IO.File]::Delete($manifest)
  $m0 = Plan @()
  Check 'SANITY M0: plan parsed' ($null -ne $m0.Plan) $m0.Err
  Check 'M0  no manifest: NOTE says no platform library is named' ($m0.Err -match 'NOTE:.*names no platform library') $m0.Err
  Check 'M0b no manifest: the library cast is NOT fixed' (-not (& $has $m0 $castLine)) "lines=$($m0.Lines -join ',')"

  # Explicit reference plan: both libraries.
  Set-Manifest @('libfirst.sqlite', 'library-Win32.sqlite')
  $expl = Plan @('--library-db', $libA, '--library-db', $libB)
  Check 'SANITY: explicit A+B fixes the library cast' (& $has $expl $castLine) "lines=$($expl.Lines -join ',') err=$($expl.Err)"
  $dflt = Plan @()
  Check 'M1  two Win32 library sections, type only in the 2nd: default plan fixes the cast' (& $has $dflt $castLine) "lines=$($dflt.Lines -join ',') err=$($dflt.Err)"
  Check 'M2  default plan equals the explicit A+B plan' (($dflt.Lines -join ',') -eq ($expl.Lines -join ',')) "default=$($dflt.Lines -join ',') explicit=$($expl.Lines -join ',')"
  Check 'M3  NOTE names both library DBs' ($dflt.Err -match [regex]::Escape('libfirst.sqlite') -and $dflt.Err -match [regex]::Escape('library-Win32.sqlite')) $dflt.Err
  Set-Manifest @('library-Win32.sqlite', 'libfirst.sqlite')
  $swap = Plan @()
  Check 'M4  section order does not change the plan' (($swap.Lines -join ',') -eq ($dflt.Lines -join ',')) "swapped=$($swap.Lines -join ',') default=$($dflt.Lines -join ',')"
  $none = Plan @('--library-db', 'none')
  Check 'M5  CONTROL: --library-db none does not fix the library cast' ($null -ne $none.Plan -and -not (& $has $none $castLine)) "lines=$($none.Lines -join ',')"
  $all = @($m0, $expl, $dflt, $swap, $none)
  Check 'M5b CONTROL: string(N) of an Integer is never a fix' (@($all | Where-Object { & $has $_ $noneLine }).Count -eq 0) "line=$noneLine"
} finally { Pop-Location }
if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
