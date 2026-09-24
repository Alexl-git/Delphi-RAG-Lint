unit DRagLint.Report.CyclePlan;  // dl:ok unit-too-large@252c -- one self-contained pipeline (plan, materialise, predict, render) whose ~15 record types are private to it; a split would publish them all for no second caller

// ---------------------------------------------------------------------------
// `drag-lint cycles --plan` -- the circular-dependency refactoring playbook.
//
// Written for the CHEAPEST reader: a model with no project context and no
// index access must be able to follow it to a compiling tree whose `cycles`
// report matches the playbook's own prediction
// (docs\INBOX-test-cycle-playbook-followability-haiku-flash.md). The old
// playbook said "extract the shared contract into a leaf unit"; Haiku moved a
// CLASS declaration without its method bodies (E2065 x5) and was then told the
// cycle "should be gone" when a legal implementation-only cycle remained.
//
// So every step here is concrete: the kind of each symbol and the recipe for
// that kind, exact line ranges, the full text of every new unit, the current
// and the replacement text of every edited line, a per-unit decision on the
// old uses entry, a DONE definition, and a checklist that ends in the exact
// output `cycles` must print afterwards -- computed by replaying the plan on
// the unit graph, not promised.
// ---------------------------------------------------------------------------

interface

uses
  System.Classes, System.Generics.Collections,
  DRagLint.Core.Interfaces;

const
  /// <summary>Tag `cycles` prints after a group that has interface coupling.
  /// Shared with DoCycles so the playbook's predicted output cannot drift
  /// from what the report really prints.</summary>
  CCycleTagInterface = '(has interface coupling -- widest recompile blast radius)';
  /// <summary>Tag `cycles` prints after an implementation-only group.</summary>
  CCycleTagImplOnly = '(implementation-only -- legal, lower impact)';
  /// <summary>Hint line `cycles` prints after the groups when neither
  /// --edges nor --causes was given.</summary>
  CCycleEdgesHint = '  (add --edges for the uses lines, --causes for the symbols to refactor)';
  /// <summary>What `cycles` prints for an acyclic unit graph.</summary>
  CCycleNone = 'No circular unit dependencies found.';
  /// <summary>First line of a non-empty report; the argument is the group count.</summary>
  CCycleCountFmt = '%d circular unit group(s) found:';
  /// <summary>One group line: size, members joined by ' &lt;-&gt; ', tag.</summary>
  CCycleGroupFmt = '  [%d units] %s   %s';

type
  /// <summary>The unit-uses graph DoCycles already built, handed to the
  /// playbook renderer.</summary>
  /// <remarks>Every dictionary is keyed by the LOWER-CASE unit stem (file name
  /// without extension) and is owned by the caller; the renderer only reads
  /// them.</remarks>
  TCycleGraph = record
    /// <summary>Unit stem -> stems it uses, from either uses clause.</summary>
    Adj: TDictionary<string, TList<string>>;
    /// <summary>Holds the key 'a-&gt;b' when a names b in its INTERFACE uses.</summary>
    IntfEdges: TDictionary<string, Boolean>;
    /// <summary>Unit stem -> source path.</summary>
    UnitFile: TDictionary<string, string>;
    /// <summary>Unit stem -> file id in the index.</summary>
    UnitFid: TDictionary<string, Int64>;
  end;

/// <summary>Renders the `cycles --plan` markdown playbook for every circular
/// unit group into <paramref name="pOut"/>, one output line per item.</summary>
/// <param name="pStore">Open index the graph was built from; read only.</param>
/// <param name="pDbPath">Path of that index, quoted in the re-check commands.</param>
/// <param name="pSccs">The circular groups (strongly-connected components of
/// more than one unit), as lower-case unit stems.</param>
/// <param name="pGraph">The uses graph the groups were computed from.</param>
/// <param name="pOut">Receives the markdown; lines are appended.</param>
/// <remarks>
/// <para>An INTERFACE-coupled group gets Part A: every symbol that one member's
/// interface takes from another moves into a new leaf unit
/// `&lt;Declaring&gt;.Contracts` -- a class whose method bodies use the cycle is
/// NOT moved; a base class carrying the members its consumers use is
/// extracted instead. An implementation-only group gets the cheapest edge
/// that can be cut the same way, or a statement that none can.</para>
/// <para>Line numbers are those of the files as indexed. Each file's edits are
/// listed bottom-up so they can be applied in order without renumbering.</para>
/// <para>The expected `cycles` output is predicted by replaying the planned
/// uses changes on the graph; it assumes the other groups are left alone.</para>
/// </remarks>
procedure RenderCyclePlaybook(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings);

implementation

uses
  System.SysUtils, System.IOUtils, System.StrUtils, System.RegularExpressions, System.Math,
  System.Generics.Defaults,
  DRagLint.Core.Model;

const
  CLeafSuffix    = '.Contracts';
  CBaseSuffix    = 'Base';
  CCodeFence     = '```';
  CPascalFence   = '```pascal';
  CTextFence     = '```text';
  CXmlFence      = '```xml';
  CEntryIndent   = '  ';
  CNotFound      = -1;
  CKeyFmt        = '%d:%d';
  COverrideTail  = ' override;';
  CAbstractTail  = ' virtual; abstract;';
  CMaxNamesShown = 6;
  CIntfMark      = '!';
  CStepMoves     = 1;
  CStepUses      = 2;
  CStepCreate    = 3;
  CStepEdit      = 4;
  CBlockWords: TArray<string> = ['type', 'var', 'const', 'threadvar', 'resourcestring'];

type
  TSect = (scIntf, scImpl, scProg);

  TLineRange = record
    First: Integer;
    Last : Integer;
  end;

  TPlanFile = record
    Fid      : Int64;
    Path     : string;
    UnitName : string;
    Stem     : string;
    IsProgram: Boolean;
    Lines    : TArray<string>;
    IntfLine : Integer;
    ImplLine : Integer;
    Syms     : TArray<TSymbol>;
    Refs     : TArray<TReference>;
    UsesList : TArray<TUnitUse>;
  end;

  TNeed = record
    Owner    : TSymbol;
    OwnerStem: string;
    Sect     : TSect;
    Line     : Integer;
    RefName  : string;
    RefKind  : TSymbolKind;
  end;

  TCandidate = record
    Actual: TSymbol;
    Owner : TSymbol;
    Stem  : string;
  end;

  TMoveKind = (mvDecl, mvWithBodies, mvBase, mvBlocked);

  TBaseMember = record
    Sym  : TSymbol;
    Range: TLineRange;
  end;

  TSwitchLine = record
    Fid    : Int64;
    Line   : Integer;
    NewText: string;
  end;

  TMoveItem = record
    Sym        : TSymbol;
    Stem       : string;
    Kind       : TMoveKind;
    Keyword    : string;
    Header     : Integer;
    Decl       : TLineRange;
    Bodies     : TArray<TLineRange>;
    Drags      : TArray<string>;
    Reason     : string;
    BaseName   : string;
    BaseIndent : string;
    BaseMembers: TArray<TBaseMember>;
    CutFids    : TArray<Int64>;
    HeaderNew  : string;
    Switches   : TArray<TSwitchLine>;
  end;

  TConsumer = record
    Fid : Int64;
    Sect: TSect;
    Line: Integer;
  end;

  TUsesVerdict = (uvKeep, uvKeepUnseen, uvMove, uvRemove);

  TUsesDecision = record
    Fid        : Int64;
    PartnerStem: string;
    Sect       : TSect;
    Verdict    : TUsesVerdict;
    Still      : string;
  end;

  TEditKind = (ekDelete, ekReplace, ekInsertAfter, ekManual);

  TFileEdit = record
    Kind    : TEditKind;
    First   : Integer;
    Last    : Integer;
    NewLines: TArray<string>;
    Note    : string;
  end;

  TEdgeEval = record
    FromStem: string;
    ToStem  : string;
    Needs   : TArray<TNeed>;
    Movable : Boolean;
    Why     : string;
    Cost    : Integer;
  end;

  TPredGroup = record
    Members: TArray<string>;
    HasIntf: Boolean;
  end;

  TCyclePlanner = class  // dl:ok god-class@8d65, high-response@8d65 -- implementation-private; one per cycles --plan run, holding the shared per-cycle state that every small step reads; its many methods are the steps, each short
  private
    FStore      : ISymbolStore;
    FDbPath     : string;
    FSccs       : TList<TArray<string>>;
    FGraph      : TCycleGraph;
    FOut        : TStrings;
    FProjectFid : Int64;
    FProjectFile: string;
    FFiles      : TDictionary<Int64, TPlanFile>;
    FPaths      : TDictionary<Int64, string>;
    FStemFid    : TDictionary<string, Int64>;
    FUsersOf    : TObjectDictionary<string, TList<Int64>>;
    FCands      : TDictionary<string, TArray<TCandidate>>;
    FSyms       : TDictionary<Int64, TSymbol>;
    FNeeds      : TDictionary<Int64, TArray<TNeed>>;
    // per-cycle state, cleared by ResetCycle
    FComp       : TArray<string>;
    FMembers    : TDictionary<string, Boolean>;
    FItems      : TDictionary<Int64, TMoveItem>;
    FOrder      : TList<Int64>;
    FManual     : TList<TMoveItem>;
    FDeleted    : TDictionary<string, Boolean>;
    FReplaced   : TDictionary<string, string>;
    FExtraEdits : TObjectDictionary<Int64, TList<TFileEdit>>;
    FLeafName   : TDictionary<string, string>;
    FLeafPath   : TDictionary<string, string>;
    FLeafDeps   : TObjectDictionary<string, TList<string>>;
    FConsumers  : TObjectDictionary<Int64, TList<TConsumer>>;
    FDecisions  : TList<TUsesDecision>;
    FUsesAdd    : TObjectDictionary<string, TList<string>>;
    FUsesDel    : TObjectDictionary<string, TList<string>>;
    FDprojEdits : TList<TFileEdit>;
    FTouched    : TList<Int64>;
    FPredicted  : TList<TPredGroup>;
    FCutEdge    : TEdgeEval;
    // loading + resolution
    procedure IndexAllFiles;
    function GetFile(pFid: Int64): TPlanFile;
    function PathOf(pFid: Int64): string;
    function StemOfFid(pFid: Int64): string;
    function GetSym(pId: Int64): TSymbol;
    function OwnerOf(const pSym: TSymbol; out pOwner: TSymbol): Boolean;
    function CandidatesFor(const pName: string): TArray<TCandidate>;
    function VisibleStems(const pF: TPlanFile; pSect: TSect): TArray<string>;
    function PickCandidate(const pF: TPlanFile; pSect: TSect; const pCands: TArray<TCandidate>): Integer;
    function IsLocalName(const pR: TReference): Boolean;
    function Resolve(const pF: TPlanFile; const pR: TReference; out pNeed: TNeed): Boolean;
    function NeedsOf(pFid: Int64): TArray<TNeed>;
    function FidOfStem(const pStem: string): Int64;
    function UnitNameOfStem(const pStem: string): string;
    // closure
    procedure ResetCycle(const pComp: TArray<string>);
    function IsDeclOnly(const pSym: TSymbol): Boolean;
    function BodyRanges(const pSym: TSymbol): TArray<TLineRange>;
    function NeedsInRanges(const pF: TPlanFile; const pRanges: TArray<TLineRange>): TArray<TNeed>;
    function MovedRanges(const pItem: TMoveItem): TArray<TLineRange>;
    function Classify(const pSym: TSymbol; const pCut: TArray<Int64>): TMoveItem;
    procedure ClassifyStructured(const pF: TPlanFile; var pItem: TMoveItem);
    procedure SetHeader(const pF: TPlanFile; var pItem: TMoveItem);
    procedure BuildBase(const pF: TPlanFile; var pItem: TMoveItem);
    function UsedMemberNames(const pChildren: TArray<TSymbol>; const pCut: TArray<Int64>): TDictionary<string, Boolean>;
    function PullMembers(const pF: TPlanFile; var pItem: TMoveItem; const pChildren: TArray<TSymbol>;
      pUsed: TDictionary<string, Boolean>): Boolean;
    function BuildSwitches(var pItem: TMoveItem): Boolean;
    function TryAdd(const pSym: TSymbol; const pCut: TArray<Int64>; out pWhy: string): Boolean;
    function AddDependencies(const pItem: TMoveItem; out pWhy: string): Boolean;
    function AddCompanions(const pItem: TMoveItem; out pWhy: string): Boolean;
    procedure Rollback(pSnap: Integer);
    function IsMovedFor(const pOwner: TSymbol; pFid: Int64): Boolean;
    // materialise
    procedure Materialize;
    procedure AssignLeafNames;
    function LeafStems: TArray<string>;
    procedure MarkDeleted(pFid: Int64; const pRange: TLineRange);
    function IsDeleted(pFid: Int64; pLine: Integer): Boolean;
    procedure MarkReplaced(pFid: Int64; pLine: Integer; const pText: string);
    procedure MarkItemLines;
    procedure DeleteEmptyHeaders;
    procedure CollectConsumers;
    procedure AddConsumer(const pItem: TMoveItem; pFid: Int64; pSect: TSect; pLine: Integer);
    procedure CollectLeafDeps;
    procedure DecideUses;
    procedure DecideOne(const pA: TPlanFile; const pU: TUnitUse);
    procedure RegisterLeaves;
    procedure AddUses(pFid: Int64; pSect: TSect; const pEntry: string);
    procedure DelUses(pFid: Int64; pSect: TSect; const pStem: string);
    procedure Touch(pFid: Int64);
    function EntryText(const pF: TPlanFile; const pU: TUnitUse): string;
    function EntryComment(const pF: TPlanFile; const pU: TUnitUse): string;
    function UsesEntryFor(const pF: TPlanFile; const pLeafStem: string): string;
    procedure DedupeAdds;
    procedure BuildUsesEdits;
    procedure BuildClauseEdit(const pF: TPlanFile; pSect: TSect);
    function SectionEntries(const pF: TPlanFile; pSect: TSect): TArray<TUnitUse>;
    function ListOf(pDict: TObjectDictionary<string, TList<string>>; pFid: Int64; pSect: TSect): TList<string>;
    function EditList(pFid: Int64): TList<TFileEdit>;
    function EditsOf(pFid: Int64): TArray<TFileEdit>;
    function EditOrder: TArray<Int64>;
    // prediction
    procedure Predict;
    function PredictedEdges: TObjectDictionary<string, TList<string>>;
    function Targets(pEdges: TObjectDictionary<string, TList<string>>; const pFrom: string): TArray<string>;
    function ExpectedOutput(pSelf: Integer): TArray<string>;
    function GroupHasIntf(const pComp: TArray<string>): Boolean;
    function EvaluateEdge(const pFrom, pTo: string; const pNeeds: TArray<TNeed>): TEdgeEval;
    function RemainingNeeds(const pFrom, pTo: string; pAll: Boolean): TArray<TNeed>;
    // rendering
    procedure Emit(const pText: string);
    procedure EmitFmt(const pFmt: string; const pArgs: array of const);
    procedure EmitBlock(const pFence: string; const pLines: TArray<string>);
    procedure RenderHeader;
    procedure RenderFiles;
    procedure RenderIntfWhy;
    procedure RenderImplWhy;
    procedure RenderMoves(pStep: Integer);
    procedure RenderOneMove(pNo: Integer; const pItem: TMoveItem);
    procedure RenderBaseRecipe(const pItem: TMoveItem);
    procedure RenderConsumers(const pItem: TMoveItem);
    procedure RenderManual;
    procedure RenderDecisions(pStep: Integer);
    procedure RenderLeafUnits(pStep: Integer);
    function LeafUnitText(const pStem: string): TArray<string>;
    function BaseClassText(const pItem: TMoveItem): TArray<string>;
    procedure RenderEdits(pStep: Integer);
    procedure RenderFileEdits(const pTitle: string; const pLines: TArray<string>;
      const pEdits: TArray<TFileEdit>; const pFence: string);
    procedure RenderChecklist(pSelf: Integer);
    procedure RenderCompileHelp;
    procedure RenderDone(pIntf: Boolean);
    procedure RenderPartB;
    procedure RenderIntfCycle(pSelf: Integer);
    procedure RenderImplCycle(pSelf: Integer);
    procedure RenderNoMechanicalCut(const pEvals: TArray<TEdgeEval>);
    procedure RenderRemedy;
    function ReindexCommand: string;
    function CyclesCommand(pPlan: Boolean): string;
    function KindLabel(const pItem: TMoveItem): string;
    function MemberNames: string;
  public
    constructor Create(const pStore: ISymbolStore; const pDbPath: string;
      const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings);
    destructor Destroy; override;
    procedure Run;
  end;

