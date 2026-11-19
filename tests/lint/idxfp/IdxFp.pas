unit IdxFp;
{ index-possibly-out-of-range FP classes (1.52 lane BK-RULEFP, from the IDXRANGE2 12-sample).
  Lines marked SILENT must not fire; lines marked FIRE are the positive controls. Line numbers
  are pinned by tests\autotest\run_v152_BK-RULEFP.ps1 -- append, never insert. }

interface

implementation

uses
  System.SysUtils, System.Generics.Collections, IdxFpConsts;

{ F1 (YADF.Tokens:208): the lower guard `if j < 0 then Exit` survives the later Inc(j); the upper
  side is `j < AExt` with AExt a parameter every local caller passes as a valid index. }
procedure MarkAfter(const AList: TList<Integer>; AExt: Integer; var AMarks: TArray<Boolean>);
var
  j: Integer;
begin
  j:= AExt - 1;
  while (j >= 0) and (AList[j] <> 0) do
    Dec(j);
  if j < 0 then
    Exit;
  Inc(j);
  while (j < AExt) and (AList[j] = 1) do
    Inc(j);
  if j < AExt then
    AMarks[j]:= True;                                   { SILENT line 28 (write at 25) }
end;

procedure MarkAll(const AList: TList<Integer>; var AMarks: TArray<Boolean>);
var
  i: Integer;
begin
  SetLength(AMarks, AList.Count);
  for i:= 0 to AList.Count - 1 do
    if AList[i] = 7 then
      MarkAfter(AList, i, AMarks);
end;

{ F1 control: a caller passes the Count itself (one past High) -- the bound is not proven. }
procedure MarkAfterBad(const AList: TList<Integer>; AExt: Integer; var AMarks: TArray<Boolean>);
var
  j: Integer;
begin
  j:= AExt - 1;
  if j < 0 then
    Exit;
  Inc(j);
  while (j < AExt) and (AList[j] = 1) do
    Inc(j);
  if j <= AExt then
    AMarks[j]:= True;                                   { FIRE on the write at line 49 }
end;

procedure MarkAllBad(const AList: TList<Integer>; var AMarks: TArray<Boolean>);
begin
  SetLength(AMarks, AList.Count);
  MarkAfterBad(AList, AList.Count, AMarks);
end;

{ F2 (STATS:1988): `if not (gi in [1, 3]) then gi := 3` clamps gi into the set. }
function PickSx(g: Integer): Double;
var
  sx: array[1..14] of Double;
  gi: Integer;
begin
  FillChar(sx, SizeOf(sx), 0);
  gi:= g;
  if not (gi in [1, 3]) then
    gi:= 3;
  Result:= sx[gi];                                      { SILENT (write at 68) }
end;

{ F2 control: the set reaches past the array. }
function PickSxBad(g: Integer): Double;
var
  sx: array[1..14] of Double;
  gi: Integer;
begin
  FillChar(sx, SizeOf(sx), 0);
  gi:= g;                                               { FIRE line 81 }
  if not (gi in [1, 3, 20]) then
    gi:= 3;
  Result:= sx[gi];
end;

{ F2b: a range element in the set. }
function PickSxRange(g: Integer): Double;
var
  sx: array[1..14] of Double;
begin
  FillChar(sx, SizeOf(sx), 0);
  Result:= 0;
  if g in [2..9] then
    Result:= sx[g];                                     { SILENT (parameter) line 95 }
end;

