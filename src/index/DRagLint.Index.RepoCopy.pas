unit DRagLint.Index.RepoCopy;

{ drag-lint 1.56 -- lane CON-I: `index --project` copies the project's field repository into the
  project index and derives the caption concepts of the project's own forms
  (design 2026-11-27-three-place-search-caption-concepts-design.md, part 2: CC-1, CC-6).

  Two parts, each replaced as a whole:
    repository part -- concept_fields + concept_texts(place = repository), from the .dlrepo file;
    derived part    -- concept_texts(place = project) + concept_links, from dfm_objects /
                       dfm_properties / call_literal_args of the same index. No file is parsed.

  The step never fails an index run: every problem ends in a `repository: ..` / `concepts: ..`
  line and a repo_copy row. REPO_COPY_FORMAT and CONCEPT_DERIVED_FORMAT are NOT part of the
  indexer or the resolver fingerprint: raising one refreshes the copy on the next index run and
  costs no re-parse. }

interface

const
  /// <summary>Layout version of the repository part; a different stored value forces a new copy.</summary>
  REPO_COPY_FORMAT = 1;
  /// <summary>Layout version of the derived part; a different stored value forces a recompute.</summary>
  CONCEPT_DERIVED_FORMAT = 1;
  /// <summary>repo_copy.state: the copy rows match the repository file named by repo_path.</summary>
  REPO_COPY_COPIED = 'copied';
  /// <summary>repo_copy.state: the project names no field repository.</summary>
  REPO_COPY_NOT_CONFIGURED = 'not-configured';
  /// <summary>repo_copy.state: the configured repository file does not exist.</summary>
  REPO_COPY_MISSING = 'missing';
  /// <summary>repo_copy.state: the file exists but could not be read; the previous copy is kept.</summary>
  REPO_COPY_UNREADABLE = 'unreadable';
  /// <summary>schema_meta key holding the state of `files` the derived part was computed from.</summary>
  /// <remarks>Ends in `_unix` on purpose: it depends on parse times, and the index diff tool skips
  /// such keys.</remarks>
  CONCEPT_DERIVED_STAMP_KEY = 'concept_derived_stamp_unix';

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Hash,
  System.IOUtils,
  System.DateUtils,
  System.StrUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.Comp.Client,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite,
  DRagLint.FieldRepo.Locate,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.DfmReadSql;

const
  PLACE_REPOSITORY = 'repository';
  PLACE_PROJECT = 'project';
  TEXT_CAPTION = 'caption';
  TEXT_DESCRIPTION = 'description';
  TEXT_TABLE_DESCRIPTION = 'table-description';
  TEXT_DISPLAY_LABEL = 'display-label';
  TEXT_GRID_CAPTION = 'grid-caption';
  TEXT_HINT = 'hint';
  LINK_PERSISTENT_FIELD = 'persistent-field';
  LINK_GRID_COLUMN = 'grid-column';
  LINK_EDIT_CONTROL = 'edit-control';
  LINK_CODE = 'code';
  CONF_RESOLVED = 'resolved';
  CONF_BY_NAME = 'by-name-only';
  VIA_REPO_GRID = 'repo-grid';
  VIA_ORIGIN = 'origin';
  VIA_TABLE_NAME = 'table-name';
  VIA_SQL = 'sql';
  KEY_SEP = '|';
  PART_SEP = #1;
  BLANK = ' ';
  ACCELERATOR = '&';
  DOT = '.';
  HASH_BUFFER_SIZE = 65536;
  WAL_SUFFIX = '-wal';
  FIELD_SUFFIX = 'Field';
  AGGREGATE_CLASS = 'TAggregateField';
  DATA_SOURCE_CLASS = 'TDataSource';
  KIND_DATA = 'fkData';
  KIND_LIST = 'list';
  KIND_COLLECTION = 'collection';
  VALUE_TRUE = 'True';
  LIST_BREAK = #13#10;
  FIRST_ARGUMENT = 1;
  { A project text key = kind, table, field, text (AddText). }
  TEXT_KEY_PARTS = 4;
  { Positions of DOC_SUMMARY .. DOCUMENTATION in SQL_REPO_FIELDS. }
  COL_FIRST_DESCRIPTION = 9;
  COL_LAST_DESCRIPTION = 11;
  PLACEHOLDER_TEXTS: array[0..1] of string = ('Summary here', 'Remarks here');
  { The accessors whose first string argument is a field name (design 2.8, NQ-7). }
  NAME_ACCESSORS: array[0..2] of string = ('FieldByName', 'FindField', 'FieldValues');
  { The dataset classes `repo read-dfm` knows (DRagLint.FieldRepo.DfmRead.DATASET_CLASSES, private there). }
  DATASET_CLASSES: array[0..19] of string = ('TTable', 'TQuery', 'TStoredProc', 'TFDTable', 'TFDQuery', 'TFDMemTable',
    'TFDStoredProc', 'TClientDataSet', 'TdxMemData', 'TADOTable', 'TADOQuery', 'TADODataSet', 'TADOStoredProc',
    'TIBTable', 'TIBQuery', 'TIBDataSet', 'TSQLDataSet', 'TSQLQuery', 'TSQLTable', 'TSimpleDataSet');

  SQL_READ_ROW = 'SELECT state, repo_path, repo_sha256, repo_schema_version, copied_at_unix, copy_format, ' +
    'derived_format, derived_at_unix FROM repo_copy WHERE id = 1';
  SQL_WRITE_ROW = 'INSERT OR REPLACE INTO repo_copy (id, state, repo_path, repo_sha256, repo_size, repo_mtime_unix, ' +
    'repo_schema_version, copied_at_unix, checked_at_unix, copy_format, derived_format, derived_at_unix, last_error) ' +
    'VALUES (1, :state, :path, :sha, :size, :mtime, :ver, :copied, :checked, :cfmt, :dfmt, :derived, :err)';
  SQL_FILES_STAMP = 'SELECT id, sha256, parsed_at FROM files ORDER BY id';
  SQL_TABLE_EXISTS = 'SELECT COUNT(*) FROM sqlite_master WHERE name = :n';
  SQL_REPO_FIELDS = 'SELECT TABLE_NAME, FIELD_NAME, DISPLAY_LABEL, VISIBLE, FIELD_KIND, ISCALCULATED, ISLOOKUP, ' +
    'VAR_TYPE, STRING_SIZE, DOC_SUMMARY, DOC_REMARKS, DOCUMENTATION FROM DL_FIELDS_INFO ORDER BY TABLE_NAME, FIELD_NAME';
  SQL_REPO_DATASETS = 'SELECT UPDATE_TABLE_NAME, DESCRIPTION FROM DL_DATASETS_INFO ' +
    'WHERE UPDATE_TABLE_NAME IS NOT NULL AND DESCRIPTION IS NOT NULL ORDER BY DS_ID';
  SQL_REPO_GRID = 'SELECT FORM_NAME, VIEW_NAME, COLUMN_NAME, TABLE_NAME, FIELD_NAME FROM DL_GRID_COLUMNS';
  SQL_INSERT_FIELD = 'INSERT OR IGNORE INTO concept_fields (table_name, field_name, caption, type_text, field_kind, ' +
    'is_calculated, is_lookup, visible) VALUES (:t, :f, :caption, :type, :kind, :calc, :lookup, :visible)';
  SQL_INSERT_TEXT = 'INSERT OR IGNORE INTO concept_texts (place, text_kind, table_name, field_name, text, uses) ' +
    'VALUES (:place, :kind, :t, :f, :text, :uses)';
  SQL_INSERT_LINK = 'INSERT INTO concept_links (link_kind, confidence, table_name, field_name, file_id, line, col, ' +
    'form_name, form_class, component_name, dataset_name, symbol_id, enclosing_symbol_id, via, caption) ' +
    'VALUES (:kind, :conf, :t, :f, :file, :line, :col, :form, :class, :comp, :ds, :sym, :encl, :via, :caption)';
  SQL_FIELD_CAPTIONS = 'SELECT table_name, field_name, caption FROM concept_fields WHERE field_name <> ''''';
  SQL_COUNT_REPO_TEXTS = 'SELECT COUNT(*) FROM concept_texts WHERE place = ''repository''';
  SQL_DELETE_FIELDS = 'DELETE FROM concept_fields WHERE id > 0';
  SQL_DELETE_TEXTS = 'DELETE FROM concept_texts WHERE place = :place';
  SQL_DELETE_LINKS = 'DELETE FROM concept_links WHERE id > 0';
  SQL_FTS_REBUILD = 'INSERT INTO concept_texts_fts(concept_texts_fts) VALUES(''rebuild'')';
  SQL_DFM_FILES = 'SELECT id, path FROM files WHERE lower(path) LIKE ''%.dfm'' ORDER BY path';
  SQL_DFM_OBJECTS = 'SELECT name, class_name, depth, symbol_id, start_line, start_col FROM dfm_objects ' +
    'WHERE file_id = :f ORDER BY ordinal';
  SQL_DFM_PROPS = 'SELECT object_ordinal, parent, depth, name, value_text, value_kind FROM dfm_properties ' +
    'WHERE file_id = :f ORDER BY ordinal';
  SQL_LITERAL_ARGS = 'SELECT a.file_id, f.path, a.symbol_id, a.call_line, a.call_col, a.callee_name, a.receiver_text, ' +
    'a.value FROM call_literal_args a JOIN files f ON f.id = a.file_id ' +
    'WHERE a.arg_index = :arg AND a.lit_kind = :kind ORDER BY a.file_id, a.ordinal';

