unit IdxRangeFp53;

interface

type
  TBox = class
  private
    FItems: TArray<Integer>;
    FNames: TArray<string>;
    FMarks: TArray<Integer>;
    function ItemAt(AIdx: Integer): Integer;
    function CtlItemAt(AIdx: Integer): Integer;
    procedure AddBoth(const AName: string);
  public
    function Sum: Integer;
    function CtlSum(AFrom: Integer): Integer;
    function Show: Integer;
    function CtlPublic(AIdx: Integer): Integer;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

function Outside(AKey: Integer): Integer; external 'x.dll';

{ 1.53 SLZ-IDXFP shapes (self-LoopZero) -- every plain routine must stay silent, every Ctl* must fire. }

{ H1: binary search, all three usual forms (DataFlowFacts:278, RedundantCast:521) }
function SilentBinary(const A: TArray<Integer>; V: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  Lo := 0;
  Hi := High(A);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if A[Mid] = V then Exit(True);
    if A[Mid] < V then Lo := Mid + 1 else Hi := Mid - 1;
  end;
end;

function SilentBinaryUp(const A: TArray<Integer>; V: Integer): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := High(A);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if A[Mid] <= V then Lo := Mid else Hi := Mid - 1;
  end;
  Result := Lo;
end;

{ H2: insertion sort, the hole walks down from i - 1 (Trace.Anchor:773) }
procedure SilentInsertion(var A: TArray<Integer>);
var
  I, J, T: Integer;
begin
  for I := 1 to High(A) do
  begin
    T := A[I];
    J := I - 1;
    while (J >= 0) and (A[J] > T) do
    begin
      A[J + 1] := A[J];
      Dec(J);
    end;
    A[J + 1] := T;
  end;
end;

{ H3: the start index was read already (XCONST:505) }
function SilentPrior(const A: TArray<Integer>): Integer;
var
  I, K: Integer;
begin
  Result := 0;
  for I := 0 to High(A) do
  begin
    if A[I] < 0 then Continue;
    K := I;
    while (K >= 0) and (A[K] > 0) do Dec(K);
    Result := Result + K;
  end;
end;

{ H4: sentinel, the found counter, the test (APP.Support:1272, DataFlow:347) }
function SilentFound(const ASrc: TArray<Integer>; AWant: Integer): Integer;
var
  A: TArray<Integer>;
  I, K: Integer;
begin
  Result := 0;
  A := nil;
  for I := 0 to High(ASrc) do A := A + [ASrc[I] * 2];
  K := -1;
  for I := High(A) downto 0 do
    if A[I] = AWant then
    begin
      K := I;
      Break;
    end;
  if K >= 0 then Result := A[K];
end;

{ H5: look up or append }
var
  GBuckets: TArray<Integer>;

procedure SilentAppend(AKey: Integer);
var
  I, K: Integer;
begin
  K := -1;
  for I := 0 to High(GBuckets) do
    if GBuckets[I] = AKey then
    begin
      K := I;
      Break;
    end;
  if K < 0 then
  begin
    K := Length(GBuckets);
    SetLength(GBuckets, K + 1);
  end;
  Inc(GBuckets[K]);
end;

{ H6: `i + 1 < Length(A)` bounds i (IncludeUses:605) }
function SilentPairScan(const A: TBytes): Integer;
var
  I: Integer;
begin
  I := 0;
  while (I + 1 < Length(A)) and not ((A[I] = 42) and (A[I + 1] = 41)) do Inc(I);
  Result := I;
end;

{ H7: the not-equal half of `<= Length` }
function SilentAtEnd(const A: TBytes): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I <= Length(A) do
  begin
    if (I = Length(A)) or (A[I] = 10) then Inc(Result);
    Inc(I);
  end;
end;

{ H8: the smaller of two lengths (Charts.Text:313) }
function SilentMin(const A, B: TArray<string>): Integer;
var
  N: Integer;
begin
  N := Length(A);
  if Length(B) < N then N := Length(B);
  Result := 0;
  while (Result < N) and SameText(A[Result], B[Result]) do Inc(Result);
  N := Result;
  while (N > 0) and (A[N - 1] = '') do Dec(N);
end;

function SilentMinLocal(const A, B: TArray<string>): Integer;
var
  N, K: Integer;
begin
  N := Length(A);
  if Length(B) < N then N := Length(B);
  K := 0;
  while (K < N) and SameText(A[K], B[K]) do Inc(K);
  Result := K;
end;

{ H9: an index list the routine filled itself (CLI.Wiki:404), a work queue (Analysis.DataFlow:416) }
function SilentIndexList(const A: TArray<string>): string;
var
  Order: TArray<Integer>;
  I: Integer;
begin
  Order := nil;
  for I := 0 to High(A) do
    if A[I] <> '' then Order := Order + [I];
  TArray.Sort<Integer>(Order);
  for I in Order do Result := Result + A[I];
end;

procedure SilentQueue(const A: TArray<Integer>);
var
  Work: TQueue<Integer>;
  B, I: Integer;
begin
  Work := TQueue<Integer>.Create;
  try
    for I := 0 to High(A) do Work.Enqueue(I);
    while Work.Count > 0 do
    begin
      B := Work.Dequeue;
      if A[B] > 0 then Work.Enqueue(B);
    end;
  finally
    Work.Free;
  end;
end;

{ P1: arrays that grow and shrink together (PurityStage, CLI:10081, LSP.Server:4610) }
function SilentTwins(const ASrc: TArray<string>): string;
var
  Names, Values: TArray<string>;
  I: Integer;
  S: string;
begin
  Names := nil;
  Values := nil;
  for S in ASrc do
  begin
    if S = '' then Continue;
    Names := Names + [S];
    Values := Values + [UpperCase(S)];
  end;
  Result := '';
  for I := 0 to High(Names) do Result := Result + Names[I] + Values[I];
end;

{ P2: the rows of an edit distance: one size, swapped whole (Fuzzy:90) }
function SilentRows(const A, B: string): Integer;
var
  Prev, Cur, Swap: TArray<Integer>;
  I, J: Integer;
begin
  SetLength(Prev, Length(B) + 1);
  SetLength(Cur, Length(B) + 1);
  for J := 0 to Length(B) do Prev[J] := J;
  for I := 1 to Length(A) do
  begin
    Cur[0] := I;
    for J := 1 to Length(B) do Cur[J] := Prev[J] + Ord(A[I] <> B[J]);
    Swap := Prev;
    Prev := Cur;
    Cur := Swap;
  end;
  Result := Prev[Length(B)];
end;

{ P3: made as long as the other one first (DataFlowFacts:1609) }
procedure SilentEnsure(const AOld: TArray<Boolean>; var AMask: TArray<Boolean>);
var
  I: Integer;
begin
  if Length(AOld) > Length(AMask) then SetLength(AMask, Length(AOld));
  for I := 0 to High(AOld) do AMask[I] := AMask[I] or AOld[I];
end;

{ P4: a copy, and one append per trip (MenuTree:2320, Fix.Stmt:1472) }
function SilentCopy(const AArgs: TArray<Integer>): Integer;
var
  One: TArray<Integer>;
  I: Integer;
begin
  Result := 0;
  One := Copy(AArgs);
  for I := 0 to High(AArgs) do
    Inc(Result, One[I]);
end;

function SilentMapped(const AArgs: TArray<Integer>): string;
var
  Txt: TArray<string>;
  A, I: Integer;
begin
  Result := '';
  Txt := nil;
  for A in AArgs do
  begin
    if A < 0 then Exit;
    Txt := Txt + [IntToStr(A)];
  end;
  for I := High(AArgs) downto 0 do Result := Result + Txt[I];
end;

{ P5: the equal-length test held in a Boolean (ConvertApply:525) }
function SilentSame(const A, B: TArray<string>): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
    if not SameText(A[I], B[I]) then Exit(False);
end;

{ P6: a local that holds the one size of both (ClassMetrics:720) }
function SilentSizeLocal(const ASrc: TArray<Integer>): Integer;
var
  Picked, Marks: TArray<Integer>;
  I, N: Integer;
begin
  Picked := nil;
  for I in ASrc do
    if I > 0 then Picked := Picked + [I];
  N := Length(Picked);
  SetLength(Marks, N);
  Result := 0;
  for I := 0 to N - 1 do Marks[I] := Picked[I];
  for I := 0 to N - 1 do Inc(Result, Marks[I]);
end;

{ R1: every caller of a private method passes a valid index (PurityStage:682) }
function TBox.ItemAt(AIdx: Integer): Integer;
begin
  Result := FItems[AIdx];
end;

function TBox.Sum: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FItems) do Inc(Result, ItemAt(I));
end;