{ ---------------------------------------------------------------------------
  small text helpers
  --------------------------------------------------------------------------- }

function StemOfPath(const pPath: string): string;
begin
  Result:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), ''));
end;

function UnitNameOfPath(const pPath: string): string;
begin
  Result:= ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), '');
end;

function LineKey(pFid: Int64; pLine: Integer): string;
begin
  Result:= Format(CKeyFmt, [pFid, pLine]);
end;

function SectKey(pFid: Int64; pSect: TSect): string;
begin
  Result:= Format(CKeyFmt, [pFid, Ord(pSect)]);
end;

function IsIndented(const pLine: string): Boolean;
begin
  Result:= (pLine <> '') and CharInSet(pLine[1], [' ', #9]);
end;

function IsCommentOnly(const pLine: string): Boolean;
var
  T: string;
begin
  T:= Trim(pLine);
  if T = '' then Exit(True);
  if StartsStr('//', T) then Exit(True);
  if StartsStr('{', T) and EndsStr('}', T) then Exit(True);
  Result:= StartsStr('(*', T) and EndsStr('*)', T);
end;

/// Text of a line before its first comment (`//`, `{`, `(*`); quotes are honoured.
function CodePart(const pLine: string): string;
var
  InStr: Boolean;
  Pair : string;
begin
  InStr:= False;
  for var I:= 1 to Length(pLine) do
  begin
    if pLine[I] = '''' then InStr:= not InStr;
    if InStr then Continue;
    Pair:= Copy(pLine, I, 2);
    if (pLine[I] = '{') or (Pair = '//') or (Pair = '(*') then Exit(Copy(pLine, 1, I - 1));
  end;
  Result:= pLine;
end;

function LineAt(const pLines: TArray<string>; pLine: Integer): string;
begin
  if (pLine >= 1) and (pLine <= Length(pLines)) then Result:= pLines[pLine - 1]
  else Result:= '';
end;

function SliceLines(const pLines: TArray<string>; const pRange: TLineRange): TArray<string>;
begin
  SetLength(Result, pRange.Last - pRange.First + 1);
  for var I:= pRange.First to pRange.Last do Result[I - pRange.First]:= LineAt(pLines, I);
end;

function DocStart(const pLines: TArray<string>; pLine: Integer): Integer;
begin
  Result:= pLine;
  while (Result > 1) and StartsStr('///', Trim(LineAt(pLines, Result - 1))) do Dec(Result);
end;

function FindKeywordLine(const pLines: TArray<string>; const pWord: string): Integer;
begin
  for var I:= 0 to High(pLines) do
    if SameText(Trim(CodePart(pLines[I])), pWord) then Exit(I + 1);
  Result:= 0;
end;

function IsBlockWord(const pText: string): Boolean;
begin
  Result:= MatchText(Trim(CodePart(pText)), CBlockWords);
end;

/// The `type` / `var` / `const` line that opens the block holding pFirst, or 0.
function HeaderOf(const pLines: TArray<string>; pFirst: Integer): Integer;
var
  L: Integer;
begin
  L:= pFirst - 1;
  while (L >= 1) and (IsIndented(LineAt(pLines, L)) or IsCommentOnly(LineAt(pLines, L))) do Dec(L);
  if (L >= 1) and IsBlockWord(LineAt(pLines, L)) then Result:= L
  else Result:= 0;
end;

/// First line after pHeader that starts a new column-1 construct.
function BlockEnd(const pLines: TArray<string>; pHeader: Integer): Integer;
var
  L: Integer;
begin
  L:= pHeader + 1;
  while (L <= Length(pLines)) and (IsIndented(LineAt(pLines, L)) or IsCommentOnly(LineAt(pLines, L))) do Inc(L);
  Result:= L;
end;

function RangeText(const pRanges: TArray<TLineRange>): string;
var
  S: TStringBuilder;
begin
  S:= TStringBuilder.Create;
  try
    for var R in pRanges do
    begin
      if S.Length > 0 then S.Append(', ');
      if R.First = R.Last then S.Append(R.First)
      else S.Append(R.First).Append('-').Append(R.Last);
    end;
    Result:= S.ToString;
  finally
    S.Free;
  end;
end;

function OneRange(pFirst, pLast: Integer): TLineRange;
begin
  Result.First:= pFirst;
  Result.Last := pLast;
end;

function WithRange(const pFirst: TLineRange; const pRest: TArray<TLineRange>): TArray<TLineRange>;
begin
  SetLength(Result, Length(pRest) + 1);
  Result[0]:= pFirst;
  for var I:= 0 to High(pRest) do Result[I + 1]:= pRest[I];
end;

function PrependBlank(const pLines: TArray<string>): TArray<string>;
begin
  SetLength(Result, Length(pLines) + 1);
  Result[0]:= '';
  for var I:= 0 to High(pLines) do Result[I + 1]:= pLines[I];
end;

function InRanges(pLine: Integer; const pRanges: TArray<TLineRange>): Boolean;
begin
  for var R in pRanges do
    if (pLine >= R.First) and (pLine <= R.Last) then Exit(True);
  Result:= False;
end;

function QuoteList(const pNames: TArray<string>): string;
var
  Shown: TList<string>;
begin
  Shown:= TList<string>.Create;
  try
    for var I:= 0 to Min(High(pNames), CMaxNamesShown - 1) do Shown.Add('`' + pNames[I] + '`');
    Result:= string.Join(', ', Shown.ToArray);
  finally
    Shown.Free;
  end;
  if Length(pNames) > CMaxNamesShown then Result:= Result + Format(' and %d more', [Length(pNames) - CMaxNamesShown]);
end;

function AddUnique(pList: TList<string>; const pText: string): Boolean;
begin
  for var S in pList do
    if SameText(S, pText) then Exit(False);
  pList.Add(pText);
  Result:= True;
end;

function StemOfEntry(const pEntry: string): string;
var
  P: Integer;
begin
  P:= Pos(' in ', LowerCase(pEntry));
  if P > 0 then Result:= LowerCase(Trim(Copy(pEntry, 1, P - 1)))
  else Result:= LowerCase(Trim(pEntry));
end;

function SectLabel(pSect: TSect): string;
begin
  case pSect of
    scIntf: Result:= 'interface';
    scImpl: Result:= 'implementation';
  else
    Result:= 'program uses';
  end;
end;

function FormatUses(const pIndent: string; const pEntries, pComments: TArray<string>): TArray<string>;
var
  Row: string;
begin
  SetLength(Result, Length(pEntries) + 1);
  Result[0]:= pIndent + 'uses';
  for var I:= 0 to High(pEntries) do
  begin
    Row:= CEntryIndent + pIndent + pEntries[I] + (if I = High(pEntries) then ';' else ',');
    if (I <= High(pComments)) and (pComments[I] <> '') then Row:= Row + ' ' + pComments[I];
    Result[I + 1]:= Row;
  end;
end;

function SortedInts(pList: TList<Integer>): TArray<Integer>;
begin
  pList.Sort;
  Result:= pList.ToArray;
end;

/// Coarse layer of a path, to flag an inverted dependency (COMMON -> CLIENT/SERVER).
function LayerOfPath(const pPath: string): string;
begin
  if ContainsText(pPath, '\common\') then Exit('COMMON');
  if ContainsText(pPath, '\client\') then Exit('CLIENT');
  if ContainsText(pPath, '\server\') then Exit('SERVER');
  Result:= '';
end;

function SectOf(const pF: TPlanFile; pLine: Integer): TSect;
begin
  if pF.IsProgram then Exit(scProg);
  if (pF.ImplLine > 0) and (pLine >= pF.ImplLine) then Exit(scImpl);
  Result:= scIntf;
end;

{ ---------------------------------------------------------------------------
  TCyclePlanner -- construction and loading
  --------------------------------------------------------------------------- }

constructor TCyclePlanner.Create(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings);
begin
  inherited Create;
  FStore     := pStore;
  FDbPath    := pDbPath;
  FSccs      := pSccs;
  FGraph     := pGraph;
  FOut       := pOut;
  FFiles     := TDictionary<Int64, TPlanFile>.Create;
  FPaths     := TDictionary<Int64, string>.Create;
  FStemFid   := TDictionary<string, Int64>.Create;
  FUsersOf   := TObjectDictionary<string, TList<Int64>>.Create([doOwnsValues]);
  FCands     := TDictionary<string, TArray<TCandidate>>.Create;
  FSyms      := TDictionary<Int64, TSymbol>.Create;
  FNeeds     := TDictionary<Int64, TArray<TNeed>>.Create;
  FMembers   := TDictionary<string, Boolean>.Create;
  FItems     := TDictionary<Int64, TMoveItem>.Create;
  FOrder     := TList<Int64>.Create;
  FManual    := TList<TMoveItem>.Create;
  FDeleted   := TDictionary<string, Boolean>.Create;
  FReplaced  := TDictionary<string, string>.Create;
  FExtraEdits:= TObjectDictionary<Int64, TList<TFileEdit>>.Create([doOwnsValues]);
  FLeafName  := TDictionary<string, string>.Create;
  FLeafPath  := TDictionary<string, string>.Create;
  FLeafDeps  := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FConsumers := TObjectDictionary<Int64, TList<TConsumer>>.Create([doOwnsValues]);
  FDecisions := TList<TUsesDecision>.Create;
  FUsesAdd   := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FUsesDel   := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FDprojEdits:= TList<TFileEdit>.Create;
  FTouched   := TList<Int64>.Create;
  FPredicted := TList<TPredGroup>.Create;
  IndexAllFiles;
end;

destructor TCyclePlanner.Destroy;
begin
  FPredicted.Free;
  FTouched.Free;
  FDprojEdits.Free;
  FUsesDel.Free;
  FUsesAdd.Free;
  FDecisions.Free;
  FConsumers.Free;
  FLeafDeps.Free;
  FLeafPath.Free;
  FLeafName.Free;
  FExtraEdits.Free;
  FReplaced.Free;
  FDeleted.Free;
  FManual.Free;
  FOrder.Free;
  FItems.Free;
  FMembers.Free;
  FNeeds.Free;
  FSyms.Free;
  FCands.Free;
  FUsersOf.Free;
  FStemFid.Free;
  FPaths.Free;
  FFiles.Free;
  inherited Destroy;
end;

procedure TCyclePlanner.IndexAllFiles;
var
  Users: TList<Int64>;
begin
  for var Fid in FStore.GetAllFileIds do
  begin
    var Path:= PathOf(Fid);
    var Ext := LowerCase(ExtractFileExt(Path));
    if not MatchText(Ext, ['.pas', '.dpr', '.dpk']) then Continue;
    FStemFid.AddOrSetValue(StemOfPath(Path), Fid);
    if SameText(Ext, '.dpr') and (FProjectFid = 0) then FProjectFid:= Fid;
    for var U in FStore.GetUnitUsesForFile(Fid) do
    begin
      if not FUsersOf.TryGetValue(LowerCase(U.UnitName), Users) then
      begin
        Users:= TList<Int64>.Create;
        FUsersOf.Add(LowerCase(U.UnitName), Users);
      end;
      if not Users.Contains(Fid) then Users.Add(Fid);
    end;
  end;
  if FProjectFid = 0 then Exit;
  FProjectFile:= ChangeFileExt(PathOf(FProjectFid), '.dproj');
  if not TFile.Exists(FProjectFile) then FProjectFile:= PathOf(FProjectFid);
end;

function TCyclePlanner.PathOf(pFid: Int64): string;
begin
  if FPaths.TryGetValue(pFid, Result) then Exit;
  Result:= FStore.GetFilePath(pFid);
  FPaths.Add(pFid, Result);
end;

function TCyclePlanner.StemOfFid(pFid: Int64): string;
begin
  Result:= StemOfPath(PathOf(pFid));
end;

function TCyclePlanner.FidOfStem(const pStem: string): Int64;
begin
  if not FStemFid.TryGetValue(pStem, Result) then Result:= 0;
end;

function TCyclePlanner.UnitNameOfStem(const pStem: string): string;
var
  Fid: Int64;
begin
  Fid:= FidOfStem(pStem);
  if Fid > 0 then Result:= UnitNameOfPath(PathOf(Fid))
  else Result:= pStem;
end;

function TCyclePlanner.GetFile(pFid: Int64): TPlanFile;
begin
  if FFiles.TryGetValue(pFid, Result) then Exit;
  Result:= Default(TPlanFile);
  Result.Fid      := pFid;
  Result.Path     := PathOf(pFid);
  Result.UnitName := UnitNameOfPath(Result.Path);
  Result.Stem     := LowerCase(Result.UnitName);
  Result.IsProgram:= MatchText(ExtractFileExt(Result.Path), ['.dpr', '.dpk']);
  if TFile.Exists(Result.Path) then Result.Lines:= TFile.ReadAllLines(Result.Path);
  Result.IntfLine:= FindKeywordLine(Result.Lines, 'interface');
  Result.ImplLine:= FindKeywordLine(Result.Lines, 'implementation');
  Result.Syms    := FStore.FindSymbolsByFile(Result.Path);
  Result.Refs    := FStore.GetReferencesFromFile(pFid);
  Result.UsesList:= FStore.GetUnitUsesForFile(pFid);
  FFiles.Add(pFid, Result);
end;

function TCyclePlanner.GetSym(pId: Int64): TSymbol;
begin
  if FSyms.TryGetValue(pId, Result) then Exit;
  Result:= FStore.GetSymbolById(pId);
  FSyms.Add(pId, Result);
end;

function TCyclePlanner.OwnerOf(const pSym: TSymbol; out pOwner: TSymbol): Boolean;
begin
  pOwner:= pSym;
  if pSym.Kind in [skLocalVar, skParam, skUnit, skProgram, skPackage] then Exit(False);
  if pSym.Kind = skEnumValue then
  begin
    if pSym.ParentId <= 0 then Exit(False);
    pOwner:= GetSym(pSym.ParentId);
  end;
  Result:= (pOwner.ParentId > 0) and (GetSym(pOwner.ParentId).Kind in [skUnit, skProgram, skPackage]);
end;

function TCyclePlanner.CandidatesFor(const pName: string): TArray<TCandidate>;
var
  L: TList<TCandidate>;
  C: TCandidate;
begin
  if FCands.TryGetValue(LowerCase(pName), Result) then Exit;
  C:= Default(TCandidate);
  L:= TList<TCandidate>.Create;
  try
    for var S in FStore.FindSymbolsByExactName(pName) do
    begin
      if not OwnerOf(S, C.Owner) then Continue;
      C.Actual:= S;
      C.Stem  := StemOfFid(C.Owner.FileId);
      L.Add(C);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
  FCands.Add(LowerCase(pName), Result);
end;

function TCyclePlanner.VisibleStems(const pF: TPlanFile; pSect: TSect): TArray<string>;
var
  L   : TList<string>;
  Take: Boolean;
begin
  L:= TList<string>.Create;
  try
    for var U in pF.UsesList do
    begin
      case U.Section of
        uusInterface     : Take:= pSect in [scIntf, scImpl];
        uusImplementation: Take:= pSect = scImpl;
      else
        Take:= pSect = scProg;
      end;
      if Take then L.Add(LowerCase(U.UnitName));
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.PickCandidate(const pF: TPlanFile; pSect: TSect; const pCands: TArray<TCandidate>): Integer;
var
  Vis    : TArray<string>;
  BestPos: Integer;
begin
  for var I:= 0 to High(pCands) do
    if pCands[I].Owner.FileId = pF.Fid then Exit(I);   { own declaration wins }
  Result := CNotFound;
  BestPos:= CNotFound;
  Vis    := VisibleStems(pF, pSect);
  for var I:= 0 to High(pCands) do
  begin
    if SameText(pCands[I].Owner.Section, 'implementation') then Continue;
    for var P:= 0 to High(Vis) do
      if (Vis[P] = pCands[I].Stem) and (P > BestPos) then
      begin
        BestPos:= P;   { Delphi: the LAST unit in the uses list wins }
        Result := I;
      end;
  end;
end;

function TCyclePlanner.IsLocalName(const pR: TReference): Boolean;
var
  Local: TSymbol;
begin
  if pR.EnclosingSymbolId <= 0 then Exit(False);
  Local:= FStore.FindChildSymbolByName(pR.EnclosingSymbolId, pR.NameText);
  Result:= (Local.Id > 0) and (Local.Kind in [skLocalVar, skParam]);
end;

function TCyclePlanner.Resolve(const pF: TPlanFile; const pR: TReference; out pNeed: TNeed): Boolean;
var
  Cands: TArray<TCandidate>;
  Best : Integer;
begin
  pNeed:= Default(TNeed);
  if (pR.ReceiverText <> '') or SameText(pR.Kind, 'member-access') then Exit(False);
  Cands:= CandidatesFor(pR.NameText);
  if Length(Cands) = 0 then Exit(False);
  Best:= PickCandidate(pF, SectOf(pF, pR.StartLine), Cands);
  if (Best = CNotFound) or IsLocalName(pR) then Exit(False);
  pNeed.Owner    := Cands[Best].Owner;
  pNeed.OwnerStem:= Cands[Best].Stem;
  pNeed.Sect     := SectOf(pF, pR.StartLine);
  pNeed.Line     := pR.StartLine;
  pNeed.RefName  := pR.NameText;
  pNeed.RefKind  := Cands[Best].Actual.Kind;
  Result:= True;
end;

function TCyclePlanner.NeedsOf(pFid: Int64): TArray<TNeed>;
var
  F: TPlanFile;
  L: TList<TNeed>;
  N: TNeed;
begin
  if FNeeds.TryGetValue(pFid, Result) then Exit;
  F:= GetFile(pFid);
  L:= TList<TNeed>.Create;
  try
    for var R in F.Refs do
      if Resolve(F, R, N) then L.Add(N);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
  FNeeds.Add(pFid, Result);
end;

{ ---------------------------------------------------------------------------
  closure: which declarations move, and how
  --------------------------------------------------------------------------- }

procedure TCyclePlanner.ResetCycle(const pComp: TArray<string>);
begin
  FComp:= pComp;
  FMembers.Clear;
  for var S in pComp do FMembers.AddOrSetValue(S, True);
  FItems.Clear;
  FOrder.Clear;
  FManual.Clear;
  FDeleted.Clear;
  FReplaced.Clear;
  FExtraEdits.Clear;
  FLeafName.Clear;
  FLeafPath.Clear;
  FLeafDeps.Clear;
  FConsumers.Clear;
  FDecisions.Clear;
  FUsesAdd.Clear;
  FUsesDel.Clear;
  FDprojEdits.Clear;
  FTouched.Clear;
  FPredicted.Clear;
  FCutEdge:= Default(TEdgeEval);
end;

function TCyclePlanner.BodyRanges(const pSym: TSymbol): TArray<TLineRange>;
var
  L: TList<TLineRange>;
begin
  L:= TList<TLineRange>.Create;
  try
    for var C in FStore.FindAllChildSymbols(pSym.Id) do
      if (C.ImplStartLine > 0) and (C.ImplEndLine >= C.ImplStartLine) then L.Add(OneRange(C.ImplStartLine, C.ImplEndLine));
    L.Sort(TComparer<TLineRange>.Construct(
      function(const pLeft, pRight: TLineRange): Integer
      begin
        Result:= pLeft.First - pRight.First;
      end));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.IsDeclOnly(const pSym: TSymbol): Boolean;
begin
  if pSym.Kind in [skEnum, skTypeAlias, skInterface, skConstDecl] then Exit(True);
  Result:= (pSym.Kind in [skRecord, skClass]) and (Length(BodyRanges(pSym)) = 0);
end;

function TCyclePlanner.NeedsInRanges(const pF: TPlanFile; const pRanges: TArray<TLineRange>): TArray<TNeed>;
var
  L: TList<TNeed>;
begin
  L:= TList<TNeed>.Create;
  try
    for var N in NeedsOf(pF.Fid) do
      if InRanges(N.Line, pRanges) then L.Add(N);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.MovedRanges(const pItem: TMoveItem): TArray<TLineRange>;
begin
  if pItem.Kind = mvBase then
  begin
    SetLength(Result, Length(pItem.BaseMembers));
    for var I:= 0 to High(pItem.BaseMembers) do Result[I]:= pItem.BaseMembers[I].Range;
  end
  else if pItem.Kind = mvWithBodies then Result:= WithRange(pItem.Decl, pItem.Bodies)
  else Result:= WithRange(pItem.Decl, nil);
end;

procedure TCyclePlanner.SetHeader(const pF: TPlanFile; var pItem: TMoveItem);
begin
  pItem.Header:= HeaderOf(pF.Lines, pItem.Decl.First);
  if pItem.Header = 0 then
  begin
    pItem.Kind  := mvBlocked;
    pItem.Reason:= Format('the declaration block around line %d was not recognised (expected a ' +
      '`type` / `var` / `const` line at column 1 above it)', [pItem.Decl.First]);
    Exit;
  end;
  pItem.Keyword:= LowerCase(Trim(CodePart(LineAt(pF.Lines, pItem.Header))));
end;

function TCyclePlanner.Classify(const pSym: TSymbol; const pCut: TArray<Int64>): TMoveItem;
var
  F: TPlanFile;
begin
  Result:= Default(TMoveItem);
  Result.Sym    := pSym;
  Result.Stem   := StemOfFid(pSym.FileId);
  Result.CutFids:= pCut;
  F:= GetFile(pSym.FileId);
  Result.Decl:= OneRange(DocStart(F.Lines, pSym.StartLine), pSym.EndLine);
  case pSym.Kind of
    skEnum, skTypeAlias, skInterface, skConstDecl, skVarDecl: Result.Kind:= mvDecl;
    skRecord, skClass: ClassifyStructured(F, Result);
    skProcedure, skFunction:
      begin
        Result.Kind  := mvBlocked;
        Result.Reason:= 'it is a routine: its body would have to move together with everything it ' +
          'uses, or be handed over as a parameter / event instead of being called by name';
      end;
  else
    Result.Kind  := mvBlocked;
    Result.Reason:= Format('a %s cannot be moved mechanically', [pSym.Kind.ToText]);
  end;
  if Result.Kind in [mvDecl, mvWithBodies] then SetHeader(F, Result);
end;

procedure TCyclePlanner.ClassifyStructured(const pF: TPlanFile; var pItem: TMoveItem);
var
  Drags: TList<string>;
begin
  pItem.Bodies:= BodyRanges(pItem.Sym);
  if Length(pItem.Bodies) = 0 then
  begin
    pItem.Kind:= mvDecl;
    Exit;
  end;
  Drags:= TList<string>.Create;
  try
    { a body DRAGS a symbol of the cycle that is not a plain declaration --
      a global variable, a routine, a class with code -- because moving the
      body would mean moving that too }
    for var N in NeedsInRanges(pF, WithRange(pItem.Decl, pItem.Bodies)) do
    begin
      if (N.Owner.Id = pItem.Sym.Id) or not FMembers.ContainsKey(N.OwnerStem) then Continue;
      if IsMovedFor(N.Owner, 0) or IsDeclOnly(N.Owner) then Continue;
      AddUnique(Drags, N.Owner.Name);
    end;
    pItem.Drags:= Drags.ToArray;
  finally
    Drags.Free;
  end;
  if Length(pItem.Drags) = 0 then pItem.Kind:= mvWithBodies
  else if (pItem.Sym.Kind = skClass) and (Length(pItem.CutFids) > 0) then BuildBase(pF, pItem)
  else
  begin
    pItem.Kind  := mvBlocked;
    pItem.Reason:= Format('its method bodies use %s, which live in units of this cycle -- they ' +
      'would have to move with it', [QuoteList(pItem.Drags)]);
  end;
end;

procedure TCyclePlanner.BuildBase(const pF: TPlanFile; var pItem: TMoveItem);
var
  M       : TMatch;
  Children: TArray<TSymbol>;
  Used    : TDictionary<string, Boolean>;
  Comment : string;
begin
  pItem.Kind:= mvBlocked;
  if (pItem.Sym.Heritage <> '') or pItem.Sym.IsHelper or (pItem.Sym.GenericParams <> '') then
  begin
    pItem.Reason:= 'it inherits, is generic or is a helper, so a base class cannot be slotted in ' +
      'mechanically';
    Exit;
  end;
  M:= TRegEx.Match(LineAt(pF.Lines, pItem.Sym.StartLine),
    '^(\s*)' + pItem.Sym.Name + '\s*=\s*class\s*(//.*)?$', [roIgnoreCase]);
  if not M.Success then
  begin
    pItem.Reason:= Format('its header (line %d) is not a plain `%s = class` line',
      [pItem.Sym.StartLine, pItem.Sym.Name]);
    Exit;
  end;
  pItem.BaseName  := pItem.Sym.Name + CBaseSuffix;
  pItem.BaseIndent:= M.Groups[1].Value;
  Comment:= '';
  if M.Groups.Count > 2 then Comment:= M.Groups[2].Value;
  pItem.HeaderNew:= pItem.BaseIndent + pItem.Sym.Name + ' = class(' + pItem.BaseName + ')' +
    (if Comment <> '' then ' ' + Comment else '');
  Children:= FStore.FindAllChildSymbols(pItem.Sym.Id);
  Used:= UsedMemberNames(Children, pItem.CutFids);
  try
    if not PullMembers(pF, pItem, Children, Used) then Exit;
  finally
    Used.Free;
  end;
  if BuildSwitches(pItem) then pItem.Kind:= mvBase;
end;

function TCyclePlanner.UsedMemberNames(const pChildren: TArray<TSymbol>; const pCut: TArray<Int64>): TDictionary<string, Boolean>;
var
  Ids  : TDictionary<Int64, Boolean>;
  Names: TDictionary<string, Boolean>;
begin
  Result:= TDictionary<string, Boolean>.Create;
  Ids   := TDictionary<Int64, Boolean>.Create;
  Names := TDictionary<string, Boolean>.Create;
  try
    for var C in pChildren do
    begin
      if C.Kind in [skConstructor, skDestructor] then Continue;
      Ids.AddOrSetValue(C.Id, True);
      Names.AddOrSetValue(LowerCase(C.Name), True);
    end;
    for var Fid in pCut do
      for var R in GetFile(Fid).Refs do
      begin
        if (R.ReceiverText = '') and not SameText(R.Kind, 'member-access') then Continue;
        if (R.SymbolId > 0) and not Ids.ContainsKey(R.SymbolId) then Continue;
        if Names.ContainsKey(LowerCase(R.NameText)) then Result.AddOrSetValue(LowerCase(R.NameText), True);
      end;
  finally
    Names.Free;
    Ids.Free;
  end;
end;

function TCyclePlanner.PullMembers(const pF: TPlanFile; var pItem: TMoveItem;
  const pChildren: TArray<TSymbol>; pUsed: TDictionary<string, Boolean>): Boolean;
var
  L     : TList<TBaseMember>;
  Pulled: TDictionary<Int64, Boolean>;
  Why   : string;

  procedure Pull(const pSym: TSymbol);
  var
    B: TBaseMember;
  begin
    if Pulled.ContainsKey(pSym.Id) then Exit;
    Pulled.Add(pSym.Id, True);
    B.Sym  := pSym;
    B.Range:= OneRange(DocStart(pF.Lines, pSym.StartLine), pSym.EndLine);
    L.Add(B);
  end;

  function FieldNamed(const pName: string; out pField: TSymbol): Boolean;
  begin
    for var C in pChildren do
      if SameText(C.Name, pName) then
      begin
        pField:= C;
        Exit(C.Kind = skField);
      end;
    pField:= Default(TSymbol);
    Result:= False;
  end;

  function PullAccessors(const pProp: TSymbol): Boolean;
  var
    Fld: TSymbol;
  begin
    var Text:= string.Join(' ', SliceLines(pF.Lines, OneRange(pProp.StartLine, pProp.EndLine)));
    for var M in TRegEx.Matches(CodePart(Text), '\b(read|write)\s+([A-Za-z_]\w*)', [roIgnoreCase]) do
    begin
      if not FieldNamed(M.Groups[2].Value, Fld) then
      begin
        Why:= Format('property `%s` is read or written through `%s`, which is not a field',
          [pProp.Name, M.Groups[2].Value]);
        Exit(False);
      end;
      Pull(Fld);
    end;
    Result:= True;
  end;

begin
  Result:= False;
  Why   := '';
  L     := TList<TBaseMember>.Create;
  Pulled:= TDictionary<Int64, Boolean>.Create;
  try
    for var C in pChildren do
    begin
      if not pUsed.ContainsKey(LowerCase(C.Name)) then Continue;
      if (C.Kind = skProperty) and not PullAccessors(C) then Break;
      if (C.Kind in [skMethod, skFunction, skProcedure]) and (C.Directives <> '') then
      begin
        Why:= Format('method `%s` already carries directives (%s)', [C.Name, C.Directives]);
        Break;
      end;
      if C.Kind in [skField, skProperty, skMethod, skFunction, skProcedure] then Pull(C);
    end;
    if Why <> '' then
    begin
      pItem.Reason:= Why;
      Exit;
    end;
    L.Sort(TComparer<TBaseMember>.Construct(
      function(const pLeft, pRight: TBaseMember): Integer
      begin
        Result:= pLeft.Range.First - pRight.Range.First;
      end));
    pItem.BaseMembers:= L.ToArray;
    Result:= True;
  finally
    Pulled.Free;
    L.Free;
  end;
end;

function TCyclePlanner.BuildSwitches(var pItem: TMoveItem): Boolean;
var
  L : TList<TSwitchLine>;
  SL: TSwitchLine;
begin
  Result:= False;
  L:= TList<TSwitchLine>.Create;
  try
    for var Fid in pItem.CutFids do
    begin
      var F:= GetFile(Fid);
      for var I:= 1 to Length(F.Lines) do
      begin
        var Line:= F.Lines[I - 1];
        if IsCommentOnly(Line) then Continue;
        var Code:= CodePart(Line);
        if not TRegEx.IsMatch(Code, '\b' + pItem.Sym.Name + '\b', [roIgnoreCase]) then Continue;
        if TRegEx.IsMatch(Code, '\b' + pItem.Sym.Name + '\s*\.', [roIgnoreCase]) then
        begin
          pItem.Reason:= Format('`%s` line %d uses `%s.` (the class itself, not an instance)',
            [ExtractFileName(F.Path), I, pItem.Sym.Name]);
          Exit;
        end;
        SL.Fid    := Fid;
        SL.Line   := I;
        SL.NewText:= TRegEx.Replace(Code, '\b' + pItem.Sym.Name + '\b', pItem.BaseName, [roIgnoreCase]) +
          Copy(Line, Length(Code) + 1, MaxInt);
        L.Add(SL);
      end;
    end;
    pItem.Switches:= L.ToArray;
    Result:= True;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.TryAdd(const pSym: TSymbol; const pCut: TArray<Int64>; out pWhy: string): Boolean;
var
  Item: TMoveItem;
begin
  pWhy:= '';
  if FItems.TryGetValue(pSym.Id, Item) then
  begin
    { a class that only got a base class extracted has NOT moved }
    if Item.Kind <> mvBase then Exit(True);
    pWhy:= Format('`%s` itself stays in its unit -- only its base class moves', [pSym.Name]);
    Exit(False);
  end;
  if not FMembers.ContainsKey(StemOfFid(pSym.FileId)) then Exit(True);
  Item:= Classify(pSym, pCut);
  if Item.Kind = mvBlocked then
  begin
    pWhy:= Item.Reason;
    Exit(False);
  end;
  FItems.Add(pSym.Id, Item);
  FOrder.Add(pSym.Id);
  Result:= AddDependencies(Item, pWhy) and AddCompanions(Item, pWhy);
end;

function TCyclePlanner.AddDependencies(const pItem: TMoveItem; out pWhy: string): Boolean;
var
  Why: string;
begin
  pWhy:= '';
  for var N in NeedsInRanges(GetFile(pItem.Sym.FileId), MovedRanges(pItem)) do
  begin
    if (N.Owner.Id = pItem.Sym.Id) or not FMembers.ContainsKey(N.OwnerStem) then Continue;
    if not TryAdd(N.Owner, nil, Why) then
    begin
      pWhy:= Format('it needs `%s` (%s), which cannot move: %s', [N.Owner.Name, N.Owner.Kind.ToText, Why]);
      Exit(False);
    end;
  end;
  Result:= True;
end;

function TCyclePlanner.AddCompanions(const pItem: TMoveItem; out pWhy: string): Boolean;
var
  Owner: TSymbol;
  Why  : string;
begin
  pWhy:= '';
  if pItem.Kind = mvBase then Exit(True);
  { every other unit-level declaration on the moved lines moves too }
  for var S in GetFile(pItem.Sym.FileId).Syms do
  begin
    if (S.Id = pItem.Sym.Id) or not InRanges(S.StartLine, WithRange(pItem.Decl, nil)) then Continue;
    if (S.Kind = skEnumValue) or not OwnerOf(S, Owner) or (Owner.Id <> S.Id) then Continue;
    if not TryAdd(S, nil, Why) then
    begin
      pWhy:= Format('`%s` is declared on the same lines and cannot move: %s', [S.Name, Why]);
      Exit(False);
    end;
  end;
  Result:= True;
end;

procedure TCyclePlanner.Rollback(pSnap: Integer);
begin
  while FOrder.Count > pSnap do
  begin
    FItems.Remove(FOrder.Last);
    FOrder.Delete(FOrder.Count - 1);
  end;
end;

function TCyclePlanner.IsMovedFor(const pOwner: TSymbol; pFid: Int64): Boolean;
var
  Item: TMoveItem;
begin
  if not FItems.TryGetValue(pOwner.Id, Item) then Exit(False);
  if Item.Kind in [mvDecl, mvWithBodies] then Exit(True);
  for var Fid in Item.CutFids do
    if Fid = pFid then Exit(True);
  Result:= False;
end;

{ ---------------------------------------------------------------------------
  materialise: leaf names, line edits, consumers, uses decisions
  --------------------------------------------------------------------------- }

procedure TCyclePlanner.Materialize;
begin
  AssignLeafNames;
  MarkItemLines;
  DeleteEmptyHeaders;
  CollectConsumers;
  CollectLeafDeps;
  DecideUses;
  RegisterLeaves;
  BuildUsesEdits;
  Predict;
end;

procedure TCyclePlanner.AssignLeafNames;
begin
  for var Id in FOrder do
  begin
    var Stem:= FItems[Id].Stem;
    if FLeafName.ContainsKey(Stem) then Continue;
    var F:= GetFile(FidOfStem(Stem));
    var Name:= F.UnitName + CLeafSuffix;
    var N:= 1;
    while TFile.Exists(ExtractFilePath(F.Path) + Name + '.pas') do
    begin
      Inc(N);
      Name:= F.UnitName + CLeafSuffix + IntToStr(N);
    end;
    FLeafName.Add(Stem, Name);
    FLeafPath.Add(Stem, ExtractFilePath(F.Path) + Name + '.pas');
  end;
end;

function TCyclePlanner.LeafStems: TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var Id in FOrder do
      if FLeafName.ContainsKey(FItems[Id].Stem) then AddUnique(L, FItems[Id].Stem);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCyclePlanner.Touch(pFid: Int64);
begin
  if not FTouched.Contains(pFid) then FTouched.Add(pFid);
end;

procedure TCyclePlanner.MarkDeleted(pFid: Int64; const pRange: TLineRange);
begin
  Touch(pFid);
  for var I:= pRange.First to pRange.Last do FDeleted.AddOrSetValue(LineKey(pFid, I), True);
end;

function TCyclePlanner.IsDeleted(pFid: Int64; pLine: Integer): Boolean;
begin
  Result:= FDeleted.ContainsKey(LineKey(pFid, pLine));
end;

procedure TCyclePlanner.MarkReplaced(pFid: Int64; pLine: Integer; const pText: string);
begin
  Touch(pFid);
  FReplaced.AddOrSetValue(LineKey(pFid, pLine), pText);
end;

procedure TCyclePlanner.MarkItemLines;
begin
  for var Id in FOrder do
  begin
    var Item:= FItems[Id];
    var Fid := Item.Sym.FileId;
    if Item.Kind <> mvBase then
    begin
      for var R in MovedRanges(Item) do MarkDeleted(Fid, R);
      Continue;
    end;
    var F:= GetFile(Fid);
    MarkReplaced(Fid, Item.Sym.StartLine, Item.HeaderNew);
    for var M in Item.BaseMembers do
      if M.Sym.Kind in [skMethod, skFunction, skProcedure] then
      begin
        var Last:= LineAt(F.Lines, M.Sym.EndLine);
        var Code:= CodePart(Last);
        MarkReplaced(Fid, M.Sym.EndLine, TrimRight(Code) + COverrideTail + Copy(Last, Length(Code) + 1, MaxInt));
      end
      else MarkDeleted(Fid, M.Range);
    for var S in Item.Switches do MarkReplaced(S.Fid, S.Line, S.NewText);
  end;
end;

procedure TCyclePlanner.DeleteEmptyHeaders;
begin
  { a `type` / `var` block whose every declaration moved loses its keyword too }
  for var Id in FOrder do
  begin
    var Item:= FItems[Id];
    if Item.Kind = mvBase then Continue;
    var F    := GetFile(Item.Sym.FileId);
    var Empty:= True;
    for var L:= Item.Header + 1 to BlockEnd(F.Lines, Item.Header) - 1 do
      if not (IsDeleted(F.Fid, L) or IsCommentOnly(LineAt(F.Lines, L))) then Empty:= False;
    if Empty then MarkDeleted(F.Fid, OneRange(Item.Header, Item.Header));
  end;
end;

procedure TCyclePlanner.AddConsumer(const pItem: TMoveItem; pFid: Int64; pSect: TSect; pLine: Integer);
var
  L: TList<TConsumer>;
  C: TConsumer;
begin
  if not FConsumers.TryGetValue(pItem.Sym.Id, L) then
  begin
    L:= TList<TConsumer>.Create;
    FConsumers.Add(pItem.Sym.Id, L);
  end;
  for var I:= 0 to L.Count - 1 do
    if (L[I].Fid = pFid) and (L[I].Sect = pSect) then
    begin
      C:= L[I];
      if pLine < C.Line then C.Line:= pLine;
      L[I]:= C;
      Exit;
    end;
  C.Fid := pFid;
  C.Sect:= pSect;
  C.Line:= pLine;
  L.Add(C);
  AddUses(pFid, pSect, UsesEntryFor(GetFile(pFid), pItem.Stem));
end;

procedure TCyclePlanner.CollectConsumers;
var
  Users: TList<Int64>;
  Files: TList<Int64>;
begin
  Files:= TList<Int64>.Create;
  try
    for var Id in FOrder do
    begin
      var Item:= FItems[Id];
      if Item.Kind = mvBase then
      begin
        AddConsumer(Item, Item.Sym.FileId, scIntf, Item.Sym.StartLine);
        for var S in Item.Switches do AddConsumer(Item, S.Fid, SectOf(GetFile(S.Fid), S.Line), S.Line);
        Continue;
      end;
      Files.Clear;
      Files.Add(Item.Sym.FileId);
      if FUsersOf.TryGetValue(Item.Stem, Users) then
        for var U in Users do
          if not Files.Contains(U) then Files.Add(U);
      for var Fid in Files do
        for var N in NeedsOf(Fid) do
          if (N.Owner.Id = Item.Sym.Id) and not IsDeleted(Fid, N.Line) then AddConsumer(Item, Fid, N.Sect, N.Line);
    end;
  finally
    Files.Free;
  end;
end;

procedure TCyclePlanner.CollectLeafDeps;
var
  Deps : TList<string>;
  Other: TMoveItem;
begin
  for var Id in FOrder do
  begin
    var Item:= FItems[Id];
    if not FLeafDeps.TryGetValue(Item.Stem, Deps) then
    begin
      Deps:= TList<string>.Create;
      FLeafDeps.Add(Item.Stem, Deps);
    end;
    for var N in NeedsInRanges(GetFile(Item.Sym.FileId), MovedRanges(Item)) do
    begin
      if N.OwnerStem = Item.Stem then Continue;
      if FItems.TryGetValue(N.Owner.Id, Other) then AddUnique(Deps, FLeafName[Other.Stem])
      else if not FMembers.ContainsKey(N.OwnerStem) then AddUnique(Deps, UnitNameOfStem(N.OwnerStem));
    end;
  end;
end;

procedure TCyclePlanner.DecideUses;
begin
  for var Stem in FComp do
  begin
    var F:= GetFile(FidOfStem(Stem));
    for var U in F.UsesList do
    begin
      var B:= LowerCase(U.UnitName);
      if (B = Stem) or not FMembers.ContainsKey(B) or not FLeafName.ContainsKey(B) then Continue;
      if U.Section in [uusInterface, uusImplementation] then DecideOne(F, U);
    end;
  end;
end;

procedure TCyclePlanner.DecideOne(const pA: TPlanFile; const pU: TUnitUse);
var
  D      : TUsesDecision;
  Had    : array [Boolean] of Boolean;
  Still  : array [Boolean] of TList<string>;
  InImpl : Boolean;
  Partner: string;
begin
  Partner    := LowerCase(pU.UnitName);
  InImpl     := pU.Section = uusImplementation;
  Had[False] := False;
  Had[True]  := False;
  Still[False]:= TList<string>.Create;
  Still[True] := TList<string>.Create;
  try
    for var N in NeedsOf(pA.Fid) do
    begin
      if (N.OwnerStem <> Partner) or IsDeleted(pA.Fid, N.Line) then Continue;
      Had[N.Sect = scImpl]:= True;
      if IsMovedFor(N.Owner, pA.Fid) then Continue;
      var Shown:= False;
      for var S in Still[N.Sect = scImpl] do
        if StartsText('`' + N.RefName + '`', S) then Shown:= True;
      if not Shown then Still[N.Sect = scImpl].Add(Format('`%s` line %d', [N.RefName, N.Line]));
    end;
    D.Fid        := pA.Fid;
    D.PartnerStem:= Partner;
    D.Sect       := if InImpl then scImpl else scIntf;
    if not Had[InImpl] then D.Verdict:= uvKeepUnseen
    else if Still[InImpl].Count > 0 then D.Verdict:= uvKeep
    else if (not InImpl) and (Still[True].Count > 0) then D.Verdict:= uvMove
    else D.Verdict:= uvRemove;
    D.Still:= string.Join(', ', Still[InImpl or (D.Verdict = uvMove)].ToArray);
  finally
    Still[True].Free;
    Still[False].Free;
  end;
  FDecisions.Add(D);
  if D.Verdict in [uvMove, uvRemove] then DelUses(pA.Fid, D.Sect, Partner);
  if D.Verdict = uvMove then AddUses(pA.Fid, scImpl, EntryText(pA, pU));
end;

procedure TCyclePlanner.RegisterLeaves;
var
  Dproj: TArray<string>;
  E    : TFileEdit;
begin
  if FProjectFid = 0 then Exit;
  var Prj:= GetFile(FProjectFid);
  for var Stem in LeafStems do AddUses(FProjectFid, scProg, UsesEntryFor(Prj, Stem));
  if not (SameText(ExtractFileExt(FProjectFile), '.dproj') and TFile.Exists(FProjectFile)) then Exit;
  Dproj:= TFile.ReadAllLines(FProjectFile);
  for var U in Prj.UsesList do
  begin
    var Stem:= LowerCase(U.UnitName);
    if (U.InPath = '') or not FLeafName.ContainsKey(Stem) then Continue;
    for var I:= 0 to High(Dproj) do
      if ContainsText(Dproj[I], 'Include="' + U.InPath + '"') then
      begin
        E:= Default(TFileEdit);
        E.Kind    := ekInsertAfter;
        E.First   := I + 1;
        E.Last    := I + 1;
        E.NewLines:= [StringReplace(Dproj[I], U.InPath, ExtractFilePath(U.InPath) + FLeafName[Stem] + '.pas', [rfIgnoreCase])];
        FDprojEdits.Add(E);
        Break;
      end;
  end;
end;

function TCyclePlanner.ListOf(pDict: TObjectDictionary<string, TList<string>>; pFid: Int64; pSect: TSect): TList<string>;
begin
  if not pDict.TryGetValue(SectKey(pFid, pSect), Result) then
  begin
    Result:= TList<string>.Create;
    pDict.Add(SectKey(pFid, pSect), Result);
  end;
end;

procedure TCyclePlanner.AddUses(pFid: Int64; pSect: TSect; const pEntry: string);
begin
  Touch(pFid);
  AddUnique(ListOf(FUsesAdd, pFid, pSect), pEntry);
end;

procedure TCyclePlanner.DelUses(pFid: Int64; pSect: TSect; const pStem: string);
begin
  Touch(pFid);
  AddUnique(ListOf(FUsesDel, pFid, pSect), pStem);
end;

function TCyclePlanner.EntryText(const pF: TPlanFile; const pU: TUnitUse): string;
var
  S: TStringBuilder;
begin
  if pU.StartLine = pU.EndLine then
    Exit(Copy(LineAt(pF.Lines, pU.StartLine), pU.StartCol, pU.EndCol - pU.StartCol));
  S:= TStringBuilder.Create;
  try
    S.Append(Copy(LineAt(pF.Lines, pU.StartLine), pU.StartCol, MaxInt));
    for var I:= pU.StartLine + 1 to pU.EndLine - 1 do S.Append(' ').Append(Trim(LineAt(pF.Lines, I)));
    S.Append(' ').Append(TrimLeft(Copy(LineAt(pF.Lines, pU.EndLine), 1, pU.EndCol - 1)));
    Result:= S.ToString;
  finally
    S.Free;
  end;
end;

function TCyclePlanner.EntryComment(const pF: TPlanFile; const pU: TUnitUse): string;
var
  Rest: string;
begin
  Rest:= Trim(Copy(LineAt(pF.Lines, pU.EndLine), pU.EndCol, MaxInt));
  if StartsStr(',', Rest) or StartsStr(';', Rest) then Rest:= Trim(Copy(Rest, 2, MaxInt));
  if StartsStr('//', Rest) or StartsStr('{', Rest) then Result:= Rest
  else Result:= '';
end;

function TCyclePlanner.UsesEntryFor(const pF: TPlanFile; const pLeafStem: string): string;
begin
  Result:= FLeafName[pLeafStem];
  if not pF.IsProgram then Exit;
  for var U in pF.UsesList do
    if (LowerCase(U.UnitName) = pLeafStem) and (U.InPath <> '') then
      Exit(Format('%s in ''%s''', [Result, ExtractFilePath(U.InPath) + Result + '.pas']));