type
  /// <summary>What one run of the copy step did.</summary>
  TRepoCopyResult = record
    /// <summary>False when the index has no concept tables: nothing was read or written.</summary>
    Ran: Boolean;
    /// <summary>The repo_copy.state written (one of the REPO_COPY_* states).</summary>
    State: string;
    /// <summary>Full path LocateFieldRepository returned; '' when none is configured.</summary>
    RepoPath: string;
    /// <summary>Why the repository was not readable; '' otherwise.</summary>
    LastError: string;
    /// <summary>True when the repository part was written again.</summary>
    RepoCopied: Boolean;
    /// <summary>True when the derived part was computed again.</summary>
    DerivedCopied: Boolean;
    /// <summary>Repository fields copied (table rows not counted).</summary>
    Fields: Integer;
    /// <summary>Repository texts copied.</summary>
    RepoTexts: Integer;
    /// <summary>Project texts written by the derived part.</summary>
    ProjectTexts: Integer;
    /// <summary>Links written by the derived part.</summary>
    Links: Integer;
    /// <summary>Of Links, those with confidence by-name-only.</summary>
    ByNameLinks: Integer;
    /// <summary>Forms left out of the derived part because reading their rows raised.</summary>
    SkippedForms: Integer;
    /// <summary>The first reason a form was left out; '' when none was.</summary>
    SkipReason: string;
    /// <summary>The `repository: ..` line of the index run.</summary>
    /// <returns>One line without a line break.</returns>
    function RepositoryLine: string;
    /// <summary>The `concepts: ..` line of the index run.</summary>
    /// <returns>One line without a line break.</returns>
    function ConceptsLine: string;
  end;

  TRepoField = record
    Table: string;
    Field: string;
    Caption: string;
    TypeText: string;
    Kind: Integer;
    HasKind: Boolean;
    Calculated: Boolean;
    Lookup: Boolean;
    Visible: Boolean;
    Descriptions: TArray<string>;
  end;

  TRepoRow = record
    State: string;
    Path: string;
    Sha: string;
    Size: Int64;
    MTime: Int64;
    Version: Integer;
    CopiedAt: Int64;
    CopyFormat: Integer;
    DerivedFormat: Integer;
    DerivedAt: Int64;
    LastError: string;
  end;

  TDfmObj = record
    Name: string;
    ClassName: string;
    Depth: Integer;
    SymbolId: Int64;
    Line: Integer;
    Col: Integer;
    FirstProp: Integer;
  end;

  TDfmProp = record
    Obj: Integer;
    Parent: Integer;
    Depth: Integer;
    Name: string;
    Value: string;
    Kind: string;
  end;

  TPersistentField = record
    Obj: Integer;
    FieldName: string;
    Origin: string;
    IsData: Boolean;
  end;

  TDatasetInfo = record
    Name: string;
    FormName: string;
    FormClass: string;
    Table: string;      // table of calc / lookup fields and of data fields without a SELECT
    TableVia: string;
    HasSql: Boolean;
    Source: TDfmrSqlSource;
    Fields: TArray<TPersistentField>;
  end;

  { One link before it is written. }
  TLink = record
    Kind: string;
    Table: string;
    Field: string;
    Via: string;
    Resolved: Boolean;
    FileId: Int64;
    Line: Integer;
    Col: Integer;
    FormName: string;
    FormClass: string;
    Component: string;
    Dataset: string;
    SymbolId: Int64;
    EnclosingId: Int64;
    Caption: string;
  end;

  TRepoCopyRun = class  // dl:ok god-class@8bd9, high-response@8bd9 -- REVIEWED 2026-11-26 CON-I: one run of the copy step = one transaction over two parts; private to the unit; REVIEWED 2026-11-26 CON-I: the response set is FireDAC, dictionary and string calls of one private run
  strict private
    FStore: ISymbolStore;
    FConn: TFDConnection;
    FResult: TRepoCopyResult;
    FRepoFields: TArray<TRepoField>;
    FTableTexts: TList<TArray<string>>;                  // [table, description]
    FGrid: TDictionary<string, TArray<string>>;          // FORM|VIEW|COLUMN -> [table, field]
    FCaptions: TDictionary<string, string>;              // TABLE|FIELD of the repository copy -> caption
    FTextUses: TDictionary<string, Integer>;             // kind, table, field, text -> places
    FTextOrder: TList<string>;
    FDataSources: TDictionary<string, string>;           // data source of the form being read -> DataSet
    FFormDatasets: TList<TDatasetInfo>;                  // datasets of the form being read
    FUnitDatasets: TDictionary<string, TDatasetInfo>;    // unit stem|DATASET -> dataset, for code links
    FObjs: TArray<TDfmObj>;
    FProps: TArray<TDfmProp>;
    FIsField: TArray<Boolean>;
    FLinkQuery: TFDQuery;
    FFileId: Int64;
    function NewQuery(pConn: TFDConnection; const pSql: string): TFDQuery;
    function TableExists(pConn: TFDConnection; const pName: string): Boolean;
    function ReadRow: TRepoRow;
    procedure WriteRow(const pRow: TRepoRow);
    function FilesStamp: string;
    procedure LoadRepository(const pPath: string; pFields: Boolean; out pVersion: Integer);
    procedure WriteRepositoryPart;
    procedure InsertText(pQuery: TFDQuery; const pPlace, pKind, pTable, pField, pText: string; pUses: Integer);
    procedure LoadCaptions;
    procedure WriteDerivedPart;
    procedure LoadFormRows(pFileId: Int64);
    function Prop(pObject: Integer; const pName: string): string;
    function ListText(pRow: Integer): string;
    function ReadDataset(pObject: Integer; out pDataset: TDatasetInfo): Boolean;
    procedure ReadForm(pFileId: Int64; const pPath: string);
    function FindDataset(const pDataSource: string; out pDataset: TDatasetInfo): Boolean;
    function FormLink(const pKind: string; pObject: Integer): TLink;
    procedure EmitFields(const pDataset: TDatasetInfo);
    procedure EmitViewColumns(pView: Integer; const pDataSource: string);
    procedure EmitGridItems(pGrid, pColumns: Integer; const pDataSource: string);
    procedure EmitBound(var pLink: TLink; const pDataSource, pFieldName: string);
    procedure EmitCodeLinks;
    procedure AddLink(const pLink: TLink);
    procedure AddText(const pKind, pTable, pField, pText: string);
    procedure FlushTexts;
  public
    constructor Create(const pStore: ISymbolStore);
    destructor Destroy; override;
    function Execute(const pProjectFile: string): TRepoCopyResult;
  end;