{ P7: fields appended side by side in one method, read in another }
procedure TBox.AddBoth(const AName: string);
begin
  FNames := FNames + [AName];
  FMarks := FMarks + [0];
end;

function TBox.Show: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FNames) do
    if FNames[I] <> '' then Inc(Result, FMarks[I]);
end;

{ R2: what a local function returns (Doc.Document:745) }
procedure FindClose(const A: TArray<string>; AFrom: Integer; out AClose: Integer);
begin
  AClose := -1;
  for var K := 0 to High(A) do
    if A[K] = ')' then AClose := K;
end;

function SilentOutArg(const A: TArray<string>): string;
var
  C, I: Integer;
begin
  Result := '';
  FindClose(A, 1, C);
  I := C + 1;
  while I <= High(A) do
  begin
    Result := Result + A[I];
    Inc(I);
  end;
end;

{ U1: an unsigned counter (MCP.Server:825) }
procedure SilentUnsigned(const A: TBytes);
var
  Done: Cardinal;
begin
  Done := 0;
  while Done < Cardinal(Length(A)) do
  begin
    if A[Done] = 0 then Exit;
    Inc(Done, 2);
  end;
end;

{ U2: a read of at most SizeOf - 1 bytes (Plugin.LiveDiagnostics:731) }
procedure SilentReadCap(AReader: TStream);
var
  Chunk: array[0..255] of AnsiChar;
  N: Integer;
