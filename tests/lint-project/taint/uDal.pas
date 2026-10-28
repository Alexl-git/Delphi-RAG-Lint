unit uDal;

interface

uses
  FireDAC.Comp.Client;

type
  TDalBase = class
  public
    procedure Exec(const ASql: string); virtual;
  end;

procedure DoExec(const ASql: string);
procedure RunQuery(const AName: string);
procedure RunArg;

var
  GConn: TFDConnection;

implementation

uses
  uInput, uDal2;

procedure TDalBase.Exec(const ASql: string);
begin
end;

procedure DoExec(const ASql: string);
begin
  GConn.ExecSQL(ASql);
end;

procedure RunQuery(const AName: string);
begin
  DoExec('select * from T where N = ''' + AName + '''');
end;

procedure RunArg;
var
  D: TDalBase;
begin
  D := TDal2.Create;
  D.Exec('delete from T where id = ' + ReadArg);
end;

end.