{ ---- text helpers ---- }

function UnixNow: Int64;
begin
  Result := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now));
end;

{ Trimmed, inner runs of white space collapsed to one blank. }
function CleanText(const pText: string): string;
var
  VChar: Char;
  VGap: Boolean;
  VBuilder: TStringBuilder;
begin
  VBuilder := TStringBuilder.Create;
  try
    VGap := False;
    for VChar in pText.Trim do
      if VChar <= BLANK then
        VGap := True
      else
      begin
        if VGap then
          VBuilder.Append(BLANK);
        VGap := False;
        VBuilder.Append(VChar);
      end;
    Result := VBuilder.ToString;
  finally
    VBuilder.Free;
  end;
end;

{ A caption without its one accelerator mark: `&&` becomes `&`, the first single `&` goes. }
function StripAccelerator(const pText: string): string;
var
  VAt: Integer;
  VStripped: Boolean;
  VBuilder: TStringBuilder;
begin
  VBuilder := TStringBuilder.Create;
  try
    VStripped := False;
    VAt := 1;
    while VAt <= Length(pText) do
    begin
      if (pText[VAt] = ACCELERATOR) and (VAt < Length(pText)) and (pText[VAt + 1] = ACCELERATOR) then
      begin
        VBuilder.Append(ACCELERATOR);
        Inc(VAt);
      end
      else if (pText[VAt] = ACCELERATOR) and not VStripped then
        VStripped := True
      else
        VBuilder.Append(pText[VAt]);
      Inc(VAt);
    end;
    Result := VBuilder.ToString;
  finally
    VBuilder.Free;
  end;
end;

function FieldKey(const pTable, pField: string): string;
begin
  Result := UpperCase(pTable) + KEY_SEP + UpperCase(pField);
end;

function IsTrue(const pValue: string): Boolean;
begin
  Result := SameText(pValue, VALUE_TRUE) or (pValue = '1');
end;

{ SHA-256 over the file, followed by its non-empty -wal: an uncheckpointed write must change the hash. }
function RepositoryHash(const pPath: string; out pSize: Int64): string;
var
  VHash: THashSHA2;

  procedure Feed(const pFile: string; var pTotal: Int64);
  var
    VStream: TFileStream;
    VBuffer: TBytes;
    VRead: Integer;
  begin
    VStream := TFileStream.Create(pFile, fmOpenRead or fmShareDenyNone);
    try
      SetLength(VBuffer, HASH_BUFFER_SIZE);
      repeat
        VRead := VStream.Read(VBuffer, 0, HASH_BUFFER_SIZE);
        if VRead > 0 then
          VHash.Update(VBuffer, VRead);
        Inc(pTotal, VRead);
      until VRead <= 0;
    finally
      VStream.Free;
    end;
  end;

var
  VWalSize: Int64;
begin
  VHash := THashSHA2.Create(SHA256);  // dl:ok object-leak@552d -- REVIEWED 2026-11-26 CON-I: THashSHA2 is a record, there is nothing to free
  pSize := 0;
  VWalSize := 0;
  Feed(pPath, pSize);
  if TFile.Exists(pPath + WAL_SUFFIX) and (TFile.GetSize(pPath + WAL_SUFFIX) > 0) then
    Feed(pPath + WAL_SUFFIX, VWalSize);
  Result := VHash.HashAsString;
end;

{ ---- TRepoCopyResult ---- }

function TRepoCopyResult.RepositoryLine: string;
begin
  if State = REPO_COPY_NOT_CONFIGURED then
    Result := 'repository: not configured'
  else if State = REPO_COPY_MISSING then
    Result := 'repository: not found: ' + RepoPath
  else if State = REPO_COPY_UNREADABLE then
    Result := Format('repository: not readable: %s (%s); previous copy kept', [RepoPath, LastError])
  else if RepoCopied then
    Result := Format('repository: copied %d fields, %d texts from %s', [Fields, RepoTexts, RepoPath])
  else
    Result := Format('repository: unchanged (%s)', [RepoPath]);
end;

function TRepoCopyResult.ConceptsLine: string;
begin
  if not DerivedCopied then
    Exit('concepts: unchanged');
  Result := Format('concepts: %d project texts, %d links (%d by name only)', [ProjectTexts, Links, ByNameLinks]);
  if SkippedForms > 0 then
    Result := Result + Format('; %d form(s) skipped (%s)', [SkippedForms, SkipReason]);
end;

{ ---- TRepoCopyRun ---- }

constructor TRepoCopyRun.Create(const pStore: ISymbolStore);
begin
  inherited Create;
  FStore := pStore;
  FConn := (pStore as TSQLiteSymbolStore).GetConnection;
  FGrid := TDictionary<string, TArray<string>>.Create;
  FTableTexts := TList<TArray<string>>.Create;
  FCaptions := TDictionary<string, string>.Create;
  FTextUses := TDictionary<string, Integer>.Create;
  FTextOrder := TList<string>.Create;
  FDataSources := TDictionary<string, string>.Create;
  FFormDatasets := TList<TDatasetInfo>.Create;
  FUnitDatasets := TDictionary<string, TDatasetInfo>.Create;
end;

destructor TRepoCopyRun.Destroy;
begin
  FLinkQuery.Free;
  FUnitDatasets.Free;
  FFormDatasets.Free;
  FDataSources.Free;
  FTextOrder.Free;
  FTextUses.Free;
  FCaptions.Free;
  FTableTexts.Free;
  FGrid.Free;
  inherited;
end;

