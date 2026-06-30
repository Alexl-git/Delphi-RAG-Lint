unit Caller;
interface
implementation
uses Subject;
procedure DoIt;
var S: TSubject;
begin
  S := TSubject.Create;
  S.Foo;
end;
end.