end;

function TCyclePlanner.SectionEntries(const pF: TPlanFile; pSect: TSect): TArray<TUnitUse>;
var
  L: TList<TUnitUse>;
begin
  L:= TList<TUnitUse>.Create;
  try
    for var U in pF.UsesList do
      case pSect of
        scIntf: if U.Section = uusInterface then L.Add(U);
        scImpl: if U.Section = uusImplementation then L.Add(U);
      else
        if U.Section in [uusProgram, uusPackage] then L.Add(U);
      end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCyclePlanner.DedupeAdds;
var
  Impl: TList<string>;
  Seen: TList<string>;
begin
  { a unit the interface section already sees must not be named again in the
    implementation uses -- that is E2004 "Identifier redeclared" }
  Seen:= TList<string>.Create;
  try
    for var Fid in FTouched.ToArray do
    begin
      if not FUsesAdd.TryGetValue(SectKey(Fid, scImpl), Impl) then Continue;
      Seen.Clear;
      for var U in SectionEntries(GetFile(Fid), scIntf) do
        if not ListOf(FUsesDel, Fid, scIntf).Contains(LowerCase(U.UnitName)) then Seen.Add(LowerCase(U.UnitName));
      for var S in ListOf(FUsesAdd, Fid, scIntf) do Seen.Add(StemOfEntry(S));
      for var I:= Impl.Count - 1 downto 0 do
        if Seen.Contains(StemOfEntry(Impl[I])) then Impl.Delete(I);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TCyclePlanner.BuildUsesEdits;