function TRepoCopyRun.NewQuery(pConn: TFDConnection; const pSql: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := pConn;
  Result.ResourceOptions.MacroCreate := False;
  Result.ResourceOptions.MacroExpand := False;
  Result.ResourceOptions.EscapeExpand := False;
  Result.FetchOptions.Unidirectional := True;
  Result.SQL.Text := pSql;
end;

function TRepoCopyRun.TableExists(pConn: TFDConnection; const pName: string): Boolean;
begin
  Result := pConn.ExecSQLScalar(SQL_TABLE_EXISTS, [pName]) > 0;
end;

function TRepoCopyRun.ReadRow: TRepoRow;
var
  VQuery: TFDQuery;
begin
  Result := Default(TRepoRow);
  VQuery := NewQuery(FConn, SQL_READ_ROW);
  try
    VQuery.Open;
    if VQuery.Eof then
      Exit;
    Result.State := VQuery.Fields[0].AsString;
    Result.Path := VQuery.Fields[1].AsString;
    Result.Sha := VQuery.Fields[2].AsString;
    Result.Version := VQuery.Fields[3].AsInteger;
    Result.CopiedAt := VQuery.Fields[4].AsLargeInt;
    Result.CopyFormat := VQuery.Fields[5].AsInteger;
    Result.DerivedFormat := VQuery.Fields[6].AsInteger;
    Result.DerivedAt := VQuery.Fields[7].AsLargeInt;
  finally
    VQuery.Free;
  end;
end;

procedure TRepoCopyRun.WriteRow(const pRow: TRepoRow);
var
  VQuery: TFDQuery;
begin
  VQuery := NewQuery(FConn, SQL_WRITE_ROW);
  try
    VQuery.ParamByName('state').AsString := pRow.State;
    VQuery.ParamByName('path').AsWideMemo := pRow.Path;
    VQuery.ParamByName('sha').AsString := pRow.Sha;
    VQuery.ParamByName('size').AsLargeInt := pRow.Size;
    VQuery.ParamByName('mtime').AsLargeInt := pRow.MTime;
    VQuery.ParamByName('ver').AsInteger := pRow.Version;
    VQuery.ParamByName('copied').AsLargeInt := pRow.CopiedAt;
    VQuery.ParamByName('checked').AsLargeInt := UnixNow;
    VQuery.ParamByName('cfmt').AsInteger := pRow.CopyFormat;
    VQuery.ParamByName('dfmt').AsInteger := pRow.DerivedFormat;
    VQuery.ParamByName('derived').AsLargeInt := pRow.DerivedAt;
    VQuery.ParamByName('err').AsWideMemo := pRow.LastError;
    VQuery.ExecSQL;
  finally
    VQuery.Free;
  end;
end;

{ The state of `files` the derived part depends on: a parsed, added or evicted file changes it. }
function TRepoCopyRun.FilesStamp: string;
var
  VQuery: TFDQuery;
  VHash: THashSHA2;
begin
  VHash := THashSHA2.Create(SHA256);  // dl:ok object-leak@552d -- REVIEWED 2026-11-26 CON-I: THashSHA2 is a record, there is nothing to free
  VQuery := NewQuery(FConn, SQL_FILES_STAMP);
  try
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VHash.Update(VQuery.Fields[0].AsString + KEY_SEP + VQuery.Fields[1].AsString + KEY_SEP + VQuery.Fields[2].AsString +
        PART_SEP);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
  Result := VHash.HashAsString;
end;

{ Reads what the two parts need from the repository file: the fields and table descriptions (pFields) and the grid
  column bindings (always). Raises when the file is not a readable repository. }
procedure TRepoCopyRun.LoadRepository(const pPath: string; pFields: Boolean; out pVersion: Integer);
var
  VRepo: TFDConnection;
  VQuery: TFDQuery;
  VField: TRepoField;
  VColumn: Integer;
  VText: string;
begin
  FRepoFields := nil;
  FTableTexts.Clear;
  FGrid.Clear;
  VRepo := OpenRepository(pPath, True);
  try
    pVersion := RepoSchemaVersion(VRepo);
    if pFields then
    begin
      VQuery := NewQuery(VRepo, SQL_REPO_FIELDS);
      try
        VQuery.Open;
        while not VQuery.Eof do
        begin
          VField := Default(TRepoField);
          VField.Table := VQuery.Fields[0].AsString.Trim;
          VField.Field := VQuery.Fields[1].AsString.Trim;
          VField.Caption := CleanText(VQuery.Fields[2].AsString);
          VField.Visible := VQuery.Fields[3].IsNull or IsTrue(VQuery.Fields[3].AsString);
          VField.HasKind := not VQuery.Fields[4].IsNull;
          VField.Kind := VQuery.Fields[4].AsInteger;
          VField.Calculated := IsTrue(VQuery.Fields[5].AsString);
          VField.Lookup := IsTrue(VQuery.Fields[6].AsString);
          VField.TypeText := VQuery.Fields[7].AsString.Trim;
          if (VField.TypeText <> '') and (VQuery.Fields[8].AsInteger > 0) then
            VField.TypeText := Format('%s(%d)', [VField.TypeText, VQuery.Fields[8].AsInteger]);
          for VColumn := COL_FIRST_DESCRIPTION to COL_LAST_DESCRIPTION do
          begin
            VText := CleanText(VQuery.Fields[VColumn].AsString);
            if (VText <> '') and not MatchText(VText, PLACEHOLDER_TEXTS) then
              VField.Descriptions := VField.Descriptions + [VText];
          end;
          if (VField.Table <> '') and (VField.Field <> '') then
            FRepoFields := FRepoFields + [VField];
          VQuery.Next;
        end;
      finally
        VQuery.Free;
      end;
      VQuery := NewQuery(VRepo, SQL_REPO_DATASETS);
      try
        VQuery.Open;
        while not VQuery.Eof do
        begin
          VText := CleanText(VQuery.Fields[1].AsString);
          if (VQuery.Fields[0].AsString.Trim <> '') and (VText <> '') then
            FTableTexts.Add([VQuery.Fields[0].AsString.Trim, VText]);
          VQuery.Next;
        end;
      finally
        VQuery.Free;
      end;
    end;
    if not TableExists(VRepo, REPO_TABLE_GRID_COLUMNS) then
      Exit;
    VQuery := NewQuery(VRepo, SQL_REPO_GRID);
    try
      VQuery.Open;
      while not VQuery.Eof do
      begin
        if (VQuery.Fields[3].AsString.Trim <> '') and (VQuery.Fields[4].AsString.Trim <> '') then
          FGrid.AddOrSetValue(UpperCase(VQuery.Fields[0].AsString + KEY_SEP + VQuery.Fields[1].AsString + KEY_SEP +
            VQuery.Fields[2].AsString), [VQuery.Fields[3].AsString.Trim, VQuery.Fields[4].AsString.Trim]);
        VQuery.Next;
      end;
    finally
      VQuery.Free;
    end;
  finally
    VRepo.Free;
  end;
end;

procedure TRepoCopyRun.InsertText(pQuery: TFDQuery; const pPlace, pKind, pTable, pField, pText: string; pUses: Integer);
begin
  pQuery.ParamByName('place').AsString := pPlace;
  pQuery.ParamByName('kind').AsString := pKind;
  pQuery.ParamByName('t').AsString := pTable;
  pQuery.ParamByName('f').AsString := pField;
  pQuery.ParamByName('text').AsWideMemo := pText;
  pQuery.ParamByName('uses').AsInteger := pUses;
  pQuery.ExecSQL;
end;

{ Inserts the repository part from FRepoFields / FTableTexts; the caller deleted the old rows. }
procedure TRepoCopyRun.WriteRepositoryPart;
var
  VFieldQuery: TFDQuery;
  VTextQuery: TFDQuery;
  VField: TRepoField;
  VTables: TDictionary<string, Boolean>;
  VText: string;
  VPair: TArray<string>;

  procedure InsertField(const pField: TRepoField);
  begin
    VFieldQuery.ParamByName('t').AsString := pField.Table;
    VFieldQuery.ParamByName('f').AsString := pField.Field;
    VFieldQuery.ParamByName('caption').AsWideMemo := pField.Caption;
    VFieldQuery.ParamByName('type').AsString := pField.TypeText;
    VFieldQuery.ParamByName('kind').DataType := ftInteger;
    if pField.HasKind then
      VFieldQuery.ParamByName('kind').AsInteger := pField.Kind
    else
      VFieldQuery.ParamByName('kind').Clear;
    VFieldQuery.ParamByName('calc').AsInteger := Ord(pField.Calculated);
    VFieldQuery.ParamByName('lookup').AsInteger := Ord(pField.Lookup);
    VFieldQuery.ParamByName('visible').AsInteger := Ord(pField.Visible);
    VFieldQuery.ExecSQL;
  end;

var
  VTableRow: TRepoField;
begin
  VTables := TDictionary<string, Boolean>.Create;
  VFieldQuery := NewQuery(FConn, SQL_INSERT_FIELD);
  VTextQuery := NewQuery(FConn, SQL_INSERT_TEXT);
  try
    for VField in FRepoFields do
    begin
      if VTables.TryAdd(UpperCase(VField.Table), True) then
      begin
        VTableRow := Default(TRepoField);
        VTableRow.Table := VField.Table;
        VTableRow.Visible := True;
        InsertField(VTableRow);
      end;
      InsertField(VField);
      if VField.Caption <> '' then
        InsertText(VTextQuery, PLACE_REPOSITORY, TEXT_CAPTION, VField.Table, VField.Field, VField.Caption, 1);
      for VText in VField.Descriptions do
        InsertText(VTextQuery, PLACE_REPOSITORY, TEXT_DESCRIPTION, VField.Table, VField.Field, VText, 1);
    end;
    for VPair in FTableTexts do
      if VTables.ContainsKey(UpperCase(VPair[0])) then
        InsertText(VTextQuery, PLACE_REPOSITORY, TEXT_TABLE_DESCRIPTION, VPair[0], '', VPair[1], 1);
  finally
    VTextQuery.Free;
    VFieldQuery.Free;
    VTables.Free;
  end;
  FResult.Fields := Length(FRepoFields);
  FResult.RepoTexts := FConn.ExecSQLScalar(SQL_COUNT_REPO_TEXTS);
end;

{ The (table, field) -> caption map of the repository copy as it now stands in the index. }
procedure TRepoCopyRun.LoadCaptions;
var
  VQuery: TFDQuery;
begin
  FCaptions.Clear;
  VQuery := NewQuery(FConn, SQL_FIELD_CAPTIONS);
  try
    VQuery.Open;
    while not VQuery.Eof do
    begin
      FCaptions.AddOrSetValue(FieldKey(VQuery.Fields[0].AsString, VQuery.Fields[1].AsString), VQuery.Fields[2].AsString);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ ---- derived part: DFM rows ---- }

