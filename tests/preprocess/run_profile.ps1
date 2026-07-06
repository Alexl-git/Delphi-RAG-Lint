<#
  run_profile.ps1 -- TDD harness for PP-Task-7: the define-profile resolver
  (PlatformBuiltins + ProfileFromDproj).

  Exercises the resolver through the staged exe via the pp-profile diagnostic
  verb:
    pp-profile --dproj <file.dproj> [--platform Win32|Win64] [--config Release|Debug]
  which prints the resolved active defines, one lowercased symbol per line,
  SORTED (so we can grep for membership).

  The resolver = PlatformBuiltins(APlatform) UNION the DCC_Define values from the
  .dproj's Base PropertyGroup AND the selected config's PropertyGroup (Cfg_2 for
  Release, Cfg_1 for Debug), split on ';', dropping the $(DCC_Define) MSBuild
  recursion token, all lowercased + deduped.

  Fixture fixtures/sample.dproj mirrors src/cli/drag-lint.dproj's structure:
    Base  PropertyGroup DCC_Define = CUSTOM_BASE;$(DCC_Define)
    Cfg_1 (Debug)       DCC_Define = DEBUG;$(DCC_Define)
    Cfg_2 (Release)     DCC_Define = RELEASE;$(DCC_Define)

  Assertions (per the brief):
    --platform Win64 --config Release ->
       CONTAINS win64, mswindows, unicode, compiler_version_37 (builtins)
       CONTAINS release, custom_base (Release + Base DCC_Define)
       NOT      debug (Cfg_1/Debug not selected)
    --config Debug   -> CONTAINS debug, NOT release
    --platform Win32 -> CONTAINS win32 + cpux86, NOT win64
    nonexistent .dproj -> Win64 builtins only (no crash, no custom_base/release)

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures')).Path
$sample  = Join-Path $fixDir 'sample.dproj'
$missing = Join-Path $fixDir 'no_such_file.dproj'

# Run pp-profile and return the set of lowercased define lines (an array).
function Profile([string]$dproj, [string]$platform, [string]$config) {
  $cliArgs = @('pp-profile', '--dproj', $dproj)
  if ($platform) { $cliArgs += @('--platform', $platform) }
  if ($config)   { $cliArgs += @('--config',   $config)   }
  $out = & $exePath @cliArgs 2>$null
  return @($out | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' })
}

Push-Location C:\TEMP
try {
  # --- Win64 / Release ---
  $rel64 = Profile $sample 'Win64' 'Release'
  Check 'Win64/Release CONTAINS win64 (platform builtin)'              ($rel64 -contains 'win64')
  Check 'Win64/Release CONTAINS mswindows (platform builtin)'          ($rel64 -contains 'mswindows')
  Check 'Win64/Release CONTAINS unicode (platform builtin)'            ($rel64 -contains 'unicode')
  Check 'Win64/Release CONTAINS compiler_version_37 (platform builtin)'($rel64 -contains 'compiler_version_37')
  Check 'Win64/Release CONTAINS release (Cfg_2 DCC_Define)'            ($rel64 -contains 'release')
  Check 'Win64/Release CONTAINS custom_base (Base DCC_Define)'         ($rel64 -contains 'custom_base')
  Check 'Win64/Release NOT debug (Cfg_1 not selected)'                 (-not ($rel64 -contains 'debug'))

  # --- Win64 / Debug ---
  $dbg64 = Profile $sample 'Win64' 'Debug'
  Check 'Win64/Debug CONTAINS debug (Cfg_1 DCC_Define)'                ($dbg64 -contains 'debug')
  Check 'Win64/Debug CONTAINS custom_base (Base DCC_Define)'           ($dbg64 -contains 'custom_base')
  Check 'Win64/Debug NOT release (Cfg_2 not selected)'                 (-not ($dbg64 -contains 'release'))

  # --- Win32 / Release ---
  $rel32 = Profile $sample 'Win32' 'Release'
  Check 'Win32/Release CONTAINS win32 (platform builtin)'              ($rel32 -contains 'win32')
  Check 'Win32/Release CONTAINS cpux86 (platform builtin)'             ($rel32 -contains 'cpux86')
  Check 'Win32/Release NOT win64 (wrong-platform builtin absent)'      (-not ($rel32 -contains 'win64'))
  Check 'Win32/Release NOT cpu64bits (wrong-platform builtin absent)'  (-not ($rel32 -contains 'cpu64bits'))

  # --- nonexistent .dproj -> Win64 builtins only, no crash ---
  $none = Profile $missing 'Win64' 'Release'
  Check 'missing.dproj CONTAINS win64 (builtins still returned)'       ($none -contains 'win64')
  Check 'missing.dproj CONTAINS unicode (builtins still returned)'     ($none -contains 'unicode')
  Check 'missing.dproj NOT custom_base (no .dproj parsed)'             (-not ($none -contains 'custom_base'))
  Check 'missing.dproj NOT release (no .dproj parsed)'                 (-not ($none -contains 'release'))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
