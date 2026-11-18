unit scfgData;

interface

var
  GCfgRead: Integer;
  GCfgSet: Integer;
  GCfgNone: Integer;
  GCfgBogus: Integer;
  GCfgMark: Integer;

procedure UseAll;

implementation

procedure UseAll;
begin
  Writeln(GCfgRead); // USE-READ
  Writeln(GCfgSet); // USE-SET
  Writeln(GCfgNone); // USE-NONE
  Writeln(GCfgBogus); // USE-BOGUS
  Writeln(GCfgMark); // USE-MARK
end;

end.
