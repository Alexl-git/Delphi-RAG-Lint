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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.Repo.GenMemTable (DRagLint.CLI.Repo.pas) ?, DRagLint.FieldRepo.CsvMemTable.GenMemTableFromCsv (DRagLint.FieldRepo.CsvMemTable.pas)</para>
  /// <para>Used in units: DRagLint.CLI.Repo, DRagLint.FieldRepo.CsvMemTable</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ECsvMemTableError = class(Exception);

/// <summary>Turns a field-definition CSV into the Pascal source of a procedure that builds the fields of a TFDMemTable.</summary>
/// <param name="pCsvText">CSV text. Header: FieldName,FieldType,Size,FieldKind,LookupDataset,KeyFields,LookupKeyFields,LookupResultField. The header row and rows with fewer than 4 columns are skipped.</param>
/// <param name="pName">Identifier used for the generated routine, <c>Create&lt;pName&gt;Fields</c>. Default is FDMemTable.</param>
/// <returns>Pascal source text, CRLF line ends, 7-bit ASCII.</returns>
/// <exception cref="ECsvMemTableError">Raised when pName is not an identifier or a FieldType is not a TFieldType member (ft prefix omitted).</exception>
/// <remarks>
/// Pure function, no I/O, thread-safe. Same rules as the wizard: columns split on comma and trimmed; Size 0 or non-numeric means no Size line; FieldKind Calculated or Lookup else Data.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.CsvMemTable.GenMemTableFromCsvFile (DRagLint.FieldRepo.CsvMemTable.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.CsvMemTable.IsIdent, DRagLint.FieldRepo.CsvMemTable.Q, Format, GetEnumValue, IntToStr, SameText, StrToIntDef</para>
/// <para>Returns: OutText.Text</para>
/// <seealso cref="DRagLint.FieldRepo.CsvMemTable.IsIdent"/>
/// <seealso cref="DRagLint.FieldRepo.CsvMemTable.Q"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GenMemTableFromCsv(const pCsvText: string; const pName: string = 'FDMemTable'): string;

/// <summary>Reads a CSV file and calls GenMemTableFromCsv.</summary>
/// <param name="pCsvFile">Path of the CSV file (default ANSI/BOM detection).</param>
/// <param name="pName">Routine identifier, see GenMemTableFromCsv.</param>
/// <returns>Pascal source text.</returns>
/// <exception cref="ECsvMemTableError">As GenMemTableFromCsv; a missing file raises EFOpenError.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.GenMemTable (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.CsvMemTable.GenMemTableFromCsv</para>
/// <para>Returns: GenMemTableFromCsv(List.Text, pName)</para>
/// <seealso cref="DRagLint.FieldRepo.CsvMemTable.GenMemTableFromCsv"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
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
  Lines, OutText: TStringList;
  Parts: TArray<string>;
  Line, FieldType, FieldKind: string;
  FieldSize: Integer;
begin
  if not IsIdent(pName) then
    raise ECsvMemTableError.CreateFmt('Invalid routine name: %s', [pName]);
  Lines := TStringList.Create;
  OutText := TStringList.Create;
  try
    Lines.Text := pCsvText;
    OutText.Add(Format('procedure Create%sFields(pMemTable: TFDMemTable);', [pName]));
    OutText.Add('var');
    OutText.Add('  lDef: TFieldDef;');
    OutText.Add('  lField: TField;');
    OutText.Add('begin');
    OutText.Add('  pMemTable.Close;');
    OutText.Add('  pMemTable.FieldDefs.Clear;');
    OutText.Add('  pMemTable.Fields.Clear;');
    for Line in Lines do
    begin
      Parts := Line.Split([',']);
      if (Length(Parts) < CMinCols) or SameText(Parts[0].Trim, 'FieldName') then
        Continue;
      FieldType := Parts[1].Trim;
      if GetEnumValue(TypeInfo(TFieldType), 'ft' + FieldType) < 0 then
        raise ECsvMemTableError.CreateFmt('Unknown FieldType: %s', [FieldType]);
      FieldSize := StrToIntDef(Parts[CColSize].Trim, 0);
      FieldKind := Parts[CColKind].Trim;
      OutText.Add('');
      OutText.Add('  lDef := pMemTable.FieldDefs.AddFieldDef;');
      OutText.Add('  lDef.Name := ' + Q(Parts[0].Trim) + ';');
      OutText.Add('  lDef.DataType := ft' + FieldType + ';');
      if FieldSize > 0 then
        OutText.Add('  lDef.Size := ' + IntToStr(FieldSize) + ';');
      OutText.Add('  lField := lDef.CreateField(pMemTable);');
      if SameText(FieldKind, 'Calculated') then
        OutText.Add('  lField.FieldKind := fkCalculated;')
      else if SameText(FieldKind, 'Lookup') then
      begin
        OutText.Add('  lField.FieldKind := fkLookup;');
        if Length(Parts) >= CLookupCols then
        begin
          OutText.Add('  lField.LookupDataset := pMemTable.Owner.FindComponent(' + Q(Parts[CColDataset].Trim) + ') as TDataSet;');
          OutText.Add('  lField.KeyFields := ' + Q(Parts[CColKeyFields].Trim) + ';');
          OutText.Add('  lField.LookupKeyFields := ' + Q(Parts[CColLookupKeys].Trim) + ';');
          OutText.Add('  lField.LookupResultField := ' + Q(Parts[CColResult].Trim) + ';');
        end;
      end
      else
        OutText.Add('  lField.FieldKind := fkData;');
    end;
    OutText.Add('');
    OutText.Add('  pMemTable.CreateDataSet;');
    OutText.Add('end;');
    Result := OutText.Text;
  finally
    OutText.Free;
    Lines.Free;
  end;
end;

function GenMemTableFromCsvFile(const pCsvFile: string; const pName: string): string;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.LoadFromFile(pCsvFile);
    Result := GenMemTableFromCsv(List.Text, pName);
  finally
    List.Free;
  end;
end;

end.