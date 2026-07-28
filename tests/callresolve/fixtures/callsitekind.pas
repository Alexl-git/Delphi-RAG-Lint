unit callsitekind;

// T3i fixture (register item E1): the CALL-SITE ref-kind universe.
//
// Every consumer that reports an UNRESOLVED call site takes the complement of
// the resolved call_edges, and ResolveCallTargets only ever walks kind='call'
// refs -- so the complement is only meaningful within that same universe. This
// fixture holds one instance of each shape that pressures the boundary:
//
//   TDriver.CallsFire     FProbe.Fire;      statement dotted call
//                                           -> 'call' ref AND a co-located
//                                              'member-access' ref (9d7e641);
//                                              resolves CERTAIN to TProbe.Fire
//   TDriver.CallsUnknown  U.Fire;           statement dotted call on an
//                                           UNDECLARED receiver type
//                                           -> 'call' ref with NO call_edge:
//                                              the one genuine unresolved site
//   TDriver.ReadsProperty N:= FProbe.Count; PROPERTY read, not a call at all
//                                           -> 'member-access' only. Its name
//                                              collides with the unit-level
//                                              function Count, so a kind-blind
//                                              reader mistakes it for a call
//   TDriver.ParenlessExpr N:= FProbe.Make;  paren-less call in EXPRESSION
//                                           position -> 'member-access' only,
//                                              NO 'call' ref. The DISCLOSED gap
//
// Count is declared BOTH as a TProbe property and as a unit-level function on
// purpose: that name collision is what turns a property read into a phantom
// unresolved call site once the kind restriction is missing.

// T3i REVIEW ROUND 2 additions: TProbeKind (enum) and TProbeAlias (type alias)
// are documentable kinds (Doc.Batch.IsDocumentableKind) that round 1's gate
// omitted, so their reference list silently vanished. Each is referenced from a
// unit-scope var in the implementation section -- the NULL-enclosing shape that
// run_doc_no_self_caller.ps1 pins for a class -- so the four kinds carry the
// SAME reference shape and any difference between them is the gate, not the data.

interface

type
  TProbeKind = (pkFirst, pkSecond);

  TProbe = class
  private
    FCount: Integer;
  public
    property Count: Integer read FCount write FCount;
    procedure Fire;
    function Make: Integer;
  end;

  TProbeAlias = TProbe;

  TDriver = class
  private
    FProbe: TProbe;
  public
    procedure ReadsProperty;
    procedure CallsFire;
    procedure ParenlessExpr;
    procedure CallsUnknown;
  end;

function Count: Integer;

implementation

// Unit-scope references: NULL-enclosing type_use refs, one per non-routine kind.
var
  GKind : TProbeKind ;
  GAlias: TProbeAlias;

function Count: Integer;
begin
  Result:= 0;
end;

procedure TProbe.Fire;
begin
end;

function TProbe.Make: Integer;
begin
  Result:= 1;
end;

procedure TDriver.ReadsProperty;
var
  N: Integer;
begin
  N:= FProbe.Count;    // property read -- member-access only, NOT a call
end;

procedure TDriver.CallsFire;
begin
  FProbe.Fire;         // field receiver TProbe -> certain TProbe.Fire
end;

procedure TDriver.ParenlessExpr;
var
  N: Integer;
begin
  N:= FProbe.Make;     // paren-less call in expression position -- no call ref
end;

procedure TDriver.CallsUnknown;
var
  U: IUnknownProbe;
begin
  U.Fire;              // receiver type undeclared -> call ref, no edge -> '?'
end;

end.
