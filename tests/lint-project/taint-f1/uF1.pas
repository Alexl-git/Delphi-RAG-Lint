unit uF1;

interface

uses
  FireDAC.Comp.Client;

type
  TCustomEdit = class
  end;

  TEdit = class(TCustomEdit)
  end;

  TFancyEdit = class(TCustomEdit)
  end;

  TLabel = class
  end;

  TF1Form = class
  private
    FEdit    : TEdit;
    FFancy   : TFancyEdit;
    ParamsLabel: TLabel;
    FConn    : TFDConnection;
  public
    procedure ByDottedEdit;
    procedure ByDottedFancy;
    procedure ByLabel;
    procedure ByUnknown;
    procedure BySinkField;
  end;

implementation

procedure TF1Form.ByDottedEdit;
begin
  FConn.ExecSQL('select * from T where N = ' + Self.FEdit.Text);
end;

procedure TF1Form.ByDottedFancy;
begin
  FConn.ExecSQL('select * from T where N = ' + Self.FFancy.Text);
end;

procedure TF1Form.ByLabel;
begin
  FConn.ExecSQL('select * from T where N = ' + Self.ParamsLabel.Text);
end;

procedure TF1Form.ByUnknown;
begin
  FConn.ExecSQL('select * from T where N = ' + Self.edtMystery.Text);
end;

procedure TF1Form.BySinkField;
begin
  Self.FConn.ExecSQL('select * from T where N = ' + ParamStr(1));
end;

end.
