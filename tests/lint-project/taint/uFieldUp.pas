unit uFieldUp;

interface

type
  TBase = class
  protected
    FCmd: string;
  public
    procedure Exec;
  end;

  TChild = class(TBase)
  public
    procedure Load;
  end;

implementation

uses
  uDal;

procedure TBase.Exec;
begin
  GConn.ExecSQL(FCmd);
end;

procedure TChild.Load;
begin
  FCmd := ParamStr(4);
end;

end.
