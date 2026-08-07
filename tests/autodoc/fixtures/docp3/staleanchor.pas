unit staleanchor;

{ Fixture for run_doc_p3_stale_anchor.ps1 -- PHASE A2.

  TWO members of ONE class, documented by TWO consecutive `document --qname
  --apply` commands with NO reindex in between. That is the whole shape: the
  first apply inserts lines above Create, every declaration below it moves down,
  and the store still holds the PRE-EDIT start_line for Ping -- which now points
  into the middle of the block the first command just wrote.

  Ping calls Create so that both members have a fact and therefore a doc block;
  without one the engine writes nothing and the test would be vacuous. }

interface

type
  TZeiss = class
  public
    constructor Create(const AText: string);
    procedure Ping(const AValue: Integer);
  end;

implementation

constructor TZeiss.Create(const AText: string);
begin
end;

procedure TZeiss.Ping(const AValue: Integer);
begin
  Create('x');
end;

end.
