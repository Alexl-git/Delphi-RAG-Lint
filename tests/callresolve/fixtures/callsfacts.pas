unit callsfacts;

// D5 Task 10 fixture: a caller whose body mixes a RESOLVABLE call (typed-local
// receiver -> call_edges resolves it) with an UNRESOLVABLE call-site
// ('ExternalHelper(...)', declared in no unit at all) so AutoDocument's Calls
// facts must show the union: the resolved callee QUALIFIED, plus the unresolved
// site via the body-scan fallback, with no double-listing of the resolved
// site's bare name.
//
// The unresolvable carrier used to be SetLength. It stopped working as one when
// compiler intrinsics were excluded from callee lists: SetLength is syntax, not
// a collaborator, and listing five such names buried the one real callee among
// them. So SetLength stays in the body and is now asserted ABSENT, and
// ExternalHelper -- unresolvable AND not an intrinsic -- carries the fallback
// assertion. The two together separate "intrinsics are filtered" from "the
// fallback bucket was emptied".
//
// NOTE for anyone editing this header: do NOT write a literal example of a
// rendered callee line here. The runner locates that line by pattern, and prose
// in this comment that looks like one is picked up instead of the engine's
// output -- which happened, and cost four bogus failures against a perfectly
// correct emission. The runner now also requires the '///' prefix.
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
  SetLength(Arr, 3);    // a compiler INTRINSIC -> deliberately NOT listed as a callee
  ExternalHelper(3);    // unresolved, NOT intrinsic -> body-scan FALLBACK must still show it
  W.Free;
  O.Free;
end;

end.
