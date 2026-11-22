unit XuUse;
{ index-possibly-out-of-range, lane IDXRANGE-TP (1.52.3): the accessed array is a constant array
  declared in ANOTHER unit (uINSPRSLT:5575 -> MscConst.pas:189). Routines named *Fire must fire,
  the others must stay silent. Pinned by tests\autotest\run_v1523_IDXRANGE-TP.ps1. }

interface

type
  TInsp = class
    f_DistHist: array [0 .. 8] of Integer;
    fNSS: Integer;
    fCase: Integer;
    procedure DisplayFire;
  end;

implementation

uses
  XuConsts;

{ The ORM3 line verbatim: i reaches 5 when bins 0..4 are empty, NssDistConvert is 0..4. }
procedure TInsp.DisplayFire;
var
  i: Integer;
begin
  if fCase <= 3 then begin i:= 0; while (f_DistHist[i] = 0) and (i <= 4) do Inc(i); fNSS:= NssDistConvert[i]; end;
end;

{ Same shape, Integer element type, one statement per line. }
procedure ConvFire(const AHist: array of Integer; var N: Integer);
var
  i: Integer;
begin
  if Length(AHist) < 9 then Exit;
  i:= 0;
  while (AHist[i] = 0) and (i <= 4) do Inc(i);
  N:= NssConv[i];
end;

{ Guarded on the foreign array's own High before the access. }
procedure ConvSilent(const AHist: array of Integer; var N: Integer);
var
  i: Integer;
begin
  if Length(AHist) < 9 then Exit;
  i:= 0;
  while (AHist[i] = 0) and (i <= 4) do Inc(i);
  if i <= High(NssConv) then N:= NssConv[i];
end;

{ for over the foreign array's own bounds. }
procedure ForSilent(var N: Integer);
var
  i: Integer;
begin
  N:= 0;
  for i:= Low(NssDistConvert) to High(NssDistConvert) do
    N:= N + NssDistConvert[i];
end;

{ Twice is declared twice with different bounds (XuConsts, XuConsts2): no shape, no finding. }
procedure AmbigSilent(const AHist: array of Integer; var N: Integer);
var
  i: Integer;
begin
  if Length(AHist) < 9 then Exit;
  i:= 0;
  while (AHist[i] = 0) and (i <= 4) do Inc(i);
  N:= Twice[i];
end;

{ A local constant shadows the foreign name with wider bounds: the local wins (guard i <= 8). }
procedure ShadowSilent(const AHist: array of Integer; var N: Integer);
const
  NssConv: array [0 .. 8] of Integer = (0, 1, 2, 3, 4, 5, 6, 7, 8);
var
  i: Integer;
begin
  if Length(AHist) < 9 then Exit;
  i:= 0;
  while (AHist[i] = 0) and (i <= 4) do Inc(i);
  if i <= 8 then N:= NssConv[i];
end;

{ ORM3 FP set (1.52.3 A/B): shapes that are in range; another unit's array is reported only on a
  PROVEN overrun, so each stays silent. BASICSF:3938 clamp. }
function ClampSilent(const ps: Integer): Integer;
var
  i: Integer;
begin
  i:= ps;
  if i < 0 then i:= 0;
  if i > 9 then i:= 9;
  Result:= SevColor[i];
end;

{ uINSPRSLT:3128: the while stops at High(QTab). }
function WhileHighSilent(N: Integer): Integer;
var
  i: Integer;
begin
  i:= 1;
  while (i < High(QTab)) and (N > QTab[i]) do Inc(i);
  Result:= QTab[i];
end;

{ uINSPRSLT:1872 (the fixed NssFromDistHist): the same condition picks the limit and the array. }
function CorrelatedSilent(const AHist: array of Integer; ACase: Integer): Integer;
var
  i, Last: Integer;
begin
  if Length(AHist) < 9 then Exit(0);
  Last:= if ACase <= 3 then High(NssDistConvert) else 8;
  i:= 0;
  while (i < Last) and (AHist[i] = 0) do Inc(i);
  Result:= if ACase <= 3 then NssDistConvert[i] else i;
end;

{ STATS:1312: j is guarded against a parallel array of another shape source. }
function ParallelSilent(const ASizes: array of Integer; ASample: Integer): Double;
var
  j: Integer;
begin
  j:= 1;
  while (j <= High(ASizes)) and (ASample < ASizes[j]) do Inc(j);
  if j > High(ASizes) then Result:= 100
  else Result:= Aql[j];
end;

end.