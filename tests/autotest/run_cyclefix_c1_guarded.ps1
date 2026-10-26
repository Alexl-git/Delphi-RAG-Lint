<#
  run_cyclefix_c1_guarded.ps1 -- plan 2026-10-25 C1 (rest), `receiver-unknown` when `is`-guarded, and the C9 plan
  wording (lane X-CYC 2026-10-26): recipe R2 casts a receiver whose static type it cannot tell (`GetOwner as TX`,
  `TX(GetOwner).M`) through the IInterface ancestor when an `X is TX` test on the same receiver text precedes the
  cast inside the same routine -- the cast is reached only when X IS a TX (the J9 argument). Unguarded stays
  `receiver-unknown`, now saying so; a guard in ANOTHER routine does not count.

  THE PLATFORM LIBRARY: copied into the $PID scratch dir, passed with --library-db; z1 compares the real DBs'
  size + mtime. Without -LibraryDb on disk: SKIP, exit 0.

  Every case is tests\fixtures\cyclefix\memberwrite without its `with`-body write (the clean pair) edited in
  DemoUIConnect.pas:
  ACCEPTED: guardedas (Attach: `if not (GetOwner is TDemoGagePort) then Exit; with GetOwner as TDemoGagePort do`
            -> `with TComponent(GetOwner) as IDemoGagePortSurface do`), guardedcast (OnData: the same guard, then
            `TDemoGagePort(GetOwner).Log.Add('g')` -> `(TComponent(GetOwner) as IDemoGagePortSurface).Log.Add('g')`).
  REFUSED:  unguardedas (`with GetOwner as TDemoGagePort do`, no guard on GetOwner), guardelsewhere (the guard in
            Attach, the cast in OnData) -- `receiver-unknown`, the reason names the missing guard.
  C9 WORDING: keptgetter (TDemoGagePort already declares `function GetLog: TStrings;` read by Log): the hand-over
            step says the getter is reused, not declared.
  POSITIVE CONTROL: the clean pair is mechanical. The compile of the accepted trees: run_cyclefix_c1_guarded_dcc.ps1.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-c1-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite'
$Ascii = [Text.Encoding]::ASCII

function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# A copy of the clean pair in pTag with pEdits = @(@(file, old, new), ...) applied; Ok = every edit matched.
function New-Variant([string]$Tag, [object[]]$Edits) {
  $dir = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $dir | Out-Null
  Get-ChildItem $Fx -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $dir $_.Name) -Force }
  $ok = $true
  $all = @(, @('DemoUIConnect.pas', "    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n", '')) + $Edits
  foreach ($e in $all) {
    $p = Join-Path $dir $e[0]
    $t = [IO.File]::ReadAllText($p)
    $n = $t.Replace(($e[1] -replace "`r?`n", "`r`n"), ($e[2] -replace "`r?`n", "`r`n"))
    if ($n -eq $t) { $ok = $false }
    Set-Text $p $n
  }
  return @{ Dir = $dir; Ok = $ok }
}

# Indexes the variant and plans it; the dump (DRAGLINT_TEST_DUMP_PLAN) of cycle 1 gives verdict / refusals.
function Get-VariantPlan([hashtable]$V, [string]$Tag) {
  $dproj = Join-Path $V.Dir 'MemberWrite.dproj'
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $okIdx = ($LASTEXITCODE -eq 0)
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
  $h = @{ verdict = '<no dump>'; refusals = '' }
  if (Test-Path $dump) {
    foreach ($l in [IO.File]::ReadAllLines($dump)) {
      $x = @{}
      foreach ($kv in ($l -split "`t")) { $i = $kv.IndexOf('='); if ($i -gt 0) { $x[$kv.Substring(0, $i)] = $kv.Substring($i + 1) } }
      if ($x.ContainsKey('cycle') -and ([int]$x['cycle'] -eq 1)) { $h = $x }
    }
  }
  return @{ Ok = ($V.Ok -and $okIdx -and ($p.ExitCode -eq 0)); Text = [IO.File]::ReadAllText($o); Dump = $h; File = $o }
}

# The new text of the edit that replaces line pLine of DemoUIConnect.pas in the plan text.
function Get-NewText([string]$Plan, [int]$Line) {
  $m = [regex]::Match($Plan, "(?s)Replace line $Line\. .*?New text:\r?\n``````pascal\r?\n(.*?)\r?\n``````")
  if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}

