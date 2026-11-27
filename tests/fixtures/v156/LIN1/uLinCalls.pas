unit uLinCalls;

{ Fixture of tests\autotest\run_v156_LIN1.ps1 (1.56 lane LIN-1, lineage model; SPEC-LIN 5.2 "uLinCalls").
  Never compiled: it is indexed. The tests find their lines by the M-... markers, so lines may move. }

interface

uses
  System.Classes, System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfLinCalls = class(TForm)
    tblOrders: TFDQuery;
    tblOrdersQTY: TFloatField;
    tblOrdersRATE2: TFloatField;
    tblOrdersR3: TFloatField;
    tblOrdersP4: TFloatField;
  public
    procedure Fill;
    procedure SetP4(const pV: Double);
  end;

function CalcRate(const pQty: Double): Double;

var
  fLinCalls: TfLinCalls;

implementation

{$R *.dfm}

function CalcRate(const pQty: Double): Double;
begin
  Result := pQty * 2;
end;

procedure TfLinCalls.Fill;
begin
  tblOrdersRATE2.AsFloat := CalcRate(tblOrdersQTY.AsFloat); { M-RATE2 }
  tblOrdersR3.AsFloat := Round(tblOrdersQTY.AsFloat); { M-R3 }
end;

procedure TfLinCalls.SetP4(const pV: Double);
begin
  tblOrdersP4.AsFloat := pV; { M-P4 }
end;

end.
