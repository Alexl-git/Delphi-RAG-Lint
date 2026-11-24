unit FlowNested;

// address-of-nested-routine (G-17)

interface

type
  TCompare = function(A, B: Pointer): Integer;

procedure Go;
procedure UnitProc;

implementation

procedure Take(P: Pointer);
begin
  if P = nil then UnitProc;
end;

procedure Thunk(P: Pointer; N: Integer);
asm
  NOP
end;

procedure UnitProc;
begin
end;

procedure Go;
var
  P: Pointer;
  F: TCompare;
  Local: Integer;

  function Cmp(A, B: Pointer): Integer;
  begin
    Result := Local;
  end;

  procedure Inner;

    procedure Deep;
    begin
    end;

  begin
    P := @Deep; // FIRE address-of-nested-routine
    Take(@Cmp); // FIRE address-of-nested-routine
  end;

begin
  Local := 1;
  P := @Inner; // FIRE address-of-nested-routine
  F := @Cmp; // FIRE address-of-nested-routine
  Take(Addr(Inner)); // FIRE address-of-nested-routine
  Take(Pointer(@Cmp)); // FIRE address-of-nested-routine
  P := @UnitProc;
  Take(@Local);
  Take(@Go);
  Thunk(@Inner, 1);
  Inner;
  if Assigned(F) then Take(P);
end;

procedure Shadow;

  procedure Inner;
  begin
  end;

  procedure Other(Inner: Integer);
  begin
    Take(@Inner);
  end;

begin
  Inner;
  Other(1);
end;

procedure InLambda;
type
  TRun = reference to procedure;
var
  R: TRun;
begin
  R :=
    procedure

      procedure Deeper;
      begin
      end;

    begin
      Take(@Deeper); // FIRE address-of-nested-routine
    end;
  R();
end;

procedure Sibling;
begin
  Take(@UnitProc);
end;

end.