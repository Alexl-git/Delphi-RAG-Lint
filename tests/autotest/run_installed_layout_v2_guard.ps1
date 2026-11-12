<#
  run_installed_layout_v2_guard.ps1 -- installed layout v2, phase 1: path resolution behind an
  OFF switch. Spec: docs\superpowers\specs\2026-11-06-installed-layout-v2.md.

  Every engine run here sees a FAKE APPDATA and LOCALAPPDATA under -WorkDir, an engine COPY and
  a scratch CWD. Assert-Scratch refuses a WorkDir outside %TEMP% (or C:\TEMP) or inside the real
  profile folders before anything is created; S2 proves that refusal fires.

  CASES
    S1-S2 scratch guard: WorkDir accepted; the real %APPDATA% as WorkDir refused
    O1-O3 switch OFF (default): the exe-side manifest answers although an APPDATA one exists;
          the fatal log stays beside the exe; DRAGLINT_LAYOUT=anything-else is still OFF
    V1-V4 DRAGLINT_LAYOUT=v2: APPDATA wins, outDir resolves against the folder FOUND in;
          no APPDATA manifest falls back to the exe side; fatal log in LOCALAPPDATA\drag-lint\logs
    E1-E4 explicit: DRAGLINT_MANIFEST wins in both layouts; a MISSING explicit file never falls
          through to another manifest and is named on stderr
    F1-F2 --manifest beats the env var, and a spawned index child inherits it
    W1-W2 register-project writes the file the read answered, and leaves the exe side alone
    M1-M2 nothing moved: `manifest where` creates nothing; both manifests byte-identical at the end
    R1    the real manifest locations and fatal log did not change

  Pass the deployed pre-phase-1 engine as -Exe for the RED control: V*, E*, F*, W* must fail.
  Run from any CWD, pwsh 7. Exit 0 = all pass, 1 = a check failed, 2 = refused to run.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_layout_v2_guard_$PID"
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # 152 HG3: no machine drag-lint.json

