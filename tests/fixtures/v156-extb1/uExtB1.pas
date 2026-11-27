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

procedure SinkI(N: Integer);
procedure SinkD(D: TDateTime);
procedure SinkS(const S: string);

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

end.
