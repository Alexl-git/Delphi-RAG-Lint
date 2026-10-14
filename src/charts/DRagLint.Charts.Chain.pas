unit DRagLint.Charts.Chain;

(* The datasource chain feeds-from, lands-where and consumers share:

     control --DataSource--> TDataSource --DataSet--> memtable --owner--> view model
             --literal--> table

  plus the hop feeds-from misses past a DANGLING designer datasource (the code re-point,
  followed to the dataset field and the table literal beside it), and the per-binding
  population behind feeds-from's disclosure rows. Each routine is a port of the named
  function in charts\src\Emit-Common.ps1 (line numbers of 2026-10-13); the PowerShell output
  is the reference (spec P3/P4), so every hop label, grade and stop reason is reproduced
  verbatim. Every hop is graded (certain / inferred / by name / dangling / unresolved /
  stale source) and the first hop that cannot be taken says WHY.

  PS TRAPS CLOSED HERE: `-eq`, `-ne`, `-in`, `-like`, `-contains`, `-match`, `-replace`
  and `switch` are case-insensitive (so 'NIL' is nil and 'self.' is Self.); Sort-Object
  -Unique dedupes case-insensitively in culture order (SortUniqueNames); .NET \s matches
  #$85 and #$A0 in Latin-1 text (PS_WS); a query with no ORDER BY returns the rows SQLite
  gives, which the in-process query reproduces because it runs the same SQL on the same file. *)

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Charts.Index
  , DRagLint.Charts.Source
  , DRagLint.Charts.Sql
  ;

type
  /// <summary>The control a re-pointing assignment names. Port of the Get-RePointControl result.</summary>
  TRePointControl = record
    /// <summary>The control; '' when none.</summary>
    Control: string;
    /// <summary>'receiver' | 'source' | ''.</summary>
    From   : string;
  end;

  /// <summary>The identifier whose declared type a chain follows. Port of the Get-RhsRoot result.</summary>
  TRhsRoot = record
    /// <summary>The root; '' when the RHS has none to follow.</summary>
    Root  : string;
    /// <summary>Why there is no root; '' when there is one.</summary>
    Reason: string;
  end;

  /// <summary>One code assignment re-pointing a control's property. Port of a Get-RePointSites row.</summary>
  TRePointSite = record
    /// <summary>The control.</summary>
    Control    : string;
    /// <summary>'receiver' | 'source'.</summary>
    ControlFrom: string;
    /// <summary>refs.receiver_text.</summary>
    Receiver   : string;
    /// <summary>The property assigned.</summary>
    Prop       : string;
    /// <summary>The unit.</summary>
    Path       : string;
    /// <summary>The line.</summary>
    Line       : Integer;
    /// <summary>The enclosing routine's qualified name.</summary>
    Routine    : string;
    /// <summary>The right-hand side; '' when the file is stale.</summary>
    Rhs        : string;
    /// <summary>The file differs from the indexed copy (the line is still a fact).</summary>
    Stale      : Boolean;
  end;

  /// <summary>Where a datasource gets its dataset. Port of a Get-DataSetSites row.</summary>
  TDataSetSite = record
    /// <summary>'dfm' | 'assign' | 'read' | 'stale'.</summary>
    Kind   : string;
    /// <summary>The file.</summary>
    Path   : string;
    /// <summary>The line.</summary>
    Line   : Integer;
    /// <summary>The enclosing routine ('' on a dfm row).</summary>
    Routine: string;
    /// <summary>The dataset text (dfm) or the assigned RHS (assign); '' otherwise.</summary>
    Rhs    : string;
    /// <summary>The enclosing routine's symbol id; 0 on a dfm row.</summary>
    Eid    : Integer;
  end;

  /// <summary>One hop of a chain (Get-DataSourceChain and Get-RePointChain share the shape).</summary>
  TChainHop = record
    /// <summary>datasource | dataset | rhs-type | table | re-point | member | accessor | field.</summary>
    Hop    : string;
    /// <summary>certain | inferred | by name | dangling | unresolved | stale source.</summary>
    Grade  : string;
    /// <summary>What the hop reached (the PS Label).</summary>
    Caption: string;
    /// <summary>The file.</summary>
    Path   : string;
    /// <summary>The line.</summary>
    Line   : Integer;
    /// <summary>The routine (Get-RePointChain hops only).</summary>
    Routine: string;
    /// <summary>Why the hop is graded so, or why it stops.</summary>
    Reason : string;
    /// <summary>The INBOX question the hop depends on (Get-RePointChain hops only).</summary>
    Ask    : string;
  end;

  /// <summary>A control that names the datasource in the DFM.</summary>
  TChainControl = record
    /// <summary>The control's name.</summary>
    Control    : string;
    /// <summary>Its type.</summary>
    ControlType: string;
    /// <summary>Its symbol id; 0 when the literal has none.</summary>
    ControlId  : Integer;
    /// <summary>The DFM property.</summary>
    Prop       : string;
    /// <summary>The DFM.</summary>
    Path       : string;
    /// <summary>The DFM line.</summary>
    Line       : Integer;
    /// <summary>The property is a ListSource (a lookup, not a binding).</summary>
    IsLookup   : Boolean;
  end;

  /// <summary>The datasource component a chain resolved.</summary>
  TChainDataSource = record
    /// <summary>False for the PS $null.</summary>
    Present : Boolean;
    /// <summary>symbols.id.</summary>
    Id      : Integer;
    /// <summary>Its name.</summary>
    Name    : string;
    /// <summary>Its qualified name.</summary>
    QName   : string;
    /// <summary>Its type (the PS Type).</summary>
    TypeName: string;
    /// <summary>Its DFM.</summary>
    Path    : string;
    /// <summary>Its line.</summary>
    Line    : Integer;
    /// <summary>Declared in the binding's own DFM ([certain]); False = reached by module NAME.</summary>
    SameFile: Boolean;
  end;

  /// <summary>The declared type of the dataset assignment's RHS root.</summary>
  TRhsType = record
    /// <summary>False for the PS $null.</summary>
    Present : Boolean;
    /// <summary>The RHS.</summary>
    Rhs     : string;
    /// <summary>Its root identifier.</summary>
    Root    : string;
    /// <summary>The root's symbol kind.</summary>
    RootKind: string;
    /// <summary>The root's declared type, generic arguments cut.</summary>
    TypeName: string;
    /// <summary>class | interface | record; '' when unresolved.</summary>
    TypeKind: string;
    /// <summary>The type's file; '' when unresolved.</summary>
    TypePath: string;
    /// <summary>The type's line; 0 when unresolved.</summary>
    TypeLine: Integer;
  end;

  /// <summary>A datasource chain. Port of the Get-DataSourceChain result.</summary>
  TDataSourceChain = record
    /// <summary>The form as asked (DFM path or form name).</summary>
    Form            : string;
    /// <summary>The DFM as indexed.</summary>
    FormFile        : string;
    /// <summary>The sibling .pas as indexed; '' when none.</summary>
    PasFile         : string;
    /// <summary>The datasource text the binding carries.</summary>
    DsName          : string;
    /// <summary>The module prefix of DsName; '' when none.</summary>
    Module          : string;
    /// <summary>The module is declared nowhere in the index.</summary>
    Dangling        : Boolean;
    /// <summary>The datasource component.</summary>
    DataSource      : TChainDataSource;
    /// <summary>The controls naming it in this DFM.</summary>
    Controls        : TArray<TChainControl>;
    /// <summary>Their code re-points (DataSource / ListSource).</summary>
    RePointedAt     : TArray<TRePointSite>;
    /// <summary>Where it gets its dataset.</summary>
    DataSetSites    : TArray<TDataSetSite>;
    /// <summary>The RHS root's declared type.</summary>
    RhsType         : TRhsType;
    /// <summary>Table-name literals in the type's unit, first-literal order (exact match).</summary>
    CandidateTables : TArray<string>;
    /// <summary>The first line of each candidate, parallel to CandidateTables.</summary>
    CandidateLines  : TArray<Integer>;
    /// <summary>Upper-case column names bound through the datasource, sorted.</summary>
    BoundColumns    : TArray<string>;
    /// <summary>Candidates that hold every bound column.</summary>
    ColumnMatch     : TArray<string>;
    /// <summary>"'Text' :line" for literals equal to a table name only case-insensitively.</summary>
    CaseOnlyLiterals: TArray<string>;
    /// <summary>The table; '' when none (the PS $null).</summary>
    ResolvedTable   : string;
    /// <summary>one-table | by-columns | many | none | no-type | no-assignment | dfm-dataset |
    /// dangling | no-datasource | stale source.</summary>
    Grade           : string;
    /// <summary>The hops, in chain order.</summary>
    Hops            : TArray<TChainHop>;
    /// <summary>'' when a table was resolved.</summary>
    StopReason      : string;
  end;

  /// <summary>The dataset field a re-point walk reached.</summary>
  TChainDataSet = record
    /// <summary>False for the PS $null.</summary>
    Present : Boolean;
    /// <summary>The field's name.</summary>
    Name    : string;
    /// <summary>symbols.id.</summary>
    Id      : Integer;
    /// <summary>Its class's symbols.id.</summary>
    ClassId : Integer;
    /// <summary>Its file.</summary>
    Path    : string;
    /// <summary>Its files.id.</summary>
    Fid     : Integer;
    /// <summary>Its line.</summary>
    Line    : Integer;
    /// <summary>Its declared type (the PS Type).</summary>
    TypeName: string;
  end;

  /// <summary>A re-point walk. Port of the Get-RePointChain result.</summary>
  TRePointChain = record
    /// <summary>The hops, in order.</summary>
    Hops      : TArray<TChainHop>;
    /// <summary>The dataset field reached.</summary>
    DataSet   : TChainDataSet;
    /// <summary>'' when the dataset was reached.</summary>
    StopReason: string;
    /// <summary>'' or the indexed path that differs (the caller REFUSES).</summary>
    StaleFile : string;
    /// <summary>The stop is a shape this walk does not follow, not a fact of the code.</summary>
    Limit     : Boolean;
  end;

  /// <summary>Which re-point a dangling chain follows. Port of the Get-RePointPick result.</summary>
  TRePointPick = record
    /// <summary>follow | no-site | stale | multi-rhs.</summary>
    Status   : string;
    /// <summary>The owner's counted sites; Rows[0] is the one to follow.</summary>
    Rows     : TArray<TRePointSite>;
    /// <summary>The owner's ':= nil' sites.</summary>
    NilSites : Integer;
    /// <summary>'' for follow / no-site.</summary>
    Stop     : string;
    /// <summary>'' or the stale file.</summary>
    StaleFile: string;
  end;

  /// <summary>A table literal beside a dataset field. Port of a Get-DataSetTableLiterals row.</summary>
  TTableLiteral = record
    /// <summary>The table name.</summary>
    Table: string;
    /// <summary>Its first line.</summary>
    Line : Integer;
    /// <summary>How many lines carry it.</summary>
    Lines: Integer;
  end;

  /// <summary>The table past a dangling datasource. Port of the Resolve-RePointTable result.</summary>
  TRePointTable = record
    /// <summary>table | no-table | stops | walk-limit | stale | multi-rhs | no-site.</summary>
    Status    : string;
    /// <summary>The owner control.</summary>
    Owner     : string;
    /// <summary>The counted re-point rows.</summary>
    Sites     : TArray<TRePointSite>;
    /// <summary>The ':= nil' sites.</summary>
    NilSites  : Integer;
    /// <summary>Get-RePointChain's hops.</summary>
    Hops      : TArray<TChainHop>;
    /// <summary>The dataset reached.</summary>
    DataSet   : TChainDataSet;
    /// <summary>The table; '' when none.</summary>
    Table     : string;
    /// <summary>Its first line.</summary>
    TableLine : Integer;
    /// <summary>How many lines carry it.</summary>
    TableLines: Integer;
    /// <summary>Why it stops.</summary>
    Stop      : string;
    /// <summary>'' or the stale file.</summary>
    StaleFile : string;
  end;

  /// <summary>One DFM field binding classified by where its chain ends. Port of a
  /// Get-FieldBindingChains Bindings row.</summary>
  TFieldBinding = record
    /// <summary>string_literals.id.</summary>
    Id        : Integer;
    /// <summary>The DFM.</summary>
    Dfm       : string;
    /// <summary>The DFM line.</summary>
    Line      : Integer;
    /// <summary>The DFM property.</summary>
    Prop      : string;
    /// <summary>The bound column.</summary>
    Column    : string;
    /// <summary>The control's symbol id; 0 when none.</summary>
    ControlId : Integer;
    /// <summary>The control's name.</summary>
    Control   : string;
    /// <summary>The datasource text; '' when none.</summary>
    Ds        : string;
    /// <summary>column | not-column | ambiguous | dangling | stops | stale | no-ds.</summary>
    Outcome   : string;
    /// <summary>The table; '' when none.</summary>
    Table     : string;
    /// <summary>The chain dangles.</summary>
    Dangling  : Boolean;
    /// <summary>Key into RePoints; '' when no owner was found.</summary>
    RePointKey: string;
    /// <summary>Resolve-RePointTable's Status; '' when none.</summary>
    RePoint   : string;
  end;

  /// <summary>Every datasource chain and every field binding. Port of the Get-FieldBindingChains result.</summary>
  TFieldBindingChains = record
    /// <summary>ChainKey -> chain, in the order the chains were first built.</summary>
    ChainKeys  : TArray<string>;
    /// <summary>The chains, parallel to ChainKeys.</summary>
    Chains     : TArray<TDataSourceChain>;
    /// <summary>One chain per TDataSource component, in symbols.id order.</summary>
    DataSources: TArray<TDataSourceChain>;
    /// <summary>One row per DFM field binding, in string_literals.id order.</summary>
    Bindings   : TArray<TFieldBinding>;
    /// <summary>RePointKey -> Resolve-RePointTable, in first-use order.</summary>
    RePointKeys: TArray<string>;
    /// <summary>The re-point tables, parallel to RePointKeys.</summary>
    RePoints   : TArray<TRePointTable>;
  end;

  /// <summary>The engine's own ORM links. Port of the Get-OrmLinksState result.</summary>
  TOrmLinksState = record
    /// <summary>The index file.</summary>
    Db        : string;
    /// <summary>orm_links rows.</summary>
    Rows      : Integer;
    /// <summary>The newest computed_at; '' when none.</summary>
    ComputedAt: string;
  end;

  /// <summary>Walks datasource chains over one Delphi index against one SQL catalogue.</summary>
  /// <remarks>Nothing is owned: the Delphi index, its reader, the SQL catalogue and the table
  /// set must outlive the walker. pSet may be a doctored copy (HideExtractedColumns). Not
  /// thread-safe.</remarks>
  TChainWalker = class  // dl:ok high-response@e8f9 -- REVIEWED 2026-10-13: the walker IS the PS chain family (Get-RePointSites .. Get-FieldBindingChains, 8 public calls); its response set is the SQL and formatting calls each hop makes, already split into per-hop free functions
  private
    FIndex  : TChartsIndex;
    FReader : TSourceReader;
    FCatalog: TSqlCatalog;
    FSet    : TSqlTableSet;
  public
    /// <summary>Constructor: a walker over one Delphi index and one SQL catalogue.</summary>
    /// <param name="pIndex">The Delphi index (the PS $DbPath).</param>
    /// <param name="pReader">A source reader over pIndex.</param>
    /// <param name="pCatalog">The SQL catalogue (column states).</param>
    /// <param name="pSet">The SQL table set (the PS $SqlSet).</param>
    constructor Create(pIndex: TChartsIndex; pReader: TSourceReader; pCatalog: TSqlCatalog; pSet: TSqlTableSet);
    /// <summary>Code ASSIGNMENTS to &lt;control&gt;[.DataBinding|...].&lt;prop&gt; in one unit.</summary>
    /// <param name="pPasPath">The unit as indexed.</param>
    /// <param name="pNames">The controls (matched case-insensitively).</param>
    /// <param name="pProps">The properties.</param>
    /// <returns>The sites in line, column order; a stale file keeps its rows with Stale True.</returns>
    /// <remarks>Port of Get-RePointSites (Emit-Common.ps1:1593). A READ is not a re-pointing.</remarks>
    function RePointSites(const pPasPath: string; const pNames, pProps: TArray<string>): TArray<TRePointSite>;
    /// <summary>Where a datasource gets its dataset: DFM rows and `&lt;Local&gt;.DataSet` sites in code.</summary>
    /// <param name="pDsId">The component (0 = a FIELD datasource, no DFM rows).</param>
    /// <param name="pDsFile">The component's DFM.</param>
    /// <param name="pDsPas">The unit to scan; '' for none.</param>
    /// <param name="pLocal">The datasource's own name.</param>
    /// <returns>The sites.</returns>
    /// <remarks>Port of Get-DataSetSites (Emit-Common.ps1:1631); the RHS is read with 5 following lines.</remarks>
    function DataSetSites(pDsId: Integer; const pDsFile, pDsPas, pLocal: string): TArray<TDataSetSite>;
    /// <summary>The chain from a datasource text to a table.</summary>
    /// <param name="pForm">The DFM path as indexed (any case), or the form's name.</param>
    /// <param name="pDsName">The datasource text a binding carries (possibly Module.Name).</param>
    /// <returns>The chain, every hop graded.</returns>
    /// <exception cref="EChartsIndex">pForm is not a DFM / form of the index, or names several forms.</exception>
    /// <remarks>Port of Get-DataSourceChain (Emit-Common.ps1:1724).</remarks>
    function DataSourceChain(const pForm, pDsName: string): TDataSourceChain;
    /// <summary>Follows ONE re-point site's RHS to the dataset field.</summary>
    /// <param name="pRePoint">A RePointSites row.</param>
    /// <returns>The walk.</returns>
    /// <remarks>Port of Get-RePointChain (Emit-Common.ps1:2018).</remarks>
    function RePointChain(const pRePoint: TRePointSite): TRePointChain;
    /// <summary>Which re-point a dangling chain follows.</summary>
    /// <param name="pChain">A chain graded dangling.</param>
    /// <param name="pOwner">The component carrying the DFM DataSource.</param>
    /// <returns>The pick.</returns>
    /// <remarks>Port of Get-RePointPick (Emit-Common.ps1:2175).</remarks>
    function RePointPick(const pChain: TDataSourceChain; const pOwner: string): TRePointPick;
    /// <summary>Table-name literals sharing a line with a read of the dataset field.</summary>
    /// <param name="pDataSet">The dataset field.</param>
    /// <returns>Rows in first-line order.</returns>
    /// <remarks>Port of Get-DataSetTableLiterals (Emit-Common.ps1:2201).</remarks>
    function DataSetTableLiterals(const pDataSet: TChainDataSet): TArray<TTableLiteral>;
    /// <summary>The table past a dangling datasource: pick, walk, literal.</summary>
    /// <param name="pChain">A chain graded dangling.</param>
    /// <param name="pOwner">The owner control.</param>
    /// <returns>The outcome.</returns>
    /// <remarks>Port of Resolve-RePointTable (Emit-Common.ps1:2225).</remarks>
    function ResolveRePointTable(const pChain: TDataSourceChain; const pOwner: string): TRePointTable;
    /// <summary>Every datasource chain and every DFM field binding of the index.</summary>
    /// <returns>The population.</returns>
    /// <remarks>Port of Get-FieldBindingChains (Emit-Common.ps1:2291). The PS process-wide
    /// cache is not ported: a caller keeps the result.</remarks>
    function FieldBindingChains: TFieldBindingChains;
  end;

