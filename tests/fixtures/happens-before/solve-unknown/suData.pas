unit suData;

interface

var
  GUnk: Integer;
  GRead: Integer;
  GSets: Integer;
  GExempt: Integer;

procedure UseAll;

implementation

procedure UseAll;
begin
  Writeln(GUnk); // USE-UNK
  Writeln(GRead); // USE-READ
  Writeln(GSets); // USE-SETS
end;

end.
