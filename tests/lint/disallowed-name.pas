unit DisallowedName;

interface

implementation

procedure Probe;
var
  Foo: Integer;
  Count: Integer;
begin
  Foo:= 1;
  Count:= Foo + 2;
  Count:= Rec.foo;
  // foo in a comment
  Writeln('foo');
end;

end.
