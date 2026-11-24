<#
  run_pack_vcruntime_guard.ps1 -- the release carries the Microsoft C runtime and the exact engine (1.54).

  WHY: all three tree-sitter DLLs import VCRUNTIME140.dll; a clean machine without the VC++
  redistributable could not start the engine, and neither the setup nor the zips carried it.
  And the win64 zip once held a Release engine no battery had run (the setup held the tested one).

  A  build\PeImports.ps1 reads the imports (control: the committed parser DLLs DO import vcruntime140)
  B  build\VcRuntime.ps1 Add-VcRuntime: a stage with the parser DLLs gets a Microsoft-signed runtime of
     the right bitness (x64 and x86); afterwards nothing is missing; a second run adds nothing
  C  it fails loudly: no such redist folder, unsigned file, wrong bitness
  D  pack-lint-release.ps1 refuses -EngineExe with a wrong or missing hash, before any other work;
     control: with the right hash it gets past the check
  E  static: pack, Build-Installer.ps1 and drag-lint.iss use it (text of the scripts)
  Sections B and C need the Visual Studio redist folder (as the pack does); without it they FAIL.
#>
param([string]$Scratch = '', [switch]$KeepWorkDir)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\WorkDirCleanup.ps1"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) "pack_vcrt_guard_$PID" }
[void][IO.Directory]::CreateDirectory($Scratch)
$script:fails = 0; $script:passes = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:passes++; "PASS $Name" } else { $script:fails++; "FAIL $Name $Detail" }
}
function Throws([scriptblock]$Body, [string]$Pattern) {
  try { & $Body | Out-Null; return $false } catch { return ("$_" -match $Pattern) }
}
. (Join-Path $repo 'build\VcRuntime.ps1')
$parsers = 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll'

foreach ($d in $parsers) {
  $f = Join-Path $repo "third_party\dll-win64\$d"
  Check "A $d (x64) imports vcruntime140.dll" ((Get-PeMachine $f) -eq 'x64' -and (Get-PeImports $f) -contains 'vcruntime140.dll')
}
Check 'A control: a text file is refused as a PE image' (Throws { Get-PeImports $PSCommandPath } 'not a PE image')

foreach ($arch in 'x64', 'x86') {
  $src = if ($arch -eq 'x64') { 'third_party\dll-win64' } else { 'third_party\dll-win32' }
  $stage = Join-Path $Scratch "stage-$arch"
  [void][IO.Directory]::CreateDirectory($stage)
  foreach ($d in $parsers) { [IO.File]::Copy((Join-Path $repo "$src\$d"), (Join-Path $stage $d), $true) }
  $before = @(Get-VcRuntimeNeeded @(Get-ChildItem $stage -File | ForEach-Object FullName))
  Check "B $arch control: before, vcruntime140.dll is reported missing" ($before -contains 'vcruntime140.dll') ($before -join ',')
  $added = @(Add-VcRuntime -Stage $stage -Arch $arch)
  Check "B $arch vcruntime140.dll added" ($added -contains 'vcruntime140.dll') ($added -join ',')
  $got = Join-Path $stage 'vcruntime140.dll'
  Check "B $arch it is signed by Microsoft and $arch" (-not (Throws { Assert-VcRuntimeFile $got $arch } '.')) 
  $after = @(Get-VcRuntimeNeeded @(Get-ChildItem $stage -File | ForEach-Object FullName))
  Check "B $arch nothing is missing afterwards" ($after.Count -eq 0) ($after -join ',')
  Check "B $arch a second run adds nothing" (@(Add-VcRuntime -Stage $stage -Arch $arch).Count -eq 0)
}

