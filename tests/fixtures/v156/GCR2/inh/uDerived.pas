unit uDerived;

interface

uses
  System.SysUtils, System.Classes, Data.DB, FireDAC.Comp.Client, uBase;

type
  TdmDerived = class(TdmBase)
    tblOrdersNOTE: TStringField;
    tblOwn: TFDTable;
    tblOwnID: TIntegerField;
    procedure tblOrdersNOTEGetText(Sender: TField; var Text: string; DisplayText: Boolean);
  end;

var
  dmDerived: TdmDerived;

implementation

{$R *.dfm}

procedure TdmDerived.tblOrdersNOTEGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  Text := UpperCase(Sender.AsString);
end;

end.
