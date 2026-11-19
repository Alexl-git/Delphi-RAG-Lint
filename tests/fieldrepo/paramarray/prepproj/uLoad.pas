unit uLoad;

{ Fixture of repo gen-param-array --prepare-queries (1.52 BK-TTFINISH U6): stub component classes,
  so the project builds without FireDAC / BDE while the R directive still compiles the text DFM. }

interface

uses
  System.Classes;

type
  TTable = class(TComponent);
  TIntegerField = class(TComponent);
  TStringField = class(TComponent);
  TFDQuery = class(TComponent);
  TFDUpdateSQL = class(TComponent);
  TFDSchemaAdapter = class(TComponent);

  TfrmLoad = class(TComponent)
    tblFOLDERS: TTable;
    tblFOLDERSID: TIntegerField;
    tblFOLDERSNAME: TStringField;
    qryFOLDERS: TFDQuery;
    qryFOLDERSID: TIntegerField;
    qryFOLDERSNAME: TStringField;
    updFOLDERS: TFDUpdateSQL;
    SA1: TFDSchemaAdapter;
  private
    FCount: Integer;
  end;

implementation

{$R *.dfm}

end.
