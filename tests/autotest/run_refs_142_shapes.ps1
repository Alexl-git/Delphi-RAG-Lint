<#
  run_refs_142_shapes.ps1 -- the five ref shapes of the 1.42 `refs` lane
  (BACKLOG-2026-11-01 rows HARDCAST-CALL, EXT-PARENCAST-REF, EXT-PROCFIELD-WRITE,
  EXT-REFFUNC-RET, EXT-CONSTINIT-READ), pinned on one fixture.

  THE DEFECT FIXED HERE (HARDCAST-CALL). A hard cast `TEnum(X)` cannot be told
  from a one-argument call at parse, so the extractor records it as a 'call' ref
  and the resolver (X6 / gap G1, ResolveEnumCast) binds it to the ENUM type --
  deliberately keeping kind 'call' (lint rule enum-ordinal-persisted selects
  exactly those rows) and writing no call_edges row. But `usages` bucketed by
  the ref kind alone, so `usages --name TCommandID` reported every cast as a
  CALL ("calls: 1045" on Micronite2027). The bucket now asks what the ref is
  BOUND to: a 'call' ref bound to one of the name's TYPE declarations is a type
  use and lands in 'types' (UsageBucketIn, shared by the CLI verb and the LSP
  draglint/usages reply).

  THE OTHER FOUR were fixed before 1.42 (G4 paren-cast receiver, dotted-lhs
  write mode, reference-to return typeref, const-initializer reads); they are
  pinned here as REGRESSION checks, each with the symptom the gap log recorded
  (usages bucket / uses-audit), not only the raw ref row.

  CONTROLS:
    * a real one-argument FUNCTION call `PrTwin(K)` stays in 'calls';
    * the cast ref itself is still kind 'call' bound to the enum (the
      enum-ordinal-persisted contract) -- the fix is in the bucket, not the row;
    * a unit that imports uPrA in its interface and uses it ONLY in the
      implementation IS reported "MOVE down" by uses-audit, so the two negative
      uses-audit checks cannot pass with uses-audit silent.

  Exit code: 0 on full pass, 1 on any failure. pwsh 7. Run from a neutral CWD.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_refs142_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($work)
$db = Join-Path $work 'refs142.sqlite'

$units = [ordered]@{}
$units['uPrA'] = @'
unit uPrA;

interface

const
  PR_VERSION = '1.0';

type
  TPrKind = (pkA, pkB);
  TPrShape = class
    Name: string;
  end;
  IPrStore = interface
    procedure Touch;
  end;
  TPrHdr = record
    CommandID: Integer;
  end;
  TPrHost = record
    FeedHarvest: TProc<TArray<string>>;
  end;

function PrTwin(pN: Integer): Integer;

implementation

function PrTwin(pN: Integer): Integer;
begin
  Result:= pN;
end;

end.
'@
$units['uPrB'] = @'
unit uPrB;

interface

uses System.SysUtils, uPrA;

procedure Run(pShape: TObject; const pHdr: TPrHdr);

implementation

procedure Run(pShape: TObject; const pHdr: TPrHdr);
var
  K: TPrKind;
  N: Integer;
  LHost: TPrHost;
begin
  K:= TPrKind(pHdr.CommandID);
  N:= PrTwin(Ord(K));
  Writeln((pShape as TPrShape).Name, N);
  LHost.FeedHarvest:= procedure(APaths: TArray<string>)
    var
      LErrs: TArray<string>;
    begin
      LErrs:= APaths;
    end;
end;

end.
'@
$units['uPrConst'] = @'
unit uPrConst;

interface

uses uPrA;

const
  VERSION = PR_VERSION;

implementation

end.
'@
$units['uPrRefFn'] = @'
unit uPrRefFn;

interface

uses uPrA;

type
  TPrOpener = reference to function(const pPath: string): IPrStore;

implementation

end.
'@
$units['uPrMove'] = @'
unit uPrMove;

interface

uses uPrA;

function MoveMe: string;

implementation

function MoveMe: string;
begin
  Result:= PR_VERSION;
end;

end.
'@
foreach ($k in $units.Keys) {
  $norm = $units[$k] -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText((Join-Path $work "$k.pas"), $norm, [Text.Encoding]::ASCII)
}

function Usages($name) {
  $raw = (& $exePath usages --name $name --db $db --json 2>$null) -join "`n"
  try { return $raw | ConvertFrom-Json } catch { return $null }
}
function Lines($arr, $file) {
  @($arr | Where-Object { [IO.Path]::GetFileNameWithoutExtension([string]$_.file) -eq $file } | ForEach-Object { [int]$_.line })
}