begin
  DedupeAdds;
  for var Fid in FTouched.ToArray do
    for var Sect:= Low(TSect) to High(TSect) do
      if (ListOf(FUsesAdd, Fid, Sect).Count > 0) or (ListOf(FUsesDel, Fid, Sect).Count > 0) then
        BuildClauseEdit(GetFile(Fid), Sect);
end;

procedure TCyclePlanner.BuildClauseEdit(const pF: TPlanFile; pSect: TSect);
var
  Entries : TArray<TUnitUse>;
  Adds    : TList<string>;
  Dels    : TList<string>;
  Kept    : TList<string>;
  Notes   : TList<string>;
  Stems   : TList<string>;
  E       : TFileEdit;
  UsesLine: Integer;
  Clean   : Boolean;
begin
  Entries:= SectionEntries(pF, pSect);
  Adds   := ListOf(FUsesAdd, pF.Fid, pSect);
  Dels   := ListOf(FUsesDel, pF.Fid, pSect);
  E      := Default(TFileEdit);
  if Length(Entries) = 0 then
  begin
    if Adds.Count = 0 then Exit;
    E.Kind := ekInsertAfter;
    E.First:= if pSect = scIntf then pF.IntfLine else pF.ImplLine;
    E.Last := E.First;
    if (pSect = scProg) or (E.First = 0) then
    begin
      E.Kind:= ekManual;
      E.Note:= Format('Add a `uses` clause naming %s to the %s section.', [QuoteList(Adds.ToArray), SectLabel(pSect)]);
    end
    else E.NewLines:= PrependBlank(FormatUses('', Adds.ToArray, nil));
    EditList(pF.Fid).Add(E);
    Exit;
  end;
  { the clause runs from the `uses` keyword to the last entry; a clause that
    holds anything else (a directive, a comment line) gets a manual edit }
  UsesLine:= Entries[0].StartLine;
  while (UsesLine > 1) and not TRegEx.IsMatch(CodePart(LineAt(pF.Lines, UsesLine)), '\buses\b', [roIgnoreCase]) do
    Dec(UsesLine);
  E.First:= UsesLine;
  E.Last := Entries[High(Entries)].EndLine;
  Clean  := SameText(Trim(CodePart(LineAt(pF.Lines, UsesLine))), 'uses');
  for var L:= UsesLine + 1 to E.Last do
  begin
    var Covered:= Trim(LineAt(pF.Lines, L)) = '';
    for var U in Entries do
      if (L >= U.StartLine) and (L <= U.EndLine) then Covered:= True;
    Clean:= Clean and Covered;
  end;
  Kept := TList<string>.Create;
  Notes:= TList<string>.Create;
  Stems:= TList<string>.Create;
  try
    for var U in Entries do
      if not Dels.Contains(LowerCase(U.UnitName)) then
      begin
        Kept.Add(EntryText(pF, U));
        Notes.Add(EntryComment(pF, U));
        Stems.Add(LowerCase(U.UnitName));
      end;
    for var S in Adds do
      if not Stems.Contains(StemOfEntry(S)) then
      begin
        Kept.Add(S);
        Notes.Add('');
        Stems.Add(StemOfEntry(S));
      end;
    if not Clean then
    begin
      E.Kind:= ekManual;
      E.Note:= Format('In the %s uses clause (lines %d-%d): remove %s; add %s. Keep the commas and ' +
        'the final semicolon correct.', [SectLabel(pSect), E.First, E.Last,
        (if Dels.Count > 0 then QuoteList(Dels.ToArray) else 'nothing'), (if Adds.Count > 0 then QuoteList(Adds.ToArray) else 'nothing')]);
    end
    else if Kept.Count = 0 then E.Kind:= ekDelete
    else
    begin
      E.Kind    := ekReplace;
      E.NewLines:= FormatUses(TRegEx.Match(LineAt(pF.Lines, UsesLine), '^\s*').Value, Kept.ToArray, Notes.ToArray);
    end;
  finally
    Stems.Free;
    Notes.Free;
    Kept.Free;
  end;
  EditList(pF.Fid).Add(E);
