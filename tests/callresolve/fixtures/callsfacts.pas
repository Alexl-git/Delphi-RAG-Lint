unit callsfacts;

// D5 Task 10 fixture: a caller whose body mixes a RESOLVABLE call (typed-local
// receiver -> call_edges resolves it) with an UNRESOLVABLE call-site
// ('SetLength(...)', an RTL routine with no matching symbol in this unit) so
// AutoDocument's Calls facts must show the union: the resolved callee
// QUALIFIED, plus the unresolved site via the body-scan fallback, with no
// double-listing of the resolved site's bare name.

interface

type
  TWorker = class
    procedure Run;
  end;

  TDriver = class
  public
    procedure DoWork;
  end;

implementation

procedure TWorker.Run;
begin
end;

procedure TDriver.DoWork;
var
  W: TWorker;
  Arr: array of Integer;
begin
  W := TWorker.Create;
  W.Run;               // typed-local receiver -> RESOLVES to callsfacts.TWorker.Run
  SetLength(Arr, 3);    // unresolved RTL call -> body-scan FALLBACK only
  W.Free;
end;

end.