/// <summary>SQL predicate: pReceiverSql IS pName, bare or as the last segment of a qualified receiver.</summary>
/// <param name="pReceiverSql">A column or a quoted literal.</param>
/// <param name="pName">The name.</param>
/// <returns>The predicate (an exact suffix compare, never LIKE: '_' is a LIKE wildcard).</returns>
/// <remarks>Port of Get-ReceiverMatchSql (Emit-Common.ps1:1522).</remarks>
function ReceiverMatchSql(const pReceiverSql, pName: string): string;

/// <summary>The control a `&lt;ctl&gt;[.DataBinding|.DataController|.Properties].&lt;Prop&gt; :=` names.</summary>
/// <param name="pReceiverText">refs.receiver_text.</param>
/// <param name="pBefore">The stripped text before the ref.</param>
/// <param name="pHasBefore">False for the PS $null (a stale file).</param>
/// <returns>The control and where it was read.</returns>
/// <remarks>Port of Get-RePointControl (Emit-Common.ps1:1534).</remarks>
function RePointControl(const pReceiverText, pBefore: string; pHasBefore: Boolean): TRePointControl;

/// <summary>The identifier whose declared type a chain follows from an RHS.</summary>
/// <param name="pRhs">The right-hand side.</param>
/// <returns>The root, or '' and a reason the chart prints after "chain stops here:".</returns>
/// <remarks>Port of Get-RhsRoot (Emit-Common.ps1:1555).</remarks>
function RhsRoot(const pRhs: string): TRhsRoot;

/// <summary>SQL scalar subquery: the datasource text feeding a component -- own, parent's, grandparent's.</summary>
/// <param name="pSlAlias">The string_literals alias of the binding row.</param>
/// <param name="pCtlAlias">The symbols alias of the component.</param>
/// <returns>A COALESCE of three lookups.</returns>
/// <remarks>Port of Get-ControlDataSourceSql (Emit-Common.ps1:1577).</remarks>
function ControlDataSourceSql(const pSlAlias: string = 'sl'; const pCtlAlias: string = 'c'): string;

/// <summary>The cache key of one chain: DFM path and datasource text, upper-cased.</summary>
/// <param name="pDfm">The DFM.</param>
/// <param name="pDs">The datasource text.</param>
/// <returns>'&lt;DFM&gt;|&lt;DS&gt;' upper case.</returns>
/// <remarks>Port of Get-ChainKey (Emit-Common.ps1:2252).</remarks>
function ChainKey(const pDfm, pDs: string): string;

/// <summary>The engine's own ORM links: row count and newest computed_at.</summary>
/// <param name="pIndex">The (guarded) index.</param>
/// <returns>The state; Db is the file SQLite reports for the main database.</returns>
/// <remarks>Port of Get-OrmLinksState (Emit-Common.ps1:2387). PS difference: the PS ran
/// Get-CloneDb on its path; the caller guards the path before it opens the index.</remarks>
function OrmLinksState(pIndex: TChartsIndex): TOrmLinksState;  // dl:ok unused-public-symbol@80f4 -- REVIEWED 2026-10-13: step-2 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests and the ChartsCoreProbe parity harness, which sit outside this project index

implementation

uses
  System.StrUtils
  , System.RegularExpressions
  , System.Generics.Defaults
  , DRagLint.Charts.Text
  , DRagLint.Charts.Columns
  ;

