<#
  run_cyclefix_refusal_reasons.ps1 -- lane CYC3 (wave 152c, fabcyc cases 14 / 15): a base-class refusal that stays a
  refusal says WHY in one clause, so nobody reads it as a gap to be filled later.

  Pairs, each copied from docs\examples\cycle-lab (LabVar, LabGuard, LabRc) or tests\fixtures\cyclefix\genericarg
  into a two-unit program of its own, indexed with the platform library (class ancestry):
    var   LabVar   `var pWidget: TLabVarWidget`         -> "... (E2033), so every caller's variable would have to be retyped"
    res   LabGuard  a function result of the class       -> "every caller's expression would change type; ... not a cut"
    rc    LabRc     a function result + TInterfacedObject -> the result clause AND "; also, ... descends from
                    `TInterfacedObject`: an interface reference would count the object and free it ..."
    gen   GenericArg `TList<TGenWidget>` in a signature   -> "`TList<TGenWidget>` and `TList<TGenWidgetBase>` are
                    different types (E2010)"
  For each: the refusal KIND is asserted first (unchanged from the base engine: ctor-inversion-surface / base-class)
  and `Fix it: not available`, then the clause. POSITIVE CONTROL: the clause is searched in the refusal line only, and
  each pair's clause differs, so a constant emptied or a clause attached to the wrong site fails its row; the kind
  rows pass on the base engine too (the identity half), the clause rows fail there (RED: 4 of 4).
  Exit 0 all PASS, 1 any FAIL, 2 setup; SKIP (exit 0) without the platform library.
#>
[CmdletBinding()]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }),
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win32.sqlite',
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-reasons-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Lab  = Join-Path $Repo 'docs\examples\cycle-lab'
$Ascii = [Text.Encoding]::ASCII
$Dproj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\genericarg\GenericArg.dproj'), $Ascii)

# A two-unit program from two existing units: .dpr + a .dproj made from the genericarg one.
function New-Pair([string]$Tag, [string]$From, [string]$U1, [string]$U2) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  foreach ($u in $U1, $U2) { Copy-Item (Join-Path $From "$u.pas") (Join-Path $root "$u.pas") }
  $name = "Reason$Tag"
  $dpr = "program $name;`r`n`r`n{`$APPTYPE CONSOLE}`r`n`r`nuses`r`n  $U1 in '$U1.pas',`r`n  $U2 in '$U2.pas';`r`n`r`nbegin`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $root "$name.dpr"), $dpr, $Ascii)
  $dp = $Dproj.Replace('GenericArg', $name).Replace('GenHost.pas', "$U1.pas").Replace('GenWidget.pas', "$U2.pas").Replace('DEBUG;$(DCC_Define)', 'DEBUG;LAB_EXTRA;$(DCC_Define)')
  [IO.File]::WriteAllText((Join-Path $root "$name.dproj"), $dp, $Ascii)
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try {
    $null | & $Exe index --project (Join-Path $root "$name.dproj") --db $db --library-db $LibraryDb *> "$db.log"
    return ($null | & $Exe cycles --plan --project (Join-Path $root "$name.dproj") --db $db --library-db $LibraryDb 2>$null | Out-String)
  } finally { Pop-Location }
}
# The refusal line of class pClass: "- `TX` (class, `U.pas` line N): refused: <kind> -- <text>".
function Get-Refusal([string]$Plan, [string]$Class) {
  $m = [regex]::Match($Plan, '(?m)^- `' + [regex]::Escape($Class) + '` \(class, [^)]*\): refused: ([\w-]+) -- (.*)$')
  if (-not $m.Success) { return @{ Kind = ''; Text = '' } }
  return @{ Kind = $m.Groups[1].Value; Text = $m.Groups[2].Value.TrimEnd() }
}

$Cases = @(
  @{ Tag = 'var'; From = $Lab; U1 = 'LabVarHost'; U2 = 'LabVarWidget'; Class = 'TLabVarWidget'; Kind = 'ctor-inversion-surface'
     Clause = 'a base class cannot stand in for it -- the compiler requires the actual and the formal `var` parameter to be of the identical type (E2033), so every caller''s variable would have to be retyped' },
  @{ Tag = 'res'; From = $Lab; U1 = 'LabGuardA'; U2 = 'LabGuardB'; Class = 'TLabGuardB'; Kind = 'ctor-inversion-surface'
     Clause = 'a function result of type `TLabGuardB` -- every caller''s expression would change type; that is retyping the callers, not a cut' },
  @{ Tag = 'rc'; From = $Lab; U1 = 'LabRcHost'; U2 = 'LabRcWidget'; Class = 'TLabRcWidget'; Kind = 'ctor-inversion-surface'
     Clause = 'not a cut; also, `TLabRcWidget` descends from `TInterfacedObject`: an interface reference would count the object and free it when the reference goes out of scope while plain object references still hold it' },
  @{ Tag = 'gen'; From = (Join-Path $Repo 'tests\fixtures\cyclefix\genericarg'); U1 = 'GenHost'; U2 = 'GenWidget'; Class = 'TGenWidget'; Kind = 'base-class'
     Clause = '`TGenWidget` is a generic type argument here (`TList<TGenWidget>`) -- `TList<TGenWidget>` and `TList<TGenWidgetBase>` are different types (E2010)' }
)
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  foreach ($c in $Cases) {
    Write-Host "== $($c.Tag): $($c.Class)" -ForegroundColor Cyan
    $plan = New-Pair $c.Tag $c.From $c.U1 $c.U2
    $r = Get-Refusal $plan $c.Class
    Check "$($c.Tag).kind refusal kind is $($c.Kind) and Fix it is not available (unchanged)" (($r.Kind -eq $c.Kind) -and ($plan -match '(?m)^Fix it: not available')) "kind=[$($r.Kind)] text=[$($r.Text)]"
    Check "$($c.Tag).reason the refusal says why" ($r.Text.Contains($c.Clause)) "text=[$($r.Text)]"
  }
} finally {
  try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
}
Write-Host ("passed {0}, {1}" -f $script:Passed, $(if ($script:Failed) { 'FAILED' } else { 'all PASS' }))
if ($script:Failed) { exit 1 } else { exit 0 }
