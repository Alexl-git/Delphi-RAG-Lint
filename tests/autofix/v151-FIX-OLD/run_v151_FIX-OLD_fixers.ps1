<#
  run_v151_FIX-OLD_fixers.ps1 -- wave v151 lane FIX-OLD: APPLY proof of every fixer the lane adds.

  Case layout (one directory per case, beside this folder):
    tests\autofix\v151-FIX-OLD-<case>\FoUnit.pas            input unit (exports RunAll); the rule fires on it
    tests\autofix\v151-FIX-OLD-<case>\FoUnit.expected.pas   expected bytes after the fix, written BY HAND
    tests\autofix\v151-FIX-OLD-<case>\case.txt              line 1: the rule id; line 2 (optional): the number
                                                            of findings that legitimately remain (declined shapes)
                                                            line 3 (optional): extra lint arguments, space-separated; the token
                                                            lint-all drives the case through lint-all (project rules);
                                                            the token library becomes --library-db <LibraryDb> (the
                                                            unwith route needs TObject's members; SKIP when missing)
  Shared project: tests\autofix\v151-FIX-OLD\template\FoDemo.dpr + FoDemo.dproj (uses FoUnit).

  Per case, on a scratch copy:
    1. index the project into a scratch DB (--library-db none)
    2. POSITIVE CONTROL: lint --rule <id> finds at least one more finding than case.txt line 2
    3. lint --in FoUnit.pas --enable <id> --fix --fix-rule <id> --apply --no-backup --project FoDemo.dproj
       --compile-gate: exit 0, real bytes written THROUGH the compile gate (baseline build, write, after
       build, rollback on a compile error), FoUnit.pas byte-identical to FoUnit.expected.pas
    4. the fixed project builds (the gate already built it; dcc64 again proves the bytes on disk)
    5. after a reindex, lint --rule <id> leaves exactly case.txt line 2 findings
  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing.
  Usage: run_v151_FIX-OLD_fixers.ps1 [-Exe <drag-lint.exe>] [-Filter <case-wildcard>]
#>
param(
  [string]$Exe    = '',
  [string]$Filter = '*',
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$env:DRAGLINT_RENAME_TEST_UNGATED = '1'   # the rename proof's test seam: these fixtures have no library
$script:pass = 0; $script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  ok   $Name" }
  else { $script:fail++; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Tpl  = Join-Path $PSScriptRoot 'template'
$Root = Split-Path $PSScriptRoot -Parent
$Tmp  = Join-Path $env:TEMP ('v151_fixold_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function Count-Findings([string]$Db, [string]$Unit, [string]$Rule, [string[]]$Extra = @()) {
  if ($Extra -contains 'lint-all') { $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --rule $Rule --json 2>$null } | Out-String }
  else { $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint --in $Unit --db $Db --rule $Rule --json @Extra 2>$null } | Out-String }
  $t = $raw.Trim()
  if (-not $t.StartsWith('[')) { return -1 }
  $rows = @(($t | ConvertFrom-Json) | ForEach-Object { $_ })
  return @($rows | Where-Object { $_.rule -eq $Rule -or $_.rule_id -eq $Rule -or $_.id -eq $Rule }).Count
}
function Build-Project([string]$Dir) {
  $bat = Join-Path $Dir 'b.bat'
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /d `"$Dir`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal FoDemo.dproj`r`necho BUILD_EXITCODE=%ERRORLEVEL%`r`n")
  $log = Join-Path $Dir 'build.log'
  Start-Process cmd.exe -ArgumentList '/c', $bat -Wait -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError (Join-Path $Dir 'build.err')
  $txt = Get-Content $log -Raw
  return ($txt -match 'BUILD_EXITCODE=0') -and ($txt -notmatch 'error E\d+')
}

$cases = Get-ChildItem $Root -Directory -Filter "v151-FIX-OLD-$Filter" | Where-Object { Test-Path (Join-Path $_.FullName 'case.txt') }
foreach ($c in $cases) {
  $spec  = @(Get-Content (Join-Path $c.FullName 'case.txt'))
  $rule  = $spec[0].Trim()
  $leave = if ($spec.Count -gt 1 -and $spec[1].Trim() -ne '') { [int]$spec[1] } else { 0 }
  $extra = @(if ($spec.Count -gt 2 -and $spec[2].Trim() -ne '') { @($spec[2].Trim() -split ' ') } else { @() })
  if ($extra -contains 'library') {
    if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP $($c.Name): no platform library ($LibraryDb)" -ForegroundColor Yellow; continue }
    $extra = @($extra | Where-Object { $_ -ne 'library' }) + @('--library-db', $LibraryDb)
  }
  Write-Host "case $($c.Name) ($rule, leaves $leave)"
  $d = Join-Path $Tmp $c.Name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  Copy-Item (Join-Path $Tpl '*') $d
  Copy-Item (Join-Path $c.FullName 'FoUnit.pas') $d
  $unit = Join-Path $d 'FoUnit.pas'; $proj = Join-Path $d 'FoDemo.dproj'; $db = Join-Path $d 'p.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project $proj --db $db --library-db none *> (Join-Path $d 'index.log') }
  $before = Count-Findings $db $unit $rule $extra
  Check "$($c.Name): rule fires before the fix ($before > $leave)" ($before -gt $leave)
  if ($extra -contains 'lint-all') { $out = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --enable $rule --fix --fix-rule $rule --apply --no-backup --rsvars $Rsvars --project $proj --compile-gate 2>&1 | ForEach-Object { "$_" } } | Out-String }
  else { $out = & { $ErrorActionPreference = 'Continue'; & $Exe lint --in $unit --db $db --enable $rule --fix --fix-rule $rule --apply --no-backup --rsvars $Rsvars --project $proj --compile-gate @extra 2>&1 | ForEach-Object { "$_" } } | Out-String }
  $code = $LASTEXITCODE
  [IO.File]::WriteAllText((Join-Path $d 'fix.log'), $out)
  Check "$($c.Name): --fix --compile-gate exit 0" ($code -eq 0) "exit=$code; see $d\fix.log"
  $exp = [IO.File]::ReadAllBytes((Join-Path $c.FullName 'FoUnit.expected.pas'))
  $got = [IO.File]::ReadAllBytes($unit)
  $same = ($exp.Length -eq $got.Length) -and (-not (Compare-Object $exp $got -SyncWindow 0))
  Check "$($c.Name): written bytes = FoUnit.expected.pas" $same "see $unit"
  Check "$($c.Name): the written project builds" (Build-Project $d) "see $d\build.log"
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project $proj --db $db --library-db none *> (Join-Path $d 'reindex.log') }
  $after = Count-Findings $db $unit $rule $extra
  Check "$($c.Name): $after finding(s) left (expected $leave)" ($after -eq $leave)
}
if (-not $cases) { Check 'at least one case found' $false }
Write-Host ("v151 FIX-OLD fixers: {0} pass / {1} fail (scratch {2})" -f $script:pass, $script:fail, $Tmp)
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