Push-Location $env:TEMP
try {
  & $exePath index $work --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  # sql --json rows are POSITIONAL arrays: [0]=file, [1]=name, [2]=kind, [3]=line, [4]=receiver, [5]=symbol kind.
  $q = "select f.path, r.name_text, r.kind, r.start_line, coalesce(r.receiver_text, ''), coalesce(s.kind, '') " +
       "from refs r join files f on f.id = r.file_id left join symbols s on s.id = r.symbol_id"
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n" | ConvertFrom-Json
  $rows = @(foreach ($row in $j.rows) {
    [pscustomobject]@{ File = [IO.Path]::GetFileNameWithoutExtension([string]$row[0]); Name = [string]$row[1]
                       Kind = [string]$row[2]; Line = [int]$row[3]; Rcv = [string]$row[4]; SymKind = [string]$row[5] } })
  Check 'refs were read for the fixture (premise)' ($rows.Count -gt 10) "rows=$($rows.Count)"
  function Sel($file, $name, $kind, $line) {
    @($rows | Where-Object { $_.File -eq $file -and $_.Name -eq $name -and $_.Kind -eq $kind -and $_.Line -eq $line })
  }

  Write-Host 'HARDCAST-CALL -- TPrKind(pHdr.CommandID) is a type use, not a call:' -ForegroundColor Cyan
  $cast = Sel 'uPrB' 'TPrKind' 'call' 17
  Check 'CONTROL: the cast ref is still kind call, bound to the enum' ($cast.Count -eq 1 -and $cast[0].SymKind -eq 'enum') "n=$($cast.Count) sym='$(if ($cast.Count) { $cast[0].SymKind })'"
  $u = Usages 'TPrKind'
  Check 'usages TPrKind answered JSON (premise)' ($null -ne $u)
  Check 'usages TPrKind: the cast at uPrB:17 is NOT under calls' ((Lines $u.calls 'uPrB') -notcontains 17) "calls=$((Lines $u.calls 'uPrB') -join ',')"
  Check 'usages TPrKind: the cast at uPrB:17 IS under types' ((Lines $u.types 'uPrB') -contains 17) "types=$((Lines $u.types 'uPrB') -join ',')"
  Check 'usages TPrKind: the local var type at uPrB:13 stays under types' ((Lines $u.types 'uPrB') -contains 13)
  $t = Usages 'PrTwin'
  Check 'CONTROL: PrTwin(Ord(K)) (a real one-arg call) stays under calls' ((Lines $t.calls 'uPrB') -contains 18) "calls=$((Lines $t.calls 'uPrB') -join ',')"

  Write-Host 'EXT-PARENCAST-REF -- member after a parenthesised as-cast:' -ForegroundColor Cyan
  $pc = Sel 'uPrB' 'Name' 'member-access' 19
  Check '(pShape as TPrShape).Name has ONE member-access ref' ($pc.Count -eq 1) "n=$($pc.Count)"
  Check '... with receiver text (pShape as TPrShape)' ($pc.Count -eq 1 -and $pc[0].Rcv -eq '(pShape as TPrShape)') "rcv='$(if ($pc.Count) { $pc[0].Rcv })'"

  Write-Host 'EXT-PROCFIELD-WRITE -- LHost.FeedHarvest:= procedure(...):' -ForegroundColor Cyan
  $f = Usages 'FeedHarvest'
  Check 'usages FeedHarvest: uPrB:20 is a write' ((Lines $f.writes 'uPrB') -contains 20) "writes=$((Lines $f.writes 'uPrB') -join ',') calls=$((Lines $f.calls 'uPrB') -join ',')"

  Write-Host 'EXT-REFFUNC-RET -- return type of reference to function:' -ForegroundColor Cyan
  Check 'IPrStore has a type_use ref at uPrRefFn:8' ((Sel 'uPrRefFn' 'IPrStore' 'type_use' 8).Count -eq 1)

  Write-Host 'EXT-CONSTINIT-READ -- untyped const initializer:' -ForegroundColor Cyan
  Check 'PR_VERSION has a read ref at uPrConst:8' ((Sel 'uPrConst' 'PR_VERSION' 'read' 8).Count -eq 1)

  Write-Host 'uses-audit (the symptom both gap lines recorded):' -ForegroundColor Cyan
  $au = @{}
  foreach ($k in 'uPrMove', 'uPrConst', 'uPrRefFn') {
    $au[$k] = (& $exePath uses-audit (Join-Path $work "$k.pas") --db $db 2>$null | Out-String)
  }
  Check 'CONTROL: uPrMove (uPrA used only in implementation) IS a MOVE candidate' ($au['uPrMove'] -match 'uPrA\s+--.*MOVE') ($au['uPrMove'].Trim() -replace "`r?`n", ' | ')
  Check 'uPrConst (VERSION = PR_VERSION) is NOT a MOVE candidate' ($au['uPrConst'] -notmatch 'uPrA\s+--.*MOVE') ($au['uPrConst'].Trim() -replace "`r?`n", ' | ')
  Check 'uPrRefFn (reference to function: IPrStore) is NOT a MOVE candidate' ($au['uPrRefFn'] -notmatch 'uPrA\s+--.*MOVE') ($au['uPrRefFn'].Trim() -replace "`r?`n", ' | ')
} finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
