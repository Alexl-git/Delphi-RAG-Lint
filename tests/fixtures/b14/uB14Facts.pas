unit uB14Facts;

{ Fixture of tests\autotest\run_v156_B14.ps1 (1.56 lane EXT-B3, B14 field lineage facts).
  Never compiled: it is indexed. The runner finds its lines by the M-... markers, so lines may move. }

interface

uses
  System.Classes, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfB14 = class(TForm)
    tblM: TFDMemTable;
    tblMTOTAL: TFloatField;
    tblMNOTE: TStringField;
    qryO: TFDQuery;
    qryC: TFDQuery;
    qryL: TFDQuery;
  private
    FTbl: TFDMemTable;
    FItem: TField;
  public
    procedure Direct;
    procedure Sum;
    procedure InWith(pBase: Double);
    procedure ViewModel(pSrc: TDataSet);
    procedure Shapes(pFld: TField);
    procedure Caller;
    procedure Nested;
    procedure Plain(const pText: string);
  end;

procedure Fill(pDS: TDataSet; const pRate: Double);

var
  fB14: TfB14;

implementation

{$R *.dfm}

procedure TfB14.Direct;
var
  d: Double;
  vName: string;
begin
  d := qryO.FieldByName('QTY').AsFloat * qryO.FieldByName('PRICE').AsFloat; { M-READ2 }
  tblMTOTAL.AsFloat := d; { M-ACCW }
  tblM.FieldByName('NOTE').AsString := qryC.FieldByName('NAME').AsString; { M-BYNAMEW }
  tblM.FieldValues['FLAG'] := True; { M-LITERAL }
  tblM.FieldByName(vName).AsFloat := d; { M-EXPR }
end;

procedure TfB14.Sum;
var
  s: Double;
begin
  s := 0;
  while not qryL.Eof do { M-WHILE }
  begin
    s := s + qryL.FieldByName('AMOUNT').AsFloat; { M-SUMREAD }
    qryL.Next;
  end; { M-WHILE-END }
  tblMTOTAL.AsFloat := s; { M-SUMW }
end;

procedure TfB14.InWith(pBase: Double);
begin
  with tblM do
    FieldByName('TOTAL').AsFloat := qryO.FieldByName('QTY').AsFloat * pBase; { M-WITH }
  with tblM, qryC do
    FieldValues['FLAG'] := FItem.AsFloat > 0; { M-WITH2 }
end;

procedure Fill(pDS: TDataSet; const pRate: Double);
begin
  pDS.FieldByName('T').AsFloat := pRate * 2; { M-FILL }
end;

procedure TfB14.ViewModel(pSrc: TDataSet);
var
  vT: TFDMemTable;
begin
  FTbl.FieldByName('X').AsFloat := pSrc.FieldByName('A').AsFloat; { M-VM-FIELD }
  vT := FTbl;
  vT['Y'] := FTbl.FieldByName('X').AsFloat + 1; { M-VM-LOCAL }
end;

procedure TfB14.Shapes(pFld: TField);
var
  vF: TField;
  vS: string;
  vD: Double;
  i: Integer;
begin
  vF := qryO.FindField('QTY'); { M-FIND }
  tblMTOTAL.AsFloat := vF.AsFloat; { M-LOCALACC }
  tblM.Fields[0].AsString := qryC.Fields[1].AsString; { M-INDEX }
  tblM.FieldByName('NOTE').Clear; { M-CLEAR }
  tblMNOTE.Assign(pFld); { M-ASSIGN }
  vS := qryC.FieldValues['NAME']; { M-VALREAD }
  vS := qryC['CITY']; { M-DEFREAD }
  vD := FItem.AsFloat + pFld.AsFloat + tblMTOTAL.AsFloat; { M-ACCREAD }
  tblM.FieldByName('NOTE').AsString := vS; { M-VIASTR }
  FTbl.FieldByName('X').AsFloat := vD; { M-VIAFLT }
  for i := 0 to 9 do { M-FOR }
    tblM.FieldByName('N').AsInteger := i; { M-FORBODY }
end;

procedure TfB14.Caller;
begin
  Fill(tblM, qryO.FieldByName('RATE').AsFloat); { M-CALL }
end;

procedure TfB14.Nested;
var
  vFld: TField;
begin
  for vFld in qryL.Fields do { M-FORIN }
  begin
    repeat { M-REPEAT }
      qryL.Next;
    until qryL.Eof; { M-UNTIL }
  end;
end;

procedure TfB14.Plain(const pText: string);
var
  vList: TStringList;
begin
  vList := TStringList.Create;
  try
    vList.Add(pText); { M-PLAIN }
    Caption := vList.Text;
  finally
    vList.Free;
  end;
end;

end.
