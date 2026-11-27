unit uExtB1;

{ drag-lint 1.56 lane EXT-B1 (B3) fixture: data flows of numeric / Boolean / date-time values.
  Read by tests\autotest\run_v156_EXTB1_valclass.ps1, which finds lines by the M-... markers.
  Index-only: the unit is parsed, never compiled. 7-bit ASCII, CRLF. }

interface

type
  TFieldStub = class
  public
    AsFloat   : Double;
    AsCurrency: Currency;
    AsString  : string;
  end;

  TDataSetStub = class
  public
    A, B, T, Amount: TFieldStub;
    Eof: Boolean;
    procedure Next;
  end;

  { lane EXT-B1F: fields, a unit variable and function results of DECLARED scalar type }
  TOrderStub = class
  private
    FQty  : Integer;
    FTotal: Currency;
    FName : string;
    FCode : Integer;
  public
    procedure SetQty(pQty: Integer);
    function Total: Currency;
    procedure Recalc;
    procedure Describe;
    procedure Ambiguous;
  end;

  { the same field name with another type in another class: each FCode has the class of its owner }
  TOtherStub = class
  private
    FCode: string;
  end;

var
  GLastTotal: Currency;
  GLastName : string;

procedure SinkI(N: Integer);
procedure SinkD(D: TDateTime);
procedure SinkS(const S: string);
function Twice(pN: Integer): Integer;

implementation

procedure SinkI(N: Integer);
begin
end;

procedure SinkD(D: TDateTime);
begin
end;

procedure SinkS(const S: string);
begin
end;

procedure TDataSetStub.Next;
begin
end;

{ an Integer parameter reaches a call argument }
procedure IntArg(N: Integer);
begin
  SinkI(N); { M-INT }
end;

{ a TDateTime parameter reaches a call argument }
procedure StampArg(D: TDateTime);
begin
  SinkD(D); { M-DATE }
end;

{ SPEC-LIN B14-4: two field reads multiplied into a Double local, written to a third field }
procedure FloatMul(Q, M: TDataSetStub);
var
  d: Double;
begin
  d := Q.A.AsFloat * Q.B.AsFloat; { M-MUL-SRC }
  M.T.AsFloat := d; { M-MUL-DST }
end;

{ a comparison of a string is a Boolean value derived from it }
function IsBlank(const S: string): Boolean;
begin
  Result := S = ''; { M-BOOL }
end;

{ Length() is an integer derived from its argument }
function LenOf(const S: string): Integer;
begin
  Result := Length(S); { M-LEN }
end;

{ SPEC-LIN B14-4: v := v + <field read> inside a loop }
function SumUp(Q: TDataSetStub): Currency;
var
  Total: Currency;
begin
  Total := 0;
  while not Q.Eof do
  begin
    Total := Total + Q.Amount.AsCurrency; { M-ACC }
    Q.Next;
  end;
  Result := Total; { M-ACC-RES }
end;

{ Inc(X, D): X receives D }
function CountUp(Step: Integer): Integer;
var
  Cnt: Integer;
begin
  Cnt := 0;
  Inc(Cnt, Step); { M-INC }
  Result := Cnt;
end;

{ a string and an integer reach one sink: the string row keeps val_class '', the integer row is new }
procedure Mixed(const Name: string; N: Integer);
var
  S: string;
begin
  S := Name + IntToStr(N);
  SinkS(S); { M-MIXED }
end;

{ a var argument of Integer type: the argout source is a value row now }
procedure ParseIt(const S: string);
var
  N: Integer;
begin
  if TryStrToInt(S, N) then { M-TRY }
    SinkI(N); { M-TRY-SINK }
end;

{ NEGATIVE: a pure string routine gains no value row }
function Plain(const S: string): string;
begin
  Result := Trim(S); { M-PLAIN }
end;

{ the kill is still flow-sensitive for a scalar local }
procedure KillInt(A, B: Integer);
var
  X: Integer;
begin
  X := A;
  X := B;
  SinkI(X); { M-KILL }
end;

{ hook seam (run with DRAGLINT_TEST_V156_DFHOOK=1): statement, expression and write hooks }
procedure Hooked(Q, M: TDataSetStub; const Msg: string);
var
  d: Double;
begin
  d := Q.A.AsFloat; { M-HOOK-READ }
  M.T.AsFloat := d; { M-HOOK-WRITE }
  if d < 0 then
    raise EHookStub.Create(Msg); { M-HOOK-RAISE }
end;

{ ---- lane EXT-B1F: a source of DECLARED scalar type keeps its pre-1.56 row and gains a value row ---- }

function Twice(pN: Integer): Integer;
begin
  Result := pN * 2;
end;

procedure TOrderStub.SetQty(pQty: Integer);
begin
  FQty := pQty;
end;

function TOrderStub.Total: Currency;
begin
  Result := FTotal;
end;

{ (a) a Currency field assigned to a unit variable; NEGATIVE: the string pair gains nothing }
procedure TOrderStub.Recalc;
begin
  GLastTotal := FTotal; { M-F-GLOBAL }
  GLastName := FName; { M-F-GLOBAL-STR }
end;

{ (b) an Integer field as a direct argument }
procedure TOrderStub.Describe;
begin
  SinkS(IntToStr(FQty)); { M-F-ARG }
end;

{ FCode is Integer here and string in TOtherStub -- the lookup is by scope: int is claimed here }
procedure TOrderStub.Ambiguous;
begin
  SinkI(FCode); { M-F-AMBIG }
end;

{ (c) the result of a function this unit declares, passed as an argument }
procedure Feed(pOrder: TOrderStub; pCount: Integer);
begin
  pOrder.SetQty(Twice(pCount)); { M-F-FUNC }
end;

{ (d) a method called without parentheses: the source is its result, not only the object }
procedure Report(pOrder: TOrderStub);
begin
  GLastTotal := pOrder.Total; { M-F-NOPAREN }
end;

{ a member this unit does not declare, written to a Currency unit variable: the object is the
  source of a currency value }
procedure Untyped(pOrder: TOrderStub);
begin
  GLastTotal := pOrder.Extra; { M-F-DST }
end;

end.
