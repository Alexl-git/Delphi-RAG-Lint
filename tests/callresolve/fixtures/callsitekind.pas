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

interface

type
  TProbe = class
  private
    FCount: Integer;
  public
    property Count: Integer read FCount write FCount;
    procedure Fire;
    function Make: Integer;
  end;

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
