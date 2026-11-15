unit uHiLibVar;

{ heavy-initialization: the section reaches a library METHOD through a local variable. }

interface

implementation

uses
  HiLibStore;

procedure Boot;
var
  Store: THiLibStore;
begin
  Store:= nil;
  Store.Load;
end;

initialization
  Boot; // TRIGGER-LIBVAR
end.