const
  { .NET \s over Latin-1 text (see DRagLint.Charts.Sql) }
  PS_WS = '[\s\x{85}\x{A0}]';
  NIL_TEXT = 'nil';
  SELF_PREFIX_PATTERN = '(?i)^Self' + PS_WS + '*\.' + PS_WS + '*';
  ASSIGN_PATTERN = '^' + PS_WS + '*:=';
  WS_PATTERN = PS_WS;
  WS_RUN_PATTERN = PS_WS + '+';
  DOT_WS_PATTERN = PS_WS + '*\.' + PS_WS + '*';
  CALL_ROOT_PATTERN = '^([A-Za-z_][A-Za-z0-9_]*)' + PS_WS + '*\(';
  ROOT_PATTERN = '^([A-Za-z_][A-Za-z0-9_]*)';
  CONTROL_FROM_SOURCE_PATTERN = '(?i)(?:^|[^A-Za-z0-9_.])(?:Self\.)?([A-Za-z_][A-Za-z0-9_]*)\.(?:DataBinding|DataController|Properties)\.$';
  READ_ACCESSOR_PATTERN = '(?i)(?<![\w\x{AA}\x{B5}\x{BA}\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{FF}])read' + PS_WS +
    '+([A-Za-z_][A-Za-z0-9_]*)';
  GENERIC_TAIL_PATTERN = '<.*$';
  COLON_LEAD_PATTERN = '^' + PS_WS + '*:' + PS_WS + '*';
  CALL_TAIL_PATTERN = '\(.*$';
  DFM_EXT_PATTERN = '(?i)\.dfm$';
  FOLLOWING_DATASET = 5;
  GRADE_CERTAIN = 'certain';
  GRADE_INFERRED = 'inferred';
  GRADE_BY_NAME = 'by name';
  GRADE_UNRESOLVED = 'unresolved';
  GRADE_STALE = 'stale source';
  KIND_ASSIGN = 'assign';
  KIND_STALE = 'stale';
  KIND_DFM = 'dfm';
  KIND_READ = 'read';
  PAS_EXT = '.pas';

{ ---- small PS shims ---- }

{ -split '\.' then [-1] / [-2]: the last / second-to-last dot segment; '' when absent. }
function DotSegment(const pS: string; pFromEnd: Integer): string;
begin
  var Parts:= pS.Split(['.']);
  var K:= Length(Parts) - pFromEnd;
  Result:= if (K >= 0) and (K < Length(Parts)) then Parts[K] else '';
end;

function InList(const pList: TArray<string>; const pS: string): Boolean;
begin
  for var S in pList do
    if SameText(S, pS) then
      Exit(True);
  Result:= False;
end;

function SortIntsUnique(const pValues: TArray<Integer>): TArray<Integer>;
begin
  Result:= Copy(pValues);
  TArray.Sort<Integer>(Result);
  var N:= 0;
  for var K:= 0 to Length(Result) - 1 do
    if (N = 0) or (Result[N - 1] <> Result[K]) then
    begin
      Result[N]:= Result[K];
      Inc(N);
    end;
  SetLength(Result, N);
end;

function SortNames(const pNames: TArray<string>): TArray<string>;
begin
  Result:= Copy(pNames);
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const pA, pB: string): Integer begin Result:= CompareGroupKeys(pA, pB); end));
end;

