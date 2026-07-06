unit locals;

interface

type
  TWorker = class
    procedure Go;
    // D5 fast-follow (T3): an OVERLOADED routine, two declarations sharing the
    // leaf name 'Combine' but different param lists. Each overload has its own
    // DISTINCT local var of the same name (Tmp), so FindRoutineSymbolIndex's
    // overload disambiguation (by ImplStartLine) must parent each Tmp to the
    // RIGHT overload -- not both to the first match found by name alone.
    procedure Combine(A: Integer); overload;
    procedure Combine(A: TWorker); overload;
  end;

implementation

procedure TWorker.Go;
var
  L: TWorker;
  N: Integer;
  X, Y: TWorker;
begin
  L := Self;
  N := 0;
  X := L;
  Y := L;
end;

procedure TWorker.Combine(A: Integer);
var
  Tmp: Integer;
begin
  Tmp := A;
end;

procedure TWorker.Combine(A: TWorker);
var
  Tmp: TWorker;
begin
  Tmp := A;
end;

end.
