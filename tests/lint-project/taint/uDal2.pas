unit uDal2;

interface

uses
  FireDAC.Comp.Client, uDal;

type
  TDal2 = class(TDalBase)
  public
    procedure Exec(const ASql: string); override;
  end;

implementation

procedure TDal2.Exec(const ASql: string);
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := ASql;
  Q.Open;
end;

end.