end;

function TCyclePlanner.EditList(pFid: Int64): TList<TFileEdit>;
begin
  Touch(pFid);
  if not FExtraEdits.TryGetValue(pFid, Result) then
  begin
    Result:= TList<TFileEdit>.Create;
    FExtraEdits.Add(pFid, Result);
  end;
end;

function TCyclePlanner.EditsOf(pFid: Int64): TArray<TFileEdit>;
var
  L   : TList<TFileEdit>;
  Dels: TList<Integer>;
  E   : TFileEdit;
  F   : TPlanFile;
  I   : Integer;
  J   : Integer;
begin
  F   := GetFile(pFid);
  L   := TList<TFileEdit>.Create;
  Dels:= TList<Integer>.Create;
  try
    for var K:= 1 to Length(F.Lines) do
      if IsDeleted(pFid, K) then Dels.Add(K);
    var Sorted:= SortedInts(Dels);
    I:= 0;
    while I <= High(Sorted) do
    begin
      J:= I;
      while (J < High(Sorted)) and (Sorted[J + 1] = Sorted[J] + 1) do Inc(J);
      E:= Default(TFileEdit);
      E.Kind := ekDelete;
      E.First:= Sorted[I];
      E.Last := Sorted[J];
      L.Add(E);
      I:= J + 1;
    end;
    for var K:= 1 to Length(F.Lines) do
      if FReplaced.ContainsKey(LineKey(pFid, K)) then
      begin
        E:= Default(TFileEdit);
        E.Kind    := ekReplace;
        E.First   := K;
        E.Last    := K;
        E.NewLines:= [FReplaced[LineKey(pFid, K)]];
        L.Add(E);
      end;
    if FExtraEdits.ContainsKey(pFid) then L.AddRange(FExtraEdits[pFid]);
    { bottom-up; an insert AFTER line N runs before an edit starting AT line N }
    L.Sort(TComparer<TFileEdit>.Construct(
      function(const pLeft, pRight: TFileEdit): Integer
      begin
        Result:= (pRight.First * 2 + Ord(pRight.Kind = ekInsertAfter)) - (pLeft.First * 2 + Ord(pLeft.Kind = ekInsertAfter));
      end));
    Result:= L.ToArray;
  finally
    Dels.Free;
    L.Free;
  end;
