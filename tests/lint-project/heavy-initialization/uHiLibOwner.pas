unit uHiLibOwner;

{ heavy-initialization: the section calls a member of a heavy library type returned by a library function: the project never names the type. }

interface

implementation

uses
  HiLibStore;

procedure Open;
begin
  HiLibReg.OpenKey;
end;

initialization
  Open; // TRIGGER-OWNER
end.
