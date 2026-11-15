unit uHiLibOwner;

{ heavy-initialization: the section calls a member of a heavy library type through a field of a library
  object (GStore.Reg.OpenKey): the project never names the type, only the index's binding does. }

interface

implementation

uses
  HiLibStore;

var
  GStore: THiLibStore;

procedure Open;
begin
  GStore.Reg.OpenKey;
end;

initialization
  Open; // TRIGGER-OWNER
end.
