unit dispatch;

// Fixture for run_doc_covered_by_dispatch.ps1 -- the TARGETS.
//
// Two classes implement the same interface method, so the reverse walk has more
// than one same-named candidate to attribute a call to. That is the shape
// behind the report: eight symbols named TransferFile, and one test attributed
// to all of them.

interface

type
  ICopy = interface
    ['{2C3A1B10-0000-4000-8000-00000000A001}']
    function TransferFile(const A: string): Boolean;
  end;

  TAlpha = class(TInterfacedObject, ICopy)
  public
    function TransferFile(const A: string): Boolean;
  end;

  TBeta = class(TInterfacedObject, ICopy)
  public
    function TransferFile(const A: string): Boolean;
  end;

// A FREE ROUTINE, and the negative control: an unqualified call to one of these
// has no receiver and needs none, so its coverage must NEVER be marked.
function PlainHelper(const A: string): Boolean;

implementation

function TAlpha.TransferFile(const A: string): Boolean;
begin
  Result:= A <> '';
end;

function TBeta.TransferFile(const A: string): Boolean;
begin
  Result:= A <> '';
end;

function PlainHelper(const A: string): Boolean;
begin
  Result:= Length(A) > 0;
end;

end.
