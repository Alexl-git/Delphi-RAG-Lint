<#
  run_marker_shared_union.ps1 -- lint-all --shared-db merges the marker evidence of
  several project indexes, so a closure-dependent dl:ok on a dl:shared unit gets a
  verdict instead of the skip run_marker_unused_shared_closure.ps1 pins for ONE DB.

  THE CONTRACT (backlog MARKER-SHARED-UNION, wiki Run-Lint-All-Full-Report):
    * stale or unused only if NO participating DB produces the finding;
    * a marker is judged only when as many DBs scanned the unit as its dl:shared
      lists -- fewer, or a peer that could not run, keeps today's skip;
    * no --shared-db (including --db A --db B, whose second slot is the library)
      keeps today's skip.

  FIXTURE, all `dl:shared SecA, SecB` unless noted:
    thing.pas   duplicate-code under B only (twin in bside); marker recorded by `allow`
    drift.pas   as thing, then the recorded hash is corrupted: STALE, seen only under B
    gone.pas    a duplicate-code marker with no finding under either DB: TRULY UNUSED
    triple.pas  as gone, but lists SecA, SecB, SecC, and only two DBs are given
    aonly\aonly.pas  as gone, but only SecA indexes it, so B is no evidence for it
    other.pas / plain\solo.pas  the controls of the older test (still judged)

  RED on main bea4f375: every run with the flag dies on unknown-flag, so 2, 4, 7, 8, 10, 11
  and 12 fail; 1 shows the old semantics for the same marker (gone.pas is only skipped).
  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_marker_sharedunion_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
foreach ($d in 'shared','common','bside','plain','aonly') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) | Out-Null }
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
$crunchBody = @'
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
'@
$driftBody = @'
var
  QCount: Int64;
  QName, QPath: string;
  QStream: TStream;
  QList: TStringList;
begin
  QList := TStringList.Create;
  QStream := TFileStream.Create(AInput.Location, fmOpenRead);
  QList.LoadFromStream(QStream, TEncoding.UTF8);
  for QName in QList do QTable.Insert(QName.ToUpper, QName.Length, AInput.Owner);
  QPath := TPath.Combine(AInput.Folder, ChangeFileExt(AInput.Title, '.bak'));
  if TFile.Exists(QPath) then TFile.Delete(QPath);
  QCount := QTable.Purge(AInput.Cutoff, AInput.Grace * 2, not AInput.Forced);
  QAudit.Write('purged', QCount, AInput.Title, QPath, DateTimeToStr(Now));
  repeat QCount := QCount - QQueue.Drain(AInput.Batch) until QCount <= AInput.Floor;
  QNotifier.Publish(TNotice.Build(AInput.Topic, QCount, QPath), AInput.Channel);
  QStream.Free;
  QList.Free;
  Result := QCount > AInput.Floor;
