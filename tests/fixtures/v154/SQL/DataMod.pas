unit DataMod;
interface
uses SqlStubs;
type
  TDM = class(TForm)
    qOne: TFDQuery;
    qTwo: TFDQuery;
    qOut: TFDQuery;
    qMissing: TFDQuery;
    qValued: TFDQuery;
    qNullDecl: TFDQuery;
  published
    procedure Go;
  end;
var
  DM: TDM;
implementation
{$R *.dfm}
procedure TDM.Go;
begin
  qOne.ParamByName('ID').AsInteger := 1;
  qOne.ParamByName('IDD').AsInteger := 1; // FIRE sql-param-mismatch
  qOne.Open;
  qOut.ParamByName('X').AsInteger := 1;
  qMissing.ParamByName('A').AsInteger := 1;
  qMissing.Open; // FIRE sql-param-mismatch
  qValued.ParamByName('A').AsInteger := 1;
  qValued.Open;
  qNullDecl.ParamByName('B').AsInteger := 1;
  qNullDecl.Open;
end;
end.