procedure TRepoCopyRun.LoadFormRows(pFileId: Int64);
var
  VQuery: TFDQuery;
  VObjs: TList<TDfmObj>;
  VProps: TList<TDfmProp>;
  VObj: TDfmObj;
  VProp: TDfmProp;
  VAt: Integer;
begin
  VObjs := TList<TDfmObj>.Create;
  VProps := TList<TDfmProp>.Create;
  try
    VQuery := NewQuery(FConn, SQL_DFM_OBJECTS);
    try
      VQuery.ParamByName('f').AsLargeInt := pFileId;
      VQuery.Open;
      while not VQuery.Eof do
      begin
        VObj.Name := VQuery.Fields[0].AsString;
        VObj.ClassName := VQuery.Fields[1].AsString;
        VObj.Depth := VQuery.Fields[2].AsInteger;
        VObj.SymbolId := VQuery.Fields[3].AsLargeInt;
        VObj.Line := VQuery.Fields[4].AsInteger;
        VObj.Col := VQuery.Fields[5].AsInteger;
        VObj.FirstProp := -1;
        VObjs.Add(VObj);
        VQuery.Next;
      end;
    finally
      VQuery.Free;
    end;
    VQuery := NewQuery(FConn, SQL_DFM_PROPS);
    try
      VQuery.ParamByName('f').AsLargeInt := pFileId;
      VQuery.Open;
      while not VQuery.Eof do
      begin
        VProp.Obj := VQuery.Fields[0].AsInteger;
        VProp.Parent := VQuery.Fields[1].AsInteger;
        VProp.Depth := VQuery.Fields[2].AsInteger;
        VProp.Name := VQuery.Fields[3].AsString;
        VProp.Value := VQuery.Fields[4].AsString;
        VProp.Kind := VQuery.Fields[5].AsString;
        VProps.Add(VProp);
        VQuery.Next;
      end;
    finally
      VQuery.Free;
    end;
    FObjs := VObjs.ToArray;
    FProps := VProps.ToArray;
  finally
    VProps.Free;
    VObjs.Free;
  end;
  for VAt := High(FProps) downto 0 do
    if (FProps[VAt].Obj >= 0) and (FProps[VAt].Obj < Length(FObjs)) then
      FObjs[FProps[VAt].Obj].FirstProp := VAt;
  SetLength(FIsField, 0);
  SetLength(FIsField, Length(FObjs));
end;

function TRepoCopyRun.ListText(pRow: Integer): string;
var
  VAt: Integer;
  VLines: TStringList;
begin
  VLines := TStringList.Create;
  try
    VLines.LineBreak := LIST_BREAK;
    VAt := pRow + 1;
    while (VAt < Length(FProps)) and (FProps[VAt].Depth > FProps[pRow].Depth) do
    begin
      if FProps[VAt].Parent = pRow then
        VLines.Add(FProps[VAt].Value);
      Inc(VAt);
    end;
    Result := TrimRight(VLines.Text);
  finally
    VLines.Free;
  end;
end;

{ An object-level property of an object, as `repo read-dfm` reads it; '' when absent. }
function TRepoCopyRun.Prop(pObject: Integer; const pName: string): string;
var
  VAt: Integer;
begin
  Result := '';
  if (pObject < 0) or (pObject > High(FObjs)) then
    Exit;
  VAt := FObjs[pObject].FirstProp;
  while (VAt >= 0) and (VAt < Length(FProps)) and (FProps[VAt].Obj = pObject) do
  begin
    if (FProps[VAt].Depth = 0) and SameText(FProps[VAt].Name, pName) then
      Exit(if FProps[VAt].Kind = KIND_LIST then ListText(VAt) else FProps[VAt].Value);
    Inc(VAt);
  end;
end;

{ A dataset = a known dataset class, or any component with a persistent field child. Its table follows
  DRagLint.FieldRepo.DfmReadPlan.SourceOf: UpdateTableName, TableName, then a SELECT over one table. }
function TRepoCopyRun.ReadDataset(pObject: Integer; out pDataset: TDatasetInfo): Boolean;
var
  VAt: Integer;
  VField: TPersistentField;
  VKind: string;
  VTableName: string;
  VUpdateTable: string;
  VSql: string;
begin
  pDataset := Default(TDatasetInfo);
  VAt := pObject + 1;
  while (VAt < Length(FObjs)) and (FObjs[VAt].Depth > FObjs[pObject].Depth) do
  begin
    if (FObjs[VAt].Depth = FObjs[pObject].Depth + 1) and EndsText(FIELD_SUFFIX, FObjs[VAt].ClassName)
      and (Prop(VAt, 'FieldName') <> '') then
    begin
      VKind := Prop(VAt, 'FieldKind');
      VField.Obj := VAt;
      VField.FieldName := Prop(VAt, 'FieldName');
      VField.Origin := Prop(VAt, 'Origin');
      VField.IsData := ((VKind = '') or SameText(VKind, KIND_DATA)) and not SameText(FObjs[VAt].ClassName, AGGREGATE_CLASS);
      if VKind = '' then
        VField.IsData := VField.IsData and not SameText(Prop(VAt, 'Lookup'), VALUE_TRUE)
          and not SameText(Prop(VAt, 'Calculated'), VALUE_TRUE);
      pDataset.Fields := pDataset.Fields + [VField];
      FIsField[VAt] := True;
    end;
    Inc(VAt);
  end;
  Result := MatchText(FObjs[pObject].ClassName, DATASET_CLASSES) or (Length(pDataset.Fields) > 0);
  if not Result then
    Exit;
  pDataset.Name := FObjs[pObject].Name;
  pDataset.FormName := FObjs[0].Name;
  pDataset.FormClass := FObjs[0].ClassName;
  VUpdateTable := Prop(pObject, 'UpdateOptions.UpdateTableName');
  VTableName := Prop(pObject, 'TableName');
  VSql := Prop(pObject, 'SQL.Strings');
  pDataset.HasSql := (VTableName = '') and (VSql <> '');
  if pDataset.HasSql then
    pDataset.Source := ReadSelectSource(VSql);
  pDataset.TableVia := VIA_TABLE_NAME;
  if VUpdateTable <> '' then
    pDataset.Table := CleanTableName(VUpdateTable)
  else if VTableName <> '' then
    pDataset.Table := CleanTableName(VTableName)
  else if pDataset.HasSql and (pDataset.Source.Reason = '') and (Length(pDataset.Source.Tables) = 1) then
  begin
    pDataset.Table := pDataset.Source.Tables[0].Name;
    pDataset.TableVia := VIA_SQL;
  end;
end;

{ The table column of a field name of a dataset, as DRagLint.FieldRepo.DfmReadPlan.FieldSource decides it. }
function ResolveField(const pDataset: TDatasetInfo; const pFieldName: string; out pTable, pField, pVia: string): Boolean;
var
  VField: TPersistentField;
  VIsData: Boolean;
  VOrigin: string;
  VReason: string;
  VTable: string;
  VColumn: string;
