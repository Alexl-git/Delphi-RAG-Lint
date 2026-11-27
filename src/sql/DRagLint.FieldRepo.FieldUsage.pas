unit DRagLint.FieldRepo.FieldUsage;

{ drag-lint 1.56 -- lane UI-M (USEDICON): where a repository field is USED in a project, one kind per use, read from the
  project index DB (the Select Fields icons of lane UI-P are drawn from it). Read-only: nothing here writes either
  database. A field is matched by name, case-insensitive; the table is not part of the match (a DFM names the field of
  a dataset whose table is only known through its query). API FROZEN once UI-M.1 lands: UI-P builds on it. }

interface

uses
  FireDAC.Comp.Client;

type
  /// <summary>The kind of one use of a field in a project.</summary>
  TFieldUseKind = (
    /// <summary>A data-aware edit control in a DFM: a component whose DataField property names the field.</summary>
    fukDfmControl,
    /// <summary>A grid column bound to the field (FieldName / DataBinding.FieldName on a column object).</summary>
    fukGridColumn,
    /// <summary>A lookup: the field is a lookup key / list / result field of a control or of a lookup TField.</summary>
    fukLookup,
    /// <summary>Code: a FieldByName / Fields / dataset-index access of the field in a source unit.</summary>
    fukCode);

  /// <summary>A set of use kinds; empty = the field is unused.</summary>
  TFieldUseKinds = set of TFieldUseKind;

  /// <summary>One use of a field.</summary>
  TFieldUse = record
    /// <summary>The kind of use.</summary>
    Kind: TFieldUseKind;
    /// <summary>The field name as written at the use site.</summary>
    FieldName: string;
    /// <summary>Path of the file (.dfm or source) holding the use, as stored in the project DB.</summary>
    FilePath: string;
    /// <summary>The DFM component name; for a code use the dataset expression as written ('qCust', 'Self.qCust').</summary>
    Component: string;
    /// <summary>The DFM component class; '' for a code use.</summary>
    ComponentClass: string;
    /// <summary>1-based line of the use.</summary>
    Line: Integer;
  end;

/// <summary>Every use of a field in the project the DB indexes.</summary>
/// <param name="pProjectDb">An open connection to a project index DB (SQLite); not owned, only read.</param>
/// <param name="pFieldName">The field name; case-insensitive; '' returns no use.</param>
/// <returns>The uses ordered by kind, file path, line. A DB without the DFM property tables (an index older than
/// schema 25) returns no DFM use and does not raise.</returns>
/// <remarks>Kinds: fukDfmControl = DataField; fukGridColumn = FieldName / DataBinding.FieldName on a *Column object;
/// fukLookup = KeyField, ListField, LookupKeyFields, LookupResultField, Properties.KeyFieldNames / ListFieldNames
/// (one name or a ;-separated list); fukCode = a ds_field_accesses row with the literal field name. A field
/// named by a constant in code, and a TField whose own FieldKind is fkLookup, are not seen. Blanks in pFieldName are ignored.</remarks>
function FindFieldUses(pProjectDb: TFDConnection; const pFieldName: string): TArray<TFieldUse>;

/// <summary>The kinds in which a field is used.</summary>
/// <param name="pProjectDb">See FindFieldUses.</param>
/// <param name="pFieldName">See FindFieldUses.</param>
/// <returns>The set of kinds of FindFieldUses; empty when unused.</returns>
function FieldUseKinds(pProjectDb: TFDConnection; const pFieldName: string): TFieldUseKinds;

implementation

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.Comp.DataSet;

function TableExists(pDb: TFDConnection; const pTable: string): Boolean;
var
  VQuery: TFDQuery;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pDb;
    VQuery.SQL.Text := 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = :n';
    VQuery.ParamByName('n').AsString := pTable;
    VQuery.Open;
    Result := not VQuery.Eof;
  finally
    VQuery.Free;
  end;
end;

{ Appends the rows of pSql (columns: path, component, class, field text, line; parameter :f = the field, upper-case,
  no blanks) as uses of pKind. }
