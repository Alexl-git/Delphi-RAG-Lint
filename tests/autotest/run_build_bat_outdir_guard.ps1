<#
  run_build_bat_outdir_guard.ps1 -- 149 RQ item 5.

  build\build_draglint.bat and build\build_phase0.bat staged the Win64 exe into
  third_party\dll (the x86 directory). An x86 DLL beside a Win64 exe = 0xC000007B.
  Rule: no build\*.bat may assign OUT (or stage) into third_party\dll without
  the -win32 / -win64 suffix. Positive control: the matcher must fire on a
  synthetic bad line.
  149 INT: an x86-ONLY build bat (it links /MACHINE:X86, e.g. 149 DF's _builddfm32.bat) staging its
  x86 DLL into third_party\dll is the intended layout (x86 -> dll-win32 + dll), so it is exempt; a
  bat without /MACHINE:X86 is still checked (second control below).
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bad = '(?im)^\s*(set\s+\w+=|copy\b|xcopy\b).*third_party\\dll(?![-\w])'

# positive control
if ('set OUT=%ROOT%\third_party\dll' -notmatch $bad) { Write-Host 'FAIL control did not fire'; exit 1 }
if ('set OUT=%ROOT%\third_party\dll-win64' -match $bad) { Write-Host 'FAIL control fired on good line'; exit 1 }
$x86Only = '(?im)/MACHINE:X86\b'
if ('copy a.dll %ROOT%\third_party\dll\a.dll' -match $x86Only) { Write-Host 'FAIL control: a bat without /MACHINE:X86 would be exempt'; exit 1 }

$fail = 0
foreach ($f in Get-ChildItem (Join-Path $root 'build') -Filter *.bat) {
  $t = [IO.File]::ReadAllText($f.FullName)
  if (($t -match $bad) -and ($t -notmatch $x86Only)) { Write-Host ('FAIL ' + $f.Name + ' stages into third_party\dll'); $fail++ }
}
if ($fail) { Write-Host "build_bat_outdir_guard: $fail FAIL"; exit 1 }
Write-Host 'build_bat_outdir_guard: PASS'
exit 0
