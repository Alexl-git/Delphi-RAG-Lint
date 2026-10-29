unit uField;

interface

type
  TCfg = class
  protected
    FSql: string;
  public
    procedure Load;
    procedure Run;
  end;

  TCfg2 = class(TCfg)
  public
    procedure Run2;
  end;

implementation

uses
  uDal;

procedure TCfg.Load;
begin
  FSql := ParamStr(2);
end;

procedure TCfg.Run;
begin
  GConn.ExecSQL(FSql);
end;

procedure TCfg2.Run2;
begin
  GConn.ExecSQL('select ' + FSql);
end;

end.
