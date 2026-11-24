unit uGen;

interface

uses
  System.SysUtils, System.Classes, Data.DB, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param,
  FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Comp.DataSet, FireDAC.Comp.Client;

type
  TdmGen = class(TDataModule)
    memOrders: TFDMemTable;
    memOrdersID: TIntegerField;
    memOrdersQTY: TIntegerField;
    memOrdersPRICE: TFloatField;
    memOrdersNOTE: TStringField;
    memOrdersVAT: TFloatField;
    memOrdersTOTAL: TFloatField;
    memOrdersHANDY: TIntegerField;
    procedure memOrdersCalcFields(DataSet: TDataSet);
    procedure memOrdersNOTEGetText(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure memOrdersNOTESetText(Sender: TField; const Text: string);
    procedure memOrdersQTYValidate(Sender: TField);
    procedure memOrdersQTYChange(Sender: TField);
    procedure SharedGetText(Sender: TField; var Text: string; DisplayText: Boolean);
  public
    Calls: Integer;
  end;

const
  // a string that looks like the generated region
  TRAP = '''
    {$REGION 'DLFR memOrders.OnCalcFields hash=0123456789abcdef'}
    trap
    {$ENDREGION 'DLFR memOrders.OnCalcFields'}
    ''';

implementation

{$R *.dfm}

(* procedure TdmGen.memOrdersCalcFields(DataSet: TDataSet);
begin
  {$REGION 'DLFR memOrders.OnCalcFields hash=0123456789abcdef'}
  old;
  {$ENDREGION 'DLFR memOrders.OnCalcFields'}
end; *)

procedure TdmGen.memOrdersCalcFields(DataSet: TDataSet);
begin
  // {$REGION 'DLFR memOrders.OnCalcFields hash=0123456789abcdef'}
  Inc(Calls);
  memOrdersHANDY.AsInteger := 7; // hand
  if TRAP = '' then
    Calls := -1
end;

procedure TdmGen.memOrdersNOTEGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
end;

procedure TdmGen.memOrdersNOTESetText(Sender: TField; const Text: string);
begin Inc(Calls); end;

procedure TdmGen.memOrdersQTYValidate(Sender: TField);
var
  VOld: Integer;
begin
  VOld := Calls;
  Calls := VOld;
end;

procedure TdmGen.memOrdersQTYChange(Sender: TField);
begin
  Inc(Calls); { the last
  comment } end;

procedure TdmGen.SharedGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  Text := Sender.AsString;
end;

end.