end;

function TCyclePlanner.EditOrder: TArray<Int64>;
var
  L: TList<Int64>;
begin
  L:= TList<Int64>.Create;
  try
    for var S in FComp do
      if FTouched.Contains(FidOfStem(S)) then L.Add(FidOfStem(S));
    for var Fid in FTouched do
      if (not L.Contains(Fid)) and (Fid <> FProjectFid) then L.Add(Fid);
    if FTouched.Contains(FProjectFid) then L.Add(FProjectFid);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  prediction: replay the uses changes on the graph
  --------------------------------------------------------------------------- }

function TCyclePlanner.PredictedEdges: TObjectDictionary<string, TList<string>>;
var
  L: TList<string>;
begin
  { edge list per member: 'b' for an implementation edge, 'b!' for an interface one }
  Result:= TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  for var A in FComp do
  begin
    L:= TList<string>.Create;
    Result.Add(A, L);
    var F:= GetFile(FidOfStem(A));
    for var U in F.UsesList do
    begin
      var B:= LowerCase(U.UnitName);
      if (B = A) or not FMembers.ContainsKey(B) then Continue;
      var Sect:= if U.Section = uusInterface then scIntf else scImpl;
      if ListOf(FUsesDel, F.Fid, Sect).Contains(B) then Continue;
      AddUnique(L, B + (if Sect = scIntf then CIntfMark else ''));
    end;
    for var S in ListOf(FUsesAdd, F.Fid, scImpl) do
      if FMembers.ContainsKey(StemOfEntry(S)) then AddUnique(L, StemOfEntry(S));
  end;
end;

function TCyclePlanner.Targets(pEdges: TObjectDictionary<string, TList<string>>; const pFrom: string): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var S in pEdges[pFrom] do AddUnique(L, S.Replace(CIntfMark, ''));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCyclePlanner.Predict;
var
  Edges: TObjectDictionary<string, TList<string>>;
  Reach: TDictionary<string, Boolean>;
  Done : TDictionary<string, Boolean>;
  Queue: TList<string>;
  M    : TList<string>;
  G    : TPredGroup;
begin
  Edges:= PredictedEdges;
  Reach:= TDictionary<string, Boolean>.Create;
  Done := TDictionary<string, Boolean>.Create;
  Queue:= TList<string>.Create;
  M    := TList<string>.Create;
  try
    { breadth-first reachability from every member -- the groups are small }
    for var A in FComp do
    begin
      Queue.Clear;
      Queue.Add(A);
      while Queue.Count > 0 do
      begin
        var X:= Queue[0];
        Queue.Delete(0);
        for var Y in Targets(Edges, X) do
          if not Reach.ContainsKey(A + '>' + Y) then
          begin
            Reach.Add(A + '>' + Y, True);
            Queue.Add(Y);
          end;
      end;
    end;
    for var A in FComp do
    begin
      if Done.ContainsKey(A) then Continue;
      M.Clear;
      M.Add(A);
      for var B in FComp do
        if (B <> A) and Reach.ContainsKey(A + '>' + B) and Reach.ContainsKey(B + '>' + A) then M.Add(B);
      for var S in M do Done.AddOrSetValue(S, True);
      if M.Count < 2 then Continue;
      G.Members:= M.ToArray;
      G.HasIntf:= False;
      for var X in G.Members do
        for var Y in G.Members do
          if (X <> Y) and Edges[X].Contains(Y + CIntfMark) then G.HasIntf:= True;
      FPredicted.Add(G);
    end;
  finally
    M.Free;
    Queue.Free;
    Done.Free;
    Reach.Free;
    Edges.Free;
  end;
end;

function TCyclePlanner.GroupHasIntf(const pComp: TArray<string>): Boolean;
begin
  for var A in pComp do
    for var B in pComp do
      if (A <> B) and FGraph.IntfEdges.ContainsKey(A + '->' + B) then Exit(True);
  Result:= False;
end;

function TCyclePlanner.ExpectedOutput(pSelf: Integer): TArray<string>;
var
  L: TList<string>;
  N: Integer;
begin
  L:= TList<string>.Create;
  try
    N:= FSccs.Count - 1 + FPredicted.Count;
    if N = 0 then L.Add(CCycleNone)
    else
    begin
      L.Add(Format(CCycleCountFmt, [N]));
      for var I:= 0 to FSccs.Count - 1 do
        if I <> pSelf then
          L.Add(Format(CCycleGroupFmt, [Length(FSccs[I]), string.Join(' <-> ', FSccs[I]),
            (if GroupHasIntf(FSccs[I]) then CCycleTagInterface else CCycleTagImplOnly)]));
      for var G in FPredicted do
        L.Add(Format(CCycleGroupFmt, [Length(G.Members), string.Join(' <-> ', G.Members),
          (if G.HasIntf then CCycleTagInterface else CCycleTagImplOnly)]));
      L.Add(CCycleEdgesHint);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.RemainingNeeds(const pFrom, pTo: string; pAll: Boolean): TArray<TNeed>;
var
  L   : TList<TNeed>;
  Seen: TDictionary<Int64, Boolean>;
  Fid : Int64;
begin
  L   := TList<TNeed>.Create;
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    Fid:= FidOfStem(pFrom);
    for var N in NeedsOf(Fid) do
    begin
      if (N.OwnerStem <> pTo) or Seen.ContainsKey(N.Owner.Id) then Continue;
      if (not pAll) and (IsMovedFor(N.Owner, Fid) or IsDeleted(Fid, N.Line)) then Continue;
      Seen.Add(N.Owner.Id, True);
      L.Add(N);
    end;
    Result:= L.ToArray;
  finally
    Seen.Free;
    L.Free;
  end;
end;

function TCyclePlanner.EvaluateEdge(const pFrom, pTo: string; const pNeeds: TArray<TNeed>): TEdgeEval;
var
  Snap: Integer;
  Why : string;
begin
  Result:= Default(TEdgeEval);
  Result.FromStem:= pFrom;
  Result.ToStem  := pTo;
  Result.Needs   := pNeeds;
  Result.Movable := Length(pNeeds) > 0;
  if not Result.Movable then Result.Why:= 'the index resolved no symbol for this edge';
  Snap:= FOrder.Count;
  for var N in pNeeds do
    if not TryAdd(N.Owner, nil, Why) then
    begin
      Result.Movable:= False;
      Result.Why    := Format('`%s` (%s): %s', [N.Owner.Name, N.Owner.Kind.ToText, Why]);
      Break;
    end;
  Result.Cost:= FOrder.Count - Snap;
  Rollback(Snap);
end;

{ ---------------------------------------------------------------------------
  rendering
  --------------------------------------------------------------------------- }

procedure TCyclePlanner.Emit(const pText: string);
begin
  FOut.Add(pText);
end;

procedure TCyclePlanner.EmitFmt(const pFmt: string; const pArgs: array of const);
begin
  FOut.Add(Format(pFmt, pArgs));
end;

procedure TCyclePlanner.EmitBlock(const pFence: string; const pLines: TArray<string>);
begin
  Emit(pFence);
  for var S in pLines do Emit(S);
  Emit(CCodeFence);
end;

function TCyclePlanner.MemberNames: string;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var S in FComp do L.Add(UnitNameOfStem(S));
    L.Sort;
    Result:= QuoteList(L.ToArray);
  finally
    L.Free;
  end;
end;

function TCyclePlanner.ReindexCommand: string;
begin
  if FProjectFile <> '' then
    Result:= Format('drag-lint index --project "%s" --db "%s"', [FProjectFile, FDbPath])
  else
    Result:= Format('drag-lint index "%s" --db "%s"',
      [ExcludeTrailingPathDelimiter(ExtractFilePath(PathOf(FidOfStem(FComp[0])))), FDbPath]);
end;

function TCyclePlanner.CyclesCommand(pPlan: Boolean): string;
begin
  Result:= Format('drag-lint cycles --db "%s"', [FDbPath]) + (if pPlan then ' --plan' else '');
end;

procedure TCyclePlanner.RenderHeader;
begin
  Emit('# Cycle refactoring playbook');
  Emit('');
  Emit('Generated by `drag-lint cycles --plan`. Each cycle below is a mechanical');
  Emit('procedure: which declarations move, into which new unit, which uses clauses');
  Emit('change, and the exact text of every edit. Line numbers are those of the files');
  Emit('AS THEY ARE NOW, before any edit. The index can miss a reference (e.g. a `set`');
  Emit('type), so each procedure ends with a compile, a re-check, and what to do about');
  Emit('each error the compile can report. Fix ONE cycle, then re-run');
  Emit('`drag-lint cycles --plan`: after the first edit, the line numbers given for the');
  Emit('other cycles are stale.');
  Emit('');
end;

procedure TCyclePlanner.RenderFiles;
begin
  Emit('Files:');
  for var A in FComp do
  begin
    var P: string:= '';
    FGraph.UnitFile.TryGetValue(A, P);
    EmitFmt('- `%s` -> `%s`', [A, P]);
  end;
  for var A in FComp do
    for var B in FComp do
      if (A <> B) and FGraph.Adj[A].Contains(B) and (LayerOfPath(PathOf(FidOfStem(A))) = 'COMMON') and
        MatchText(LayerOfPath(PathOf(FidOfStem(B))), ['CLIENT', 'SERVER']) then
        EmitFmt('- Note: `%s` (COMMON) uses `%s` (%s) -- a layering inversion. The steps below cut the ' +
          'cycle; that edge should also go, by declaring in COMMON an interface that `%s` implements.',
          [A, B, LayerOfPath(PathOf(FidOfStem(B))), B]);
  Emit('');
end;

procedure TCyclePlanner.RenderIntfWhy;
var
  Seen: TDictionary<Int64, Boolean>;
begin
  Emit('### Why it cycles');
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    for var A in FComp do
      for var B in FComp do
      begin
        if (A = B) or not FGraph.IntfEdges.ContainsKey(A + '->' + B) then Continue;
        var F:= GetFile(FidOfStem(A));
        Seen.Clear;
        for var N in NeedsOf(F.Fid) do
        begin
          if (N.Sect <> scIntf) or (N.OwnerStem <> B) or Seen.ContainsKey(N.Owner.Id) then Continue;
          Seen.Add(N.Owner.Id, True);
          EmitFmt('- `%s` interface uses `%s` (%s) at `%s:%d`; declared in `%s:%d`.',
            [A, N.Owner.Name, N.Owner.Kind.ToText, ExtractFileName(F.Path), N.Line,
             ExtractFileName(PathOf(N.Owner.FileId)), N.Owner.StartLine]);
        end;
        if Seen.Count = 0 then
          EmitFmt('- `%s` interface uses `%s` but the index could not resolve the symbol (likely a ' +
            '`set` type). **Open `%s` and find what its interface uses from `%s` by hand.**',
            [A, B, ExtractFileName(F.Path), B]);
      end;
  finally
    Seen.Free;
  end;
  Emit('');
end;

procedure TCyclePlanner.RenderImplWhy;
var
  Seen: TDictionary<string, Boolean>;
begin
  Emit('### Why it cycles (implementation-section edges)');
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for var A in FComp do
      for var B in FComp do
      begin
        if (A = B) or not FGraph.Adj[A].Contains(B) then Continue;
        var F:= GetFile(FidOfStem(A));
        EmitFmt('- `%s` uses `%s` in its **implementation** section (`%s`) via:', [A, B, ExtractFileName(F.Path)]);
        Seen.Clear;
        for var N in NeedsOf(F.Fid) do
        begin
          if (N.Sect <> scImpl) or (N.OwnerStem <> B) or Seen.ContainsKey(LowerCase(N.RefName)) then Continue;
          Seen.Add(LowerCase(N.RefName), True);
          EmitFmt('    - line %d: `%s`  [%s]  -> declared in `%s`', [N.Line, N.RefName, N.RefKind.ToText, B]);
        end;
        if Seen.Count = 0 then
          EmitFmt('    - (no specific symbol resolved -- index gap, e.g. a `set` type; open `%s` and ' +
            'scan its implementation uses of `%s` by hand)', [ExtractFileName(F.Path), B]);
      end;
  finally
    Seen.Free;
  end;
  Emit('');
