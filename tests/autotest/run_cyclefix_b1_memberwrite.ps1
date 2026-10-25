<#
  run_cyclefix_b1_memberwrite.ps1 -- recipe B1 (plan 2026-10-25-cycles-fix-refusal-recipes.md):
  where the consumer of an R2 cut WRITES a member of the class, `cycles --plan` carries the
  write by a read/write interface property with a one-line setter; the write shapes no property
  can carry stay REFUSED as `member-write`, each with its own reason.

  Variants of tests\fixtures\cyclefix\memberwrite (`LastGage := 0` inside the `with` body):
  ACCEPTED (verdict mechanical):
    a1 the fixture as shipped: the leaf declares `procedure SetLastGage(const pValue: Integer);`
       and `property LastGage: Integer read GetLastGage write SetLastGage;` (Log stays read-only);
       TDemoGagePort declares the setter and implements it as `LastGage := pValue;`; the prose
       names the setter. Followed and re-indexed, no cycle remains.
    a2 a write of a public FIELD (`Count := 3`): setter `SetCount`, body `Count := pValue;`.
    a3 POSITIVE CONTROL for r3/r4: the member passed to a routine whose parameter is `const`
       (`Show(LastGage)`) is a plain read -- the var / out check discriminates.
    a4 POSITIVE CONTROL for r5: a write into a CLASS-typed member (`Log.Text := InBuf`) is
       carried as it is -- no setter for Log.
  REFUSED (verdict refused, kind member-write; before B1 the planner accepted r1-r5 as READS
  and planned code that does not compile):
    r1 `Inc(LastGage)`            -- Inc / Dec takes a variable
    r2 `Dec(LastGage, 2)`         -- Inc / Dec takes a variable
    r3 `Adjust(LastGage)` (var)   -- may take it as a var / out parameter
    r4 `Fetch(LastGage)` (out)    -- may take it as a var / out parameter
    r5 `Origin.X := 5` (TPoint)   -- a write into a record-typed member changes a copy
    r6 the class already declares `SetLastGage` -- `duplicate-identifier`, naming the setter.

  The platform library is COPIED into the scratch dir (R2 reads class ancestry from it); the
  real library DBs are never opened. Without -LibraryDb on disk it prints SKIP and exits 0.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-b1-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite'
$Ascii = [Text.Encoding]::ASCII
$WriteLine = '    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it'
$ImplUses  = "uses`n  DemoGagePort; // <-- the edge to cut: ``is``/``as`` + two member reads`n"

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# A copy of the fixture with each (file, old, new) of pEdits applied; Ok = every edit changed its file.
function New-Variant([string]$Tag, [object[]]$Edits) {
  $dir = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $dir | Out-Null
  Get-ChildItem $Fx -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $dir $_.Name) -Force }
  $ok = $true
  foreach ($e in $Edits) {
    $p = Join-Path $dir $e[0]
    $t = [IO.File]::ReadAllText($p)
    $n = $t.Replace(($e[1] -replace "`r?`n", "`r`n"), ($e[2] -replace "`r?`n", "`r`n"))
    if ($n -eq $t) { $ok = $false }
    Set-Text $p $n
  }
  return @{ Dir = $dir; Ok = $ok }
}

# Indexes and plans a variant; the plan text, the plan dump of cycle 1, the files.
function Get-VariantPlan([hashtable]$V, [string]$Tag) {
  $dproj = Join-Path $V.Dir 'MemberWrite.dproj'
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $okIdx = $LASTEXITCODE -eq 0
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $dump = Join-Path $WorkDir "dump-$Tag.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
      -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  } finally {
    $env:DRAGLINT_TEST_DUMP_PLAN = $null
  }
  $h = @{}
  if (Test-Path $dump) {
    foreach ($l in [IO.File]::ReadAllLines($dump)) {
      $r = @{}
      foreach ($kv in ($l -split "`t")) { $i = $kv.IndexOf('='); if ($i -gt 0) { $r[$kv.Substring(0, $i)] = $kv.Substring($i + 1) } }
      if ($r['cycle'] -eq '1') { $h = $r }
    }
  }
  return @{ Ok = ($V.Ok -and $okIdx -and ($p.ExitCode -eq 0)); Text = [IO.File]::ReadAllText($o); File = $o; Dump = $h;
            Db = $db; Dproj = $dproj; Dir = $V.Dir }
}

function Test-Refused([string]$Tag, [string]$Kind, [string]$Reason, [object[]]$Edits) {
  $v = Get-VariantPlan (New-Variant $Tag $Edits) $Tag
  $kinds = @($v.Dump.refusals -split ',')
  Check "$Tag refused: $Kind -- $Reason" ($v.Ok -and ($v.Dump.verdict -eq 'refused') -and ($kinds -contains $Kind) -and
    $v.Text.Contains("refused: $Kind -- ") -and $v.Text.Contains($Reason) -and -not $v.Text.Contains('### Step 4')) "[$($v.Dump.verdict) / $($v.Dump.refusals)]"
}