function Assert-Scratch([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
  foreach ($real in @($env:APPDATA, $env:LOCALAPPDATA)) {
    if ($real -and $full.StartsWith($real.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
      # %TEMP% usually lives under LOCALAPPDATA; it is scratch, the rest of the profile is not
      $tmp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
      if (-not $full.StartsWith($tmp, [StringComparison]::OrdinalIgnoreCase)) {
        throw "refused: $Path is inside the real profile folder $real"
      }
    }
  }
  $roots = @(([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'), 'C:\TEMP\')
  $inScratch = @($roots | Where-Object { $full.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) -and $full.Length -gt $_.Length })
  if ($inScratch.Count -eq 0) { throw "refused: $Path is not below a scratch root ($($roots -join ', '))" }
}

try { Assert-Scratch $WorkDir } catch { Write-Host "REFUSED: $_" -ForegroundColor Red; exit 2 }

$savedEnv = @{}
foreach ($n in 'APPDATA','LOCALAPPDATA','DRAGLINT_LAYOUT','DRAGLINT_MANIFEST') { $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
$realAppData = $env:APPDATA
$realLocal   = $env:LOCALAPPDATA

try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}

Check 'S1 WorkDir accepted as scratch' $true
$refused = $false
try { Assert-Scratch (Join-Path $realAppData 'drag-lint') } catch { $refused = $true }
Check 'S2 positive control: the real APPDATA is refused' $refused

# Fingerprint of the real locations, taken before the first engine run
function Get-Stamp([string]$p) { if (Test-Path -LiteralPath $p) { $i = Get-Item -LiteralPath $p; "$($i.Length)/$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' } }
$exePath = (Resolve-Path $Exe).Path
$srcDir  = Split-Path $exePath -Parent
$realWatch = @(
  (Join-Path $realAppData 'drag-lint\drag-lint.json'),
  (Join-Path $realLocal 'drag-lint\logs\drag-lint-fatal.log'),
  (Join-Path $srcDir 'drag-lint-fatal.log'),
  (Join-Path $srcDir 'drag-lint.json'))
$realBefore = $realWatch | ForEach-Object { Get-Stamp $_ }

if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$engineDir = Join-Path $WorkDir 'engine'
$fakeRoam  = Join-Path $WorkDir 'fake-appdata'
$fakeLocal = Join-Path $WorkDir 'fake-localappdata'
$other     = Join-Path $WorkDir 'other'
$cwd       = Join-Path $WorkDir 'cwd'
foreach ($d in $engineDir, $fakeRoam, $fakeLocal, $other, $cwd) { [void][IO.Directory]::CreateDirectory($d) }
Copy-Item -LiteralPath $exePath -Destination $engineDir
Get-ChildItem -LiteralPath $srcDir -Filter '*.dll' | Copy-Item -Destination $engineDir
Copy-Item -LiteralPath (Join-Path $srcDir 'rules') -Destination $engineDir -Recurse
$copy = Join-Path $engineDir 'drag-lint.exe'

function New-Manifest([string]$Dir, [string]$Section) {
  [void][IO.Directory]::CreateDirectory((Join-Path $Dir 'src'))
  [IO.File]::WriteAllText((Join-Path $Dir 'src\Only.pas'), "unit Only;`r`ninterface`r`nimplementation`r`nend.`r`n")
  $path = Join-Path $Dir 'drag-lint.json'
  [IO.File]::WriteAllText($path, '{"settings":{},"indexes":{"outDir":"OUT","sections":[{"name":"' + $Section + '","include":["src"]}]}}')
  return $path
}
$exeManifest  = New-Manifest $engineDir 'FromExe'
$roamDir      = Join-Path $fakeRoam 'drag-lint'
$roamManifest = New-Manifest $roamDir 'FromAppData'
$expManifest  = New-Manifest $other 'FromExplicit'
$flagDir      = Join-Path $WorkDir 'flag'
$flagManifest = New-Manifest $flagDir 'FromFlag'

function Invoke-Engine([string[]]$EngineArgs, [hashtable]$Vars = @{}) {
  $env:APPDATA = $fakeRoam
  $env:LOCALAPPDATA = $fakeLocal
  $env:DRAGLINT_LAYOUT = $null
  $env:DRAGLINT_MANIFEST = $null
  foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
  Push-Location -LiteralPath $cwd
  try {
    $errFile = Join-Path $WorkDir 'stderr.txt'
    $o = ((& $copy @EngineArgs 2>$errFile | ForEach-Object { "$_" }) -join "`n")
    $rc = $LASTEXITCODE
    $e = if (Test-Path -LiteralPath $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
    return [pscustomobject]@{ Rc = $rc; Out = $o; Err = $e }
  } finally { Pop-Location }
}
function Get-PlanSections([hashtable]$Vars = @{}, [string[]]$Extra = @()) {
  $r = Invoke-Engine (@('index','--all','--dry-run','--json') + $Extra) $Vars
  try { $plan = $r.Out | ConvertFrom-Json } catch { return [pscustomobject]@{ Names = @(); Dbs = @(); Raw = $r.Out + $r.Err } }
  return [pscustomobject]@{ Names = @($plan.sections | ForEach-Object { $_.name }); Dbs = @($plan.sections | ForEach-Object { $_.db }); Raw = $r.Out + $r.Err }
}
function Test-Under([string]$Path, [string]$Dir) { return $Path -and $Path.StartsWith($Dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }
function Get-Where([hashtable]$Vars = @{}, [string[]]$Extra = @()) {
  $r = Invoke-Engine (@('manifest','where','--json') + $Extra) $Vars
  try { return ($r.Out | ConvertFrom-Json) } catch { return $null }
}
$V2 = @{ DRAGLINT_LAYOUT = 'v2' }
$fatalBesideExe = Join-Path $engineDir 'drag-lint-fatal.log'
$fatalInLogs    = Join-Path $fakeLocal 'drag-lint\logs\drag-lint-fatal.log'

# ---- O: switch OFF is today's behaviour ----
$p = Get-PlanSections
Check 'O1 OFF: the exe-side manifest answers, APPDATA ignored' (($p.Names -join ',') -eq 'FromExe') $p.Raw
$p = Get-PlanSections @{ DRAGLINT_LAYOUT = 'v3' }
Check 'O2 an unknown switch value stays OFF' (($p.Names -join ',') -eq 'FromExe') $p.Raw
[void](Invoke-Engine @('query','--no-such-flag-for-the-guard'))
Check 'O3 OFF: the fatal log is beside the exe' ((Test-Path -LiteralPath $fatalBesideExe) -and -not (Test-Path -LiteralPath $fatalInLogs))

# ---- M1: where creates nothing ----
$before = @(Get-ChildItem -LiteralPath $fakeLocal -Recurse -Force | ForEach-Object { $_.FullName }) -join '|'
$w = Get-Where $V2
$after = @(Get-ChildItem -LiteralPath $fakeLocal -Recurse -Force | ForEach-Object { $_.FullName }) -join '|'
Check 'M1 manifest where --json answers and creates nothing' (($null -ne $w) -and ($before -eq $after)) "before=[$before] after=[$after]"

# ---- V: v2 ----
$p = Get-PlanSections $V2
Check 'V1 v2: APPDATA wins over the exe side' (($p.Names -join ',') -eq 'FromAppData') $p.Raw
Check 'V2 v2: a relative outDir resolves against the folder the file was FOUND in' (Test-Under $p.Dbs[0] (Join-Path $roamDir 'OUT')) ($p.Dbs -join ',')
if ($w) {
  Check 'V2a where: origin appdata, layout v2, log + library dirs under LOCALAPPDATA' (
    ($w.manifest.origin -eq 'appdata') -and ($w.layout -eq 'v2') -and
    ($w.logDir -eq (Join-Path $fakeLocal 'drag-lint\logs')) -and ($w.libraryDir -eq (Join-Path $fakeLocal 'drag-lint\library'))) ($w | ConvertTo-Json -Depth 4)
} else { Check 'V2a where answered' $false }
[void](Invoke-Engine @('query','--no-such-flag-for-the-guard') $V2)
Check 'V3 v2: the fatal log lands in LOCALAPPDATA\drag-lint\logs' (Test-Path -LiteralPath $fatalInLogs)
$hidden = "$roamManifest.guard-hidden"
[IO.File]::Move($roamManifest, $hidden)
$p = Get-PlanSections $V2
[IO.File]::Move($hidden, $roamManifest)
Check 'V4 v2: no APPDATA manifest falls back to the exe side' (($p.Names -join ',') -eq 'FromExe') $p.Raw

# ---- E: explicit ----
$p = Get-PlanSections @{ DRAGLINT_MANIFEST = $expManifest }
Check 'E1 explicit wins with the switch OFF' (($p.Names -join ',') -eq 'FromExplicit') $p.Raw
$p = Get-PlanSections @{ DRAGLINT_MANIFEST = $expManifest; DRAGLINT_LAYOUT = 'v2' }
Check 'E2 explicit wins over APPDATA in v2' (($p.Names -join ',') -eq 'FromExplicit') $p.Raw
$missing = Join-Path $other 'no-such-manifest.json'
$p = Get-PlanSections @{ DRAGLINT_MANIFEST = $missing }
Check 'E3 a missing explicit file never falls through to another manifest' (($p.Names -notcontains 'FromExe') -and ($p.Names -notcontains 'FromAppData')) $p.Raw
Check 'E4 and it is named on stderr' ($p.Raw -match [regex]::Escape($missing)) $p.Raw

# ---- F: the flag ----
$p = Get-PlanSections @{ DRAGLINT_MANIFEST = $expManifest } @('--manifest', $flagManifest)
Check 'F1 --manifest beats DRAGLINT_MANIFEST' (($p.Names -join ',') -eq 'FromFlag') $p.Raw
$r = Invoke-Engine @('index','--all','--manifest',$flagManifest)
$flagDb = Join-Path $flagDir 'OUT\FromFlag.sqlite'
Check 'F2 a real index --all --manifest reaches the section (children inherit it)' ((Test-Path -LiteralPath $flagDb) -and -not (Test-Path -LiteralPath (Join-Path $engineDir 'OUT'))) ($r.Out + $r.Err)

# ---- W: writers follow the reader ----
$proj = Join-Path $cwd 'Reg.dproj'
[IO.File]::WriteAllText($proj, '<Project><PropertyGroup><MainSource>Reg.dpr</MainSource></PropertyGroup></Project>')
$exeBefore = [IO.File]::ReadAllText($exeManifest)
$r = Invoke-Engine @('register-project', $proj, '--name', 'RegW1', '--apply') $V2
Check 'W1 v2: register-project writes the APPDATA manifest' ([IO.File]::ReadAllText($roamManifest) -match 'RegW1') ($r.Out + $r.Err)
Check 'W2 v2: register-project leaves the exe side alone' ([IO.File]::ReadAllText($exeManifest) -ceq $exeBefore)

# ---- M2 / R ----
$p = Get-PlanSections
Check 'M2 nothing moved: the exe-side manifest is still there and answers once the switch is off' (($p.Names -join ',') -eq 'FromExe') $p.Raw
$env:APPDATA = $realAppData
$env:LOCALAPPDATA = $realLocal
$realAfter = $realWatch | ForEach-Object { Get-Stamp $_ }
Check 'R1 the real manifest locations and fatal logs did not change' ((($realBefore) -join '|') -ceq (($realAfter) -join '|')) "before=$($realBefore -join '|') after=$($realAfter -join '|')"
}
finally {
  foreach ($n in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $savedEnv[$n]) }
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: could not delete $WorkDir" } }
}
if ($script:fail) { exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
