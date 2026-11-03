<#
  run_marker_unused_shared_closure.ps1 -- a `dl:ok` marker on a `dl:shared` unit
  for a CLOSURE-DEPENDENT rule must not be reported `review-marker-unused` by a
  run whose index is only ONE of the unit's projects.

  YADF FALSE POSITIVE #5 (docs\INBOX-yadf-false-positives-2026-11-03.md). The
  finding the marker reviews exists only under the other project's compile
  closure, so this project's lint-all cannot account the marker. ApplyLineMarkers
  now skips the unused verdict for such a rule on a unit with more than one
  project in its dl:shared marker (backlog MARKER-SHARED-UNION merges findings
  across --db first).

  FIXTURE: shared\thing.pas (`dl:shared SecA, SecB`) holds function Crunch; its
  body is duplicated in bside\dup.pas (section B only), so the cross-file
  `duplicate-code` finding on Crunch exists ONLY under SecB's closure. The test
  records the marker with `drag-lint allow` (computing the real @hash) against
  SecB's report. plain\solo.pas (not shared) carries `dl:ok unused-public-symbol`on a
  routine that IS used from both sections (no finding anywhere);
  shared\other.pas (shared) carries an unrelated `dl:ok self-assignment` on a
  line with no finding (an AST rule, still judged).

  1 sanity  allow succeeded; lint-all --db dbB: the marker is live (no unused hint)
  2 FIX     lint-all --db dbA: no review-marker-unused at the thing.pas marker
            (RED on main effb5c97)
  CONTROLS
  3 solo.pas (unshared) marker with no finding is STILL reported unused (dbA)
  4 the AST-rule marker on the shared unit is STILL reported unused (dbA)

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_marker_sharedclosure_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
foreach ($d in 'shared','common','bside','plain') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) | Out-Null }
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'shared\thing.pas') @'
unit thing; // dl:shared SecA, SecB

interface

function Crunch(const ASource: TSourceRec): Boolean;

implementation

function Crunch(const ASource: TSourceRec): Boolean;
var
  LTotal, LScaled: Integer;
  LRatio: Double;
  LTarget: TTarget;
  LBuffer: TStringBuilder;
  LStatus: string;
begin
  LTotal := LTotal + ComputeWeight(ASource.Alpha, ASource.Beta);
  if LTotal > FUpperBound then LTotal := FUpperBound;
  LScaled := Round(LTotal * FScaleFactor) + FOffsetBase;
  LBuffer.Append(Format('%s=%d', [ASource.Caption, LScaled]));
  if not TryResolveTarget(ASource.Handle, LTarget) then Exit(False);
  LTarget.Rebind(LScaled, FUpperBound - LTotal);
  FHistory.Add(TSample.Create(LTarget.Id, LScaled, Now));
  while FHistory.Count > FRetentionLimit do FHistory.Delete(0);
  LRatio := LScaled / (FUpperBound + FOffsetBase + 1);
  if LRatio < FMinimumRatio then FlagUnderflow(ASource.Caption, LRatio);
  LStatus := DescribeRatio(LRatio, FMinimumRatio, FUpperBound);
  FLogger.Trace('rebind', LStatus, LTarget.Id, LScaled, LRatio);
  LBuffer.Free;
  Result := True;
end;

end.
'@
WriteAscii (Join-Path $scratch 'bside\dup.pas') @'
unit dup;

interface

function Crunch2(const ASource: TSourceRec): Boolean;

implementation

function Crunch2(const ASource: TSourceRec): Boolean;
var
  LTotal, LScaled: Integer;
  LRatio: Double;
  LTarget: TTarget;
  LBuffer: TStringBuilder;
  LStatus: string;
