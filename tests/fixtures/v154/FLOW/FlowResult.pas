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

implementation

procedure Fill(out S: string);
begin
  S := 'x';
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

end.