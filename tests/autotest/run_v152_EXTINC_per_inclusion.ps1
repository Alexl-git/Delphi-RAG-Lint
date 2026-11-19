<#
  run_v152_EXTINC_per_inclusion.ps1 -- 1.52 lane EXTINC (owner ruling B9i): an .inc is parsed
  per INCLUSION, in each includer's define context, with one binding per host.

  Fixture tests\autotest\fixtures\v152-EXTINC:
    ExShared.inc   {$IFDEF COMPILE1} X: Integer; TShape = Integer {$ELSE} X: Double; TShape = Double.
    ExBody.inc     procedure Work: {$IFDEF COMPILE1} PingA {$ELSE} PingB.
    ExA.pas        {$DEFINE COMPILE1} {$I ExShared.inc}; PingA, PingB; {$I ExBody.inc}.
    ExB.pas        the same WITHOUT the define.
    ExProj.dpr     lists the four units (the runner indexes it with --project).
    ExTwin.inc     the same IFDEF shape (Y); included by ExC.pas and ExD.pas, BOTH with COMPILE1
                   (the twin: equal defines must give ONE symbol, not one per host).

  Checks (RED on 1.51.1: the first host's define context wins -- ONE X, ONE TShape, and the
  ExBody site is reported as calling the branch of that one context in BOTH hosts):
    T  two symbol types: X and TShape each exist twice, once Integer (host ExA) and once Double
       (host ExB). Positive control: X exists at all.
    C  find-callers per host: ExA.PingA is called from ExBody.inc:4, ExB.PingB from ExBody.inc:6;
       ExA.PingB and ExB.PingA are called from nowhere in the include (the inactive branch of
       that host). Positive control: each host's active call is listed.
    W  twin: Y exists exactly once (Integer).
  pwsh 7.

  Usage: pwsh -File tests\autotest\run_v152_EXTINC_per_inclusion.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$repo\tests\autotest\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_v152_extinc_$PID"
$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if ($Ok) { $script:pass++ } else { $script:fail++ }
}
function Invoke-Json([string[]]$CliArgs) {
  $raw = (& { $ErrorActionPreference = 'Continue'; & $exePath @CliArgs 2>$null }) -join "`n"
  $a = $raw.IndexOf('['); $o = $raw.IndexOf('{')
  $i = if ($a -ge 0 -and ($o -lt 0 -or $a -lt $o)) { $a } else { $o }
  if ($i -lt 0) { return ,@() }
  try { return ,@(($raw.Substring($i) | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { return ,@() }
}
# Symbols named $Name declared in the include $IncLeaf: their signatures, sorted.
function IncSigs([string]$Db, [string]$Name, [string]$IncLeaf) {
  # Assign first: Invoke-Json returns ,@(rows), which a direct pipe hands on as ONE object
  # (two rows then read as one signature "Integer Double").
  $rows = Invoke-Json @('query', '--name', $Name, '--db', $Db, '--exact', '--json')
  $s = @($rows | Where-Object { $_ -and $_.name -eq $Name -and (Split-Path ([string]$_.file) -Leaf) -eq $IncLeaf })
  return ,@($s | ForEach-Object { [string]$_.signature } | Sort-Object)
}
# find-callers --resolved text: "  <Target>:" then "    <Caller>  (<path>:<line>)  [...]" lines.
# Returns the include sites ("ExBody.inc:4") listed under $Target.
function ResolvedSites([string]$Db, [string]$Name, [string]$Target) {
  $lines = @(& { $ErrorActionPreference = 'Continue'; & $exePath query find-callers --name $Name --db $Db --resolved 2>$null })
  $cur = ''; $out = @()
  foreach ($l in $lines) {
    if ($l -match '^\s{2}(\S+):\s*$') { $cur = $Matches[1]; continue }
    if ($cur -eq $Target -and $l -match '\(([^()]+):(\d+)\)') { $out += ('{0}:{1}' -f (Split-Path $Matches[1] -Leaf), $Matches[2]) }
  }
  return ,@($out)
}
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $fx = Join-Path $scratch 'fx'
  [void](New-Item -ItemType Directory -Force -Path $fx)
  Copy-Item (Join-Path $repo 'tests\autotest\fixtures\v152-EXTINC\*') $fx
  $db = Join-Path $scratch 'ex.sqlite'
  # A PROJECT index: only it parses an .inc in its includer's define context.
  & { $ErrorActionPreference = 'Continue'; & $exePath index --project (Join-Path $fx 'ExProj.dpr') --db $db --library-db none 2>&1 | ForEach-Object { "$_" } } | Out-Null
  Check 'index exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"

  # ---- T: two hosts, different define, two symbol types ----
  $x = IncSigs $db 'X' 'ExShared.inc'
  Check 'T control: X is declared in ExShared.inc' ($x.Count -ge 1) "$($x.Count)"
  Check 'T X exists once per define context: Double + Integer' (($x -join ',') -eq 'Double,Integer') ($x -join ',')
  $t = IncSigs $db 'TShape' 'ExShared.inc'
  Check 'T TShape exists once per define context: Double + Integer' ($t.Count -eq 2) "$($t.Count): $($t -join ',')"

  # ---- C: find-callers per host ----
  $aA = ResolvedSites $db 'PingA' 'ExA.PingA'
  $bA = ResolvedSites $db 'PingA' 'ExB.PingA'
  $bB = ResolvedSites $db 'PingB' 'ExB.PingB'
  $aB = ResolvedSites $db 'PingB' 'ExA.PingB'
  Check 'C host ExA (COMPILE1): ExA.PingA is called from ExBody.inc:4' (@($aA | Where-Object { $_ -eq 'ExBody.inc:4' }).Count -eq 1) ($aA -join ' ')
  Check 'C host ExB (no define): ExB.PingB is called from ExBody.inc:6' (@($bB | Where-Object { $_ -eq 'ExBody.inc:6' }).Count -eq 1) ($bB -join ' ')
  Check 'C host ExA: ExA.PingB is NOT called from the include (inactive branch there)' (@($aB | Where-Object { $_ -like 'ExBody.inc:*' }).Count -eq 0) ($aB -join ' ')
  Check 'C host ExB: ExB.PingA is NOT called from the include (inactive branch there)' (@($bA | Where-Object { $_ -like 'ExBody.inc:*' }).Count -eq 0) ($bA -join ' ')

  # ---- W: twin with equal defines = one symbol ----
  $y = IncSigs $db 'Y' 'ExTwin.inc'
  Check 'W twin (ExC + ExD, both COMPILE1): Y exists exactly once, Integer' (($y -join ',') -eq 'Integer') "$($y.Count): $($y -join ',')"
} finally {
  if (Test-Path $scratch) { try { [IO.Directory]::Delete($scratch, $true) } catch { } }
}
Write-Host ("run_v152_EXTINC_per_inclusion: {0} pass, {1} fail" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0