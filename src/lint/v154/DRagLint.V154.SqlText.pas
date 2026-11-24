unit DRagLint.V154.SqlText;

{ Wave v154 (1.54.0-alpha) shared helper S1, owned by lane SQL; lane SCHEMA reads it. API FROZEN by its first commit:
  ReadSqlText (one SQL text: verb, parameter names, tables, columns) and TSqlTextScan (one unit: every dataset the
  unit's code uses, with its SQL text from the .dfm or the code and the sites that set, open or ask it). Whatever is
  not understood carries a reason; nothing is guessed. Reuses DRagLint.FieldRepo.DfmReadSql. Read only. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Interfaces
  , DRagLint.FieldRepo.DfmReadSql
  ;

type
  /// <summary>What a SQL text does.</summary>
  TSqlVerb = (svNone, svSelect, svInsert, svUpdate, svDelete, svMerge, svProcedure, svOther);

  /// <summary>The facts of one SQL text.</summary>
  /// <remarks>ParamReason = '' means ParamNames is the complete list; with a reason the list is not usable.
  /// Source is filled for svSelect only and has its own Reason. TargetColumns is the column list an INSERT names
  /// (empty when it names none).</remarks>
  TSqlTextFacts = record
    /// <summary>The SQL text; '' = none.</summary>
    Sql          : string;
    /// <summary>The statement kind.</summary>
    Verb         : TSqlVerb;
    /// <summary>Distinct parameter names without the colon, as first written.</summary>
    ParamNames   : TArray<string>;
    /// <summary>'' = the parameter names are known; otherwise why they are not.</summary>
    ParamReason  : string;
    /// <summary>Tables and select list of a SELECT.</summary>
    Source       : TDfmrSqlSource;
    /// <summary>INSERT / UPDATE / DELETE / MERGE: clean upper-case table; '' = not stated plainly.</summary>
    TargetTable  : string;
    /// <summary>INSERT: the columns it names, upper case, without quotes.</summary>
    TargetColumns: TArray<string>;
    /// <summary>True when the SQL has a parameter of that name (any case).</summary>
    /// <param name="AName">Parameter name without the colon.</param>
    /// <returns>False also when the names are not known.</returns>
    function HasParam(const AName: string): Boolean;
  end;

  /// <summary>Kind of one place where the unit touches a dataset.</summary>
  /// <remarks>
  /// sskSqlSet: the whole SQL is set (SQL.Text, CommandText, Open('..')). sskSqlAdd / sskSqlClear: SQL.Add / SQL.Clear.
  /// sskSqlOther: the SQL is changed or handed out in a way that is not read. sskParam: ParamByName / FindParam.
  /// sskParamsOther: any other use of Params, or a link that fills them (Member says which). sskRun: Open, ExecSQL, Execute, Active := True.
  /// sskField: FieldByName / FindField. sskNoParams: ParamCheck or parameter creation is switched. sskCreated: the
  /// variable is assigned. sskPassed: the dataset itself is passed on, stored or aliased.
  /// </remarks>
  TSqlSiteKind = (sskSqlSet, sskSqlAdd, sskSqlClear, sskSqlOther, sskParam, sskParamsOther, sskRun, sskField, sskNoParams,
    sskCreated, sskPassed);

  /// <summary>One place where the unit touches a dataset.</summary>
  TSqlSite = record
    Kind    : TSqlSiteKind;
    /// <summary>Member name, lower case ('parambyname', 'open', 'items').</summary>
    Member  : string;
    /// <summary>The literal the site states (SQL, parameter name, field name, created class); valid when Known.</summary>
    Text    : string;
    /// <summary>True when Text is one literal or constant.</summary>
    Known   : Boolean;
    /// <summary>Number of call arguments.</summary>
    ArgCount: Integer;
    /// <summary>1-based position of the member name (of the dataset name for sskCreated / sskPassed).</summary>
    Line    : Integer;
    Col     : Integer;
    EndCol  : Integer;
    /// <summary>Start byte in the parsed source; sites of one dataset are in source order.</summary>
    Pos     : Cardinal;
    /// <summary>Start byte of the outermost routine around the site; 0 = none.</summary>
    Routine : Cardinal;
    /// <summary>Identity of the statement list the site's own statement stands in.</summary>
    ListPos : UInt64;
    /// <summary>The member's syntax node; valid while the file stays in TAstParseCache.</summary>
    Node    : TTSNode;
  end;

  /// <summary>How the unit reaches a dataset.</summary>
  TSqlScope = (ssLocal, ssParameter, ssMember, ssUnitVar, ssOther);

  /// <summary>What the .dfm states about one dataset component.</summary>
  TSqlDfmDataset = record
    Name       : string;
    ClassName  : string;
    /// <summary>object, inherited or inline.</summary>
    ObjKind    : string;
    /// <summary>SQL.Strings (or CommandText.Strings / CommandText), lines joined; '' = none.</summary>
    Sql        : string;
    /// <summary>TableName as written; '' = none.</summary>
    TableName  : string;
    /// <summary>UpdateOptions.UpdateTableName as written; '' = none.</summary>
    UpdateTable: string;
    /// <summary>True when ParamCheck or ResourceOptions.ParamCreate is False.</summary>
    NoParams   : Boolean;
    /// <summary>True when a MasterSource / DataSource / MasterFields fills the parameters.</summary>
    HasMaster  : Boolean;
    /// <summary>Parameters of ParamData / Params / Parameters that carry a value.</summary>
    ValuedParams: TArray<string>;
    /// <summary>1-based line of the component.</summary>
    Line       : Integer;
  end;

  /// <summary>One dataset of a unit.</summary>
  TSqlDataset = class
  strict private
    FName     : string;
    FScope    : TSqlScope;
    FDataClass: string;
    FOwnerClass: string;
    FSites    : TArray<TSqlSite>;
    FInDfm    : Boolean;
    FDfm      : TSqlDfmDataset;
    FFacts    : TSqlTextFacts;
    FReason   : string;
    FTable    : string;
    FSymbolId : Int64;
  public
    /// <summary>True when a site of one of AKinds exists.</summary>
    /// <param name="AKinds">Kinds to look for.</param>
    /// <returns>Whether one exists.</returns>
    function Has(const AKinds: array of TSqlSiteKind): Boolean;
    /// <summary>The dataset as the code names it first (Q, dmMain.qryX).</summary>
    property Name: string read FName write FName;
    /// <summary>How the unit reaches it.</summary>
    property Scope: TSqlScope read FScope write FScope;
    /// <summary>Declared class without a unit prefix; '' = not known.</summary>
    property DataClass: string read FDataClass write FDataClass;
    /// <summary>The class whose field this is (ssMember); '' otherwise.</summary>
    property OwnerClass: string read FOwnerClass write FOwnerClass;
    /// <summary>Sites in source order.</summary>
    property Sites: TArray<TSqlSite> read FSites write FSites;
    /// <summary>True when a .dfm object stands behind the name; Dfm is valid then.</summary>
    property InDfm: Boolean read FInDfm write FInDfm;
    /// <summary>What the .dfm states.</summary>
    property Dfm: TSqlDfmDataset read FDfm write FDfm;
    /// <summary>Facts of the one SQL text; Facts.Sql = '' when Reason is set.</summary>
    property Facts: TSqlTextFacts read FFacts write FFacts;
    /// <summary>'' = the dataset has exactly one known SQL text; otherwise why not.</summary>
    property Reason: string read FReason write FReason;
    /// <summary>Clean upper-case table: UpdateTableName, else TableName of the .dfm, else the one table of the
    /// SELECT, else the target table; '' = not stated. Set only when no code in the unit can change it.</summary>
    property Table: string read FTable write FTable;
    /// <summary>Index symbol behind a member, unit variable or other unit's dataset; 0 = unknown or local.</summary>
    property SymbolId: Int64 read FSymbolId write FSymbolId;
  end;

  /// <summary>Every dataset one unit uses.</summary>
  /// <remarks>Built in the constructor from the cached parse tree, the unit's own .dfm, the .dfm of another unit's
  /// dataset (through the index) and the index. Without an index, names the unit does not declare stay ssOther with a
  /// Reason. A text .dfm only: a binary one gives the reason "the DFM is binary". Not thread-safe.</remarks>
  TSqlTextScan = class  // dl:ok god-class@0e13,high-response@0e13 -- REVIEWED 2026-11-23 v154 SQL: one walk over one unit; scope, with and statement-list state belong together
  public type
    { One link of an access chain: Q . SQL . Add ('x'). }
    TLink = record
      Name : string;
      Node : TTSNode;
      Args : TTSNode;   // exprArgs of a call or a subscript; null when none
      Sub  : Boolean;   // Args belong to [..]
    end;
    TLinks = TArray<TLink>;
    { One declaration a routine can see. }
    TDecl = record
      Key    : string;
      TypeName: string;
      IsParam: Boolean;
      Value  : TTSNode; // initialiser of a constant; null for a variable
      IsConst: Boolean;
    end;
    TScopeMap = TDictionary<string, TDecl>;
  strict private
    FFile     : string;
    FSrc      : TBytes;
    FStore    : ISymbolStore;
    FFileId   : Int64;
    FDatasets     : TObjectList<TSqlDataset>;
    FByKey    : TDictionary<string, TSqlDataset>;

    FLate     : TList<TPair<string, TTSNode>>;    // bare uses of a name no member access had shown to be a dataset yet
    FScopes   : TObjectList<TScopeMap>;
    FUnitVars : TDictionary<string, string>;      // lower name -> type
    FConsts   : TDictionary<string, TTSNode>;     // lower name -> initialiser
    FFields   : TDictionary<string, string>;      // class|field -> type
    FDfms     : TDictionary<string, TArray<TSqlDfmDataset>>;
    FDfmRoots : TDictionary<string, string>;      // dfm path -> root class
    FDfmNotes : TDictionary<string, string>;      // dfm path -> why it is not read
    FWith     : TList<TSqlDataset>;               // each open with-target; nil = not a dataset
    FOwner    : string;                           // class of the method being walked
    FRoutine  : Cardinal;
    FList0    : UInt64;                           // statement list being walked
    FHasRecv  : Boolean;                          // the index has ref_receivers, ref_types and dfm_properties
    function Txt(const ANode: TTSNode): string;
    procedure CollectUnit(const ANode: TTSNode; const AClass: string);
    procedure CollectFields(const ANode: TTSNode; const AClass: string);
    procedure AddConst(const ANode: TTSNode; AMap: TScopeMap);
    procedure AddVars(const ANode: TTSNode; AMap: TScopeMap; AParam: Boolean);
    procedure WalkRoutine(const ANode: TTSNode);
    procedure Walk(const ANode: TTSNode);
    procedure WalkChildren(const ANode: TTSNode);
    procedure WalkWith(const ANode: TTSNode);
    procedure WalkAssignment(const ANode: TTSNode);
    procedure WalkControl(const ANode: TTSNode);
    procedure WalkChain(const ANode: TTSNode);
    function Flatten(const ANode: TTSNode; out ALinks: TLinks; out ABase: TTSNode): Boolean;
    procedure Member(const AData: TSqlDataset; const ALinks: TLinks; AFrom: Integer; const ANode: TTSNode);
    procedure SqlMember(const AData: TSqlDataset; const ALinks: TLinks; AFrom: Integer; const ANode: TTSNode);
    procedure ParamsMember(const AData: TSqlDataset; const ALinks: TLinks; AFrom: Integer);
    procedure RunMember(const AData: TSqlDataset; const ALink: TLink);
    function FindDecl(const AName: string; out ADecl: TDecl): Boolean;
    function DatasetOf(const ALinks: TLinks; ACount: Integer; ACreate: Boolean): TSqlDataset;
    function MemberKey(const AName: string; out AType: string): Boolean;
    function NewDataset(const AKey, AName, AType: string; AScope: TSqlScope; const ANode: TTSNode;
      ACreate: Boolean): TSqlDataset;
    procedure AddSite(const AData: TSqlDataset; AKind: TSqlSiteKind; const ANode: TTSNode; const AMember: string;
      const AArg: TTSNode; AArgs: Integer);
    procedure AddCreated(const AData: TSqlDataset; const ANode: TTSNode; const AClass: string);
    function EvalConst(const AName: string; const ANode: TTSNode; out AText: string): Boolean;
    function NewQuery(const ASql: string): TObject;
    function RefValue(const ANode: TTSNode; const AColumn: string): string;
    function SymbolAt(const ANode: TTSNode): Int64;
    function TypeAt(const ANode: TTSNode): string;
    procedure LoadDfm(const ADfm: string);
    procedure BindDfm(const AData: TSqlDataset);
    procedure BindSymbol(const AData: TSqlDataset; const ANode: TTSNode);
    procedure Conclude(const AData: TSqlDataset);
    function OneText(const AData: TSqlDataset; out AText: string): string;
    function Blocked(const AData: TSqlDataset): string;
    function TableExists(const AName: string): Boolean;

  public
    /// <summary>Reads the unit.</summary>
    /// <param name="AFile">The .pas file.</param>
    /// <param name="AStore">The project index; may be nil.</param>
    /// <param name="AFileId">AFile's id in AStore; 0 without one.</param>
    /// <remarks>The caller frees the scan, which owns its datasets.</remarks>
    constructor Create(const AFile: string; const AStore: ISymbolStore; AFileId: Int64);
    destructor Destroy; override;
    /// <summary>The text of a string expression made of literals, constants and + only.</summary>
    /// <param name="ANode">Expression node of this file.</param>
    /// <param name="AText">Receives the text.</param>
    /// <returns>False when the value is not one literal or constant.</returns>
    function Eval(const ANode: TTSNode; out AText: string): Boolean;
    /// <summary>Why another unit may change what this unit sees in the dataset.</summary>
    /// <param name="AData">One of Datasets.</param>
    /// <param name="AParams">True: setting parameters elsewhere counts too.</param>
    /// <returns>'' when the index shows no such use; a reason otherwise, also when there is no index to ask.
    /// Always '' for a local.</returns>
    function OutsideReason(const AData: TSqlDataset; AParams: Boolean): string;
    /// <summary>The table column behind a field of the dataset.</summary>
    /// <param name="AData">One of Datasets.</param>
    /// <param name="AField">Field name.</param>
    /// <param name="ATable">Receives the clean table.</param>
    /// <param name="AColumn">Receives the upper-case column.</param>
    /// <param name="AReason">Receives why there is none ('' when found).</param>
    /// <returns>True when the SELECT or the table property states the column.</returns>
    function ColumnOf(const AData: TSqlDataset; const AField: string; out ATable, AColumn, AReason: string): Boolean;
    /// <summary>The datasets, in order of first use. Owned by the scan.</summary>
    property Datasets: TObjectList<TSqlDataset> read FDatasets;
  end;

/// <summary>Reads one SQL text.</summary>
/// <param name="ASql">SQL text as the component gets it.</param>
/// <returns>The facts. ParamReason is set for an empty text, macros, positional or numbered parameters, a colon inside a
/// comment, EXECUTE BLOCK and DDL (their colons are PSQL variables).</returns>
function ReadSqlText(const ASql: string): TSqlTextFacts;

/// <summary>True for a class whose SQL text decides its parameters.</summary>
/// <param name="AClass">Class name without a unit prefix.</param>
/// <returns>True for the known query and command classes; descendants are not known here.</returns>
function IsSqlClass(const AClass: string): Boolean;

implementation

uses
  System.IOUtils
  , System.StrUtils
  , System.Math
  , System.Generics.Defaults
  , System.Character
  , System.RegularExpressions
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , DRagLint.Core.Model
  , DRagLint.Core.Encoding
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Parser.DFM
  , DRagLint.Parser.DFMProps
  , DRagLint.Storage.SQLite
  ;

const
  LF = #10;
  QUOTE = '''';
  MULTI_QUOTE = '''''''';
  SEP = '|';
  SELF_NAME = 'self';
  CREATE_NAME = 'create';
  KIND_LIST = 'list';
  KIND_COLLECTION = 'collection';
  KIND_ITEM = 'item';
  MAX_PLAIN_LINKS = 2;       // Unit-level dataset path: Form.Query
  BINARY_DFM_BYTE = $FF;
  TWO_CHARS = 2;

  SQL_CLASSES: array[0..16] of string = ('TFDQuery', 'TFDCommand', 'TQuery', 'TADOQuery', 'TSQLQuery', 'TIBQuery', 'TIBSQL',
    'TUniQuery', 'TUniSQL', 'TZQuery', 'TZReadOnlyQuery', 'TMyQuery', 'TOraQuery', 'TMSQuery', 'TPgQuery', 'TIBCQuery', 'TSQLDataSet');

  RUN_MEMBERS: array[0..6] of string = ('open', 'execsql', 'execute', 'execproc', 'openorexecute', 'execquery', 'active');
  SQL_MEMBERS: array[0..1] of string = ('sql', 'commandtext');
  PARAMS_MEMBERS: array[0..1] of string = ('params', 'parameters');
  PARAM_CALLS: array[0..1] of string = ('parambyname', 'findparam');
  FIELD_CALLS: array[0..1] of string = ('fieldbyname', 'findfield');
  NO_PARAM_MEMBERS: array[0..1] of string = ('paramcheck', 'resourceoptions');
  { Links that fill parameters from another dataset. }
  MASTER_MEMBERS: array[0..3] of string = ('mastersource', 'masterfields', 'detailfields', 'datasource');
  { Members that hand the dataset's SQL on or replace it as a whole. }
  UNREAD_MEMBERS: array[0..14] of string = ('command', 'assign', 'selectsql', 'insertsql', 'updatesql', 'deletesql', 'refreshsql',
    'sqls', 'macros', 'macrobyname', 'loadfromfile', 'clonecursor', 'data', 'tablename', 'commandtype');
  { Arguments that do not hand the dataset on. }
  HARMLESS_CALLS: array[0..3] of string = ('freeandnil', 'assigned', 'assert', 'freemem');
  EXPR_NODES: array[0..3] of string = ('identifier', 'exprDot', 'exprCall', 'exprSubscript');
  DECL_NODES: array[0..9] of string = ('declArgs', 'declVars', 'declConsts', 'declTypes', 'declUses', 'declProc', 'typeref', 'declLabels',
    'declClass', 'declIntf');
  LIST_NODES: array[0..1] of string = ('block', 'statements');
  CONTROL_NODES: array[0..7] of string = ('if', 'ifElse', 'while', 'for', 'foreach', 'case', 'caseCase', 'repeat');
  LIST_SHIFT = 32;
  DDL_WORDS: array[0..9] of string = ('CREATE', 'ALTER', 'RECREATE', 'DROP', 'DECLARE', 'BEGIN', 'COMMENT', 'GRANT', 'REVOKE', 'SET');
  EXECUTE_WORD = 'EXECUTE';

  REASON_EMPTY = 'there is no SQL text';
  REASON_BLOCK = 'EXECUTE BLOCK: its colons are PSQL variables';
  REASON_DDL = 'DDL: its colons are PSQL variables';
  REASON_MACRO = 'the SQL has a macro';
  REASON_POSITIONAL = 'the SQL has positional parameters';
  REASON_COMMENT = 'the SQL has a parameter in a comment';
  REASON_NUMBERED = 'the SQL has numbered parameters';
  REASON_BUILT = 'the SQL is built by an expression';
  REASON_PLACES = 'the SQL is assigned in several places';
  REASON_OTHER_SQL = 'the SQL is changed in a way that is not read';
  REASON_PASSED = 'the dataset is passed on';
  REASON_PARAMETER = 'the dataset is a parameter';
  REASON_NO_PARAMS = 'parameter checking is switched';
  REASON_NO_SQL = 'no SQL text in the unit or its DFM';
  REASON_SOURCE = 'the dataset is not created here';
  REASON_BINARY = 'the DFM is binary';
  REASON_INHERITED = 'the component is inherited from another form';
  REASON_NO_INDEX = 'no index to ask about other units';
  REASON_OLD_INDEX = 'the index has no receiver facts';
  REASON_NO_SYMBOL = 'the index does not know the dataset';
  REASON_OUTSIDE = 'another unit changes the dataset or takes it over';
  REASON_OUTSIDE_PARAMS = 'another unit sets parameters of the dataset';
  REASON_DESCENDANT = 'a descendant form has its own SQL';
  REASON_OTHER_UNIT = 'code of the other unit sets the SQL';

function ArrayHas(const AText: string; const AList: array of string): Boolean;
begin
  Result:= MatchText(AText, AList);
end;

function IsSqlClass(const AClass: string): Boolean;
begin
  Result:= ArrayHas(AClass, SQL_CLASSES);
end;

function LeafName(const AName: string): string;
begin
  Result:= AName.Substring(AName.LastIndexOf('.') + 1).Trim;
end;

{ ---- SQL text ---- }

function IsParamStart(AChar: Char): Boolean;
begin
  Result:= AChar.IsLetter or (AChar = '_') or (AChar = '$');
end;

function IsParamChar(AChar: Char): Boolean;
begin
  Result:= AChar.IsLetterOrDigit or CharInSet(AChar, ['_', '$', '#']);
end;

type
  { Reads the parameter names and the text without comments; one use per SQL text. }
  TSqlReader = record
  private
    FSql  : string;
    FPos  : Integer;
    FNames: TArray<string>;
    FBad  : string;
    FClean: string;
    function Peek(AOffset: Integer): Char;
    procedure Keep(ACount: Integer);
    procedure SkipQuoted;
    procedure SkipComment(const AEnd: string);
    procedure Colon;
    procedure Fail(const AReason: string);
  public
    procedure Run(const ASql: string; out ANames: TArray<string>; out ABad, AClean: string);
  end;

function TSqlReader.Peek(AOffset: Integer): Char;
begin
  Result:= if InRange(FPos + AOffset, 1, Length(FSql)) then FSql[FPos + AOffset] else #0;
end;

procedure TSqlReader.Keep(ACount: Integer);
begin
  FClean:= FClean + Copy(FSql, FPos, ACount);
  Inc(FPos, ACount);
end;

procedure TSqlReader.Fail(const AReason: string);
begin
  if FBad = '' then FBad:= AReason;
end;

procedure TSqlReader.SkipQuoted;
var
  Last: Integer;
begin
  Last:= PosEx(Peek(0), FSql, FPos + 1);
  if Last = 0 then Last:= Length(FSql);
  Keep(Last - FPos + 1);
end;

procedure TSqlReader.SkipComment(const AEnd: string);
var
  Last: Integer;
begin
  Last:= PosEx(AEnd, FSql, FPos + TWO_CHARS);
  Last:= if Last = 0 then Length(FSql) + 1 else Last + Length(AEnd);
  if TRegEx.IsMatch(Copy(FSql, FPos, Last - FPos), ':[A-Za-z_]') then Fail(REASON_COMMENT);
  FPos:= Last;
  FClean:= FClean + ' ';
end;

procedure TSqlReader.Colon;
var
  Name: string;
  Last: Integer;
begin
  if CharInSet(Peek(1), [':', '=']) then
  begin
    Keep(TWO_CHARS);
    Exit;
  end;
  if Peek(1) = '"' then
  begin
    Last:= PosEx('"', FSql, FPos + TWO_CHARS);
    if Last = 0 then Last:= Length(FSql) + 1;
    Name:= Copy(FSql, FPos + TWO_CHARS, Last - FPos - TWO_CHARS);
  end
  else if IsParamStart(Peek(1)) then
  begin
    Last:= FPos + 1;
    while (Last <= Length(FSql)) and IsParamChar(FSql[Last]) do Inc(Last);
    Name:= Copy(FSql, FPos + 1, Last - FPos - 1);
    Dec(Last);
  end
  else
  begin
    if Peek(1).IsDigit and (not Peek(-1).IsDigit) then Fail(REASON_NUMBERED);
    Keep(1);
    Exit;
  end;
  if (Name <> '') and (not MatchText(Name, FNames)) then FNames:= FNames + [Name];
  Keep(Last - FPos + 1);
end;

procedure TSqlReader.Run(const ASql: string; out ANames: TArray<string>; out ABad, AClean: string);
begin
  FSql  := ASql;
  FPos  := 1;
  FNames:= nil;
  FBad  := '';
  FClean:= '';
  while FPos <= Length(FSql) do
    case Peek(0) of
      QUOTE, '"', '`': SkipQuoted;
      ':': Colon;
      '-': if Peek(1) = '-' then SkipComment(LF) else Keep(1);
      '/': if Peek(1) = '*' then SkipComment('*/') else Keep(1);
      '?':
      begin
        Fail(REASON_POSITIONAL);
        Keep(1);
      end;
      '&', '!':
      begin
        if IsParamStart(Peek(1)) then Fail(REASON_MACRO);
        Keep(1);
      end;
    else
      Keep(1);
    end;
  ANames:= FNames;
  ABad  := FBad;
  AClean:= FClean;
end;

function TSqlTextFacts.HasParam(const AName: string): Boolean;
begin
  Result:= (ParamReason = '') and MatchText(AName, ParamNames);
end;

function VerbOf(const AWords: TArray<string>): TSqlVerb;
var
  Word: string;
begin
  Result:= svNone;
  if Length(AWords) = 0 then Exit;
  Word:= UpperCase(AWords[0]);
  if MatchStr(Word, ['SELECT', 'WITH']) then Result:= svSelect
  else if (Word = 'INSERT') or (Word = 'REPLACE') then Result:= svInsert
  else if (Word = 'UPDATE') and (Length(AWords) > TWO_CHARS) and SameText(AWords[1], 'OR') then Result:= svInsert
  else if Word = 'UPDATE' then Result:= svUpdate
  else if Word = 'DELETE' then Result:= svDelete
  else if Word = 'MERGE' then Result:= svMerge
  else if (Word = EXECUTE_WORD) or (Word = 'EXEC') or (Word = 'CALL') then Result:= svProcedure
  else Result:= svOther;
end;

{ INSERT INTO t (a, b) / UPDATE t / DELETE FROM t / MERGE INTO t. }
procedure ReadTarget(const ASql: string; var AFacts: TSqlTextFacts);
const
  NAME = '("[^"]+"|[\w$]+)';
  GROUP_COLUMNS = 3;
var
  M   : TMatch;
  Part: string;
begin
  case AFacts.Verb of
    svInsert: M:= TRegEx.Match(ASql, '^[^(]*?\bINTO\s+' + NAME + '\s*(\(([^()]*)\))?', [roIgnoreCase]);
    svUpdate: M:= TRegEx.Match(ASql, '^\s*UPDATE\s+' + NAME, [roIgnoreCase]);
    svDelete: M:= TRegEx.Match(ASql, '^\s*DELETE\s+FROM\s+' + NAME, [roIgnoreCase]);
    svMerge : M:= TRegEx.Match(ASql, '^\s*MERGE\s+INTO\s+' + NAME, [roIgnoreCase]);
  else
    Exit;
  end;
  if not M.Success then Exit;
  AFacts.TargetTable:= CleanTableName(M.Groups[1].Value);
  if (AFacts.Verb = svInsert) and (M.Groups.Count > GROUP_COLUMNS) then
    for Part in M.Groups[GROUP_COLUMNS].Value.Split([',']) do
      AFacts.TargetColumns:= AFacts.TargetColumns + [UpperCase(Part.Trim.DeQuotedString('"'))];
end;

function ReadSqlText(const ASql: string): TSqlTextFacts;
var
  Reader: TSqlReader;
  Clean : string;
  Words : TArray<string>;
begin
  Reader:= Default(TSqlReader);
  Result:= Default(TSqlTextFacts);
  Result.Sql:= ASql;
  Reader.Run(ASql, Result.ParamNames, Result.ParamReason, Clean);
  Words:= Clean.Split([' ', #9, #13, #10, '('], TStringSplitOptions.ExcludeEmpty);
  Result.Verb:= VerbOf(Words);
  if Length(Words) = 0 then Result.ParamReason:= REASON_EMPTY
  else if SameText(Words[0], EXECUTE_WORD) and (Length(Words) > 1) and SameText(Words[1], 'BLOCK') then Result.ParamReason:= REASON_BLOCK
  else if MatchText(Words[0], DDL_WORDS) then Result.ParamReason:= REASON_DDL;
  if Result.Verb = svSelect then Result.Source:= ReadSelectSource(Clean)
  else ReadTarget(Clean, Result);
end;

{ ---- Delphi string literals ---- }

{ The lines between the opening and the closing quotes, without the closing line's indent. }
function MultiLineText(const AText: string): string;
var
  Lines : TArray<string>;
  Indent: Integer;
  I     : Integer;
begin
  Lines := AText.Replace(#13#10, LF).Split([LF]);
  Indent:= Length(Lines[High(Lines)]) - Length(TrimLeft(Lines[High(Lines)]));
  Lines := Copy(Lines, 1, Length(Lines) - TWO_CHARS);
  for I:= 0 to High(Lines) do Lines[I]:= Copy(Lines[I], Indent + 1, MaxInt);
  Result:= string.Join(sLineBreak, Lines);
end;

{ 'it''s'#13#10'x' -> the text; False for a control form that is not read. }
function LiteralText(const ALiteral: string; out AText: string): Boolean;
var
  I, Last, Code: Integer;
  Parts: TArray<string>;
begin
  AText:= '';
  Parts:= nil;
  if ALiteral.StartsWith(MULTI_QUOTE + #13) or ALiteral.StartsWith(MULTI_QUOTE + LF) then
  begin
    AText:= MultiLineText(ALiteral);
    Exit(True);
  end;
  I:= 1;
  while I <= Length(ALiteral) do
    if ALiteral[I] = QUOTE then
    begin
      Last:= PosEx(QUOTE, ALiteral, I + 1);
      if Last = 0 then Exit(False);
      { a doubled quote inside the literal }
      if (I > 1) and (ALiteral[I - 1] = QUOTE) then Parts:= Parts + [QUOTE];
      Parts:= Parts + [Copy(ALiteral, I + 1, Last - I - 1)];
      I:= Last + 1;
    end
    else if ALiteral[I] = '#' then
    begin
      Last:= I + 1;
      while (Last <= Length(ALiteral)) and (ALiteral[Last].IsLetterOrDigit or (ALiteral[Last] = '$')) do Inc(Last);
      if not TryStrToInt(Copy(ALiteral, I + 1, Last - I - 1), Code) then Exit(False);
      Parts:= Parts + [Chr(Code)];
      I:= Last;
    end
    else if ALiteral[I] <= ' ' then Inc(I)
    else Exit(False);
  AText := string.Join('', Parts);
  Result:= True;
end;

{ ---- TSqlDataset ---- }

function TSqlDataset.Has(const AKinds: array of TSqlSiteKind): Boolean;
var
  Site: TSqlSite;
  Kind: TSqlSiteKind;
begin
  for Site in Sites do
    for Kind in AKinds do
      if Site.Kind = Kind then Exit(True);
  Result:= False;
end;

{ ---- TSqlTextScan ---- }

constructor TSqlTextScan.Create(const AFile: string; const AStore: ISymbolStore; AFileId: Int64);
var
  Parsed: TParsedFile;
  Data  : TSqlDataset;
  Late  : TPair<string, TTSNode>;
begin
  inherited Create;
  FFile    := AFile;
  FStore   := AStore;
  FFileId  := AFileId;
  FDatasets    := TObjectList<TSqlDataset>.Create(True);
  FByKey   := TDictionary<string, TSqlDataset>.Create;

  FLate    := TList<TPair<string, TTSNode>>.Create;
  FScopes  := TObjectList<TScopeMap>.Create(True);
  FUnitVars:= TDictionary<string, string>.Create;
  FConsts  := TDictionary<string, TTSNode>.Create;
  FFields  := TDictionary<string, string>.Create;
  FDfms    := TDictionary<string, TArray<TSqlDfmDataset>>.Create;
  FDfmRoots:= TDictionary<string, string>.Create;
  FDfmNotes:= TDictionary<string, string>.Create;
  FWith    := TList<TSqlDataset>.Create;
  Parsed:= TAstParseCache.Get(AFile);
  if Parsed.Tree = nil then Exit;
  FSrc    := Parsed.Src;
  FHasRecv:= TableExists('ref_receivers') and TableExists('ref_types') and TableExists('dfm_properties');
  LoadDfm(TPath.ChangeExtension(AFile, '.dfm'));
  CollectUnit(Parsed.Tree.RootNode, '');
  Walk(Parsed.Tree.RootNode);
  for Late in FLate do
    if FByKey.TryGetValue(Late.Key, Data) then AddSite(Data, sskPassed, Late.Value, 'passed', Default(TTSNode), 0);
  for Data in FDatasets do Conclude(Data);
end;

destructor TSqlTextScan.Destroy;
begin
  FWith.Free;
  FLate.Free;
  FDfmNotes.Free;
  FDfmRoots.Free;
  FDfms.Free;
  FFields.Free;
  FConsts.Free;
  FUnitVars.Free;
  FScopes.Free;
  FByKey.Free;
  FDatasets.Free;
  inherited Destroy;
end;

function TSqlTextScan.Txt(const ANode: TTSNode): string;
var
  First, Last: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  First:= Integer(ANode.StartByte);
  Last := Integer(ANode.EndByte);
  if (Last > First) and (Last <= Length(FSrc)) then Result:= TEncoding.UTF8.GetString(FSrc, First, Last - First);
end;

function TSqlTextScan.TableExists(const AName: string): Boolean;
var
  Query: TFDQuery;
begin
  Result:= False;
  if FStore is not TSQLiteSymbolStore then Exit;
  Query:= NewQuery('SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = :n') as TFDQuery;
  try
    Query.ParamByName('n').AsString:= AName;
    Query.Open;
    Result:= Query.Fields[0].AsInteger > 0;
  finally
    Query.Free;
  end;
end;

{ ---- declarations ---- }

procedure TSqlTextScan.CollectFields(const ANode: TTSNode; const AClass: string);
var
  I    : Integer;
  Child: TTSNode;
  TypeName: string;
begin
  if ANode.NodeType = 'declField' then
  begin
    TypeName:= LeafName(Txt(ANode.ChildByField('type')));
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      Child:= ANode.NamedChild(I);
      if Child.NodeType = 'identifier' then FFields.AddOrSetValue(LowerCase(AClass + SEP + Txt(Child)), TypeName);
    end;
    Exit;
  end;
  if ANode.NodeType = 'declConsts' then
  begin
    AddConst(ANode, nil);
    Exit;
  end;
  if ANode.NodeType = 'declTypes' then
  begin
    CollectUnit(ANode, AClass);
    Exit;
  end;
  for I:= 0 to ANode.NamedChildCount - 1 do CollectFields(ANode.NamedChild(I), AClass);
end;

procedure TSqlTextScan.AddConst(const ANode: TTSNode; AMap: TScopeMap);
var
  I   : Integer;
  Decl, Init: TTSNode;
  Item: TDecl;
begin
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Decl:= ANode.NamedChild(I);
    if (Decl.NodeType <> 'declConst') or (Decl.NamedChildCount < TWO_CHARS) then Continue;
    Init:= Decl.NamedChild(Decl.NamedChildCount - 1);
    if Init.NodeType <> 'defaultValue' then Continue;
    Item:= Default(TDecl);
    Item.IsConst:= True;
    Item.Value  := Init.NamedChild(Init.NamedChildCount - 1);
    if AMap <> nil then AMap.AddOrSetValue(LowerCase(Txt(Decl.NamedChild(0))), Item)
    else FConsts.AddOrSetValue(LowerCase(Txt(Decl.NamedChild(0))), Item.Value);
  end;
end;

procedure TSqlTextScan.AddVars(const ANode: TTSNode; AMap: TScopeMap; AParam: Boolean);
var
  I, J: Integer;
  Decl, Child, TypeNode: TTSNode;
  Item: TDecl;
begin
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Decl:= ANode.NamedChild(I);
    if not MatchStr(Decl.NodeType, ['declVar', 'declArg']) then Continue;
    TypeNode:= Decl.ChildByField('type');
    for J:= 0 to Decl.NamedChildCount - 1 do
    begin
      Child:= Decl.NamedChild(J);
      if Child.NodeType <> 'identifier' then Continue;
      if (not TypeNode.IsNull) and (Child.StartByte >= TypeNode.StartByte) then Break;
      Item:= Default(TDecl);
      Item.Key     := Format('L%d:%s', [Child.StartByte, LowerCase(Txt(Child))]);
      Item.TypeName:= LeafName(Txt(TypeNode));
      Item.IsParam := AParam;
      AMap.AddOrSetValue(LowerCase(Txt(Child)), Item);
    end;
  end;
end;

{ Unit-level variables, constants and the fields of every class. Routine bodies are not entered. }
procedure TSqlTextScan.CollectUnit(const ANode: TTSNode; const AClass: string);
var
  I    : Integer;
  Child: TTSNode;
  Map  : TScopeMap;
  Pair : TPair<string, TDecl>;
begin
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(I);
    if Child.NodeType = 'declConsts' then AddConst(Child, nil)
    else if Child.NodeType = 'declType' then
      CollectFields(Child, Txt(Child.NamedChild(0)))
    else if Child.NodeType = 'declVars' then
    begin
      Map:= TScopeMap.Create;
      try
        AddVars(Child, Map, False);
        for Pair in Map do FUnitVars.AddOrSetValue(Pair.Key, Pair.Value.TypeName);
      finally
        Map.Free;
      end;
    end
    else if not MatchStr(Child.NodeType, ['defProc', 'block']) then CollectUnit(Child, AClass);
  end;
end;

{ ---- the walk ---- }

procedure TSqlTextScan.WalkChildren(const ANode: TTSNode);
var
  I: Integer;
begin
  for I:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(I));
end;

procedure TSqlTextScan.WalkRoutine(const ANode: TTSNode);
var
  Map   : TScopeMap;
  Saved : string;
  Outer : Boolean;
  Head  : TArray<string>;
  SavedWith: TList<TSqlDataset>;
  I     : Integer;
  Child : TTSNode;
begin
  Saved:= FOwner;
  Outer:= FRoutine = 0;
  if Outer then
  begin
    FRoutine:= ANode.StartByte;
    Child:= ANode.ChildByField('header');
    if Child.IsNull then Child:= ANode.NamedChild(0);
    for I:= 0 to Child.NamedChildCount - 1 do
      if MatchStr(Child.NamedChild(I).NodeType, ['genericDot', 'exprDot', 'identifier']) then
      begin
        Head:= Txt(Child.NamedChild(I)).Split(['.']);
        FOwner:= if Length(Head) > 1 then Head[High(Head) - 1].Trim else '';
        Break;
      end;
  end;
  SavedWith:= FWith;
  FWith:= TList<TSqlDataset>.Create;
  Map:= TScopeMap.Create;
  FScopes.Add(Map);
  try
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      Child:= ANode.NamedChild(I);
      if Child.NodeType = 'declProc' then
        for var J: Integer:= 0 to Child.NamedChildCount - 1 do
        begin
          if Child.NamedChild(J).NodeType = 'declArgs' then AddVars(Child.NamedChild(J), Map, True);
        end
      else if Child.NodeType = 'declArgs' then AddVars(Child, Map, True)
      else if Child.NodeType = 'declVars' then AddVars(Child, Map, False)
      else if Child.NodeType = 'declConsts' then AddConst(Child, Map);
    end;
    WalkChildren(ANode);
  finally
    FScopes.Delete(FScopes.Count - 1);
    FWith.Free;
    FWith := SavedWith;
    FOwner:= Saved;
    if Outer then FRoutine:= 0;
  end;
end;

function ListKey(const ANode: TTSNode; ABranch: Boolean): UInt64;
begin
  { a branch and the list inside it may span the same bytes }
  Result:= (UInt64(ANode.StartByte) shl LIST_SHIFT) or (UInt64(ANode.EndByte) shl 1) or UInt64(Ord(ABranch));
end;

{ if / loop / case: a single statement below one of these is a list of its own. }
procedure TSqlTextScan.WalkControl(const ANode: TTSNode);
var
  I    : Integer;
  Saved: UInt64;
begin
  Saved:= FList0;
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    FList0:= ListKey(ANode.NamedChild(I), True);
    Walk(ANode.NamedChild(I));
  end;
  FList0:= Saved;
end;

procedure TSqlTextScan.Walk(const ANode: TTSNode);
var
  Kind : string;
  Saved: UInt64;
begin
  Kind:= ANode.NodeType;
  if ArrayHas(Kind, DECL_NODES) then Exit;
  if (Kind = 'defProc') or (Kind = 'lambda') then WalkRoutine(ANode)
  else if Kind = 'with' then WalkWith(ANode)
  else if Kind = 'assignment' then WalkAssignment(ANode)
  else if ArrayHas(Kind, EXPR_NODES) then WalkChain(ANode)
  else if ArrayHas(Kind, LIST_NODES) then
  begin
    Saved := FList0;
    FList0:= ListKey(ANode, False);
    WalkChildren(ANode);
    FList0:= Saved;
  end
  else if Kind = 'exceptionHandler' then
  begin
    for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
      if ANode.NamedChild(I).NodeType <> 'identifier' then Walk(ANode.NamedChild(I));
  end
  else if ArrayHas(Kind, CONTROL_NODES) then WalkControl(ANode)
  else WalkChildren(ANode);
end;

procedure TSqlTextScan.WalkWith(const ANode: TTSNode);
var
  I, Count: Integer;
  Child: TTSNode;
  Links: TLinks;
  Base : TTSNode;
  Data : TSqlDataset;
begin
  Count:= FWith.Count;
  I:= 0;
  while I < ANode.NamedChildCount do
  begin
    Child:= ANode.NamedChild(I);
    Inc(I);
    if Child.NodeType = 'kDo' then Break;
    if Child.NodeType = 'kWith' then Continue;
    Data:= nil;
    if Flatten(Child, Links, Base) and Base.IsNull and (Length(Links) <= MAX_PLAIN_LINKS) then Data:= DatasetOf(Links, Length(Links), False);
    if Data = nil then Walk(Child);
    FWith.Add(Data);
  end;
  { More than one open target: a bare name may belong to any of them, so each dataset counts as handed on. }
  if FWith.Count > 1 then
    for Data in FWith do
      if Data <> nil then AddSite(Data, sskPassed, ANode.NamedChild(1), 'with', Default(TTSNode), 0);
  while I < ANode.NamedChildCount do
  begin
    Walk(ANode.NamedChild(I));
    Inc(I);
  end;
  while FWith.Count > Count do FWith.Delete(FWith.Count - 1);
end;

procedure TSqlTextScan.WalkAssignment(const ANode: TTSNode);
var
  Lhs, Rhs, Ident: TTSNode;
  Links: TLinks;
  Base : TTSNode;
  Data : TSqlDataset;
  Item : TDecl;
  Created: string;
begin
  Lhs:= ANode.ChildByField('lhs');
  Rhs:= ANode.ChildByField('rhs');
  Created:= '';
  if (not Rhs.IsNull) and Flatten(Rhs, Links, Base) and Base.IsNull and (Length(Links) >= MAX_PLAIN_LINKS) and
     SameText(Links[High(Links)].Name, CREATE_NAME) then
    Created:= Links[High(Links) - 1].Name;
  if Lhs.NodeType = 'varAssignDef' then
  begin
    Ident:= Lhs.NamedChild(1);
    if Ident.NodeType = 'identifier' then
    begin
      Item:= Default(TDecl);
      Item.Key:= Format('L%d:%s', [Ident.StartByte, LowerCase(Txt(Ident))]);
      Item.TypeName:= if Lhs.ChildByField('type').IsNull then Created else LeafName(Txt(Lhs.ChildByField('type')));
      if FScopes.Count > 0 then FScopes.Last.AddOrSetValue(LowerCase(Txt(Ident)), Item);
    end;
    Lhs:= Ident;
  end;
  if (not Lhs.IsNull) and Flatten(Lhs, Links, Base) and Base.IsNull and (Length(Links) <= MAX_PLAIN_LINKS) then
  begin
    Data:= DatasetOf(Links, Length(Links), False);
    if Data <> nil then
    begin
      AddCreated(Data, Lhs, Created);
      Walk(Rhs);
      Exit;
    end;
  end;
  WalkChildren(ANode);
end;

{ Splits a chain of names, calls and subscripts. ABase is set when the chain starts with something else. }
function TSqlTextScan.Flatten(const ANode: TTSNode; out ALinks: TLinks; out ABase: TTSNode): Boolean;
var
  Kind: string;
  Link: TLink;
  Base: TTSNode;
begin
  ALinks:= nil;
  ABase := Default(TTSNode);
  Kind  := ANode.NodeType;
  if Kind = 'identifier' then
  begin
    Link:= Default(TLink);
    Link.Name:= Txt(ANode).TrimLeft(['&']);
    Link.Node:= ANode;
    ALinks:= [Link];
    Exit(True);
  end;
  if Kind = 'exprDot' then
  begin
    if ANode.ChildByField('rhs').NodeType <> 'identifier' then Exit(False);
    if not Flatten(ANode.ChildByField('lhs'), ALinks, ABase) then
    begin
      ABase := ANode.ChildByField('lhs');
      ALinks:= nil;
    end;
    Link:= Default(TLink);
    Link.Node:= ANode.ChildByField('rhs');
    Link.Name:= Txt(Link.Node).TrimLeft(['&']);
    ALinks:= ALinks + [Link];
    Exit(True);
  end;
  if not MatchStr(Kind, ['exprCall', 'exprSubscript']) then Exit(False);
  Base:= ANode.ChildByField('entity');
  if Base.IsNull then Base:= ANode.NamedChild(0);
  if (not Flatten(Base, ALinks, ABase)) or (Length(ALinks) = 0) then Exit(False);
  { X(..)[..]: only the last argument list is kept, the chain is not a plain one then }
  ALinks[High(ALinks)].Args:= ANode.ChildByField('args');
  if ALinks[High(ALinks)].Args.IsNull and (ANode.NamedChildCount > 1) then ALinks[High(ALinks)].Args:= ANode.NamedChild(1);
  ALinks[High(ALinks)].Sub:= Kind = 'exprSubscript';
  Result:= True;
end;

function IsDatasetMember(const AName: string): Boolean;
begin
  if ArrayHas(AName, RUN_MEMBERS) or ArrayHas(AName, SQL_MEMBERS) or ArrayHas(AName, PARAMS_MEMBERS) or ArrayHas(AName, PARAM_CALLS) then
    Exit(True);
  Result:= ArrayHas(AName, FIELD_CALLS) or ArrayHas(AName, NO_PARAM_MEMBERS) or ArrayHas(AName, UNREAD_MEMBERS) or
    ArrayHas(AName, MASTER_MEMBERS);
end;

procedure TSqlTextScan.WalkChain(const ANode: TTSNode);  // dl:ok too-many-exit-points@0dc2 -- REVIEWED 2026-11-23 v154 SQL: guard-clause ladder; every Exit is one refusal
var
  Links: TLinks;
  Base : TTSNode;
  Link : TLink;
  At, I: Integer;
  Data : TSqlDataset;
  Item : TDecl;
  Parent: TTSNode;
  Call : string;
begin
  if not Flatten(ANode, Links, Base) then
  begin
    WalkChildren(ANode);
    Exit;
  end;
  if not Base.IsNull then Walk(Base);
  { the arguments are expressions of their own }
  for Link in Links do
    if not Link.Args.IsNull then WalkChildren(Link.Args);
  if not Base.IsNull then Exit;
  if (FWith.Count = 1) and (FWith[0] <> nil) and IsDatasetMember(Links[0].Name) and (not FindDecl(Links[0].Name, Item)) then
  begin
    Member(FWith[0], Links, 0, ANode);
    Exit;
  end;
  At:= -1;
  for I:= 1 to High(Links) do
  begin
    if IsDatasetMember(Links[I].Name) then
    begin
      At:= I;
      Break;
    end;
    if not Links[I - 1].Args.IsNull then Exit;
  end;
  if At > 0 then
  begin
    if not Links[At - 1].Args.IsNull then Exit;
    Data:= DatasetOf(Links, At, True);
    if Data <> nil then Member(Data, Links, At, ANode);
    Exit;
  end;
  if Length(Links) > MAX_PLAIN_LINKS then Exit;
  for Link in Links do
    if not Link.Args.IsNull then Exit;
  Data:= DatasetOf(Links, Length(Links), False);
  if Data = nil then Exit;
  Parent:= ANode.Parent;
  if Parent.NodeType = 'exprArgs' then
  begin
    Call:= LowerCase(LeafName(Txt(Parent.Parent.ChildByField('entity'))));
    if ArrayHas(Call, HARMLESS_CALLS) then Exit;
  end
  else if Parent.NodeType = 'statement' then Exit
  else if (Parent.NodeType = 'exprBinary') and (Parent.ChildCount > 1) and MatchStr(Parent.Child(1).NodeType, ['kNeq', 'kEq']) then Exit;
  AddSite(Data, sskPassed, ANode, 'passed', Default(TTSNode), 0);
end;

function TSqlTextScan.FindDecl(const AName: string; out ADecl: TDecl): Boolean;
var
  I: Integer;
begin
  ADecl:= Default(TDecl);
  for I:= FScopes.Count - 1 downto 0 do
    if FScopes[I].TryGetValue(LowerCase(AName), ADecl) then Exit(True);
  Result:= False;
end;

{ A field of the class whose method is walked, or a component of its form. }
function TSqlTextScan.MemberKey(const AName: string; out AType: string): Boolean;
var
  Dfm, Root: string;
  Item : TSqlDfmDataset;
  Items: TArray<TSqlDfmDataset>;
begin
  AType:= '';
  if FOwner = '' then Exit(False);
  if FFields.TryGetValue(LowerCase(FOwner + SEP + AName), AType) then Exit(True);
  Dfm:= LowerCase(TPath.ChangeExtension(FFile, '.dfm'));
  Result:= False;
  if FDfmRoots.TryGetValue(Dfm, Root) and SameText(Root, FOwner) and FDfms.TryGetValue(Dfm, Items) then
    for Item in Items do
      if SameText(Item.Name, AName) then
      begin
        AType:= Item.ClassName;
        Exit(True);
      end;
end;

function TSqlTextScan.NewDataset(const AKey, AName, AType: string; AScope: TSqlScope; const ANode: TTSNode;
  ACreate: Boolean): TSqlDataset;
begin
  if FByKey.TryGetValue(AKey, Result) then Exit;
  if not ACreate then
  begin
    FLate.Add(TPair<string, TTSNode>.Create(AKey, ANode));
    Exit(nil);
  end;
  Result:= TSqlDataset.Create;
  Result.Name      := AName;
  Result.Scope     := AScope;
  Result.DataClass:= AType;
  if AScope = ssMember then Result.OwnerClass:= FOwner;
  FDatasets.Add(Result);
  FByKey.Add(AKey, Result);

  if AScope not in [ssLocal, ssParameter] then BindSymbol(Result, ANode);
  BindDfm(Result);
end;

{ The dataset the first ACount links name. ACreate: a member access proves it is one even when its type is not seen. }
function TSqlTextScan.DatasetOf(const ALinks: TLinks; ACount: Integer; ACreate: Boolean): TSqlDataset;  // dl:ok too-many-exit-points@7492 -- REVIEWED 2026-11-23 v154 SQL: guard-clause ladder; every Exit is one refusal
var
  First   : Integer;
  Item    : TDecl;
  TypeName: string;
  Name    : string;
  Leaf    : TTSNode;
  I       : Integer;
begin
  Result:= nil;
  First := if (ACount > 1) and SameText(ALinks[0].Name, SELF_NAME) then 1 else 0;
  for I:= First to ACount - 1 do
    if not ALinks[I].Args.IsNull then Exit;
  Leaf:= ALinks[ACount - 1].Node;
  if ACount - First = 1 then
  begin
    Name:= ALinks[First].Name;
    if (First = 0) and FindDecl(Name, Item) then
    begin
      if Item.IsConst or ((not ACreate) and (not IsSqlClass(Item.TypeName)) and (not FByKey.ContainsKey(Item.Key))) then Exit;
      Exit(NewDataset(Item.Key, Name, Item.TypeName, (if Item.IsParam then ssParameter else ssLocal), Leaf, True));
    end;
    if MemberKey(Name, TypeName) then
    begin
      if (not ACreate) and (not IsSqlClass(TypeName)) then Exit;
      Exit(NewDataset('M:' + LowerCase(FOwner + SEP + Name), Name, TypeName, ssMember, Leaf, True));
    end;
    if FUnitVars.TryGetValue(LowerCase(Name), TypeName) then
    begin
      if (not ACreate) and (not IsSqlClass(TypeName)) then Exit;
      Exit(NewDataset('G:' + LowerCase(Name), Name, TypeName, ssUnitVar, Leaf, True));
    end;
    Exit(NewDataset('X:' + LowerCase(FOwner + SEP + Name), Name, '', ssOther, Leaf, ACreate));
  end
  else
  begin
    Name:= '';
    for I:= First to ACount - 1 do Name:= if Name = '' then ALinks[I].Name else Name + '.' + ALinks[I].Name;
  end;
  Result:= NewDataset('X:' + LowerCase(Name), Name, '', ssOther, Leaf, ACreate);
end;

procedure TSqlTextScan.AddSite(const AData: TSqlDataset; AKind: TSqlSiteKind; const ANode: TTSNode; const AMember: string;
  const AArg: TTSNode; AArgs: Integer);
var
  Site: TSqlSite;
begin
  Site:= Default(TSqlSite);
  Site.Kind    := AKind;
  Site.Member  := AMember;
  Site.ArgCount:= AArgs;
  Site.Line    := Integer(ANode.StartPoint.Row) + 1;
  Site.Col     := TAstParseCache.CharCol(FFile, ANode.StartPoint);
  Site.EndCol  := TAstParseCache.CharCol(FFile, ANode.EndPoint);
  Site.Pos     := ANode.StartByte;
  Site.Routine := FRoutine;
  Site.ListPos := FList0;
  Site.Node    := ANode;
  if not AArg.IsNull then Site.Known:= Eval(AArg, Site.Text);
  AData.Sites:= AData.Sites + [Site];
end;

{ The variable is assigned; AClass is the class the right side creates, '' when it is something else. }
procedure TSqlTextScan.AddCreated(const AData: TSqlDataset; const ANode: TTSNode; const AClass: string);
var
  Sites: TArray<TSqlSite>;
begin
  AddSite(AData, sskCreated, ANode, 'assign', Default(TTSNode), 0);
  if AClass = '' then Exit;
  Sites:= AData.Sites;
  Sites[High(Sites)].Text := AClass;
  Sites[High(Sites)].Known:= True;
  AData.Sites:= Sites;
end;

function ArgOf(const ALink: TSqlTextScan.TLink; AIndex: Integer): TTSNode;
begin
  Result:= Default(TTSNode);
  if (not ALink.Args.IsNull) and (ALink.Args.NamedChildCount > AIndex) then Result:= ALink.Args.NamedChild(AIndex);
end;

function ArgCountOf(const ALink: TSqlTextScan.TLink): Integer;
begin
  Result:= if ALink.Args.IsNull then 0 else ALink.Args.NamedChildCount;
end;

{ The right side when ANode is the left side of an assignment; null otherwise. }
function AssignedTo(const ANode: TTSNode): TTSNode;
var
  Parent: TTSNode;
begin
  Result:= Default(TTSNode);
  Parent:= ANode.Parent;
  if (not Parent.IsNull) and (Parent.NodeType = 'assignment') and (Parent.ChildByField('lhs').StartByte = ANode.StartByte) and
     (Parent.ChildByField('lhs').EndByte = ANode.EndByte) then
    Result:= Parent.ChildByField('rhs');
end;

procedure TSqlTextScan.SqlMember(const AData: TSqlDataset; const ALinks: TLinks; AFrom: Integer; const ANode: TTSNode);
var
  Name : string;
  Value: TTSNode;
begin
  Value:= AssignedTo(ANode);
  if AFrom = High(ALinks) then
  begin
    { CommandText := 'x' (a string property); SQL := List or SQL handed out is not read }
    if (not Value.IsNull) and SameText(ALinks[AFrom].Name, 'commandtext') and ALinks[AFrom].Args.IsNull then
      AddSite(AData, sskSqlSet, ALinks[AFrom].Node, LowerCase(ALinks[AFrom].Name), Value, 0)
    else
      AddSite(AData, sskSqlOther, ALinks[AFrom].Node, LowerCase(ALinks[AFrom].Name), Default(TTSNode), 0);
    Exit;
  end;
  Name:= LowerCase(ALinks[AFrom + 1].Name);
  if not ALinks[AFrom].Args.IsNull then Name:= '';
  if Name = 'text' then
  begin
    if not Value.IsNull then AddSite(AData, sskSqlSet, ALinks[AFrom + 1].Node, Name, Value, 0);
  end
  else if Name = 'add' then AddSite(AData, sskSqlAdd, ALinks[AFrom + 1].Node, Name, ArgOf(ALinks[AFrom + 1], 0), ArgCountOf(ALinks[AFrom + 1]))
  else if Name = 'clear' then AddSite(AData, sskSqlClear, ALinks[AFrom + 1].Node, Name, Default(TTSNode), 0)
  else if not MatchStr(Name, ['beginupdate', 'endupdate', 'count', 'savetofile']) then
    AddSite(AData, sskSqlOther, ALinks[AFrom + 1].Node, Name, Default(TTSNode), 0);
end;

procedure TSqlTextScan.ParamsMember(const AData: TSqlDataset; const ALinks: TLinks; AFrom: Integer);
var
  Link: TLink;
begin
  if (AFrom = High(ALinks)) or (not ALinks[AFrom].Args.IsNull) then
  begin
    AddSite(AData, sskParamsOther, ALinks[AFrom].Node, (if ALinks[AFrom].Args.IsNull then 'params' else 'items'), Default(TTSNode), 0);
    Exit;
  end;
  Link:= ALinks[AFrom + 1];
  if ArrayHas(Link.Name, PARAM_CALLS) then
    AddSite(AData, sskParam, Link.Node, LowerCase(Link.Name), ArgOf(Link, 0), ArgCountOf(Link))
  else
    AddSite(AData, sskParamsOther, Link.Node, LowerCase(Link.Name), ArgOf(Link, 0), ArgCountOf(Link));
end;

procedure TSqlTextScan.RunMember(const AData: TSqlDataset; const ALink: TLink);
var
  Name : string;
  Arg  : TTSNode;
  Value: TTSNode;
begin
  Name:= LowerCase(ALink.Name);
  Arg := ArgOf(ALink, 0);
  if Name = 'active' then
  begin
    Value:= AssignedTo(ALink.Node.Parent);
    if Value.IsNull then Value:= AssignedTo(ALink.Node);
    if (not Value.IsNull) and (Value.NodeType = 'kTrue') then AddSite(AData, sskRun, ALink.Node, Name, Default(TTSNode), 0);
    Exit;
  end;
  if (Name = 'execute') and (not Arg.IsNull) then
    AddSite(AData, sskParamsOther, ALink.Node, 'execute-array', Default(TTSNode), ArgCountOf(ALink))
  else if (not Arg.IsNull) and (not MatchStr(Arg.NodeType, ['kTrue', 'kFalse'])) then
  begin
    AddSite(AData, sskSqlSet, ALink.Node, Name, Arg, ArgCountOf(ALink));
    if ArgCountOf(ALink) > 1 then AddSite(AData, sskParamsOther, ALink.Node, 'values', Default(TTSNode), ArgCountOf(ALink));
  end;
  AddSite(AData, sskRun, ALink.Node, Name, Default(TTSNode), ArgCountOf(ALink));
end;

procedure TSqlTextScan.Member(const AData: TSqlDataset; const ALinks: TLinks; AFrom: Integer; const ANode: TTSNode);
var
  Link: TLink;
  Name: string;
begin
  Link:= ALinks[AFrom];
  Name:= LowerCase(Link.Name);
  if ArrayHas(Name, SQL_MEMBERS) then SqlMember(AData, ALinks, AFrom, ANode)
  else if ArrayHas(Name, PARAMS_MEMBERS) then ParamsMember(AData, ALinks, AFrom)
  else if ArrayHas(Name, PARAM_CALLS) then AddSite(AData, sskParam, Link.Node, Name, ArgOf(Link, 0), ArgCountOf(Link))
  else if ArrayHas(Name, FIELD_CALLS) then AddSite(AData, sskField, Link.Node, Name, ArgOf(Link, 0), ArgCountOf(Link))
  else if ArrayHas(Name, RUN_MEMBERS) then RunMember(AData, Link)
  else if Name = 'resourceoptions' then
  begin
    if (AFrom < High(ALinks)) and MatchText(ALinks[AFrom + 1].Name, ['ParamCreate', 'MacroCreate', 'ParamExpand', 'PreprocessCmdText']) then
      AddSite(AData, sskNoParams, Link.Node, Name, Default(TTSNode), 0);
  end
  else if Name = 'paramcheck' then AddSite(AData, sskNoParams, Link.Node, Name, Default(TTSNode), 0)
  else if ArrayHas(Name, MASTER_MEMBERS) then AddSite(AData, sskParamsOther, Link.Node, Name, Default(TTSNode), 0)
  else AddSite(AData, sskSqlOther, Link.Node, Name, Default(TTSNode), 0);
end;

{ ---- constants ---- }

function TSqlTextScan.Eval(const ANode: TTSNode; out AText: string): Boolean;
var
  Left, Right: string;
  Links: TLinks;
  Base : TTSNode;
begin
  AText:= '';
  if ANode.IsNull then Exit(False);
  if ANode.NodeType = 'literalString' then Exit(LiteralText(Txt(ANode), AText));
  if ANode.NodeType = 'exprParens' then Exit(Eval(ANode.NamedChild(0), AText));
  if ANode.NodeType = 'exprBinary' then
  begin
    Result:= (ANode.ChildCount > TWO_CHARS) and (ANode.Child(1).NodeType = 'kAdd') and Eval(ANode.Child(0), Left) and
      Eval(ANode.Child(TWO_CHARS), Right);
    if Result then AText:= Left + Right;
    Exit;
  end;
  if Flatten(ANode, Links, Base) and Base.IsNull and (Links[High(Links)].Args.IsNull) then
    Exit(EvalConst(Links[High(Links)].Name, Links[High(Links)].Node, AText));
  Result:= False;
end;

{ A query on the index; the caller frees it. }
function TSqlTextScan.NewQuery(const ASql: string): TObject;
var
  Query: TFDQuery;
begin
  Query:= TFDQuery.Create(nil);
  Query.Connection:= (FStore as TSQLiteSymbolStore).GetConnection;
  Query.SQL.Text  := ASql;
  Result:= Query;
end;

{ AColumn of the reference at ANode as text; '' = none. }
function TSqlTextScan.RefValue(const ANode: TTSNode; const AColumn: string): string;
var
  Query: TFDQuery;
begin
  Result:= '';
  if (not FHasRecv) or (FFileId = 0) then Exit;
  Query:= NewQuery('SELECT ' + AColumn + ' FROM refs r LEFT JOIN ref_types t ON t.ref_id = r.id WHERE r.file_id = :f ' +
    'AND r.start_line = :l AND r.start_col = :c AND r.name_text = :n COLLATE NOCASE AND ' + AColumn + ' IS NOT NULL LIMIT 1') as TFDQuery;
  try
    Query.ParamByName('f').AsLargeInt:= FFileId;
    Query.ParamByName('l').AsInteger := Integer(ANode.StartPoint.Row) + 1;
    Query.ParamByName('c').AsInteger := TAstParseCache.CharCol(FFile, ANode.StartPoint);
    Query.ParamByName('n').AsString  := Txt(ANode).TrimLeft(['&']);
    Query.Open;
    if not Query.Eof then Result:= Query.Fields[0].AsString;
  finally
    Query.Free;
  end;
end;

{ The symbol the index binds the name at ANode to; 0 = none. }
function TSqlTextScan.SymbolAt(const ANode: TTSNode): Int64;
begin
  Result:= StrToInt64Def(RefValue(ANode, 'r.symbol_id'), 0);
end;

{ The static type ref_types records for the name at ANode, as a leaf; '' = none. }
function TSqlTextScan.TypeAt(const ANode: TTSNode): string;
begin
  Result:= LeafName(RefValue(ANode, 't.type_qname'));
end;

{ The constant node of that name that starts on ALine, in another file's tree. }
function FindConstNode(const ANode: TTSNode; ALine: Integer): TTSNode;
var
  I: Integer;
begin
  Result:= Default(TTSNode);
  if ANode.NodeType = 'declConst' then
  begin
    if Integer(ANode.StartPoint.Row) + 1 = ALine then Result:= ANode;
    Exit;
  end;
  if (Integer(ANode.StartPoint.Row) + 1 > ALine) or (Integer(ANode.EndPoint.Row) + 1 < ALine) then Exit;
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Result:= FindConstNode(ANode.NamedChild(I), ALine);
    if not Result.IsNull then Exit;
  end;
end;

{ Literals joined with + only. }
function LiteralsOf(const ANode: TTSNode; const ASrc: TBytes; out AText: string): Boolean;
var
  Left, Right: string;
begin
  AText:= '';
  if ANode.NodeType = 'literalString' then
    Exit(LiteralText(TEncoding.UTF8.GetString(ASrc, Integer(ANode.StartByte), Integer(ANode.EndByte - ANode.StartByte)), AText));
  Result:= (ANode.NodeType = 'exprBinary') and (ANode.ChildCount > TWO_CHARS) and (ANode.Child(1).NodeType = 'kAdd') and
    LiteralsOf(ANode.Child(0), ASrc, Left) and LiteralsOf(ANode.Child(TWO_CHARS), ASrc, Right);
  if Result then AText:= Left + Right;
end;

function TSqlTextScan.EvalConst(const AName: string; const ANode: TTSNode; out AText: string): Boolean;  // dl:ok too-many-exit-points@6689 -- REVIEWED 2026-11-23 v154 SQL: guard-clause ladder; every Exit is one refusal
var
  Item  : TDecl;
  Value : TTSNode;
  Id    : Int64;
  Query : TFDQuery;
  Parsed: TParsedFile;
begin
  AText:= '';
  if FindDecl(AName, Item) then Exit(Item.IsConst and Eval(Item.Value, AText));
  if FConsts.TryGetValue(LowerCase(AName), Value) then Exit(Eval(Value, AText));
  if SameText(AName, 'sLineBreak') then
  begin
    AText:= sLineBreak;
    Exit(True);
  end;
  Result:= False;
  Id:= SymbolAt(ANode);
  if Id = 0 then Exit;
  Query:= NewQuery('SELECT f.path, s.start_line FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = :i AND s.kind = ''const''') as TFDQuery;
  try
    Query.ParamByName('i').AsLargeInt:= Id;
    Query.Open;
    if Query.Eof then Exit;
    Parsed:= TAstParseCache.Get(Query.Fields[0].AsString);
    if Parsed.Tree = nil then Exit;
    Value:= FindConstNode(Parsed.Tree.RootNode, Query.Fields[1].AsInteger);
    if Value.IsNull or (Value.NamedChild(Value.NamedChildCount - 1).NodeType <> 'defaultValue') then Exit;
    Value := Value.NamedChild(Value.NamedChildCount - 1);
    Result:= LiteralsOf(Value.NamedChild(Value.NamedChildCount - 1), Parsed.Src, AText);
  finally
    Query.Free;
  end;
end;

{ ---- the .dfm ---- }

type
  { The property rows of one .dfm object. }
  TDfmProps = record
    Rows : TArray<TDfmPropertyRow>;
    Owner: Integer;
    function Value(const AName: string): string;
    function ListText(ARow: Integer): string;
    function IsFalse(const AName: string): Boolean;
    function Valued: TArray<string>;
  end;

function TDfmProps.ListText(ARow: Integer): string;
var
  I    : Integer;
  Parts: TArray<string>;
begin
  Parts:= nil;
  for I:= ARow + 1 to High(Rows) do
    if Rows[I].Parent = ARow then Parts:= Parts + [Rows[I].ValueText]
    else if Rows[I].Depth <= Rows[ARow].Depth then Break;
  Result:= string.Join(sLineBreak, Parts).TrimRight;
end;

function TDfmProps.Value(const AName: string): string;
var
  I: Integer;
begin
  for I:= 0 to High(Rows) do
    if (Rows[I].ObjectOrdinal = Owner) and (Rows[I].Depth = 0) and SameText(Rows[I].Name, AName) then
      Exit(if Rows[I].ValueKind = KIND_LIST then ListText(I) else Rows[I].ValueText);
  Result:= '';
end;

function TDfmProps.IsFalse(const AName: string): Boolean;
begin
  Result:= SameText(Value(AName), 'False');
end;

{ Names of collection items that have a Value other than Null. }
function TDfmProps.Valued: TArray<string>;
var
  I   : Integer;
  Name: string;
begin
  Result:= nil;
  Name  := '';
  for I:= 0 to High(Rows) do
  begin
    if Rows[I].ObjectOrdinal <> Owner then Continue;
    if Rows[I].ValueKind = KIND_ITEM then Name:= ''
    else if (Rows[I].Depth > 0) and SameText(Rows[I].Name, 'Name') then Name:= Rows[I].ValueText
    else if (Rows[I].Depth > 0) and SameText(Rows[I].Name, 'Value') and (Name <> '') and (not MatchText(Rows[I].ValueText, ['Null', ''])) then
      Result:= Result + [Name];
  end;
end;

procedure TSqlTextScan.LoadDfm(const ADfm: string);
var
  Key   : string;
  Bytes : TBytes;
  Parser: TDFMParser;
  Parsed: TParseResult;
  Props : TDfmProps;
  Item  : TSqlDfmDataset;
  Items : TArray<TSqlDfmDataset>;
  I     : Integer;
begin
  Key:= LowerCase(ADfm);
  if FDfms.ContainsKey(Key) then Exit;
  FDfms.Add(Key, nil);
  FDfmRoots.Add(Key, '');
  if not TFile.Exists(ADfm) then Exit;
  Bytes:= TFile.ReadAllBytes(ADfm);
  if (Length(Bytes) > 0) and ((Bytes[0] = BINARY_DFM_BYTE) or (Bytes[0] = Ord('T'))) then
  begin
    FDfmNotes.AddOrSetValue(Key, REASON_BINARY);
    Exit;
  end;
  Bytes := EnsureUtf8Bytes(Bytes);
  Parser:= TDFMParser.Create;
  try
    Parsed:= Parser.Parse(Bytes, ADfm);
  finally
    Parser.Free;
  end;
  if Length(Parsed.DfmObjects) = 0 then Exit;
  FDfmRoots[Key]:= Parsed.DfmObjects[0].ClassName;
  Props.Rows:= ExtractDfmPropertyRows(ADfm, TEncoding.UTF8.GetString(Bytes), Parsed.DfmObjects);
  Items:= nil;
  for I:= 1 to High(Parsed.DfmObjects) do
  begin
    Props.Owner:= I;
    Item:= Default(TSqlDfmDataset);
    Item.Name       := Parsed.DfmObjects[I].Name;
    Item.ClassName  := Parsed.DfmObjects[I].ClassName;
    Item.ObjKind    := Parsed.DfmObjects[I].ObjKind;
    Item.Line       := Parsed.DfmObjects[I].StartLine;
    Item.Sql        := Props.Value('SQL.Strings');
    if Item.Sql = '' then Item.Sql:= Props.Value('CommandText.Strings');
    if Item.Sql = '' then Item.Sql:= Props.Value('CommandText');
    Item.TableName  := Props.Value('TableName');
    Item.UpdateTable:= Props.Value('UpdateOptions.UpdateTableName');
    Item.NoParams   := Props.IsFalse('ParamCheck') or Props.IsFalse('ResourceOptions.ParamCreate');
    Item.HasMaster  := (Props.Value('MasterSource') <> '') or (Props.Value('DataSource') <> '') or (Props.Value('MasterFields') <> '');
    Item.ValuedParams:= Props.Valued;
    if (Item.Sql <> '') or (Item.TableName <> '') or IsSqlClass(Item.ClassName) or MatchText(Item.ObjKind, ['inherited']) then
      Items:= Items + [Item];
  end;
  FDfms[Key]:= Items;
end;

{ ---- the index ---- }

procedure TSqlTextScan.BindSymbol(const AData: TSqlDataset; const ANode: TTSNode);
begin
  AData.SymbolId:= SymbolAt(ANode);
  if AData.DataClass = '' then AData.DataClass:= TypeAt(ANode);
end;

procedure TSqlTextScan.BindDfm(const AData: TSqlDataset);
var
  Dfm  : string;
  Query: TFDQuery;
  Item : TSqlDfmDataset;
  Items: TArray<TSqlDfmDataset>;
  Root, Found, Note: string;
begin
  Dfm := '';
  Root:= AData.OwnerClass;
  if AData.Scope = ssMember then Dfm:= TPath.ChangeExtension(FFile, '.dfm')
  else if (AData.Scope = ssOther) and (AData.SymbolId > 0) then
  begin
    Query:= NewQuery('SELECT f.path, p.name FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbols p ON p.id = s.parent_id ' +
      'WHERE s.id = :i AND s.kind = ''field''') as TFDQuery;
    try
      Query.ParamByName('i').AsLargeInt:= AData.SymbolId;
      Query.Open;
      if not Query.Eof then
      begin
        Dfm := TPath.ChangeExtension(Query.Fields[0].AsString, '.dfm');
        Root:= Query.Fields[1].AsString;
      end;
    finally
      Query.Free;
    end;
  end;
  if Dfm = '' then Exit;
  LoadDfm(Dfm);
  Dfm:= LowerCase(Dfm);
  if FDfmNotes.TryGetValue(Dfm, Note) then AData.Reason:= Note;
  if (not FDfmRoots.TryGetValue(Dfm, Found)) or (not SameText(Found, Root)) or (not FDfms.TryGetValue(Dfm, Items)) then Exit;
  for Item in Items do
    if SameText(Item.Name, LeafName(AData.Name)) then
    begin
      AData.InDfm:= True;
      AData.Dfm  := Item;
      if AData.DataClass = '' then AData.DataClass:= Item.ClassName;
      Exit;
    end;
end;

function TSqlTextScan.OutsideReason(const AData: TSqlDataset; AParams: Boolean): string;
var
  Query : TFDQuery;
  Member: string;
begin
  if AData.Scope in [ssLocal, ssParameter] then Exit('');
  if FStore = nil then Exit(REASON_NO_INDEX);
  if not FHasRecv then Exit(REASON_OLD_INDEX);
  if AData.SymbolId = 0 then Exit(REASON_NO_SYMBOL);
  Result:= '';
  Query:= NewQuery('SELECT m.name_text FROM refs r LEFT JOIN ref_receivers rr ON rr.receiver_ref_id = r.id ' +
    'LEFT JOIN refs m ON m.id = rr.ref_id WHERE r.symbol_id = :s AND r.file_id <> :f') as TFDQuery;
  try
    Query.ParamByName('s').AsLargeInt:= AData.SymbolId;
    Query.ParamByName('f').AsLargeInt:= FFileId;
    Query.Open;
    while (Result = '') and (not Query.Eof) do
    begin
      Member:= LowerCase(Query.Fields[0].AsString);
      if (Member = '') or ArrayHas(Member, SQL_MEMBERS) or ArrayHas(Member, UNREAD_MEMBERS) or ArrayHas(Member, NO_PARAM_MEMBERS) then
        Result:= REASON_OUTSIDE
      else if AParams and (ArrayHas(Member, PARAM_CALLS) or ArrayHas(Member, PARAMS_MEMBERS) or ArrayHas(Member, MASTER_MEMBERS)) then
        Result:= REASON_OUTSIDE_PARAMS;
      Query.Next;
    end;
    if (Result <> '') or (not AData.InDfm) then Exit;
    Query.Close;
    Query.SQL.Text:= 'SELECT COUNT(*) FROM dfm_objects o JOIN dfm_properties p ON p.file_id = o.file_id AND p.object_ordinal = o.ordinal ' +
      'WHERE o.name = :n COLLATE NOCASE AND o.obj_kind = ''inherited'' AND p.name IN (''SQL.Strings'', ''CommandText.Strings'', ''CommandText'')';
    Query.ParamByName('n').AsString:= AData.Dfm.Name;
    Query.Open;
    if Query.Fields[0].AsInteger > 0 then Result:= REASON_DESCENDANT;
  finally
    Query.Free;
  end;
end;

{ ---- the conclusion per dataset ---- }

{ Why no SQL text of the dataset can be read at all; '' = go on. }
function TSqlTextScan.Blocked(const AData: TSqlDataset): string;  // dl:ok too-many-exit-points@44e3 -- REVIEWED 2026-11-23 v154 SQL: guard-clause ladder; every Exit is one refusal
var
  Site : TSqlSite;
  Count: Integer;
begin
  Result:= AData.Reason;
  if Result <> '' then Exit;
  if AData.Scope = ssParameter then Exit(REASON_PARAMETER);
  if AData.Has([sskPassed]) then Exit(REASON_PASSED);
  if AData.Has([sskSqlOther]) then Exit(REASON_OTHER_SQL);
  if AData.Has([sskNoParams]) or (AData.InDfm and AData.Dfm.NoParams) then Exit(REASON_NO_PARAMS);
  if AData.InDfm and (not SameText(AData.Dfm.ObjKind, 'object')) then Exit(REASON_INHERITED);
  Count:= 0;
  for Site in AData.Sites do
    if Site.Kind = sskCreated then
    begin
      Inc(Count);
      if not Site.Known then Exit(REASON_SOURCE);
    end;
  if (AData.Scope = ssLocal) and (Count <> 1) then Exit(REASON_SOURCE);
end;

{ The one SQL text of the dataset; the result is the reason when there is none. }
function TSqlTextScan.OneText(const AData: TSqlDataset; out AText: string): string;  // dl:ok too-many-exit-points@3986 -- REVIEWED 2026-11-23 v154 SQL: guard-clause ladder; every Exit is one refusal
var
  Site, First: TSqlSite;
  Count: Integer;
begin
  AText := '';
  Result:= '';
  Count := 0;
  First := Default(TSqlSite);
  for Site in AData.Sites do
    case Site.Kind of
      sskSqlSet, sskSqlAdd, sskSqlClear:
      begin
        if Count > 0 then
        begin
          { SQL.Clear, SQL.Add .. SQL.Add in one statement list is one text; anything else is several places }
          if (Site.Kind <> sskSqlAdd) and ((Site.Kind <> sskSqlSet) or (First.Kind <> sskSqlClear) or (AText <> '')) then Exit(REASON_PLACES);
          if (Site.ListPos <> First.ListPos) or (Site.Routine <> First.Routine) then Exit(REASON_PLACES);
        end
        else First:= Site;
        Inc(Count);
        if Site.Kind = sskSqlClear then Continue;
        if not Site.Known then Exit(REASON_BUILT);
        AText:= AText + (if AText = '' then '' else sLineBreak) + Site.Text;
      end;
      sskRun:
        { SQL added after a run in the same list is a second text }
        if (Count > 0) and (AText <> '') then
          for var Later: TSqlSite in AData.Sites do
            if (Later.Kind in [sskSqlSet, sskSqlAdd, sskSqlClear]) and (Later.Pos > Site.Pos) then Exit(REASON_PLACES);
    else
      Continue;
    end;
  if not AData.InDfm then Exit(if AText = '' then REASON_NO_SQL else '');
  if AData.Dfm.Sql = '' then Exit(if AText = '' then REASON_NO_SQL else '');
  if Count > 0 then Exit(REASON_PLACES);
  AText:= AData.Dfm.Sql;
end;

procedure TSqlTextScan.Conclude(const AData: TSqlDataset);
var
  Text : string;
  Sites: TArray<TSqlSite>;
begin
  Sites:= AData.Sites;
  TArray.Sort<TSqlSite>(Sites, TComparer<TSqlSite>.Construct(
    function (const ALeft, ARight: TSqlSite): Integer
    begin
      Result:= CompareValue(ALeft.Pos, ARight.Pos);
      if Result = 0 then Result:= CompareValue(Ord(ALeft.Kind), Ord(ARight.Kind));
    end));
  AData.Sites := Sites;
  AData.Reason:= Blocked(AData);
  Text:= '';
  if AData.Reason = '' then AData.Reason:= OneText(AData, Text);
  if AData.Reason <> '' then Text:= '';
  if (Text <> '') and (AData.Scope = ssOther) and (not AData.InDfm) then
  begin
    AData.Reason:= REASON_OTHER_UNIT;
    Text:= '';
  end;
  if Text <> '' then AData.Facts:= ReadSqlText(Text);
  if AData.InDfm and (AData.Dfm.UpdateTable <> '') then AData.Table:= CleanTableName(AData.Dfm.UpdateTable)
  else if AData.InDfm and (AData.Dfm.TableName <> '') then
  begin
    if not AData.Has([sskSqlOther, sskPassed]) then AData.Table:= CleanTableName(AData.Dfm.TableName);
  end
  else if (AData.Facts.Verb = svSelect) and (Length(AData.Facts.Source.Tables) = 1) then AData.Table:= AData.Facts.Source.Tables[0].Name
  else AData.Table:= AData.Facts.TargetTable;
end;

function TSqlTextScan.ColumnOf(const AData: TSqlDataset; const AField: string; out ATable, AColumn, AReason: string): Boolean;
begin
  ATable := '';
  AColumn:= '';
  AReason:= '';
  if AData.Facts.Verb = svSelect then
  begin
    AReason:= AData.Facts.Source.Reason;
    Exit((AReason = '') and SqlFieldColumn(AData.Facts.Source, AField, '', ATable, AColumn, AReason));
  end;
  Result:= AData.InDfm and (AData.Dfm.TableName <> '') and (AData.Table <> '') and (AData.Facts.Sql = '');
  if Result then
  begin
    ATable := AData.Table;
    AColumn:= UpperCase(AField);
  end
  else AReason:= if AData.Reason <> '' then AData.Reason else REASON_NO_SQL;
end;

end.
