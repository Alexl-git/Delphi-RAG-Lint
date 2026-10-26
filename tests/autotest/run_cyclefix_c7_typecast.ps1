<#
  run_cyclefix_c7_typecast.ps1 -- plan 2026-10-25 C7 `type-cast` (owner-delegated 2026-10-26, ledger
  docs\superpowers\plans\2026-10-26-xcyc-ledger.md): recipe R2 (member hand-over through an extracted
  interface) accepts a HARD CAST followed by a member, `TX(Y).M`, and rewrites it to `(Y as ISurface).M` --
  `(TAnc(Y) as ISurface).M` when Y's static type does not implement IInterface. The plan states the behaviour
  change: a cast of the wrong object now raises EIntfCastError instead of reading through the wrong object.

  THE PLATFORM LIBRARY: R2 reads class ancestry from it. The engine never opens the real
  C:\Projects\.drag-lint\library-*.sqlite: -LibraryDb is copied into the $PID scratch dir and the copy is
  passed with --library-db; check z1 compares size + mtime of the real library DBs. Without -LibraryDb on
  disk it prints SKIP and exits 0.

  Every case is tests\fixtures\cyclefix\memberwrite without its `with`-body write (the clean pair) plus one
  line in DemoUIConnect.pas:
  ACCEPTED: castmember (TDemoGagePort(Sender).Log.Add -- Sender: TObject, cast through TComponent),
            castowner (TDemoGagePort(Owner).Log.Add -- Owner: TComponent, cast as is),
            castwrite (TDemoGagePort(Sender).LastGage := 0 -- carried by the B1 read/write property).
  REFUSED:  castnil (`TDemoGagePort(Sender) = nil`: no member follows), castwith (`with TDemoGagePort(Sender) do`),
            castinherited (`.Name`, a member of the ancestor), castmethod (`.ReadGage(1)`, a method) -- all
            `type-cast`; castunknownrecv (`TDemoGagePort(GetOwner).Log` -- `receiver-unknown`).
  POSITIVE CONTROL: the clean pair itself is mechanical; each refused case differs from castmember by one edit.
  The compile of every accepted tree is run_cyclefix_c7_typecast_dcc.ps1 (needs RAD Studio).
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-c7-$PID",
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
  return @{ Ok = ($V.Ok -and $okIdx -and ($p.ExitCode -eq 0)); Text = [IO.File]::ReadAllText($o); Dump = $h; File = $o; Db = $db; Dproj = $dproj }
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
  $U = 'DemoUIConnect.pas'
  $afterExit = "  if not (Sender is TDemoGagePort) then`n    Exit;`n"   # OnData, line 58-59: the cast goes on line 60

  Write-Host '== positive control: the clean pair is mechanical' -ForegroundColor Cyan
  $v0 = Get-VariantPlan (New-Variant 'clean' @()) 'clean'
  Check 'pc0 clean pair: mechanical, no refusal' ($v0.Ok -and ($v0.Dump.verdict -eq 'mechanical') -and ($v0.Dump.refusals -eq '')) "[$($v0.Dump.verdict) / $($v0.Dump.refusals)]"

  Write-Host '== accepted: a hard cast followed by a member' -ForegroundColor Cyan
  $Accepted = @(
    @('castmember', @(, @($U, $afterExit, ($afterExit + "  TDemoGagePort(Sender).Log.Add('cast');`n"))), 60, "  (TComponent(Sender) as IDemoGagePortSurface).Log.Add('cast');", ''),
    @('castowner', @(, @($U, "  if not (Owner is TDemoGagePort) then`n    Exit;`n", "  if not (Owner is TDemoGagePort) then`n    Exit;`n  TDemoGagePort(Owner).Log.Add('attach cast');`n")), 52, "  (Owner as IDemoGagePortSurface).Log.Add('attach cast');", ''),
    @('castwrite', @(, @($U, $afterExit, ($afterExit + "  TDemoGagePort(Sender).LastGage := 0;`n"))), 60, "  (TComponent(Sender) as IDemoGagePortSurface).LastGage := 0;", '    property LastGage: Integer read GetLastGage write SetLastGage;')
  )
  foreach ($c in $Accepted) {
    $v = Get-VariantPlan (New-Variant $c[0] $c[1]) $c[0]
    Check "$($c[0]) a0 mechanical, no refusal" ($v.Ok -and ($v.Dump.verdict -eq 'mechanical') -and ($v.Dump.refusals -eq '')) "[$($v.Dump.verdict) / $($v.Dump.refusals)] ok=$($v.Ok)"
    $new = Get-NewText $v.Text $c[2]
    Check "$($c[0]) a1 line $($c[2]) becomes $($c[3].Trim())" ($new -ceq $c[3]) "got: $new"
    if ($c[4]) { Check "$($c[0]) a3 the plan carries: $($c[4].Trim())" $v.Text.Contains($c[4]) '' }
    Check "$($c[0]) a2 the plan states the EIntfCastError behaviour change for the hard cast (line $($c[2]))" ($v.Text -match "hard cast[^\n]*line $($c[2])[^\n]*EIntfCastError|EIntfCastError[^\n]*hard cast[^\n]*line $($c[2])|line $($c[2])[^\n]*hard cast[^\n]*EIntfCastError") ''
  }

  Write-Host '== refused: a cast that no member follows, or a member the class does not declare' -ForegroundColor Cyan
  $Refused = @(
    @('castnil', 'type-cast', 'casts to `TDemoGagePort`', ($afterExit + "  if TDemoGagePort(Sender) = nil then`n    Exit;`n")),
    @('castwith', 'type-cast', 'casts to `TDemoGagePort`', ($afterExit + "  with TDemoGagePort(Sender) do`n    Log.Add('w');`n")),
    @('castinherited', 'type-cast', '`Name`', ($afterExit + "  InBuf := TDemoGagePort(Sender).Name;`n")),
    @('castmethod', 'type-cast', '`ReadGage`', ($afterExit + "  TDemoGagePort(Sender).ReadGage(1);`n")),
    @('castunknownrecv', 'receiver-unknown', '`GetOwner`', ($afterExit + "  TDemoGagePort(GetOwner).Log.Add('x');`n"))
  )
  foreach ($c in $Refused) {
    $v = Get-VariantPlan (New-Variant $c[0] @(, @($U, $afterExit, $c[3]))) $c[0]
    $kinds = @($v.Dump.refusals -split ',')
    Check ("{0} r0 refused: {1} ({2})" -f $c[0], $c[1], $c[2]) `
      ($v.Ok -and ($v.Dump.verdict -eq 'refused') -and ($kinds -contains $c[1]) -and $v.Text.Contains('refused: ' + $c[1] + ' -- ') -and $v.Text.Contains($c[2])) `
      ("[$($v.Dump.verdict) / $($v.Dump.refusals)] ok=$($v.Ok)")
    Check "$($c[0]) r1 the refusal names line 60" ($v.Text -match 'refused: [a-z-]+ -- line 60\b') ''
  }
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
$Stamp1 = Get-LibStamp
Check 'z1 the real library DBs are unchanged (size + mtime)' ($Stamp0 -eq $Stamp1) "before [$Stamp0] after [$Stamp1]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
