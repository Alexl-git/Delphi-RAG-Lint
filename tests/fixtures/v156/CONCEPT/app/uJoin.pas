unit uJoin;

interface

uses
  System.Classes, Data.DB, Vcl.Forms, FireDAC.Comp.Client;

type
  TfrmJoin = class(TForm)
    qryJoin: TFDQuery;
    qryJoinNAME: TStringField;
    qryJoinCUSTOMER_ID: TIntegerField;
  end;

var
  frmJoin: TfrmJoin;

implementation

{$R *.dfm}

end.
