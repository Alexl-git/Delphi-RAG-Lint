unit uDerived;

interface

uses
  System.Classes, Data.DB, FireDAC.Comp.Client, uBase;

type
  { TdmDerived = class(TdmWrong) -- a comment is not a declaration }
  TdmDerived = class(TdmBase)
    tblOrdersNOTE: TStringField;
  end;

var
  dmDerived: TdmDerived;

implementation

{$R *.dfm}

end.
