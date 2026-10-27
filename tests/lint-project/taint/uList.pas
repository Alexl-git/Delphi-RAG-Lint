unit uList;

interface

procedure UseList;

implementation

uses
  Classes, FireDAC.Comp.Client, uDal;

procedure UseList;
var
  L: TStringList;
  Q: TFDQuery;
begin
  L := TStringList.Create;
  L.Add(ParamStr(1));
  GConn.ExecSQL(L.Text);
  Q := TFDQuery.Create(nil);
  Q.SQL.Add(ParamStr(2));
end;

end.
