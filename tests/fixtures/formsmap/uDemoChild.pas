unit uDemoChild;
interface
uses Vcl.Forms;
type
  TfrmChild = class(TForm)
  public
    constructor CreateForFolder(AOwner: TComponent; AId: Integer);
  end;
implementation
{$R *.dfm}
constructor TfrmChild.CreateForFolder(AOwner: TComponent; AId: Integer);
begin
  inherited Create(AOwner);
end;
end.
