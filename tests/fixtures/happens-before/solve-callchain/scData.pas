unit scData;

interface

var
  GData: Integer;
  GDataIf: Integer;

procedure SetData;
procedure SetDataIf;

implementation

procedure SetData;
begin
  GData:= 1;
end;

procedure SetDataIf;
begin
  GDataIf:= 1;
end;

end.
