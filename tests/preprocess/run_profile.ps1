<#
  run_profile.ps1 -- TDD harness for PP-Task-7: the define-profile resolver
  (PlatformBuiltins + ProfileFromDproj).

  Exercises the resolver through the staged exe via the pp-profile diagnostic
  verb:
    pp-profile --dproj <file.dproj> [--platform Win32|Win64] [--config Release|Debug]
  which prints the resolved active defines, one lowercased symbol per line,
  SORTED (so we can grep for membership).

  The resolver = PlatformBuiltins(APlatform) UNION the DCC_Define values from the
  .dproj's Base PropertyGroup, the Base_<Platform> group, the selected config's
  PropertyGroup (Cfg_2 for Release, Cfg_1 for Debug) AND that config's
  Cfg_N_<Platform> group, split on ';', dropping the $(DCC_Define) MSBuild
  recursion token, all lowercased + deduped. (The two platform groups were added
  2026-09-23; fixtures/platform_groups.dproj covers them.)

  Since X5 (2026-10-25) the groups are applied IN ORDER with MSBuild semantics: a
  DCC_Define without $(DCC_Define) REPLACES the set so far
  (fixtures/replace_groups.dproj), and the config NAME is mapped to its Cfg_N key
  through the .dproj's own '$(Config)'=='Name' groups, walking CfgParent for a
  child config (fixtures/custom_configs.dproj).

  Fixture fixtures/sample.dproj mirrors src/cli/drag-lint.dproj's structure:
    Base  PropertyGroup DCC_Define = CUSTOM_BASE;$(DCC_Define)
    Cfg_1 (Debug)       DCC_Define = DEBUG;$(DCC_Define)
    Cfg_2 (Release)     DCC_Define = RELEASE;$(DCC_Define)

  Assertions (per the brief):
    --platform Win64 --config Release ->
       CONTAINS win64, mswindows, unicode, ver370 (builtins)
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
  Check 'Win64/Release CONTAINS ver370 (platform builtin)'($rel64 -contains 'ver370')
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

  # --- PLATFORM PropertyGroups (Base_<P>, Cfg_N_<P>) -- 2026-09-23 ---
  # MSBuild applies Base, Base_<Platform>, Cfg_N, Cfg_N_<Platform> for the
  # active platform. The resolver read only Base + Cfg_N, so a define that lives
  # ONLY in a platform group (Micronite2027: EUREKALOG in Base_Win64/Base_Win32)
  # was missing, its {$IFDEF} branch was blanked, and index --project evicted
  # EExtraExceptionInfo.pas. The fixture mirrors that .dproj's layout, including
  # the selector groups whose Condition names BOTH $(Base) and $(Base_Win64) but
  # carry no DCC_Define. See docs\INBOX-pp-profile-ignores-platform-propertygroups.md.
  $plat = Join-Path $fixDir 'platform_groups.dproj'
  $p64d = Profile $plat 'Win64' 'Debug'
  Check 'plat Win64/Debug CONTAINS all_base (Base)'                    ($p64d -contains 'all_base')
  Check 'plat Win64/Debug CONTAINS plat64_only (Base_Win64)'           ($p64d -contains 'plat64_only')
  Check 'plat Win64/Debug CONTAINS debug (Cfg_1)'                      ($p64d -contains 'debug')
  Check 'plat Win64/Debug CONTAINS cfg1_w64 (Cfg_1_Win64)'             ($p64d -contains 'cfg1_w64')
  Check 'plat Win64/Debug NOT plat32_only (Base_Win32 is other platform)' (-not ($p64d -contains 'plat32_only'))
  Check 'plat Win64/Debug NOT cfg2_w32 (Cfg_2_Win32 not selected)'     (-not ($p64d -contains 'cfg2_w32'))
  $p32r = Profile $plat 'Win32' 'Release'
  Check 'plat Win32/Release CONTAINS plat32_only (Base_Win32)'         ($p32r -contains 'plat32_only')
  Check 'plat Win32/Release CONTAINS cfg2_w32 (Cfg_2_Win32)'           ($p32r -contains 'cfg2_w32')
  Check 'plat Win32/Release NOT plat64_only (Base_Win64 is other platform)' (-not ($p32r -contains 'plat64_only'))
  Check 'plat Win32/Release NOT cfg1_w64 (Cfg_1_Win64 not selected)'   (-not ($p32r -contains 'cfg1_w64'))
  $p64r = Profile $plat 'Win64' 'Release'
  Check 'plat Win64/Release NOT cfg1_w64 (Debug platform group not selected)' (-not ($p64r -contains 'cfg1_w64'))
  Check 'plat Win64/Release CONTAINS plat64_only (Base_Win64 is config-independent)' ($p64r -contains 'plat64_only')

  # --- REPLACE semantics (X5, 2026-10-25) ---
  # A DCC_Define WITHOUT the $(DCC_Define) recursion token REPLACES the set
  # inherited so far instead of appending to it -- 94 such non-Base groups in the
  # C:\Projects corpus. The union reader kept the replaced define, so the index
  # parsed {$IFDEF} branches the build never compiles.
  $repl = Join-Path $fixDir 'replace_groups.dproj'
  $r64d = Profile $repl 'Win64' 'Debug'
  Check 'repl Win64/Debug CONTAINS w64_only (Base_Win64 replaces)'      ($r64d -contains 'w64_only')
  Check 'repl Win64/Debug CONTAINS debug (Cfg_1 appends, token first)'  ($r64d -contains 'debug')
  Check 'repl Win64/Debug NOT base_a (replaced by Base_Win64)'          (-not ($r64d -contains 'base_a'))
  Check 'repl Win64/Debug CONTAINS win64 (builtins survive a replace)'  ($r64d -contains 'win64')
  $r32d = Profile $repl 'Win32' 'Debug'
  Check 'repl Win32/Debug CONTAINS base_a (no replace on Win32)'        ($r32d -contains 'base_a')
  Check 'repl Win32/Debug CONTAINS debug'                               ($r32d -contains 'debug')
  $r32r = Profile $repl 'Win32' 'Release'
  Check 'repl Win32/Release CONTAINS only_r32 (Cfg_2_Win32 replaces)'   ($r32r -contains 'only_r32')
  Check 'repl Win32/Release NOT release (replaced by Cfg_2_Win32)'      (-not ($r32r -contains 'release'))
  Check 'repl Win32/Release NOT base_a (replaced by Cfg_2_Win32)'       (-not ($r32r -contains 'base_a'))
  $r64r = Profile $repl 'Win64' 'Release'
  Check 'repl Win64/Release CONTAINS release (appends after replace)'   ($r64r -contains 'release')
  Check 'repl Win64/Release NOT base_a'                                 (-not ($r64r -contains 'base_a'))

  # --- CONFIG NAMES map through the .dproj, not a hard-coded alias (X5) ---
  # custom_configs.dproj: Release=Cfg_1 and Debug=Cfg_2 (SWAPPED), Profiling=Cfg_3
  # (child of Release/Cfg_1), Staging=Cfg_4 (child of Base). The old reader
  # mapped Debug->Cfg_1 and everything else->Cfg_2.
  $cust = Join-Path $fixDir 'custom_configs.dproj'
  $c64d = Profile $cust 'Win64' 'Debug'
  Check 'cust Win64/Debug CONTAINS debug (Debug is Cfg_2 here)'         ($c64d -contains 'debug')
  Check 'cust Win64/Debug NOT release (Cfg_1 is Release here)'          (-not ($c64d -contains 'release'))
  Check 'cust Win64/Debug NOT rel_w64'                                  (-not ($c64d -contains 'rel_w64'))
  $c64r = Profile $cust 'Win64' 'Release'
  Check 'cust Win64/Release CONTAINS release + rel_w64'                 (($c64r -contains 'release') -and ($c64r -contains 'rel_w64'))
  Check 'cust Win64/Release NOT debug'                                  (-not ($c64r -contains 'debug'))
  $c64p = Profile $cust 'Win64' 'Profiling'
  Check 'cust Win64/Profiling CONTAINS profiling + prof_w64 (Cfg_3, Cfg_3_Win64)' (($c64p -contains 'profiling') -and ($c64p -contains 'prof_w64'))
  Check 'cust Win64/Profiling CONTAINS release + rel_w64 (parent Cfg_1 chain)'    (($c64p -contains 'release') -and ($c64p -contains 'rel_w64'))
  Check 'cust Win64/Profiling CONTAINS all_base'                        ($c64p -contains 'all_base')
  Check 'cust Win64/Profiling NOT debug (not Cfg_2)'                    (-not ($c64p -contains 'debug'))
  $c32p = Profile $cust 'Win32' 'Profiling'
  Check 'cust Win32/Profiling NOT prof_w64 / rel_w64 (other platform)'  (-not (($c32p -contains 'prof_w64') -or ($c32p -contains 'rel_w64')))
  $c64s = Profile $cust 'Win64' 'Staging'
  Check 'cust Win64/Staging CONTAINS staging + all_base'                (($c64s -contains 'staging') -and ($c64s -contains 'all_base'))
  Check 'cust Win64/Staging NOT release / debug (parent is Base)'       (-not (($c64s -contains 'release') -or ($c64s -contains 'debug')))

  # --- project-facts reads the SAME effective set (X5 follow-up) ---
  # Project.Facts had its own copy of the old union reader; it now goes through
  # DprojEffectiveDefines / the config chain, so its define list and cfg alias
  # must agree with pp-profile on the replace and custom-config fixtures.
  function Facts([string]$dproj, [string]$platform, [string]$config) {
    $raw = (& $exePath project-facts --dproj $dproj --platform $platform --config $config --json 2>$null) -join "`n"
    $i = $raw.IndexOf('{'); if ($i -lt 0) { return $null }
    return ($raw.Substring($i) | ConvertFrom-Json)
  }
  function FactNames($f) { return @($f.defines | ForEach-Object { $_.name.ToLower() }) }
  $fr = Facts $repl 'Win64' 'Debug'
  Check 'facts repl Win64/Debug NOT base_a (Base_Win64 replaces)'       (-not ((FactNames $fr) -contains 'base_a'))
  Check 'facts repl Win64/Debug CONTAINS w64_only + debug'              (((FactNames $fr) -contains 'w64_only') -and ((FactNames $fr) -contains 'debug'))
  $fr32 = Facts $repl 'Win32' 'Release'
  Check 'facts repl Win32/Release NOT release / base_a (Cfg_2_Win32 replaces)' (-not (((FactNames $fr32) -contains 'release') -or ((FactNames $fr32) -contains 'base_a')))
  $fc = Facts $cust 'Win64' 'Debug'
  Check 'facts cust Win64/Debug cfg = Cfg_2 (swapped alias)'            ($fc.cfg -eq 'Cfg_2')
  Check 'facts cust Win64/Debug CONTAINS debug, NOT release'            (((FactNames $fc) -contains 'debug') -and -not ((FactNames $fc) -contains 'release'))
  $fp = Facts $cust 'Win64' 'Profiling'
  Check 'facts cust Win64/Profiling cfg = Cfg_3, config = Profiling'    (($fp.cfg -eq 'Cfg_3') -and ($fp.config -eq 'Profiling'))
  Check 'facts cust Win64/Profiling CONTAINS profiling + release (chain)' (((FactNames $fp) -contains 'profiling') -and ((FactNames $fp) -contains 'release'))
  $fpb = @($fp.defines | Where-Object { $_.name -eq 'ALL_BASE' })
  Check 'facts cust: ALL_BASE source is Base'                           (($fpb.Count -eq 1) -and ($fpb[0].sources -contains 'Base'))
  $plat2 = Facts (Join-Path $fixDir 'platform_groups.dproj') 'Win64' 'Debug'
  $both = @($plat2.defines | Where-Object { $_.name -eq 'win64' })
  Check 'facts platform_groups: builtin win64 still reported'           ($both.Count -eq 1 -and $both[0].sources -contains 'builtin')

  # --- nonexistent .dproj -> Win64 builtins only, no crash ---
  $none = Profile $missing 'Win64' 'Release'
  Check 'missing.dproj CONTAINS win64 (builtins still returned)'       ($none -contains 'win64')
  Check 'missing.dproj CONTAINS unicode (builtins still returned)'     ($none -contains 'unicode')
  Check 'missing.dproj NOT custom_base (no .dproj parsed)'             (-not ($none -contains 'custom_base'))
  Check 'missing.dproj NOT release (no .dproj parsed)'                 (-not ($none -contains 'release'))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
