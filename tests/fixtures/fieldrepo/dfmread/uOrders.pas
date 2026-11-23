unit uOrders;

interface

uses
  Forms, DB, DBTables;

type
  TfrmOrders = class(TForm)
    tblOrders: TTable;
    tblOrdersQTY: TIntegerField;
    procedure tblOrdersCalcFields(DataSet: TDataSet);
    procedure tblOrdersQTYGetText(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure tblOrdersQTYValidate(Sender: TField);
  end;

implementation

{$R *.dfm}

procedure TfrmOrders.tblOrdersCalcFields(DataSet: TDataSet);
begin
  tblOrdersTOTAL.Value := tblOrdersQTY.Value * tblOrdersPRICE.Value;
  if tblOrdersTOTAL.Value > 100 then
    tblOrdersBIG.AsString := 'yes'
  else
    tblOrdersBIG.AsString := 'no';
  tblOrdersLATE.Value := not tblOrdersPRICE.IsNull;
end;

procedure TfrmOrders.tblOrdersQTYGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  if tblOrdersLATE.Value then
    Text := '!' + Sender.AsString;
end;

procedure TfrmOrders.tblOrdersQTYValidate(Sender: TField);
begin
end;

end.
