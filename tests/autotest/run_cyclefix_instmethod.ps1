<#
  run_cyclefix_instmethod.ps1 -- plan B2 (R2m, lane W6-cyc4, owner ruling 2026-10-25): the member
  hand-over recipe carries INSTANCE methods the consumer calls inside `with ... as TX do` as
  interface methods, the signature copied verbatim (as R1 does). Static, virtual and override
  methods are accepted; a call through the CLASS name and a class method stay refused.

  (a) tests\fixtures\cyclefix\instmethod: Mark and Touch (static), Reset (virtual, default parameter) and
      GetNamePath (override of an RTL virtual, read without parentheses) -> mechanical; the leaf
      interface declares the three methods verbatim; the class gains no getter for them; the
      follower applies the plan and the cycle is gone after a re-index.
  POSITIVE CONTROLS (each must still refuse):
  (b) tests\fixtures\cyclefix\classmethod: `TDemoGagePort.ClassName` -> class-method.
  (c) a class method `class procedure Stamp` called in the `with` body -> class-method.
  (d) Mark overloaded (Mark(string) / Mark(Integer)) -> refused (with-member, see below).
  (e) a parameter typed by an enum of the cycle unit -> signature-in-cycle, the type named.
  (f) a procedure taken as a method pointer (`FOnTouch := Touch`) -> class-method "without calling it".
  (d) and the unbound-call case: the index leaves an OVERLOADED call unbound, so the with-member
  safety net refuses it before CheckMethod sees it; either kind is a refusal.
  The compile, the dispatch through the interface and the byte-identical output are
  run_cyclefix_instmethod_dcc.ps1 (needs RAD Studio).
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-instmethod-$PID",
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
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# A copy of pFrom with each (file, old, new) of pEdits applied; Ok = every edit changed its file.
function New-Variant([string]$From, [string]$Tag, [object[]]$Edits) {
  $dir = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $dir | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
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

# `cycles` on pDb with pExtra; the plan dump (DRAGLINT_TEST_DUMP_PLAN) of cycle 1 parsed.
function Get-Cycles([string]$Db, [string]$Tag, [string[]]$Extra) {
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $dump = Join-Path $WorkDir "dump-$Tag.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList (@('cycles', '--db', ('"' + $Db + '"')) + $Extra) `
      -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
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
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); File = $o; Dump = $h }
}

