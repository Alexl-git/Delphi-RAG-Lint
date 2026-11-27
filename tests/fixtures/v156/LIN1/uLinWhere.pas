unit uLinWhere;

{ Fixture of tests\autotest\run_v156_LIN1.ps1 (1.56 lane LIN-1, lineage model; SPEC-LIN 5.2 "uLinWhere").
  Never compiled: it is indexed. The tests find their lines by the M-... markers, so lines may move. }

interface

uses
  System.Classes, System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfLinWhere = class(TForm)
    tblOrders: TFDQuery;
    tblOrdersQTY: TFloatField;
    tblOrdersX: TFloatField;
    tblOrdersY: TFloatField;
  private
    procedure FillY;
  end;

var
  fLinWhere: TfLinWhere;

implementation

{$R *.dfm}

procedure TfLinWhere.FillY;
begin
  tblOrdersY.AsFloat := tblOrdersQTY.AsFloat; { M-Y }
end;

end.
