<#
  run_duplicate_code_marker_either_end.ps1 -- a `dl:ok duplicate-code` marker
  on EITHER end of a clone pair suppresses it, and counts as used, in both
  scopes (D30, 2026-09-24).

  THE DEFECT, measured on the self index 2026-09-24. `lint <file>` sees one
  file, so a clone inside it is anchored there (TCloneChecker.Check on that
  file alone). `lint-all` sees the corpus: the coverage suppression takes the
  LONGEST clone first, so the same tokens can pair with a longer copy in another
  file, and EmitPair anchors every pair at the lexicographically GREATER
  (FilePath, Line) -- a different file. A `dl:ok` marker is bound to ONE line,
  so the marker written from the per-file view was "unused" in the project view
  (review-marker-unused at AstChecks.pas:6021) while the finding it reviewed
  came back at Parser.Delphi13.pas:98. Both scopes were right about the clone
  and wrong about the review.

  THE FIX: a duplicate-code finding carries its partner site (RelatedFile /
  RelatedLine); ApplyLineMarkers honours a marker at either end, verified
  against the line it was hashed on, and accounts BOTH ends.

  THE FIXTURE. uAlpha.pas holds two copies of routine R (AlphaOne < AlphaTwo);
  AlphaTwo carries a tail E, AlphaOne a tail F. uZeta.pas holds R+F (ZetaOne)
  and R+E (ZetaPlus). F is what lets lint-all drop the within-file pair: the
  coverage suppression skips a pair only when BOTH ends are covered. So:
    lint uAlpha.pas -> anchor uAlpha:L2 (AlphaTwo), also at uAlpha:L1;
    lint-all        -> the R+E pair is longest: anchor uZeta:Lz (greater path),
                       also at uAlpha:L2; the within-file pair is suppressed.
  Both are asserted as PRECONDITIONS against the running engine -- if the
  clone engine ever stops producing this shape the test says so, instead of
  passing vacuously.

  STEPS: `allow` the per-file finding at uAlpha:L2; then `lint-all` must report
  no review-marker-unused at uAlpha:L2 and no duplicate-code at uZeta:Lz.
  CONTROLS: (a) before the marker, lint-all reports uZeta:Lz; (b) a marker on
  an unrelated line is still reported unused; (c) `lint uAlpha.pas` after
  `allow` is clean, and `lint uZeta.pas` alone reports no CROSS-file pair
  (single-file scope has none; uZeta's own ZetaOne/ZetaPlus pair is expected).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "draglint-dup-either-end-$PID")
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
try {

# The clone body: varied statements, wide vocabulary -- it must survive
# IsLowInformation (see run_clone_anchor_stability.ps1).
$CloneBody = @(
  "  LTotal := LTotal + ComputeWeight(ASource.Alpha, ASource.Beta);"
  "  if LTotal > FUpperBound then LTotal := FUpperBound;"
  "  LScaled := Round(LTotal * FScaleFactor) + FOffsetBase;"
  "  LBuffer.Append(Format('%s=%d', [ASource.Caption, LScaled]));"
  "  if not TryResolveTarget(ASource.Handle, LTarget) then Exit(False);"
  "  LTarget.Rebind(LScaled, FUpperBound - LTotal);"
  "  FHistory.Add(TSample.Create(LTarget.Id, LScaled, Now));"
  "  while FHistory.Count > FRetentionLimit do FHistory.Delete(0);"
  "  LRatio := LScaled / (FUpperBound + FOffsetBase + 1);"
  "  if LRatio < FMinimumRatio then FlagUnderflow(ASource.Caption, LRatio);"
  "  LStatus := DescribeRatio(LRatio, FMinimumRatio, FUpperBound);"
  "  FLogger.Trace('rebind', LStatus, LTarget.Id, LScaled, LRatio);"
) -join "`r`n"
# The tail E: only AlphaTwo and ZetaPlus carry it, which is what makes their
# pair the longest for AlphaTwo's tokens.
$Tail = @(
  "  LQuota := AllocateQuota(LTarget.Id, LScaled div 4, FRetentionLimit);"
  "  if LQuota.Exhausted then NotifyQuota(ASource.Caption, LQuota.Remaining);"
  "  FJournal.Record(LTarget.Id, LQuota.Remaining, LStatus, FEpochCounter);"
  "  Inc(FEpochCounter, LQuota.Remaining + FOffsetBase);"
  "  LDigest := HashCombine(LDigest, LQuota.Remaining xor LTarget.Id);"
  "  FAudit.Push(LDigest, LStatus, FEpochCounter, ASource.Handle);"
) -join "`r`n"
# The tail F: AlphaOne and ZetaOne carry it. Without it the within-file pair
# survives lint-all: coverage suppression skips a candidate only when BOTH of
# its ends are already >= 50% covered (CloneChecks.Match), so AlphaOne's end
# needs a longer partner of its own -- the shape the self index had at 6021.
$TailF = @(
  "  LSpan := MeasureSpan(LTarget.Id, FWindowStart, FWindowEnd, LScaled);"
  "  if LSpan.Overflow then ClampWindow(FWindowStart, FWindowEnd, LSpan.Width);"
  "  FMonitor.Observe(LSpan.Width, LSpan.Height, ASource.Beta, FEpochCounter);"
  "  LChecksum := Crc32Update(LChecksum, LSpan.Width * LSpan.Height);"
  "  FTrail.Enqueue(LChecksum, LSpan, ASource.Alpha, LStatus);"
) -join "`r`n"

function RoutineText([string]$Name, [string]$TailText) {
  $t = if ($TailText) { "`r`n$TailText" } else { '' }
@"
function $Name(const ASource: TSourceRec): Boolean;
var
  LTotal, LScaled: Integer;
  LRatio: Double;
  LTarget: TTarget;
  LBuffer: TStringBuilder;
  LStatus: string;
  LQuota: TQuota;
  LDigest: Cardinal;
begin
  Result := True;
  LTotal := 0;
  LDigest := 0;
  LBuffer := TStringBuilder.Create;
$CloneBody$t
  LBuffer.Free;
end;
"@
}
function UnitText([string]$UnitName, [string[]]$Decls, [string]$Bodies) {
@"
unit $UnitName;

interface

$($Decls -join "`r`n")

implementation

uses System.SysUtils, System.Classes, System.Generics.Collections, uShared;

$Bodies

end.
"@
}
function WriteAscii([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}

$alpha = Join-Path $WorkDir 'uAlpha.pas'
$zeta  = Join-Path $WorkDir 'uZeta.pas'
$db    = Join-Path $WorkDir 'dup.sqlite'
WriteAscii $alpha (UnitText 'uAlpha' @('function AlphaOne(const ASource: TSourceRec): Boolean;', 'function AlphaTwo(const ASource: TSourceRec): Boolean;') `
  ((RoutineText 'AlphaOne' $TailF) + "`r`n`r`n" + (RoutineText 'AlphaTwo' $Tail)))
WriteAscii $zeta  (UnitText 'uZeta'  @('function ZetaOne(const ASource: TSourceRec): Boolean;', 'function ZetaPlus(const ASource: TSourceRec): Boolean;') `
  ((RoutineText 'ZetaOne' $TailF) + "`r`n`r`n" + (RoutineText 'ZetaPlus' $Tail)))

function Reindex { & $Exe index $WorkDir --db $db *> $null }
function LintAll { (& $Exe lint-all --db $db --quiet 2>$null) }
function LintFile([string]$Path) { (& $Exe lint $Path --db $db 2>$null) }
function DupAt([string[]]$Out, [string]$File) {
  @($Out | Where-Object { $_ -match ('\\' + [regex]::Escape($File) + ':(\d+):\d+\s+\[info\] duplicate-code:') })
}
function LineOf([string]$Hit, [string]$File) {
  if ($Hit -match ('\\' + [regex]::Escape($File) + ':(\d+):')) { [int]$Matches[1] } else { 0 }
}

Reindex

# --- PRECONDITIONS: the engine really produces the two different anchors ------
$perFile = LintFile $alpha
$pfDup   = @(DupAt $perFile 'uAlpha.pas')
Check 'PRE per-file lint anchors a within-file pair in uAlpha' ($pfDup.Count -ge 1) ($perFile -join ' | ')
$L2 = if ($pfDup.Count -ge 1) { ($pfDup | ForEach-Object { LineOf $_ 'uAlpha.pas' } | Measure-Object -Maximum).Maximum } else { 0 }
$L1 = 0
foreach ($h in $pfDup) { if ($h -match 'also at .*uAlpha\.pas:(\d+)$') { $L1 = [int]$Matches[1] } }
Check 'PRE the per-file pair is AlphaTwo (L2) also at AlphaOne (L1 < L2)' (($L1 -gt 0) -and ($L1 -lt $L2)) "L1=$L1 L2=$L2"
$all0   = LintAll
$zDup0  = @(DupAt $all0 'uZeta.pas' | Where-Object { $_ -match ('also at .*uAlpha\.pas:' + $L2 + '$') })
Check 'PRE lint-all anchors the pair in uZeta, naming uAlpha:L2 as the other end' ($zDup0.Count -eq 1) "L2=$L2 :: $($all0 -join ' | ')"
Check 'PRE lint-all reports NO duplicate-code anchored in uAlpha (the per-file pair is suppressed)' `
  (@(DupAt $all0 'uAlpha.pas').Count -eq 0) ((DupAt $all0 'uAlpha.pas') -join ' | ')
$Lz = if ($zDup0.Count -ge 1) { LineOf $zDup0[0] 'uZeta.pas' } else { 0 }

# --- CONTROL (a): no marker -> lint-all reports uZeta:Lz ---------------------
Check 'CONTROL a: without a marker lint-all reports uZeta:Lz' ($Lz -gt 0) "Lz=$Lz"

# --- allow the per-file finding at uAlpha:L2 ---------------------------------
$al = (& $Exe allow $alpha --fix-line $L2 --fix-rule duplicate-code --apply 2>&1) -join "`n"
$markerLine = ([IO.File]::ReadAllLines($alpha))[$L2 - 1]
Check 'allow wrote a duplicate-code marker on uAlpha:L2' ($markerLine -match 'dl:ok duplicate-code@[0-9a-f]{4}') "$markerLine :: $al"

# CONTROL (b) setup: a marker on an unrelated line (the `interface` keyword).
$ls = [Collections.Generic.List[string]]([IO.File]::ReadAllLines($alpha))
$ifaceAt = $ls.IndexOf('interface')
$ls[$ifaceAt] = 'interface // dl:ok duplicate-code@1234 -- REVIEWED 2026-09-24 control: reviews nothing'
[IO.File]::WriteAllText($alpha, (($ls -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
Reindex

# --- THE ASSERTIONS: a marker at EITHER end ----------------------------------
$all1 = LintAll
Check 'lint-all: the marker at uAlpha:L2 is NOT reported unused' `
  (@($all1 | Where-Object { $_ -match ('uAlpha\.pas:' + $L2 + ':\d+\s+\[hint\] review-marker-unused') }).Count -eq 0) `
  (($all1 | Where-Object { $_ -match 'review-marker' }) -join ' | ')
$zDup1 = @(DupAt $all1 'uZeta.pas' | Where-Object { $_ -match ('uZeta\.pas:' + $Lz + ':') })
Check 'lint-all: the uZeta:Lz finding is suppressed by its partner''s marker' ($zDup1.Count -eq 0) ($zDup1 -join ' | ')
Check 'CONTROL: the OTHER uZeta pair (partner uAlpha:L1, no marker there) is still reported' `
  (@(DupAt $all1 'uZeta.pas' | Where-Object { $_ -match ('also at .*uAlpha\.pas:' + $L1 + '$') }).Count -eq 1) ((DupAt $all1 'uZeta.pas') -join ' | ')
Check 'CONTROL b: the marker on an unrelated line IS still reported unused' `
  (@($all1 | Where-Object { $_ -match ('uAlpha\.pas:' + ($ifaceAt + 1) + ':\d+\s+\[hint\] review-marker-unused') }).Count -eq 1) `
  (($all1 | Where-Object { $_ -match 'review-marker' }) -join ' | ')

# --- CONTROL (c): single-file scopes ------------------------------------------
$pf1 = LintFile $alpha
Check 'CONTROL c: lint uAlpha.pas after allow reports no duplicate-code' (@(DupAt $pf1 'uAlpha.pas').Count -eq 0) ($pf1 -join ' | ')
Check 'CONTROL c: lint uAlpha.pas after allow does not call the L2 marker unused' `
  (@($pf1 | Where-Object { $_ -match (':' + $L2 + ':\d+\s+\[hint\] review-marker-unused') }).Count -eq 0) ($pf1 -join ' | ')
$pz = LintFile $zeta
Check 'CONTROL c: lint uZeta.pas alone reports no CROSS-file pair (single-file scope cannot see uAlpha)' `
  (@(DupAt $pz 'uZeta.pas' | Where-Object { $_ -match 'uAlpha\.pas' }).Count -eq 0) ($pz -join ' | ')

} finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