end;

function TCyclePlanner.KindLabel(const pItem: TMoveItem): string;
begin
  case pItem.Sym.Kind of
    skEnum     : Result:= 'enum';
    skTypeAlias: Result:= 'type';
    skInterface: Result:= 'interface type';
    skConstDecl: Result:= 'constant';
    skVarDecl  : Result:= 'global variable';
    skRecord   : Result:= if Length(pItem.Bodies) > 0 then 'record with methods' else 'record';
    skClass    : Result:= if Length(pItem.Bodies) > 0 then 'class with methods' else 'class';
  else
    Result:= pItem.Sym.Kind.ToText;
  end;
end;

procedure TCyclePlanner.RenderConsumers(const pItem: TMoveItem);
var
  L: TList<TConsumer>;
begin
  if not FConsumers.TryGetValue(pItem.Sym.Id, L) then Exit;
  EmitFmt('   - Used by (each needs `%s` in the uses clause of that section; the edit step does it):',
    [FLeafName[pItem.Stem]]);
  for var C in L do
    EmitFmt('     - `%s` %s (first use: line %d)', [ExtractFileName(PathOf(C.Fid)), SectLabel(C.Sect), C.Line]);
end;

procedure TCyclePlanner.RenderBaseRecipe(const pItem: TMoveItem);
var
  Names: TList<string>;
  Lines: TList<Integer>;
begin
  EmitFmt('   - Recipe: **extract a base class** and keep `%s` where it is. Why: its method bodies use %s, ' +
    'which live in units of this cycle; moving the class would mean moving those bodies (lines %s) ' +
    'AND everything they use.', [pItem.Sym.Name, QuoteList(pItem.Drags), RangeText(pItem.Bodies)]);
  Names:= TList<string>.Create;
  Lines:= TList<Integer>.Create;
  try
    for var M in pItem.BaseMembers do Names.Add(M.Sym.Name);
    EmitFmt('   - New class `%s` in `%s` carries exactly what the units below use: %s.',
      [pItem.BaseName, FLeafName[pItem.Stem], (if Names.Count > 0 then QuoteList(Names.ToArray) else 'nothing (an empty base)')]);
    EmitFmt('   - `%s` stays in `%s` and becomes `%s = class(%s)`; the members above are deleted from it.',
      [pItem.Sym.Name, ExtractFileName(PathOf(pItem.Sym.FileId)), pItem.Sym.Name, pItem.BaseName]);
    for var Fid in pItem.CutFids do
    begin
      Lines.Clear;
      for var S in pItem.Switches do
        if S.Fid = Fid then Lines.Add(S.Line);
      var Nums:= TList<string>.Create;
      try
        for var N in SortedInts(Lines) do Nums.Add(IntToStr(N));
        EmitFmt('   - Units that switch to `%s` (the name is replaced on these lines): `%s` lines %s.',
          [pItem.BaseName, ExtractFileName(PathOf(Fid)), string.Join(', ', Nums.ToArray)]);
      finally
        Nums.Free;
      end;
    end;
  finally
    Lines.Free;
    Names.Free;
  end;
end;

procedure TCyclePlanner.RenderOneMove(pNo: Integer; const pItem: TMoveItem);
var
  FileName: string;
begin
  FileName:= ExtractFileName(PathOf(pItem.Sym.FileId));
  EmitFmt('%d. `%s` -- **%s**, declared at `%s` lines %d-%d%s.', [pNo, pItem.Sym.Name, KindLabel(pItem),
    FileName, pItem.Decl.First, pItem.Decl.Last,
    (if Length(pItem.Bodies) > 0 then Format('; method bodies at `%s` lines %s', [FileName, RangeText(pItem.Bodies)]) else '')]);
  case pItem.Kind of
    mvDecl:
      EmitFmt('   - Recipe: %s %s has no code of its own -- move the declaration, unchanged, into `%s`.',
        [(if CharInSet(KindLabel(pItem)[1], ['a', 'e', 'i', 'o', 'u']) then 'an' else 'a'), KindLabel(pItem), FLeafName[pItem.Stem]]);
    mvWithBodies:
      EmitFmt('   - Recipe: **move the whole %s**: its declaration AND its method bodies (lines %s) go ' +
        'into `%s` (the bodies into its implementation section). Why: the bodies use nothing else from ' +
        'this cycle, so they can travel with it.', [KindLabel(pItem), RangeText(pItem.Bodies), FLeafName[pItem.Stem]]);
    mvBase:
      RenderBaseRecipe(pItem);
  end;
  RenderConsumers(pItem);
end;

procedure TCyclePlanner.RenderManual;
begin
  if FManual.Count = 0 then Exit;
  Emit('');
  Emit('**MANUAL -- not mechanical.** These symbols cannot be moved by the recipes above; their ' +
    'edge stays until you cut it by hand:');
  for var M in FManual do
    EmitFmt('- `%s` (%s, `%s` line %d): %s.', [M.Sym.Name, M.Sym.Kind.ToText,
      ExtractFileName(PathOf(M.Sym.FileId)), M.Sym.StartLine, M.Reason]);
end;

procedure TCyclePlanner.RenderMoves(pStep: Integer);
var
  No: Integer;
begin
  EmitFmt('### Step %d: what moves where', [pStep]);
  No:= 0;
  for var Id in FOrder do
  begin
    Inc(No);
    RenderOneMove(No, FItems[Id]);
  end;
  if FOrder.Count = 0 then Emit('Nothing can be moved mechanically.');
  RenderManual;
  Emit('');
end;

procedure TCyclePlanner.RenderDecisions(pStep: Integer);
begin
  EmitFmt('### Step %d: uses clauses -- keep, move or remove the old unit', [pStep]);
  Emit('For each unit of the cycle that uses a unit whose declarations move. A unit can be removed ' +
    'from a section only when nothing else from it is used there.');
  for var D in FDecisions do
  begin
    var Who:= Format('- `%s` / `%s`: ', [ExtractFileName(PathOf(D.Fid)), UnitNameOfStem(D.PartnerStem)]);
    case D.Verdict of
      uvKeep:
        EmitFmt('%s**keep** it in the %s uses; that section still uses %s.', [Who, SectLabel(D.Sect), D.Still]);
      uvKeepUnseen:
        EmitFmt('%s**keep** it in the %s uses (the index saw no symbol from it there -- do not touch it).',
          [Who, SectLabel(D.Sect)]);
      uvMove:
        EmitFmt('%sthe interface no longer needs it; the implementation still does (%s) -> **move** it ' +
          'from the interface uses to the implementation uses.', [Who, D.Still]);
      uvRemove:
        EmitFmt('%snothing from it is used there any more -> **remove** it from the %s uses.',
          [Who, SectLabel(D.Sect)]);
    end;
  end;
  if FDecisions.Count = 0 then Emit('- (no uses entry between units of this cycle changes)');
  Emit('');
end;

function TCyclePlanner.BaseClassText(const pItem: TMoveItem): TArray<string>;
var
  L     : TList<string>;
  F     : TPlanFile;
  Ind   : string;
  Header: Boolean;
begin
  F  := GetFile(pItem.Sym.FileId);
  Ind:= pItem.BaseIndent;
  L  := TList<string>.Create;
  try
    L.Add(Ind + '/// <summary>Base class of <c>' + pItem.Sym.Name + '</c>: the members that units');
    L.Add(Ind + '/// outside <c>' + F.UnitName + '</c> use, extracted by drag-lint cycles --plan');
    L.Add(Ind + '/// so those units can depend on this leaf unit instead.</summary>');
    L.Add(Ind + pItem.BaseName + ' = class');
    for var Vis in TArray<string>.Create('protected', 'public', 'published') do
    begin
      Header:= False;
      for var M in pItem.BaseMembers do
      begin
        var MVis:= if M.Sym.Kind = skField then 'protected' else LowerCase(Trim(M.Sym.Modifiers));
        if not MatchText(MVis, ['public', 'published']) then MVis:= 'protected';
        if MVis <> Vis then Continue;
        if not Header then L.Add(Ind + Vis);
        Header:= True;
        var Body:= SliceLines(F.Lines, M.Range);
        if M.Sym.Kind in [skMethod, skFunction, skProcedure] then
        begin
          var Code:= CodePart(Body[High(Body)]);
          Body[High(Body)]:= TrimRight(Code) + CAbstractTail + Copy(Body[High(Body)], Length(Code) + 1, MaxInt);
        end;
        L.AddRange(Body);
      end;
    end;
    L.Add(Ind + 'end;');
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TCyclePlanner.LeafUnitText(const pStem: string): TArray<string>;
var
  L      : TList<string>;
  P      : TPlanFile;
  Entries: TList<string>;
  Keyword: string;
  Bodies : TList<TLineRange>;
  Items  : TList<TMoveItem>;
begin
  P      := GetFile(FidOfStem(pStem));
  L      := TList<string>.Create;
  Entries:= TList<string>.Create;
  Bodies := TList<TLineRange>.Create;
  Items  := TList<TMoveItem>.Create;
  try
    L.Add('unit ' + FLeafName[pStem] + ';');
    L.Add('');
    L.Add('// Created by `drag-lint cycles --plan`: declarations moved here from ' + P.UnitName);
    L.Add('// to break a circular unit dependency. This unit may use only units OUTSIDE');
    L.Add('// that cycle -- never ' + MemberNames.Replace('`', '') + '.');
    L.Add('');
    L.Add('interface');
    for var U in SectionEntries(P, scIntf) do
      if not FMembers.ContainsKey(LowerCase(U.UnitName)) then Entries.Add(EntryText(P, U));
    if FLeafDeps.ContainsKey(pStem) then
      for var S in FLeafDeps[pStem] do AddUnique(Entries, S);
    if Entries.Count > 0 then
    begin
      L.Add('');
      L.AddRange(FormatUses('', Entries.ToArray, nil));
    end;
    { SOURCE order, not closure order: a variable is added before the type it
      needs, and Delphi requires the type to be declared first }
    Items.Clear;
    for var Id in FOrder do
      if FItems[Id].Stem = pStem then Items.Add(FItems[Id]);
    Items.Sort(TComparer<TMoveItem>.Construct(
      function(const pLeft, pRight: TMoveItem): Integer
      begin
        Result:= pLeft.Decl.First - pRight.Decl.First;
      end));
    Keyword:= '';
    for var Item in Items do
    begin
      var KW:= if Item.Kind = mvBase then 'type' else Item.Keyword;
      L.Add('');
      if KW <> Keyword then L.Add(KW);
      Keyword:= KW;
      if Item.Kind = mvBase then L.AddRange(BaseClassText(Item))
      else L.AddRange(SliceLines(P.Lines, Item.Decl));
      if Item.Kind = mvWithBodies then Bodies.AddRange(Item.Bodies);
    end;
    L.Add('');
    L.Add('implementation');
    if Bodies.Count > 0 then
    begin
      Entries.Clear;
      for var U in SectionEntries(P, scImpl) do
        if not FMembers.ContainsKey(LowerCase(U.UnitName)) then Entries.Add(EntryText(P, U));
      if Entries.Count > 0 then
      begin
        L.Add('');
        L.AddRange(FormatUses('', Entries.ToArray, nil));
      end;
      for var R in Bodies do
      begin
        L.Add('');
        L.AddRange(SliceLines(P.Lines, R));
      end;
    end;
    L.Add('');
    L.Add('end.');
    Result:= L.ToArray;
  finally
    Items.Free;
    Bodies.Free;
    Entries.Free;
    L.Free;
  end;
end;

procedure TCyclePlanner.RenderLeafUnits(pStep: Integer);
begin
  EmitFmt('### Step %d: create the new units', [pStep]);
  EmitFmt('Each new unit may use only RTL / library units and other new `*%s` units -- never a ' +
    'unit of this cycle (%s). Create each file with EXACTLY this text:', [CLeafSuffix, MemberNames]);
  Emit('');
  for var Stem in LeafStems do
  begin
    EmitFmt('#### `%s` -> `%s`', [FLeafName[Stem], FLeafPath[Stem]]);
    EmitBlock(CPascalFence, LeafUnitText(Stem));
    if FProjectFid > 0 then
      EmitFmt('Register it in the project (the edit step spells out both edits): the .dpr uses clause ' +
        'gets `%s`; the .dproj lists it as `<DCCReference Include="%s"/>`.',
        [UsesEntryFor(GetFile(FProjectFid), Stem), ExtractFileName(FLeafPath[Stem])]);
    Emit('');
  end;
end;

procedure TCyclePlanner.RenderFileEdits(const pTitle: string; const pLines: TArray<string>;
  const pEdits: TArray<TFileEdit>; const pFence: string);
var
  No: Integer;
begin
  if Length(pEdits) = 0 then Exit;
  Emit(pTitle);
  No:= 0;
  for var E in pEdits do
  begin
    Inc(No);
    var Span:= if E.First = E.Last then Format('line %d', [E.First]) else Format('lines %d-%d', [E.First, E.Last]);
    case E.Kind of
      ekDelete:
        begin
          EmitFmt('E%d. Delete %s. Current text:', [No, Span]);
          EmitBlock(pFence, SliceLines(pLines, OneRange(E.First, E.Last)));
        end;
      ekReplace:
        begin
          EmitFmt('E%d. Replace %s. Current text:', [No, Span]);
          EmitBlock(pFence, SliceLines(pLines, OneRange(E.First, E.Last)));
          Emit('New text:');
          EmitBlock(pFence, E.NewLines);
        end;
      ekInsertAfter:
        begin
          EmitFmt('E%d. After line %d (`%s`), insert:', [No, E.First, Trim(LineAt(pLines, E.First))]);
          EmitBlock(pFence, E.NewLines);
        end;
      ekManual:
        EmitFmt('E%d. %s', [No, E.Note]);
    end;
  end;
  Emit('');
