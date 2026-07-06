unit callsfacts;

// D5 Task 10 fixture: a caller whose body mixes a RESOLVABLE call (typed-local
// receiver -> call_edges resolves it) with an UNRESOLVABLE call-site
// ('SetLength(...)', an RTL routine with no matching symbol in this unit) so
// AutoDocument's Calls facts must show the union: the resolved callee
// QUALIFIED, plus the unresolved site via the body-scan fallback, with no
// double-listing of the resolved site's bare name.
//
// D5 fast-follow (T10): TOther also declares a same-leaf-name Run, and
// TDriver.DoWork calls it via a second typed local (O). One caller body now
// dispatches to TWO differently-qualified 'Run' methods -- the resolver must
// keep them apart (callsfacts.TWorker.Run vs callsfacts.TOther.Run), not
// collapse them into a single bare 'Run' entry.

interface

type
  TWorker = class
    procedure Run;
  end;

  TOther = class
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

procedure TOther.Run;
begin
end;

procedure TDriver.DoWork;
var
  W: TWorker;
  O: TOther;
  Arr: array of Integer;
begin
  W := TWorker.Create;
  W.Run;               // typed-local receiver -> RESOLVES to callsfacts.TWorker.Run
  O := TOther.Create;
  O.Run;                // typed-local receiver -> RESOLVES to callsfacts.TOther.Run (same leaf name 'Run', different qualified target)
  SetLength(Arr, 3);    // unresolved RTL call -> body-scan FALLBACK only
  W.Free;
  O.Free;
end;

end.