begin
  LTotal := LTotal + ComputeWeight(ASource.Alpha, ASource.Beta);
  if LTotal > FUpperBound then LTotal := FUpperBound;
  LScaled := Round(LTotal * FScaleFactor) + FOffsetBase;
  LBuffer.Append(Format('%s=%d', [ASource.Caption, LScaled]));
  if not TryResolveTarget(ASource.Handle, LTarget) then Exit(False);
  LTarget.Rebind(LScaled, FUpperBound - LTotal);
  FHistory.Add(TSample.Create(LTarget.Id, LScaled, Now));
  while FHistory.Count > FRetentionLimit do FHistory.Delete(0);
  LRatio := LScaled / (FUpperBound + FOffsetBase + 1);
  if LRatio < FMinimumRatio then FlagUnderflow(ASource.Caption, LRatio);
  LStatus := DescribeRatio(LRatio, FMinimumRatio, FUpperBound);
  FLogger.Trace('rebind', LStatus, LTarget.Id, LScaled, LRatio);
  LBuffer.Free;
  Result := True;
end;

end.
'@
WriteAscii (Join-Path $scratch 'shared\other.pas') @'
unit other; // dl:shared SecA, SecB

interface

procedure Poke(var B: Integer);

implementation

procedure Poke(var B: Integer);
begin
  B := 1; // dl:ok self-assignment -- planted, no finding on this line
end;

end.
'@
WriteAscii (Join-Path $scratch 'common\a.pas') @'
unit a;

interface

procedure RunA;

implementation

uses
  thing, other, solo;

procedure RunA;
var
  N: Integer;
begin
  thing.Crunch;
  solo.Lonely;
  other.Poke(N);
end;

end.
'@
WriteAscii (Join-Path $scratch 'bside\b.pas') @'
unit b;

interface

procedure RunB;

implementation

uses
  thing, other, solo;

procedure RunB;
var
  N: Integer;
begin
  solo.Lonely;
  other.Poke(N);
  N := N + 1;
end;

end.
'@
WriteAscii (Join-Path $scratch 'plain\solo.pas') @'
unit solo;

interface

procedure Lonely; // dl:ok unused-public-symbol -- unshared control

implementation

procedure Lonely;
begin
end;

end.
'@
$cfg = Join-Path $scratch 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "SecA", "db": "a.sqlite", "include": ["shared", "common", "plain"] },
      { "name": "SecB", "db": "b.sqlite", "include": ["shared", "bside", "plain"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
$dbA = Join-Path $scratch 'out\a.sqlite'; $dbB = Join-Path $scratch 'out\b.sqlite'

function UnusedAt([string]$Out, [string]$File) { $Out -match "(?im)$File[:\w\\/.]*:\d+:\d+[^\r\n]*review-marker-unused" }

Push-Location C:\TEMP
try {
  & $exePath index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
  & $exePath index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
  Check '0. sanity: both DBs exist' ((Test-Path $dbA) -and (Test-Path $dbB))

  $pre = (& $exePath lint-all --db $dbB --rule duplicate-code 2>&1 | Out-String)
  $m = [regex]::Match($pre, '(?im)thing\.pas:(\d+):\d+\s+\[\w+\]\s+duplicate-code')
  Check '0b. sanity: duplicate-code fires on thing.pas under B (no marker yet)' $m.Success
  if ($m.Success) { & $exePath allow (Join-Path $scratch 'shared\thing.pas') --fix-line $m.Groups[1].Value --fix-rule duplicate-code --apply 2>&1 | Out-Null }
  Check '0c. sanity: a dl:ok duplicate-code marker was written' ((Get-Content (Join-Path $scratch 'shared\thing.pas') -Raw) -match 'dl:ok duplicate-code@')

  $oB = (& $exePath lint-all --db $dbB 2>&1 | Out-String)
  $oA = (& $exePath lint-all --db $dbA 2>&1 | Out-String)
  Write-Host (($oA -split "`n" | Where-Object { $_ -match 'review-marker' }) -join "`n") -ForegroundColor DarkGray
  Check '1. sanity: under B the duplicate-code finding is suppressed (marker live, not reported unused)' (-not (UnusedAt $oB 'thing\.pas'))
  Check '2. FIX: under A the shared-unit marker is NOT reported unused' (-not (UnusedAt $oA 'thing\.pas'))
  Check '3. CONTROL: unshared solo.pas marker with no finding is still reported unused (A)' (UnusedAt $oA 'solo\.pas')
  Check '4. CONTROL: AST-rule marker on a shared unit is still judged and reported unused (A)' (UnusedAt $oA 'other\.pas')
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} catch { Write-Host "ERROR: $_" -ForegroundColor Red; exit 2 }