function Get-VariantPlan([hashtable]$V, [string]$Tag) {
  $dproj = (Get-ChildItem $V.Dir -Filter '*.dproj')[0].FullName
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $okIdx = $LASTEXITCODE -eq 0
  $pl = Get-Cycles $db $Tag @('--plan', '--library-db', ('"' + $Lib + '"'))
  return @{ Ok = ($V.Ok -and $okIdx); Text = $pl.Out; Dump = $pl.Dump; File = $pl.File; Db = $db; Dproj = $dproj }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  $U = 'DemoUIConnect.pas'; $G = 'DemoGagePort.pas'

  # --- (a) the three instance methods -----------------------------------------------------------
  Write-Host '== (a) instmethod: static, virtual and override methods called in the with body' -ForegroundColor Cyan
  $va = Get-VariantPlan (New-Variant (Join-Path $Fx 'instmethod') 'a' @()) 'a'
  Check 'a1 mechanical by member hand-over' ($va.Ok -and ($va.Dump.verdict -eq 'mechanical') -and
    $va.Text.Contains('by **member hand-over through an extracted interface**')) "[$($va.Dump.verdict) / $($va.Dump.refusals)]"
  Check 'a2 the leaf interface declares the three methods, signatures verbatim, directives dropped' (
    $va.Text.Contains("    procedure Mark(const pText: string);`r`n    procedure Touch;`r`n    procedure Reset(const pCount: Integer = 1);`r`n    function GetNamePath: string;`r`n")) ''
  Check 'a3 the prose names the carried methods' $va.Text.Contains('calls on it, the signature copied verbatim: Mark(const pText: string), Touch, Reset(const pCount: Integer = 1), GetNamePath: string.') ''
  Check 'a4 no getter for a method (no GetMark / GetTouch / GetReset / GetGetNamePath)' ($va.Text -notmatch 'GetMark|GetTouch|GetReset|GetGetNamePath') ''
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $va.File -Cycle 1 -Root (Join-Path $WorkDir 'a') 2>&1 | Out-String
  Check 'a5 the follower applies cycle 1 (exit 0)' ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $gp = [IO.File]::ReadAllText((Join-Path $WorkDir "a\$G"))
  Check 'a6 the class keeps its methods and directives, and implements the interface' (
    $gp.Contains('TDemoGagePort = class(TComponent, IDemoGagePortSurface)') -and
    $gp.Contains('    procedure Reset(const pCount: Integer = 1); virtual;') -and $gp.Contains('    function GetNamePath: string; override;')) ''
  & $Exe index --project $va.Dproj --db $va.Db *> (Join-Path $WorkDir 'index-a2.log')
  $after = Get-Cycles $va.Db 'a-after' @()
  Check 'a7 no cycle remains after a re-index' ($after.Out -match 'No circular unit dependencies found\.') ($after.Out.Trim() -replace "`r?`n", ' | ')

  # --- positive controls ---------------------------------------------------------------------------
  Write-Host '== positive controls: each must still refuse' -ForegroundColor Cyan
  $vb = Get-VariantPlan (New-Variant (Join-Path $Fx 'classmethod') 'b' @()) 'b'
  Check 'b1 a call through the class name stays refused: class-method' ($vb.Ok -and ($vb.Dump.verdict -eq 'refused') -and
    $vb.Text.Contains('refused: class-method -- line 54 calls `ClassName` through the class `TDemoGagePort`')) "[$($vb.Dump.verdict) / $($vb.Dump.refusals)]"
  $Cases = @(
    @('c1', 'class-method', 'line 67 calls `Stamp`, a class method of `TDemoGagePort`',
      @(@($G, "    procedure Mark(const pText: string);`n", "    procedure Mark(const pText: string);`n    /// <summary>A class method.</summary>`n    class procedure Stamp;`n"),
        @($G, "procedure TDemoGagePort.Mark(", "class procedure TDemoGagePort.Stamp;`nbegin`nend;`n`nprocedure TDemoGagePort.Mark("),
        @($U, "    Mark(InBuf);`n", "    Stamp;`n    Mark(InBuf);`n"))),
    @('d1', 'with-member', '`Mark` at line 67 names a member of `TDemoGagePort`',
      @(@($G, "    procedure Mark(const pText: string);`n", "    procedure Mark(const pText: string); overload;`n    /// <summary>An overload.</summary>`n    procedure Mark(const pValue: Integer); overload;`n"),
        @($G, "procedure TDemoGagePort.Mark(", "procedure TDemoGagePort.Mark(const pValue: Integer);`nbegin`nend;`n`nprocedure TDemoGagePort.Mark("))),
    @('e1', 'signature-in-cycle', 'names `TDemoGageUnit`, declared in `demogageport`',
      @(@($G, "type`n  /// <summary>Stand-in for the gage-port form", "type`n  /// <summary>Units.</summary>`n  TDemoGageUnit = (guMm, guInch);`n`n  /// <summary>Stand-in for the gage-port form"),
        @($G, "    procedure Mark(const pText: string);`n", "    procedure Mark(const pText: string; pUnit: TDemoGageUnit = guMm);`n"),
        @($G, "procedure TDemoGagePort.Mark(const pText: string);", "procedure TDemoGagePort.Mark(const pText: string; pUnit: TDemoGageUnit);"))),
    @('f1', 'class-method', 'line 68 names the method `Touch` without calling it',
      @(@($U, "    FInBuf: string;`n", "    FInBuf: string;`n    FOnTouch: TProc;`n"),
        @($U, "    Mark(InBuf);`n", "    FOnTouch := Touch;`n")))
  )
  foreach ($c in $Cases) {
    $v = Get-VariantPlan (New-Variant (Join-Path $Fx 'instmethod') ('v-' + $c[0]) $c[3]) ('v-' + $c[0])
    $kinds = @($v.Dump.refusals -split ',')
    Check ("{0} refused: {1} ({2})" -f $c[0], $c[1], $c[2]) `
      ($v.Ok -and ($v.Dump.verdict -eq 'refused') -and ($kinds -contains $c[1]) -and $v.Text.Contains('refused: ' + $c[1] + ' -- ') -and $v.Text.Contains($c[2])) `
      ("[$($v.Dump.verdict) / $($v.Dump.refusals)] ok=$($v.Ok)")
  }
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