$bare = Join-Path $Scratch 'bare'; [void][IO.Directory]::CreateDirectory($bare)
[IO.File]::Copy((Join-Path $repo 'third_party\dll-win64\tree-sitter.dll'), (Join-Path $bare 'tree-sitter.dll'), $true)
Check 'C missing redist folder: throws' (Throws { Add-VcRuntime -Stage $bare -Arch 'x64' -RedistDir (Join-Path $Scratch 'nope') } 'no vcruntime140\.dll')
$fake = Join-Path $Scratch 'fakeredist'; [void][IO.Directory]::CreateDirectory($fake)
[IO.File]::Copy((Join-Path $repo 'third_party\dll-win64\tree-sitter.dll'), (Join-Path $fake 'vcruntime140.dll'), $true)
Check 'C unsigned runtime: throws' (Throws { Add-VcRuntime -Stage $bare -Arch 'x64' -RedistDir $fake } 'not validly signed')
Check 'C wrong bitness: throws' (Throws { Assert-VcRuntimeFile (Join-Path $Scratch 'stage-x86\vcruntime140.dll') 'x64' } 'is x86, expected x64')
Check 'C nothing was copied by the failed runs' (-not (Test-Path -LiteralPath (Join-Path $bare 'vcruntime140.dll')))

# D: a fake repo with only the pack script; the engine check comes first
$fr = Join-Path $Scratch 'repo'
[void][IO.Directory]::CreateDirectory((Join-Path $fr 'build'))
[IO.File]::Copy((Join-Path $repo 'build\pack-lint-release.ps1'), (Join-Path $fr 'build\pack-lint-release.ps1'), $true)
$eng = Join-Path $Scratch 'engine.exe'; [IO.File]::WriteAllText($eng, 'not really an engine')
$hash = (Get-FileHash -LiteralPath $eng -Algorithm SHA256).Hash
function Invoke-Pack([string[]]$Extra) {
  $shell = (Get-Process -Id $PID).Path
  $out = & { $ErrorActionPreference = 'Continue'; & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fr 'build\pack-lint-release.ps1') -Version 0.0.0-test -SkipBuild -NoProfileInstall @Extra 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}
$r = Invoke-Pack @('-EngineExe', $eng, '-EngineSha256', ('0' * 64))
Check 'D wrong hash: exit 1, both hashes named' ($r.Exit -eq 1 -and $r.Text.Contains($hash) -and $r.Text -match 'PACK REFUSED') $r.Text
$r = Invoke-Pack @('-EngineExe', $eng)
Check 'D hash missing: exit 1' ($r.Exit -eq 1 -and $r.Text -match 'go together') $r.Text
$r = Invoke-Pack @('-EngineExe', $eng, '-EngineSha256', $hash)
Check 'D control: right hash gets past the check (stops at the WWW check)' ($r.Text -match 'index\.json is missing' -and $r.Text -notmatch 'expected') $r.Text

$statics = @(
  @('pack stages the runtime', 'build\pack-lint-release.ps1', 'Add-VcRuntime -Stage \$stg -Arch \$arch'),
  @('pack verifies vcruntime140.dll in the finished win64 zip', 'build\pack-lint-release.ps1', "foreach \(\`$need in .*'vcruntime140\.dll'"),
  @('pack re-checks the packed engine', 'build\pack-lint-release.ps1', 'Assert-EngineHash \(Join-Path \$stg'),
  @('setup ships it in bin\', 'installer\drag-lint.iss', '^Source: "\{#VcRedistDir\}\\vcruntime140\.dll";\s+DestDir: "\{app\}\\bin";.*Components: core'),
  @('Build-Installer checks signature and bitness', 'installer\Build-Installer.ps1', "Assert-VcRuntimeFile .*'x64'"),
  @('Build-Installer checks nothing else is missing', 'installer\Build-Installer.ps1', 'Get-VcRuntimeNeeded \$binPe'),
  @('Build-Installer can pin the engine', 'installer\Build-Installer.ps1', 'if \(\$h -ne \$EngineSha256\) \{ throw')
)
foreach ($s in $statics) {
  $lines = [IO.File]::ReadAllLines((Join-Path $repo $s[1]))
  Check "E $($s[0])" (@($lines | Where-Object { $_ -match $s[2] }).Count -ge 1) "no line matches $($s[2])"
}
Check 'E the runtime is not taken from git' (@(& git -C $repo ls-files 'third_party/dll-win64/vcruntime140.dll').Count -eq 0)

Remove-WorkDir $Scratch -Keep:$KeepWorkDir
"run_pack_vcruntime_guard: $script:passes passed, $script:fails failed"
if ($script:fails -gt 0) { exit 1 }
exit 0
