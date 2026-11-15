unit UDm;

interface

uses
  System.Classes, Data.DB;

type
  TdmMain = class(TDataModule)
    qryItems: TDataSet;
  public
    UserName: string;
  end;

var
  dmMain: TdmMain;

implementation

{$R *.dfm}

end.