begin
  VIsData := True;
  VOrigin := '';
  for VField in pDataset.Fields do
    if SameText(VField.FieldName, pFieldName.Trim) then
    begin
      VIsData := VField.IsData;
      VOrigin := VField.Origin;
      Break;
    end;
  pTable := pDataset.Table;
  pField := UpperCase(pFieldName.Trim);
  pVia := pDataset.TableVia;
  if VIsData and pDataset.HasSql and (pDataset.Source.Reason = '') then
  begin
    Result := SqlFieldColumn(pDataset.Source, pFieldName, VOrigin, pTable, pField, VReason);
    pVia := VIA_SQL;
    if Result and (VOrigin <> '') and not SqlFieldColumn(pDataset.Source, pFieldName, '', VTable, VColumn, VReason) then
      pVia := VIA_ORIGIN;
  end
  else
    Result := pTable <> '';
  if Result then
    Exit;
  pTable := '';
  pField := pFieldName.Trim;
  pVia := '';
end;

{ The dataset a data source name of the form being read points at; False for a data source of another form. }
function TRepoCopyRun.FindDataset(const pDataSource: string; out pDataset: TDatasetInfo): Boolean;
var
  VName: string;
  VDataset: TDatasetInfo;
begin
  pDataset := Default(TDatasetInfo);
  if not FDataSources.TryGetValue(UpperCase(pDataSource.Trim), VName) then
    Exit(False);
  for VDataset in FFormDatasets do
    if SameText(VDataset.Name, VName.Trim) then
    begin
      pDataset := VDataset;
      Exit(True);
    end;
  Result := False;
end;

function TRepoCopyRun.FormLink(const pKind: string; pObject: Integer): TLink;
begin
  Result := Default(TLink);
  Result.Kind := pKind;
  Result.FileId := FFileId;
  Result.Line := FObjs[pObject].Line;  // dl:ok index-possibly-out-of-range@81d7 -- REVIEWED 2026-11-26 CON-I: pObject is an object ordinal the callers enumerate over FObjs; ReadForm leaves when FObjs is empty
  Result.Col := FObjs[pObject].Col;
  Result.FormName := FObjs[0].Name;
  Result.FormClass := FObjs[0].ClassName;
  Result.Component := FObjs[pObject].Name;
  Result.SymbolId := FObjs[pObject].SymbolId;
end;

procedure TRepoCopyRun.EmitFields(const pDataset: TDatasetInfo);
var
  VField: TPersistentField;
  VLink: TLink;
begin
  for VField in pDataset.Fields do
  begin
    VLink := FormLink(LINK_PERSISTENT_FIELD, VField.Obj);
    VLink.Dataset := pDataset.Name;
    VLink.Resolved := ResolveField(pDataset, VField.FieldName, VLink.Table, VLink.Field, VLink.Via);
    VLink.Caption := CleanText(Prop(VField.Obj, 'DisplayLabel'));
    AddLink(VLink);
    AddText(TEXT_DISPLAY_LABEL, VLink.Table, VLink.Field, VLink.Caption);
  end;
end;

{ Finishes a grid column or edit control link: its dataset and table, then the write. }
procedure TRepoCopyRun.EmitBound(var pLink: TLink; const pDataSource, pFieldName: string);
var
  VDataset: TDatasetInfo;
begin
  pLink.Dataset := pDataSource.Trim;
  pLink.Field := pFieldName.Trim;
  if FindDataset(pDataSource, VDataset) then
  begin
    pLink.Dataset := VDataset.Name;
    pLink.Resolved := ResolveField(VDataset, pFieldName, pLink.Table, pLink.Field, pLink.Via);
  end;
  AddLink(pLink);
end;

{ A data-aware view (cxGrid view, tree list): its direct children bound with DataBinding.FieldName are the columns. }
procedure TRepoCopyRun.EmitViewColumns(pView: Integer; const pDataSource: string);
var
  VAt: Integer;
  VLink: TLink;
  VFieldName: string;
  VBinding: TArray<string>;
  VHint: string;
  VDataset: TDatasetInfo;
begin
  VAt := pView + 1;
  while (VAt < Length(FObjs)) and (FObjs[VAt].Depth > FObjs[pView].Depth) do
  begin
    VFieldName := Prop(VAt, 'DataBinding.FieldName').Trim;
    if (FObjs[VAt].Depth = FObjs[pView].Depth + 1) and (VFieldName <> '') then
    begin
      VLink := FormLink(LINK_GRID_COLUMN, VAt);
      VLink.Caption := CleanText(StripAccelerator(Prop(VAt, 'Caption')));
      VHint := CleanText(Prop(VAt, 'Hint'));
      if FGrid.TryGetValue(UpperCase(VLink.FormName + KEY_SEP + FObjs[pView].Name + KEY_SEP + VLink.Component), VBinding) then
      begin
        VLink.Dataset := if FindDataset(pDataSource, VDataset) then VDataset.Name else pDataSource.Trim;
        VLink.Table := VBinding[0];
        VLink.Field := VBinding[1];
        VLink.Via := VIA_REPO_GRID;
        VLink.Resolved := True;
        AddLink(VLink);
      end
      else
        EmitBound(VLink, pDataSource, VFieldName);
      AddText(TEXT_GRID_CAPTION, VLink.Table, VLink.Field, VLink.Caption);
      AddText(TEXT_HINT, VLink.Table, VLink.Field, VHint);
    end;
    Inc(VAt);
  end;
end;

{ A TDBGrid: the items of its Columns collection with a FieldName are the columns. }
procedure TRepoCopyRun.EmitGridItems(pGrid, pColumns: Integer; const pDataSource: string);
var
  VItem: Integer;
  VAt: Integer;
  VIndex: Integer;
  VLink: TLink;
  VFieldName: string;
begin
  VIndex := 0;
  VItem := pColumns + 1;
  while (VItem < Length(FProps)) and (FProps[VItem].Depth > FProps[pColumns].Depth) do
  begin
    if FProps[VItem].Parent = pColumns then
    begin
      VLink := FormLink(LINK_GRID_COLUMN, pGrid);
      VLink.Component := Format('%s.Columns[%d]', [FObjs[pGrid].Name, VIndex]);
      VLink.SymbolId := 0;
      VFieldName := '';
      VAt := VItem + 1;
      while (VAt < Length(FProps)) and (FProps[VAt].Depth > FProps[VItem].Depth) do
      begin
        if (FProps[VAt].Parent = VItem) and SameText(FProps[VAt].Name, 'FieldName') then
          VFieldName := FProps[VAt].Value.Trim
        else if (FProps[VAt].Parent = VItem) and SameText(FProps[VAt].Name, 'Title.Caption') then
          VLink.Caption := CleanText(StripAccelerator(FProps[VAt].Value));
        Inc(VAt);
      end;
      if VFieldName <> '' then
      begin
        EmitBound(VLink, pDataSource, VFieldName);
        AddText(TEXT_GRID_CAPTION, VLink.Table, VLink.Field, VLink.Caption);
      end;
      Inc(VIndex);
    end;
    Inc(VItem);
  end;
end;

procedure TRepoCopyRun.ReadForm(pFileId: Int64; const pPath: string);
var
  VAt: Integer;
  VRow: Integer;
  VDataset: TDatasetInfo;
  VLink: TLink;
  VSource: string;
  VFieldName: string;
  VStem: string;
