unit FlowResult;

// managed-result-read-first (G-08)

interface

uses
  System.SysUtils;

type
  INode = interface
    procedure Touch;
  end;
  TNames = array of string;
  TColor3 = (clRed3, clGreen3);
  TPair2 = record
    Name: string;
  end;

function Append(const S: string): string;
function Grow(const A: TArray<Integer>): TArray<Integer>;
function OnePath(B: Boolean): string;
function Looped(N: Integer): string;
function GrowAlias(N: Integer): TNames;
function Walked(const N: INode): INode;
function Padded(N: Integer): string;
function SetFirst(const S: string): string;
function SetBoth(B: Boolean): string;
function Sized(N: Integer): TArray<Integer>;
function Filled: string;
function ByOut: string;
function Rec(const S: string): TPair2;
function Nested(const S: string): string;
function Num(N: Integer): Integer;
function ShortText(const S: string): ShortString;
function ByName(const S: string): string;
function Exits(const S: string): string;
function Guarded(B: Boolean): string;
function Raised(B: Boolean): string;
function Counted(N: Integer): string;
function NoInit(N: Integer): TArray<string>;
function Segments(const A: TArray<Integer>): TArray<string>;
function Published(const A: TArray<string>): TArray<string>;
function ShellText(N: Integer; P: PChar): string;
function Binding(const N: INode): INode;
function Stems(const A: TArray<string>): TArray<string>;
function AfterBranch(B: Boolean; N: Integer): string;
function ByIndex(const S: TArray<string>): string;
function ByFlag(const S: TArray<string>): string;
function ByFound(const S: TArray<string>): string;
function ElseRaises(N: Integer): string;
function CaseRaises(N: Integer): string;
function FarRaises(N: Integer): string;
function ExitsFirst(N: Integer): string;
function TwoIfs(N: Integer): string;
function AllColors(C: TColor3): string;
function TriedFirst(const S: string): string;
function InLoop(const S: TArray<string>): string;
function ShortCut(B, C: Boolean): string;
function NotAlways(N: Integer): string;

implementation

procedure Fill(out S: string);
begin
  S := 'x';
end;

procedure RaiseBad;
begin
  raise Exception.Create('bad');
end;

procedure RaiseEither(N: Integer);
begin
  if N > 1 then raise Exception.Create('many')
  else RaiseBad;
end;

procedure RaiseSome(N: Integer);
begin
  if N > 1 then raise Exception.Create('many');
end;

function Append(const S: string): string;
begin
  Result := Result + S; // FIRE managed-result-read-first
end;

function Grow(const A: TArray<Integer>): TArray<Integer>;
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Result := Result + [A[I]]; // FIRE managed-result-read-first
end;

function OnePath(B: Boolean): string;
begin
  if B then Result := 'x';
  Result := Result + 'y'; // FIRE managed-result-read-first
end;

function Looped(N: Integer): string;
var
  I: Integer;
begin
  for I := 1 to N do
  begin
    if I > 1 then Result := Result + ', '; // FIRE managed-result-read-first
    Result := Result + IntToStr(I);
  end;
end;

function GrowAlias(N: Integer): TNames;
begin
  SetLength(Result, Length(Result) + 1); // FIRE managed-result-read-first
  Result[High(Result)] := IntToStr(N);
end;

function Walked(const N: INode): INode;
begin
  if Result = nil then // FIRE managed-result-read-first
    Result := N;
end;

function Padded(N: Integer): string;
begin
  while Length(Result) < N do // FIRE managed-result-read-first
    Result := Result + ' ';
end;

function NoInit(N: Integer): TArray<string>;
begin
  if N > 0 then Exit(Result + ['a']); // FIRE managed-result-read-first
  Result := nil;
end;

function SetFirst(const S: string): string;
begin
  Result := '';
  Result := Result + S;
end;

function SetBoth(B: Boolean): string;
begin
  if B then Result := 'a' else Result := 'b';
  Result := Result + 'c';
end;

function Sized(N: Integer): TArray<Integer>;
begin
  SetLength(Result, N);
  Result[0] := Length(Result);
end;

function Filled: string;
begin
  Fill(Result);
  Result := Result + '!';
end;

function ByOut: string;
begin
  if not TryStrToInt64('1', PInt64(@Result)^) then Exit('');
  Result := Result + '!';
end;

function Rec(const S: string): TPair2;
begin
  Result.Name := Result.Name + S;
end;

function Nested(const S: string): string;

  procedure Add(const T: string);
  begin
    Result := Result + T;
  end;

begin
  Result := '';
  Add(S);
end;

function Num(N: Integer): Integer;
begin
  Result := 0;
  Result := Result + N;
end;

function ShortText(const S: string): ShortString;
begin
  Result := ShortString(S);
  Result := Result + '.';
end;

function ByName(const S: string): string;
begin
  ByName := S;
  Result := Result + '.';
end;

function Exits(const S: string): string;
begin
  if S = '' then Exit('none');
  Result := S;
  if Result = 'x' then Exit;
  Result := Result + '.';
end;

function Guarded(B: Boolean): string;
begin
  if B then Result := 'x';
  if B then Result := Result + 'y';
end;

