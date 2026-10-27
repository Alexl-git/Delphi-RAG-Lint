unit NilReturningCallDereferenced;

interface

implementation

uses
  System.Classes, Vcl.Forms, Vcl.Controls, Data.DB;

procedure Bad(AForm: TForm; ADataSet: TDataSet);
begin
  AForm.FindComponent('Edit1').Name := 'x';
  (AForm.FindComponent('Edit1') as TControl).Visible := False;
  ADataSet.FindField('ID').AsInteger := 1;
  AForm.FindChildControl('Panel1').Hide;
end;

procedure Good(AForm: TForm; ADataSet: TDataSet);
var
  C: TComponent;
begin
  if Assigned(AForm.FindComponent('Edit1')) then
    AForm.Caption := 'x';
  C := AForm.FindComponent('Edit1');
  if C <> nil then
    C.Name := 'y';
  AForm.Caption := AForm.Name;
  AForm.FindComponent('Edit1');
end;

end.