{ A hop without routine / INBOX question (Get-RePointChain's Hop adds both). }
function MakeHop(const pHop, pGrade, pCaption, pPath: string; pLine: Integer; const pReason: string): TChainHop;
begin
  Result:= Default(TChainHop);
  Result.Hop:= pHop;
  Result.Grade:= pGrade;
  Result.Caption:= pCaption;
  Result.Path:= pPath;
  Result.Line:= pLine;
  Result.Reason:= pReason;
end;

{ ---- free functions ---- }

function ReceiverMatchSql(const pReceiverSql, pName: string): string;
begin
  var N:= TChartsIndex.SqlText(pName);
  var K:= Length(pName) + 1;
  Result:= Format('(UPPER(%0:s) = UPPER(''%1:s'') OR (LENGTH(%0:s) > %2:d AND UPPER(SUBSTR(%0:s, -%2:d)) = UPPER(''.%1:s'')))',
    [pReceiverSql, N, K]);
end;

function RePointControl(const pReceiverText, pBefore: string; pHasBefore: Boolean): TRePointControl;
begin
  Result:= Default(TRePointControl);
  if (pReceiverText <> '') and not pReceiverText.StartsWith('.') then
  begin
    var Segs:= pReceiverText.Split(['.']);
    for var K:= 0 to Length(Segs) - 1 do
      Segs[K]:= PsTrim(Segs[K]);
    Result.Control:= if SameText(Segs[0], 'Self') and (Length(Segs) > 1) then Segs[1] else Segs[0];
    Result.From:= 'receiver';
    Exit;
  end;
  if not pHasBefore then
    Exit;
  var Bef:= TRegEx.Replace(pBefore, WS_PATTERN, '');
  var M:= TRegEx.Match(Bef, CONTROL_FROM_SOURCE_PATTERN);
  if M.Success then
  begin
    Result.Control:= M.Groups[1].Value;
    Result.From:= 'source';
  end;
end;

function RhsRoot(const pRhs: string): TRhsRoot;
begin
  Result:= Default(TRhsRoot);
  var R:= TRegEx.Replace(PsTrim(pRhs), SELF_PREFIX_PATTERN, '');
  if R = '' then
  begin
    Result.Reason:= 'RHS is empty -- nothing to follow';
    Exit;
  end;
  if R.StartsWith('(') then
  begin
    Result.Reason:= Format('RHS %s is a cast expression -- its type is not followed', [pRhs]);
    Exit;
  end;
  var M:= TRegEx.Match(R, CALL_ROOT_PATTERN);
  if M.Success then
  begin
    Result.Reason:= Format('RHS %s starts with a call or hard cast (%s(...)) -- its result type is not followed', [pRhs, M.Groups[1].Value]);
    Exit;
  end;
  M:= TRegEx.Match(R, ROOT_PATTERN);
  if M.Success then
  begin
    Result.Root:= M.Groups[1].Value;
    Exit;
  end;
  Result.Reason:= Format('RHS %s has no identifier root -- nothing to follow', [pRhs]);
end;

function ControlDataSourceSql(const pSlAlias, pCtlAlias: string): string;

  function One(const pWho: string): string;
  begin
    Result:= Format('(SELECT d.text FROM string_literals d WHERE d.kind = ''dfm-prop'' AND d.file_id = %s.file_id ' +
      'AND d.owner_name IN (''DataSource'',''DataBinding.DataSource'',''DataController.DataSource'') ' +
      'AND d.symbol_id = %s ORDER BY d.start_line LIMIT 1)', [pSlAlias, pWho]);
  end;

begin
  Result:= Format('COALESCE(%s, %s, %s)', [One(pCtlAlias + '.id'), One(pCtlAlias + '.parent_id'),
    One(Format('(SELECT g.parent_id FROM symbols g WHERE g.id = %s.parent_id)', [pCtlAlias]))]);
end;

function ChainKey(const pDfm, pDs: string): string;
begin
  Result:= (pDfm + '|' + pDs).ToUpperInvariant;
end;

function OrmLinksState(pIndex: TChartsIndex): TOrmLinksState;
begin
  Result:= Default(TOrmLinksState);
  var Rows:= pIndex.Query('PRAGMA database_list');
  try
    for var R in Rows do
      if SameText(R.S('name'), 'main') then
        Result.Db:= R.S('file');
  finally
    Rows.Free;
  end;
  Rows:= pIndex.Query('SELECT COUNT(*) AS n, MAX(computed_at) AS at FROM orm_links');
  try
    Result.Rows:= Rows[0].I('n');
    Result.ComputedAt:= Rows[0].S('at');
  finally
    Rows.Free;
  end;
end;

{ ---- TChainWalker ---- }

constructor TChainWalker.Create(pIndex: TChartsIndex; pReader: TSourceReader; pCatalog: TSqlCatalog; pSet: TSqlTableSet);
begin
  inherited Create;
  FIndex:= pIndex;
  FReader:= pReader;
  FCatalog:= pCatalog;
  FSet:= pSet;
end;

function TChainWalker.RePointSites(const pPasPath: string; const pNames, pProps: TArray<string>): TArray<TRePointSite>;
begin
  Result:= [];
  if (pPasPath = '') or (Length(pNames) = 0) then
    Exit;
  var Fid:= FReader.FileId(pPasPath);
  var Rows:= FIndex.Query(Format('SELECT r.receiver_text AS rt, r.name_text AS prop, r.start_line AS line, r.start_col AS col, ' +
    'r.end_col AS ecol, encl.qualified_name AS routine FROM refs r LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id ' +
    'WHERE r.file_id = %d AND r.kind = ''member-access'' AND r.name_text IN (%s) ORDER BY r.start_line, r.start_col',
    [Fid, TChartsIndex.SqlInList(pProps)]));
  try
    for var S in Rows do
    begin
      var Rt:= S.S('rt');
      var Ctx:= FReader.SourceContext(pPasPath, S.I('line'), S.I('col'), S.I('ecol') - S.I('col'));
      var Who:= RePointControl(Rt, Ctx.Before, not Ctx.Stale);
      if (Who.Control = '') or not InList(pNames, Who.Control) then
        Continue;
      var Rhs:= '';
      if not Ctx.Stale then
      begin
        if not TRegEx.IsMatch(Ctx.After, ASSIGN_PATTERN) then
          Continue;
        Rhs:= PsTrim(TRegEx.Replace(Ctx.After, ASSIGN_PATTERN, '').Split([';'])[0]);
      end;
      var Site: TRePointSite;
      Site.Control:= Who.Control;
      Site.ControlFrom:= Who.From;
      Site.Receiver:= Rt;
      Site.Prop:= S.S('prop');
      Site.Path:= pPasPath;
      Site.Line:= S.I('line');
      Site.Routine:= S.S('routine');
      Site.Rhs:= Rhs;
      Site.Stale:= Ctx.Stale;
      Result:= Result + [Site];
    end;
  finally
    Rows.Free;
  end;
end;

function TChainWalker.DataSetSites(pDsId: Integer; const pDsFile, pDsPas, pLocal: string): TArray<TDataSetSite>;
var
  Site: TDataSetSite;
begin
  Result:= [];
  if pDsId <> 0 then
  begin
    var Rows:= FIndex.Query(Format('SELECT sl.text AS t, sl.start_line AS line FROM string_literals sl ' +
      'WHERE sl.kind = ''dfm-prop'' AND sl.owner_name = ''DataSet'' AND sl.symbol_id = %d', [pDsId]));
    try
      for var X in Rows do
      begin
        Site:= Default(TDataSetSite);
        Site.Kind:= KIND_DFM;
        Site.Path:= pDsFile;
        Site.Line:= X.I('line');
        Site.Rhs:= X.S('t');
        Result:= Result + [Site];
      end;
    finally
      Rows.Free;
    end;
  end;
  if pDsPas = '' then
    Exit;
  var Rows:= FIndex.Query(Format('SELECT r.start_line AS line, r.start_col AS col, r.end_col AS ecol, ' +
    'r.enclosing_symbol_id AS eid, encl.qualified_name AS routine FROM refs r LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id ' +
    'WHERE r.file_id = %d AND r.kind = ''member-access'' AND r.name_text = ''DataSet'' AND %s ORDER BY r.start_line, r.start_col',
    [FReader.FileId(pDsPas), ReceiverMatchSql('r.receiver_text', pLocal)]));
  try
    for var X in Rows do
    begin
      Site:= Default(TDataSetSite);
      Site.Path:= pDsPas;
      Site.Line:= X.I('line');
      Site.Routine:= X.S('routine');
      Site.Eid:= X.I('eid');
      var Ctx:= FReader.SourceContext(pDsPas, X.I('line'), X.I('col'), X.I('ecol') - X.I('col'), FOLLOWING_DATASET);
      if Ctx.Stale then
        Site.Kind:= KIND_STALE
      else if TRegEx.IsMatch(Ctx.After, ASSIGN_PATTERN) then
      begin
        var Buf:= TRegEx.Replace(Ctx.After, ASSIGN_PATTERN, '');
        for var F in Ctx.Following do
        begin
          if Buf.Contains(';') then
            Break;
          Buf:= Buf + ' ' + F;
        end;
        { whitespace is collapsed, not deleted: `(VM as IFoo)` must not read `(VMasIFoo)` }
        var Rhs:= TRegEx.Replace(PsTrim(Buf.Split([';'])[0]), DOT_WS_PATTERN, '.');
        Site.Rhs:= TRegEx.Replace(Rhs, WS_RUN_PATTERN, ' ');
        Site.Kind:= KIND_ASSIGN;
      end
      else
        Site.Kind:= KIND_READ;
      Result:= Result + [Site];
    end;
  finally
    Rows.Free;
  end;
end;

type
  { The chain being built and what the hops hand on (the PS $o / $hops and the locals of
    Get-DataSourceChain). Each Step* below is one hop; it returns False once the chain is
    COMPLETE (graded and stopped), so DataSourceChain reads as the PS's sequence of returns. }
  TChainBuild = record
    Chain : TDataSourceChain;
    DfmId : Integer;
    PasId : Integer;
    Local : string;
    DsFile: string;
    DsPas : string;
    DFid  : Integer;
    A0    : TDataSetSite;
    TsFid : Integer;
    procedure AddHop(const pHop, pGrade, pCaption, pPath: string; pLine: Integer; const pReason: string);
    function Stop(const pGrade, pWhy: string): Boolean;
  end;

procedure TChainBuild.AddHop(const pHop, pGrade, pCaption, pPath: string; pLine: Integer; const pReason: string);
begin
  Chain.Hops:= Chain.Hops + [MakeHop(pHop, pGrade, pCaption, pPath, pLine, pReason)];
end;

function TChainBuild.Stop(const pGrade, pWhy: string): Boolean;
begin
  Chain.Grade:= pGrade;
  Chain.StopReason:= pWhy;
  Result:= False;
end;

{ The form's DFM (a path matched case-insensitively, or a form name) and its sibling .pas. }
procedure StepLocateForm(pW: TChainWalker; const pForm: string; var B: TChainBuild);
var
  DfmPath, PasPath: string;
begin
  if TRegEx.IsMatch(pForm, DFM_EXT_PATTERN) then
  begin
    if not pW.FReader.IndexedPath(pForm, DfmPath) then
      raise EChartsIndex.CreateFmt('Get-DataSourceChain: %s is not a DFM of this index', [pForm]);
  end
  else
  begin
    var Fr:= pW.FIndex.Query(Format('SELECT f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id ' +
      'WHERE s.kind = ''form'' AND (s.qualified_name = ''%0:s'' OR s.name = ''%0:s'')', [TChartsIndex.SqlText(pForm)]));
    try
      if Fr.Count = 0 then
        raise EChartsIndex.CreateFmt('Get-DataSourceChain: no form or data module named %s in this index', [pForm]);
      if Fr.Count > 1 then
      begin
        var Names: TArray<string>:= [];
        for var R in Fr do
          Names:= Names + [FileNameOf(R.S('path'))];
        raise EChartsIndex.CreateFmt('Get-DataSourceChain: %s names %d forms (%s) -- pass the DFM path',
          [pForm, Fr.Count, string.Join(', ', Names)]);
      end;
      DfmPath:= Fr[0].S('path');
    finally
      Fr.Free;
    end;
  end;
  if not pW.FReader.IndexedPath(ChangeFileExt(DfmPath, PAS_EXT), PasPath) then
    PasPath:= '';
  B.Chain.Form:= pForm;
  B.Chain.FormFile:= DfmPath;
  B.Chain.PasFile:= PasPath;
  B.DfmId:= pW.FReader.FileId(DfmPath);
  B.PasId:= if PasPath <> '' then pW.FReader.FileId(PasPath) else 0;
end;

{ The controls that name this datasource in THIS DFM, and their code re-points. }
procedure StepControls(pW: TChainWalker; var B: TChainBuild);
begin
  var Rows:= pW.FIndex.Query(Format('SELECT sl.owner_name AS prop, sl.start_line AS line, c.id AS cid, c.name AS ctl, ' +
    'c.signature AS ctype FROM string_literals sl LEFT JOIN symbols c ON c.id = sl.symbol_id ' +
    'WHERE sl.kind = ''dfm-prop'' AND sl.file_id = %d AND sl.owner_name IN (''DataSource'',''DataBinding.DataSource'',' +
    '''DataController.DataSource'',''ListSource'',''Properties.ListSource'') AND UPPER(sl.text) = UPPER(''%s'') ' +
    'ORDER BY sl.start_line', [B.DfmId, TChartsIndex.SqlText(B.Chain.DsName)]));
  try
    for var R in Rows do
    begin
      var C:= Default(TChainControl);
      C.Control:= R.S('ctl');
      C.ControlType:= R.S('ctype');
      C.ControlId:= R.I('cid');
      C.Prop:= R.S('prop');
      C.Path:= B.Chain.FormFile;
      C.Line:= R.I('line');
      C.IsLookup:= EndsText('ListSource', C.Prop);
      B.Chain.Controls:= B.Chain.Controls + [C];
    end;
  finally
    Rows.Free;
  end;
  var Names: TArray<string>:= [];
  for var C in B.Chain.Controls do
    if C.Control <> '' then
      Names:= Names + [C.Control];
  if B.PasId <> 0 then
    B.Chain.RePointedAt:= pW.RePointSites(B.Chain.PasFile, SortUniqueNames(Names), ['DataSource', 'ListSource']);
end;

{ The datasource component's row: by module NAME for a prefixed text, else in this DFM. }
function DataSourceRows(pW: TChainWalker; var B: TChainBuild): TObjectList<TIndexRow>;
begin
  var Cols:= 'SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.start_line AS line, ' +
    'f.path AS path, c.file_id AS fid FROM symbols c JOIN files f ON f.id = c.file_id WHERE c.kind = ''component'' ';
  if B.Chain.Module = '' then
    Exit(pW.FIndex.Query(Cols + Format('AND c.file_id = %d AND UPPER(c.name) = UPPER(''%s'')',
      [B.DfmId, TChartsIndex.SqlText(B.Chain.DsName)])));
  Result:= pW.FIndex.Query(Cols + Format('AND UPPER(c.name) = UPPER(''%s'') AND c.file_id IN (SELECT r.file_id FROM symbols r ' +
    'WHERE r.kind = ''form'' AND UPPER(r.name) = UPPER(''%s''))', [TChartsIndex.SqlText(B.Local), TChartsIndex.SqlText(B.Chain.Module)]));
end;

{ True when a module prefix names nothing in the index (a dangling designer reference). }
function ModuleDangles(pW: TChainWalker; const pModule: string): Boolean;
begin
  var Md:= pW.FIndex.Query(Format('SELECT COUNT(*) AS n FROM symbols WHERE UPPER(name) = UPPER(''%s'')', [TChartsIndex.SqlText(pModule)]));
  try
    Result:= Md[0].I('n') = 0;
  finally
    Md.Free;
  end;
end;

{ hop 1: the datasource component. }
function StepDataSource(pW: TChainWalker; var B: TChainBuild): Boolean;
var
  D: TChainDataSource;
begin
  B.Local:= B.Chain.DsName;
  if B.Chain.DsName.Contains('.') then
  begin
    B.Chain.Module:= Copy(B.Chain.DsName, 1, B.Chain.DsName.LastIndexOf('.'));
    B.Local:= Copy(B.Chain.DsName, B.Chain.DsName.LastIndexOf('.') + 2, MaxInt);
    if ModuleDangles(pW, B.Chain.Module) then
    begin
      B.Chain.Dangling:= True;
      var Why:= Format('module %s is declared nowhere in this index (no form, var or symbol) -- a dangling designer reference', [B.Chain.Module]);
      B.AddHop('datasource', 'dangling', B.Chain.DsName, B.Chain.FormFile,
        if Length(B.Chain.Controls) > 0 then B.Chain.Controls[0].Line else 0, Why);
      Exit(B.Stop('dangling', Why));
    end;
  end;
  var Ds:= DataSourceRows(pW, B);
  try
    if Ds.Count <> 1 then
    begin
      var Why:= if Ds.Count <> 0 then Format('%d components named %s -- cannot tell which', [Ds.Count, B.Local])
        else Format('no component named %s in %s', [B.Local, if B.Chain.Module <> '' then 'module ' + B.Chain.Module else FileNameOf(B.Chain.FormFile)]);
      B.AddHop('datasource', GRADE_UNRESOLVED, B.Chain.DsName, B.Chain.FormFile, 0, Why);
      Exit(B.Stop('no-datasource', Why));
    end;
    D.Present:= True;
    D.Id:= Ds[0].I('id');
    D.Name:= Ds[0].S('name');
    D.QName:= Ds[0].S('q');
    D.TypeName:= Ds[0].S('sig');
    D.Path:= Ds[0].S('path');
    D.Line:= Ds[0].I('line');
    B.DFid:= Ds[0].I('fid');
    D.SameFile:= B.DFid = B.DfmId;
  finally
    Ds.Free;
  end;
  B.Chain.DataSource:= D;
  { only a SAME-FILE component is certain; a module prefix naming another form's file is a NAME match }
  if D.SameFile then
    B.AddHop('datasource', GRADE_CERTAIN, D.Name + ': ' + D.TypeName, D.Path, D.Line, '')
  else
    B.AddHop('datasource', GRADE_BY_NAME, D.Name + ': ' + D.TypeName, D.Path, D.Line, Format('resolved through the module NAME %s to %s, not declared in %s',
      [B.Chain.Module, FileNameOf(D.Path), FileNameOf(B.Chain.FormFile)]));
  B.DsFile:= D.Path;
  B.DsPas:= '';
  if B.DFid = B.DfmId then
    B.DsPas:= B.Chain.PasFile
  else if not pW.FReader.IndexedPath(ChangeFileExt(B.DsFile, PAS_EXT), B.DsPas) then
    B.DsPas:= '';
  Result:= True;
end;

{ The upper-case column names bound through the datasource (checked against candidates later). }
procedure StepBoundColumns(pW: TChainWalker; var B: TChainBuild);
begin
  var Ids: TArray<Integer>:= [];
  for var C in B.Chain.Controls do
    if not C.IsLookup and (C.ControlId <> 0) then
      Ids:= Ids + [C.ControlId];
  Ids:= SortIntsUnique(Ids);
  if Length(Ids) = 0 then
    Exit;
  var InIds: TArray<string>:= [];
  for var Id in Ids do
    InIds:= InIds + [IntToStr(Id)];
  var Bc:= pW.FIndex.Query(Format('SELECT DISTINCT UPPER(sl.text) AS col FROM string_literals sl JOIN symbols c ON c.id = sl.symbol_id ' +
    'WHERE sl.kind = ''dfm-prop'' AND sl.owner_name IN (''DataBinding.FieldName'',''DataBinding.DataField'',''FieldName'',''DataField'') ' +
    'AND (c.id IN (%0:s) OR c.parent_id IN (%0:s))', [string.Join(',', InIds)]));
  try
    for var R in Bc do
      if R.S('col') <> '' then
        B.Chain.BoundColumns:= B.Chain.BoundColumns + [R.S('col')];
  finally
    Bc.Free;
  end;
  B.Chain.BoundColumns:= SortNames(B.Chain.BoundColumns);
end;

{ hop 2 when no non-nil assignment exists: a designer dataset, or nothing assigns one. }
function StopWithoutAssignment(var B: TChainBuild): Boolean;
begin
  for var S in B.Chain.DataSetSites do
    if S.Kind = KIND_DFM then
    begin
      var Why:= Format('the dataset %s is set in the DFM; a designer dataset names no table this index can follow', [S.Rhs]);
      B.AddHop('dataset', GRADE_CERTAIN, 'DataSet = ' + S.Rhs, B.DsFile, S.Line, Why);
      Exit(B.Stop('dfm-dataset', Why));
    end;
  var Why:= if Length(B.Chain.DataSetSites) > 0 then
    Format('%d DataSet site(s) in code, none assigns a dataset', [Length(B.Chain.DataSetSites)])
  else 'no DataSet assignment in the DFM or in the form unit';
  B.AddHop('dataset', GRADE_UNRESOLVED, B.Local + '.DataSet', if B.DsPas <> '' then B.DsPas else B.DsFile, 0, Why);
  Result:= B.Stop('no-assignment', Why);
end;

{ hop 2: where the datasource gets its dataset. }
function StepDataSet(pW: TChainWalker; var B: TChainBuild): Boolean;
begin
  B.Chain.DataSetSites:= pW.DataSetSites(B.Chain.DataSource.Id, B.DsFile, B.DsPas, B.Local);
  var StaleSites: TArray<TDataSetSite>:= [];
  var Assigns: TArray<TDataSetSite>:= [];
  for var S in B.Chain.DataSetSites do
    if S.Kind = KIND_STALE then
      StaleSites:= StaleSites + [S]
    else if (S.Kind = KIND_ASSIGN) and not SameText(S.Rhs, NIL_TEXT) then
      Assigns:= Assigns + [S];
  if (Length(StaleSites) > 0) and (Length(Assigns) = 0) then
  begin
    var Why:= Format('%s differs from the indexed copy -- its %d DataSet site(s) are not read', [FileNameOf(B.DsPas), Length(StaleSites)]);
    B.AddHop('dataset', GRADE_STALE, B.Local + '.DataSet', B.DsPas, StaleSites[0].Line, Why);
    Exit(B.Stop(GRADE_STALE, Why));
  end;
  if Length(Assigns) = 0 then
    Exit(StopWithoutAssignment(B));
  B.A0:= Assigns[0];
  { the assignment LINE is a fact read from fresh source: certain when it is the only story }
  var RhsUpper: TArray<string>:= [];
  for var S in Assigns do
    RhsUpper:= RhsUpper + [S.Rhs.ToUpperInvariant];
  var RhsCount:= Length(SortUniqueNames(RhsUpper));
  var DsWhy: TArray<string>:= [];
  if RhsCount > 1 then
    DsWhy:= DsWhy + [Format('%d assignments with %d different right-hand sides; following the first', [Length(Assigns), RhsCount])];
  if Length(StaleSites) > 0 then
    DsWhy:= DsWhy + [Format('%d other site(s) in a stale file not read', [Length(StaleSites)])];
  B.AddHop('dataset', if Length(DsWhy) > 0 then GRADE_INFERRED else GRADE_CERTAIN, B.Local + '.DataSet := ' + B.A0.Rhs, B.A0.Path,
    B.A0.Line, string.Join('; ', DsWhy));
  Result:= True;
end;

{ The RHS root's declaration: the one whose parent is the assigning routine, else a field or
  property, else the first row (the PS's three-step $pick, in SQL row order). }
function PickRootDecl(pW: TChainWalker; const B: TChainBuild; const pRoot: string; out pKind, pSig: string): Boolean;
begin
  pKind:= '';
  pSig:= '';
  var Pid2:= if B.DsPas <> '' then pW.FReader.FileId(B.DsPas) else 0;
  var Decl:= pW.FIndex.Query(Format('SELECT s.kind AS kind, s.signature AS sig, s.parent_id AS pid FROM symbols s ' +
    'WHERE s.file_id = %d AND UPPER(s.name) = UPPER(''%s'') AND s.kind IN (''field'',''property'',''param'',''local_var'',''var'',''const'')',
    [Pid2, TChartsIndex.SqlText(pRoot)]));
  try
    Result:= Decl.Count > 0;
    if not Result then
      Exit;
    var At:= 0;
    for var K:= Decl.Count - 1 downto 0 do
    begin
      var OwnRoutine:= (Decl[K].I('pid') <> 0) and (Decl[K].I('pid') = B.A0.Eid);
      if OwnRoutine then
        At:= K;
    end;
    var Owned:= (Decl[At].I('pid') <> 0) and (Decl[At].I('pid') = B.A0.Eid);
    if not Owned then
      for var K:= Decl.Count - 1 downto 0 do
        if SameText(Decl[K].S('kind'), 'field') or SameText(Decl[K].S('kind'), 'property') then
          At:= K;
    pKind:= Decl[At].S('kind');
    pSig:= Decl[At].S('sig');
  finally
    Decl.Free;
  end;
end;

{ hop 3: the declared type of the RHS root. }
function StepRhsType(pW: TChainWalker; var B: TChainBuild): Boolean;
var
  Kind, Sig: string;
begin
  var Rr:= RhsRoot(B.A0.Rhs);
  if Rr.Root = '' then
  begin
    B.AddHop('rhs-type', GRADE_UNRESOLVED, B.A0.Rhs, B.DsPas, B.A0.Line, Rr.Reason);
    Exit(B.Stop('no-type', Rr.Reason));
  end;
  if not PickRootDecl(pW, B, Rr.Root, Kind, Sig) then
  begin
    var Why:= Format('%s is not declared as a field, property, parameter or variable in %s', [Rr.Root, FileNameOf(B.DsPas)]);
    B.AddHop('rhs-type', GRADE_UNRESOLVED, Rr.Root, B.DsPas, B.A0.Line, Why);
    Exit(B.Stop('no-type', Why));
  end;
  var T:= Default(TRhsType);
  T.Present:= True;
  T.Rhs:= B.A0.Rhs;
  T.Root:= Rr.Root;
  T.RootKind:= Kind;
  T.TypeName:= PsTrim(TRegEx.Replace(Sig, GENERIC_TAIL_PATTERN, ''));
  B.Chain.RhsType:= T;
  var Ts:= pW.FIndex.Query(Format('SELECT s.kind AS kind, s.start_line AS line, f.path AS path, s.file_id AS fid ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id WHERE UPPER(s.name) = UPPER(''%s'') AND s.kind IN (''class'',''interface'',''record'')',
    [TChartsIndex.SqlText(T.TypeName)]));
  try
    if Ts.Count <> 1 then
    begin
      var Why:= if Ts.Count <> 0 then Format('%s names %d types in this index -- cannot tell which', [T.TypeName, Ts.Count])
        else Format('%s is a %s, which is not declared in this index (library type)', [Rr.Root, T.TypeName]);
      B.AddHop('rhs-type', GRADE_UNRESOLVED, Rr.Root + ': ' + T.TypeName, B.DsPas, B.A0.Line, Why);
      Exit(B.Stop('no-type', Why));
    end;
    B.Chain.RhsType.TypeKind:= Ts[0].S('kind');
    B.Chain.RhsType.TypePath:= Ts[0].S('path');
    B.Chain.RhsType.TypeLine:= Ts[0].I('line');
    B.TsFid:= Ts[0].I('fid');
  finally
    Ts.Free;
  end;
  B.AddHop('rhs-type', GRADE_BY_NAME, Rr.Root + ': ' + T.TypeName, B.Chain.RhsType.TypePath, B.Chain.RhsType.TypeLine, '');
  Result:= True;
end;

{ The table-name literals of the type's unit: exact (candidates, first-literal order) and case-only (named, never taken). }
procedure LoadTableLiterals(pW: TChainWalker; var B: TChainBuild);
begin
  var InNames:= TChartsIndex.SqlInList(pW.FSet.Names);
  var Lit:= pW.FIndex.Query(Format('SELECT sl.text AS t, MIN(sl.start_line) AS line FROM string_literals sl ' +
    'WHERE sl.file_id = %d AND sl.kind IN (''literal'',''const'') AND sl.text IN (%s) GROUP BY sl.text ORDER BY MIN(sl.start_line), sl.text',
    [B.TsFid, InNames]));
  try
    for var R in Lit do
    begin
      B.Chain.CandidateTables:= B.Chain.CandidateTables + [R.S('t')];
      B.Chain.CandidateLines:= B.Chain.CandidateLines + [R.I('line')];
    end;
  finally
    Lit.Free;
  end;
  var Ci:= pW.FIndex.Query(Format('SELECT sl.text AS t, MIN(sl.start_line) AS line FROM string_literals sl ' +
    'WHERE sl.file_id = %d AND sl.kind IN (''literal'',''const'') AND UPPER(sl.text) IN (%1:s) AND sl.text NOT IN (%1:s) ' +
    'GROUP BY sl.text ORDER BY MIN(sl.start_line), sl.text', [B.TsFid, InNames]));
  try
    for var R in Ci do
      B.Chain.CaseOnlyLiterals:= B.Chain.CaseOnlyLiterals + [Format('''%s'' :%d', [R.S('t'), R.I('line')])];
  finally
    Ci.Free;
  end;
end;

{ hop 4: the table -- one literal, or the one candidate holding every bound column, else many / none. }
procedure StepTable(pW: TChainWalker; var B: TChainBuild);
begin
  LoadTableLiterals(pW, B);
  var TypeFile:= B.Chain.RhsType.TypePath;
  var UnitFile:= FileNameOf(TypeFile);
  var CaseNote:= '';
  if Length(B.Chain.CaseOnlyLiterals) > 0 then
    CaseNote:= Format('; %d literal(s) equal a table name only case-insensitively and are not taken as one: %s',
      [Length(B.Chain.CaseOnlyLiterals), string.Join(', ', B.Chain.CaseOnlyLiterals)]);
  var Cand:= B.Chain.CandidateTables;
  if Length(Cand) = 0 then
  begin
    var Why:= Format('%s holds no upper-case string literal naming a table', [UnitFile]) + (if SameText(B.Chain.RhsType.TypeKind, 'interface')
      then Format(' (%s is an interface; its implementation is not followed)', [B.Chain.RhsType.TypeName]) else '') + CaseNote;
    B.AddHop('table', GRADE_UNRESOLVED, B.Chain.RhsType.TypeName, TypeFile, B.Chain.RhsType.TypeLine, Why);
    B.Stop('none', Why);
    Exit;
  end;
  if Length(Cand) = 1 then
  begin
    B.Chain.ResolvedTable:= Cand[0];
    B.AddHop('table', GRADE_INFERRED, Cand[0], TypeFile, B.Chain.CandidateLines[0], Format('the only upper-case table-name literal in %s', [UnitFile]) + CaseNote);
    B.Stop('one-table', '');
    Exit;
  end;
  { after the one-table return: a single candidate needs no tie-break (and no source scan) }
  var FitLine:= 0;
  for var K:= 0 to Length(Cand) - 1 do
    if Length(ColumnsNotHeld(pW.FCatalog, pW.FSet, Cand[K], B.Chain.BoundColumns)) = 0 then
    begin
      if Length(B.Chain.ColumnMatch) = 0 then
        FitLine:= B.Chain.CandidateLines[K];
      B.Chain.ColumnMatch:= B.Chain.ColumnMatch + [Cand[K]];
    end;
  var Bound:= Length(B.Chain.BoundColumns);
  if (Bound > 0) and (Length(B.Chain.ColumnMatch) = 1) then
  begin
    B.Chain.ResolvedTable:= B.Chain.ColumnMatch[0];
    B.AddHop('table', GRADE_INFERRED, B.Chain.ColumnMatch[0], TypeFile, FitLine, Format('%d tables named in upper case in %s; only %s holds all %d bound column(s)',
      [Length(Cand), UnitFile, B.Chain.ColumnMatch[0], Bound]) + CaseNote);
    B.Stop('by-columns', '');
    Exit;
  end;
  var Why:= if Bound = 0 then
    Format('%s names %d tables in upper case and no column is bound through %s to tell them apart', [UnitFile, Length(Cand), B.Local]) + CaseNote
  else
    Format('%s names %d tables in upper case; %d of them hold all %d bound column(s)', [UnitFile, Length(Cand), Length(B.Chain.ColumnMatch), Bound]) + CaseNote;
  B.AddHop('table', GRADE_UNRESOLVED, Format('%d candidates', [Length(Cand)]), TypeFile, B.Chain.RhsType.TypeLine, Why);
  B.Stop('many', Why);
end;

function TChainWalker.DataSourceChain(const pForm, pDsName: string): TDataSourceChain;
var
  B: TChainBuild;
begin
  B:= Default(TChainBuild);
  B.Chain.DsName:= pDsName;
  StepLocateForm(Self, pForm, B);
  StepControls(Self, B);
  if StepDataSource(Self, B) then
  begin
    StepBoundColumns(Self, B);
    if StepDataSet(Self, B) and StepRhsType(Self, B) then
      StepTable(Self, B);
  end;
  Result:= B.Chain;
end;

type
  { The walk being built (the PS $hops / Hop / Done closure of Get-RePointChain). Done
    returns False so a step can `Exit(B.Done(...))` like the PS `return (Done ...)`. }
  TRePointBuild = record
    Walk: TRePointChain;
    procedure Hop(const pHop: TChainHop; const pRoutine, pAsk: string);
    function Done(const pStop, pStale: string; pLimit: Boolean = False): Boolean;
  end;

procedure TRePointBuild.Hop(const pHop: TChainHop; const pRoutine, pAsk: string);
begin
  var H:= pHop;
  H.Routine:= pRoutine;
  H.Ask:= pAsk;
  Walk.Hops:= Walk.Hops + [H];
end;

function TRePointBuild.Done(const pStop, pStale: string; pLimit: Boolean): Boolean;
begin
  Walk.StopReason:= pStop;
  Walk.StaleFile:= pStale;
  Walk.Limit:= pLimit;
  Result:= False;
end;

const
  FIELD_QUERY = 'SELECT s.id AS id, s.name AS name, s.signature AS sig, s.start_line AS line, f.path AS path, ' +
    's.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id';
  MEMBER_COLUMNS = 'SELECT t.id AS tid, t.kind AS tkind, t.qualified_name AS tq, t.start_line AS tline, t.signature AS tsig, ' +
    'tf.path AS tpath, t.file_id AS tfid, t.parent_id AS tpid ';

type
  { One row of the walk's field query ($fieldQ), or the member the walk stands on ($m / $fr). }
  TFieldRow = record
    Id   : Integer;
    Name : string;
    Sig  : string;
    Line : Integer;
    Path : string;
    Fid  : Integer;
    Pid  : Integer;
    Kind : string;
    QName: string;
  end;

function FieldRows(pIndex: TChartsIndex; const pWhere: string): TArray<TFieldRow>;
begin
  Result:= [];
  var Rows:= pIndex.Query(FIELD_QUERY + ' WHERE ' + pWhere);
  try
    for var R in Rows do
    begin
      var F:= Default(TFieldRow);
      F.Id:= R.I('id');
      F.Name:= R.S('name');
      F.Sig:= R.S('sig');
      F.Line:= R.I('line');
      F.Path:= R.S('path');
      F.Fid:= R.I('fid');
      F.Pid:= R.I('pid');
      Result:= Result + [F];
    end;
  finally
    Rows.Free;
  end;
end;

function MemberRows(pIndex: TChartsIndex; const pSql: string; const pMember: string): TArray<TFieldRow>;
begin
  Result:= [];
  var Rows:= pIndex.Query(pSql);
  try
    for var R in Rows do
    begin
      var M:= Default(TFieldRow);
      M.Id:= R.I('tid');
      M.Name:= pMember;
      M.Sig:= R.S('tsig');
      M.Line:= R.I('tline');
      M.Path:= R.S('tpath');
      M.Fid:= R.I('tfid');
      M.Pid:= R.I('tpid');
      M.Kind:= R.S('tkind');
      M.QName:= R.S('tq');
      Result:= Result + [M];
    end;
  finally
    Rows.Free;
  end;
end;

{ A bare identifier RHS: say WHAT it is -- a local or parameter of the re-pointing routine is not followed. }
function BareRhsStop(pIndex: TChartsIndex; pFid: Integer; const pRoot, pRoutine, pRn, pFile: string): string;
begin
  var Bd:= pIndex.Query(Format('SELECT s.kind AS kind, s.signature AS sig, s.start_line AS line, p.qualified_name AS pq ' +
    'FROM symbols s LEFT JOIN symbols p ON p.id = s.parent_id WHERE s.file_id = %d AND UPPER(s.name) = UPPER(''%s'') ' +
    'AND s.kind IN (''param'',''local_var'',''field'',''var'',''property'') ' +
    'ORDER BY CASE WHEN p.qualified_name = ''%s'' THEN 0 ELSE 1 END, s.start_line LIMIT 1',
    [pFid, TChartsIndex.SqlText(pRoot), TChartsIndex.SqlText(pRoutine)]));
  try
    if Bd.Count = 0 then
      Exit(Format('%s is not declared in %s', [pRoot, FileNameOf(pFile)]));
    var Kind:= Bd[0].S('kind');
    var Ty:= PsTrim(TRegEx.Replace(Bd[0].S('sig'), COLON_LEAD_PATTERN, ''));
    var Line:= Bd[0].I('line');
    if SameText(Kind, 'param') then
      Result:= Format('%s is a parameter of %s (%s, :%d) -- the arguments its callers pass are not followed', [pRoot, pRn, Ty, Line])
    else if SameText(Kind, 'local_var') then
      Result:= Format('%s is a local variable of %s (%s, :%d) -- the value assigned to it there is not followed', [pRoot, pRn, Ty, Line])
    else
      Result:= Format('%s is a %s (%s, :%d) -- a bare datasource %s is not followed to where it is assigned', [pRoot, Kind, Ty, Line, Kind]);
  finally
    Bd.Free;
  end;
end;

{ The member ref on the re-point line, RIGHT of the re-pointed property's own ref (BOUND:
  certain); unbound, the root's declared type and its member by name. }
function RePointMember(pW: TChainWalker; var B: TRePointBuild; const pRePoint: TRePointSite; pFid: Integer; const pRoot, pMember: string;
  out pM: TFieldRow): Boolean;
begin
  pM:= Default(TFieldRow);
  var Mq:= TChartsIndex.SqlText(pMember);
  var Found:= MemberRows(pW.FIndex, MEMBER_COLUMNS + Format('FROM refs r JOIN symbols t ON t.id = r.symbol_id JOIN files tf ON tf.id = t.file_id ' +
    'WHERE r.file_id = %d AND r.start_line = %d AND r.kind = ''member-access'' AND r.name_text = ''%s'' AND EXISTS (SELECT 1 FROM refs d ' +
    'WHERE d.file_id = r.file_id AND d.start_line = r.start_line AND d.kind = ''member-access'' AND d.name_text = ''%s'' ' +
    'AND d.start_col < r.start_col) ORDER BY r.start_col', [pFid, pRePoint.Line, Mq, TChartsIndex.SqlText(pRePoint.Prop)]), pMember);
  var Grade:= GRADE_CERTAIN;
  if Length(Found) = 0 then
  begin
    var Decl:= pW.FIndex.Query(Format('SELECT s.signature AS sig FROM symbols s WHERE s.file_id = %d AND UPPER(s.name) = UPPER(''%s'') ' +
      'AND s.kind IN (''field'',''property'',''var'',''param'',''local_var'') ORDER BY s.start_line LIMIT 1', [pFid, TChartsIndex.SqlText(pRoot)]));
    var DeclSig: string;
    try
      if Decl.Count = 0 then
        Exit(B.Done(Format('%s is not declared in %s', [pRoot, FileNameOf(pRePoint.Path)]), ''));
      DeclSig:= Decl[0].S('sig');
    finally
      Decl.Free;
    end;
    var Tn:= TChartsIndex.SqlText(PsTrim(TRegEx.Replace(DeclSig, GENERIC_TAIL_PATTERN, '')));
    Found:= MemberRows(pW.FIndex, MEMBER_COLUMNS + Format('FROM symbols t JOIN files tf ON tf.id = t.file_id WHERE UPPER(t.name) = UPPER(''%s'') ' +
      'AND t.kind IN (''property'',''field'') AND t.parent_id IN (SELECT c.id FROM symbols c WHERE c.kind IN (''class'',''interface'') ' +
      'AND UPPER(c.name) = UPPER(''%s''))', [Mq, Tn]), pMember);
    if Length(Found) <> 1 then
      Exit(B.Done(Format('%s is not a property or field of %s in this index (%d matches)', [pMember, PsTrim(DeclSig), Length(Found)]), ''));
    Grade:= GRADE_BY_NAME;
  end;
  pM:= Found[0];
  B.Hop(MakeHop('member', Grade, pMember + ' : ' + PsTrim(pM.Sig), pM.Path, pM.Line,
    if Grade = GRADE_BY_NAME then 'member found by name on the declared type of ' + pRoot else ''), DotSegment(pM.QName, 2), '');
  Result:= True;
end;

{ A property accessor that is not a field of its class: its ONE implementation in a class whose
  heritage names the owner, then the ONE field the body reads. }
function AccessorField(pW: TChainWalker; var B: TRePointBuild; const pM: TFieldRow; const pAcc, pMember: string;
  out pFound: TArray<TFieldRow>): Boolean;
var
  IFid, IStart, IEnd, IPid: Integer;
  ReadName: string;
begin
  pFound:= [];
  var OwnerName:= DotSegment(pM.QName, 2);
  var On:= TChartsIndex.SqlText(OwnerName);
  var Impl:= pW.FIndex.Query(Format('SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, s.impl_end_line AS iend, ' +
    'f.path AS path, s.file_id AS fid, s.parent_id AS pid FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'WHERE s.name = ''%s'' AND s.kind = ''method'' AND s.impl_start_line > 0 AND s.parent_id IN (SELECT c.id FROM symbols c ' +
    'WHERE c.kind = ''class'' AND (c.id = %d OR INSTR('','' || REPLACE(COALESCE(c.heritage, ''''), '' '', '''') || '','', '',%2:s,'') > 0 ' +
    'OR INSTR('','' || REPLACE(COALESCE(c.heritage, ''''), '' '', '''') || '','', ''.%2:s,'') > 0))',
    [TChartsIndex.SqlText(pAcc), pM.Pid, On]));
  try
    if Impl.Count <> 1 then
      Exit(B.Done(Format('%s has %d implementations in classes implementing %s -- cannot tell which', [pAcc, Impl.Count, OwnerName]), ''));
    IFid:= Impl[0].I('fid');
    IStart:= Impl[0].I('istart');
    IEnd:= Impl[0].I('iend');
    IPid:= Impl[0].I('pid');
    B.Hop(MakeHop('accessor', GRADE_BY_NAME, pAcc, Impl[0].S('path'), IStart, Format('the read accessor of %s, implemented once in a class ' +
      'whose heritage names %s', [pMember, OwnerName])), DotSegment(Impl[0].S('q'), 2), 'in-class-field-reads');
  finally
    Impl.Free;
  end;
  { the field the accessor body reads: an in-class read, unbound in this index }
  var Reads:= pW.FIndex.Query(Format('SELECT DISTINCT r.name_text AS n FROM refs r WHERE r.file_id = %d AND r.start_line BETWEEN %d AND %d ' +
    'AND r.kind = ''read'' AND r.name_text <> ''Result'' AND r.name_text IN (SELECT s.name FROM symbols s WHERE s.parent_id = %d ' +
    'AND s.kind = ''field'')', [IFid, IStart, IEnd, IPid]));
  try
    if Reads.Count <> 1 then
      Exit(B.Done(Format('%s reads %d fields of its class -- cannot tell which is the datasource', [pAcc, Reads.Count]), ''));
    ReadName:= Reads[0].S('n');
  finally
    Reads.Free;
  end;
  pFound:= FieldRows(pW.FIndex, Format('s.parent_id = %d AND s.name = ''%s'' AND s.kind = ''field''', [IPid, TChartsIndex.SqlText(ReadName)]));
  Result:= True;
end;

{ A property member: the read accessor quoted from the FRESH declaration line, then the field behind it. }
function PropertyField(pW: TChainWalker; var B: TRePointBuild; const pM: TFieldRow; const pMember: string; out pFr: TFieldRow): Boolean;
var
  Found: TArray<TFieldRow>;
  FieldWhy, FieldAsk: string;
begin
  pFr:= Default(TFieldRow);
  if not pW.FReader.SourceFresh(pM.Path) then
    Exit(B.Done(Format('%s differs from the indexed copy -- the property''s read accessor is not read', [FileNameOf(pM.Path)]), pM.Path));
  var Lines:= pW.FReader.StrippedSourceLines(pW.FReader.ReadPath(pM.Path));
  { a line past the end reads $null in the PS: no accessor }
  var DeclLine:= if (pM.Line >= 1) and (pM.Line <= Length(Lines)) then Lines[pM.Line - 1] else '';
  var Acc:= TRegEx.Match(DeclLine, READ_ACCESSOR_PATTERN);
  if not Acc.Success then
    Exit(B.Done(Format('property %s at %s:%d has no read accessor on its declaration line', [pMember, FileNameOf(pM.Path), pM.Line]), ''));
  var AccName:= Acc.Groups[1].Value;
  { a field accessor (`read FX`) is the field itself, found by name in the property's class }
  Found:= FieldRows(pW.FIndex, Format('s.parent_id = %d AND s.name = ''%s'' AND s.kind = ''field''', [pM.Pid, TChartsIndex.SqlText(AccName)]));
  if Length(Found) > 0 then
  begin
    FieldWhy:= Format('the read accessor of %s, by name in its class', [pMember]);
    FieldAsk:= '';
  end
  else
  begin
    if not AccessorField(pW, B, pM, AccName, pMember, Found) then
      Exit(False);
    FieldWhy:= 'an in-class read, unbound in this index';
    FieldAsk:= 'in-class-field-reads';
  end;
  if Length(Found) <> 1 then
    Exit(B.Done(Format('the datasource field behind %s was not found', [pMember]), ''));
  pFr:= Found[0];
  B.Hop(MakeHop('field', GRADE_BY_NAME, pFr.Name + ' : ' + PsTrim(pFr.Sig), pFr.Path, pFr.Line, FieldWhy), '', FieldAsk);
  Result:= True;
end;

{ A non-property member IS the datasource field -- only when it is a FIELD of a datasource type;
  anything else is a shape this walk does not follow (a named LIMIT, never "never assigned"). }
function MemberIsDataSourceField(var B: TRePointBuild; const pM: TFieldRow; const pMember: string; const pSegs: TArray<string>): Boolean;
begin
  var MTy:= PsTrim(TRegEx.Replace(pM.Sig, COLON_LEAD_PATTERN, ''));
  if SameText(pM.Kind, 'field') and ContainsText(MTy, 'DataSource') then
    Exit(True);
  var Rest:= ' -- not followed further';
  if Length(pSegs) > 2 then
    Rest:= Format(' -- the member .%s after it is not followed', [string.Join('.', Copy(pSegs, 2, MaxInt))]);
  var Desc:= if MTy = '' then Format('a %s with no declared type', [pM.Kind])
    else if SameText(pM.Kind, 'method') or SameText(pM.Kind, 'function') then Format('a %s returning %s', [pM.Kind, MTy])
    else Format('a %s of type %s', [pM.Kind, MTy]);
  Result:= B.Done(Format('the walk reached %s, %s, not a datasource field%s', [pMember, Desc, Rest]), '', True);
end;

{ `<field>.DataSet :=` in the field's unit, to the dataset field of the same class. }
procedure RePointDataSet(pW: TChainWalker; var B: TRePointBuild; const pFr: TFieldRow);
begin
  var Sites:= pW.DataSetSites(0, '', pFr.Path, pFr.Name);
  var Stale:= 0;
  var Assigns: TArray<TDataSetSite>:= [];
  for var S in Sites do
    if S.Kind = KIND_STALE then
      Inc(Stale)
    else if (S.Kind = KIND_ASSIGN) and not SameText(S.Rhs, NIL_TEXT) then
      Assigns:= Assigns + [S];
  if (Stale > 0) and (Length(Assigns) = 0) then
  begin
    B.Done(Format('%s differs from the indexed copy -- its %d DataSet site(s) are not read', [FileNameOf(pFr.Path), Stale]), pFr.Path);
    Exit;
  end;
  if Length(Assigns) = 0 then
  begin
    B.Done(Format('%s.DataSet is never assigned in %s (%d site(s) scanned)', [pFr.Name, FileNameOf(pFr.Path), Length(Sites)]), '');
    Exit;
  end;
  var A0:= Assigns[0];
  var DsName:= DotSegment(TRegEx.Replace(A0.Rhs, '(?i)^Self\.', ''), 1);
  var DsRow:= FieldRows(pW.FIndex, Format('s.parent_id = %d AND s.name = ''%s'' AND s.kind = ''field''', [pFr.Pid, TChartsIndex.SqlText(DsName)]));
  if Length(DsRow) <> 1 then
  begin
    B.Done(Format('the dataset %s assigned at :%d is not a field of the same class (%d matches)', [A0.Rhs, A0.Line, Length(DsRow)]), '');
    Exit;
  end;
  { as in Get-DataSourceChain: certain when every non-nil assignment names the same RHS }
  var RhsUpper: TArray<string>:= [];
  for var S in Assigns do
    RhsUpper:= RhsUpper + [S.Rhs.ToUpperInvariant];
  var RhsCount:= Length(SortUniqueNames(RhsUpper));
  var Why:= if RhsCount > 1 then Format('%d assignments with %d different right-hand sides, following the first', [Length(Assigns), RhsCount]) else '';
  B.Hop(MakeHop('dataset', if Why <> '' then GRADE_INFERRED else GRADE_CERTAIN, pFr.Name + '.DataSet := ' + A0.Rhs, A0.Path, A0.Line, Why),
    DotSegment(A0.Routine, 1), '');
  B.Walk.DataSet.Present:= True;
  B.Walk.DataSet.Name:= DsRow[0].Name;
  B.Walk.DataSet.Id:= DsRow[0].Id;
  B.Walk.DataSet.ClassId:= DsRow[0].Pid;
  B.Walk.DataSet.Path:= DsRow[0].Path;
  B.Walk.DataSet.Fid:= DsRow[0].Fid;
  B.Walk.DataSet.Line:= DsRow[0].Line;
  B.Walk.DataSet.TypeName:= PsTrim(DsRow[0].Sig);
  B.Done('', '');
end;

function TChainWalker.RePointChain(const pRePoint: TRePointSite): TRePointChain;
var
  B : TRePointBuild;
  M : TFieldRow;
  Fr: TFieldRow;
begin
  B.Walk:= Default(TRePointChain);
  if pRePoint.Stale then
  begin
    B.Done(Format('%s differs from the indexed copy -- the re-point at :%d is not read', [FileNameOf(pRePoint.Path), pRePoint.Line]), pRePoint.Path);
    Exit(B.Walk);
  end;
  var Rn:= DotSegment(pRePoint.Routine, 1);
  B.Hop(MakeHop('re-point', GRADE_CERTAIN, Format('%s.%s := %s', [pRePoint.Control, pRePoint.Prop, pRePoint.Rhs]), pRePoint.Path,
    pRePoint.Line, ''), Rn, '');
  var Rr:= RhsRoot(pRePoint.Rhs);
  var Segs:= TRegEx.Replace(TRegEx.Replace(PsTrim(pRePoint.Rhs), SELF_PREFIX_PATTERN, ''), WS_PATTERN, '').Split(['.']);
  var Fid:= FReader.FileId(pRePoint.Path);
  if Rr.Root = '' then
    B.Done(Rr.Reason, '')
  else if Length(Segs) < 2 then
    { a bare identifier: a local or parameter of the re-pointing routine is not followed }
    B.Done(BareRhsStop(FIndex, Fid, Rr.Root, pRePoint.Routine, Rn, pRePoint.Path), '', True)
  else
  begin
    var Member:= TRegEx.Replace(Segs[1], CALL_TAIL_PATTERN, '');
    if RePointMember(Self, B, pRePoint, Fid, Rr.Root, Member, M) then
    begin
      var HaveField:= if SameText(M.Kind, 'property') then PropertyField(Self, B, M, Member, Fr) else MemberIsDataSourceField(B, M, Member, Segs);
      if not SameText(M.Kind, 'property') then
        Fr:= M;
      if HaveField then
        RePointDataSet(Self, B, Fr);
    end;
  end;
  Result:= B.Walk;
end;

function TChainWalker.RePointPick(const pChain: TDataSourceChain; const pOwner: string): TRePointPick;
begin
  Result:= Default(TRePointPick);
  Result.Status:= 'follow';
  var Mine:= 0;
  var StaleRows: TArray<TRePointSite>:= [];
  for var S in pChain.RePointedAt do
  begin
    if not SameText(S.Control, pOwner) then
      Continue;
    Inc(Mine);
    if S.Stale or not SameText(S.Rhs, NIL_TEXT) then
    begin
      Result.Rows:= Result.Rows + [S];
      if S.Stale then
        StaleRows:= StaleRows + [S];
    end;
  end;
  Result.NilSites:= Mine - Length(Result.Rows);
  if (Length(StaleRows) > 0) or ((pChain.PasFile <> '') and (Length(Result.Rows) = 0) and not FReader.SourceFresh(pChain.PasFile)) then
  begin
    Result.Status:= 'stale';
    Result.StaleFile:= if Length(StaleRows) > 0 then StaleRows[0].Path else pChain.PasFile;
    Result.Stop:= Format('%s differs from the indexed copy -- the code re-point of %s is not read', [FileNameOf(Result.StaleFile), pOwner]);
    Exit;
  end;
  var RhsUpper: TArray<string>:= [];
  for var S in Result.Rows do
    RhsUpper:= RhsUpper + [TRegEx.Replace(S.Rhs, WS_PATTERN, '').ToUpperInvariant];
  var RhsCount:= Length(SortUniqueNames(RhsUpper));
  if RhsCount > 1 then
  begin
    var Where: TArray<string>:= [];
    for var S in Result.Rows do
      Where:= Where + [Format('%s:%d', [FileNameOf(S.Path), S.Line])];
    Result.Status:= 'multi-rhs';
    Result.Stop:= Format('%s is re-pointed at %d sites with %d different right-hand sides (%s) -- cannot tell which feeds the grid',
      [pOwner, Length(Result.Rows), RhsCount, string.Join(', ', Where)]);
    Exit;
  end;
  if Length(Result.Rows) = 0 then
    Result.Status:= 'no-site';
end;

function TChainWalker.DataSetTableLiterals(const pDataSet: TChainDataSet): TArray<TTableLiteral>;
begin
  Result:= [];
  var Rows:= FIndex.Query(Format('SELECT sl.text AS t, MIN(sl.start_line) AS line, COUNT(*) AS n FROM string_literals sl ' +
    'WHERE sl.file_id = %d AND sl.kind = ''literal'' AND sl.text IN (%s) AND EXISTS (SELECT 1 FROM refs r WHERE r.file_id = sl.file_id ' +
    'AND r.start_line = sl.start_line AND r.name_text = ''%s'') GROUP BY sl.text ORDER BY MIN(sl.start_line), sl.text',
    [pDataSet.Fid, TChartsIndex.SqlInList(FSet.Names), TChartsIndex.SqlText(pDataSet.Name)]));
  try
    for var R in Rows do
    begin
      var L: TTableLiteral;
      L.Table:= R.S('t');
      L.Line:= R.I('line');
      L.Lines:= R.I('n');
      Result:= Result + [L];
    end;
  finally
    Rows.Free;
  end;
end;

function TChainWalker.ResolveRePointTable(const pChain: TDataSourceChain; const pOwner: string): TRePointTable;
begin
  var Pk:= RePointPick(pChain, pOwner);
  Result:= Default(TRePointTable);
  Result.Status:= Pk.Status;
  Result.Owner:= pOwner;
  Result.Sites:= Pk.Rows;
  Result.NilSites:= Pk.NilSites;
  Result.Stop:= Pk.Stop;
  Result.StaleFile:= Pk.StaleFile;
  if Pk.Status <> 'follow' then
  begin
    if Pk.Status = 'no-site' then
      Result.Stop:= if Pk.NilSites > 0 then Format('%s is re-pointed in code only to nil (%d site(s)) -- nothing to follow', [pOwner, Pk.NilSites])
        else Format('no code re-point of %s in %s -- nothing to follow', [pOwner, UnitNameOf(pChain.PasFile)]);
    Exit;
  end;
  var Rc:= RePointChain(Pk.Rows[0]);
  Result.Hops:= Rc.Hops;
  if Rc.StaleFile <> '' then
  begin
    Result.Status:= 'stale';
    Result.StaleFile:= Rc.StaleFile;
    Result.Stop:= Rc.StopReason;
    Exit;
  end;
  if Rc.StopReason <> '' then
  begin
    Result.Status:= if Rc.Limit then 'walk-limit' else 'stops';
    Result.Stop:= Rc.StopReason;
    Exit;
  end;
  Result.DataSet:= Rc.DataSet;
  var Lit:= DataSetTableLiterals(Rc.DataSet);
  if Length(Lit) <> 1 then
  begin
    Result.Status:= 'no-table';
    if Length(Lit) = 0 then
      Result.Stop:= Format('no upper-case table-name literal shares a line with %s in %s -- the table cannot be inferred',
        [Rc.DataSet.Name, UnitNameOf(Rc.DataSet.Path)])
    else
    begin
      var Names: TArray<string>:= [];
      for var L in Lit do
        Names:= Names + [L.Table];
      Result.Stop:= Format('%d tables share a line with %s in %s (%s) -- cannot tell which',
        [Length(Lit), Rc.DataSet.Name, UnitNameOf(Rc.DataSet.Path), string.Join(', ', Names)]);
    end;
    Exit;
  end;
  Result.Status:= 'table';
  Result.Table:= Lit[0].Table;
  Result.TableLine:= Lit[0].Line;
  Result.TableLines:= Lit[0].Lines;
end;

type
  { The population being built: chains and re-point tables keyed case-insensitively, kept in first-use order. }
  TBindingBuild = class
  private
    FWalker   : TChainWalker;
    FChainAt  : TDictionary<string, Integer>;
    FRePointAt: TDictionary<string, Integer>;
    FOut      : TFieldBindingChains;
  public
    constructor Create(pWalker: TChainWalker);
    destructor Destroy; override;
    function Chain(const pDfm, pDs: string): Integer;
    function RePoint(const pKey: string; pChain: Integer; const pOwner: string): Integer;
    procedure AddDataSource(pChain: Integer);
    procedure AddBinding(const pRow: TFieldBinding);
    function Outcome(const pRow: TFieldBinding; pChain: Integer): string;
    property Population: TFieldBindingChains read FOut;
  end;

constructor TBindingBuild.Create(pWalker: TChainWalker);
begin
  inherited Create;
  FWalker:= pWalker;
  FChainAt:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  FRePointAt:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
end;

destructor TBindingBuild.Destroy;
begin
  FRePointAt.Free;
  FChainAt.Free;
  inherited Destroy;
end;

function TBindingBuild.Chain(const pDfm, pDs: string): Integer;
begin
  var K:= ChainKey(pDfm, pDs);
  if FChainAt.TryGetValue(K, Result) then
    Exit;
  Result:= Length(FOut.Chains);
  FOut.ChainKeys:= FOut.ChainKeys + [K];
  FOut.Chains:= FOut.Chains + [FWalker.DataSourceChain(pDfm, pDs)];
  FChainAt.Add(K, Result);
end;

function TBindingBuild.RePoint(const pKey: string; pChain: Integer; const pOwner: string): Integer;
begin
  if FRePointAt.TryGetValue(pKey, Result) then
    Exit;
  Result:= Length(FOut.RePoints);
  FOut.RePointKeys:= FOut.RePointKeys + [pKey];
  FOut.RePoints:= FOut.RePoints + [FWalker.ResolveRePointTable(FOut.Chains[pChain], pOwner)];
  FRePointAt.Add(pKey, Result);
end;

procedure TBindingBuild.AddDataSource(pChain: Integer);
begin
  FOut.DataSources:= FOut.DataSources + [FOut.Chains[pChain]];
end;

procedure TBindingBuild.AddBinding(const pRow: TFieldBinding);
begin
  FOut.Bindings:= FOut.Bindings + [pRow];
end;

{ Where a binding's chain ends, judged by the SHARED column test (cheap first, the source
  scan only for a miss). pRow carries Table / Dangling / RePoint already. }
function TBindingBuild.Outcome(const pRow: TFieldBinding; pChain: Integer): string;
begin
  var Ch:= FOut.Chains[pChain];
  if (Ch.Grade = GRADE_STALE) or (Ch.Dangling and (pRow.RePoint = 'stale')) then
    Exit('stale');
  if Ch.Dangling and (pRow.Table = '') then
    Exit('dangling');
  if pRow.Table = '' then
    Exit(if Ch.Grade = 'many' then 'ambiguous' else 'stops');
  if FWalker.FSet.Table(pRow.Table).IsColumn(pRow.Column) then
    Exit('column');
  var State:= SqlColumnState(FWalker.FCatalog, FWalker.FSet, pRow.Table, pRow.Column, TServerSqlHit.None, '').State;
  Result:= if SameText(State, 'quoted') then 'column' else if SameText(State, 'stale') then 'stale' else 'not-column';
end;

{ The owner of a dangling binding: the nearest of control, parent, grandparent that is a
  non-lookup control of the chain (Get-ControlDataSourceSql's nearest-first rule). }
function OwnerOf(const pChain: TDataSourceChain; const pIds: TArray<Integer>): string;
begin
  Result:= '';
  for var Id in pIds do
    if Id <> 0 then
      for var C in pChain.Controls do
        if not C.IsLookup and (C.ControlId = Id) then
          Exit(C.Control);
end;

{ One binding row: its chain, past a DANGLING datasource the owner's code re-point, then its outcome. }
function BindingRow(pBuild: TBindingBuild; pBind: TIndexRow): TFieldBinding;
begin
  Result:= Default(TFieldBinding);
  Result.Id:= pBind.I('id');
  Result.Dfm:= pBind.S('dfm');
  Result.Line:= pBind.I('line');
  Result.Prop:= pBind.S('prop');
  Result.Column:= pBind.S('col');
  Result.ControlId:= pBind.I('cid');
  Result.Control:= pBind.S('ctl');
  Result.Ds:= pBind.S('ds');
  Result.Outcome:= 'no-ds';
  if Result.Ds = '' then
    Exit;
  var At:= pBuild.Chain(Result.Dfm, Result.Ds);
  var Ch:= pBuild.Population.Chains[At];
  Result.Table:= Ch.ResolvedTable;
  Result.Dangling:= Ch.Dangling;
  var Owner: string:= '';
  if Ch.Dangling then
    Owner:= OwnerOf(Ch, [pBind.I('cid'), pBind.I('pid'), pBind.I('gpid')]);
  if Owner <> '' then
  begin
    Result.RePointKey:= (pBuild.Population.ChainKeys[At] + '|' + Owner).ToUpperInvariant;
    var Rp:= pBuild.Population.RePoints[pBuild.RePoint(Result.RePointKey, At, Owner)];
    Result.RePoint:= Rp.Status;
    if Rp.Status = 'table' then
      Result.Table:= Rp.Table;
  end;
  Result.Outcome:= pBuild.Outcome(Result, At);
end;

function TChainWalker.FieldBindingChains: TFieldBindingChains;
begin
  var Build:= TBindingBuild.Create(Self);
  try
    var DsRows:= FIndex.AllRows('SELECT c.id AS id, c.name AS name, f.path AS path FROM symbols c JOIN files f ON f.id = c.file_id ' +
      'WHERE c.kind = ''component'' AND c.signature = ''TDataSource''', 'c.id');
    try
      for var D in DsRows do
        Build.AddDataSource(Build.Chain(D.S('path'), D.S('name')));
    finally
      DsRows.Free;
    end;
    var Binds:= FIndex.AllRows('SELECT sl.id AS id, sl.start_line AS line, sl.owner_name AS prop, sl.text AS col, f.path AS dfm, ' +
      'c.id AS cid, c.name AS ctl, c.parent_id AS pid, (SELECT g.parent_id FROM symbols g WHERE g.id = c.parent_id) AS gpid, ' +
      ControlDataSourceSql('sl', 'c') + ' AS ds FROM string_literals sl JOIN files f ON f.id = sl.file_id ' +
      'LEFT JOIN symbols c ON c.id = sl.symbol_id WHERE sl.kind = ''dfm-prop'' ' +
      'AND sl.owner_name IN (''DataBinding.FieldName'',''DataBinding.DataField'',''DataField'')', 'sl.id');
    try
      for var Bd in Binds do
        Build.AddBinding(BindingRow(Build, Bd));
    finally
      Binds.Free;
    end;
    Result:= Build.Population;
  finally
    Build.Free;
  end;
end;

end.