begin
  FFileId := pFileId;
  LoadFormRows(pFileId);
  FDataSources.Clear;
  FFormDatasets.Clear;
  if Length(FObjs) = 0 then
    Exit;
  VStem := LowerCase(ChangeFileExt(pPath, ''));
  for VAt := 1 to High(FObjs) do
    if ReadDataset(VAt, VDataset) then
    begin
      FFormDatasets.Add(VDataset);
      FUnitDatasets.AddOrSetValue(VStem + KEY_SEP + UpperCase(VDataset.Name), VDataset);
    end
    else if SameText(FObjs[VAt].ClassName, DATA_SOURCE_CLASS) then
      FDataSources.AddOrSetValue(UpperCase(FObjs[VAt].Name), Prop(VAt, 'DataSet'));
  for VDataset in FFormDatasets do
    EmitFields(VDataset);
  for VAt := 1 to High(FObjs) do
  begin
    if FIsField[VAt] then
      Continue;
    VSource := Prop(VAt, 'DataController.DataSource');
    if VSource <> '' then
    begin
      EmitViewColumns(VAt, VSource);
      Continue;
    end;
    VSource := Prop(VAt, 'DataSource');
    VRow := FObjs[VAt].FirstProp;
    while (VSource <> '') and (VRow >= 0) and (VRow < Length(FProps)) and (FProps[VRow].Obj = VAt) do
    begin
      if (FProps[VRow].Depth = 0) and (FProps[VRow].Kind = KIND_COLLECTION) and SameText(FProps[VRow].Name, 'Columns') then
        EmitGridItems(VAt, VRow, VSource);
      Inc(VRow);
    end;
    VFieldName := Prop(VAt, 'DataBinding.DataField');
    if VFieldName <> '' then
      VSource := Prop(VAt, 'DataBinding.DataSource')
    else
      VFieldName := Prop(VAt, 'DataField');
    if (VFieldName = '') or (VSource = '') then
      Continue;
    VLink := FormLink(LINK_EDIT_CONTROL, VAt);
    EmitBound(VLink, VSource, VFieldName);
    AddText(TEXT_HINT, VLink.Table, VLink.Field, CleanText(Prop(VAt, 'Hint')));
  end;
end;

{ Name literals: the first string argument of FieldByName / FindField / FieldValues (design 2.8, source 2). }
procedure TRepoCopyRun.EmitCodeLinks;
var
  VQuery: TFDQuery;
  VLink: TLink;
  VReceiver: string;
  VDataset: TDatasetInfo;
  VAccessor: string;
  VName: string;
  VValue: string;
begin
  if not FStore.HasV156Facts then
    Exit;
  VQuery := NewQuery(FConn, SQL_LITERAL_ARGS);
  try
    VQuery.ParamByName('arg').AsInteger := FIRST_ARGUMENT;
    VQuery.ParamByName('kind').AsString := CLA_KIND_STRING;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VAccessor := '';
      for VName in NAME_ACCESSORS do
        if SameText(VName, VQuery.Fields[5].AsString) then
          VAccessor := VName;
      if (VAccessor <> '') and (VQuery.Fields[7].AsString.Trim <> '') then
      begin
        VLink := Default(TLink);
        VLink.Kind := LINK_CODE;
        VLink.FileId := VQuery.Fields[0].AsLargeInt;
        VLink.EnclosingId := VQuery.Fields[2].AsLargeInt;
        VLink.Line := VQuery.Fields[3].AsInteger;
        VLink.Col := VQuery.Fields[4].AsInteger;
        VLink.Via := VAccessor;
        VLink.Dataset := VQuery.Fields[6].AsString.Trim;
        VLink.Field := VQuery.Fields[7].AsString.Trim;
        VReceiver := VLink.Dataset.Substring(VLink.Dataset.LastIndexOf(DOT) + 1).Trim;
        if FUnitDatasets.TryGetValue(LowerCase(ChangeFileExt(VQuery.Fields[1].AsString, '')) + KEY_SEP + UpperCase(VReceiver),
          VDataset) then
        begin
          VLink.FormName := VDataset.FormName;
          VLink.FormClass := VDataset.FormClass;
          VValue := VLink.Field; // a copy: ResolveField clears its out parameters first
          VLink.Resolved := ResolveField(VDataset, VValue, VLink.Table, VLink.Field, VName);
          { With a repository the table must have the field; without one a persistent field must state it. }
          if VLink.Resolved and (FCaptions.Count > 0) then
            VLink.Resolved := FCaptions.ContainsKey(FieldKey(VLink.Table, VLink.Field))
          else if VLink.Resolved then
            VLink.Resolved := Length(VDataset.Fields) > 0;
          if not VLink.Resolved then
          begin
            VLink.Table := '';
            VLink.Field := VValue;
          end;
        end;
        AddLink(VLink);
      end;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TRepoCopyRun.AddLink(const pLink: TLink);

  procedure SetId(const pName: string; pId: Int64);
  begin
    FLinkQuery.ParamByName(pName).DataType := ftLargeint;
    if pId > 0 then
      FLinkQuery.ParamByName(pName).AsLargeInt := pId
    else
      FLinkQuery.ParamByName(pName).Clear;
  end;

begin
  FLinkQuery.ParamByName('kind').AsString := pLink.Kind;
  FLinkQuery.ParamByName('conf').AsString := if pLink.Resolved then CONF_RESOLVED else CONF_BY_NAME;
  FLinkQuery.ParamByName('t').AsString := pLink.Table;
  FLinkQuery.ParamByName('f').AsString := pLink.Field;
  FLinkQuery.ParamByName('file').AsLargeInt := pLink.FileId;
  FLinkQuery.ParamByName('line').AsInteger := pLink.Line;
  FLinkQuery.ParamByName('col').AsInteger := pLink.Col;
  FLinkQuery.ParamByName('form').AsString := pLink.FormName;
  FLinkQuery.ParamByName('class').AsString := pLink.FormClass;
  FLinkQuery.ParamByName('comp').AsString := pLink.Component;
  FLinkQuery.ParamByName('ds').AsString := pLink.Dataset;
  SetId('sym', pLink.SymbolId);
  SetId('encl', pLink.EnclosingId);
  FLinkQuery.ParamByName('via').AsString := pLink.Via;
  FLinkQuery.ParamByName('caption').AsWideMemo := pLink.Caption;
  FLinkQuery.ExecSQL;
  Inc(FResult.Links);
  if not pLink.Resolved then
    Inc(FResult.ByNameLinks);
end;

