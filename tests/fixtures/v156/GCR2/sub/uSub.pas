unit uSub;

interface

uses
  System.Classes, Vcl.Forms, Data.DB, FireDAC.Comp.Client, uMod;

type
  TfrmSub = class(TForm)
    memCust: TFDMemTable;
    memCustNAME: TStringField;
    procedure FormCreate(Sender: TObject);
  end;

var
  frmSub: TfrmSub;

implementation

{$R *.dfm}

procedure TfrmSub.FormCreate(Sender: TObject);
begin
  memCust.CopyDataSet(dmMod.tblCust);
end;

end.
