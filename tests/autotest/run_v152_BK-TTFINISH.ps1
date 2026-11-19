#Requires -Version 7.3
<#
  run_v152_BK-TTFINISH.ps1 -- lane BK-TTFINISH (1.52): B33 (ORM / DataService generator verbs
  public, region 9 emits the ORM3 FIELD_AS_TYPE form, IDE rows unhidden) + U6 (gen-param-array
  --prepare-queries, the IDE assistant's query preparation).

  1. docs: --help source lists repo gen-orm / update-orm / gen-dataservice with --save-form and
     gen-param-array with --prepare-queries; README / AI-USAGE / wiki no longer call the generator
     verbs "not available"; the CHANGELOG no longer calls them internal.
  2. IDE: tests\plugin\run_v152_TTIDE_menu.ps1 (all six Field Repository rows visible, helpers).
  3. engine (needs -Exe): --save-form rejects a bad value (exit 1); repo --help lists the verbs;
     tests\autotest\run_v152_TTFINISH_prepare_queries.ps1 (U6).
  4. golden (needs -RepoFile or DL_TEST_ORM_REPO): run_fieldrepo_ormgen_golden.ps1 -RequireForm
     (unit checks + 521/528 same ignoring blanks/case, 7 listed drift). Without a repository: SKIP.

  Run: pwsh -File tests\autotest\run_v152_BK-TTFINISH.ps1 [-Exe <drag-lint.exe>] [-RepoFile <dev.dlrepo>]
#>
[CmdletBinding()]
param([string]$Exe = '',
      [string]$RepoFile = $env:DL_TEST_ORM_REPO,
      [string]$WorkDir = "$env:TEMP\drag-lint-v152-ttfinish-$PID")
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$pass = 0; $fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  ok   $Name" }
  else { $script:fail++; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null

# ---- 1. docs ----
$help = [IO.File]::ReadAllText((Join-Path $repo 'src\cli\DRagLint.CLI.HelpText.pas'))
foreach ($v in 'gen-orm', 'update-orm', 'gen-dataservice') {
  Check "help lists repo $v" ($help -match "Writeln\('  drag-lint repo $v ")
}
Check 'help: update-orm carries --save-form' ($help -match "repo update-orm [^\r\n]*--save-form legacy\|current")
Check 'help: gen-param-array carries --prepare-queries' ($help -match "repo gen-param-array [^\r\n]*\[--prepare-queries\]")
foreach ($d in 'README.md', 'docs\AI-USAGE.md', 'docs\wiki\field-repository.md') {
  $t = [IO.File]::ReadAllText((Join-Path $repo $d))
  Check "$d names update-orm" ($t.Contains('update-orm'))
  Check "$d no longer says not available" (-not ($t -match '(gen-orm|update-orm|gen-dataservice)[^\r\n]*not available'))
}
Check 'CHANGELOG no longer calls the generators internal' (-not ([IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md')) -match 'update-orm`? are\s+internal'))

# ---- 2. IDE ----
& { $ErrorActionPreference = 'Continue'; pwsh -NoProfile -File (Join-Path $repo 'tests\plugin\run_v152_TTIDE_menu.ps1') -WorkDir (Join-Path $WorkDir 'menu') *> (Join-Path $WorkDir 'menu.log') }
Check 'IDE: TTIDE menu runner (six rows visible)' ($LASTEXITCODE -eq 0) "(log $WorkDir\menu.log)"

# ---- 3. engine ----
if (-not (Test-Path -LiteralPath $Exe)) { Check "engine exe present ($Exe)" $false }
else {
  $tmpRepo = Join-Path $WorkDir 'empty.dlrepo'
  & { $ErrorActionPreference = 'Continue'; & $Exe repo update-orm --repo $tmpRepo --code-dir $WorkDir --save-form bogus *> (Join-Path $WorkDir 'saveform.log') }
  Check '--save-form bogus -> exit 1' ($LASTEXITCODE -eq 1)
  Check '--save-form bogus names the values' ((Get-Content (Join-Path $WorkDir 'saveform.log') -Raw) -match 'legacy or current')
  $rh = (& { $ErrorActionPreference = 'Continue'; & $Exe repo --help 2>&1 | ForEach-Object { "$_" } } | Out-String)
  Check 'repo --help lists update-orm' ($rh -match 'repo update-orm ')
  & { $ErrorActionPreference = 'Continue'; pwsh -NoProfile -File (Join-Path $repo 'tests\autotest\run_v152_TTFINISH_prepare_queries.ps1') -Exe $Exe -WorkDir (Join-Path $WorkDir 'prep') *> (Join-Path $WorkDir 'prep.log') }
  Check 'U6: --prepare-queries battery' ($LASTEXITCODE -eq 0) "(log $WorkDir\prep.log)"
}

# ---- 4. golden ----
if ([string]::IsNullOrWhiteSpace($RepoFile)) { Write-Host '  SKIP golden (no -RepoFile / DL_TEST_ORM_REPO)' }
else {
  & { $ErrorActionPreference = 'Continue'; pwsh -NoProfile -File (Join-Path $repo 'tests\autotest\run_fieldrepo_ormgen_golden.ps1') -RequireForm -RepoFile $RepoFile -Work (Join-Path $WorkDir 'golden') *> (Join-Path $WorkDir 'golden.log') }
  Check 'golden -RequireForm' ($LASTEXITCODE -eq 0) "(log $WorkDir\golden.log)"
}

Write-Host "BK-TTFINISH: $pass passed, $fail failed"
if ($fail) { exit 1 }
exit 0