procedure AddUses(pDb: TFDConnection; const pSql, pField: string; pKind: TFieldUseKind; var pUses: TArray<TFieldUse>);
var
  VQuery: TFDQuery;
  VUse: TFieldUse;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pDb;
    VQuery.SQL.Text := pSql;
    VQuery.ParamByName('f').AsString := pField;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VUse.Kind := pKind;
      VUse.FilePath := VQuery.Fields[0].AsString;
      VUse.Component := VQuery.Fields[1].AsString;
      VUse.ComponentClass := VQuery.Fields[2].AsString;
      VUse.FieldName := VQuery.Fields[3].AsString;
      VUse.Line := VQuery.Fields[4].AsInteger;
      pUses := pUses + [VUse];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

const
  SQL_DFM_CONTROL =
    'SELECT f.path, o.name, o.class_name, p.value_text, p.start_line FROM dfm_properties p ' +
    'JOIN dfm_objects o ON o.file_id = p.file_id AND o.ordinal = p.object_ordinal ' +
    'JOIN files f ON f.id = p.file_id ' +
    'WHERE p.name = ''DataField'' AND UPPER(p.value_text) = :f ORDER BY f.path, p.start_line';
  SQL_GRID_COLUMN =
    'SELECT f.path, o.name, o.class_name, p.value_text, p.start_line FROM dfm_properties p ' +
    'JOIN dfm_objects o ON o.file_id = p.file_id AND o.ordinal = p.object_ordinal ' +
    'JOIN files f ON f.id = p.file_id ' +
    'WHERE p.name IN (''FieldName'', ''DataBinding.FieldName'') AND o.class_name LIKE ''%Column%'' ' +
    'AND UPPER(p.value_text) = :f ORDER BY f.path, p.start_line';
  { The lookup properties hold one name or a ;-separated list ('NAME; CITY'); INSTR, not LIKE, so an underscore in a name is no wildcard. }
  SQL_LOOKUP =
    'SELECT f.path, o.name, o.class_name, p.value_text, p.start_line FROM dfm_properties p ' +
    'JOIN dfm_objects o ON o.file_id = p.file_id AND o.ordinal = p.object_ordinal ' +
    'JOIN files f ON f.id = p.file_id ' +
    'WHERE p.name IN (''KeyField'', ''ListField'', ''LookupKeyFields'', ''LookupResultField'', ' +
    '''Properties.KeyFieldNames'', ''Properties.ListFieldNames'') ' +
    'AND INSTR('';'' || REPLACE(UPPER(p.value_text), '' '', '''') || '';'', '';'' || :f || '';'') > 0 ' +
    'ORDER BY f.path, p.start_line';
  SQL_CODE =
    'SELECT f.path, a.dataset_text, '''', a.field_name, a.line FROM ds_field_accesses a JOIN files f ON f.id = a.file_id ' +
    'WHERE UPPER(a.field_name) = :f ORDER BY f.path, a.line';

function FindFieldUses(pProjectDb: TFDConnection; const pFieldName: string): TArray<TFieldUse>;
var
  VField: string;
begin
  Result := nil;
  VField := UpperCase(StringReplace(pFieldName, ' ', '', [rfReplaceAll]));
  if VField = '' then
    Exit;
  if TableExists(pProjectDb, 'dfm_properties') and TableExists(pProjectDb, 'dfm_objects') then
  begin
    AddUses(pProjectDb, SQL_DFM_CONTROL, VField, fukDfmControl, Result);
    AddUses(pProjectDb, SQL_GRID_COLUMN, VField, fukGridColumn, Result);
    AddUses(pProjectDb, SQL_LOOKUP, VField, fukLookup, Result);
  end;
  if TableExists(pProjectDb, 'ds_field_accesses') then
    AddUses(pProjectDb, SQL_CODE, VField, fukCode, Result);
end;

function FieldUseKinds(pProjectDb: TFDConnection; const pFieldName: string): TFieldUseKinds;
var
  VUse: TFieldUse;
begin
  Result := [];
  for VUse in FindFieldUses(pProjectDb, pFieldName) do
    Include(Result, VUse.Kind);
end;

end.
