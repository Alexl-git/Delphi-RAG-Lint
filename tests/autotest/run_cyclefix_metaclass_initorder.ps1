<#
  run_cyclefix_metaclass_initorder.ps1 -- lane CYC3 finisher (wave 152c, FOUND-152c a): the metaclass hand-over
  step of `cycles --plan` never says "Checked: its own initialization section makes none of these calls" when the
  consumer's initialization DOES make them and the init order is proved -- it says the initialization reaches the
  calls and prints the proof line instead (as the routine-call inversion step does).

  Fixture tests\fixtures\cyclefix\metainit: MiA -> MiC -> MiB -> MiA plus MiA -> MiB; MiA's initialization calls
  MiAStart, which passes TMiJob (MiB) to RegisterClass. With MiA listed first in the .dpr, MiB initializes before MiA
  (proved); with MiB first it does not (refused `init-order`).
    a  MiA first: recipe metaclass hand-over, the "init order:" proof line, "its initialization section reaches
       these calls", and NOT the "Checked: its own initialization section makes none" sentence (RED on the base).
    b  POSITIVE CONTROL, MiB first: the same edge is refused `init-order` -- the proof can say no, so row a is the
       proof talking, not a constant.
  Indexed and planned with the platform library (RegisterClass's parameter type). Exit 0 all PASS, 1 any FAIL,
  2 setup; SKIP (exit 0) without the library.
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-metainit-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win32.sqlite'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\HermeticEngine.ps1"
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library ($LibraryDb): RegisterClass's parameter type is read from it" -ForegroundColor Yellow; exit 0 }
$Exe   = Get-HermeticEngine $Exe
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix\metainit'
$Ascii = [Text.Encoding]::ASCII

function Get-Plan([string]$Tag, [string[]]$Order) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem $Fx -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  $dpr = Join-Path $root 'MetaInit.dpr'
  $list = ($Order | ForEach-Object { "  $_ in '$_.pas'" }) -join ",`r`n"
  [IO.File]::WriteAllText($dpr, [regex]::Replace([IO.File]::ReadAllText($dpr, $Ascii), '(?s)uses\r\n.*?;\r\n', "uses`r`n$list;`r`n"), $Ascii)
  $dproj = Join-Path $root 'MetaInit.dproj'
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try {
    $null | & $Exe index --project $dproj --db $db --library-db $LibraryDb *> "$db.log"
    return ($null | & $Exe cycles --plan --project $dproj --db $db --library-db $LibraryDb 2>$null | Out-String)
  } finally { Pop-Location }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== a: MiA first (MiB initializes first: proved)' -ForegroundColor Cyan
  $plan = Get-Plan 'afirst' @('MiA', 'MiB', 'MiC')
  Check 'a.0 the plan is not empty' ($plan -match '(?m)^## Cycle 1:') "plan: $($plan.Length) chars"
  Check 'a.1 recipe: metaclass hand-over' $plan.Contains('Recipe: **metaclass hand-over**')
  Check 'a.2 the proof line is printed' ($plan -match '(?m)^- init order: `MiB` initializes before `MiA` in `MetaInit\.dpr`')
  Check 'a.3 the pass step says the initialization reaches the calls' ($plan -match '(?m)^- `MiA\.pas` passes `\w+` instead of `TMiJob` \(line [\d, ]+\); its initialization section reaches these calls\.\r?$')
  Check 'a.4 no "Checked: its own initialization section makes none" sentence' (-not $plan.Contains('Checked: its own initialization section makes none'))
  Check 'a.5 Fix it is mechanical' ($plan -match '(?m)^Fix it \(mechanical, compile-gated\):')

  Write-Host '== b: MiB first (positive control: refused init-order)' -ForegroundColor Cyan
  $plan = Get-Plan 'bfirst' @('MiB', 'MiA', 'MiC')
  Check 'b.1 the edge mia -> mib is refused init-order' ($plan -match '(?m)^- `mia -> mib`: .*refused: init-order --')
  Check 'b.2 no proof line' (-not ($plan -match '(?m)^- init order:'))
} finally {
  try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
}
Write-Host ("passed {0}{1}" -f $script:Passed, $(if ($script:Failed) { ', FAILURES' } else { ', all PASS' }))
exit $(if ($script:Failed) { 1 } else { 0 })