end;

procedure TCyclePlanner.RenderEdits(pStep: Integer);
begin
  EmitFmt('### Step %d: edit the existing files', [pStep]);
  Emit('Apply each file''s edits in the order listed. They run from the bottom of the file to the ' +
    'top, so the line numbers of the edits still to do do not move. "Current text" is what the lines ' +
    'say before the edit -- if it does not match, stop: the file changed since it was indexed.');
  Emit('');
  for var Fid in EditOrder do
  begin
    var F:= GetFile(Fid);
    RenderFileEdits(Format('#### `%s`  (`%s`)', [ExtractFileName(F.Path), F.Path]), F.Lines, EditsOf(Fid), CPascalFence);
  end;
  if FDprojEdits.Count = 0 then Exit;
  var Arr:= FDprojEdits.ToArray;
  TArray.Sort<TFileEdit>(Arr, TComparer<TFileEdit>.Construct(
    function(const pLeft, pRight: TFileEdit): Integer
    begin
      Result:= pRight.First - pLeft.First;
    end));
  RenderFileEdits(Format('#### `%s`  (`%s`)', [ExtractFileName(FProjectFile), FProjectFile]),
    TFile.ReadAllLines(FProjectFile), Arr, CXmlFence);
end;

procedure TCyclePlanner.RenderCompileHelp;
begin
  Emit('#### If the compile fails');
  Emit('- `E2003 Undeclared identifier: ''X''` in file F at line N: the index missed a use of X. ' +
    'If X is listed in the "what moves where" step, add that step''s new unit to F''s uses clause ' +
    'of the section holding line N (interface above `implementation`, implementation below it). ' +
    'Otherwise X still lives in a unit you moved or removed in the uses step: add that unit back ' +
    'to the same section.');
  Emit('- `E2065 Unsatisfied forward or external declaration`: a class moved without its method ' +
    'bodies. Move the bodies listed for it as well.');
  Emit('- `E2010 Incompatible types: ''TX'' and ''TXBase''` or `E2033 Types of actual and formal ' +
    'var parameters must be identical`: a routine now takes or returns the base class. Cast at that ' +
    'line: `TX(value)`.');
  Emit('- `F2047 Circular unit reference`: a new unit names a unit of this cycle in its uses. ' +
    'Remove that entry -- the new units may use only what the "create the new units" step lists.');
  Emit('- `F1026 File not found`: a new unit''s file name must equal its unit name plus `.pas`.');
  Emit('');
end;

procedure TCyclePlanner.RenderChecklist(pSelf: Integer);
var
  No: Integer;

  procedure Item(const pText: string);
  begin
    Inc(No);
    EmitFmt('%d. [ ] %s', [No, pText]);
  end;

begin
  Emit('### Checklist');
  Emit('Tick each box in order. Do not skip the compile.');
  No:= 0;
  { IDE-9 run 2 (2026-09-23): a cheap model followed the plan 4/4 but saved the
    NEW units with LF endings -- the plan never said how to save them. Say it. }
  for var Stem in LeafStems do
    Item(Format('Create `%s` with the exact text given for `%s`. Save it as plain ASCII with ' +
      'Windows CRLF line endings, like the existing units.', [FLeafPath[Stem], FLeafName[Stem]]));
  for var Fid in EditOrder do
    if Length(EditsOf(Fid)) > 0 then
      Item(Format('Apply every edit listed for `%s`, in the order listed.', [ExtractFileName(PathOf(Fid))]));
  if FDprojEdits.Count > 0 then
    Item(Format('Apply every edit listed for `%s`.', [ExtractFileName(FProjectFile)]));
  if FProjectFile <> '' then
    Item(Format('Compile `%s` (RAD Studio: Project > Build; or `msbuild "%s" /t:Build` from a RAD ' +
      'Studio Command Prompt). Expect 0 errors; on an error see "If the compile fails" below, fix, ' +
      'and compile again.', [ExtractFileName(FProjectFile), FProjectFile]))
  else
    Item('Compile the project. Expect 0 errors; on an error see "If the compile fails" below.');
  Item(Format('Re-index: `%s`', [ReindexCommand]));
  Item(Format('Run `%s`. It must print exactly:', [CyclesCommand(False)]));
  EmitBlock(CTextFence, ExpectedOutput(pSelf));
  Emit('   The units inside a group may be listed in a different order. Lines starting with ' +
    '`(loaded`, `drag-lint: note:` or `  resolver:` are informational -- ignore them.');
  Emit('');
  RenderCompileHelp;
end;

procedure TCyclePlanner.RenderDone(pIntf: Boolean);
var
  Still: Boolean;
begin
  Still:= False;
  for var G in FPredicted do
    if G.HasIntf then Still:= True;
  Emit('### DONE');
  if pIntf then
    Emit('This plan (Part A) removes the INTERFACE-section coupling of this cycle. It is DONE when ' +
      'both hold: (1) the project compiles with 0 errors, and (2) `drag-lint cycles` prints exactly ' +
      'the output given in the last checklist item.')
  else
    EmitFmt('This plan cuts the edge `%s -> %s`, the cheapest edge of this cycle that can be cut ' +
      'mechanically. It is DONE when both hold: (1) the project compiles with 0 errors, and (2) ' +
      '`drag-lint cycles` prints exactly the output given in the last checklist item.',
      [FCutEdge.FromStem, FCutEdge.ToStem]);
  if FPredicted.Count = 0 then
    Emit('After it, these units form no cycle at all.')
  else if Still then
    Emit('After it, some of these units still use each other in their interfaces: the MANUAL ' +
      'items were not cut. Cut them by hand, or leave them.')
  else
    Emit('After it, these units still form a cycle, but only through IMPLEMENTATION uses. That is ' +
      'LEGAL Delphi: it compiles, and a change to one unit no longer forces the others'' ' +
      'interfaces to recompile. Removing it as well is optional (Part B).');
  Emit('');
end;

procedure TCyclePlanner.RenderRemedy;
begin
  Emit('The standard remedy: move the shared GLOBAL variables (and the plain types they need) into a ' +
    'leaf unit that both sides use; a routine can move only together with everything its body uses, ' +
    'or be handed over as a parameter / event instead of being called by name.');
end;

procedure TCyclePlanner.RenderPartB;
var
  Best : TEdgeEval;
  Names: TList<string>;
begin
  Emit('### Part B (optional): remove the implementation-only cycle too');
  if FPredicted.Count = 0 then
  begin
    Emit('Nothing to do: after Part A no cycle remains among these units.');
    Emit('');
    Exit;
  end;
  Emit('After Part A these units still use each other through these edges (predicted):');
  Best := Default(TEdgeEval);
  Names:= TList<string>.Create;
  try
    for var G in FPredicted do
      for var A in G.Members do
        for var B in G.Members do
        begin
          if A = B then Continue;
          var Needs:= RemainingNeeds(A, B, False);
          if Length(Needs) = 0 then Continue;
          var Ev:= EvaluateEdge(A, B, Needs);
          Names.Clear;
          for var N in Needs do Names.Add(Format('%s (%s)', [N.Owner.Name, N.Owner.Kind.ToText]));
          EmitFmt('- `%s -> %s`: %s -- %s', [A, B, QuoteList(Names.ToArray),
            (if Ev.Movable then 'mechanical: these can move into a new leaf unit' else 'not mechanical: ' + Ev.Why)]);
          if Ev.Movable and ((Best.FromStem = '') or (Ev.Cost < Best.Cost)) then Best:= Ev;
        end;
  finally
    Names.Free;
  end;
  Emit('');
  RenderRemedy;
  if Best.FromStem <> '' then
    EmitFmt('To do it: finish Part A (every checklist item), then run `%s` again. It prints Part B as ' +
      'the same kind of numbered, mechanical steps, with line numbers for the edited files. The edge ' +
      'it will cut is `%s -> %s`.', [CyclesCommand(True), Best.FromStem, Best.ToStem])
  else
    Emit('No edge above can be cut mechanically; leaving the implementation-only cycle is acceptable.');
  Emit('');
end;

procedure TCyclePlanner.RenderIntfCycle(pSelf: Integer);
var
  Seeds: TList<TNeed>;
  Cut  : TObjectDictionary<Int64, TList<Int64>>;
  Why  : string;
begin
  Emit('Status: **interface coupling** -- units of this cycle use each other in their INTERFACE ' +
    'uses clauses.');
  Emit('');
  RenderFiles;
  RenderIntfWhy;
  Seeds:= TList<TNeed>.Create;
  Cut  := TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  try
    { every interface edge of the cycle is cut: its symbols are the seeds, and
      the units whose interface names a class are its base-class consumers }
    for var A in FComp do
      for var B in FComp do
      begin
        if (A = B) or not FGraph.IntfEdges.ContainsKey(A + '->' + B) then Continue;
        for var N in NeedsOf(FidOfStem(A)) do
        begin
          if (N.Sect <> scIntf) or (N.OwnerStem <> B) then Continue;
          if not Cut.ContainsKey(N.Owner.Id) then
          begin
            Cut.Add(N.Owner.Id, TList<Int64>.Create);
            Seeds.Add(N);
          end;
          if not Cut[N.Owner.Id].Contains(FidOfStem(A)) then Cut[N.Owner.Id].Add(FidOfStem(A));
        end;
      end;
    for var N in Seeds do
    begin
      var Snap:= FOrder.Count;
      if TryAdd(N.Owner, Cut[N.Owner.Id].ToArray, Why) then Continue;
      Rollback(Snap);
      var M:= Classify(N.Owner, Cut[N.Owner.Id].ToArray);
      M.Reason:= Why;
      FManual.Add(M);
    end;
  finally
    Cut.Free;
    Seeds.Free;
  end;
  Materialize;
  Emit('### Goal');
  Emit('Part A (steps 1-4, required) removes the INTERFACE coupling: each symbol above -- and ' +
    'whatever it needs -- moves into a new leaf unit, or its class gets a base class there, so no ' +
    'unit of the cycle needs another one in its interface any more. Part B (optional) removes the ' +
    'implementation-only cycle that may remain.');
  Emit('');
  RenderDone(True);
  RenderMoves(CStepMoves);
  RenderDecisions(CStepUses);
  RenderLeafUnits(CStepCreate);
  RenderEdits(CStepEdit);
  RenderChecklist(pSelf);
  RenderPartB;
end;

procedure TCyclePlanner.RenderNoMechanicalCut(const pEvals: TArray<TEdgeEval>);
begin
  Emit('No edge of this cycle can be cut mechanically:');
  for var Ev in pEvals do
    EmitFmt('- `%s -> %s`: %s', [Ev.FromStem, Ev.ToStem, Ev.Why]);
  Emit('');
  RenderRemedy;
  Emit('This cycle is legal Delphi and compiles; leaving it is acceptable.');
  Emit('');
end;

procedure TCyclePlanner.RenderImplCycle(pSelf: Integer);
var
  Evals: TList<TEdgeEval>;
  Why  : string;
begin
  Emit('Status: **implementation-only** (legal in Delphi, low impact -- no interface-recompile ' +
    'blast radius). Optional to fix; the steps below are for when you want a fully acyclic uses-graph.');
  Emit('');
  RenderFiles;
  RenderImplWhy;
  Emit('### Recommended fix (optional)');
  Evals:= TList<TEdgeEval>.Create;
  try
    for var A in FComp do
      for var B in FComp do
        if (A <> B) and FGraph.Adj[A].Contains(B) then
        begin
          var Ev:= EvaluateEdge(A, B, RemainingNeeds(A, B, True));
          Evals.Add(Ev);
          if Ev.Movable and ((FCutEdge.FromStem = '') or (Ev.Cost < FCutEdge.Cost)) then FCutEdge:= Ev;
        end;
    if FCutEdge.FromStem = '' then RenderNoMechanicalCut(Evals.ToArray);
  finally
    Evals.Free;
  end;
  if FCutEdge.FromStem = '' then Exit;
  EmitFmt('Cut the edge `%s -> %s`: everything `%s` uses from `%s` can move into a new leaf unit, ' +
    'the smallest mechanical cut in this cycle.', [FCutEdge.FromStem, FCutEdge.ToStem,
    FCutEdge.FromStem, FCutEdge.ToStem]);
  Emit('');
  for var N in FCutEdge.Needs do TryAdd(N.Owner, nil, Why);
  Materialize;
  RenderDone(False);
  RenderMoves(CStepMoves);
  RenderDecisions(CStepUses);
  RenderLeafUnits(CStepCreate);
  RenderEdits(CStepEdit);
  RenderChecklist(pSelf);
end;

procedure TCyclePlanner.Run;
begin
  RenderHeader;
  if FSccs.Count = 0 then
  begin
    Emit('No circular unit dependencies. Nothing to do.');
    Exit;
  end;
  for var I:= 0 to FSccs.Count - 1 do
  begin
    ResetCycle(FSccs[I]);
    EmitFmt('## Cycle %d: %s', [I + 1, string.Join(' <-> ', FComp)]);
    Emit('');
    if GroupHasIntf(FComp) then RenderIntfCycle(I)
    else RenderImplCycle(I);
  end;
end;

procedure RenderCyclePlaybook(const pStore: ISymbolStore; const pDbPath: string;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pOut: TStrings);
var
  Planner: TCyclePlanner;
begin
  Planner:= TCyclePlanner.Create(pStore, pDbPath, pSccs, pGraph, pOut);
  try
    Planner.Run;
  finally
    Planner.Free;
  end;
end;

end.
