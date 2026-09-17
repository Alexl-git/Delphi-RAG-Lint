<#
  run_property_refs_resolve.ps1 -- PROPERTY and FIELD references resolve
  (docs\INBOX-property-refs-never-resolve.md; spec
  docs\superpowers\specs\2026-09-16-property-refs-resolve.md).

  THE DEFECT: a `member-access` ref naming a property reached the resolve pass
  (v20b) and was discarded there because only ROUTINE targets may own a
  call_edges row -- so `find-callers --resolved` answered 0 for `Connected`
  while `Disconnect` on the same receiver answered 4, and lint-tree reported
  "0 place(s)" when a public property with 207 dependents was removed.

  THE OWNER'S RULING (2026-09-16): a property READ is also a call to its read
  accessor; a WRITE is also a call to its write accessor; when the accessor is
  a FIELD, record a read/write USE of the field instead.

  FIXTURE (uProv / uCons, the note's shape widened):
    property Flag : Boolean read GetFlag write FFlag;    getter METHOD, setter FIELD
    property Count: Integer read FCount  write SetCount; getter FIELD,  setter METHOD
    property Items[I: Integer]: Integer read GetItem write SetItem;   indexed
    procedure DoWork;                                    the routine CONTROL
  and in uCons:
    ReadIt : if FProv.Flag then FProv.DoWork;            Flag READ  -> GetFlag call
    WriteIt: FProv.Flag := True;                         Flag WRITE -> FFlag use
    CountIt: FProv.Count := FProv.Count + 1;             Count WRITE -> SetCount call; Count READ -> FCount use
    IndexIt: FProv.Items[0] := 2;                        Items WRITE past an indexer -> SetItem call
    ReadCnt: if FProv.Count > 0 then ...;                Count READ -> FCount use

  POSITIVE CONTROL: on the pre-fix engine every property/field assertion is
  RED and every DoWork assertion is GREEN. If the DoWork assertions go red the
  fixture, not the feature, is broken.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_property_refs_resolve'
if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
New-Item -ItemType Directory $scratch | Out-Null
function W([string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $scratch $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

W 'uProv.pas' @'
unit uProv;

interface

type
  TProvider = class
  private
    FFlag: Boolean;
    FCount: Integer;
    FItems: array[0..3] of Integer;
    function GetFlag: Boolean;
    procedure SetCount(const AValue: Integer);
    function GetItem(I: Integer): Integer;
    procedure SetItem(I: Integer; const AValue: Integer);
  public
    procedure DoWork;
    property Flag: Boolean read GetFlag write FFlag;
    property Count: Integer read FCount write SetCount;
    property Items[I: Integer]: Integer read GetItem write SetItem;
  end;

implementation

function TProvider.GetFlag: Boolean;
begin
  Result := FFlag;
end;

procedure TProvider.SetCount(const AValue: Integer);
begin
  FCount := AValue;
end;

function TProvider.GetItem(I: Integer): Integer;
begin
  Result := FItems[I];
end;

procedure TProvider.SetItem(I: Integer; const AValue: Integer);
begin
  FItems[I] := AValue;
end;

procedure TProvider.DoWork;
begin
  FCount := 0;
end;

end.
'@

W 'uCons.pas' @'
unit uCons;

interface

uses
  uProv;

type
  TConsumer = class
  private
    FProv: TProvider;
  public
    procedure ReadIt;
    procedure WriteIt;
    procedure CountIt;
    procedure IndexIt;
    procedure ReadCnt;
  end;

implementation

procedure TConsumer.ReadIt;
begin
  if FProv.Flag then FProv.DoWork;
end;

procedure TConsumer.WriteIt;
begin
  FProv.Flag := True;
end;

procedure TConsumer.CountIt;
begin
  FProv.Count := FProv.Count + 1;
end;

procedure TConsumer.IndexIt;
begin
  FProv.Items[0] := 2;
end;

procedure TConsumer.ReadCnt;
begin
  if FProv.Count > 0 then FProv.DoWork;
end;

end.
'@

$db = Join-Path $scratch 'pr.sqlite'
$idxOut = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0) ''
Check 'index reported no parse errors' ($idxOut -match '0 errors') ''

function Resolved([string]$name) {
  $raw = & $exePath query find-callers --name $name --resolved --json --db $db 2>$null | Out-String
  if ($raw.Trim() -eq '') { return @() }
  try { return @(($raw | ConvertFrom-Json)) } catch { return @() }
}
function Of($rows, [string]$target) { @($rows | Where-Object { $_.target_qname -eq $target }) }

Write-Host ''
Write-Host '== control: the routine still resolves exactly as before ==' -ForegroundColor Cyan
$dw = Of (Resolved 'DoWork') 'uProv.TProvider.DoWork'
Check 'DoWork: 2 resolved callers (ReadIt, ReadCnt)' ($dw.Count -eq 2) "n=$($dw.Count)"
Check 'DoWork: both certain' (@($dw | Where-Object { $_.confidence -eq 'certain' }).Count -eq 2) ''

Write-Host ''
Write-Host '== U1/E4: a PROPERTY has resolved callers, with a mode ==' -ForegroundColor Cyan
$fl = Of (Resolved 'Flag') 'uProv.TProvider.Flag'
Check 'Flag: 2 resolved accesses (ReadIt, WriteIt)' ($fl.Count -eq 2) "n=$($fl.Count) raw=$($fl | ConvertTo-Json -Compress)"
Check 'Flag: ReadIt is a READ'   (@($fl | Where-Object { $_.caller_qname -match 'ReadIt$'  -and $_.mode -eq 'read'  }).Count -eq 1) ''
Check 'Flag: WriteIt is a WRITE' (@($fl | Where-Object { $_.caller_qname -match 'WriteIt$' -and $_.mode -eq 'write' }).Count -eq 1) ''
Check 'Flag: both certain' (@($fl | Where-Object { $_.confidence -eq 'certain' }).Count -eq 2) ''
$ct = Of (Resolved 'Count') 'uProv.TProvider.Count'
Check 'Count: 3 resolved accesses (CountIt write + read, ReadCnt read)' ($ct.Count -eq 3) "n=$($ct.Count)"
Check 'Count: exactly one WRITE, two READs' ((@($ct | Where-Object { $_.mode -eq 'write' }).Count -eq 1) -and (@($ct | Where-Object { $_.mode -eq 'read' }).Count -eq 2)) ($ct | ConvertTo-Json -Compress)
$it = Of (Resolved 'Items') 'uProv.TProvider.Items'
Check 'Items: 1 resolved access, a WRITE past the [0] indexer (E3)' ($it.Count -eq 1 -and $it[0].mode -eq 'write') ($it | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== E1: a METHOD accessor is called by the access ==' -ForegroundColor Cyan
$gf = Of (Resolved 'GetFlag') 'uProv.TProvider.GetFlag'
Check 'GetFlag: called by ReadIt (the Flag READ)' ($gf.Count -eq 1 -and $gf[0].caller_qname -match 'ReadIt$') ($gf | ConvertTo-Json -Compress)
$sc = Of (Resolved 'SetCount') 'uProv.TProvider.SetCount'
Check 'SetCount: called by CountIt (the Count WRITE), once' ($sc.Count -eq 1 -and $sc[0].caller_qname -match 'CountIt$') ($sc | ConvertTo-Json -Compress)
$si = Of (Resolved 'SetItem') 'uProv.TProvider.SetItem'
Check 'SetItem: called by IndexIt (the Items WRITE)' ($si.Count -eq 1 -and $si[0].caller_qname -match 'IndexIt$') ($si | ConvertTo-Json -Compress)
$gi = Of (Resolved 'GetItem') 'uProv.TProvider.GetItem'
Check 'GetItem: NOT called (Items is only ever written)' ($gi.Count -eq 0) ($gi | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== E2: a FIELD accessor is USED by the access, with no call edge ==' -ForegroundColor Cyan
$ff = Of (Resolved 'FFlag') 'uProv.TProvider.FFlag'
Check 'FFlag: used by WriteIt (the Flag WRITE), as a write' ($ff.Count -eq 1 -and $ff[0].caller_qname -match 'WriteIt$' -and $ff[0].mode -eq 'write') ($ff | ConvertTo-Json -Compress)
$fc = Of (Resolved 'FCount') 'uProv.TProvider.FCount'
Check 'FCount: used by CountIt and ReadCnt (the Count READs), as reads' ($fc.Count -eq 2 -and (@($fc | Where-Object { $_.mode -eq 'read' }).Count -eq 2)) ($fc | ConvertTo-Json -Compress)

Write-Host ''
Write-Host '== E5: lint-tree sees a removed PROPERTY ==' -ForegroundColor Cyan
$base = Join-Path $scratch 'base.json'
& $exePath lint-tree --unit (Join-Path $scratch 'uProv.pas') --db $db --write-baseline $base --format json *> $null
Check 'baseline written' (Test-Path $base) ''
$buf = Join-Path $scratch 'uProv.buf.pas'
$src = [IO.File]::ReadAllText((Join-Path $scratch 'uProv.pas'))
[IO.File]::WriteAllText($buf, ($src -replace '(?m)^\s*property Flag: Boolean read GetFlag write FFlag;\r?\n', ''), [Text.Encoding]::ASCII)
$lt = & $exePath lint-tree --unit (Join-Path $scratch 'uProv.pas') --db $db --buffer $buf --baseline $base --format json 2>$null | Out-String
$lj = $null; try { $lj = $lt | ConvertFrom-Json } catch { }
Check 'lint-tree returned JSON' ($null -ne $lj) $lt
if ($null -ne $lj) {
  $stale = @($lj.findings | Where-Object { $_.rule -eq 'stale-interface-reference' -or $_.message -match 'no longer declares' })
  Check 'removing Flag reports 2 stale references (ReadIt, WriteIt)' ($stale.Count -eq 2) ($lj.findings | ConvertTo-Json -Compress -Depth 4)
  Check 'property is no longer in not_reportable' (-not (@($lj.not_reportable) -contains 'property')) (@($lj.not_reportable) -join ',')
}

Write-Host ''
if ($script:fail) { Write-Host 'PROPERTY-REFS-RESOLVE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PROPERTY-REFS-RESOLVE: PASS' -ForegroundColor Green
exit 0