begin
  repeat
    N := AReader.Read(Chunk[0], SizeOf(Chunk) - 1);
    if N <= 0 then Break;
    Chunk[N] := #0;
  until False;
end;

{ ---- controls: each must keep firing ---- }

function CtlBinaryBound(const A: TArray<Integer>; V: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  Lo := 0;
  Hi := Length(A);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if A[Mid] = V then Exit(True);
    if A[Mid] < V then Lo := Mid + 1 else Hi := Mid - 1;
  end;
end;

function CtlDownFromLength(const A: TArray<Integer>): Integer;
var
  J: Integer;
begin
  J := Length(A);
  while (J >= 0) and (A[J] > 0) do Dec(J);
  Result := J;
end;

procedure CtlInsertionUp(var A: TArray<Integer>);
var
  I, J: Integer;
begin
  for I := 0 to High(A) do
  begin
    J := I + 1;
    while (J >= 0) and (A[J] > 0) do Dec(J);
  end;
end;

function CtlPriorMoved(const A: TArray<Integer>): Integer;
var
  I, K: Integer;
begin
  Result := 0;
  for I := 0 to High(A) do
  begin
    if A[I] < 0 then Continue;
    K := I;
    Inc(K);
    Result := Result + A[K];
  end;
end;

function CtlPriorBranch(const A: TArray<Integer>; ATest: Boolean): Integer;
var
  K: Integer;
begin
  Result := 0;
  K := Outside(1);
  if ATest then Result := A[K];
  Inc(K);
  Result := Result + A[K];
end;

function CtlFoundNoTest(const A: TArray<Integer>; AWant: Integer): Integer;
var
  I, K: Integer;
begin
  K := -1;
  for I := 0 to High(A) do
    if A[I] = AWant then K := I;
  Result := A[K];
end;

procedure CtlAppendForgot(AKey: Integer);
var
  I, K: Integer;
begin
  K := -1;
  for I := 0 to High(GBuckets) do
    if GBuckets[I] = AKey then K := I;
  if K < 0 then K := Length(GBuckets);
  Inc(GBuckets[K]);
end;

function CtlPairScanWide(const A: TBytes): Integer;
var
  I: Integer;
begin
  I := 0;
  while (I - 1 < Length(A)) and (A[I] <> 42) do Inc(I);
  Result := I;
end;

function CtlMax(const A, B: TArray<string>): Integer;
var
  N, K: Integer;
begin
  N := Length(A);
  if Length(B) > N then N := Length(B);
  K := 0;
  while (K < N) and (A[K] <> '') do Inc(K);
  Result := K;
end;

function CtlIndexList(const A: TArray<string>): string;
var
  Order: TArray<Integer>;
  I: Integer;
begin
  Order := nil;
  for I := 0 to High(A) do
    if A[I] <> '' then Order := Order + [I + 1];
  for I in Order do Result := Result + A[I];
end;

function CtlTwins(const ASrc: TArray<string>): string;
var
  Names, Values: TArray<string>;
  I: Integer;
  S: string;
begin
  Names := nil;
  Values := nil;
  for S in ASrc do
  begin
    Names := Names + [S];
    if S = '' then Continue;
    Values := Values + [UpperCase(S)];
  end;
  Result := '';
  for I := 0 to High(Names) do Result := Result + Values[I];
end;

function CtlTwinsTrimmed(const ASrc: TArray<string>): string;
var
  Names, Values: TArray<string>;
  I: Integer;
  S: string;
begin
  Names := nil;
  Values := nil;
  for S in ASrc do
  begin
    Names := Names + [S];
    Values := Values + [UpperCase(S)];
  end;
  if Length(Values) > 3 then SetLength(Values, 3);
  Result := '';
  for I := 0 to High(Names) do Result := Result + Values[I];
end;

function CtlRows(const A, B: string): Integer;
var
  Prev, Cur: TArray<Integer>;
  J: Integer;
begin
  Result := 0;
  SetLength(Prev, Length(B));
  SetLength(Cur, Length(B));
  for J := 0 to Length(A) do
  begin
    Prev[J] := J;
    Prev := Copy(Cur);
  end;
end;

procedure CtlEnsureWrongWay(const AOld: TArray<Boolean>; var AMask: TArray<Boolean>);
var
  I: Integer;
begin
  if Length(AMask) < 8 then SetLength(AMask, 8);
  for I := 0 to High(AOld) do AMask[I] := AMask[I] or AOld[I];
end;

function CtlMapped(const AArgs: TArray<Integer>): string;
var
  Txt: TArray<string>;
  A, I: Integer;
begin
  Result := '';
  Txt := nil;
  for A in AArgs do
  begin
    if A < 0 then Continue;
    Txt := Txt + [IntToStr(A)];
  end;
  for I := High(AArgs) downto 0 do Result := Result + Txt[I];
end;

function CtlSame(const A, B: TArray<string>): Boolean;
var
  I: Integer;
begin
  Result := Length(A) > 0;
  if not Result then Exit;
  for I := 0 to High(A) do
    if not SameText(A[I], B[I]) then Exit(False);
end;

function TBox.CtlItemAt(AIdx: Integer): Integer;
begin
  Result := FItems[AIdx];
end;

function TBox.CtlSum(AFrom: Integer): Integer;
begin
  Result := CtlItemAt(AFrom);
end;

function TBox.CtlPublic(AIdx: Integer): Integer;
begin
  Result := FItems[AIdx];
end;

procedure CtlFindClose(const A: TArray<string>; out AClose: Integer);
begin
  AClose := -3;
  for var K := 0 to High(A) do
    if A[K] = ')' then AClose := K + 1;
end;

function CtlOutArg(const A: TArray<string>): string;
var
  C, I: Integer;
begin
  Result := '';
  CtlFindClose(A, C);
  I := C + 1;
  while I <= High(A) do
  begin
    Result := Result + A[I];
    Inc(I);
  end;
end;

procedure CtlReadWhole(AReader: TStream);
var
  Chunk: array[0..255] of AnsiChar;
  N: Integer;
begin
  N := AReader.Read(Chunk[0], SizeOf(Chunk));
  if N <= 0 then Exit;
  Chunk[N] := #0;
end;

function CtlShrunk(const ASrc: TArray<Integer>): Integer;
var
  A: TArray<Integer>;
  K: Integer;
begin
  A := Copy(ASrc);
  K := Outside(2);
  if (K < 0) or (K > High(A)) then Exit(0);
  Result := A[K];
  SetLength(A, K);
  K := K + 0;
  Result := Result + A[K];
end;

{ ---- second part: the smaller classes ---- }

type
  TGrid = class
  strict private
    FCount: Integer;
    FSeen: TArray<Boolean>;
    FRows: TArray<string>;
    FFlags: TArray<Boolean>;
    procedure Mark(AIdx: Integer);
    procedure CtlMark(AIdx: Integer);
  public
    constructor Create(ACount: Integer);
    procedure Load(const ARows: TArray<string>);
    procedure MarkAll;
    procedure CtlMarkAll;
    function ShowFlags: Integer;
  end;

constructor TGrid.Create(ACount: Integer);
begin
  FCount := ACount;
  SetLength(FSeen, FCount);
end;

procedure TGrid.Load(const ARows: TArray<string>);
begin
  FRows := ARows;
  SetLength(FFlags, Length(FRows));
end;

{ S1: a size field the file assigns once (ArchDiagram:382) }
procedure TGrid.Mark(AIdx: Integer);
begin
  FSeen[AIdx] := True;
end;

procedure TGrid.MarkAll;
begin
  for var I := 0 to FCount - 1 do Mark(I);
end;

procedure TGrid.CtlMark(AIdx: Integer);
begin
  FSeen[AIdx] := True;
end;

procedure TGrid.CtlMarkAll;
begin
  for var I := 0 to FCount do CtlMark(I);
end;

{ S2: a field sized once, from the other field's one value (PurityStage:1168) }
function TGrid.ShowFlags: Integer;
begin
  Result := 0;
  for var I := 0 to High(FRows) do
    if FFlags[I] then Inc(Result);
end;

{ S3: a Boolean function of this file is the guard (CallResolver:11969) }
function InsideArr(const A: TArray<string>; AIdx: Integer): Boolean;
begin
  Result := (AIdx >= 0) and (AIdx <= High(A)) and (A[AIdx] <> '');
end;

function SilentPredicate(const A: TArray<string>): string;
var
  J: Integer;
begin
  Result := '';
  J := Outside(3);
  while InsideArr(A, J) do
  begin
    Result := Result + A[J];
    Inc(J);
  end;
end;

function CtlOneSidedPredicate(const A: TArray<string>; AIdx: Integer): Boolean;
begin
  Result := (AIdx <= High(A)) or (AIdx < 0);
end;

function CtlPredicate(const A: TArray<string>): string;
var
  J: Integer;
begin
  Result := '';
  J := Outside(4);
  while CtlOneSidedPredicate(A, J) do
  begin
    Result := Result + A[J];
    Inc(J);
  end;
end;

{ S4: one start value, one finding: the second read of a down-scan (DeadCodeChecks:376) }
function CtlOneStart(const A: TBytes): Boolean;
var
  P: Integer;
begin
  P := Outside(5);
  while (P >= 0) and (A[P] = 32) do Dec(P);
  if (P < 0) or (A[P] <> 62) then Exit(False);
  Result := True;
end;

function CtlOneStartRaised(const A: TBytes): Boolean;
var
  P: Integer;
begin
  P := Outside(6);
  while (P >= 0) and (A[P] = 32) do Dec(P);
  Inc(P, 2);
  if (P < 0) or (A[P] <> 62) then Exit(False);
  Result := True;
end;

{ S5: the else of `Length(A) <> Length(B)` (ParityExtChecks:331) }
function SilentElseEqual(const A, B: TArray<string>): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Length(A) <> Length(B) then
    Result := False
  else
    for I := 0 to High(B) do
      if not SameText(A[I], B[I]) then Result := False;
end;

function CtlThenUnequal(const A, B: TArray<string>): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Length(A) <> Length(B) then
    for I := 0 to High(B) do
      if not SameText(A[I], B[I]) then Result := False;
end;

{ S6: the last element just appended, the other array made as long (CLI:4618) }
function SilentLastAppended(const ASrc: TArray<string>): Integer;
var
  Names: TArray<string>;
  Counts: TArray<Integer>;
  Found, I: Integer;
  S: string;
begin
  Names := nil;
  Counts := nil;
  for S in ASrc do
  begin
    Found := -1;
    for I := 0 to High(Names) do
      if (Found < 0) and SameText(Names[I], S) then Found := I;
    if Found < 0 then
    begin
      Names := Names + [S];
      SetLength(Counts, Length(Names));
      Found := High(Names);
    end;
    Counts[Found] := Counts[Found] + 1;
  end;
  Result := Length(Counts);
end;

{ S7: `if E < 0 then 0 else E` (Core.Indexer:2033) }
function SilentChosen(const A: TArray<Integer>; const ASpan: TPair<Integer, Integer>): Integer;
var
  L: Integer;
begin
  Result := 0;
  L := if ASpan.Key < 0 then 0 else ASpan.Key;
  while L <= High(A) do
  begin
    Inc(Result, A[L]);
    Inc(L);
  end;
end;

function CtlChosen(const A: TArray<Integer>; const ASpan: TPair<Integer, Integer>): Integer;
var
  L: Integer;
begin
  Result := 0;
  L := if ASpan.Key > 0 then 0 else ASpan.Key;
  while L <= High(A) do
  begin
    Inc(Result, A[L]);
    Inc(L);
  end;
end;

{ S8: a retry that leaves when it finds nothing either (XCONST:770) }
function SilentRetry(const A: TArray<string>): string;
var
  I, K: Integer;
begin
  Result := '';
  K := -1;
  for I := 0 to High(A) do
    if A[I] = 'x' then K := I;
  if K < 0 then
  begin
    for I := 0 to High(A) do
      if A[I] = 'y' then K := I;
    if K < 0 then Exit;
  end;
  Result := A[K];
end;

function CtlRetry(const A: TArray<string>): string;
var
  I, K: Integer;
begin
  Result := '';
  K := -1;
  for I := 0 to High(A) do
    if A[I] = 'x' then K := I;
  if K < 0 then
    for I := 0 to High(A) do
      if A[I] = 'y' then K := I;
  Result := A[K];
end;

{ S9: lengths copied from two arrays found equal (SharedFacts:958) }
function SilentEqualCopies(const A, B: TArray<string>): Boolean;
var
  NA, NB: TArray<string>;
  I: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  SetLength(NA, Length(A));
  SetLength(NB, Length(B));
  for I := 0 to High(A) do NA[I] := UpperCase(A[I]);
  for I := 0 to High(B) do NB[I] := UpperCase(B[I]);
  for I := 0 to High(NA) do
    if NA[I] <> NB[I] then Exit(False);
  Result := True;
end;

{ S10: the result of a local function (the caller excludes its not-found value) }
function FirstEmpty(const A: TArray<string>): Integer;
begin
  Result := -1;
  for var I := 0 to High(A) do
    if A[I] = '' then Exit(I);
end;

function SilentNext(const A: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  I := FirstEmpty(A) + 1;
  while I <= High(A) do
  begin
    Result := Result + A[I];
    Inc(I);
  end;
end;

function CtlNext(const A: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  I := FirstEmpty(A);
  while I <= High(A) do
  begin
    Result := Result + A[I];
    Inc(I);
  end;
end;

end.
