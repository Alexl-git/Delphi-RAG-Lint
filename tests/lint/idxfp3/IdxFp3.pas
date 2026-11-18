unit IdxFp3;

{ Fixture for run_v152_IDXRANGE3.ps1 (1.52 lane IDXRANGE3): the seven FP classes of the FPM2
  re-measure of index-possibly-out-of-range, each modelled on its real site, and next to each a
  routine named *Bad that differs in the one fact the proof needs and must still fire. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, IdxFp3Lib;

type
  THdr = record
    Len: Integer;
  end;

var
  Table: array[0..240] of Double;

implementation

const
  AQL: array[0..5] of Double = (0.1, 0.2, 0.4, 0.8, 1.6, 3.2);

function FindAt(const A, B: TBytes): Integer;
begin
  Result:= Length(A) - Length(B) - 1;
end;

{ 1. short-circuit guard (Pipes.Commands:131): the index is a copy of a local whose writes are
  non-negative or guarded right after the write }
function Chain1(const APayload, AKey: TBytes): Integer;
var
  P1, P2: Integer;
begin
  if Length(AKey) = 0 then P1:= Length(AKey)
  else
  begin
    P1:= FindAt(APayload, AKey);
    if P1 < 0 then Exit(0);
    P1:= P1 + Length(AKey);
  end;
  P2:= P1;
  while (P2 < Length(APayload)) and (APayload[P2] <> 124) do Inc(P2);
  Result:= P2;
end;

function Chain1Bad(const APayload, AKey: TBytes): Integer;
var
  P1, P2: Integer;
begin
  P1:= FindAt(APayload, AKey);
  P2:= P1;
  while (P2 < Length(APayload)) and (APayload[P2] <> 124) do Inc(P2);
  Result:= P2;
end;

{ 2. while-top guard re-checked every trip (YADF.Layout:457/509): i and j feed each other }
function WhileTop(const Src: TArray<Integer>): Integer;
var
  i, j: Integer;
begin
  Result:= 0;
  i:= 0;
  while i <= High(Src) do
  begin
    if Src[i] = 1 then
    begin
      j:= i + 1;
      while (j <= High(Src)) and (Src[j] = 0) do Inc(j);
      if j <= High(Src) then
      begin
        i:= j;
        Continue;
      end;
    end;
    Result:= Result + Src[i];
    Inc(i);
  end;
end;

{ the write before the later access is followed by Continue: the while guard is re-checked first }
function WhileTopNoContinueBad(const Src: TArray<Integer>): Integer;
var
  i, j: Integer;
begin
  Result:= 0;
  i:= 0;
  while i <= High(Src) do
  begin
    if Src[i] = 1 then
    begin
      j:= i + 1;
      while (j <= High(Src)) and (Src[j] = 0) do Inc(j);
      if j <= High(Src) then i:= j + 5;
    end;
    Result:= Result + Src[i];
    Inc(i);
  end;
end;

{ the index copies a local reset at the top of every trip of the loop around it (BASICSF:1399) }
procedure ChainReset(const Data: array of Double);
var
  i, J, k: Integer;
  Used: array of Boolean;
begin
  SetLength(Used, High(Data) - Low(Data) + 3);
  for J:= Low(Data) to High(Data) do Used[J]:= False;
  i:= Low(Data);
  while i <= High(Data) do
  begin
    J:= Low(Data);
    while Used[J] and (J <= High(Data)) do Inc(J);
    if J > High(Data) then Break;
    Used[J]:= True;
    k:= J + 1;
    while k <= High(Data) do
    begin
      if not Used[k] then Used[k]:= True;
      Inc(k);
    end;
    Inc(i);
  end;
end;

procedure ChainResetBad(const Data: array of Double);
var
  i, J, k: Integer;
  Used: array of Boolean;
begin
  SetLength(Used, High(Data) - Low(Data) + 3);
  for J:= Low(Data) to High(Data) do Used[J]:= False;
  i:= Low(Data);
  while i <= High(Data) do
  begin
    J:= Low(Data);
    while Used[J] and (J <= High(Data)) do Inc(J);
    if J > High(Data) then Break;
    Used[J]:= True;
    k:= J - 1;
    while k <= High(Data) do
    begin
      if not Used[k] then Used[k]:= True;
      Inc(k);
    end;
    Inc(i);
  end;
end;

function WhileTopBad(const Src: TArray<Integer>): Integer;
var
  i, j: Integer;
begin
  Result:= 0;
  i:= 0;
  while i <= High(Src) do
  begin
    if Src[i] = 1 then
    begin
      j:= i - 1;
      while (j <= High(Src)) and (Src[j] = 0) do Inc(j);
      if j <= High(Src) then
      begin
        i:= j;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

{ 3a. SetLength(A, N) then an index bounded by N, N a local written once (BASICSF:3578) }
procedure SetLenOnce(AStream: TStream);
var
  Buf: array of Byte;
  Size, i: Integer;
  Ok: Boolean;
begin
  Size:= AStream.Size;
  if Size <= 10 then Exit;
  SetLength(Buf, Size + 1000);
  AStream.ReadBuffer(Pointer(Buf)^, Size);
  i:= 1;
  Ok:= True;
  while (i < Size) and Ok do
  begin
    Ok:= Buf[i] = 0;
    Inc(i, 2);
  end;
end;

procedure SetLenOnceBad(AStream: TStream);
var
  Buf: array of Byte;
  Size, i: Integer;
  Ok: Boolean;
begin
  Size:= AStream.Size;
  if Size <= 10 then Exit;
  SetLength(Buf, Size - 1);
  AStream.ReadBuffer(Pointer(Buf)^, Size - 1);
  i:= 1;
  Ok:= True;
  while (i < Size) and Ok do
  begin
    Ok:= Buf[i] = 0;
    Inc(i, 2);
  end;
end;

{ 3b. N a field of a record nobody changes after the SetLength (Pipes.Framing:557) }
function ReadHdr: THdr;
begin
  Result.Len:= 4;
end;

procedure SetLenField(out AHdr: THdr; out APayload: TBytes);
var
  Off: Integer;
begin
  AHdr:= ReadHdr;
  if AHdr.Len = 0 then Exit;
  SetLength(APayload, AHdr.Len);
  Off:= 0;
  while Off < AHdr.Len do
  begin
    APayload[Off]:= 0;
    if Off > 1000000 then
    begin
      APayload:= nil;
      Exit;
    end;
    Inc(Off);
  end;
end;

{ the array is dropped inside the loop and the loop goes on }
procedure SetLenFieldNilBad(out AHdr: THdr; out APayload: TBytes);
var
  Off: Integer;
begin
  AHdr:= ReadHdr;
  if AHdr.Len = 0 then Exit;
  SetLength(APayload, AHdr.Len);
  Off:= 0;
  while Off < AHdr.Len do
  begin
    APayload[Off]:= 0;
    if Off > 1000000 then APayload:= nil;
    Inc(Off);
  end;
end;

{ 3d. N = Length of a local array that nothing resizes from the SetLength to the end of the loop
  (an element passed to a call is no resize), the loop starting at a guarded local
  (Blueprint4.ViewModel:3004) }
function SetLenOpaque(const ARows: TArray<TArray<string>>): Integer;
var
  Hdr, Rows: TArray<string>;
  First, Cnt, r: Integer;
begin
  Hdr:= nil;
  for r:= 0 to High(ARows) do
    if Length(ARows[r]) > 0 then Hdr:= ARows[r];
  First:= -1;
  for var I: Integer:= 1 to Length(Hdr) - 1 do
    if Hdr[I] <> '' then First:= I;
  if First <= 0 then Exit(0);
  SetLength(Rows, Length(Hdr));
  Cnt:= 0;
  for var I: Integer:= First to Length(Hdr) - 1 do
  begin
    if Trim(Hdr[I]) = '' then Continue;
    Rows[Cnt]:= Hdr[I];
    Inc(Cnt);
  end;
  SetLength(Rows, Cnt);
  Result:= Cnt;
end;

function SetLenOpaqueBad(const ARows: TArray<TArray<string>>): Integer;
var
  Hdr, Rows: TArray<string>;
  First, Cnt, r: Integer;
begin
  Hdr:= nil;
  for r:= 0 to High(ARows) do
    if Length(ARows[r]) > 0 then Hdr:= ARows[r];
  First:= -1;
  for var I: Integer:= 1 to Length(Hdr) - 1 do
    if Hdr[I] <> '' then First:= I;
  if First <= 0 then Exit(0);
  SetLength(Rows, Length(Hdr));
  Hdr:= Hdr + ['x', 'y'];
  Cnt:= 0;
  for var I: Integer:= First to Length(Hdr) - 1 do
  begin
    if Trim(Hdr[I]) = '' then Continue;
    Rows[Cnt]:= Hdr[I];
    Inc(Cnt);
  end;
  SetLength(Rows, Cnt);
  Result:= Cnt;
end;

procedure SetLenFieldBad(out AHdr: THdr; out APayload: TBytes);
var
  Off: Integer;
begin
  AHdr:= ReadHdr;
  if AHdr.Len = 0 then Exit;
  SetLength(APayload, AHdr.Len);
  Off:= 0;
  while Off < AHdr.Len do
  begin
    APayload[Off]:= 0;
    AHdr.Len:= AHdr.Len + 1;
    Inc(Off);
  end;
end;

{ 3c. N via a callee's result: the callee starts with SetLength(Result, ALines.Count)
  (YADF.Layout:5813/6319) -- in this unit, and in another unit of the index }
function MakeLock(ALines: TStringList): TArray<Boolean>;
var
  i: Integer;
begin
  SetLength(Result, ALines.Count);
  for i:= 0 to ALines.Count - 1 do Result[i]:= ALines[i] = '';
end;

function MakeLockShort(ALines: TStringList): TArray<Boolean>;
var
  i: Integer;
begin
  SetLength(Result, ALines.Count - 1);
  for i:= 0 to ALines.Count - 2 do Result[i]:= ALines[i] = '';
end;

function CalleeLen(Lines: TStringList): Integer;
var
  Lock: TArray<Boolean>;
  i: Integer;
begin
  Result:= 0;
  Lock:= MakeLock(Lines);
  for i:= 0 to Lines.Count - 1 do
    if Lock[i] then Inc(Result);
end;

function CalleeLenBad(Lines: TStringList): Integer;
var
  Lock: TArray<Boolean>;
  i: Integer;
begin
  Result:= 0;
  Lock:= MakeLockShort(Lines);
  for i:= 0 to Lines.Count - 1 do
    if Lock[i] then Inc(Result);
end;

function CalleeLib(Lines: TStringList): Integer;
var
  Lock: TArray<Boolean>;
  j: Integer;
begin
  Lock:= LibLock(Lines);
  j:= 0;
  while True do
  begin
    if j >= Lines.Count then Break;
    if Lock[j] then Break;
    Inc(j);
  end;
  Result:= j;
end;

function CalleeLibBad(Lines: TStringList): Integer;
var
  Lock: TArray<Boolean>;
  j: Integer;
begin
  Lock:= LibLockShort(Lines);
  j:= 0;
  while True do
  begin
    if j >= Lines.Count then Break;
    if Lock[j] then Break;
    Inc(j);
  end;
  Result:= j;
end;

{ 4. a dominating Length(A) <> Length(B) Exit (YADF ShapesMatch) }
function ShapesMatch(const A, B: TArray<Integer>): Boolean;
var
  i: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  for i:= 0 to High(A) do if A[i] <> B[i] then Exit(False);
  Result:= True;
end;

function ShapesMatchBad(const A, B: TArray<Integer>): Boolean;
var
  i: Integer;
begin
  if Length(A) = 0 then
    Exit(False);
  for i:= 0 to High(A) do if A[i] <> B[i] then Exit(False);
  Result:= True;
end;

{ 5a. a counter stepped at most once per trip of a for loop over the array itself: compaction
  (YADF.Layout:11227) }
procedure Compact(var Bounds: TArray<Integer>; AMin: Integer);
var
  i, k: Integer;
begin
  k:= 0;
  for i:= 0 to High(Bounds) do if Bounds[i] >= AMin then
  begin
    Bounds[k]:= Bounds[i];
    Inc(k);
  end;
  SetLength(Bounds, k);
end;

procedure CompactBad(var Bounds: TArray<Integer>; AMin: Integer);
var
  i, k: Integer;
begin
  k:= 1;
  for i:= 0 to High(Bounds) do if Bounds[i] >= AMin then
  begin
    Bounds[k]:= Bounds[i];
    Inc(k);
  end;
  SetLength(Bounds, k);
end;

{ 5b. the same in a for-in, re-initialised inside an outer loop, the counter reused after it
  (uBroadcastServer:481) }
procedure Snapshot5(ASubs: TDictionary<Integer, TObject>);
var
  Snap: TArray<TObject>;
  Sub: TObject;
  I: Integer;
begin
  while True do
  begin
    SetLength(Snap, ASubs.Count);
    I:= 0;
    for Sub in ASubs.Values do begin Snap[I]:= Sub; Inc(I); end;
    if Length(Snap) = 0 then Break;
  end;
  I:= 0;
  for Sub in Snap do Inc(I);
end;

procedure Snapshot5Bad(ASubs: TDictionary<Integer, TObject>);
var
  Snap: TArray<TObject>;
  Sub: TObject;
  I: Integer;
begin
  while True do
  begin
    SetLength(Snap, ASubs.Count);
    I:= 1;
    for Sub in ASubs.Values do begin Snap[I]:= Sub; Inc(I); end;
    if Length(Snap) = 0 then Break;
  end;
  I:= 0;
  for Sub in Snap do Inc(I);
end;

{ 5c. a for loop reuses the index inside the loop around the access, and a later statement of
  that loop's body overwrites it before the next trip (YADF.Layout:2801) }
function ForReuse(Lines: TStringList): Integer;
var
  Anchors: TArray<Integer>;
  i, j, StartIdx: Integer;
begin
  Result:= 0;
  SetLength(Anchors, Lines.Count);
  i:= 0;
  while i < Lines.Count do
  begin
    if Anchors[i] = 0 then
    begin
      Inc(i);
      Continue;
    end;
    StartIdx:= i;
    j:= i + 1;
    while (j < Lines.Count) and (Anchors[j] > 0) do Inc(j);
    for i:= StartIdx to j - 1 do Inc(Result, Anchors[i]);
    i:= j;
  end;
end;

function ForReuseBad(Lines: TStringList): Integer;
var
  Anchors: TArray<Integer>;
  i, j, StartIdx: Integer;
begin
  Result:= 0;
  SetLength(Anchors, Lines.Count);
  i:= 0;
  while i < Lines.Count do
  begin
    if Anchors[i] = 0 then
    begin
      Inc(i);
      Continue;
    end;
    StartIdx:= i;
    j:= i + 1;
    while (j < Lines.Count) and (Anchors[j] > 0) do Inc(j);
    i:= j;
    for i:= StartIdx to j - 1 do Inc(Result, Anchors[i]);
  end;
end;

{ 3e. arrays sized through out parameters by a callee that starts with SetLength(AArms,
  ALines.Count) (YADF.Layout:2638), and an array of the enclosing routine indexed in a nested
  one (YADF.Groups:238) }
procedure MarkArms(ALines: TStringList; out AArms, AElse: TArray<Boolean>);
var
  L: Integer;
begin
  SetLength(AArms, ALines.Count);
  SetLength(AElse, ALines.Count);
  for L:= 0 to ALines.Count - 1 do
  begin
    AArms[L]:= False;
    AElse[L]:= False;
  end;
end;

procedure MarkArmsShort(ALines: TStringList; out AArms: TArray<Boolean>);
begin
  SetLength(AArms, ALines.Count - 1);
end;

function OutSized(Lines: TStringList): Integer;
var
  Arms, Els: TArray<Boolean>;
  i: Integer;
begin
  Result:= 0;
  MarkArms(Lines, Arms, Els);
  for i:= 0 to Lines.Count - 1 do
    if Arms[i] or Els[i] then Inc(Result);
end;

function OutSizedBad(Lines: TStringList): Integer;
var
  Arms: TArray<Boolean>;
  i: Integer;
begin
  Result:= 0;
  MarkArmsShort(Lines, Arms);
  for i:= 0 to Lines.Count - 1 do
    if Arms[i] then Inc(Result);
end;

function OuterArr(ATokens: TStringList): TArray<Boolean>;
var
  Flags: TArray<Boolean>;

  procedure Visit(AFrom: Integer);
  var
    k: Integer;
  begin
    if AFrom < 0 then Exit;
    k:= AFrom + 1;
    while (k < ATokens.Count) and (ATokens[k] = '') do
    begin
      Flags[k]:= True;
      Inc(k);
    end;
  end;

begin
  SetLength(Flags, ATokens.Count);
  Visit(0);
  Result:= Flags;
end;

function OuterArrBad(ATokens: TStringList): TArray<Boolean>;
var
  Flags: TArray<Boolean>;

  procedure Visit(AFrom: Integer);
  var
    k: Integer;
  begin
    if AFrom < 0 then Exit;
    k:= AFrom + 1;
    while (k < ATokens.Count) and (ATokens[k] = '') do
    begin
      Flags[k]:= True;
      Inc(k);
    end;
  end;

begin
  Visit(0);
  SetLength(Flags, ATokens.Count);
  Result:= Flags;
end;

{ 3f. grow by one before each store (uPipeSessionBuilder:4522) }
function GrowByOne(AQ: TStrings): TArray<Integer>;
var
  A: TArray<Integer>;
  n, r: Integer;
begin
  n:= 0;
  r:= 0;
  SetLength(A, 0);
  while r < AQ.Count do
  begin
    SetLength(A, n + 1);
    A[n]:= r;
    Inc(n);
    Inc(r, 2);
  end;
  Result:= A;
end;

function GrowByOneBad(AQ: TStrings): TArray<Integer>;
var
  A: TArray<Integer>;
  n, r: Integer;
begin
  n:= 0;
  r:= 0;
  SetLength(A, 0);
  while r < AQ.Count do
  begin
    SetLength(A, n);
    A[n]:= r;
    Inc(n);
    Inc(r, 2);
  end;
  Result:= A;
end;

{ 3g. Count / Length of a field path (uBroadcastServer:686, YADF.Layout:9888) }
type
  TOwner = class
    Subs: TDictionary<Integer, TObject>;
  end;

  TNameRec = record
    Names  : TArray<string>;
    TypeStr: string;
  end;

procedure SnapDotted(AOwner: TOwner);
var
  Snap: TArray<TObject>;
  Sub: TObject;
  I: Integer;
begin
  SetLength(Snap, AOwner.Subs.Count);
  I:= 0;
  for Sub in AOwner.Subs.Values do begin Snap[I]:= Sub; Inc(I); end;
end;

procedure SnapDottedBad(AOwner: TOwner);
var
  Snap: TArray<TObject>;
  Sub: TObject;
  I: Integer;
begin
  SetLength(Snap, AOwner.Subs.Count - 1);
  I:= 0;
  for Sub in AOwner.Subs.Values do begin Snap[I]:= Sub; Inc(I); end;
end;

procedure KeepNames(var ARec: TNameRec; ASeen: TDictionary<string, string>);
var
  Keep: TArray<Integer>;
  KeepCount, M: Integer;
begin
  SetLength(Keep, Length(ARec.Names));
  KeepCount:= 0;
  for M:= 0 to High(ARec.Names) do
    if not ASeen.ContainsKey(ARec.Names[M]) then
    begin
      ASeen.Add(ARec.Names[M], ARec.TypeStr);
      Keep[KeepCount]:= M;
      Inc(KeepCount);
    end;
  SetLength(Keep, KeepCount);
end;

procedure KeepNamesBad(var ARec: TNameRec; ASeen: TDictionary<string, string>);
var
  Keep: TArray<Integer>;
  KeepCount, M: Integer;
begin
  SetLength(Keep, Length(ARec.Names));
  ARec.Names:= ARec.Names + ['x', 'y'];
  KeepCount:= 0;
  for M:= 0 to High(ARec.Names) do
    if not ASeen.ContainsKey(ARec.Names[M]) then
    begin
      ASeen.Add(ARec.Names[M], ARec.TypeStr);
      Keep[KeepCount]:= M;
      Inc(KeepCount);
    end;
  SetLength(Keep, KeepCount);
end;

{ 1b. `idx < Y` with Y a local whose every write lies within the array (YADF.Layout:8067) }
function LeadingComments(const AItem: TArray<Boolean>): Integer;
var
  First, k, LastCode: Integer;
begin
  LastCode:= -1;
  for k:= 0 to High(AItem) do if not AItem[k] then LastCode:= k;
  First:= 0;
  while (First < LastCode) and AItem[First] do Inc(First);
  Result:= First;
end;

function LeadingCommentsBad(const AItem: TArray<Boolean>): Integer;
var
  First, k, LastCode: Integer;
begin
  LastCode:= -1;
  for k:= 0 to High(AItem) do if not AItem[k] then LastCode:= k + 2;
  First:= 0;
  while (First < LastCode) and AItem[First] do Inc(First);
  Result:= First;
end;

{ 1c. `idx < L` in a nested routine, its caller sizing the array by L inside a try..finally
  (Blueprint4.ViewModel:2474); a nested routine with its own `i` is no capture of the outer `i`,
  and a chain i -> RunEnd -> j -> i through the loop (YADF.Layout:2665) }
function SniffUtf8(AStream: TStream): Boolean;
var
  Buf: TBytes;
  N: Integer;

  function Valid(const B: TBytes; L: Integer): Boolean;
  var
    P: Integer;
  begin
    P:= 0;
    while P < L do
    begin
      if B[P] >= $80 then Exit(False);
      Inc(P);
    end;
    Result:= True;
  end;

begin
  try
    N:= AStream.Size;
    if N > 65536 then N:= 65536;
    SetLength(Buf, N);
    if N > 0 then AStream.ReadBuffer(Buf[0], N);
  finally
    AStream.Position:= 0;
  end;
  Result:= Valid(Buf, N);
end;

function SniffUtf8Bad(AStream: TStream): Boolean;
var
  Buf: TBytes;
  N: Integer;

  function ValidBad(const B: TBytes; L: Integer): Boolean;
  var
    P: Integer;
  begin
    P:= 0;
    while P < L do
    begin
      if B[P] >= $80 then Exit(False);
      Inc(P);
    end;
    Result:= True;
  end;

begin
  try
    N:= AStream.Size;
    if N > 65536 then N:= 65536;
    SetLength(Buf, N);
    if N > 0 then AStream.ReadBuffer(Buf[0], N);
  finally
    AStream.Position:= 0;
  end;
  Result:= ValidBad(Buf, N + 1);
end;

function ShadowChain(const Src: TArray<Integer>): Integer;
var
  i, j, RunEnd: Integer;

  function Helper(const A: TArray<Integer>): Integer;
  var
    i: Integer;
  begin
    Result:= 0;
    for i:= 0 to High(A) do Inc(Result, A[i]);
  end;

begin
  Result:= Helper(Src);
  i:= 0;
  while i < Length(Src) do
  begin
    if Src[i] = 0 then
    begin
      Inc(i);
      Continue;
    end;
    RunEnd:= i;
    j:= i + 1;
    while (j < Length(Src)) and (Src[j] > 0) do
    begin
      RunEnd:= j;
      Inc(j);
    end;
    i:= RunEnd + 1;
  end;
end;

function ShadowChainBad(const Src: TArray<Integer>): Integer;
var
  i, j, RunEnd: Integer;

  function Helper(const A: TArray<Integer>): Integer;
  var
    i: Integer;
  begin
    Result:= 0;
    for i:= 0 to High(A) do Inc(Result, A[i]);
  end;

begin
  Result:= Helper(Src);
  i:= 0;
  while i < Length(Src) do
  begin
    if Src[i] = 0 then
    begin
      Inc(i);
      Continue;
    end;
    RunEnd:= i - 2;
    j:= i + 1;
    while (j < Length(Src)) and (Src[j] > 0) do
    begin
      RunEnd:= j;
      Inc(j);
    end;
    i:= RunEnd + 1;
  end;
end;

{ 2b. a write in the other branch of an if / else does not undo the while guard (YADF.Guard:500);
  4b. two arrays sized by the same expression in a row (uPdfScanRescan:523) }
function OtherBranch(ATokens: TStringList): Integer;
var
  Sens: TArray<Boolean>;
  i: Integer;
begin
  Result:= 0;
  SetLength(Sens, ATokens.Count);
  i:= 0;
  while i < ATokens.Count do
  begin
    if ATokens[i] = 'E' then
      Inc(i, 2)
    else if Sens[i] then
      Inc(Result);
    Inc(i);
  end;
end;

function OtherBranchBad(ATokens: TStringList): Integer;
var
  Sens: TArray<Boolean>;
  i: Integer;
begin
  Result:= 0;
  SetLength(Sens, ATokens.Count);
  i:= 0;
  while i < ATokens.Count do
  begin
    if ATokens[i] = 'E' then
      Inc(i, 2);
    if Sens[i] then
      Inc(Result);
    Inc(i);
  end;
end;

function SameSized(AItems: TStringList): Integer;
var
  LIDs: TArray<Integer>;
  LMarked: TArray<Boolean>;
  I: Integer;
begin
  SetLength(LIDs, AItems.Capacity);
  SetLength(LMarked, AItems.Capacity);
  I:= 0;
  AItems.Sort;
  while (I < Length(LIDs)) and (AItems[I] <> '') do
  begin
    LIDs[I]:= I;
    LMarked[I]:= AItems[I] = 'x';
    Inc(I);
  end;
  Result:= I;
end;

function SameSizedBad(AItems: TStringList): Integer;
var
  LIDs: TArray<Integer>;
  LMarked: TArray<Boolean>;
  I: Integer;
begin
  SetLength(LIDs, AItems.Capacity);
  AItems.Add('y');
  SetLength(LMarked, AItems.Capacity);
  I:= 0;
  while (I < Length(LIDs)) and (AItems[I] <> '') do
  begin
    LIDs[I]:= I;
    LMarked[I]:= AItems[I] = 'x';
    Inc(I);
  end;
  Result:= I;
end;

{ 6. a counter with a constant cap on a fixed-size array: straight-line Incs, a filter loop over
  it, the best index from a for counter (FlexDateTime:384..461), three handles (Pipes.Framing:427),
  the last match of a loop over 0..5 (Z14SLCT:103) }
function Cands6(A, B, C, ACut: Integer): Integer;
var
  Cands: array[0..9] of Integer;
  N, NB, Best, i: Integer;
begin
  Result:= 0;
  N:= 0;
  if C = 0 then
  begin
    if A <> 0 then begin Cands[N]:= A; Inc(N); end;
    if B <> 0 then begin Cands[N]:= B; Inc(N); end;
  end
  else
  begin
    if A <> 0 then begin Cands[N]:= A; Inc(N); end;
    if B <> 0 then begin Cands[N]:= B; Inc(N); end;
    if C <> 0 then begin Cands[N]:= C; Inc(N); end;
    if A + B <> 0 then begin Cands[N]:= A + B; Inc(N); end;
    if B + C <> 0 then begin Cands[N]:= B + C; Inc(N); end;
    if A + C <> 0 then begin Cands[N]:= A + C; Inc(N); end;
  end;
  if N = 0 then Exit;
  NB:= 0;
  for i:= 0 to N - 1 do
    if Cands[i] <= ACut then begin Cands[NB]:= Cands[i]; Inc(NB); end;
  N:= NB;
  if N = 0 then Exit;
  Best:= 0;
  for i:= 1 to N - 1 do
    if Cands[i] < Cands[Best] then Best:= i;
  Result:= Cands[Best];
end;

function Cands6Bad(A, B, C: Integer): Integer;
var
  Cands: array[0..4] of Integer;
  N: Integer;
begin
  Result:= 0;
  N:= 0;
  if A <> 0 then begin Cands[N]:= A; Inc(N); end;
  if B <> 0 then begin Cands[N]:= B; Inc(N); end;
  if C <> 0 then begin Cands[N]:= C; Inc(N); end;
  if A + B <> 0 then begin Cands[N]:= A + B; Inc(N); end;
  if B + C <> 0 then begin Cands[N]:= B + C; Inc(N); end;
  if A + C <> 0 then begin Cands[N]:= A + C; Inc(N); end;
  Result:= N;
end;

function Handles3(AStop, AStop2: THandle): Cardinal;
var
  LHandles: array[0..2] of THandle;
  LCount: Cardinal;
begin
  LHandles[0]:= 1;
  LCount:= 1;
  if AStop <> 0 then begin LHandles[LCount]:= AStop; Inc(LCount); end;
  if AStop2 <> 0 then begin LHandles[LCount]:= AStop2; Inc(LCount); end;
  Result:= LCount + Cardinal(LHandles[0]);
end;

function Handles3Bad(AStop, AStop2: THandle): Cardinal;
var
  LHandles: array[0..1] of THandle;
  LCount: Cardinal;
begin
  LHandles[0]:= 1;
  LCount:= 1;
  if AStop <> 0 then begin LHandles[LCount]:= AStop; Inc(LCount); end;
  if AStop2 <> 0 then begin LHandles[LCount]:= AStop2; Inc(LCount); end;
  Result:= LCount + Cardinal(LHandles[0]);
end;

procedure RoundIdx(var pV: Double; var idx: Integer);
var
  i: Integer;
begin
  idx:= 0;
  for i:= 0 to 5 do
    if pV >= AQL[i] then idx:= i;
  pV:= AQL[idx];
end;

procedure RoundIdxBad(var pV: Double; var idx: Integer);
var
  i: Integer;
begin
  idx:= 0;
  for i:= 0 to 6 do
    if pV >= 1.0 then idx:= i;
  pV:= AQL[idx];
end;

{ 7. a float-derived index behind a range guard (STATS:1779) }
function Gauss(x: Double): Double;
var
  j: Integer;
begin
  if Abs(x) > 15.0 then Result:= 0
  else
  begin
    j:= Floor(Abs(x) * 16.0 + 0.5);
    Result:= Table[j];
  end;
end;

function GaussBad(x: Double): Double;
var
  j: Integer;
begin
  if Abs(x) > 15.0 then Result:= 0
  else
  begin
    j:= Floor(Abs(x) * 17.0 + 0.5);
    Result:= Table[j];
  end;
end;

function GaussBad2(x: Double): Double;
var
  j: Integer;
begin
  j:= Floor(Abs(x) * 16.0 + 0.5);
  Result:= Table[j];
end;

end.
