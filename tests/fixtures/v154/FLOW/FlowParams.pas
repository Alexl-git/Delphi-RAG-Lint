unit FlowParams;

// var-param-never-written (G-18) and value-param-assigned (G-19)

interface

uses
  FlowOther;

type
  TRec = record
    X: Integer;
    procedure Clear;
  end;
  TBase = class
  public
    procedure Virt(var A: Integer); virtual;
    procedure Click(Sender: TObject; var Action: Integer);
    procedure Notify(var A: Integer);
  end;
  TImpl = class(TInterfacedObject, ICheck)
  public
    function Allowed(A: Integer): Boolean;
    procedure Adjust(var A: Integer);
  end;
  TLeaf = class(TBase)
  public
    procedure Virt(var A: Integer); override;
    procedure Own(var A: Integer);
    procedure WinMsg(var A: Integer); message 1024;
  end;

procedure ReadOnly(var A: Integer);
procedure ReadRec(var R: TRec);
procedure ReadObject(var B: TBase);
procedure PassesByValue(var A: Integer);
procedure CallsMethod(var R: TRec);
procedure Writes(var A: Integer);
procedure WritesPart(var R: TRec);
procedure PassesOn(var A: Integer);
procedure TakesAddr(var A: Integer);
procedure Untyped(var A);
procedure Unused(var A: Integer);
procedure Incs(var A: Integer);
procedure Loops(var A: Integer);
procedure WithIt(var R: TRec);
procedure ValueSet(N: Integer);
procedure ValueInc(N: Integer);
procedure ValueText(S: string);
procedure ValueFor(I: Integer);
procedure ValueRead(N: Integer);
procedure VarSet(var N: Integer; out M: Integer);
procedure Shadowed(N: Integer);
procedure Hook;
procedure ViaNested(var A: Integer);
procedure ValueField(R: TRec);

implementation

var
  GTotal: Integer;

procedure Show(N: Integer);
begin
  GTotal := GTotal + N;
end;

procedure ReadOnly(var A: Integer); // FIRE var-param-never-written
begin
  GTotal := A + 1;
end;

procedure ReadRec(var R: TRec); // FIRE var-param-never-written
begin
  GTotal := R.X;
end;

procedure ReadObject(var B: TBase); // FIRE var-param-never-written
begin
  B.Virt(GTotal);
  if B <> nil then GTotal := 2;
end;

procedure PassesByValue(var A: Integer); // FIRE var-param-never-written
begin
  Show(A);
end;

procedure CallsMethod(var R: TRec);
begin
  R.Clear;
end;

procedure Writes(var A: Integer);
begin
  A := A + 1;
end;

procedure WritesPart(var R: TRec);
begin
  R.X := 1;
end;

procedure PassesOn(var A: Integer);
begin
  Writes(A);
end;

procedure TakesAddr(var A: Integer);
var
  P: PInteger;
begin
  P := @A;
  P^ := 1;
end;

procedure Untyped(var A);
begin
  GTotal := Integer(A);
end;

procedure Unused(var A: Integer);
begin
  GTotal := 0;
end;

procedure Incs(var A: Integer);
begin
  Inc(A);
end;

procedure Loops(var A: Integer);
begin
  ReadLn(A);
end;

procedure WithIt(var R: TRec);
begin
  with R do
    X := 1;
end;

procedure ViaNested(var A: Integer);

  procedure Inner;
  begin
    A := 1;
  end;

begin
  Inner;
  GTotal := A;
end;

procedure ValueSet(N: Integer);
begin
  N := N + 1; // FIRE value-param-assigned
  N := N * 2;
  GTotal := N;
end;

procedure ValueInc(N: Integer);
begin
  Inc(N); // FIRE value-param-assigned
  GTotal := N;
end;

procedure ValueText(S: string);
begin
  if S = '' then S := 'none'; // FIRE value-param-assigned
  GTotal := Length(S);
end;

procedure ValueFor(I: Integer);
var
  K: Integer;
begin
  for K := 1 to 3 do
    Dec(I, K); // FIRE value-param-assigned
  GTotal := I;
end;

procedure ValueRead(N: Integer);
var
  M: Integer;
begin
  M := N;
  M := M + 1;
  GTotal := M;
end;

procedure ValueField(R: TRec);
begin
  R.X := 1;
  GTotal := R.X;
end;

procedure VarSet(var N: Integer; out M: Integer);
begin
  N := 1;
  M := 2;
end;

procedure Shadowed(N: Integer);

  procedure Inner;
  var
    N: Integer;
  begin
    N := 1;
    GTotal := N;
  end;

begin
  Inner;
  GTotal := N;
end;

procedure TRec.Clear;
begin
  X := 0;
end;

procedure TBase.Virt(var A: Integer);
begin
  GTotal := A;
end;

procedure TBase.Click(Sender: TObject; var Action: Integer);
begin
  GTotal := Action;
end;

procedure TBase.Notify(var A: Integer);
begin
  GTotal := A;
end;

function TImpl.Allowed(A: Integer): Boolean;
begin
  Result := A > 0;
end;

procedure TImpl.Adjust(var A: Integer);
begin
  GTotal := A;
end;

procedure TLeaf.Virt(var A: Integer);
begin
  GTotal := A;
end;

procedure TLeaf.Own(var A: Integer); // FIRE var-param-never-written
begin
  GTotal := A;
end;

procedure TLeaf.WinMsg(var A: Integer);
begin
  GTotal := A;
end;

procedure Hook;
var
  B: TBase;
  N: TNotify;
begin
  B := TBase.Create;
  try
    N := B.Notify;
    if Assigned(N) then GTotal := 1;
  finally
    B.Free;
  end;
end;

end.