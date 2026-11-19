<#
  run_v152_APP2.ps1 -- 1.52 lane APP2 (O01, owner ruling 2026-11-17 17:12): ui-call-in-console-or-service
  follows calls into OTHER units. The per-file rule saw only a dialog call written in the console program's
  own file; here the program calls a routine declared in a used unit that shows the dialog (directly, or
  through another routine), and lint-all reports the call in the program.

  Fixtures tests\fixtures\v152-app2\console (ConsoleProg.dpr {$APPTYPE CONSOLE}; uses UDialogs, UQuiet;
  UOther is NOT used) and tests\fixtures\v152-app2\gui (GuiProg.dpr, same units, no APPTYPE CONSOLE).
  Each folder is indexed into its own db with the engine under test.

    c0  positive control: the per-file rule is live on UDialogs-style code (a console file with ShowMessage fires)
    c1  console: ConsoleProg.dpr line 9 (Hello, UQuiet, no dialog) is silent
    c2  console: line 10 (ShowDone, shows a dialog) fires
    c3  console: line 11 (WrapDone -> ShowDone, transitive) fires
    c4  console: line 12 (UDialogs.ShowDone, qualified) fires
    c5  console: exactly the three lines 10,11,12 -- UOther.Hello (a dialog routine in an unused unit) never leaks
    c6  gui: the same calls are silent (no APPTYPE CONSOLE) -- paired with c2 as its positive twin
    c7  --rule ui-call-in-console-or-service reaches the cross-unit findings (host id)

  With the pre-lane engine c2..c5 and c7 FAIL (RED); the c0/c1/c6 controls pass.

  Usage: pwsh -File tests\autotest\run_v152_APP2.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v152_app2_$PID"
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
$Rule = 'ui-call-in-console-or-service'

$script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}

# lint-all --json is a bare array; line field is start_line. Print raw once, then filter.
function Get-Findings([string]$Db, [string[]]$Extra) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --json @Extra 2>$null }) -join "`n"
  Write-Host ("  raw[{0}]: {1}" -f (Split-Path $Db -Leaf), $out.Substring(0, [Math]::Min(300, $out.Length)))
  if ($out.Trim() -eq '') { return @() }
  return @($out | ConvertFrom-Json | Where-Object { $_.rule -eq $Rule })
}

[void](New-Item -ItemType Directory -Force -Path $WorkDir)
$Fix = Join-Path $Root 'tests\fixtures\v152-app2'
Copy-Item (Join-Path $Fix 'console') $WorkDir -Recurse -Force
Copy-Item (Join-Path $Fix 'gui')     $WorkDir -Recurse -Force
$DbC = Join-Path $WorkDir 'console.sqlite'
$DbG = Join-Path $WorkDir 'gui.sqlite'
Push-Location $WorkDir
try {
  & { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $WorkDir 'console') --db $DbC *> (Join-Path $WorkDir 'index-console.log') }
  & { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $WorkDir 'gui')     --db $DbG *> (Join-Path $WorkDir 'index-gui.log') }

  # c0: the per-file rule is live (a console file with a direct dialog call)
  $c0 = Join-Path $WorkDir 'Direct.pas'
  [IO.File]::WriteAllText($c0, "program Direct;`r`n`r`n{`$APPTYPE CONSOLE}`r`n`r`nuses Vcl.Dialogs;`r`n`r`nbegin`r`n  ShowMessage('x');`r`nend.`r`n")
  $d = (& { $ErrorActionPreference = 'Continue'; & $Exe lint $c0 --json 2>$null }) -join "`n"
  $d0 = @(if ($d.Trim() -eq '') { @() } else { @($d | ConvertFrom-Json | Where-Object { $_.rule -eq $Rule }) })
  Check 'c0 positive control: per-file rule fires on a direct dialog call' ($d0.Count -ge 1) "raw: $d"

  $fc = @(Get-Findings $DbC @())
  $prog = @($fc | Where-Object { [IO.Path]::GetFileName([string]$_.file_path) -eq 'ConsoleProg.dpr' })
  $lines = @($prog | ForEach-Object { [int]$_.start_line } | Sort-Object)
  Write-Host ("  console ConsoleProg.dpr lines: " + ($lines -join ','))
  Check 'c1 console: Hello (no dialog) is silent'             (-not ($lines -contains 9))
  Check 'c2 console: ShowDone fires'                          ($lines -contains 10)
  Check 'c3 console: WrapDone (transitive) fires'             ($lines -contains 11)
  Check 'c4 console: qualified UDialogs.ShowDone fires'       ($lines -contains 12)
  Check 'c5 console: exactly lines 10,11,12 (UOther.Hello does not leak)' (($lines -join ',') -eq '10,11,12') ("got " + ($lines -join ','))

  $fg = @(Get-Findings $DbG @())
  Check 'c6 gui: same calls are silent (twin of c2)' (@($fg | Where-Object { [IO.Path]::GetFileName([string]$_.file_path) -eq 'GuiProg.dpr' }).Count -eq 0) ("got " + $fg.Count)

  $fn = @(Get-Findings $DbC @('--rule', $Rule))
  Check 'c7 --rule reaches the cross-unit findings' (@($fn | Where-Object { [IO.Path]::GetFileName([string]$_.file_path) -eq 'ConsoleProg.dpr' }).Count -eq 3) ("got " + $fn.Count)
}
finally { Pop-Location }

Write-Host ("run_v152_APP2: {0} failure(s)" -f $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
