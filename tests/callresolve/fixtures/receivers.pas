unit receivers;

// D5 Task 5 fixture: distinct call-site receiver kinds invoking same-named
// methods (Run) on different types, so the resolver's per-site correctness is
// checkable end-to-end (Task 6 writes call_edges; Task 7 asserts Called-from
// lists ONLY the right callers). Two classes TAlpha / TBeta each expose Run;
// TCaller dispatches Run via a field, a param, a typed local, and Self.

interface

type
  TAlpha = class
    procedure Run;
  end;

  TBeta = class
    procedure Run;
  end;

  TCaller = class
  private
    FAlpha: TAlpha;
  public
    procedure Run;
    procedure ViaField;
    procedure ViaParam(AAlpha: TAlpha);
    procedure ViaLocal;
    procedure ViaSelf;
  end;

implementation

procedure TAlpha.Run;
begin
end;

procedure TBeta.Run;
begin
end;

procedure TCaller.Run;
begin
end;

procedure TCaller.ViaField;
begin
  FAlpha.Run;      // field receiver -> TAlpha.Run
end;

procedure TCaller.ViaParam(AAlpha: TAlpha);
begin
  AAlpha.Run;      // param receiver -> TAlpha.Run
end;

procedure TCaller.ViaLocal;
var
  B: TBeta;
begin
  B := TBeta.Create;
  B.Run;           // typed-local receiver -> TBeta.Run
  B.Free;
end;

procedure TCaller.ViaSelf;
begin
  Self.Run;        // Self receiver -> TCaller.Run
  Run;             // bare receiver  -> TCaller.Run
end;

end.