end;
'@
function UnitText([string]$Name, [string]$Header, [string]$Fn, [string]$Param, [string]$Body) {
  "unit $Name;$Header`n`ninterface`n`nfunction $Fn($Param): Boolean;`n`nimplementation`n`nfunction $Fn($Param): Boolean;`n$Body`nend.`n"
}
$hdr = ' // dl:shared SecA, SecB'
WriteAscii (Join-Path $scratch 'shared\thing.pas') (UnitText 'thing' $hdr 'Crunch'  'const ASource: TSourceRec' $crunchBody)
WriteAscii (Join-Path $scratch 'bside\dup.pas')    (UnitText 'dup'   ''   'Crunch2' 'const ASource: TSourceRec' $crunchBody)
WriteAscii (Join-Path $scratch 'shared\drift.pas') (UnitText 'drift' $hdr 'Sweep'   'const AInput: TInputRec'   $driftBody)
WriteAscii (Join-Path $scratch 'bside\dup3.pas')   (UnitText 'dup3'  ''   'Sweep2'  'const AInput: TInputRec'   $driftBody)
function NoFindingUnit([string]$Name, [string]$Header) { @"
unit $Name;$Header

interface

procedure Touch$Name(var B: Integer);

implementation

procedure Touch$Name(var B: Integer);
begin
  B := B + 1; // dl:ok duplicate-code@1a2b -- planted: no finding on this line under any DB
end;

end.
"@ }
WriteAscii (Join-Path $scratch 'shared\gone.pas')   (NoFindingUnit 'gone' $hdr)
WriteAscii (Join-Path $scratch 'shared\triple.pas') (NoFindingUnit 'triple' ' // dl:shared SecA, SecB, SecC')
WriteAscii (Join-Path $scratch 'aonly\aonly.pas')   (NoFindingUnit 'aonly' $hdr)
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
  thing, drift, gone, triple, aonly, other, solo;

procedure RunA;
var
  N: Integer;
begin
  thing.Crunch;
  drift.Sweep;
  gone.Touchgone(N);
  triple.Touchtriple(N);
  aonly.Touchaonly(N);
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
  thing, drift, gone, triple, other, solo;

procedure RunB;
var
  N: Integer;
begin
  gone.Touchgone(N);
  triple.Touchtriple(N);
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
      { "name": "SecA", "db": "a.sqlite", "include": ["shared", "common", "plain", "aonly"] },
      { "name": "SecB", "db": "b.sqlite", "include": ["shared", "bside", "plain"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
$dbA = Join-Path $scratch 'out\a.sqlite'; $dbB = Join-Path $scratch 'out\b.sqlite'

function HintAt([string]$Out, [string]$File, [string]$Rule) { $Out -match "(?im)$File[:\w\\/.]*:\d+:\d+[^\r\n]*$Rule" }
function UnusedAt([string]$Out, [string]$File) { HintAt $Out $File 'review-marker-unused' }

Push-Location C:\TEMP
try {
  & $exePath index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
  & $exePath index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
  Check '0. sanity: both DBs exist' ((Test-Path $dbA) -and (Test-Path $dbB))

  { # record the two real markers against B's report
    $pre = (& $exePath lint-all --db $dbB --rule duplicate-code 2>&1 | Out-String)
    foreach ($u in 'thing','drift') {
      $m = [regex]::Match($pre, "(?im)$u\.pas:(\d+):\d+\s+\[\w+\]\s+duplicate-code")
      Check "0b. sanity: duplicate-code fires on $u.pas under B" $m.Success
      if ($m.Success) { & $exePath allow (Join-Path $scratch "shared\$u.pas") --fix-line $m.Groups[1].Value --fix-rule duplicate-code --apply 2>&1 | Out-Null }
      Check "0c. sanity: a dl:ok duplicate-code marker was written on $u.pas" ((Get-Content (Join-Path $scratch "shared\$u.pas") -Raw) -match 'dl:ok duplicate-code@')
    }
    $preA = (& $exePath lint-all --db $dbA --rule duplicate-code 2>&1 | Out-String)
    Check '0d. sanity: duplicate-code does NOT fire on thing/drift under A' (-not ($preA -match '(?im)(thing|drift)\.pas:\d+:\d+\s+\[\w+\]\s+duplicate-code')) ($preA -split "`n" | Where-Object { $_ -match 'duplicate-code' } | Select-Object -First 3 | Out-String)
    # corrupt drift's hash: its finding exists only under B, so only B can call it stale
    $dp = Join-Path $scratch 'shared\drift.pas'
    $dt = [IO.File]::ReadAllText($dp)
    $h = [regex]::Match($dt, 'dl:ok duplicate-code@([0-9a-fA-F]{4})').Groups[1].Value
    $bad = if ($h -ieq 'beef') { 'cafe' } else { 'beef' }
    [IO.File]::WriteAllText($dp, $dt.Replace("duplicate-code@$h", "duplicate-code@$bad"), (New-Object System.Text.ASCIIEncoding))
  }.Invoke()

  $solo = (& $exePath lint-all --db $dbA 2>&1 | Out-String)
  $two  = (& $exePath lint-all --db $dbA --db $dbB 2>&1 | Out-String)
  foreach ($u in 'thing','drift','gone','triple','aonly') {
    Check "1. one DB keeps the skip: $u.pas not reported unused" (-not (UnusedAt $solo "$u\.pas"))
  }
  Check '1b. --db A --db B is NOT a union (second slot = library): gone.pas stays skipped' (-not (UnusedAt $two 'gone\.pas'))
  Check '1c. one DB: drift.pas is not called stale (A has no finding)' (-not (HintAt $solo 'drift\.pas' 'review-marker-stale'))

  $u = (& $exePath lint-all --db $dbA --shared-db $dbB 2>&1 | Out-String)
  Write-Host (($u -split "`n" | Where-Object { $_ -match 'review-marker|shared-db' }) -join "`n") -ForegroundColor DarkGray
  Check '2. POSITIVE CONTROL: a marker no DB produces a finding for IS reported unused' (UnusedAt $u 'gone\.pas')
  Check '3. a marker live only under the peer is NOT reported unused' (-not (UnusedAt $u 'thing\.pas'))
  Check '4. a marker stale under the peer IS reported stale' (HintAt $u 'drift\.pas' 'review-marker-stale')
  Check '4b. ...and not also unused (the peer did produce the finding)' (-not (UnusedAt $u 'drift\.pas'))
  Check '5. fewer DBs than dl:shared lists: triple.pas stays skipped' (-not (UnusedAt $u 'triple\.pas'))
  Check '6. the peer does not scan aonly.pas: it stays skipped' (-not (UnusedAt $u 'aonly\.pas'))
  Check '7. CONTROL: unshared solo.pas marker still reported unused' (UnusedAt $u 'solo\.pas')
  Check '7b. CONTROL: AST-rule marker on a shared unit still reported unused' (UnusedAt $u 'other\.pas')
  Check '7c. the run names what it judged and left' ($u -match '(?im)^lint-all: --shared-db: \d+ marker\(s\) judged across 2 DB\(s\), \d+ left unjudged')

  $rev = (& $exePath lint-all --db $dbB --shared-db $dbA 2>&1 | Out-String)
  Check '8. from the other side: gone.pas reported unused' (UnusedAt $rev 'gone\.pas')
  Check '8b. from the other side: thing.pas live here, not unused' (-not (UnusedAt $rev 'thing\.pas'))
  Check '8c. from the other side: the finding itself stays suppressed' (-not (HintAt $rev 'thing\.pas' '\bduplicate-code\b(?!.*review)'))

  $self = (& $exePath lint-all --db $dbA --shared-db $dbA 2>&1 | Out-String)
  Check '9. the primary as its own peer is not a second witness: gone.pas stays skipped' (-not (UnusedAt $self 'gone\.pas'))

  $missing = Join-Path $scratch 'nosuch.sqlite'
  $mo = (& $exePath lint-all --db $dbA --shared-db $missing 2>&1 | Out-String); $mx = $LASTEXITCODE
  Check '10. a --shared-db that does not exist refuses (exit 2, named)' (($mx -eq 2) -and ($mo -match 'nosuch\.sqlite')) "exit=$mx"

  $junk = Join-Path $scratch 'junk.sqlite'
  [IO.File]::WriteAllText($junk, 'this is not a database')
  $jo = (& $exePath lint-all --db $dbA --shared-db $junk 2>&1 | Out-String)
  Check '10b. a peer that cannot run is no evidence: gone.pas stays skipped' (-not (UnusedAt $jo 'gone\.pas'))
  Check '10c. ...and the run says so' ($jo -match '(?im)--shared-db.*junk\.sqlite')

  $jsonOut = & $exePath lint-all --db $dbA --shared-db $dbB --json 2>$null
  $doc = ($jsonOut | Out-String) | ConvertFrom-Json
  $goneRows = @($doc | Where-Object { $_.rule -eq 'review-marker-unused' -and $_.file_path -match 'gone\.pas' })
  Check '11. --json: stdout stays one document and carries the verdict' ($goneRows.Count -ge 1) "rows=$($doc.Count)"

  $lp = (& $exePath lint (Join-Path $scratch 'shared\gone.pas') --db $dbA --shared-db $dbB 2>&1 | Out-String); $lx = $LASTEXITCODE
  Check '12. --shared-db on another verb refuses instead of being ignored' (($lx -eq 3) -and ($lp -match 'shared-db.*lint-all only')) "exit=$lx"

  $left = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Filter 'draglint-marker-account-*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) })
  Check '13. no account temp file left behind' ($left.Count -eq 0) "left=$($left.Count)"
} finally { Pop-Location; [IO.Directory]::Delete($scratch, $true) }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} catch { Write-Host "ERROR: $_" -ForegroundColor Red; exit 2 }
