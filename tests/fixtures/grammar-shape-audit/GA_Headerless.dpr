uses
  System.SysUtils;

{ Grammar-shape audit fixture, shape (d): a program with no `program X;`
  header parses in grammar v1.4.5 (was an ERROR root). }

var
  GObj: TObject;
  GUnused: Integer;

begin
  GObj := TObject.Create;
  if ParamCount > 0 then
    Exit;
  GObj.Free;
  try
    Writeln('x');
  except
  end;
end.
