unit BvLib;

interface

procedure ReportAt(AIndex: Integer; const AText: string);
procedure MoveOn(var AIndex: Integer);

implementation

procedure ReportAt(AIndex: Integer; const AText: string);
begin
  if AIndex > 0 then Writeln(AText);
end;

procedure MoveOn(var AIndex: Integer);
begin
  AIndex := -1;
end;

end.
