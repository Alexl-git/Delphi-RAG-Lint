unit xdb_app;

{ The CONSUMER. TJsonThing is not declared in this index at all, so
  TJsonThing.Create cannot own a call_edges row here -- target_symbol_id is a
  NOT NULL FK into THIS database. v21 records the answer by NAME instead, on
  refs.external_target. }

interface

procedure UseExternal;
procedure UseUnknown;

implementation

procedure UseExternal;
begin
  TJsonThing.Create(1);
end;

{ A type NO index knows. Must stay unresolved -- the cross-DB rung answers only
  when exactly one type and exactly one member match, so absence beats a guess. }
procedure UseUnknown;
begin
  TNeverDeclared.Create(2);
end;

end.
