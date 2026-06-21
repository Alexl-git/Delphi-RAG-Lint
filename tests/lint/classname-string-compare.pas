unit ClassNameCompare;

interface

implementation

procedure P(Obj: TObject);
begin
  if Obj.ClassName = 'TFoo' then
    WriteLn('a');
end;

end.
