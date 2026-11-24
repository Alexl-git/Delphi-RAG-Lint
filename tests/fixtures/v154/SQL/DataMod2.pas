unit DataMod2;
interface
uses SqlStubs;
type
  TDM2 = class(TForm)
    qEvt: TFDQuery;
  published
    procedure Go;
    procedure qEvtBeforeOpen(DataSet: TObject);
  end;
var
  DM2: TDM2;
implementation
{$R *.dfm}
procedure TDM2.Go;
begin
  qEvt.ParamByName('A').AsInteger := 1;
  qEvt.Open;
end;
procedure TDM2.qEvtBeforeOpen(DataSet: TObject);
begin
  TFDQuery(DataSet).ParamByName('B').AsInteger := 1;
end;
end.
