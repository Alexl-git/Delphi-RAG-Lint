<#
  run_cyclefix_cyc4_dcc.ps1 -- lane cyc4: four defects of `cycles --fix` measured by lane fabcyc, each proved by the
  real compile gate (`--apply`), an independent msbuild, and stdout compared byte for byte with the untouched build.

  D1  Mutual leaves. Two units whose moved classes need each other (docs\examples\cycle-lab\illegal, fixture leafmerge)
      printed "mechanical", gave each class its own leaf (F2047 again) and kept the old uses. Now: ONE leaf, forward
      declarations where a class is used before its place, ancestors and by-value types first, both old entries removed.
      A set that cannot share one `type` block (leafmergeconst) refuses coupling-remains, as does a plan whose own
      prediction still shows the interface coupling.
  D2  `init-order` read the FINALIZATION section as initialization (fixture finalsect). Now such a call is planned when
      the declaring unit (which finalizes first after the cut) has nothing the routine could see finalized; otherwise it
      refuses finalization-order. A name in the real initialization section still refuses init-order.
  D3  A `{ }` comment read as `Unit.Word` was a qualified-ref refusal, and `Unit.GVar` could not follow its move
      (fixtures qualglobal, qualparta). Now only code counts and the text becomes `Leaf.GVar`; strings and comments stay.
      A qualified name that does not move (a routine) still refuses qualified-ref.
  C5  A routine passed as a whole argument (fixture routinearg): the pointer is passed. `@F`, a parameterless function
      (its RESULT is the argument) and an argument on a line of its own still refuse routine-not-called.

  POSITIVE CONTROLS: every "refused" case above is a control of the planner; for the compile check, a merged leaf with
  its forward declaration removed must NOT build (pc1). Needs RAD Studio; SKIPs (exit 0) without it. Works under %TEMP%.
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-cyc4-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$script:N = 0

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
# A private copy of a fixture, patched, indexed. $Fix is a tests\fixtures\cyclefix name or a repo-relative dir.
function New-Proj([string]$Fix, [string]$Name, [scriptblock]$Patch = $null) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  $from = Join-Path $Repo "tests\fixtures\cyclefix\$Fix"
  if (-not (Test-Path $from)) { $from = Join-Path $Repo $Fix }
  Get-ChildItem $from -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root "$Name.dproj") --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root "$Name.dproj"); Db = $db; Name = $Name }
}
function Run-Fix($P, [string[]]$Extra) {
  $a = @('cycles', '--fix', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', 'none', '--format', 'json') + $Extra
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += $x.kind } } }
  foreach ($x in @($j.refusals)) { if ($x) { $k += $x.kind } }
  $r = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $r += "$($x.kind): $($x.reason)" } } }
  return @{ Exit = $code; Out = $out; Kinds = $k; Reasons = ($r -join ' || ') }
}
function Refused($P) { return Run-Fix $P @('--no-compile', '--shadow-out', "$($P.Root)-shadow") }
function Get-Plan($P) {
  Push-Location $WorkDir
  try { return ($null | & $Exe cycles --plan --project $P.Dproj --db $P.Db --library-db none 2>$null | Out-String) } finally { Pop-Location }
}
function Get-Cycles($P) {
  Push-Location $WorkDir
  try {
    $null | & $Exe index --project $P.Dproj --db $P.Db --library-db none *> "$($P.Db).relog"
    return ($null | & $Exe cycles --db $P.Db --library-db none 2>$null | Out-String)
  } finally { Pop-Location }
}
function Invoke-Build($P) {
  $bat = "$($P.Root).build.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $P.Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $P.Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program($P) {
  $exeP = Join-Path $P.Root "Win64\Debug\$($P.Name).exe"
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii)
}
# Applies the plan on one copy and proves it: exit 0, no refusal, cycle gone, builds, same stdout as an untouched copy.
function Prove-Apply([string]$Tag, [string]$Fix, [string]$Name, [scriptblock]$Patch = $null, [string[]]$Extra = @()) {
  $base = New-Proj $Fix $Name $Patch
  $b0 = Invoke-Build $base
  Check "$Tag untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program $base
  $P = New-Proj $Fix $Name $Patch
  $a = Run-Fix $P (@('--apply') + $Extra)
  Check "$Tag --apply: exit 0, no refusal" (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons) $($a.Out)"
  $b1 = Invoke-Build $P
  Check "$Tag the applied copy builds (independent msbuild)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program $P
  Check "$Tag stdout is byte-identical to the untouched build" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) "before=[$out0] after=[$out1]"
  return $P
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  # ---------------------------------------------------------------- D1
  Write-Host '== D1 cycle-lab illegal: mutual classes share one leaf' -ForegroundColor Cyan
  $Ill = New-Proj 'docs\examples\cycle-lab\illegal' 'IllegalLab'
  $plan = Get-Plan $Ill
  Write-Host ('  decisions: ' + (([regex]::Matches($plan, '(?m)^- `Ill\w+\.pas`.*$') | ForEach-Object { $_.Value.Substring(0, [Math]::Min(90, $_.Value.Length)) }) -join ' | ')) -ForegroundColor DarkGray
  Check 'd1.1 both old interface entries are removed, none kept' (
    ($plan -match '(?m)^- `IllOrders\.pas` / `IllCustomers`:.*\*\*remove\*\*') -and ($plan -match '(?m)^- `IllCustomers\.pas` / `IllOrders`:.*\*\*remove\*\*') -and ($plan -notmatch '\*\*keep\*\*')) $plan
  Check 'd1.2 one new unit, holding a forward declaration' ((([regex]::Matches($plan, '(?m)^unit \S+\.Untangle;')).Count -eq 1) -and ($plan -match '(?m)^  TIll\w+ = class;')) $plan
  $a = Run-Fix $Ill @('--apply')
  Check 'd1.3 --apply: exit 0, no refusal (F2047 baseline accepted, the build after the edit proves it)' (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Out)"
  $left = Get-Cycles $Ill
  Check 'd1.4 no cycle after a re-index' ($left -match 'No circular unit dependencies found\.') $left
  $b = Invoke-Build $Ill
  Check 'd1.5 builds (independent msbuild): the F2047 is gone' $b.Ok $b.Errors
  $leaf = @(Get-ChildItem $Ill.Root -Filter '*.Untangle.pas' | ForEach-Object FullName)[0]
  if (-not $leaf) { Check 'pc1 the merged leaf exists' $false 'no *.Untangle.pas was written'; $leaf = Join-Path $Ill.Root 'none.Untangle.pas'; [IO.File]::WriteAllText($leaf, '', $Ascii) }
  $lt = [IO.File]::ReadAllText($leaf, $Ascii)
  [IO.File]::WriteAllText($leaf, [regex]::Replace($lt, '(?m)^  TIll\w+ = class;\r\n', ''), $Ascii)
  $pc = Invoke-Build $Ill
  Check 'pc1 without the forward declaration it does NOT build (the build check has teeth)' (-not $pc.Ok) 'it built'

  Write-Host '== D1 leafmerge: a heritage edge and a record by value order the leaf' -ForegroundColor Cyan
  $Lm = New-Proj 'leafmerge' 'LeafMerge'
  $a = Run-Fix $Lm @('--apply')
  Check 'd1.6 --apply: exit 0, no refusal' (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Out)"
  $left = Get-Cycles $Lm
  Check 'd1.7 no cycle after a re-index' ($left -match 'No circular unit dependencies found\.') $left
  $b = Invoke-Build $Lm
  Check 'd1.8 builds' $b.Ok $b.Errors
  $o = Invoke-Program $Lm
  Check 'd1.9 the program runs as written' ($o.Trim() -ceq 'child3') "[$o]"

  Write-Host '== D1 refusals: never a wrong "mechanical"' -ForegroundColor Cyan
  $Lc = New-Proj 'leafmergeconst' 'LeafMergeConst'
  $h0 = Get-SrcHash $Lc.Root
  $r = Refused $Lc
  Check 'd1.10 a const in the mutual set refuses coupling-remains (exit 1)' (($r.Exit -eq 1) -and ($r.Kinds -contains 'coupling-remains')) "exit=$($r.Exit) kinds=$($r.Kinds -join ',')"
  $r = Run-Fix $Lc @('--apply')
  Check 'd1.11 --apply refused too, no source written' (($r.Exit -eq 1) -and ((Get-SrcHash $Lc.Root) -eq $h0)) "exit=$($r.Exit)"
  # the prediction guard: each unit keeps the other's entry for a qualified const that does not move
  $Lq = New-Proj 'leafmergeconst' 'LeafMergeConst' {
    param($d)
    [IO.File]::WriteAllText((Join-Path $d 'LcA.pas'), (@'
unit LcA;

interface

uses
  LcB;

type
  /// <summary>Named by LcB.</summary>
  TLcKindA = (lkaOne, lkaTwo);

const
  /// <summary>Read by LcB, qualified.</summary>
  CLcTopA = 1;
  /// <summary>Stays here and keeps the uses entry.</summary>
  CLcFromB = LcB.CLcTopB + 1;

var
  /// <summary>The need on LcB.</summary>
  GLcA: TLcKindB;

implementation

end.
'@ -replace "`r?`n", "`r`n"), $Ascii)
    [IO.File]::WriteAllText((Join-Path $d 'LcB.pas'), (@'
unit LcB;

interface

uses
  LcA;

type
  /// <summary>Named by LcA.</summary>
  TLcKindB = (lkbOne, lkbTwo);

const
  /// <summary>Read by LcA, qualified.</summary>
  CLcTopB = 2;
  /// <summary>Stays here and keeps the uses entry.</summary>
  CLcFromA = LcA.CLcTopA + 1;

var
  /// <summary>The need on LcA.</summary>
  GLcB: TLcKindA;

implementation

end.
'@ -replace "`r?`n", "`r`n"), $Ascii)
  }
  $r = Refused $Lq
  Check 'd1.12 a plan whose prediction keeps the interface coupling refuses coupling-remains' (($r.Exit -eq 1) -and ($r.Kinds -contains 'coupling-remains')) "exit=$($r.Exit) kinds=$($r.Kinds -join ',') $($r.Reasons)"

  # ---------------------------------------------------------------- D2
  Write-Host '== D2 finalization is not initialization' -ForegroundColor Cyan
  $P = Prove-Apply 'd2.1' 'finalsect' 'FinalSect'
  Check 'd2.2 the routine goes through its pointer' ([IO.File]::ReadAllText((Join-Path $P.Root 'FsA.pas'), $Ascii) -match '(?m)^\s*FsBStopPtr;') ''
  $null = Prove-Apply 'd2.3 (empty finalization in the declaring unit)' 'finalsect' 'FinalSect' {
    param($d) Edit-Text (Join-Path $d 'FsB.pas') "`nend.`n" "`ninitialization`n`nfinalization`n`nend.`n"
  }
  $null = Prove-Apply 'd2.4 (a direct call in the finalization section)' 'finalsect' 'FinalSect' {
    param($d) Edit-Text (Join-Path $d 'FsA.pas') "finalization`n  FsAShutdown;" "finalization`n  FsBStop;"
  }
  $r = Refused (New-Proj 'finalsect' 'FinalSect' {
    param($d) Edit-Text (Join-Path $d 'FsB.pas') "`nend.`n" "`ninitialization`n`nfinalization`n  GFsStops:= -100;`n`nend.`n"
  })
  Check 'd2.5 the declaring unit''s finalization has code: finalization-order' (($r.Exit -eq 1) -and ($r.Reasons -match 'finalization-order: .*already run')) "exit=$($r.Exit) $($r.Reasons)"
  $r = Refused (New-Proj 'finalsect' 'FinalSect' {
    param($d) Edit-Text (Join-Path $d 'FsB.pas') "  GFsStops: Integer;" "  GFsStops: Integer;`n  GFsName: string;"
  })
  Check 'd2.6 the declaring unit has a managed global: finalization-order' (($r.Exit -eq 1) -and ($r.Reasons -match 'finalization-order: .*GFsName')) "exit=$($r.Exit) $($r.Reasons)"
  $r = Refused (New-Proj 'finalsect' 'FinalSect' {
    param($d) Edit-Text (Join-Path $d 'FsA.pas') "  Writeln('init a');" "  Writeln('init a');`n  FsAShutdown;"
  })
  Check 'd2.7 named in the real initialization section: still init-order' (($r.Exit -eq 1) -and ($r.Reasons -match 'init-order')) "exit=$($r.Exit) $($r.Reasons)"

  # ---------------------------------------------------------------- D3
  Write-Host '== D3 Unit.GVar follows its move; a comment is no use' -ForegroundColor Cyan
  $P = Prove-Apply 'd3.1' 'qualglobal' 'QualGlobal'
  $qa = [IO.File]::ReadAllText((Join-Path $P.Root 'QgA.pas'), $Ascii)
  Check 'd3.2 the code is rewritten to the leaf' (($qa -match 'QgB\.Untangle\.GQgHook:= 7;') -and ($qa -match "Writeln\('QgB\.GQgHook=', QgB\.Untangle\.GQgHook\);")) $qa
  Check 'd3.3 the string, the line comment and the block comment are untouched' (
    $qa.Contains("'QgB.GQgHook='") -and $qa.Contains('// QgB.GQgHook in a comment stays') -and $qa.Contains('{ Every fact shown here comes from QgB. That separation')) $qa
  $left = Get-Cycles $P
  Check 'd3.4 no cycle after a re-index' ($left -match 'No circular unit dependencies found\.') $left
  $r = Refused (New-Proj 'qualglobal' 'QualGlobal' {
    param($d)
    Edit-Text (Join-Path $d 'QgB.pas') "procedure QgBRun;`n`nimplementation" "procedure QgBRun;`n`n/// <summary>Does nothing.</summary>`nprocedure QgBOther;`n`nimplementation"
    Edit-Text (Join-Path $d 'QgB.pas') "`nend.`n" "`nprocedure QgBOther;`nbegin`nend;`n`nend.`n"
    Edit-Text (Join-Path $d 'QgA.pas') "  QgB.GQgHook:= 7;" "  QgB.GQgHook:= 7;`n  QgB.QgBOther;"
  })
  Check 'd3.5 a qualified ROUTINE does not move: still qualified-ref, naming it' (($r.Exit -eq 1) -and ($r.Reasons -match 'qualified-ref: .*QgBOther')) "exit=$($r.Exit) $($r.Reasons)"

  Write-Host '== D3 Part A: a moved const named qualified, inside and outside the cycle' -ForegroundColor Cyan
  $P = Prove-Apply 'd3.6' 'qualparta' 'QualPartA'
  Check 'd3.7 both units name the leaf' ([IO.File]::ReadAllText((Join-Path $P.Root 'QpA.pas'), $Ascii).Contains('QpB.Untangle.CQpTop') -and
    [IO.File]::ReadAllText((Join-Path $P.Root 'QpC.pas'), $Ascii).Contains('QpB.Untangle.CQpTop')) ''

  # ---------------------------------------------------------------- C5
  Write-Host '== C5 a routine passed as an argument' -ForegroundColor Cyan
  $P = Prove-Apply 'c5.1' 'routinearg' 'RoutineArg'
  $ra = [IO.File]::ReadAllText((Join-Path $P.Root 'RaA.pas'), $Ascii)
  Check 'c5.2 the pointer is passed, to the procedural type and to the method reference' (
    $ra.Contains("RaApply('plain', RaBSayPtr);") -and $ra.Contains("RaApplyRef('ref', RaBSayPtr);")) $ra
  $r = Refused (New-Proj 'routinearg' 'RoutineArg' {
    param($d) Edit-Text (Join-Path $d 'RaA.pas') "RaApply('plain', RaBSay);" "RaApply('plain', @RaBSay);"
  })
  Check 'c5.3 `@F` as an argument: still refused' (($r.Exit -eq 1) -and ($r.Reasons -match 'routine-not-called')) "exit=$($r.Exit) $($r.Reasons)"
  $r = Refused (New-Proj 'routinearg' 'RoutineArg' {
    param($d) Edit-Text (Join-Path $d 'RaA.pas') "RaApply('plain', RaBSay);" "RaApply('plain',`n    RaBSay);"
  })
  Check 'c5.4 the argument on a line of its own: still refused' (($r.Exit -eq 1) -and ($r.Reasons -match 'routine-not-called')) "exit=$($r.Exit) $($r.Reasons)"
  $r = Refused (New-Proj 'routinearg' 'RoutineArg' {
    param($d)
    Edit-Text (Join-Path $d 'RaA.pas') "procedure RaAShow;`nbegin" "procedure RaTake(const pN: Integer);`nbegin`n  Writeln(pN);`nend;`n`nprocedure RaAShow;`nbegin`n  RaTake(RaBFive);"
  })
  Check 'c5.5 a parameterless function as an argument (its result): still refused' (($r.Exit -eq 1) -and ($r.Reasons -match 'routine-not-called')) "exit=$($r.Exit) $($r.Reasons)"
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host "run_cyclefix_cyc4_dcc: FAIL ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "run_cyclefix_cyc4_dcc: PASS ($script:Passed checks)" -ForegroundColor Green; exit 0