function Raised(B: Boolean): string;
begin
  if B then Result := 'x'
  else raise Exception.Create('no');
  Result := Result + 'y';
end;

function Counted(N: Integer): string;
begin
  case N of
    1: Result := 'one';
    2: Result := 'two';
  else
    Result := 'many';
  end;
  Result := Result + '.';
end;

// the measured true positives (vcl, drag-lint), in their shapes

function Segments(const A: TArray<Integer>): TArray<string>;
var
  I: Integer;
begin
  if Length(A) < 2 then
    Exit
  else if A[0] = 0 then
    Exit;
  for I := 0 to High(A) do
    if A[I] = 0 then
      Continue
    else
    begin
      SetLength(Result, Length(Result) + 1); // FIRE managed-result-read-first
      Result[Length(Result) - 1] := IntToStr(A[I]);
    end;
end;

function Published(const A: TArray<string>): TArray<string>;
var
  I: Integer;
begin
  for I := 0 to High(A) do
    if A[I] <> '' then
    begin
      SetLength(Result, Length(Result) + 1); // FIRE managed-result-read-first
      Result[Length(Result) - 1] := A[I];
    end;
end;

function ShellText(N: Integer; P: PChar): string;
var
  S: string;
begin
  case N of
    1:
      SetString(Result, P, 1);
    2:
      begin
        Fill(S);
        SetString(Result, P, 2);
      end;
    3:
      if Assigned(P) then
        Result := P
      else
        Result := '';
  end;
  if (Length(Result) > 1) and (Result[1] = '?') then // FIRE managed-result-read-first
    Result := StringReplace(Result, '?', '', [rfReplaceAll]);
end;

function Binding(const N: INode): INode;
var
  H: HRESULT;
begin
  if Assigned(N) then
  begin
    H := N.QueryInterface(INode, Pointer(Result));
    if H <> 0 then
      H := N.QueryInterface(INode, Pointer(Result));
    if H <> 0 then
      N.QueryInterface(INode, Pointer(Result));
  end;
  if not Assigned(Result) then // FIRE managed-result-read-first
    N.QueryInterface(INode, Pointer(Result));
end;

function Stems(const A: TArray<string>): TArray<string>;
var
  S: string;
begin
  if Length(A) = 1 then Exit(A);
  try
    for S in A do
    begin
      if S = '' then Continue;
      if S <> 'x' then
        Result := Result + [S]; // FIRE managed-result-read-first
    end;
  finally
    Fill(S);
  end;
end;

function AfterBranch(B: Boolean; N: Integer): string;
var
  S: string;
begin
  if B then
    Result := 'x'
  else
    Fill(S);
  Result := Result + IntToStr(N); // FIRE managed-result-read-first
end;

// a set and a read that go together

function ByIndex(const S: TArray<string>): string;
var
  I: Integer;
begin
  for I := 0 to High(S) do
    if I = 0 then Result := S[I]
    else Result := Result + ',' + S[I];
end;

function ByFlag(const S: TArray<string>): string;
var
  I: Integer;
  First: Boolean;
begin
  First := True;
  for I := 0 to High(S) do
  begin
    if not First then Result := Result + ',' + S[I]
    else Result := S[I];
    First := False;
  end;
end;

function ByFound(const S: TArray<string>): string;
var
  I: Integer;
  Found: Boolean;
begin
  Found := False;
  for I := 0 to High(S) do
    if S[I] <> '' then
    begin
      Result := S[I];
      Found := True;
    end;
  if Found and (Result <> '') then Exit;
  Result := '';
end;

function ElseRaises(N: Integer): string;
begin
  if N = 1 then Result := 'x'
  else RaiseBad;
  Result := Result + 'y';
end;

function CaseRaises(N: Integer): string;
begin
  case N of
    1: Result := 'x';
  else
    RaiseEither(N);
  end;
  Result := Result + 'y';
end;

function FarRaises(N: Integer): string;
begin
  if N = 1 then Result := 'x'
  else RaiseLastOSError;
  Result := Result + 'y';
end;

function ExitsFirst(N: Integer): string;
begin
  if N = 1 then Result := 'x';
  if N <> 1 then Exit;
  Result := Result + 'y';
end;

function TwoIfs(N: Integer): string;
begin
  if N = 1 then Result := 'x';
  if N <> 1 then Result := 'z';
  Result := Result + 'y';
end;

function AllColors(C: TColor3): string;
begin
  case C of
    clRed3: Result := 'r';
    clGreen3: Result := 'g';
  end;
  Result := Result + 'y';
end;

function TriedFirst(const S: string): string;
begin
  try
    Result := IntToStr(StrToInt(S));
  except
    RaiseSome(2);
  end;
  Result := Result + 'y';
end;

function InLoop(const S: TArray<string>): string;
var
  I: Integer;
begin
  for I := 0 to 2 do
    if S[I] <> '' then Result := S[I];
  Result := Result + 'y';
end;

function ShortCut(B, C: Boolean): string;
begin
  if B then Result := 'x';
  if C and B and (Result <> '') then Exit;
  Result := '';
end;

function NotAlways(N: Integer): string;
begin
  if N = 1 then Result := 'x'
  else RaiseSome(N);
  Result := Result + 'y'; // FIRE managed-result-read-first
end;
end.