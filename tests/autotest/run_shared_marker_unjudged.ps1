<#
  run_shared_marker_unjudged.ps1 -- C4 #5, 1.44: a closure-dependent dl:ok on a dl:shared unit that a
  single-index lint-all leaves standing is SAID to be unjudged, not silently passed over.

  Same fixture as run_marker_unused_shared_closure.ps1: thing.pas (dl:shared SecA, SecB) carries a
  duplicate-code marker whose finding exists only under B (bside\dup.pas).

  1 FIX      lint-all --db A: one "left unjudged" note on stderr, naming --shared-db (RED on 1.43)
  2 sanity   the same run still does not call the marker unused
  CONTROLS
  3 --json stdout stays parseable: the note is on stderr only
  4 lint-all --db A --shared-db B judges it: no single-index note, the union note says 1 judged
  5 lint-all --db B: the marker is live there, nothing to report
  6 lint <file> --db A: no note, a file-scoped run leaves far more unjudged by contract
  7 the AST-rule marker and the unshared marker are not counted (the count is exactly 1)

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_marker_unjudged_$PID"
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

  $note = 'left unjudged: their rule depends'
  $errA = Join-Path $scratch 'errA.txt'
  $oA = (& $exePath lint-all --db $dbA 2>$errA | Out-String)
  $eA = Get-Content $errA -Raw
  Check '1. FIX: lint-all --db A says the marker is left unjudged and names --shared-db' (($eA -match $note) -and ($eA -match '--shared-db'))
  Check '7. CONTROL: exactly the one shared closure-dependent marker is counted' ($eA -match "lint-all: 1 dl:ok marker\(s\) on dl:shared units $note")
  Check '2. sanity: the marker is still not called unused' (-not (UnusedAt $oA 'thing\.pas'))
  $j = (& $exePath lint-all --db $dbA --json 2>$null | Out-String)
  $parsed = $true; try { $null = $j | ConvertFrom-Json } catch { $parsed = $false }
  Check '3. CONTROL: --json stdout stays parseable' ($parsed -and ($j -notmatch [regex]::Escape($note)))
  $u = (& $exePath lint-all --db $dbA --shared-db $dbB 2>&1 | Out-String)
  Check '4a. CONTROL: --shared-db run has no single-index note' ($u -notmatch $note)
  Check '4b. CONTROL: --shared-db judged it' ($u -match '--shared-db: 1 marker\(s\) judged across 2 DB\(s\), 0 left unjudged')
  $b = (& $exePath lint-all --db $dbB 2>&1 | Out-String)
  Check '5. CONTROL: under B the marker is live, no note' ($b -notmatch $note)
  $f = (& $exePath lint (Join-Path $scratch 'shared\thing.pas') --db $dbA 2>&1 | Out-String)
  Check '6. CONTROL: lint <file> prints no note' ($f -notmatch $note)
} finally { Pop-Location }
[IO.Directory]::Delete($scratch, $true)
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} catch { Write-Host "FAIL (exception): $_"; exit 1 }