function Test-Accepted([string]$Tag, [string]$Why, [object[]]$Edits) {
  $v = Get-VariantPlan (New-Variant $Tag $Edits) $Tag
  Check "$Tag mechanical: $Why" ($v.Ok -and ($v.Dump.verdict -eq 'mechanical') -and ($v.Dump.refusals -eq '') -and
    $v.Text.Contains('by **member hand-over through an extracted interface**')) "[$($v.Dump.verdict) / $($v.Dump.refusals)]"
  return $v
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  Write-Host '== accepted: a plain write becomes a read/write property with a setter' -ForegroundColor Cyan
  $a1 = Test-Accepted 'a1' 'the fixture as shipped (`LastGage := 0` in the with body)' @()
  $t = $a1.Text -replace "`r`n", "`n"
  Check 'a1b the leaf declares the setter and a read/write property; Log stays read-only' `
    ($t.Contains("    procedure SetLastGage(const pValue: Integer);`n") -and
     $t.Contains("    property LastGage: Integer read GetLastGage write SetLastGage;`n") -and
     $t.Contains("    property Log: TStrings read GetLog;`n") -and -not $t.Contains('SetLog')) ''
  Check 'a1c TDemoGagePort declares the setter and implements it as one assignment' `
    ($t.Contains("    procedure SetLastGage(const pValue: Integer);`n") -and
     $t.Contains("procedure TDemoGagePort.SetLastGage(const pValue: Integer);`nbegin`n  LastGage := pValue;`nend;")) ''
  Check 'a1d the prose names the setter' ($t -match 'writes are read/write properties instead, each with a one-line setter .*\(SetLastGage\)') ''
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $a1.File -Cycle 1 -Root $a1.Dir 2>&1 | Out-String
  Check 'a1e the follower applies it (exit 0)' ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  & $Exe index --project $a1.Dproj --db $a1.Db *> (Join-Path $WorkDir 'index-a1-after.log')
  $after = & $Exe cycles --db $a1.Db --library-db $Lib 2>&1 | Out-String
  Check 'a1f re-indexed, no cycle remains' ($after -match 'No circular unit dependencies found\.') ($after.Trim() -replace "`r?`n", ' | ')

  $a2 = Test-Accepted 'a2' 'a write of a public field (`Count := 3`)' @(
    @('DemoGagePort.pas', "    FLastGage: Integer;`n  public`n", "    FLastGage: Integer;`n  public`n    /// <summary>A public field.</summary>`n    Count: Integer;`n"),
    @('DemoUIConnect.pas', $WriteLine, '    Count := 3;'))
  $t2 = $a2.Text -replace "`r`n", "`n"
  Check 'a2b setter SetCount, body `Count := pValue;`' `
    ($t2.Contains("    property Count: Integer read GetCount write SetCount;`n") -and
     $t2.Contains("procedure TDemoGagePort.SetCount(const pValue: Integer);`nbegin`n  Count := pValue;`nend;")) ''

  Write-Host '== positive controls: what the refusals below must NOT catch' -ForegroundColor Cyan
  $a3 = Test-Accepted 'a3' 'the member passed to a `const` parameter is a plain read' @(
    @('DemoUIConnect.pas', $WriteLine, '    Show(LastGage);'),
    @('DemoUIConnect.pas', $ImplUses, ($ImplUses + "`nprocedure Show(const pV: Integer);`nbegin`n  Writeln(pV);`nend;`n")))
  Check 'a3b no setter (nothing is written)' (-not $a3.Text.Contains('SetLastGage')) ''
  $a4 = Test-Accepted 'a4' 'a write into a class-typed member (`Log.Text := InBuf`)' @(
    , @('DemoUIConnect.pas', $WriteLine, '    Log.Text := InBuf;'))
  Check 'a4b no setter for Log' (-not $a4.Text.Contains('SetLog')) ''

  Write-Host '== refused: the write shapes no property can carry' -ForegroundColor Cyan
  Test-Refused 'r1' 'member-write' 'changes `LastGage` with Inc / Dec, which takes a variable' @(
    , @('DemoUIConnect.pas', $WriteLine, '    Inc(LastGage);'))
  Test-Refused 'r2' 'member-write' 'changes `LastGage` with Inc / Dec, which takes a variable' @(
    , @('DemoUIConnect.pas', $WriteLine, '    Dec(LastGage, 2);'))
  Test-Refused 'r3' 'member-write' 'passes `LastGage` as an argument of `Adjust`, which may take it as a var / out parameter' @(
    @('DemoUIConnect.pas', $WriteLine, '    Adjust(LastGage);'),
    @('DemoUIConnect.pas', $ImplUses, ($ImplUses + "`nprocedure Adjust(var pV: Integer);`nbegin`n  pV := pV + 1;`nend;`n")))
  Test-Refused 'r4' 'member-write' 'passes `LastGage` as an argument of `Fetch`, which may take it as a var / out parameter' @(
    @('DemoUIConnect.pas', $WriteLine, '    Fetch(LastGage);'),
    @('DemoUIConnect.pas', $ImplUses, ($ImplUses + "`nprocedure Fetch(out pV: Integer);`nbegin`n  pV := 1;`nend;`n")))
  Test-Refused 'r5' 'member-write' 'writes into `Origin` (of type `TPoint`), which is no class or interface' @(
    @('DemoGagePort.pas', "    FLastGage: Integer;`n  public`n", "    FLastGage: Integer;`n  public`n    /// <summary>A record field.</summary>`n    Origin: TPoint;`n"),
    @('DemoGagePort.pas', "  System.Classes;`n`ntype", "  System.Classes,`n  System.Types;`n`ntype"),
    @('DemoUIConnect.pas', $WriteLine, '    Origin.X := 5;'))
  Test-Refused 'r6' 'duplicate-identifier' 'already declares `SetLastGage` (line 55), the setter the interface needs' @(
    , @('DemoGagePort.pas', "    property LastGage: Integer read FLastGage write FLastGage;`n", "    property LastGage: Integer read FLastGage write FLastGage;`n    /// <summary>Already there.</summary>`n    procedure SetLastGage(const pV: Integer);`n"))
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
