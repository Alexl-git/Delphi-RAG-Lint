unit uLin2;

{ Fixture of tests\autotest\run_v156_LIN2.ps1 (1.56 lane LIN-2: read-dfm marks derived fields; SPEC-LIN 3.1, 3.3).
  Never compiled: it is indexed and read by `repo read-dfm`.
  TOTAL  derived direct: QTY, PRICE (home table ORDERS) and CUSTOMERS.DISCOUNT -> one DL_FIELD_INPUTS row
  NET    derived direct from the home table only -> no DL_FIELD_INPUTS row
  SUMQ   derived aggregate over ORDER_LINES -> no path ORDERS -> ORDER_LINES, unplaced
  RATE2  derived unknown (result of a project routine) -> a warning, no row
  STAMP  written from Now: not derived;  IDLE never written;  QTY a real column code overwrites: unchanged
  qryJoin.CALCD  a calc field over two tables: the read itself plans the FK relation TOTAL's input needs }

interface

uses
  System.Classes, System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfLin2 = class(TForm)
    tblOrders: TFDQuery;
    tblOrdersQTY: TFloatField;
    tblOrdersPRICE: TFloatField;
    tblOrdersTOTAL: TFloatField;
    tblOrdersNET: TFloatField;
    tblOrdersSUMQ: TFloatField;
    tblOrdersRATE2: TFloatField;
    tblOrdersSTAMP: TDateTimeField;
    tblOrdersIDLE: TFloatField;
    qryCust: TFDQuery;
    qryLines: TFDQuery;
    qryLinesAMOUNT: TFloatField;
    qryLinesQTY: TIntegerField;
    qryJoin: TFDQuery;
    qryJoinQTY: TFloatField;
    qryJoinDISCOUNT: TFloatField;
    qryJoinCALCD: TFloatField;
    procedure tblOrdersAfterOpen(DataSet: TDataSet);
    procedure qryJoinCalcFields(DataSet: TDataSet);
  public
    procedure Fill;
  end;

function CalcRate(const pQty: Double): Double;

var
  fLin2: TfLin2;

implementation

{$R *.dfm}

function CalcRate(const pQty: Double): Double;
begin
  Result := pQty * 2;
end;

procedure TfLin2.qryJoinCalcFields(DataSet: TDataSet);
begin
  qryJoinCALCD.AsFloat := qryJoinQTY.AsFloat * qryJoinDISCOUNT.AsFloat;
end;

procedure TfLin2.tblOrdersAfterOpen(DataSet: TDataSet);
var
  d: Double;
  vSum: Double;
begin
  d := tblOrdersQTY.AsFloat * tblOrdersPRICE.AsFloat;
  tblOrdersTOTAL.AsFloat := d * (1 - qryCust.FieldByName('DISCOUNT').AsFloat);
  tblOrdersNET.AsFloat := tblOrdersQTY.AsFloat * tblOrdersPRICE.AsFloat;
  tblOrdersSTAMP.AsDateTime := Now;
  vSum := 0;
  qryLines.First;
  while not qryLines.Eof do
  begin
    vSum := vSum + qryLinesAMOUNT.AsFloat * qryLinesQTY.AsInteger;
    qryLines.Next;
  end;
  tblOrdersSUMQ.AsFloat := vSum;
end;

procedure TfLin2.Fill;
begin
  tblOrdersRATE2.AsFloat := CalcRate(tblOrdersQTY.AsFloat);
  tblOrdersQTY.AsFloat := tblOrdersPRICE.AsFloat * 2;
end;

end.
