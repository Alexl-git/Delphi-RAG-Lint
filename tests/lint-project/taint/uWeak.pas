unit uWeak;

interface

uses
  Forms;

type
  TfrmWeak = class(TForm)
    procedure Go;
  end;

implementation

uses
  uDal;

procedure TfrmWeak.Go;
begin
  GConn.ExecSQL('select * from T where N = ' + edtName.Text);
end;

end.