{ Counts a project text; one equal to the field's repository caption is not stored again (design 2.4). }
procedure TRepoCopyRun.AddText(const pKind, pTable, pField, pText: string);
var
  VKey: string;
  VCaption: string;
  VUses: Integer;
begin
  if pText = '' then
    Exit;
  if (pTable <> '') and FCaptions.TryGetValue(FieldKey(pTable, pField), VCaption) and (VCaption = pText) then
    Exit;
  VKey := pKind + PART_SEP + UpperCase(pTable) + PART_SEP + UpperCase(pField) + PART_SEP + pText;
  if FTextUses.TryGetValue(VKey, VUses) then
    FTextUses[VKey] := VUses + 1
  else
  begin
    FTextUses.Add(VKey, 1);
    FTextOrder.Add(VKey);
  end;
end;

procedure TRepoCopyRun.FlushTexts;
var
  VQuery: TFDQuery;
  VKey: string;
  VParts: TArray<string>;
  VUses: Integer;
begin
  VQuery := NewQuery(FConn, SQL_INSERT_TEXT);
  try
    for VKey in FTextOrder do
    begin
      VParts := VKey.Split([PART_SEP], TEXT_KEY_PARTS);
      if FTextUses.TryGetValue(VKey, VUses) and (Length(VParts) = TEXT_KEY_PARTS) then
        InsertText(VQuery, PLACE_PROJECT, VParts[0], VParts[1], VParts[2], VParts[TEXT_KEY_PARTS - 1], VUses);
    end;
  finally
    VQuery.Free;
  end;
  FResult.ProjectTexts := FTextOrder.Count;
end;

{ Deletes and computes the derived part again from the index tables. }
procedure TRepoCopyRun.WriteDerivedPart;
var
  VQuery: TFDQuery;
  VFiles: TList<TPair<Int64, string>>;
  VFile: TPair<Int64, string>;
begin
  FConn.ExecSQL(SQL_DELETE_TEXTS, [PLACE_PROJECT]);
  FConn.ExecSQL(SQL_DELETE_LINKS);
  LoadCaptions;
  FTextUses.Clear;
  FTextOrder.Clear;
  FUnitDatasets.Clear;
  FLinkQuery := NewQuery(FConn, SQL_INSERT_LINK);
  if not (TableExists(FConn, 'dfm_objects') and FStore.HasDfmProperties) then
    Exit;
  VFiles := TList<TPair<Int64, string>>.Create;
  try
    VQuery := NewQuery(FConn, SQL_DFM_FILES);
    try
      VQuery.Open;
      while not VQuery.Eof do
      begin
        VFiles.Add(TPair<Int64, string>.Create(VQuery.Fields[0].AsLargeInt, VQuery.Fields[1].AsString));
        VQuery.Next;
      end;
    finally
      VQuery.Free;
    end;
    for VFile in VFiles do
      try
        ReadForm(VFile.Key, VFile.Value);
      except
        on E: Exception do
        begin
          Inc(FResult.SkippedForms);
          if FResult.SkipReason = '' then
            FResult.SkipReason := ExtractFileName(VFile.Value) + ': ' + E.Message;
        end;
      end;
  finally
    VFiles.Free;
  end;
  EmitCodeLinks;
  FlushTexts;
end;

function TRepoCopyRun.Execute(const pProjectFile: string): TRepoCopyResult;
var
  VOld: TRepoRow;
  VNew: TRepoRow;
  VStamp: string;
  VHadPart: Boolean;
  VCopyRepo: Boolean;
  VDropRepo: Boolean;
  VDerive: Boolean;
begin
  FResult := Default(TRepoCopyResult);
  if not FStore.HasConceptTables then
    Exit(FResult);
  FResult.Ran := True;
  VOld := ReadRow;
  VNew := VOld;
  VNew.LastError := '';
  VNew.Path := LocateFieldRepository(pProjectFile, '');
  VHadPart := VOld.Sha <> '';
  VCopyRepo := False;
  if VNew.Path = '' then
    VNew.State := REPO_COPY_NOT_CONFIGURED
  else if not TFile.Exists(VNew.Path) then
    VNew.State := REPO_COPY_MISSING
  else
    try
      VNew.State := REPO_COPY_COPIED;
      VNew.MTime := DateTimeToUnix(TFile.GetLastWriteTimeUtc(VNew.Path));
      VNew.Sha := RepositoryHash(VNew.Path, VNew.Size);
      VCopyRepo := (VOld.State <> REPO_COPY_COPIED) or (VOld.Sha <> VNew.Sha) or (VOld.CopyFormat <> REPO_COPY_FORMAT);
    except
      on E: Exception do
      begin
        VNew.State := REPO_COPY_UNREADABLE;
        VNew.LastError := CleanText(E.Message);
      end;
    end;
  VDropRepo := VHadPart and ((VNew.State = REPO_COPY_NOT_CONFIGURED) or (VNew.State = REPO_COPY_MISSING));
  VStamp := FilesStamp;
  VDerive := VCopyRepo or VDropRepo or (VOld.DerivedFormat <> CONCEPT_DERIVED_FORMAT)
    or (FStore.GetMetaValue(CONCEPT_DERIVED_STAMP_KEY) <> VStamp);
  if (VNew.State = REPO_COPY_COPIED) and (VCopyRepo or VDerive) then
    try
      LoadRepository(VNew.Path, VCopyRepo, VNew.Version);
    except
      on E: Exception do
      begin
        VNew.State := REPO_COPY_UNREADABLE;
        VNew.LastError := CleanText(E.Message);
        VCopyRepo := False;
        VDerive := (VOld.DerivedFormat <> CONCEPT_DERIVED_FORMAT) or (FStore.GetMetaValue(CONCEPT_DERIVED_STAMP_KEY) <> VStamp);
      end;
    end;
  if VNew.State = REPO_COPY_UNREADABLE then
  begin
    { The previous copy rows stay, and so do the facts that describe them. }
    VNew.Sha := VOld.Sha;
    VNew.Version := VOld.Version;
  end
  else if VNew.State <> REPO_COPY_COPIED then
  begin
    VNew.Sha := '';
    VNew.Size := 0;
    VNew.MTime := 0;
    VNew.Version := 0;
    VNew.CopiedAt := 0;
    VNew.CopyFormat := 0;
  end;
  FConn.StartTransaction;
  try
    if VCopyRepo or VDropRepo then
    begin
      FConn.ExecSQL(SQL_DELETE_FIELDS);
      FConn.ExecSQL(SQL_DELETE_TEXTS, [PLACE_REPOSITORY]);
    end;
    if VCopyRepo then
    begin
      WriteRepositoryPart;
      VNew.CopiedAt := UnixNow;
      VNew.CopyFormat := REPO_COPY_FORMAT;
    end;
    if VDerive then
    begin
      WriteDerivedPart;
      VNew.DerivedFormat := CONCEPT_DERIVED_FORMAT;
      VNew.DerivedAt := UnixNow;
      FStore.SetMetaValue(CONCEPT_DERIVED_STAMP_KEY, VStamp);
    end;
    if (VCopyRepo or VDropRepo or VDerive) and TableExists(FConn, 'concept_texts_fts') then
      FConn.ExecSQL(SQL_FTS_REBUILD);
    WriteRow(VNew);
    FConn.Commit;
  except
    FConn.Rollback;
    raise;
  end;
  FResult.State := VNew.State;
  FResult.RepoPath := VNew.Path;
  FResult.LastError := VNew.LastError;
  FResult.RepoCopied := VCopyRepo;
  FResult.DerivedCopied := VDerive;
  Result := FResult;
end;

/// <summary>Refreshes repo_copy and the concept_* tables of a project index.</summary>
/// <param name="pStore">The project store, writable; must be the SQLite store.</param>
/// <param name="pProjectFile">Full path of the project file the index run was started with.</param>
/// <returns>What was done; Ran is False when the index has no concept tables.</returns>
/// <exception cref="Exception">A failure writing the index; the step's own transaction is rolled back
/// first. A repository that is missing or unreadable is NOT an error: it is a state.</exception>
/// <remarks>Not thread-safe. Opens the repository read-only and closes it before returning. The
/// repository part is skipped when the file's SHA-256 (main file + a non-empty -wal) equals the
/// stored one; the derived part is skipped when no row of `files` changed since it was computed.</remarks>
function RefreshRepoCopy(const pStore: ISymbolStore; const pProjectFile: string): TRepoCopyResult;
var
  VRun: TRepoCopyRun;
begin
  VRun := TRepoCopyRun.Create(pStore);
  try
    Result := VRun.Execute(pProjectFile);
  finally
    VRun.Free;
  end;
end;

/// <summary>The TIndexPassHooks repository-copy step: RefreshRepoCopy plus its two stdout lines.</summary>
/// <param name="pStore">The project store.</param>
/// <param name="pProjectFile">Full path of the project file.</param>
/// <remarks>Never raises: a failure is printed as `repository: copy step failed: ..` and the index
/// run goes on with its own exit code.</remarks>
procedure RunRepoCopyStep(const pStore: ISymbolStore; const pProjectFile: string);
var
  VResult: TRepoCopyResult;
begin
  try
    VResult := RefreshRepoCopy(pStore, pProjectFile);
    if not VResult.Ran then
      Exit;
    Writeln(VResult.RepositoryLine);
    Writeln(VResult.ConceptsLine);
  except
    on E: Exception do
      Writeln('repository: copy step failed: ' + E.Message);
  end;
end;

initialization
  TIndexPassHooks.RegisterRepoCopy(RunRepoCopyStep);

end.