{ F3 (uINSPRSLT:1871): a raise guard on Length(AHist) and a loop limit written once from an
  if-expression of a foreign constant array's High and a local constant. }
function NssFrom(const AHist: array of Integer; ACase: Integer): Integer;
const
  BINS = 9;
var
  i, Last: Integer;
begin
  if Length(AHist) < BINS then
    raise EArgumentOutOfRangeException.Create('short');
  Last:= if ACase <= 3 then High(NssConv) else BINS - 1;
  i:= 0;
  while (i < Last) and (AHist[i] = 0) do Inc(i);       { SILENT with an index (write at 109) }
  Result:= i;
end;

{ F3 control: the Length guard is too weak for the loop limit. }
function NssFromBad(const AHist: array of Integer; ACase: Integer): Integer;
var
  i, Last: Integer;
begin
  if Length(AHist) < 5 then
    raise EArgumentOutOfRangeException.Create('short');
  Last:= if ACase <= 3 then 4 else 8;
  i:= 0;                                                { FIRE line 121 }
  while (i < Last) and (AHist[i] = 0) do Inc(i);
  Result:= i;
end;

{ F4 (Pipes.Protocol:1069): the out array is nil-ed, then sized from an array assigned once. }
function TryParse(const AText: string; out AParts: TArray<Integer>): Boolean;
var
  LTexts: TArray<string>;
  I: Integer;
begin
  AParts:= nil;
  LTexts:= AText.Split(['.']);
  SetLength(AParts, Length(LTexts));
  for I:= 0 to High(LTexts) do
    AParts[I]:= StrToIntDef(LTexts[I], -1);             { SILENT (for at 134) }
  Result:= True;
end;

{ F4 control: sized one short. }
function TryParseBad(const AText: string; out AParts: TArray<Integer>): Boolean;
var
  LTexts: TArray<string>;
  I: Integer;
begin
  LTexts:= AText.Split(['.']);
  SetLength(AParts, Length(LTexts) - 1);
  for I:= 0 to High(LTexts) do                          { FIRE line 146 }
    AParts[I]:= StrToIntDef(LTexts[I], -1);
  Result:= True;
end;

{ F5 (uBroadcastServer:373): one Inc per trip of a for-in over the dictionary the array is sized from. }
function Targets(const ASubs: TDictionary<string, Integer>): TArray<string>;
var
  ID: string;
  I: Integer;
  T: TArray<string>;
begin
  SetLength(T, ASubs.Count);
  I:= 0;
  for ID in ASubs.Keys do begin T[I]:= ID; Inc(I); end;  { SILENT }
  Result:= T;
end;

{ F5 control: two steps per trip. }
function TargetsBad(const ASubs: TDictionary<string, Integer>): TArray<string>;
var
  ID: string;
  I: Integer;
  T: TArray<string>;
begin
  SetLength(T, ASubs.Count);
  I:= 0;                                                { FIRE }
  for ID in ASubs.Keys do begin T[I]:= ID; Inc(I); Inc(I); end;
  Result:= T;
end;

{ F6 (Blueprint4:2009): the for start is hdi + 1 where hdi only grows from 2. }
procedure Rows6(const ALines: TList<string>);
var
  Rows: TArray<string>;
  RowCount, hdi: Integer;
begin
  hdi:= 2;
  while (hdi < ALines.Count) and (ALines[hdi] <> '') do
    Inc(hdi);
  SetLength(Rows, ALines.Count);
  RowCount:= 0;
  for var I: Integer:= hdi + 1 to ALines.Count - 1 do
  begin
    if ALines[I] = '' then Continue;
    Rows[RowCount]:= ALines[I];                         { SILENT (write at 183) }
    Inc(RowCount);
  end;
end;

{ F6 control: hdi can go negative. }
procedure Rows6Bad(const ALines: TList<string>);
var
  Rows: TArray<string>;
  RowCount, hdi: Integer;
begin
  hdi:= 2;
  Dec(hdi, 5);
  SetLength(Rows, ALines.Count);
  RowCount:= 0;                                         { FIRE line 197 }
  for var I: Integer:= hdi + 1 to ALines.Count - 1 do
  begin
    Rows[RowCount]:= ALines[I];
    Inc(RowCount);
  end;
end;

{ F7 (Blueprint4:1722): a count written once from Length of an array assigned once. }
procedure Rows7(const AText: string);
var
  Rows: TArray<string>;
  RowCount: Integer;
begin
  var Hdr: TArray<string>:= AText.Split([',']);
  var ColCount: Integer:= Length(Hdr);
  SetLength(Rows, ColCount);
  RowCount:= 0;
  for var I: Integer:= 2 to ColCount - 1 do
  begin
    Rows[RowCount]:= Hdr[I];                            { SILENT (write at 213) }
    Inc(RowCount);
  end;
end;

{ F8 (Blueprint4:1722/2009, uBroadcastServer:373): the array is sized twice in the routine -- the
  dominating SetLength before the loop counts, the trim after it does not. }
procedure Rows8(const ALines: TList<string>);
var
  Rows: TArray<string>;
  RowCount: Integer;
begin
  SetLength(Rows, ALines.Count);
  RowCount:= 0;
  for var I: Integer:= 0 to ALines.Count - 1 do
  begin
    Rows[RowCount]:= ALines[I];
    Inc(RowCount);
  end;
  SetLength(Rows, RowCount);
end;

{ F8 control: the array is resized inside the loop. }
procedure Rows8Bad(const ALines: TList<string>);
var
  Rows: TArray<string>;
  RowCount: Integer;
begin
  SetLength(Rows, ALines.Count);
  RowCount:= 0;
  for var I: Integer:= 0 to ALines.Count - 1 do
  begin
    Rows[RowCount]:= ALines[I];
    Inc(RowCount);
    SetLength(Rows, RowCount);
  end;
end;

{ F9 (YADF.Tokens:230): the caller passes its own dynamic-array Result. }
procedure MarkOne(AExt: Integer; var AMarks: TArray<Boolean>);
var
  j: Integer;
begin
  j:= AExt - 1;
  if j < 0 then
    Exit;
  Inc(j);
  if j < AExt then
    AMarks[j]:= True;
end;

function MarkFn(const AList: TList<Integer>): TArray<Boolean>;
var
  i: Integer;
begin
  SetLength(Result, AList.Count);
  for i:= 0 to AList.Count - 1 do
    MarkOne(i, Result);
end;

end.