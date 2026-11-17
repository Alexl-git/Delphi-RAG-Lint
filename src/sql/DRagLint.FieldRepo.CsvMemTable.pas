unit DRagLint.FieldRepo.CsvMemTable;

{ drag-lint 1.52 -- lane TTCSV: FDMemTable field definitions from CSV.
  Engine port of TableTools MemTableFieldWizard (migration step M8). The
  wizard built the fields live in the form designer; this unit emits the
  equivalent Pascal source so the same result needs no IDE. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised for malformed CSV input or an invalid generated-routine name.</summary>
  ECsvMemTableError = class(Exception);

/// <summary>Turns a field-definition CSV into the Pascal source of a procedure that builds the fields of a TFDMemTable.</summary>
/// <param name="pCsvText">CSV text. Header: FieldName,FieldType,Size,FieldKind,LookupDataset,KeyFields,LookupKeyFields,LookupResultField. The header row and rows with fewer than 4 columns are skipped.</param>
/// <param name="pName">Identifier used for the generated routine, <c>Create&lt;pName&gt;Fields</c>. Default is FDMemTable.</param>
/// <returns>Pascal source text, CRLF line ends, 7-bit ASCII.</returns>
/// <exception cref="ECsvMemTableError">Raised when pName is not an identifier or a FieldType is not a TFieldType member (ft prefix omitted).</exception>
/// <remarks>Pure function, no I/O, thread-safe. Same rules as the wizard: columns split on comma and trimmed; Size 0 or non-numeric means no Size line; FieldKind Calculated or Lookup else Data.</remarks>
function GenMemTableFromCsv(const pCsvText: string; const pName: string = 'FDMemTable'): string;

/// <summary>Reads a CSV file and calls GenMemTableFromCsv.</summary>
/// <param name="pCsvFile">Path of the CSV file (default ANSI/BOM detection).</param>
/// <param name="pName">Routine identifier, see GenMemTableFromCsv.</param>
/// <returns>Pascal source text.</returns>
/// <exception cref="ECsvMemTableError">As GenMemTableFromCsv; a missing file raises EFOpenError.</exception>
function GenMemTableFromCsvFile(const pCsvFile: string; const pName: string = 'FDMemTable'): string;

implementation

uses
  System.Classes, System.TypInfo, Data.DB;

const
  CMinCols = 4;
  CLookupCols = 8;
  CColSize = 2;
  CColKind = 3;
  CColDataset = 4;
  CColKeyFields = 5;
  CColLookupKeys = 6;
  CColResult = 7;

function Q(const pText: string): string;
begin
  Result := QuotedStr(pText);
end;

function IsIdent(const pText: string): Boolean;
var
  i: Integer;
begin
  Result := pText <> '';
  for i := 1 to Length(pText) do
    if not CharInSet(pText[i], ['A'..'Z', 'a'..'z', '_']) and
       not ((i > 1) and CharInSet(pText[i], ['0'..'9'])) then
      Exit(False);
end;

function GenMemTableFromCsv(const pCsvText: string; const pName: string): string;
var
  lLines, lOut: TStringList;
  lParts: TArray<string>;
  lLine, lType, lKind: string;
  lSize: Integer;
begin
  if not IsIdent(pName) then
    raise ECsvMemTableError.CreateFmt('Invalid routine name: %s', [pName]);
  lLines := TStringList.Create;
  lOut := TStringList.Create;
  try
    lLines.Text := pCsvText;
    lOut.Add(Format('procedure Create%sFields(pMemTable: TFDMemTable);', [pName]));
    lOut.Add('var');
    lOut.Add('  lDef: TFieldDef;');
    lOut.Add('  lField: TField;');
    lOut.Add('begin');
    lOut.Add('  pMemTable.Close;');
    lOut.Add('  pMemTable.FieldDefs.Clear;');
    lOut.Add('  pMemTable.Fields.Clear;');
    for lLine in lLines do
    begin
      lParts := lLine.Split([',']);
      if (Length(lParts) < CMinCols) or SameText(lParts[0].Trim, 'FieldName') then
        Continue;
      lType := lParts[1].Trim;
      if GetEnumValue(TypeInfo(TFieldType), 'ft' + lType) < 0 then
        raise ECsvMemTableError.CreateFmt('Unknown FieldType: %s', [lType]);
      lSize := StrToIntDef(lParts[CColSize].Trim, 0);
      lKind := lParts[CColKind].Trim;
      lOut.Add('');
      lOut.Add('  lDef := pMemTable.FieldDefs.AddFieldDef;');
      lOut.Add('  lDef.Name := ' + Q(lParts[0].Trim) + ';');
      lOut.Add('  lDef.DataType := ft' + lType + ';');
      if lSize > 0 then
        lOut.Add('  lDef.Size := ' + IntToStr(lSize) + ';');
      lOut.Add('  lField := lDef.CreateField(pMemTable);');
      if SameText(lKind, 'Calculated') then
        lOut.Add('  lField.FieldKind := fkCalculated;')
      else if SameText(lKind, 'Lookup') then
      begin
        lOut.Add('  lField.FieldKind := fkLookup;');
        if Length(lParts) >= CLookupCols then
        begin
          lOut.Add('  lField.LookupDataset := pMemTable.Owner.FindComponent(' + Q(lParts[CColDataset].Trim) + ') as TDataSet;');
          lOut.Add('  lField.KeyFields := ' + Q(lParts[CColKeyFields].Trim) + ';');
          lOut.Add('  lField.LookupKeyFields := ' + Q(lParts[CColLookupKeys].Trim) + ';');
          lOut.Add('  lField.LookupResultField := ' + Q(lParts[CColResult].Trim) + ';');
        end;
      end
      else
        lOut.Add('  lField.FieldKind := fkData;');
    end;
    lOut.Add('');
    lOut.Add('  pMemTable.CreateDataSet;');
    lOut.Add('end;');
    Result := lOut.Text;
  finally
    lOut.Free;
    lLines.Free;
  end;
end;

function GenMemTableFromCsvFile(const pCsvFile: string; const pName: string): string;
var
  lList: TStringList;
begin
  lList := TStringList.Create;
  try
    lList.LoadFromFile(pCsvFile);
    Result := GenMemTableFromCsv(lList.Text, pName);
  finally
    lList.Free;
  end;
end;

end.