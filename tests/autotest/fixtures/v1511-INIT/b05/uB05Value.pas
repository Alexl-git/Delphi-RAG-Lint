unit uB05Value;

// Fixture (1.51.1 lane INIT, B05): the initialization passes the file routines as VALUES (no parentheses);
// nothing runs them at init, so heavy-initialization must stay silent here.

interface

implementation

uses
  uB05Work;

var
  GHook: TB05Hook;

procedure BuildHooks;
begin
  AddHook(TB05Checks.CheckFile);
  AddHook(WorkFile);
  GHook:= TB05Checks.CheckFile;
  AddFn(TB05Checks.ReadIt);
  GHook:= @WorkFile;
end;

initialization
  BuildHooks;

end.