$Stamp0 = Get-LibStamp
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  Check 's0 the platform library was copied into the scratch dir' ((Get-Item $Lib).Length -eq (Get-Item $LibraryDb).Length) $Lib
  $U = 'DemoUIConnect.pas'; $G = 'DemoGagePort.pas'
  $attachOld = "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n"
  $onDataOld = "  if not (Sender is TDemoGagePort) then`n    Exit;`n"

  Write-Host '== positive control: the clean pair is mechanical' -ForegroundColor Cyan
  $v0 = Get-VariantPlan (New-Variant 'clean' @()) 'clean'
  Check 'pc0 clean pair: mechanical, no refusal' ($v0.Ok -and ($v0.Dump.verdict -eq 'mechanical') -and ($v0.Dump.refusals -eq '')) "[$($v0.Dump.verdict) / $($v0.Dump.refusals)]"

  Write-Host '== accepted: a receiver of unknown static type behind its own `is` guard' -ForegroundColor Cyan
  $Accepted = @(
    @('guardedas', @(, @($U, $attachOld, "  if not (GetOwner is TDemoGagePort) then`n    Exit;`n  with GetOwner as TDemoGagePort do`n")), 52, '  with TComponent(GetOwner) as IDemoGagePortSurface do'),
    @('guardedcast', @(, @($U, $onDataOld, ($onDataOld + "  if not (GetOwner is TDemoGagePort) then`n    Exit;`n  TDemoGagePort(GetOwner).Log.Add('g');`n"))), 62, "  (TComponent(GetOwner) as IDemoGagePortSurface).Log.Add('g');")
  )
  foreach ($c in $Accepted) {
    $v = Get-VariantPlan (New-Variant $c[0] $c[1]) $c[0]
    Check "$($c[0]) a0 mechanical, no refusal" ($v.Ok -and ($v.Dump.verdict -eq 'mechanical') -and ($v.Dump.refusals -eq '')) "[$($v.Dump.verdict) / $($v.Dump.refusals)] ok=$($v.Ok)"
    $new = Get-NewText $v.Text $c[2]
    Check "$($c[0]) a1 line $($c[2]) becomes $($c[3].Trim())" ($new -ceq $c[3]) "got: $new"
  }

  Write-Host '== refused: no guard, or the guard in another routine' -ForegroundColor Cyan
  $Refused = @(
    @('unguardedas', @(, @($U, $attachOld, "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with GetOwner as TDemoGagePort do`n")), 52),
    @('guardelsewhere', @(@($U, $attachOld, "  if not (GetOwner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n"), @($U, $onDataOld, ($onDataOld + "  TDemoGagePort(GetOwner).Log.Add('g');`n"))), 60)
  )
  foreach ($c in $Refused) {
    $v = Get-VariantPlan (New-Variant $c[0] $c[1]) $c[0]
    $kinds = @($v.Dump.refusals -split ',')
    Check "$($c[0]) r0 refused: receiver-unknown, naming the missing guard" `
      ($v.Ok -and ($v.Dump.verdict -eq 'refused') -and ($kinds -contains 'receiver-unknown') -and $v.Text.Contains("refused: receiver-unknown -- line $($c[2])") -and $v.Text.Contains('no `GetOwner is TDemoGagePort` guards it earlier in the same routine')) `
      ("[$($v.Dump.verdict) / $($v.Dump.refusals)] ok=$($v.Ok)")
  }

  Write-Host '== C9 wording: a getter the class already declares is reused, and the step says so' -ForegroundColor Cyan
  $vk = Get-VariantPlan (New-Variant 'keptgetter' @(
    @($G, '    property Log: TStrings read FLog;', '    property Log: TStrings read GetLog;'),
    @($G, '    procedure ReadGage(const pValue: Integer);', "    procedure ReadGage(const pValue: Integer);`n    /// <summary>The log (the getter the interface reuses).</summary>`n    function GetLog: TStrings;"),
    @($G, 'procedure TDemoGagePort.ReadGage(', "function TDemoGagePort.GetLog: TStrings;`nbegin`n  Result := FLog;`nend;`n`nprocedure TDemoGagePort.ReadGage("))) 'keptgetter'
  Check 'kg0 mechanical, no refusal' ($vk.Ok -and ($vk.Dump.verdict -eq 'mechanical') -and ($vk.Dump.refusals -eq '')) "[$($vk.Dump.verdict) / $($vk.Dump.refusals)] ok=$($vk.Ok)"
  Check 'kg1 the hand-over step names GetLog as reused, not declared' ($vk.Text.Contains('-- except `GetLog`, which the class already declares and the interface reuses as is')) ''
  Check 'kg2 positive control: the clean pair (no kept getter) carries no such clause' (-not $v0.Text.Contains('which the class already declares and the interface reuses')) ''
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
$Stamp1 = Get-LibStamp
Check 'z1 the real library DBs are unchanged (size + mtime)' ($Stamp0 -eq $Stamp1) "before [$Stamp0] after [$Stamp1]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
