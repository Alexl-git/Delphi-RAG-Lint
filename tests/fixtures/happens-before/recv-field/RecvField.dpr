program RecvField;

{ check-init fixture recv-field (lane HBRECV): see rfOwner.pas. }

uses
  rfOwner in 'rfOwner.pas';

procedure Main;
var
  O: TOwner;
  B: TOwnerB;
  R: TOwnerR;
  C: TOwnerC;
begin
  O:= TOwner.Create;
  O.Go;
  B:= TOwnerB.Create;
  B.Go;
  R:= TOwnerR.Create;
  R.Replace;
  R.Go;
  C:= TOwnerC.Create;
  C.Go;
end;

begin
  Main;
end.
