unit DRagLint.Lint.SchemaRules;

{ drag-lint 1.53 -- lane FR-LINT: the schema-aware lint rules 1 + 2 (design
  docs\superpowers\specs\2026-11-22-field-repository-v2-design.md section 6).

  schema-maxlen-drift  (rule 1) a <TABLE>_<FIELD>_MAXLEN constant whose value differs from the
                       column's char length, or a string literal longer than the char length
                       assigned to a resolved column target.
  schema-length-bound  (rule 2) Copy(x, i, N) assigned to a resolved target, or .Size / .MaxLength
                       := N on a resolved field, where N > char length; or a DFM TStringField /
                       TWideStringField persistent field whose Size differs from the char length.

  Schema facts come ONLY from the field repository (owner ruling FR-3), opened read-only through
  OpenRepository and never attached to the index connection. The index answers the code side:
  constants, refs, DFM objects / properties and link-orm's field_to_column rows.

  Target resolution is conservative; anything unresolved is silent:
    (1) a field linked by link-orm (field_to_column), or a property whose property-spec ref names
        such a field;
    (2) a DFM persistent field: dataset + FieldName, the dataset's table from
        UpdateOptions.UpdateTableName, else TableName;
    (3) <dataset>.FieldByName('<Y>') on such a dataset.
  Names are never matched bare: the dataset of a FieldByName and a constant used as N are the symbols
  the index BOUND at that site, and a ref whose name is no longer at its stored position (an edited,
  not reindexed file) is skipped. A property counts only when it writes the linked field directly (a
  setter may shorten the value). A local named t<FIELD> / fld<FIELD> is resolved by RunLocalNaming only
  (owner FR-6, 1.54 G-72: config schema_rules.local_naming_match, OFF by default). Only the statement text on
  the target's own line is read, so a statement that spans lines is silent. Not seen: a TableName / UpdateTableName assigned in code after the .dfm is loaded. }

interface

uses
  FireDAC.Comp.Client,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

const
  /// <summary>Rule 1 id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  SCHEMA_MAXLEN_DRIFT_RULE = 'schema-maxlen-drift';
  /// <summary>Rule 2 id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  SCHEMA_LENGTH_BOUND_RULE = 'schema-length-bound';

type
  /// <summary>What one run of the schema rules produced.</summary>
  TSchemaLintResult = record
    /// <summary>The findings of both rules, after DL_EXCEPTIONS suppression.</summary>
    Findings: TArray<TLintFinding>;
    /// <summary>`schema facts &lt;utc&gt; (&lt;source&gt;) from &lt;repository file name&gt;` when the
    /// rules ran against schema facts; '' when they stayed silent.</summary>
    Banner: string;
    /// <summary>Why the rules stayed silent ('' when they ran): no repository, a repository
    /// without schema facts, or one that could not be opened.</summary>
    Note: string;
    /// <summary>True when a repository IS configured but is missing or cannot be opened: the note is
    /// then shown always, so a wrong path never disables the rules unnoticed.</summary>
    Broken: Boolean;
  end;

/// <summary>Runs schema-maxlen-drift and schema-length-bound over a project index.</summary>
/// <param name="pStore">The project index; a non-SQLite store yields no findings.</param>
/// <param name="pRepoFile">The field repository file (DRagLint.FieldRepo.Locate); '' = none.</param>
/// <param name="pOnlyFileId">0 = the whole index (lint-all); else only findings anchored in that
/// file and in the .dfm beside it (lint &lt;file&gt;).</param>
/// <returns>The findings plus the banner, or an empty result with the silence note.</returns>
/// <remarks>Silent (no findings, Banner '') when pRepoFile is '', missing, unreadable, or holds
/// no schema facts (SchemaFacts.HasSchema). The repository is opened read-only and closed before
/// return. Not thread-safe; one call per run.</remarks>
function RunSchemaRules(const pStore: ISymbolStore; const pRepoFile: string;
  pOnlyFileId: Int64): TSchemaLintResult;

/// <summary>Finds the field repository of the project this run lints.</summary>
/// <param name="pStore">The project index; may be nil.</param>
/// <returns>The repository file (it need not exist); '' = none configured.</returns>
/// <remarks>For rules that have only the index: the project is --project of a lint / lint-all command line, else the
/// manifest section that owns the index, else &lt;dir&gt;\&lt;base&gt;.dproj for &lt;dir&gt;\_D-RAG\&lt;base&gt;.sqlite.
/// Not cached; see DRagLint.V154.SCHEMA.Support.</remarks>
function SchemaRepositoryOf(const pStore: ISymbolStore): string;

/// <summary>Opens a field repository read-only for lint.</summary>
/// <param name="pRepoFile">The repository file; '' = none.</param>
/// <param name="pNote">Receives why there is no connection; '' when there is one.</param>
/// <returns>The connection, owned by the caller; nil when the file is not configured, missing or unreadable.</returns>
function OpenSchemaRepository(const pRepoFile: string; out pNote: string): TFDConnection;

/// <summary>The note for a repository that holds no schema facts.</summary>
/// <param name="pRepoFile">The repository file.</param>
/// <returns>One line.</returns>
function NoSchemaFactsNote(const pRepoFile: string): string;

/// <summary>The banner of a run against schema facts.</summary>
/// <param name="pRepo">An open repository with schema facts.</param>
/// <param name="pRepoFile">The repository file.</param>
/// <returns>One line.</returns>
function SchemaFactsBanner(pRepo: TFDConnection; const pRepoFile: string): string;

/// <summary>Rules 1 and 2 on locals named after a field: tDIMABBR, fldDIMABBR (owner FR-6, G-72).</summary>
/// <param name="pStore">The project index; a non-SQLite store yields no findings.</param>
/// <param name="pRepoFile">The field repository file; '' = none.</param>
/// <param name="pFileId">The unit to check.</param>
/// <returns>schema-maxlen-drift and schema-length-bound findings.</returns>
/// <remarks>The caller asks only when the config turns schema_rules.local_naming_match on. A name counts when the part
/// after the prefix is upper case and every column of that name has one and the same char length.</remarks>
function RunLocalNaming(const pStore: ISymbolStore; const pRepoFile: string; pFileId: Int64): TArray<TLintFinding>;

/// <summary>Says on stderr what the schema rules did: the banner, or why they stayed silent.</summary>
/// <param name="pResult">What RunSchemaRules returned.</param>
/// <param name="pQuiet">True suppresses everything (lint --quiet).</param>
/// <remarks>At most one line per process, so a run over many files says it once. The banner and the note
/// of a Broken repository always show; the ordinary silence notes only with DRAGLINT_DEBUG set.
/// Not thread-safe; call from the main thread.</remarks>
procedure ReportSchemaRun(const pResult: TSchemaLintResult; pQuiet: Boolean);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.Stan.Error,
  DRagLint.Index.Manifest,
  DRagLint.Storage.SQLite,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.Locate,
  DRagLint.FieldRepo.Exceptions;

const
  SEVERITY_WARNING = 'warning';
  MAXLEN_SUFFIX = '_MAXLEN';
  { TStringField / TWideStringField.Size default; the streaming system omits Size = 20 from a .dfm. }
  STRING_FIELD_DEFAULT_SIZE = 20;
  { A <TABLE>_<FIELD> prefix with more underscores than this is not split (2^n repository probes). }
  MAX_PREFIX_UNDERSCORES = 6;
  CHAR_LENGTH_UNKNOWN = -1;
  { Copy(S, Index, Count): the count is the last of three arguments. }
  COPY_ARG_COUNT = 3;
  NOTE_NO_REPO = 'schema rules: no field repository';
  NOTE_NO_FACTS = 'schema rules: field repository %s holds no schema facts';
  NOTE_NOT_FOUND = 'schema rules: field repository %s not found';
  NOTE_OPEN_FAILED = 'schema rules: field repository %s cannot be opened: %s';
  PROP_SIZE = 'Size';
  PROP_MAXLEN = 'MaxLength';
  { G-72: the prefixes of a local named after a field, longest first. }
  LOCAL_PREFIXES: array[0..1] of string = ('fld', 't');
  DPROJ_EXT = '.dproj';
  DRAG_DIR = '_D-RAG';
  PROJECT_SWITCH = '--project';

type
  { What kind of target a symbol is: an ORM field / property takes `X := rhs`, a dataset field
    takes `X.AsString := rhs` and `X.Size := N`. }
  TTargetKind = (tkOrm, tkDatasetField);

  TColumnTarget = record
    Table: string;
    Column: string;
    DatasetKey: string;
    Kind: TTargetKind;
    CharLength: Integer;
  end;

  TDatasetInfo = record
    Table: string;
    DatasetKey: string;
  end;

  TSchemaScan = class  // dl:ok high-response@a48f -- REVIEWED 2026-11-22 FR-LINT: one private scan object per run; the response set is its SQL / dictionary / text helpers, each method one target source
  private
    FStore: ISymbolStore;
    FIndex: TFDConnection;
    FRepo: TFDConnection;
    FOnlyFileId: Int64;
    FOnlyDfmId: Int64;
    FExceptions: TArray<TFrException>;
    FLengths: TDictionary<string, Integer>;
    FLines: TDictionary<Int64, TArray<string>>;
    FDatasets: TDictionary<string, TDatasetInfo>;
    FDatasetSymbols: TDictionary<Int64, TDatasetInfo>;
    FTargets: TDictionary<Int64, TColumnTarget>;
    FSeen: TDictionary<string, Boolean>;
    FFindings: TList<TLintFinding>;
    function NewQuery(const pSql: string): TFDQuery;
    function TableExists(const pName: string): Boolean;
    function CharLength(const pTable, pColumn: string): Integer;
    function ConstValue(pFileId: Int64; pLine: Integer; const pName: string; out pValue: Integer): Boolean;
    function IntOrConst(pFileId: Int64; pLine: Integer; const pText: string; out pValue: Integer): Boolean;
    function RefLine(pFileId: Int64; pLine, pCol, pEndCol: Integer; const pName: string; out pText: string): Boolean;
    function FormFields(const pDfmPath, pName: string): TArray<Int64>;
    function LinesOf(pFileId: Int64): TArray<string>;
    function ResolveMaxLenPrefix(const pPrefix: string; out pTable, pColumn: string;
      out pLength: Integer): Boolean;
    procedure AddFinding(const pRule: string; pFileId: Int64; pLine, pCol: Integer;
      const pMessage: string; const pTarget: TColumnTarget; const pProp: string);
    procedure ScanConstants;
    procedure LoadDatasets;
    procedure ScanDfmFields;
    procedure ScanDfmField(pRow: TFDQuery);
    procedure AddWriteProperties(pFieldId: Int64; const pFieldName: string; const pTarget: TColumnTarget);
    procedure LoadOrmTargets;
    procedure ScanTargetRefs;
    procedure ScanFieldByName;
    function NamedLength(const pColumn: string; out pTable: string): Integer;
    procedure LoadLocalTargets;
    procedure CheckTail(pFileId: Int64; pLine, pCol: Integer; const pText: string; pFrom: Integer;
      const pTarget: TColumnTarget);
  public
    constructor Create(const pStore: ISymbolStore; pRepo: TFDConnection; pOnlyFileId: Int64);
    destructor Destroy; override;
    function Run: TArray<TLintFinding>;
    function RunLocals: TArray<TLintFinding>;
  end;

{ ---- pure text helpers ---- }

{ The full path without extension, so two units of one base name never share a dataset. }
function UnitKeyOfPath(const pPath: string): string;
begin
  Result := UpperCase(ChangeFileExt(pPath, ''));
end;

function StripOrmPrefix(const pName: string; pPrefix: Char): string;
begin
  { Mirrors DRagLint.Sql.OrmLinker.StripPrefix, so the names are the ones link-orm matched. }
  Result := if (Length(pName) >= 2) and (UpCase(pName[1]) = pPrefix) and CharInSet(pName[2], ['A'..'Z'])
    then Copy(pName, 2, MaxInt) else pName;
end;

function UnquoteDfm(const pValue: string): string;
begin
  Result := Trim(pValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
end;

function ParseIntSignature(const pSignature: string; out pValue: Integer): Boolean;
var
  VText: string;
  VPos: Integer;
begin
  VText := pSignature;
  VPos := LastDelimiter('=', VText);
  if VPos > 0 then
    VText := Copy(VText, VPos + 1, MaxInt);
  VText := Trim(VText);
  if (VText <> '') and (VText[Length(VText)] = ';') then
    VText := Trim(Copy(VText, 1, Length(VText) - 1));
  Result := TryStrToInt(VText, pValue);
end;

function SkipSpaces(const pText: string; pFrom: Integer): Integer;
begin
  Result := pFrom;
  while (Result <= Length(pText)) and CharInSet(pText[Result], [' ', #9]) do
    Inc(Result);
end;

function ReadIdent(const pText: string; var pPos: Integer): string;
var
  VStart: Integer;
begin
  VStart := pPos;
  while (pPos <= Length(pText)) and CharInSet(pText[pPos], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(pPos);
  Result := Copy(pText, VStart, pPos - VStart);
end;

{ The right-hand side of an assignment from pFrom: up to the first ';' or comment outside a string
  literal, trimmed. Text past a ';' is ignored. }
function StatementRhs(const pText: string; pFrom: Integer): string;
var
  VPos: Integer;
  VInQuote: Boolean;
begin
  VPos := pFrom;
  VInQuote := False;
  while VPos <= Length(pText) do
  begin
    if pText[VPos] = '''' then
      VInQuote := not VInQuote
    else if not VInQuote then
    begin
      if (pText[VPos] = ';') or (pText[VPos] = '{') then
        Break;
      if (VPos < Length(pText)) and (((pText[VPos] = '/') and (pText[VPos + 1] = '/')) or
        ((pText[VPos] = '(') and (pText[VPos + 1] = '*'))) then
        Break;
    end;
    Inc(VPos);
  end;
  Result := Trim(Copy(pText, pFrom, VPos - pFrom));
end;

{ True when pRhs is exactly one quoted literal; pLength = its character count. }
function PlainLiteralLength(const pRhs: string; out pLength: Integer): Boolean;
var
  VPos: Integer;
begin
  Result := False;
  pLength := 0;
  if (Length(pRhs) < 2) or (pRhs[1] <> '''') then
    Exit;
  VPos := 2;
  while VPos <= Length(pRhs) do
  begin
    if pRhs[VPos] = '''' then
    begin
      if (VPos < Length(pRhs)) and (pRhs[VPos + 1] = '''') then
      begin
        Inc(pLength);
        Inc(VPos, 2);
        Continue;
      end;
      Result := VPos = Length(pRhs);
      Exit;
    end;
    Inc(pLength);
    Inc(VPos);
  end;
end;

{ True when pRhs is exactly `Copy(a, b, c)`; pCount = the third argument's text. }
function CopyCountArg(const pRhs: string; out pCount: string): Boolean;
var
  VPos, VDepth, VArgStart: Integer;
  VArgs: TArray<string>;
  VInQuote: Boolean;
begin
  Result := False;
  pCount := '';
  VPos := 1;
  if not SameText(ReadIdent(pRhs, VPos), 'Copy') then
    Exit;
  VPos := SkipSpaces(pRhs, VPos);
  if (VPos > Length(pRhs)) or (pRhs[VPos] <> '(') then
    Exit;
  VDepth := 0;
  VInQuote := False;
  VArgStart := VPos + 1;
  VArgs := nil;
  while VPos <= Length(pRhs) do
  begin
    if pRhs[VPos] = '''' then
      VInQuote := not VInQuote
    else if not VInQuote then
      case pRhs[VPos] of
        '(', '[': Inc(VDepth);
        ')', ']':
          begin
            Dec(VDepth);
            if VDepth = 0 then
            begin
              VArgs := VArgs + [Trim(Copy(pRhs, VArgStart, VPos - VArgStart))];
              Result := (VPos = Length(pRhs)) and (Length(VArgs) = COPY_ARG_COUNT);
              if Result then
                pCount := VArgs[COPY_ARG_COUNT - 1];
              Exit;
            end;
          end;
        ',':
          if VDepth = 1 then
          begin
            VArgs := VArgs + [Trim(Copy(pRhs, VArgStart, VPos - VArgStart))];
            VArgStart := VPos + 1;
          end;
      end;
    Inc(VPos);
  end;
end;

{ After `FieldByName` (pFrom = the column past the name): `( '<NAME>' )` with a literal identifier
  name. pAfter = the column past the closing parenthesis. }
function FieldByNameColumn(const pText: string; pFrom: Integer; out pColumn: string;
  out pAfter: Integer): Boolean;
var
  VPos, VClose: Integer;
begin
  Result := False;
  pColumn := '';
  pAfter := 0;
  VPos := SkipSpaces(pText, pFrom);
  if (VPos > Length(pText)) or (pText[VPos] <> '(') then
    Exit;
  VPos := SkipSpaces(pText, VPos + 1);
  if (VPos > Length(pText)) or (pText[VPos] <> '''') then
    Exit;
  VClose := Pos('''', pText, VPos + 1);
  if VClose = 0 then
    Exit;
  pColumn := Copy(pText, VPos + 1, VClose - VPos - 1);
  VPos := SkipSpaces(pText, VClose + 1);
  Result := IsValidIdent(pColumn) and (VPos <= Length(pText)) and (pText[VPos] = ')');
  pAfter := VPos + 1;
end;

function IsDottedIdent(const pText: string): Boolean;
var
  VPart: string;
begin
  Result := pText <> '';
  for VPart in pText.Split(['.']) do
    Result := Result and IsValidIdent(VPart);
end;

{ ---- TSchemaScan ---- }

constructor TSchemaScan.Create(const pStore: ISymbolStore; pRepo: TFDConnection; pOnlyFileId: Int64);
begin
  inherited Create;
  FStore := pStore;
  FIndex := (pStore as TSQLiteSymbolStore).GetConnection;
  FRepo := pRepo;
  FOnlyFileId := pOnlyFileId;
  FLengths := TDictionary<string, Integer>.Create;
  FLines := TDictionary<Int64, TArray<string>>.Create;
  FDatasets := TDictionary<string, TDatasetInfo>.Create;
  FDatasetSymbols := TDictionary<Int64, TDatasetInfo>.Create;
  FTargets := TDictionary<Int64, TColumnTarget>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
  FFindings := TList<TLintFinding>.Create;
  FExceptions := LoadExceptions(FRepo);
end;

destructor TSchemaScan.Destroy;
begin
  FFindings.Free;
  FSeen.Free;
  FTargets.Free;
  FDatasetSymbols.Free;
  FDatasets.Free;
  FLines.Free;
  FLengths.Free;
  inherited;
end;

function TSchemaScan.NewQuery(const pSql: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := FIndex;
  Result.SQL.Text := pSql;
end;

function TSchemaScan.TableExists(const pName: string): Boolean;
var
  VQuery: TFDQuery;
begin
  VQuery := NewQuery('SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = :n');
  try
    VQuery.ParamByName('n').AsString := pName;
    VQuery.Open;
    Result := VQuery.Fields[0].AsInteger > 0;
  finally
    VQuery.Free;
  end;
end;

function TSchemaScan.CharLength(const pTable, pColumn: string): Integer;
var
  VKey: string;
begin
  VKey := UpperCase(pTable) + '|' + UpperCase(pColumn);
  if not FLengths.TryGetValue(VKey, Result) then
  begin
    Result := ColumnCharLength(FRepo, pTable, pColumn);
    FLengths.Add(VKey, Result);
  end;
end;

function TSchemaScan.ConstValue(pFileId: Int64; pLine: Integer; const pName: string; out pValue: Integer): Boolean;
var
  VQuery: TFDQuery;
  VValue: Integer;
begin
  { What the index BOUND the name to on this line: every ref of it must be one integer constant. A
    parameter or local of the same name leaves the ref unbound or bound to another kind. }
  Result := False;
  pValue := 0;
  VQuery := NewQuery('SELECT s.kind, s.signature FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id ' +
    'WHERE r.file_id = :f AND r.start_line = :l AND r.name_text = :n COLLATE NOCASE');
  try
    VQuery.ParamByName('f').AsLargeInt := pFileId;
    VQuery.ParamByName('l').AsInteger := pLine;
    VQuery.ParamByName('n').AsString := pName;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      if (VQuery.Fields[0].AsString <> 'const') or not ParseIntSignature(VQuery.Fields[1].AsString, VValue) or
        (Result and (VValue <> pValue)) then
      begin
        Result := False;
        Break;
      end;
      pValue := VValue;
      Result := True;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function TSchemaScan.IntOrConst(pFileId: Int64; pLine: Integer; const pText: string; out pValue: Integer): Boolean;
var
  VParts: TArray<string>;
begin
  Result := TryStrToInt(Trim(pText), pValue);
  if Result or not IsDottedIdent(Trim(pText)) then
    Exit;
  VParts := Trim(pText).Split(['.']);
  Result := ConstValue(pFileId, pLine, VParts[High(VParts)], pValue);
end;

function TSchemaScan.RefLine(pFileId: Int64; pLine, pCol, pEndCol: Integer; const pName: string;
  out pText: string): Boolean;
var
  VLines: TArray<string>;
begin
  { refs carry 1-based lines and columns; pEndCol is the column just past the name. The name must still
    be there: a file edited since it was indexed is not judged by its old positions. }
  pText := '';
  VLines := LinesOf(pFileId);
  if InRange(pLine, 1, Length(VLines)) then
    pText := VLines[pLine - 1];
  Result := (pText <> '') and SameText(Copy(pText, pCol, pEndCol - pCol), pName);
end;

function TSchemaScan.FormFields(const pDfmPath, pName: string): TArray<Int64>;
var
  VQuery: TFDQuery;
begin
  { The form's field of that name, in the unit beside the .dfm. }
  Result := nil;
  VQuery := NewQuery('SELECT s.id FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'WHERE s.kind = ''field'' AND s.name = :n COLLATE NOCASE AND f.path = :p COLLATE NOCASE');
  try
    VQuery.ParamByName('n').AsString := pName;
    VQuery.ParamByName('p').AsString := ChangeFileExt(pDfmPath, '.pas');
    VQuery.Open;
    while not VQuery.Eof do
    begin
      Result := Result + [VQuery.Fields[0].AsLargeInt];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;
function TSchemaScan.LinesOf(pFileId: Int64): TArray<string>;
var
  VPath: string;
begin
  if FLines.TryGetValue(pFileId, Result) then
    Exit;
  Result := nil;
  VPath := FStore.GetFilePath(pFileId);
  if (VPath <> '') and TFile.Exists(VPath) then
    try
      Result := TFile.ReadAllLines(VPath);
    except
      { An unreadable file costs that file's sites only. }
      on EInOutError do
        Result := nil;
      on EEncodingError do
        Result := nil;
    end;
  FLines.Add(pFileId, Result);
end;

function TSchemaScan.ResolveMaxLenPrefix(const pPrefix: string; out pTable, pColumn: string;
  out pLength: Integer): Boolean;
var
  VParts: TArray<string>;
  VSplit, VMask, VIdx, VHits, VLen: Integer;
  VTable, VColumn: string;
begin
  { <TABLE>_<FIELD>: every underscore is a candidate separator, and each underscore inside the
    table part may stand for '$' (MSC$LIST written MSC_LIST). Exactly one known column must match. }
  Result := False;
  pTable := '';
  pColumn := '';
  pLength := CHAR_LENGTH_UNKNOWN;
  VParts := pPrefix.Split(['_']);
  if (Length(VParts) < 2) or (Length(VParts) - 1 > MAX_PREFIX_UNDERSCORES) then
    Exit;
  for VIdx := 0 to High(VParts) do
    if VParts[VIdx] = '' then
      Exit;
  VHits := 0;
  for VSplit := 1 to High(VParts) do
  begin
    VColumn := string.Join('_', VParts, VSplit, Length(VParts) - VSplit);
    for VMask := 0 to (1 shl (VSplit - 1)) - 1 do
    begin
      VTable := VParts[0];
      for VIdx := 1 to VSplit - 1 do
        VTable := VTable + (if (VMask and (1 shl (VIdx - 1))) <> 0 then '$' else '_') + VParts[VIdx];
      VLen := CharLength(VTable, VColumn);
      if VLen < 0 then
        Continue;
      Inc(VHits);
      pTable := UpperCase(VTable);
      pColumn := UpperCase(VColumn);
      pLength := VLen;
    end;
  end;
  Result := VHits = 1;
end;

procedure TSchemaScan.AddFinding(const pRule: string; pFileId: Int64; pLine, pCol: Integer;
  const pMessage: string; const pTarget: TColumnTarget; const pProp: string);
var
  VKey: TFrFinding;
  VFinding: TLintFinding;
  VSeenKey: string;
begin
  VKey := Default(TFrFinding);
  VKey.RuleId := pRule;
  VKey.DatasetKey := pTarget.DatasetKey;
  VKey.TableName := pTarget.Table;
  VKey.FieldName := pTarget.Column;
  VKey.Prop := pProp;
  if IsExcepted(FExceptions, VKey) then
    Exit;
  VSeenKey := Format('%s|%d|%d|%d', [pRule, pFileId, pLine, pCol]);
  if FSeen.ContainsKey(VSeenKey) then
    Exit;
  FSeen.Add(VSeenKey, True);
  VFinding := Default(TLintFinding);
  VFinding.RuleId := pRule;
  VFinding.FileId := pFileId;
  VFinding.FilePath := FStore.GetFilePath(pFileId);
  VFinding.StartLine := pLine;
  VFinding.StartCol := pCol;
  VFinding.EndLine := pLine;
  VFinding.EndCol := pCol;
  VFinding.Severity := SEVERITY_WARNING;
  VFinding.Message := pMessage;
  FFindings.Add(VFinding);
end;

procedure TSchemaScan.ScanConstants;
var
  VQuery: TFDQuery;
  VName, VTable, VColumn: string;
  VLength, VValue: Integer;
  VTarget: TColumnTarget;
begin
  VQuery := NewQuery('SELECT name, signature, file_id, start_line, start_col FROM symbols ' +
    'WHERE kind = ''const'' AND UPPER(name) LIKE ''%\_MAXLEN'' ESCAPE ''\''' +
    (if FOnlyFileId > 0 then ' AND file_id = :f' else ''));
  try
    if FOnlyFileId > 0 then
      VQuery.ParamByName('f').AsLargeInt := FOnlyFileId;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VName := VQuery.Fields[0].AsString;
      if ParseIntSignature(VQuery.Fields[1].AsString, VValue) and
        ResolveMaxLenPrefix(Copy(VName, 1, Length(VName) - Length(MAXLEN_SUFFIX)), VTable, VColumn, VLength) and
        (VValue <> VLength) then
      begin
        VTarget := Default(TColumnTarget);
        VTarget.Table := VTable;
        VTarget.Column := VColumn;
        AddFinding(SCHEMA_MAXLEN_DRIFT_RULE, VQuery.Fields[2].AsLargeInt, VQuery.Fields[3].AsInteger,
          VQuery.Fields[4].AsInteger,
          Format('%s = %d, but %s.%s holds %d characters (field repository)',
            [VName, VValue, VTable, VColumn, VLength]), VTarget, '');
      end;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TSchemaScan.LoadDatasets;
var
  VQuery: TFDQuery;
  VTable, VUnit, VDataset: string;
  VInfo: TDatasetInfo;
  VSymbolId: Int64;
begin
  { UpdateOptions.UpdateTableName names the table the dataset posts to and wins over TableName
    (ORDER BY puts it last, so it overwrites). }
  VQuery := NewQuery('SELECT f.path, o.name, p.value_text FROM dfm_properties p ' +
    'JOIN dfm_objects o ON o.file_id = p.file_id AND o.ordinal = p.object_ordinal ' +
    'JOIN files f ON f.id = p.file_id ' +
    'WHERE p.name IN (''TableName'', ''UpdateOptions.UpdateTableName'') ' +
    'ORDER BY f.path, o.name, CASE WHEN p.name = ''TableName'' THEN 0 ELSE 1 END');
  try
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VUnit := ChangeFileExt(ExtractFileName(VQuery.Fields[0].AsString), '');
      VDataset := VQuery.Fields[1].AsString;
      VTable := UnquoteDfm(VQuery.Fields[2].AsString);
      if VTable <> '' then
      begin
        VInfo.Table := UpperCase(VTable);
        VInfo.DatasetKey := VUnit + '.' + VDataset;
        FDatasets.AddOrSetValue(UnitKeyOfPath(VQuery.Fields[0].AsString) + '|' + UpperCase(VDataset), VInfo);
        for VSymbolId in FormFields(VQuery.Fields[0].AsString, VDataset) do
          FDatasetSymbols.AddOrSetValue(VSymbolId, VInfo);
      end;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TSchemaScan.ScanDfmFields;
var
  VQuery: TFDQuery;
begin
  VQuery := NewQuery('SELECT o.file_id, f.path, o.name, o.class_name, o.parent_name, o.symbol_id, ' +
    'o.start_line, o.start_col, ' +
    '(SELECT p.value_text FROM dfm_properties p WHERE p.file_id = o.file_id AND p.object_ordinal = o.ordinal ' +
    '  AND p.name = ''FieldName'' LIMIT 1), ' +
    '(SELECT p.value_text FROM dfm_properties p WHERE p.file_id = o.file_id AND p.object_ordinal = o.ordinal ' +
    '  AND p.name = ''Size'' LIMIT 1), ' +
    '(SELECT p.start_line FROM dfm_properties p WHERE p.file_id = o.file_id AND p.object_ordinal = o.ordinal ' +
    '  AND p.name = ''Size'' LIMIT 1), ' +
    '(SELECT p.start_col FROM dfm_properties p WHERE p.file_id = o.file_id AND p.object_ordinal = o.ordinal ' +
    '  AND p.name = ''Size'' LIMIT 1) ' +
    'FROM dfm_objects o JOIN files f ON f.id = o.file_id ' +
    'WHERE o.class_name IN (''TStringField'', ''TWideStringField'')');
  try
    VQuery.Open;
    while not VQuery.Eof do
    begin
      ScanDfmField(VQuery);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TSchemaScan.ScanDfmField(pRow: TFDQuery);
var
  VInfo: TDatasetInfo;
  VTarget: TColumnTarget;
  VPath, VColumn: string;
  VFileId, VSymbolId: Int64;
  VSize, VLine, VCol: Integer;
  VDefault: Boolean;
begin
  { pRow columns: 0 file_id, 1 path, 2 name, 3 class_name, 4 parent_name, 5 symbol_id, 6 start_line,
    7 start_col, 8 FieldName, 9 Size, 10 Size line, 11 Size col. }
  VFileId := pRow.Fields[0].AsLargeInt;
  VPath := pRow.Fields[1].AsString;
  VColumn := UnquoteDfm(pRow.Fields[8].AsString);
  if (VColumn = '') or
    not FDatasets.TryGetValue(UnitKeyOfPath(VPath) + '|' + UpperCase(pRow.Fields[4].AsString), VInfo) then
    Exit;
  VTarget := Default(TColumnTarget);
  VTarget.Table := VInfo.Table;
  VTarget.Column := UpperCase(VColumn);
  VTarget.DatasetKey := VInfo.DatasetKey;
  VTarget.Kind := tkDatasetField;
  VTarget.CharLength := CharLength(VTarget.Table, VTarget.Column);
  if VTarget.CharLength < 0 then
    Exit;
  { Code names the component through the form's field of the same name in the unit beside the
    .dfm; dfm_objects.symbol_id is the DFM-side component symbol, registered too. }
  if not pRow.Fields[5].IsNull then
    FTargets.AddOrSetValue(pRow.Fields[5].AsLargeInt, VTarget);
  for VSymbolId in FormFields(VPath, pRow.Fields[2].AsString) do
    FTargets.AddOrSetValue(VSymbolId, VTarget);
  if (FOnlyFileId > 0) and (VFileId <> FOnlyDfmId) then
    Exit;
  VDefault := pRow.Fields[9].IsNull;
  VSize := STRING_FIELD_DEFAULT_SIZE;
  VLine := pRow.Fields[6].AsInteger;
  VCol := pRow.Fields[7].AsInteger;
  if not VDefault then
  begin
    if not TryStrToInt(Trim(pRow.Fields[9].AsString), VSize) then
      VSize := VTarget.CharLength;
    VLine := pRow.Fields[10].AsInteger;
    VCol := pRow.Fields[11].AsInteger;
  end;
  if VSize <> VTarget.CharLength then
    AddFinding(SCHEMA_LENGTH_BOUND_RULE, VFileId, VLine, VCol,
      Format('%s: %s.Size = %d%s, but %s.%s holds %d characters (field repository)',
        [pRow.Fields[3].AsString, pRow.Fields[2].AsString, VSize, (if VDefault then ' (default)' else ''),
         VTarget.Table, VTarget.Column, VTarget.CharLength]), VTarget, PROP_SIZE);
end;

procedure TSchemaScan.LoadOrmTargets;
var
  VQuery: TFDQuery;
  VTarget: TColumnTarget;
  VFieldId: Int64;
begin
  if not TableExists('orm_links') then
    Exit;
  { link-orm's field_to_column: T<X>.F<Y> -> <X>.<Y>, so the names are recovered by the same strip.
    link-orm writes its rows into the LAST --db, so this index holds them only when it was named last
    (link-orm --db <sql.sqlite> --db <project.sqlite>); a Delphi symbol id is this index's own only
    when its db index is that last one. }
  VQuery := NewQuery('SELECT DISTINCT f.id, f.name, c.name FROM orm_links l ' +
    'JOIN symbols f ON f.id = l.delphi_symbol_id JOIN symbols c ON c.id = f.parent_id ' +
    'WHERE l.link_kind = ''field_to_column'' AND f.kind = ''field'' AND l.delphi_db_index = ' +
    '(SELECT MAX(MAX(m.delphi_db_index, m.sql_db_index)) FROM orm_links m)');
  try
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VFieldId := VQuery.Fields[0].AsLargeInt;
      VTarget := Default(TColumnTarget);
      VTarget.Table := UpperCase(StripOrmPrefix(VQuery.Fields[2].AsString, 'T'));
      VTarget.Column := UpperCase(StripOrmPrefix(VQuery.Fields[1].AsString, 'F'));
      VTarget.Kind := tkOrm;
      VTarget.CharLength := CharLength(VTarget.Table, VTarget.Column);
      if VTarget.CharLength >= 0 then
      begin
        FTargets.AddOrSetValue(VFieldId, VTarget);
        AddWriteProperties(VFieldId, VQuery.Fields[1].AsString, VTarget);
      end;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TSchemaScan.AddWriteProperties(pFieldId: Int64; const pFieldName: string; const pTarget: TColumnTarget);
var
  VQuery: TFDQuery;
  VLines: TArray<string>;
  VLine: Integer;
begin
  { A property-spec ref carries no enclosing symbol: the property is the one declared on the ref's line in
    the field's own class. It must WRITE the field directly; a setter may shorten the value. }
  VQuery := NewQuery('SELECT DISTINCT p.id, r.file_id, r.start_line FROM refs r ' +
    'JOIN symbols f ON f.id = r.symbol_id ' +
    'JOIN symbols p ON p.file_id = r.file_id AND p.start_line = r.start_line AND p.parent_id = f.parent_id ' +
    'WHERE r.kind = ''property-spec'' AND p.kind = ''property'' AND r.symbol_id = :f');
  try
    VQuery.ParamByName('f').AsLargeInt := pFieldId;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VLines := LinesOf(VQuery.Fields[1].AsLargeInt);
      VLine := VQuery.Fields[2].AsInteger;
      if InRange(VLine, 1, Length(VLines)) and
        TRegEx.IsMatch(VLines[VLine - 1], '\bwrite\s+' + pFieldName + '\b', [roIgnoreCase]) then
        FTargets.AddOrSetValue(VQuery.Fields[0].AsLargeInt, pTarget);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TSchemaScan.CheckTail(pFileId: Int64; pLine, pCol: Integer; const pText: string; pFrom: Integer;
  const pTarget: TColumnTarget);
var
  VPos, VCount, VLitLen: Integer;
  VMember, VRhs, VCountText, VProp: string;
  VIsSize: Boolean;
begin
  { pFrom = the first character after the target expression. ORM targets take `:= rhs`; dataset
    fields take `.AsString := rhs` (and kin) and `.Size / .MaxLength := N`. }
  VPos := SkipSpaces(pText, pFrom);
  VIsSize := False;
  VProp := '';
  if pTarget.Kind = tkDatasetField then
  begin
    if (VPos > Length(pText)) or (pText[VPos] <> '.') then
      Exit;
    VPos := SkipSpaces(pText, VPos + 1);
    VMember := ReadIdent(pText, VPos);
    if SameText(VMember, PROP_SIZE) or SameText(VMember, PROP_MAXLEN) then
    begin
      VIsSize := True;
      VProp := if SameText(VMember, PROP_SIZE) then PROP_SIZE else PROP_MAXLEN;
    end
    else if not (SameText(VMember, 'AsString') or SameText(VMember, 'AsWideString') or
      SameText(VMember, 'AsAnsiString') or SameText(VMember, 'Value') or SameText(VMember, 'Text')) then
      Exit;
    VPos := SkipSpaces(pText, VPos);
  end;
  if Copy(pText, VPos, 2) <> ':=' then
    Exit;
  VRhs := StatementRhs(pText, VPos + 2);
  if VIsSize then
  begin
    if IntOrConst(pFileId, pLine, VRhs, VCount) and (VCount > pTarget.CharLength) then
      AddFinding(SCHEMA_LENGTH_BOUND_RULE, pFileId, pLine, pCol,
        Format('%s := %s (%d) exceeds %s.%s, which holds %d characters (field repository)',
          [VProp, VRhs, VCount, pTarget.Table, pTarget.Column, pTarget.CharLength]), pTarget, VProp);
  end
  else if PlainLiteralLength(VRhs, VLitLen) then
  begin
    if VLitLen > pTarget.CharLength then
      AddFinding(SCHEMA_MAXLEN_DRIFT_RULE, pFileId, pLine, pCol,
        Format('A %d-character literal is assigned to %s.%s, which holds %d characters (field repository)',
          [VLitLen, pTarget.Table, pTarget.Column, pTarget.CharLength]), pTarget, '');
  end
  else if CopyCountArg(VRhs, VCountText) and IntOrConst(pFileId, pLine, VCountText, VCount) and
    (VCount > pTarget.CharLength) then
    AddFinding(SCHEMA_LENGTH_BOUND_RULE, pFileId, pLine, pCol,
      Format('Copy(..., %s) keeps up to %d characters, but %s.%s holds %d (field repository)',
        [VCountText, VCount, pTarget.Table, pTarget.Column, pTarget.CharLength]), pTarget, '');
end;

procedure TSchemaScan.ScanTargetRefs;
var
  VQuery: TFDQuery;
  VPair: TPair<Int64, TColumnTarget>;
  VText: string;
begin
  VQuery := NewQuery('SELECT file_id, start_line, start_col, end_col, name_text FROM refs ' +
    'WHERE symbol_id = :s' + (if FOnlyFileId > 0 then ' AND file_id = :f' else ''));
  try
    if FOnlyFileId > 0 then
      VQuery.ParamByName('f').AsLargeInt := FOnlyFileId;
    for VPair in FTargets do
    begin
      VQuery.ParamByName('s').AsLargeInt := VPair.Key;
      VQuery.Open;
      while not VQuery.Eof do
      begin
        if RefLine(VQuery.Fields[0].AsLargeInt, VQuery.Fields[1].AsInteger, VQuery.Fields[2].AsInteger,
          VQuery.Fields[3].AsInteger, VQuery.Fields[4].AsString, VText) then
          CheckTail(VQuery.Fields[0].AsLargeInt, VQuery.Fields[1].AsInteger, VQuery.Fields[2].AsInteger, VText,
            VQuery.Fields[3].AsInteger, VPair.Value);
        VQuery.Next;
      end;
      VQuery.Close;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TSchemaScan.ScanFieldByName;
var
  VQuery: TFDQuery;
  VText, VColumn: string;
  VInfo: TDatasetInfo;
  VTarget: TColumnTarget;
  VPos: Integer;
begin
  if not TableExists('ref_receivers') then
    Exit;
  { The receiver is the symbol the index bound, so a local dataset of the same name is not the form's. }
  VQuery := NewQuery('SELECT DISTINCT r.file_id, r.start_line, r.start_col, r.end_col, r.name_text, x.symbol_id ' +
    'FROM refs r JOIN ref_receivers rr ON rr.ref_id = r.id JOIN refs x ON x.id = rr.receiver_ref_id ' +
    'WHERE r.name_text = ''FieldByName'' COLLATE NOCASE AND x.symbol_id IS NOT NULL' +
    (if FOnlyFileId > 0 then ' AND r.file_id = :f' else ''));
  try
    if FOnlyFileId > 0 then
      VQuery.ParamByName('f').AsLargeInt := FOnlyFileId;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      if FDatasetSymbols.TryGetValue(VQuery.Fields[5].AsLargeInt, VInfo) and
        RefLine(VQuery.Fields[0].AsLargeInt, VQuery.Fields[1].AsInteger, VQuery.Fields[2].AsInteger,
          VQuery.Fields[3].AsInteger, VQuery.Fields[4].AsString, VText) and
        FieldByNameColumn(VText, VQuery.Fields[3].AsInteger, VColumn, VPos) then
      begin
        VTarget := Default(TColumnTarget);
        VTarget.Table := VInfo.Table;
        VTarget.Column := UpperCase(VColumn);
        VTarget.DatasetKey := VInfo.DatasetKey;
        VTarget.Kind := tkDatasetField;
        VTarget.CharLength := CharLength(VTarget.Table, VTarget.Column);
        if VTarget.CharLength >= 0 then
          CheckTail(VQuery.Fields[0].AsLargeInt, VQuery.Fields[1].AsInteger, VQuery.Fields[2].AsInteger, VText, VPos,
            VTarget);
      end;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;
function TSchemaScan.Run: TArray<TLintFinding>;
var
  VQuery: TFDQuery;
  VPath: string;
begin
  FOnlyDfmId := 0;
  if FOnlyFileId > 0 then
  begin
    VPath := FStore.GetFilePath(FOnlyFileId);
    if SameText(ExtractFileExt(VPath), '.dfm') then
      FOnlyDfmId := FOnlyFileId
    else
    begin
      VQuery := NewQuery('SELECT id FROM files WHERE path = :p COLLATE NOCASE');
      try
        VQuery.ParamByName('p').AsString := ChangeFileExt(VPath, '.dfm');
        VQuery.Open;
        if not VQuery.Eof then
          FOnlyDfmId := VQuery.Fields[0].AsLargeInt;
      finally
        VQuery.Free;
      end;
    end;
  end;
  ScanConstants;
  if TableExists('dfm_objects') and TableExists('dfm_properties') then
  begin
    LoadDatasets;
    ScanDfmFields;
    ScanFieldByName;
  end;
  LoadOrmTargets;
  ScanTargetRefs;
  Result := FFindings.ToArray;
end;

{ The column part of a local named after a field: tDIMABBR, fldDIMABBR; '' = not such a name. }
function LocalColumn(const pName: string): string;
var
  VPrefix: string;
begin
  for VPrefix in LOCAL_PREFIXES do
  begin
    Result := Copy(pName, Length(VPrefix) + 1, MaxInt);
    if pName.StartsWith(VPrefix) and (Result <> '') and (Result = UpperCase(Result)) and CharInSet(Result[1], ['A'..'Z']) then
      Exit;
  end;
  Result := '';
end;

{ The one char length every column of that name has; -1 when they differ or there is none. }
function TSchemaScan.NamedLength(const pColumn: string; out pTable: string): Integer;
var
  VQuery: TFDQuery;
  VLength: Integer;
begin
  Result := CHAR_LENGTH_UNKNOWN;
  pTable := '';
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := FRepo;
    VQuery.Open('SELECT "TABLE_NAME" FROM "DL_FIELDS_INFO" WHERE UPPER("FIELD_NAME") = :F ORDER BY 1', [pColumn]);  // dl:ok path-traversal -- REVIEWED 2026-11-24 v154 SCHEMA: SQL text, not a path
    while not VQuery.Eof do
    begin
      VLength := CharLength(VQuery.Fields[0].AsString, pColumn);
      if (VLength < 0) or ((pTable <> '') and (VLength <> Result)) then
        Exit(CHAR_LENGTH_UNKNOWN);
      Result := VLength;
      pTable := if pTable = '' then UpperCase(VQuery.Fields[0].AsString) else '*';
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure TSchemaScan.LoadLocalTargets;
var
  VQuery: TFDQuery;
  VTarget: TColumnTarget;
begin
  VQuery := NewQuery('SELECT id, name FROM symbols WHERE file_id = :f AND kind = ''local_var''');
  try
    VQuery.ParamByName('f').AsLargeInt := FOnlyFileId;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VTarget := Default(TColumnTarget);
      VTarget.Kind := tkOrm;
      VTarget.Column := LocalColumn(VQuery.Fields[1].AsString);
      if VTarget.Column <> '' then
        VTarget.CharLength := NamedLength(VTarget.Column, VTarget.Table);
      if VTarget.CharLength > 0 then
        FTargets.AddOrSetValue(VQuery.Fields[0].AsLargeInt, VTarget);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function TSchemaScan.RunLocals: TArray<TLintFinding>;
begin
  LoadLocalTargets;
  ScanTargetRefs;
  Result := FFindings.ToArray;
end;

{ The repository opened read-only, or nil with pNote saying why the rules stay silent. }
function OpenSchemaRepository(const pRepoFile: string; out pNote: string): TFDConnection;
begin
  Result := nil;
  pNote := '';
  if pRepoFile = '' then
    pNote := NOTE_NO_REPO
  else if not TFile.Exists(pRepoFile) then
    pNote := Format(NOTE_NOT_FOUND, [pRepoFile])
  else
    try
      Result := OpenRepository(pRepoFile, True);
    except
      on E: ERepoError do
        pNote := Format(NOTE_OPEN_FAILED, [pRepoFile, E.Message]);
      on E: EFDException do
        pNote := Format(NOTE_OPEN_FAILED, [pRepoFile, E.Message]);
    end;
end;

function NoSchemaFactsNote(const pRepoFile: string): string;
begin
  Result := Format(NOTE_NO_FACTS, [ExtractFileName(pRepoFile)]);
end;

function SchemaFactsBanner(pRepo: TFDConnection; const pRepoFile: string): string;
var
  VInfo: TSchemaInfo;
begin
  VInfo := SchemaInfo(pRepo);
  Result := Format('schema facts %s (%s) from %s', [VInfo.ReadAtUtc, VInfo.Source, ExtractFileName(pRepoFile)]);
end;

{ --project of this run's own command line; '' when the run is not lint / lint-all or names none. }
function ProjectOfCommandLine: string;
var
  VIdx: Integer;
begin
  Result := '';
  if not MatchText(ParamStr(1), ['lint', 'lint-all']) then
    Exit;
  for VIdx := 2 to ParamCount do
    if SameText(ParamStr(VIdx), PROJECT_SWITCH) then
      Exit(ParamStr(VIdx + 1))
    else if ParamStr(VIdx).StartsWith(PROJECT_SWITCH + '=', True) then
      Exit(Copy(ParamStr(VIdx), Length(PROJECT_SWITCH) + 2, MaxInt));
end;

{ The project file whose manifest section owns the index, else the _D-RAG convention; '' when neither applies. }
function ProjectOfIndex(const pDb: string): string;
var
  VManifest: TIndexManifest;
  VSection: TIndexSection;
  VDir: string;
begin
  Result := '';
  try
    VManifest := TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
    for VSection in VManifest.Sections do
      if (SectionProjectFile(VManifest, VSection) <> '') and
        SameText(ExpandSectionDb(VManifest, VSection), ExpandFileName(pDb)) then
        Exit(SectionProjectFile(VManifest, VSection));
  except
    { No manifest, or an unreadable one, is not a lint failure. }
    on E: Exception do
      Result := '';
  end;
  VDir := ExtractFileDir(ExpandFileName(pDb));
  if SameText(ExtractFileName(VDir), DRAG_DIR) then
    Result := TPath.Combine(ExtractFileDir(VDir), ChangeFileExt(ExtractFileName(pDb), DPROJ_EXT));
end;

function SchemaRepositoryOf(const pStore: ISymbolStore): string;
var
  VProject: string;
begin
  Result := '';
  VProject := ProjectOfCommandLine;
  if (VProject = '') and (pStore is TSQLiteSymbolStore) then
    VProject := ProjectOfIndex((pStore as TSQLiteSymbolStore).DbPath);
  if VProject = '' then
    Exit;
  VProject := ExpandFileName(ChangeFileExt(VProject, DPROJ_EXT));
  if TFile.Exists(VProject) then
    Result := LocateFieldRepository(VProject, '');
end;

function RunLocalNaming(const pStore: ISymbolStore; const pRepoFile: string; pFileId: Int64): TArray<TLintFinding>;
var
  VRepo: TFDConnection;
  VScan: TSchemaScan;
  VNote: string;
begin
  Result := nil;
  if (pStore is not TSQLiteSymbolStore) or (pFileId = 0) then
    Exit;
  VRepo := OpenSchemaRepository(pRepoFile, VNote);
  if VRepo = nil then
    Exit;
  try
    if not HasSchema(VRepo) then
      Exit;
    VScan := TSchemaScan.Create(pStore, VRepo, pFileId);
    try
      Result := VScan.RunLocals;
    finally
      VScan.Free;
    end;
  finally
    VRepo.Free;
  end;
end;

function RunSchemaRules(const pStore: ISymbolStore; const pRepoFile: string;
  pOnlyFileId: Int64): TSchemaLintResult;
var
  VRepo: TFDConnection;
  VScan: TSchemaScan;
begin
  Result := Default(TSchemaLintResult);
  if pStore is not TSQLiteSymbolStore then
    Exit;
  VRepo := OpenSchemaRepository(pRepoFile, Result.Note);
  if VRepo = nil then
  begin
    Result.Broken := pRepoFile <> '';
    Exit;
  end;
  try
    if not HasSchema(VRepo) then
    begin
      Result.Note := NoSchemaFactsNote(pRepoFile);
      Exit;
    end;
    Result.Banner := SchemaFactsBanner(VRepo, pRepoFile);
    VScan := TSchemaScan.Create(pStore, VRepo, pOnlyFileId);
    try
      Result.Findings := VScan.Run;
    finally
      VScan.Free;
    end;
  finally
    VRepo.Free;
  end;
end;

var
  { ReportSchemaRun spoke already in this process. }
  GReported: Boolean = False;

procedure ReportSchemaRun(const pResult: TSchemaLintResult; pQuiet: Boolean);
var
  VText: string;
begin
  VText := pResult.Banner;
  if (VText = '') and (pResult.Broken or (GetEnvironmentVariable('DRAGLINT_DEBUG') <> '')) then
    VText := pResult.Note;
  if pQuiet or GReported or (VText = '') then
    Exit;
  GReported := True;
  Writeln(ErrOutput, 'drag-lint: ' + VText);
end;

end.
