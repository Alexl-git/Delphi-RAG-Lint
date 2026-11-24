unit DRagLint.V154.SCHEMA.Support;

{ Wave v154 lane SCHEMA -- helpers of DRagLint.V154.SCHEMA (private to the lane): the repository facts of the run, the
  forms, and the checks
    schema-unknown-column   -- a field, a select item or an INSERT column that a known table does not have
    schema-type-mismatch    -- an accessor or a persistent field class whose kind clashes with the column type
    schema-required-not-set -- an INSERT that leaves out a column the database requires and does not fill
  The dataset side (one known SQL text, its table) comes from DRagLint.V154.SqlText, the column side from
  DRagLint.FieldRepo.SchemaFactsEx. Whatever either side does not state is silent. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.V151.Api
  , DRagLint.V154.SqlText
  , DRagLint.FieldRepo.SchemaFactsEx
  ;

const
  RULE_UNKNOWN = 'schema-unknown-column';
  RULE_TYPE = 'schema-type-mismatch';
  RULE_REQUIRED = 'schema-required-not-set';

/// <summary>The schema facts of the project's field repository.</summary>
/// <param name="ACtx">The file being linted.</param>
/// <returns>nil when there is no repository or it holds no schema facts.</returns>
/// <remarks>Kept for the process until the repository file changes. Thread-safe. A run narrowed to one rule says on stderr
/// what it read, or why not; any other run hears it from DRagLint.Lint.SchemaRules.RunSchemaRules.</remarks>
function FactsOf(const ACtx: TV151FileCtx): ISchemaFacts;

/// <summary>True when the unit can hold anything the lane looks at.</summary>
/// <param name="AFile">The .pas file.</param>
/// <returns>False when no field or SQL member is named in it.</returns>
function MayUseFields(const AFile: string): Boolean;

/// <summary>The three rules on the datasets and the SQL texts of one unit.</summary>
/// <param name="ACtx">The file.</param>
/// <param name="AScan">Its datasets.</param>
/// <param name="AFacts">The repository facts; not nil.</param>
/// <returns>Findings of the rules ACtx wants; nil when none.</returns>
function CheckUnit(const ACtx: TV151FileCtx; const AScan: TSqlTextScan; const AFacts: ISchemaFacts): TArray<TLintFinding>;

/// <summary>schema-type-mismatch on persistent fields used by the unit, of its own form or another unit's.</summary>
/// <param name="ACtx">The file; needs its Store.</param>
/// <param name="AFacts">The repository facts; not nil.</param>
/// <returns>Findings; nil when none.</returns>
function CheckFieldUse(const ACtx: TV151FileCtx; const AFacts: ISchemaFacts): TArray<TLintFinding>;

/// <summary>The three rules on the persistent fields and the SQL texts of the unit's form.</summary>
/// <param name="ACtx">The file; DfmPath is not empty.</param>
/// <param name="AFacts">The repository facts; not nil.</param>
/// <returns>Findings in the .dfm; nil when none.</returns>
function CheckForm(const ACtx: TV151FileCtx; const AFacts: ISchemaFacts): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.StrUtils
  , System.DateUtils
  , System.Math
  , System.Classes
  , System.Generics.Collections
  , System.RegularExpressions
  , Winapi.Windows
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , TreeSitter
  , DRagLint.Core.Interfaces
  , DRagLint.Core.Encoding
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Parser.DFM
  , DRagLint.Parser.DFMProps
  , DRagLint.Storage.SQLite
  , DRagLint.FieldRepo.DfmReadSql
  , DRagLint.FieldRepo.Exceptions
  , DRagLint.Lint.SchemaRules
  ;

const
  SEVERITY_WARNING = 'warning';
  BINARY_DFM_BYTE = $FF;
  MAX_LISTED = 6;
  LOCATE_TTL_MS = 2000;      // how long a located repository path is trusted inside one run
  KIND_LIST = 'list';
  OBJECT_KIND = 'object';
  FACT_TABLES = 2;           // the two tables IsFixed needs
  PROP_FIELD_NAME = 'FieldName';
  PROP_TABLE_NAME = 'TableName';
  MEMBER_FIELD_BY_NAME = 'fieldbyname';
  CLASH_RAISES = 'raises at run time';
  CLASH_CONVERTS = 'converts the text and raises EConvertError for anything else';
  LIST_PROPS: array[0..2] of string = ('SQL.Strings', 'CommandText.Strings', 'CommandText');
  { accessors of TField by the kind of value they need }
  NUMBER_ACCESSORS: array[0..7] of string = ('asinteger', 'aslargeint', 'aslongword', 'asfloat', 'assingle', 'asextended',
    'ascurrency', 'asbcd');
  ORDINAL_ACCESSORS: array[0..2] of string = ('asinteger', 'aslargeint', 'aslongword');
  DATE_ACCESSORS: array[0..1] of string = ('asdatetime', 'assqltimestamp');
  ACCESSOR_LIST = '''asinteger'', ''aslargeint'', ''aslongword'', ''asfloat'', ''assingle'', ''asextended'', ''ascurrency'', ' +
    '''asbcd'', ''asdatetime'', ''assqltimestamp'', ''asboolean''';
  BOOL_ACCESSOR = 'asboolean';
  { persistent field classes by the kind of column they can open }
  TEXT_FIELDS: array[0..1] of string = ('TStringField', 'TWideStringField');
  MEMO_FIELDS: array[0..1] of string = ('TMemoField', 'TWideMemoField');
  NUMBER_FIELDS: array[0..14] of string = ('TIntegerField', 'TSmallintField', 'TLargeintField', 'TWordField', 'TLongWordField',
    'TShortintField', 'TByteField', 'TAutoIncField', 'TCurrencyField', 'TFloatField', 'TSingleField', 'TExtendedField',
    'TBCDField', 'TFMTBCDField', 'TLargeUIntField');
  DATE_FIELDS: array[0..4] of string = ('TDateField', 'TTimeField', 'TDateTimeField', 'TSQLTimeStampField', 'TSQLTimeStampOffsetField');
  { words and pseudo columns that stand where a column may }
  NO_COLUMNS: array[0..13] of string = ('ROW_COUNT', 'GDSCODE', 'SQLCODE', 'SQLSTATE', 'INSERTING', 'UPDATING', 'DELETING',
    'CURRENT_CONNECTION', 'CURRENT_TRANSACTION', 'ROWID', 'OID', 'ROWNUM', 'SYSDATE', 'RESETTING');
  SYSTEM_PREFIX = 'RDB$';
  { receiver members that replace or hand out what a dataset reads }
  CHANGE_MEMBERS: array[0..16] of string = ('sql', 'commandtext', 'command', 'assign', 'selectsql', 'insertsql', 'updatesql', 'deletesql',
    'refreshsql', 'sqls', 'macros', 'macrobyname', 'loadfromfile', 'clonecursor', 'data', 'tablename', 'commandtype');

  { dataset and command classes that can speak to the Firebird database a repository describes: FireDAC, IBX, IBDAC,
    FIBPlus, UIB, UniDAC, Zeos, dbExpress. BDE and ADO classes read another database that may reuse the table names. }
  DATABASE_CLASSES = '^T(FD|IB|pFIB|FIB|UIB|Uni|Z(Read|Update|Query|Table|Connection)|SQL(Query|DataSet|Table|Connection))';

type
  { One SQL dataset or table component of a form. }
  TFormDataset = record
    Name     : string;
    ClassName: string;
    ObjKind  : string;
    Facts    : TSqlTextFacts;
    TableName: string;
    Line     : Integer;   // of the SQL property
    Col      : Integer;
  end;

  { One persistent field of a form. }
  TFormField = record
    Name     : string;
    ClassName: string;
    FieldName: string;
    Origin   : string;
    Data     : Boolean;   // False: calculated, lookup, internal, aggregate
    Dataset  : Integer;   // index into Datasets; -1 = its parent is none
    Line     : Integer;   // of the component
    Col      : Integer;
    NameLine : Integer;   // of the FieldName property
    NameCol  : Integer;
  end;

  TSchemaForm = record
    Root    : string;     // class of the form
    Datasets: TArray<TFormDataset>;
    Fields  : TArray<TFormField>;
  end;

  TFormEntry = record
    Stamp: TDateTime;
    Form : TSchemaForm;
  end;

  { A SQL text the source states as a whole, and where. }
  TStatedSql = record
    Facts : TSqlTextFacts;
    Path  : string;
    Line  : Integer;
    Col   : Integer;
    EndCol: Integer;
  end;

  { The columns of a set of rows IsFixed reads. }
  TFixedColumn = (fxSymbol, fxMember, fxRef);  // dl:ok enum-ordinal-persisted@4ce1 -- REVIEWED 2026-11-24 v154 SCHEMA: Ord() only indexes Query.Fields[] of a read; nothing is persisted

var
  GLock     : TObject;
  GForms    : TDictionary<string, TFormEntry>;
  GFacts    : ISchemaFacts;
  GFactsKey : string;        // repository file and stamps GFacts was read from
  GFactsNote: TSchemaLintResult;
  GWhereDb  : string;        // index the last repository path was located for
  GWhereTick: UInt64;

{ ---- the repository ---- }

function StampOf(const AFile: string): string;
begin
  Result:= if TFile.Exists(AFile) then Format('%d|%d', [DateTimeToUnix(TFile.GetLastWriteTimeUtc(AFile)), TFile.GetSize(AFile)]) else '-';
end;

{ Reads the facts of ARepo into the process cache when they are not there yet. Called under GLock. }
procedure Refresh(const ARepo: string);
var
  Key : string;
  Repo: TFDConnection;
begin
  Key:= string.Join('|', [ARepo, StampOf(ARepo), StampOf(ARepo + '-wal')]);
  if Key = GFactsKey then Exit;
  GFacts    := nil;
  GFactsNote:= Default(TSchemaLintResult);
  GFactsKey := Key;
  Repo:= OpenSchemaRepository(ARepo, GFactsNote.Note);
  GFactsNote.Broken:= (Repo = nil) and (ARepo <> '');
  if Repo = nil then Exit;
  try
    GFacts:= LoadSchemaFacts(Repo);
    if GFacts = nil then GFactsNote.Note:= NoSchemaFactsNote(ARepo)
    else GFactsNote.Banner:= SchemaFactsBanner(Repo, ARepo);
  finally
    Repo.Free;
  end;
end;

function IsQuiet: Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 1 to ParamCount do
    if SameText(ParamStr(I), '--quiet') then Exit(True);
end;

function FactsOf(const ACtx: TV151FileCtx): ISchemaFacts;
var
  Db  : string;
  Note: TSchemaLintResult;
begin
  Db:= if ACtx.Store is TSQLiteSymbolStore then (ACtx.Store as TSQLiteSymbolStore).DbPath else '';
  TMonitor.Enter(GLock);
  try
    if (GWhereTick = 0) or (not SameText(Db, GWhereDb)) or (GetTickCount64 - GWhereTick > LOCATE_TTL_MS) then
    begin
      Refresh(SchemaRepositoryOf(ACtx.Store));
      GWhereDb  := Db;
      GWhereTick:= GetTickCount64;
    end;
    Result:= GFacts;
    Note  := GFactsNote;
  finally
    TMonitor.Exit(GLock);
  end;
  if ACtx.NarrowRule <> '' then ReportSchemaRun(Note, IsQuiet);
end;

function MayUseFields(const AFile: string): Boolean;
begin
  Result:= TRegEx.IsMatch(TEncoding.UTF8.GetString(TAstParseCache.Get(AFile).Src),
    '\b(SQL|CommandText|FieldByName|ExecSQL|Open|As(Integer|LargeInt|LongWord|Float|Single|Extended|Currency|BCD|DateTime|SQLTimeStamp|Boolean))\b',
    [roIgnoreCase]);
end;

{ ---- findings ---- }

function FindingAt(const ARule, AMessage, APath: string; ALine, ACol, AEndCol: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := SEVERITY_WARNING;
  Result.Message  := AMessage;
  Result.FilePath := APath;
  Result.StartLine:= ALine;
  Result.StartCol := ACol;
  Result.EndLine  := ALine;
  Result.EndCol   := AEndCol;
end;

function Excepted(const AFacts: ISchemaFacts; const ARule, ADataset, ATable, AField: string): Boolean;
var
  Key: TFrFinding;
begin
  Key:= Default(TFrFinding);
  Key.RuleId    := ARule;
  Key.DatasetKey:= ADataset;
  Key.TableName := ATable;
  Key.FieldName := AField;
  Result:= AFacts.Excepted(Key);
end;

{ The table is known and neither has the column nor knows it as a calculated or lookup field. }
function IsUnknown(const AFacts: ISchemaFacts; const ATable, AColumn: string): Boolean;
var
  Fact: TSchemaColumn;
begin
  Result:= AFacts.KnowsTable(ATable) and (not AFacts.FindColumn(ATable, AColumn, Fact)) and (not AColumn.StartsWith(SYSTEM_PREFIX, True)) and
    (not MatchText(AColumn, NO_COLUMNS));
end;

function SpeaksDatabase(const AClass: string): Boolean;
begin
  Result:= TRegEx.IsMatch(AClass, DATABASE_CLASSES, [roIgnoreCase]);
end;

{ ---- kinds ---- }

{ Why the accessor does not fit the column; '' = it fits, or nothing certain is known. }
function AccessorClash(const AFact: TSchemaColumn; const AAccessor: string): string;
var
  Name  : string;
  Number: Boolean;
  Date  : Boolean;
begin
  Name  := LowerCase(AAccessor);
  Number:= MatchStr(Name, NUMBER_ACCESSORS);
  Date  := MatchStr(Name, DATE_ACCESSORS);
  Result:= '';
  case AFact.Group of
    scgText:
      if Number or Date then Result:= CLASH_CONVERTS;
    scgMemo, scgBinary:
      if Number or Date or (Name = BOOL_ACCESSOR) then Result:= CLASH_RAISES;
    scgDateTime:
      if MatchStr(Name, ORDINAL_ACCESSORS) or (Name = BOOL_ACCESSOR) then Result:= CLASH_RAISES;
    scgNumber:
      if Date then Result:= CLASH_RAISES;
    scgBoolean:
      if Number or Date then Result:= CLASH_RAISES;
  end;
end;

{ The kind of column a persistent field class opens on. }
function ClassGroup(const AClass: string): TSchemaGroup;
begin
  if MatchText(AClass, TEXT_FIELDS) then Result:= scgText
  else if MatchText(AClass, MEMO_FIELDS) then Result:= scgMemo
  else if MatchText(AClass, NUMBER_FIELDS) then Result:= scgNumber
  else if MatchText(AClass, DATE_FIELDS) then Result:= scgDateTime
  else Result:= scgUnknown;
end;

{ A clear clash only: text, number and date are three kinds; a memo opens on text; boolean is a matter of mapping rules. }
function ClassClash(const AFact: TSchemaColumn; const AClass: string): Boolean;
var
  Own, Col: TSchemaGroup;
begin
  Own:= ClassGroup(AClass);
  Col:= AFact.Group;
  if Own = scgMemo then Own:= scgText;
  if Col = scgMemo then Col:= scgText;
  Result:= (Own in [scgText, scgNumber, scgDateTime]) and (Col in [scgText, scgNumber, scgDateTime]) and (Own <> Col);
end;

{ ---- SQL texts ---- }

function IsPlainName(const AName: string): Boolean;
begin
  Result:= IsValidIdent(AName.Replace('$', '_'));
end;

{ Select items and INSERT columns that a known table does not have, as one finding. }
function UnknownInSql(const AFacts: ISchemaFacts; const ASql: TStatedSql): TArray<TLintFinding>;
var
  Item  : TDfmrSqlItem;
  Column: string;
  Table, Name, Reason: string;
  Bad   : TStringList;

  procedure Take(const ATable, AColumn: string);
  begin
    if IsUnknown(AFacts, ATable, AColumn) and (not Excepted(AFacts, RULE_UNKNOWN, '', ATable, AColumn)) then Bad.Add(ATable + '.' + AColumn);
  end;

begin
  Result:= nil;
  Bad   := TStringList.Create(dupIgnore, True, False);
  try
    if (ASql.Facts.Verb = svSelect) and (ASql.Facts.Source.Reason = '') then
      for Item in ASql.Facts.Source.Items do
        if Item.Plain and (not Item.Star) and SqlFieldColumn(ASql.Facts.Source, Item.OutName, '', Table, Name, Reason) and
           SameText(Name, Item.Column) then
          Take(Table, Name);
    if ASql.Facts.Verb = svInsert then
      for Column in ASql.Facts.TargetColumns do
        if IsPlainName(Column) then Take(ASql.Facts.TargetTable, Column);
    if Bad.Count > 0 then
      Result:= [FindingAt(RULE_UNKNOWN, Format('The SQL names %s: no such column (field repository)', [string.Join(', ', Bad.ToStringArray)]),
        ASql.Path, ASql.Line, ASql.Col, ASql.EndCol)];
  finally
    Bad.Free;
  end;
end;

{ An INSERT that names its columns and leaves out one the table requires and nothing fills. }
function MissingInSql(const AFacts: ISchemaFacts; const ASql: TStatedSql): TArray<TLintFinding>;
var
  Fact   : TSchemaColumn;
  Column : string;
  Missing: TArray<string>;
  More   : string;
begin
  Result:= nil;
  if (ASql.Facts.Verb <> svInsert) or (Length(ASql.Facts.TargetColumns) = 0) or (not AFacts.KnowsTable(ASql.Facts.TargetTable)) then Exit;
  for Column in ASql.Facts.TargetColumns do
    if not IsPlainName(Column) then Exit;  // a macro or something else that is no plain name
  Missing:= nil;
  for Fact in AFacts.ColumnsOf(ASql.Facts.TargetTable) do
    if Fact.NotNull and (not Fact.Filled) and (not Fact.Calculated) and (not MatchText(Fact.Column, ASql.Facts.TargetColumns)) and
       (not Excepted(AFacts, RULE_REQUIRED, '', Fact.Table, Fact.Column)) then
      Missing:= Missing + [Fact.Column];
  if Length(Missing) = 0 then Exit;
  More  := if Length(Missing) > MAX_LISTED then Format(' and %d more', [Length(Missing) - MAX_LISTED]) else '';
  Result:= [FindingAt(RULE_REQUIRED, Format('This INSERT leaves out %s%s: NOT NULL in %s, without a default, trigger or sequence (field repository)',
    [string.Join(', ', Copy(Missing, 0, MAX_LISTED)), More, ASql.Facts.TargetTable]), ASql.Path, ASql.Line, ASql.Col, ASql.EndCol)];
end;

{ The whole SQL text a site states; '' = none. A dataset built with SQL.Add has one text or none. }
function StatedAt(const AData: TSqlDataset; const ASite: TSqlSite): string;
begin
  Result:= '';
  if (ASite.Kind not in [sskSqlSet, sskSqlAdd]) or (not SpeaksDatabase(AData.DataClass)) then Exit;
  if AData.Has([sskSqlAdd]) then Result:= if AData.InDfm and (AData.Dfm.Sql <> '') then '' else AData.Facts.Sql
  else if ASite.Known then Result:= ASite.Text;
end;

{ The whole SQL texts the unit states: the one text of a dataset, else each text set by one literal or constant. }
function StatedInUnit(const ACtx: TV151FileCtx; const AScan: TSqlTextScan): TArray<TStatedSql>;
var
  Data : TSqlDataset;
  Site : TSqlSite;
  Found: TStatedSql;
begin
  Result:= nil;
  for Data in AScan.Datasets do
    for Site in Data.Sites do
      if StatedAt(Data, Site) <> '' then
      begin
        Found.Facts := ReadSqlText(StatedAt(Data, Site));
        Found.Path  := ACtx.Path;
        Found.Line  := Site.Line;
        Found.Col   := Site.Col;
        Found.EndCol:= Site.EndCol;
        Result:= Result + [Found];
        if Data.Has([sskSqlAdd]) then Break;  // reported where the text starts
      end;
end;

{ ---- field sites ---- }

{ AsInteger of FieldByName('X').AsInteger; a null node when the call result is not used that way. }
function AccessorOf(const ASite: TTSNode): TTSNode;
var
  Call: TTSNode;
begin
  Call:= ASite.Parent;
  if (not Call.IsNull) and (Call.NodeType = 'exprDot') then Call:= Call.Parent;
  if Call.IsNull or (Call.NodeType <> 'exprCall') or Call.Parent.IsNull or (Call.Parent.NodeType <> 'exprDot') or
     (Call.Parent.ChildByField('lhs').EndByte <> Call.EndByte) then
    Exit(Default(TTSNode));
  Result:= Call.Parent.ChildByField('rhs');
end;

function SourceText(const ANode: TTSNode; const ASrc: TBytes): string;
begin
  Result:= '';
  if (not ANode.IsNull) and (Integer(ANode.EndByte) <= Length(ASrc)) then
    Result:= TEncoding.UTF8.GetString(ASrc, Integer(ANode.StartByte), Integer(ANode.EndByte - ANode.StartByte));
end;

function NewQuery(const AStore: ISymbolStore; const ASql: string): TFDQuery;
begin
  Result:= TFDQuery.Create(nil);
  Result.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
  Result.SQL.Text  := ASql;
end;

{ The SELECT gives the field by name, not through a star: its own SQL finding says so. }
function IsListed(const AFacts: TSqlTextFacts; const AField: string): Boolean;
var
  Item: TDfmrSqlItem;
begin
  Result:= False;
  if AFacts.Verb = svSelect then
    for Item in AFacts.Source.Items do
      if (not Item.Star) and SameText(Item.OutName, AField) then Exit(True);
end;

{ A field made at run time or on a form: calculated, lookup, or created by the unit's code. }
function IsMadeField(const ACtx: TV151FileCtx; const AData: TSqlDataset; const AField: string; const ASrc: TBytes): Boolean;
var
  Query: TFDQuery;
begin
  Result:= TRegEx.IsMatch(TEncoding.UTF8.GetString(ASrc), '\bFieldName\s*:=\s*''' + TRegEx.Escape(AField) + '''', [roIgnoreCase]);
  if Result or (not AData.InDfm) or (ACtx.Store is not TSQLiteSymbolStore) then Exit;
  Query:= NewQuery(ACtx.Store, 'SELECT COUNT(*) FROM dfm_objects o ' +
    'JOIN dfm_properties n ON n.file_id = o.file_id AND n.object_ordinal = o.ordinal AND n.name = ''FieldName'' AND n.value_text = :n COLLATE NOCASE ' +
    'JOIN dfm_properties k ON k.file_id = o.file_id AND k.object_ordinal = o.ordinal AND k.name = ''FieldKind'' AND k.value_text <> ''fkData'' ' +
    'WHERE o.parent_name = :p COLLATE NOCASE');
  try
    Query.ParamByName('n').AsString:= AField;
    Query.ParamByName('p').AsString:= AData.Dfm.Name;
    Query.Open;
    Result:= Query.Fields[0].AsInteger > 0;
  finally
    Query.Free;
  end;
end;

{ DL_EXCEPTIONS dataset key: <form unit>.<component>, as the other schema rules write it; a local has its own name. }
function DatasetKeyOf(const ACtx: TV151FileCtx; const AData: TSqlDataset): string;
begin
  Result:= if AData.Scope = ssMember then ChangeFileExt(ExtractFileName(ACtx.Path), '') + '.' + AData.Name else AData.Name;
end;

type
  { One FieldByName / FindField site and the column behind it. }
  TFieldSite = record
    Data  : TSqlDataset;
    Site  : TSqlSite;
    Table : string;
    Column: string;
    Source: TBytes;
  end;

function CheckSiteType(const ACtx: TV151FileCtx; const AScan: TSqlTextScan; const AFacts: ISchemaFacts; const ASite: TFieldSite;
  const AFact: TSchemaColumn): TArray<TLintFinding>;
var
  Access, Clash: string;
begin
  Result:= nil;
  Access:= SourceText(AccessorOf(ASite.Site.Node), ASite.Source);
  Clash := if AFact.Calculated then '' else AccessorClash(AFact, Access);
  if (Clash = '') or Excepted(AFacts, RULE_TYPE, DatasetKeyOf(ACtx, ASite.Data), ASite.Table, ASite.Column) or
     (AScan.OutsideReason(ASite.Data, False) <> '') then
    Exit;
  Result:= [FindingAt(RULE_TYPE, Format('%s.%s is %s: %s %s (field repository)', [ASite.Table, ASite.Column, AFact.TypeText, Access, Clash]),
    ACtx.Path, ASite.Site.Line, ASite.Site.Col, ASite.Site.EndCol)];
end;

function CheckSiteName(const ACtx: TV151FileCtx; const AScan: TSqlTextScan; const AFacts: ISchemaFacts; const ASite: TFieldSite): TArray<TLintFinding>;
begin
  Result:= nil;
  { FindField answers nil for a field that is not there: the code asks on purpose }
  if (ASite.Site.Member <> MEMBER_FIELD_BY_NAME) or (not IsUnknown(AFacts, ASite.Table, ASite.Column)) or
     IsListed(ASite.Data.Facts, ASite.Site.Text) then
    Exit;
  if Excepted(AFacts, RULE_UNKNOWN, DatasetKeyOf(ACtx, ASite.Data), ASite.Table, ASite.Column) or
     IsMadeField(ACtx, ASite.Data, ASite.Site.Text, ASite.Source) or (AScan.OutsideReason(ASite.Data, False) <> '') then
    Exit;
  Result:= [FindingAt(RULE_UNKNOWN, Format('%s reads table %s, which has no column %s (field repository) -- FieldByName raises at run time',
    [ASite.Data.Name, ASite.Table, ASite.Column]), ACtx.Path, ASite.Site.Line, ASite.Site.Col, ASite.Site.EndCol)];
end;

function CheckSites(const ACtx: TV151FileCtx; const AScan: TSqlTextScan; const AFacts: ISchemaFacts): TArray<TLintFinding>;
var
  Item  : TFieldSite;
  Fact  : TSchemaColumn;
  Reason: string;
  Data  : TSqlDataset;
  Site  : TSqlSite;
  Names, Types: Boolean;
begin
  Result:= nil;
  Names := ACtx.Wants(RULE_UNKNOWN);
  Types := ACtx.Wants(RULE_TYPE);
  if not (Names or Types) then Exit;
  Item.Source:= TAstParseCache.Get(ACtx.Path).Src;
  for Data in AScan.Datasets do
    for Site in Data.Sites do
    begin
      Item.Data:= Data;
      Item.Site:= Site;
      if (Site.Kind <> sskField) or (not Site.Known) or (not SpeaksDatabase(Data.DataClass)) or
         (not AScan.ColumnOf(Item.Data, Item.Site.Text, Item.Table, Item.Column, Reason)) or (not AFacts.KnowsTable(Item.Table)) then
        Continue;
      if AFacts.FindColumn(Item.Table, Item.Column, Fact) then
      begin
        if Types then Result:= Result + CheckSiteType(ACtx, AScan, AFacts, Item, Fact);
      end
      else if Names then Result:= Result + CheckSiteName(ACtx, AScan, AFacts, Item);
    end;
end;

function CheckUnit(const ACtx: TV151FileCtx; const AScan: TSqlTextScan; const AFacts: ISchemaFacts): TArray<TLintFinding>;
var
  Stated: TStatedSql;
  Names, Required: Boolean;
begin
  Result  := nil;
  Names   := ACtx.Wants(RULE_UNKNOWN);
  Required:= ACtx.Wants(RULE_REQUIRED);
  if Names or Required then
    for Stated in StatedInUnit(ACtx, AScan) do
    begin
      if Names then Result:= Result + UnknownInSql(AFacts, Stated);
      if Required then Result:= Result + MissingInSql(AFacts, Stated);
    end;
  Result:= Result + CheckSites(ACtx, AScan, AFacts);
end;

{ ---- forms ---- }

function ListText(const ARows: TArray<TDfmPropertyRow>; ARow: Integer): string;
var
  I    : Integer;
  Parts: TArray<string>;
begin
  if ARows[ARow].ValueKind <> KIND_LIST then Exit(ARows[ARow].ValueText);
  Parts:= nil;
  for I:= ARow + 1 to High(ARows) do
    if ARows[I].Parent = ARow then Parts:= Parts + [ARows[I].ValueText]
    else if ARows[I].Depth = 0 then Break;
  Result:= string.Join(sLineBreak, Parts).TrimRight;
end;

{ One property row of a block. }
procedure TakeRow(const ARows: TArray<TDfmPropertyRow>; ARow: Integer; var ADataset: TFormDataset; var AField: TFormField);
var
  Row: TDfmPropertyRow;
begin
  Row:= ARows[ARow];
  if Row.Depth > 0 then Exit;
  if MatchText(Row.Name, LIST_PROPS) and (ADataset.Facts.Sql = '') then
  begin
    ADataset.Facts:= ReadSqlText(ListText(ARows, ARow));
    ADataset.Line := Row.StartLine;
    ADataset.Col  := Row.StartCol;
  end
  else if SameText(Row.Name, PROP_TABLE_NAME) then ADataset.TableName:= Row.ValueText
  else if SameText(Row.Name, 'Origin') then AField.Origin:= Row.ValueText
  else if SameText(Row.Name, 'FieldKind') then AField.Data:= SameText(Row.ValueText, 'fkData')
  else if SameText(Row.Name, PROP_FIELD_NAME) then
  begin
    AField.FieldName:= Row.ValueText;
    AField.NameLine := Row.StartLine;
    AField.NameCol  := Row.StartCol;
  end;
end;

function NewDataset(const AObject: TDfmObjectRow): TFormDataset;
begin
  Result:= Default(TFormDataset);
  Result.Name     := AObject.Name;
  Result.ClassName:= AObject.ClassName;
  Result.ObjKind  := AObject.ObjKind;
end;

function NewField(const AObject: TDfmObjectRow): TFormField;
begin
  Result:= Default(TFormField);
  Result.Name     := AObject.Name;
  Result.ClassName:= AObject.ClassName;
  Result.Data     := True;
  Result.Dataset  := -1;
  Result.Line     := AObject.StartLine;
  Result.Col      := AObject.StartCol;
end;

{ Datasets and persistent fields out of the blocks and property rows of a form. }
procedure TakeObjects(const AObjects: TArray<TDfmObjectRow>; const ARows: TArray<TDfmPropertyRow>; var AForm: TSchemaForm);
var
  Dataset: TFormDataset;
  Field  : TFormField;
  Owners : TDictionary<Integer, Integer>;  // depth -> dataset of the open block; -1 = it is none
  I, Row : Integer;
begin
  Row   := 0;
  Owners:= TDictionary<Integer, Integer>.Create;
  try
    for I:= 0 to High(AObjects) do
    begin
      Dataset:= NewDataset(AObjects[I]);
      Field  := NewField(AObjects[I]);
      while (Row <= High(ARows)) and (ARows[Row].ObjectOrdinal <= I) do
      begin
        if ARows[Row].ObjectOrdinal = I then TakeRow(ARows, Row, Dataset, Field);
        Inc(Row);
      end;
      Owners.AddOrSetValue(AObjects[I].Depth, -1);
      if (I > 0) and ((Dataset.Facts.Sql <> '') or (Dataset.TableName <> '')) then
      begin
        Owners[AObjects[I].Depth]:= Length(AForm.Datasets);
        AForm.Datasets:= AForm.Datasets + [Dataset];
      end
      else if (Field.FieldName <> '') and EndsText('Field', Field.ClassName) and Owners.TryGetValue(AObjects[I].Depth - 1, Field.Dataset) and
              (Field.Dataset >= 0) then
        AForm.Fields:= AForm.Fields + [Field];
    end;
  finally
    Owners.Free;
  end;
end;

{ One text .dfm; a binary one gives nothing. }
function ReadForm(const ADfm: string): TSchemaForm;
var
  Bytes : TBytes;
  Parser: TDFMParser;
  Parsed: TParseResult;
begin
  Result:= Default(TSchemaForm);
  Bytes := TFile.ReadAllBytes(ADfm);
  if (Length(Bytes) = 0) or (Bytes[0] = BINARY_DFM_BYTE) or (Bytes[0] = Ord('T')) then Exit;
  Bytes := EnsureUtf8Bytes(Bytes);
  Parser:= TDFMParser.Create;
  try
    Parsed:= Parser.Parse(Bytes, ADfm);
  finally
    Parser.Free;
  end;
  if Length(Parsed.DfmObjects) = 0 then Exit;
  Result.Root:= Parsed.DfmObjects[0].ClassName;
  TakeObjects(Parsed.DfmObjects, ExtractDfmPropertyRows(ADfm, TEncoding.UTF8.GetString(Bytes), Parsed.DfmObjects), Result);
end;

{ The form beside a unit, read once per process and again when the file changes. }
function FormOf(const ADfm: string): TSchemaForm;
var
  Key  : string;
  Entry: TFormEntry;
  Stamp: TDateTime;
  Known: Boolean;
begin
  Result:= Default(TSchemaForm);
  if not TFile.Exists(ADfm) then Exit;
  Key  := LowerCase(TPath.GetFullPath(ADfm));
  Stamp:= TFile.GetLastWriteTime(ADfm);
  TMonitor.Enter(GLock);
  try
    Known:= GForms.TryGetValue(Key, Entry) and SameValue(Entry.Stamp, Stamp);
    if not Known then
    begin
      Entry.Stamp:= Stamp;
      Entry.Form := ReadForm(ADfm);
      GForms.AddOrSetValue(Key, Entry);
    end;
    Result:= Entry.Form;
  finally
    TMonitor.Exit(GLock);
  end;
end;

{ The table column behind a persistent field. }
function ColumnOfField(const AForm: TSchemaForm; const AField: TFormField; out ATable, AColumn: string): Boolean;
var
  Data  : TFormDataset;
  Reason: string;
begin
  ATable := '';
  AColumn:= '';
  Data:= AForm.Datasets[AField.Dataset];
  if (not AField.Data) or (not SameText(Data.ObjKind, OBJECT_KIND)) or (not SpeaksDatabase(Data.ClassName)) then Exit(False);
  if Data.Facts.Sql <> '' then
    Exit((Data.Facts.Verb = svSelect) and (Data.Facts.Source.Reason = '') and
      SqlFieldColumn(Data.Facts.Source, AField.FieldName, AField.Origin, ATable, AColumn, Reason));
  Result := Data.TableName <> '';
  ATable := CleanTableName(Data.TableName);
  AColumn:= UpperCase(AField.FieldName);
end;

{ True when no code of the index sets the SQL or table of the form's dataset, hands it on or aliases it. }
function NoCodeChanges(const AStore: ISymbolStore; const APas, ARoot, ADataset: string): Boolean;
var
  Query: TFDQuery;
begin
  Query:= NewQuery(AStore, 'SELECT s.id, m.name_text, r.id FROM symbols s JOIN files f ON f.id = s.file_id JOIN symbols c ON c.id = s.parent_id ' +
    'LEFT JOIN refs r ON r.symbol_id = s.id AND r.kind <> ''write-through'' LEFT JOIN ref_receivers rr ON rr.receiver_ref_id = r.id ' +
    'LEFT JOIN refs m ON m.id = rr.ref_id WHERE s.kind = ''field'' AND s.name = :n COLLATE NOCASE AND c.name = :c COLLATE NOCASE ' +
    'AND f.path = :p COLLATE NOCASE');
  try
    Query.ParamByName('n').AsString:= ADataset;
    Query.ParamByName('c').AsString:= ARoot;
    Query.ParamByName('p').AsString:= APas;
    Query.Open;
    Result:= not Query.Eof;
    while Result and (not Query.Eof) do
    begin
      if not Query.Fields[Ord(fxRef)].IsNull then
        Result:= (Query.Fields[Ord(fxMember)].AsString <> '') and (not MatchText(Query.Fields[Ord(fxMember)].AsString, CHANGE_MEMBERS));
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

{ True when the index shows that only this .dfm decides what the dataset reads. }
function IsFixed(const AStore: ISymbolStore; const APas, ARoot, ADataset: string): Boolean;
var
  Query: TFDQuery;
begin
  if AStore is not TSQLiteSymbolStore then Exit(False);
  Query:= NewQuery(AStore, 'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name IN (''ref_receivers'', ''dfm_properties'')');
  try
    Query.Open;
    Result:= Query.Fields[0].AsInteger = FACT_TABLES;
    Query.Close;
    if not Result then Exit;
    { a descendant form with its own SQL }
    Query.SQL.Text:= 'SELECT COUNT(*) FROM dfm_objects o JOIN dfm_properties p ON p.file_id = o.file_id AND p.object_ordinal = o.ordinal ' +
      'WHERE o.name = :n COLLATE NOCASE AND o.obj_kind = ''inherited'' AND p.name IN (''SQL.Strings'', ''CommandText.Strings'', ''CommandText'', ''TableName'')';
    Query.ParamByName('n').AsString:= ADataset;
    Query.Open;
    Result:= Query.Fields[0].AsInteger = 0;
    Query.Close;
  finally
    Query.Free;
  end;
  Result:= Result and NoCodeChanges(AStore, APas, ARoot, ADataset);
end;

function FormKeyOf(const APas, ADataset: string): string;
begin
  Result:= ChangeFileExt(ExtractFileName(APas), '') + '.' + ADataset;
end;

{ One persistent field of the form. }
function CheckFormField(const ACtx: TV151FileCtx; const AFacts: ISchemaFacts; const AForm: TSchemaForm; const AField: TFormField): TArray<TLintFinding>;
var
  Data  : TFormDataset;
  Table, Column, Rule: string;
  Fact  : TSchemaColumn;
begin
  Result:= nil;
  if (not ColumnOfField(AForm, AField, Table, Column)) or (not AFacts.KnowsTable(Table)) then Exit;
  Data:= AForm.Datasets[AField.Dataset];
  Rule:= '';
  if AFacts.FindColumn(Table, Column, Fact) then
  begin
    if (not Fact.Calculated) and ClassClash(Fact, AField.ClassName) then Rule:= RULE_TYPE;
  end
  else if IsUnknown(AFacts, Table, Column) and (not IsListed(Data.Facts, AField.FieldName)) then Rule:= RULE_UNKNOWN;
  if (Rule = '') or (not ACtx.Wants(Rule)) or Excepted(AFacts, Rule, FormKeyOf(ACtx.Path, Data.Name), Table, Column) or
     (not IsFixed(ACtx.Store, ACtx.Path, AForm.Root, Data.Name)) then
    Exit;
  if Rule = RULE_TYPE then
    Exit([FindingAt(RULE_TYPE, Format('%s is a %s, but %s.%s is %s (field repository) -- the dataset does not open',
      [AField.Name, AField.ClassName, Table, Column, Fact.TypeText]), ACtx.DfmPath, AField.Line, AField.Col, AField.Col)]);
  Result:= [FindingAt(RULE_UNKNOWN, Format('%s names column %s, which table %s does not have (field repository) -- the dataset does not open',
    [AField.Name, Column, Table]), ACtx.DfmPath, AField.NameLine, AField.NameCol, AField.NameCol)];
end;

function CheckForm(const ACtx: TV151FileCtx; const AFacts: ISchemaFacts): TArray<TLintFinding>;
var
  Form : TSchemaForm;
  Field: TFormField;
  Data : TFormDataset;
  Found: TStatedSql;
begin
  Result:= nil;
  Form  := FormOf(ACtx.DfmPath);
  for Field in Form.Fields do Result:= Result + CheckFormField(ACtx, AFacts, Form, Field);
  for Data in Form.Datasets do
  begin
    if (Data.Facts.Sql = '') or (not SpeaksDatabase(Data.ClassName)) then Continue;
    Found.Facts := Data.Facts;
    Found.Path  := ACtx.DfmPath;
    Found.Line  := Data.Line;
    Found.Col   := Data.Col;
    Found.EndCol:= Data.Col;
    if ACtx.Wants(RULE_UNKNOWN) then Result:= Result + UnknownInSql(AFacts, Found);
    if ACtx.Wants(RULE_REQUIRED) then Result:= Result + MissingInSql(AFacts, Found);
  end;
end;

{ ---- persistent fields in code ---- }

type
  { The columns of the query of UsesOf. }
  TUseColumn = (ucLine, ucCol, ucEndCol, ucName, ucPas, ucRoot, ucAccessor);  // dl:ok enum-ordinal-persisted@f797 -- REVIEWED 2026-11-24 v154 SCHEMA: Ord() only indexes Query.Fields[] of a read; nothing is persisted

  { A use of a persistent field: dmMain.tblOrdersNOTE.AsInteger. }
  TFieldUse = record
    Line, Col, EndCol: Integer;
    Name    : string;     // of the component
    Pas     : string;     // unit that declares it
    Root    : string;     // its class
    Accessor: string;
  end;

function UsesOf(const ACtx: TV151FileCtx): TArray<TFieldUse>;
var
  Query: TFDQuery;
  Item : TFieldUse;
begin
  Result:= nil;
  Query:= NewQuery(ACtx.Store, 'SELECT DISTINCT r.start_line, r.start_col, r.end_col, s.name, f.path, c.name, m.name_text FROM refs r ' +
    'JOIN symbols s ON s.id = r.symbol_id AND s.kind = ''field'' JOIN files f ON f.id = s.file_id JOIN symbols c ON c.id = s.parent_id ' +
    'JOIN ref_receivers rr ON rr.receiver_ref_id = r.id JOIN refs m ON m.id = rr.ref_id ' +
    'WHERE r.file_id = :f AND m.name_text COLLATE NOCASE IN (' + ACCESSOR_LIST + ') ORDER BY 1, 2');
  try
    Query.ParamByName('f').AsLargeInt:= ACtx.FileId;
    Query.Open;
    while not Query.Eof do
    begin
      Item.Line    := Query.Fields[Ord(ucLine)].AsInteger;
      Item.Col     := Query.Fields[Ord(ucCol)].AsInteger;
      Item.EndCol  := Query.Fields[Ord(ucEndCol)].AsInteger;
      Item.Name    := Query.Fields[Ord(ucName)].AsString;
      Item.Pas     := Query.Fields[Ord(ucPas)].AsString;
      Item.Root    := Query.Fields[Ord(ucRoot)].AsString;
      Item.Accessor:= Query.Fields[Ord(ucAccessor)].AsString;
      Result:= Result + [Item];
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

function CheckUse(const ACtx: TV151FileCtx; const AFacts: ISchemaFacts; const AUse: TFieldUse): TArray<TLintFinding>;
var
  Form : TSchemaForm;
  Field: TFormField;
  Table, Column, Clash: string;
  Fact : TSchemaColumn;
begin
  Result:= nil;
  Form:= FormOf(ChangeFileExt(AUse.Pas, '.dfm'));
  if not SameText(Form.Root, AUse.Root) then Exit;
  for Field in Form.Fields do
    if SameText(Field.Name, AUse.Name) and ColumnOfField(Form, Field, Table, Column) and AFacts.KnowsTable(Table) and
       AFacts.FindColumn(Table, Column, Fact) and (not Fact.Calculated) then
    begin
      Clash:= AccessorClash(Fact, AUse.Accessor);
      if (Clash = '') or Excepted(AFacts, RULE_TYPE, FormKeyOf(AUse.Pas, Form.Datasets[Field.Dataset].Name), Table, Column) or
         (not IsFixed(ACtx.Store, AUse.Pas, Form.Root, Form.Datasets[Field.Dataset].Name)) then
        Continue;
      Result:= Result + [FindingAt(RULE_TYPE, Format('%s.%s is %s: %s %s (field repository)', [Table, Column, Fact.TypeText, AUse.Accessor, Clash]),
        ACtx.Path, AUse.Line, AUse.Col, AUse.EndCol)];
    end;
end;

function CheckFieldUse(const ACtx: TV151FileCtx; const AFacts: ISchemaFacts): TArray<TLintFinding>;
var
  Item : TFieldUse;
  Lines: TArray<string>;
  Query: TFDQuery;
begin
  Result:= nil;
  if (ACtx.Store is not TSQLiteSymbolStore) or (ACtx.FileId = 0) then Exit;
  Query:= NewQuery(ACtx.Store, 'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = ''ref_receivers''');
  try
    Query.Open;
    if Query.Fields[0].AsInteger = 0 then Exit;
  finally
    Query.Free;
  end;
  Lines:= TEncoding.UTF8.GetString(TAstParseCache.Get(ACtx.Path).RawSrc).Split([#10]);
  for Item in UsesOf(ACtx) do
    { an edited, not reindexed file is not judged by its old positions }
    if (Item.Line <= Length(Lines)) and SameText(Copy(Lines[Item.Line - 1], Item.Col, Item.EndCol - Item.Col), Item.Name) then
      Result:= Result + CheckUse(ACtx, AFacts, Item);
end;

initialization
  GLock := TObject.Create;
  GForms:= TDictionary<string, TFormEntry>.Create;

finalization
  GFacts:= nil;
  GForms.Free;
  GLock.Free;

end.
