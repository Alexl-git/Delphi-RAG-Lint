unit uParenlessUse;

{ Fixture for run_parenless_call_bind.ps1. Every line the guard asserts on
  carries a POS-* or NEG-* marker, and the guard reads the line numbers from
  those markers -- never hard-codes them.

  POS-* : a parameterless function or method called WITHOUT parentheses in an
          expression. The parser records these as `read` refs; each must own
          exactly one call_edges row to the named routine.
  NEG-* : a `read` ref spelled like a parameterless routine that is NOT a call
          to it -- a nearer declaration shadows it, the source takes its
          address, the target is procedural, the candidate needs arguments, or
          a `with` may supply the name. Each must stay unbound. }

interface

uses
  uParenlessLib;

type
  TCounter = class
  private
    FTicks: Integer;
    function GetTotal: Integer;
  public
    function Tick: Integer;
    procedure Run;
    property Total: Integer read GetTotal;
  end;

  THolder = class
  public
    NextId: Integer;
    procedure UseField;
  end;

  TPropHolder = class
  private
    function GetNextId: Integer;
  public
    procedure UseProp;
    property NextId: Integer read GetNextId;
  end;

procedure Driver;
procedure ShadowByLocal;
procedure ShadowByProcVar;
procedure ProcValues;
procedure Overloads;
procedure WithScope(AHolder: THolder);
function Nested: Integer;

implementation

procedure Consume(A: Integer);
begin
  if A < 0 then
    GNext := A;
end;

procedure Driver;
var
  N: Integer;
begin
  Assert(NextId > 0); // POS-ASSERT
  N := NextId; // POS-ASSIGN
  Consume(NextId); // POS-ARG
  NextId; // POS-STMT
  Consume(N);
end;

procedure ShadowByLocal;
var
  NextId: Integer;
begin
  NextId := 1;
  Consume(NextId); // NEG-LOCAL
end;

procedure ShadowByProcVar;
var
  NextId: TIdFunc;
  N: Integer;
begin
  NextId := nil;
  N := NextId; // NEG-PROCTYPED-VAR
  Consume(N);
end;

procedure ProcValues;
var
  P: TIdFunc;
  K: TKeyFunc;
  Q: Pointer;
begin
  P := NextId; // NEG-PROCVAR
  Q := @NextId; // NEG-ADDR
  RegisterGen(NextId); // NEG-PROCARG
  K := NextKey; // NEG-PARAMS
  if Assigned(P) and Assigned(K) and (Q <> nil) then
    Consume(0);
end;

procedure Overloads;
var
  N: Integer;
begin
  N := Pick + 1; // NEG-OVERLOAD
  Consume(N);
end;

procedure WithScope(AHolder: THolder);
begin
  with AHolder do
    Consume(NextId); // NEG-WITH
end;

function Nested: Integer;

  function Local: Integer;
  begin
    Result := 2;
  end;

begin
  Result := Local * 2; // POS-NESTED
end;

function TCounter.GetTotal: Integer;
begin
  Result := FTicks;
end;

function TCounter.Tick: Integer;
begin
  Inc(FTicks);
  Result := FTicks;
end;

procedure TCounter.Run;
var
  N: Integer;
begin
  N := Tick; // POS-METHOD
  N := Self.Tick + N; // POS-SELF
  N := Total + N; // NEG-PROPERTY
  Consume(N);
end;

procedure THolder.UseField;
begin
  Consume(NextId); // NEG-FIELD
end;

function TPropHolder.GetNextId: Integer;
begin
  Result := 7;
end;

procedure TPropHolder.UseProp;
begin
  Consume(NextId); // NEG-PROPGETTER
end;

end.