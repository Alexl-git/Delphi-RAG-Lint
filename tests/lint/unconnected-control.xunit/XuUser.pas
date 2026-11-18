unit XuUser;

interface

uses
  XuBase;

procedure XuPoke(AForm: TXuBase);

implementation

procedure XuPoke(AForm: TXuBase);
begin
  AForm.btnXuRemote.Caption:= 'remote';
  AForm.btnXuBound.OnDblClick:= AForm.xuRemoteAssigned;
end;

end.