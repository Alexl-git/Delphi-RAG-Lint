unit DRagLint.Refactor.RenameProof; // dl:ok unit-too-large@ed8a -- one proof, in one place; 1 in 3 lines is the public refusal catalogue and its comments

// ---------------------------------------------------------------------------
// The proof behind `rename --apply` (lane 144 item 3, docs\wiki\Rename-Symbol.md).
//
// dcc cannot catch a rename that compiles and binds differently, so the compile gate is the backstop and this unit
// is the proof, occurrence by occurrence. It walks every identifier token of the old name in the project's sources,
// not only the refs the index holds: a token the parse never saw (an inactive {$IFDEF} branch, an `F().Name` chain)
// is exactly the occurrence nothing else would mention. Each token ends as an edit, as another symbol's, or as a
// named refusal. Then it walks every token of the NEW name, because a rename can also capture what is already
// there: a bare `Helper` that bound to a global binds to the renamed member afterwards, and compiles.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils,
  DRagLint.Core.Interfaces,
  DRagLint.Refactor.Rename,
  DRagLint.Refactor.CompileGate; // dl:ok uses-global-census@4ebc -- GBuildTimeoutMs and GScratchCited are how the gate is configured; its request record has no field for them

const
  /// <summary>The index holds no ref_receivers table: re-resolve it.</summary>
  CRefuseNoFacts = 'no-facts';
  /// <summary>An unbound ref whose receiver the index cannot type.</summary>
  CRefuseReceiverUntyped = 'receiver-untyped';
  /// <summary>An unbound ref with no receiver.</summary>
  CRefuseBareUnbound = 'bare-unbound';
  /// <summary>The receiver's chain has an ancestor neither index knows.</summary>
  CRefuseUnresolvedAncestor = 'unresolved-ancestor';
  /// <summary>A helper of a type in the chain declares the name.</summary>
  CRefuseHelperMember = 'helper-member';
  /// <summary>The name is declared `overload` with other declarers in the chain: the arguments decide.</summary>
  CRefuseOverloadSet = 'overload-set';
  /// <summary>The first declarer is not visible from the occurrence's unit, so the compiler looks further up.</summary>
  CRefuseInvisibleMember = 'invisible-member';
  /// <summary>A type name that means more than one type.</summary>
  CRefuseAmbiguousType = 'ambiguous-type';
  /// <summary>The resolver's binding is not `certain`.</summary>
  CRefuseLowConfidence = 'low-confidence';
  /// <summary>Two refs on one token bind to the target and to another symbol.</summary>
  CRefuseConflictingBinding = 'conflicting-binding';
  /// <summary>A token no ref and no declaration accounts for: an inactive {$IFDEF} branch, a chain the parse dropped.</summary>
  CRefuseNoRefOccurrence = 'no-ref-occurrence';
  /// <summary>An override or implementer in the method's group has another name.</summary>
  CRefuseGroupNameDiffers = 'group-name-differs';
  /// <summary>A dispatch edge of the method's group is not `certain`.</summary>
  CRefuseGroupUncertain = 'group-uncertain';
  /// <summary>The method overrides a base the index does not hold: the group cannot be renamed whole.</summary>
  CRefuseOverrideOfLibrary = 'override-of-library';
  /// <summary>The method implements an interface the index does not hold.</summary>
  CRefuseImplementsUnindexed = 'implements-unindexed';
  /// <summary>A descendant republishes the property (`property Name;`).</summary>
  CRefuseRedeclaredProperty = 'redeclared-property';
  /// <summary>A binary or unindexed form file may bind the name; a form that no longer loads is no compile error.</summary>
  CRefuseDfmNotRewritten = 'dfm-not-rewritten';
  /// <summary>A text form file names a published field or property; nothing rewrites it.</summary>
  CRefuseDfmNameUnbound = 'dfm-name-unbound';
  /// <summary>The new name is already a member in the class family, or a unit-level symbol.</summary>
  CRefuseNewNameCollides = 'new-name-collides';
  /// <summary>The new name is declared in the library the renamed symbol would hide or meet.</summary>
  CRefuseNewNameInLibrary = 'new-name-in-library';
  /// <summary>The proof needs the platform library and none is open.</summary>
  CRefuseNoLibrary = 'no-library';
  /// <summary>A bare occurrence of the new name would bind to the renamed symbol.</summary>
  CRefuseCaptureBare = 'capture-bare';
  /// <summary>A qualified occurrence of the new name nothing has typed.</summary>
  CRefuseCaptureUnbound = 'capture-unbound';
  /// <summary>An occurrence of the new name no ref and no declaration accounts for.</summary>
  CRefuseCaptureNoRef = 'capture-no-ref';
  /// <summary>A bare occurrence of the new name inside a `with`.</summary>
  CRefuseCaptureInWith = 'capture-in-with';
  /// <summary>A local, a parameter or a member nearer than the target would answer to the new name at this site.</summary>
  CRefuseShadowedAtSite = 'shadowed-at-site';
  /// <summary>A renamed bare site inside a `with` whose target may declare the new name.</summary>
  CRefuseShadowedInWith = 'shadowed-in-with';
  /// <summary>A local's occurrence inside a `with` the resolver did not bind.</summary>
  CRefuseWithUndecided = 'with-undecided';
  /// <summary>A local has occurrences inside a `with` and no index was given to decide them.</summary>
  CRefuseWithNeedsIndex = 'with-needs-index';
  /// <summary>The routine already uses the local's new name.</summary>
  CRefuseCaptureLocal = 'capture-local';
  /// <summary>--apply without --project: nothing could gate the write.</summary>
  CRefuseNoProject = 'no-project';
  /// <summary>--apply with --no-compile: the gate is not optional.</summary>
  CRefuseNoCompile = 'no-compile';

type
  /// <summary>One occurrence, or one fact about the target, that stops the rewrite.</summary>
  TRenameRefusal = record
    /// <summary>One of the CRefuse* kinds.</summary>
    Kind: string;
    /// <summary>The file; '' when the refusal is about no one place.</summary>
    FilePath: string;
    /// <summary>1-based line; 0 when there is no place.</summary>
    Line: Integer;
    /// <summary>1-based character column; 0 when there is no place.</summary>
    Col: Integer;
    /// <summary>The reason, in words.</summary>
    Why: string;
  end;

  /// <summary>What the proof decided about every occurrence.</summary>
  TRenameProof = record
    /// <summary>The proved edits, character columns, sorted back to front per file.</summary>
    Edits: TArray<TRenameEdit>;
    /// <summary>What stops --apply; empty = every occurrence is decided.</summary>
    Refusals: TArray<TRenameRefusal>;
    /// <summary>Edits the resolver's binding decided.</summary>
    Bound: Integer;
    /// <summary>Unbound refs the receiver's static type decided (either way).</summary>
    Typed: Integer;
    /// <summary>Occurrences decided to be another symbol's, left alone.</summary>
    Other: Integer;
    /// <summary>The qualified names renamed together (overloads, overrides, implementers).</summary>
    Group: TArray<string>;
    /// <summary>False when the target is not in the index.</summary>
    Found: Boolean;
  end;

  /// <summary>How `rename --apply` builds.</summary>
  TRenameGateOptions = record
    /// <summary>The .dproj; required.</summary>
    Project: string;
    /// <summary>win32 / win64; '' = Win64.</summary>
    Platform: string;
    /// <summary>--rsvars; '' = the Studio the registry names.</summary>
    RsVars: string;
    /// <summary>--build-timeout in seconds; 0 = none.</summary>
    BuildTimeoutSecs: Integer;
    /// <summary>--no-backup.</summary>
    NoBackup: Boolean;
  end;

/// <summary>Proves a store-backed rename: every token of the old name becomes an edit, another symbol's, or a refusal;
/// every token of the new name is checked for capture.</summary>
/// <param name="pStore">The project's index, read-only use. A store that is not SQLite refuses.</param>
/// <param name="pLibraries">The platform libraries, read-only use; empty = none open.</param>
/// <param name="pQName">The target's qualified name. Its overloads, overrides and implementers rename with it.</param>
/// <param name="pNewName">The new name.</param>
/// <returns>The proof; Found = False when the target is not in the index.</returns>
/// <remarks>Reads every source file the index lists that holds either name. Writes nothing. Identity needs a
/// `type_symbol_id`: a NULL, a missing row or an unresolved ancestor is a refusal, never a guess. A chain that reaches a
/// library type ends there: a library class cannot descend from a project class (refused when the target's qualified
/// name is in the library too).</remarks>
function ProveRename(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pQName, pNewName: string): TRenameProof;

/// <summary>Proves a routine-local rename: BuildLocal's occurrences, plus the ones under a `with`, each decided by the
/// ref the resolver bound on that token, and a check that the routine does not already use the new name.</summary>
/// <param name="pStore">The index, or nil: without one an occurrence under a `with` refuses.</param>
/// <param name="pFile">The source file.</param>
/// <param name="pLine">1-based line of the declaration identifier.</param>
/// <param name="pCol">1-based column of the declaration identifier.</param>
/// <param name="pNewName">The new name.</param>
/// <returns>The proof; Found = False when no local is declared there.</returns>
function ProveLocalRename(const pStore: ISymbolStore; const pFile: string; pLine, pCol: Integer;
  const pNewName: string): TRenameProof;

/// <summary>One refusal as a line: `file:line:col: refused [kind]: why`.</summary>
/// <param name="pRefusal">The refusal.</param>
/// <returns>The line; the place is left out when there is none.</returns>
function RefusalLine(const pRefusal: TRenameRefusal): string;

/// <summary>The proof as text: the decided counts, then every refusal.</summary>
/// <param name="pProof">The proof.</param>
/// <param name="pQName">The target.</param>
/// <param name="pNewName">The new name.</param>
/// <returns>The plan, several lines.</returns>
function RenderRenamePlan(const pProof: TRenameProof; const pQName, pNewName: string): string;

/// <summary>The proof as a JSON object: target, to, edits, bound, typed, other, group, refusals.</summary>
/// <param name="pProof">The proof.</param>
/// <param name="pQName">The target.</param>
/// <param name="pNewName">The new name.</param>
/// <returns>The document.</returns>
function RenamePlanJson(const pProof: TRenameProof; const pQName, pNewName: string): string;

/// <summary>Writes proved edits through the compile gate: baseline build, all-or-nothing write, after build, rollback.</summary>
/// <param name="pEdits">The proved edits.</param>
/// <param name="pOpts">The project and how to build it.</param>
/// <returns>The gate's outcome; Applied, or a CGate* refusal with its detail. Never raises.</returns>
function ApplyRenameGated(const pEdits: TArray<TRenameEdit>; const pOpts: TRenameGateOptions): TGateOutcome;

/// <summary>The test seam of the rename guards older than the gate, whose fixtures do not compile:
/// DRAGLINT_RENAME_TEST_UNGATED=1 with every edit under %TEMP% / C:\TEMP.</summary>
/// <param name="pEdits">The edits about to be written.</param>
/// <returns>True when the caller may write without the gate.</returns>
function RenameUngatedSeam(const pEdits: TArray<TRenameEdit>): Boolean;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Math,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Data.DB,
  FireDAC.Comp.Client,
  TreeSitter,
  DRagLint.Diagnostics.ParseCache,
  DRagLint.Refactor.TextEdit,
  DRagLint.Storage.SQLite;

const
  CSeamVar        = 'DRAGLINT_RENAME_TEST_UNGATED';
  CCertain        = 'certain';
  CMaxChainDepth  = 64;
  CMsPerSec       = 1000;
  CKindEventBind  = 'event-binding';
  CKindParam      = 'param';
  CKindLocal      = 'local_var';
  CKindProperty   = 'property';
  CKindField      = 'field';
  CKindMethod     = 'method';
  CKindUnit       = 'unit';
  CKindClass      = 'class';
  CKindForm       = 'form';
  CKindInterface  = 'interface';
  CKindAlias      = 'type';
  CDirOverride    = 'override';
  CDirOverload    = 'overload';
  CRootClass      = 'TObject';
  CNotLocal       = '''' + CKindParam + ''', ''' + CKindLocal + '''';
  CTypeKinds      = '''class'', ''form'', ''interface'', ''record'', ''type'', ''object''';

type
  TSymRow = record
    Id, FileId, ParentId: Int64;
    Kind, Name, QName, Modifiers, Directives: string;
    Line, Col, ImplLine: Integer;
    VisExplicit: Boolean;
  end;

  TRefRow = record
    Id, FileId, SymbolId, Enclosing, ReceiverType: Int64;
    Kind, ReceiverText, ExternalTarget, Confidence: string;
    Line, Col: Integer;
    HasReceiverRow: Boolean;
  end;

  TChainVerdict = (cvTarget, cvOther, cvUndecided);

  TWithSpan = record
    StartLine, StartCol, EndLine, EndCol: Integer;
  end;

  { One identifier token of a source file. }
  TTok = record
    Path: string;
    FileId: Int64;
    Line, Col, ByteCol: Integer;
    Qualified: Boolean;
    Text: string;
    Start: Integer;
  end;

  TRefMap = TObjectDictionary<string, TList<TRefRow>>;
  TDeclMap = TDictionary<string, TSymRow>;

  { One proof run. Holds the two names' refs and symbols, the group, the class family and the per-file caches. }
  TProver = class // dl:ok god-class@2b0a -- one proof run: its readers and its caches are private to this unit and live one call // dl:ok high-response@2b0a -- the same: the response set is the SQL it reads
  private
    FStore     : ISymbolStore;
    FConn      : TFDConnection;
    FLibs      : TArray<TFDConnection>;
    FQName     : string;
    FOld       : string;
    FNew       : string;
    FHasFacts  : Boolean;
    FSeamNoLib : Boolean;
    FGroup     : TDictionary<Int64, TSymRow>;
    FStartCls  : TDictionary<Int64, Boolean>;
    FAncestors : TDictionary<Int64, Boolean>;
    FDescend   : TDictionary<Int64, Boolean>;
    FLibRoots  : TList<string>;
    FIsMember  : Boolean;
    FIsRoutineLocal: Boolean;
    FTargetInLib: Boolean;
    FOldSyms   : TArray<TSymRow>;
    FNewSyms   : TArray<TSymRow>;
    FOldRefs   : TRefMap;
    FNewRefs   : TRefMap;
    FSymCache  : TDictionary<Int64, TSymRow>;
    FWithCache : TDictionary<string, TArray<TWithSpan>>;
    FPropCache : TDictionary<Int64, TArray<TSymRow>>;
    FEdits     : TList<TRenameEdit>;
    FRefusals  : TList<TRenameRefusal>;
    FSeenRefuse: TDictionary<string, Boolean>;
    FBound     : Integer;
    FTyped     : Integer;
    FOther     : Integer;
    procedure Refuse(const pKind, pFile: string; pLine, pCol: Integer; const pWhy: string);
    procedure AddEdit(const pFile: string; pLine, pCol: Integer);
    function SymRow(pId: Int64): TSymRow;
    function ReadSyms(const pWhere: string; const pName: string): TArray<TSymRow>;
    function LoadRefs(const pName: string): TRefMap;
    function LibKindOf(const pName: string; out pKind: string): Boolean;
    function LibChainDeclares(const pStart, pName: string): Boolean;
    function LibHasUnitLevel(const pName: string): Boolean;
    function LibHasMember(const pName: string): Boolean;
    function LibHasQName(const pQName: string): Boolean;
    function LibAny(const pSql, pName: string): Boolean;
    function HelperDeclares(pType: Int64; const pName: string): Boolean;
    function Members(pType: Int64; const pName: string): TArray<TSymRow>;
    function FollowAlias(const pAlias: TSymRow; out pNext: Int64; out pKind, pWhy: string): TChainVerdict;
    function NextInChain(const pType: TSymRow; out pNext: Int64; out pKind, pWhy: string): TChainVerdict;
    function DecideChain(pType, pFromFile: Int64; out pKind, pWhy: string): TChainVerdict;
    function EnclosingClass(pSym: Int64): Int64;
    function InWith(const pPath: string; pLine, pByteCol: Integer): Boolean;
    function PropertyOwnerAt(pFileId: Int64; pLine: Integer): Int64;
    function IsSpecifierToken(const pText: string; pStart: Integer): Boolean;
    function DecideInherited(pFileId: Int64; pLine: Integer; out pKind, pWhy: string): TChainVerdict;
    function IsDeclArgName(const pPath: string; pLine, pByteCol: Integer): Boolean;
    function ChainMemberExists(pClass: Int64; const pName: string): Boolean;
    procedure BuildGroup;
    procedure BuildFamily;
    procedure CheckNewNameDeclarations;
    procedure AddDeclTokens(const pSyms: TArray<TSymRow>; pFileId: Int64; pLines: TStringList; pMap: TDeclMap);
    procedure TakeVerdict(const pTok: TTok; pVerdict: TChainVerdict; const pKind, pWhy: string);
    procedure ClassifyNoRef(const pTok: TTok);
    procedure ClassifyUnbound(const pTok: TTok; const pRow: TRefRow);
    procedure ClassifyOldToken(const pTok: TTok; pDecls: TDeclMap);
    procedure CheckBareSite(const pTok: TTok; const pRef: TRefRow);
    procedure ClassifyNewToken(const pTok: TTok; pDecls: TDeclMap);
    procedure ScanFile(pFileId: Int64; const pPath: string);
    procedure ProcessDfmRefs;
    procedure ScanDfmNames(const pPath, pText: string);
    procedure CheckDfmNames;
  public
    constructor Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pQName, pNewName: string);
    destructor Destroy; override;
    function Run: TRenameProof;
  end;

function KeyOf(pFileId: Int64; pLine, pCol: Integer): string;
begin
  Result:= Format('%d:%d:%d', [pFileId, pLine, pCol]);
end;

function IsSourceFile(const pPath: string): Boolean;
begin
  Result:= MatchText(ExtractFileExt(pPath), ['.pas', '.dpr', '.dpk', '.pp', '.lpr']);
end;

function IsClassKind(const pKind: string): Boolean;
begin
  Result:= MatchText(pKind, [CKindClass, CKindForm, CKindInterface, 'record', 'object']);
end;

function HasWord(const pHay, pWord: string): Boolean;
begin
  Result:= ContainsText(' ' + pHay.Replace(',', ' ').Replace(';', ' ') + ' ', ' ' + pWord + ' ');
end;

function ProofOf(pEdits: TList<TRenameEdit>; pRefusals: TList<TRenameRefusal>): TRenameProof;
var
  Comparer: IComparer<TRenameEdit>;
begin
  Result:= Default(TRenameProof);
  Comparer:= TComparer<TRenameEdit>.Construct(
    function(const pA, pB: TRenameEdit): Integer
    begin
      Result:= CompareText(pA.FilePath, pB.FilePath);
      if Result = 0 then Result:= pB.Line - pA.Line;
      if Result = 0 then Result:= pB.Col - pA.Col;
    end);
  pEdits.Sort(Comparer);
  { One position, one edit: two rows on one token would rewrite it twice. }
  for var I:= pEdits.Count - 1 downto 1 do
    if SameText(pEdits[I].FilePath, pEdits[I - 1].FilePath) and (pEdits[I].Line = pEdits[I - 1].Line) and (pEdits[I].Col = pEdits[I - 1].Col) then
      pEdits.Delete(I);
  Result.Edits:= pEdits.ToArray;
  Result.Refusals:= pRefusals.ToArray;
end;

// ---------------------------------------------------------------------------
// TProver: set-up and small readers
// ---------------------------------------------------------------------------

constructor TProver.Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pQName, pNewName: string);
begin
  inherited Create;
  FStore:= pStore;
  FQName:= pQName;
  FOld  := pQName.Substring(pQName.LastIndexOf('.') + 1);
  FNew  := pNewName;
  FConn := (pStore as TSQLiteSymbolStore).GetConnection;
  for var Lib in pLibraries do
    if Lib is TSQLiteSymbolStore then FLibs:= FLibs + [(Lib as TSQLiteSymbolStore).GetConnection];
  FGroup     := TDictionary<Int64, TSymRow>.Create;
  FStartCls  := TDictionary<Int64, Boolean>.Create;
  FAncestors := TDictionary<Int64, Boolean>.Create;
  FDescend   := TDictionary<Int64, Boolean>.Create;
  FLibRoots  := TList<string>.Create;
  FSymCache  := TDictionary<Int64, TSymRow>.Create;
  FWithCache := TDictionary<string, TArray<TWithSpan>>.Create;
  FPropCache := TDictionary<Int64, TArray<TSymRow>>.Create;
  FEdits     := TList<TRenameEdit>.Create;
  FRefusals  := TList<TRenameRefusal>.Create;
  FSeenRefuse:= TDictionary<string, Boolean>.Create;
end;

destructor TProver.Destroy;
begin
  FSeenRefuse.Free;
  FRefusals.Free;
  FEdits.Free;
  FPropCache.Free;
  FWithCache.Free;
  FSymCache.Free;
  FLibRoots.Free;
  FDescend.Free;
  FAncestors.Free;
  FStartCls.Free;
  FGroup.Free;
  FOldRefs.Free;
  FNewRefs.Free;
  inherited Destroy;
end;

procedure TProver.Refuse(const pKind, pFile: string; pLine, pCol: Integer; const pWhy: string);
var
  R: TRenameRefusal;
begin
  var Key:= pKind + '|' + UpperCase(pFile) + '|' + IntToStr(pLine) + '|' + IntToStr(pCol) + '|' + pWhy;
  if FSeenRefuse.ContainsKey(Key) then Exit;
  FSeenRefuse.Add(Key, True);
  R.Kind:= pKind;
  R.FilePath:= pFile;
  R.Line:= pLine;
  R.Col:= pCol;
  R.Why:= pWhy;
  FRefusals.Add(R);
end;

procedure TProver.AddEdit(const pFile: string; pLine, pCol: Integer);
var
  E: TRenameEdit;
begin
  E.FilePath:= pFile;
  E.Line:= pLine;
  E.Col:= pCol;
  E.OldName:= FOld;
  E.NewName:= FNew;
  FEdits.Add(E);
end;

function ReadSymRow(pQ: TFDQuery): TSymRow;
begin
  Result:= Default(TSymRow);
  Result.Id        := pQ.FieldByName('id').AsLargeInt;
  Result.FileId    := pQ.FieldByName('file_id').AsLargeInt;
  Result.ParentId  := pQ.FieldByName('parent_id').AsLargeInt;
  Result.Kind      := pQ.FieldByName('kind').AsString;
  Result.Name      := pQ.FieldByName('name').AsString;
  Result.QName     := pQ.FieldByName('qualified_name').AsString;
  Result.Modifiers := pQ.FieldByName('modifiers').AsString;
  Result.Directives:= pQ.FieldByName('directives').AsString;
  Result.Line      := pQ.FieldByName('start_line').AsInteger;
  Result.Col       := pQ.FieldByName('start_col').AsInteger;
  Result.ImplLine  := pQ.FieldByName('impl_start_line').AsInteger;
  Result.VisExplicit:= pQ.FieldByName('vis_explicit').AsInteger <> 0;
end;

const
  CSymCols = 'SELECT id, file_id, parent_id, kind, name, qualified_name, modifiers, directives, start_line, start_col, ' +
             'impl_start_line, vis_explicit FROM symbols WHERE ';

function TProver.SymRow(pId: Int64): TSymRow;
begin
  Result:= Default(TSymRow);
  if pId <= 0 then Exit;
  if FSymCache.TryGetValue(pId, Result) then Exit;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= CSymCols + 'id = :i';
    Q.ParamByName('i').AsLargeInt:= pId;
    Q.Open;
    if not Q.Eof then Result:= ReadSymRow(Q);
  finally
    Q.Free;
  end;
  FSymCache.AddOrSetValue(pId, Result);
end;

function TProver.ReadSyms(const pWhere: string; const pName: string): TArray<TSymRow>;
begin
  Result:= nil;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= CSymCols + pWhere;
    Q.ParamByName('n').AsWideString:= pName;
    Q.Open;
    while not Q.Eof do
    begin
      Result:= Result + [ReadSymRow(Q)];
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TProver.LoadRefs(const pName: string): TRefMap;
begin
  Result:= TRefMap.Create([doOwnsValues]);
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT r.id, r.file_id, r.symbol_id, r.enclosing_symbol_id, r.kind, r.receiver_text, r.external_target, ' +
                 'r.start_line, r.start_col, ce.confidence, ' +
                 (if FHasFacts then 'rr.receiver_ref_id, t.type_symbol_id ' else 'NULL AS receiver_ref_id, NULL AS type_symbol_id ') +
                 'FROM refs r LEFT JOIN call_edges ce ON ce.ref_id = r.id ' +
                 (if FHasFacts then 'LEFT JOIN ref_receivers rr ON rr.ref_id = r.id LEFT JOIN ref_types t ON t.ref_id = rr.receiver_ref_id ' else '') +
                 'WHERE r.name_text = :n COLLATE NOCASE';
    Q.ParamByName('n').AsWideString:= pName;
    Q.Open;
    var FId:= Q.FieldByName('id');
    var FFile:= Q.FieldByName('file_id');
    var FSym:= Q.FieldByName('symbol_id');
    var FEncl:= Q.FieldByName('enclosing_symbol_id');
    var FKind:= Q.FieldByName('kind');
    var FRcv:= Q.FieldByName('receiver_text');
    var FExt:= Q.FieldByName('external_target');
    var FConf:= Q.FieldByName('confidence');
    var FLine:= Q.FieldByName('start_line');
    var FCol:= Q.FieldByName('start_col');
    var FRcvRef:= Q.FieldByName('receiver_ref_id');
    var FRcvType:= Q.FieldByName('type_symbol_id');
    while not Q.Eof do
    begin
      var Row:= Default(TRefRow);
      Row.Id            := FId.AsLargeInt;
      Row.FileId        := FFile.AsLargeInt;
      Row.SymbolId      := FSym.AsLargeInt;
      Row.Enclosing     := FEncl.AsLargeInt;
      Row.Kind          := FKind.AsString;
      Row.ReceiverText  := FRcv.AsString;
      Row.ExternalTarget:= FExt.AsString;
      Row.Confidence    := FConf.AsString;
      Row.Line          := FLine.AsInteger;
      Row.Col           := FCol.AsInteger;
      Row.HasReceiverRow:= not FRcvRef.IsNull;
      Row.ReceiverType  := FRcvType.AsLargeInt;
      var Key:= KeyOf(Row.FileId, Row.Line, Row.Col);
      var Rows: TList<TRefRow>;
      if not Result.TryGetValue(Key, Rows) then
      begin
        Rows:= TList<TRefRow>.Create;
        Result.Add(Key, Rows);
      end;
      Rows.Add(Row);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TProver.LibKindOf(const pName: string; out pKind: string): Boolean;
begin
  Result:= False;
  pKind:= '';
  for var Conn in FLibs do
  begin
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= 'SELECT kind FROM symbols WHERE name = :n COLLATE NOCASE AND kind IN (' + CTypeKinds + ') LIMIT 1'; // dl:ok sql-injection-concat@62ce -- every concatenated part is a constant of this unit; the names are parameters
      Q.ParamByName('n').AsWideString:= pName;
      Q.Open;
      if not Q.Eof then
      begin
        pKind:= Q.Fields[0].AsString;
        Exit(True);
      end;
    finally
      Q.Free;
    end;
  end;
end;

function TProver.LibChainDeclares(const pStart, pName: string): Boolean;
begin
  Result:= False;
  for var Conn in FLibs do
  begin
    var Seen:= TDictionary<string, Boolean>.Create;
    var Q:= TFDQuery.Create(nil);
    var Work:= TQueue<string>.Create;
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= 'SELECT s.id, (SELECT COUNT(*) FROM symbols m WHERE m.parent_id = s.id AND m.name = :m COLLATE NOCASE) AS hits ' +
                   'FROM symbols s WHERE s.name = :n COLLATE NOCASE AND s.kind IN (' + CTypeKinds + ')';
      var QA:= TFDQuery.Create(nil);
      try
        QA.Connection:= Conn;
        QA.SQL.Text:= 'SELECT ancestor_name FROM type_ancestors WHERE symbol_id = :i';
        Work.Enqueue(pStart);
        while Work.Count > 0 do
        begin
          var Name:= Work.Dequeue;
          if Seen.ContainsKey(LowerCase(Name)) then Continue;
          Seen.Add(LowerCase(Name), True);
          Q.Close;
          Q.ParamByName('n').AsWideString:= Name;
          Q.ParamByName('m').AsWideString:= pName;
          Q.Open;
          while not Q.Eof do
          begin
            if Q.Fields[1].AsInteger > 0 then Exit(True);
            QA.Close;
            QA.ParamByName('i').AsLargeInt:= Q.Fields[0].AsLargeInt;
            QA.Open;
            while not QA.Eof do
            begin
              Work.Enqueue(QA.Fields[0].AsString);
              QA.Next;
            end;
            Q.Next;
          end;
        end;
      finally
        QA.Free;
      end;
    finally
      Work.Free;
      Q.Free;
      Seen.Free;
    end;
  end;
end;

function TProver.LibAny(const pSql, pName: string): Boolean;
begin
  Result:= False;
  for var Conn in FLibs do
  begin
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= pSql;
      Q.ParamByName('n').AsWideString:= pName;
      Q.Open;
      if not Q.Eof then Exit(True);
    finally
      Q.Free;
    end;
  end;
end;

function TProver.LibHasUnitLevel(const pName: string): Boolean;
begin
  Result:= LibAny('SELECT 1 FROM symbols s JOIN symbols p ON p.id = s.parent_id WHERE s.name = :n COLLATE NOCASE AND p.kind = ''' + CKindUnit + ''' LIMIT 1', pName); // dl:ok sql-injection-concat@fe89 -- every concatenated part is a constant of this unit; the names are parameters
end;

function TProver.LibHasMember(const pName: string): Boolean;
begin
  Result:= LibAny('SELECT 1 FROM symbols s JOIN symbols p ON p.id = s.parent_id WHERE s.name = :n COLLATE NOCASE AND p.kind IN (' + CTypeKinds + ') LIMIT 1', pName); // dl:ok sql-injection-concat@216c -- every concatenated part is a constant of this unit; the names are parameters
end;

function TProver.LibHasQName(const pQName: string): Boolean;
begin
  Result:= LibAny('SELECT 1 FROM symbols WHERE qualified_name = :n COLLATE NOCASE LIMIT 1', pQName);
end;

function TProver.HelperDeclares(pType: Int64; const pName: string): Boolean;
begin
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT 1 FROM type_helpers h JOIN symbols m ON m.parent_id = h.helper_symbol_id ' +
                 'WHERE h.target_symbol_id = :t AND m.name = :n COLLATE NOCASE LIMIT 1';
    Q.ParamByName('t').AsLargeInt:= pType;
    Q.ParamByName('n').AsWideString:= pName;
    Q.Open;
    Result:= not Q.Eof;
  finally
    Q.Free;
  end;
end;

function TProver.Members(pType: Int64; const pName: string): TArray<TSymRow>;
begin
  Result:= ReadSyms(Format('parent_id = %d AND name = :n COLLATE NOCASE AND kind NOT IN (%s)', [pType, CNotLocal]), pName);
end;

// ---------------------------------------------------------------------------
// The chain: which class answers to the old name, from a receiver's static type
// ---------------------------------------------------------------------------

function TProver.FollowAlias(const pAlias: TSymRow; out pNext: Int64; out pKind, pWhy: string): TChainVerdict;
begin
  pNext:= 0;
  pKind:= '';
  pWhy := '';
  var Sig:= '';
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT signature FROM symbols WHERE id = :i';
    Q.ParamByName('i').AsLargeInt:= pAlias.Id;
    Q.Open;
    if not Q.Eof then Sig:= Trim(Q.Fields[0].AsString);
  finally
    Q.Free;
  end;
  if Sig.StartsWith('^') then Sig:= Trim(Sig.Substring(1));
  var Lt:= Pos('<', Sig);
  var Head:= if Lt > 0 then Copy(Sig, 1, Lt - 1) else Sig;
  Head:= Head.Substring(Head.LastIndexOf('.') + 1);
  var Plain:= Head <> '';
  for var C in Head do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Plain:= False;
  var Followable:= Plain and not SameText(Head, pAlias.Name) and not ContainsText(Sig, ' ');
  if not Followable then
  begin
    pKind:= CRefuseReceiverUntyped;
    pWhy := Format('the receiver''s type %s is an alias of "%s", which no member lookup follows', [pAlias.Name, Sig]);
    Exit(cvUndecided);
  end;
  var Cands:= ReadSyms('name = :n COLLATE NOCASE AND kind IN (' + CTypeKinds + ')', Head);
  var LibKind: string;
  var InLib:= LibKindOf(Head, LibKind);
  if (Length(Cands) > 1) or ((Length(Cands) = 1) and InLib) then
  begin
    pKind:= CRefuseAmbiguousType;
    pWhy := Format('the alias %s names "%s", which means more than one type', [pAlias.Name, Head]);
    Exit(cvUndecided);
  end;
  if Length(Cands) = 1 then
  begin
    pNext:= Cands[0].Id;
    Exit(cvTarget); { cvTarget here: go on with pNext }
  end;
  if InLib then Exit(cvOther);
  pKind:= if Length(FLibs) = 0 then CRefuseNoLibrary else CRefuseUnresolvedAncestor;
  pWhy := Format('the alias %s names "%s", which neither index holds', [pAlias.Name, Head]);
  Result:= cvUndecided;
end;

function TProver.NextInChain(const pType: TSymRow; out pNext: Int64; out pKind, pWhy: string): TChainVerdict;
begin
  pNext:= 0;
  pKind:= '';
  pWhy := '';
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT ancestor_name, ancestor_kind, ancestor_symbol_id FROM type_ancestors WHERE symbol_id = :i ORDER BY ordinal LIMIT 1';
    Q.ParamByName('i').AsLargeInt:= pType.Id;
    Q.Open;
    if Q.Eof then Exit(cvOther); { the root of a project chain: only TObject above it }
    var AncId:= Q.FieldByName('ancestor_symbol_id').AsLargeInt;
    var AncName:= Q.FieldByName('ancestor_name').AsString;
    if AncId > 0 then
    begin
      if SameText(SymRow(AncId).Kind, CKindInterface) and not SameText(pType.Kind, CKindInterface) then Exit(cvOther);
      pNext:= AncId;
      Exit(cvTarget); { cvTarget here: go on with pNext }
    end;
    var LibKind: string;
    if LibKindOf(AncName, LibKind) then Exit(cvOther);
    pKind:= if Length(FLibs) = 0 then CRefuseNoLibrary else CRefuseUnresolvedAncestor;
    pWhy := Format('%s descends from %s, which %s', [pType.Name, AncName,
      if Length(FLibs) = 0 then 'only a library could name, and none is open' else 'neither index holds']);
    Result:= cvUndecided;
  finally
    Q.Free;
  end;
end;

function TProver.DecideChain(pType, pFromFile: Int64; out pKind, pWhy: string): TChainVerdict; // dl:ok too-many-exit-points@9753 -- a ladder of final verdicts: each Exit is one reason the walk stops
var
  FirstVerdict: TChainVerdict;
begin
  pKind:= '';
  pWhy := '';
  FirstVerdict:= cvOther;
  var Seen:= False;
  var Cur := pType;
  for var Depth:= 1 to CMaxChainDepth do
  begin
    var T:= SymRow(Cur);
    if T.Id = 0 then Break;
    var Next: Int64:= 0;
    var Step: TChainVerdict;
    if SameText(T.Kind, CKindAlias) then
    begin
      Step:= FollowAlias(T, Next, pKind, pWhy);
      if Step = cvUndecided then Exit(cvUndecided);
      if Step = cvOther then
      begin
        if Seen then
        begin
          pKind:= CRefuseOverloadSet;
          pWhy := Format('"%s" is overloaded and the chain goes on into the library', [FOld]);
          Exit(cvUndecided);
        end;
        if FTargetInLib then
        begin
          pKind:= CRefuseAmbiguousType;
          pWhy := Format('%s is in the library too, so a library chain does not rule it out', [FQName]);
          Exit(cvUndecided);
        end;
        Exit(cvOther);
      end;
      Cur:= Next;
      Continue;
    end;
    if HelperDeclares(T.Id, FOld) then
    begin
      pKind:= CRefuseHelperMember;
      pWhy := Format('a helper of %s declares "%s"', [T.Name, FOld]);
      Exit(cvUndecided);
    end;
    var Mems:= Members(T.Id, FOld);
    if Length(Mems) > 0 then
    begin
      if Seen then
      begin
        pKind:= CRefuseOverloadSet;
        pWhy := Format('"%s" is overloaded and declared on more than one level of the chain', [FOld]);
        Exit(cvUndecided);
      end;
      var AnyTarget:= False;
      var AnyOther := False;
      var Overload := False;
      for var M in Mems do
      begin
        if HasWord(M.Modifiers, 'strict') or
           ((HasWord(M.Modifiers, 'private') or HasWord(M.Modifiers, 'protected')) and (M.FileId <> pFromFile)) then
        begin
          pKind:= CRefuseInvisibleMember;
          pWhy := Format('%s is not visible from this unit, so the compiler looks further up the chain', [M.QName]);
          Exit(cvUndecided);
        end;
        if FGroup.ContainsKey(M.Id) then AnyTarget:= True else AnyOther:= True;
        if HasWord(M.Directives, CDirOverload) then Overload:= True;
      end;
      if AnyTarget and AnyOther then
      begin
        pKind:= CRefuseOverloadSet;
        pWhy := Format('%s declares "%s" more than once and only some of them are the target', [T.Name, FOld]);
        Exit(cvUndecided);
      end;
      FirstVerdict:= if AnyTarget then cvTarget else cvOther;
      if not Overload then Exit(FirstVerdict);
      Seen:= True;
    end;
    Step:= NextInChain(T, Next, pKind, pWhy);
    if Step = cvUndecided then
    begin
      if not Seen then Exit(cvUndecided);
      pKind:= CRefuseOverloadSet;
      pWhy := Format('"%s" is overloaded and the chain above %s is not known', [FOld, T.Name]);
      Exit(cvUndecided);
    end;
    if Step = cvOther then
    begin
      if Seen then
      begin
        Exit(FirstVerdict);
      end;
      if FTargetInLib then
      begin
        pKind:= CRefuseAmbiguousType;
        pWhy := Format('%s is in the library too, so a library chain does not rule it out', [FQName]);
        Exit(cvUndecided);
      end;
      Exit(cvOther);
    end;
    Cur:= Next;
  end;
  pKind:= CRefuseUnresolvedAncestor;
  pWhy := 'the receiver''s chain does not end';
  Result:= cvUndecided;
end;

function TProver.EnclosingClass(pSym: Int64): Int64;
begin
  Result:= 0;
  var Cur:= pSym;
  for var Depth:= 1 to CMaxChainDepth do
  begin
    var S:= SymRow(Cur);
    if S.Id = 0 then Exit;
    if IsClassKind(S.Kind) then Exit(S.Id);
    Cur:= S.ParentId;
  end;
end;

function TProver.InWith(const pPath: string; pLine, pByteCol: Integer): Boolean;
var
  Spans: TArray<TWithSpan>;

  procedure Collect(const pNode: TTSNode);
  begin
    if pNode.IsNull then Exit;
    if pNode.NodeType = 'with' then
    begin
      var S: TWithSpan;
      S.StartLine:= Integer(pNode.StartPoint.Row) + 1;
      S.StartCol := Integer(pNode.StartPoint.Column) + 1;
      S.EndLine  := Integer(pNode.EndPoint.Row) + 1;
      S.EndCol   := Integer(pNode.EndPoint.Column) + 1;
      Spans:= Spans + [S];
    end;
    for var I:= 0 to pNode.NamedChildCount - 1 do Collect(pNode.NamedChild(I));
  end;

begin
  var Key:= UpperCase(pPath);
  if not FWithCache.TryGetValue(Key, Spans) then
  begin
    Spans:= nil;
    var PF:= TAstParseCache.Get(pPath);
    if PF.Tree <> nil then Collect(PF.Tree.RootNode);
    FWithCache.Add(Key, Spans);
  end;
  Result:= False;
  for var S in Spans do
  begin
    var AtOrAfterStart:= (pLine > S.StartLine) or ((pLine = S.StartLine) and (pByteCol >= S.StartCol));
    var BeforeEnd     := (pLine < S.EndLine) or ((pLine = S.EndLine) and (pByteCol < S.EndCol));
    if AtOrAfterStart and BeforeEnd then Exit(True);
  end;
end;

function TProver.PropertyOwnerAt(pFileId: Int64; pLine: Integer): Int64;
var
  Props: TArray<TSymRow>;
begin
  Result:= 0;
  if not FPropCache.TryGetValue(pFileId, Props) then
  begin
    Props:= nil;
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= FConn;
      Q.SQL.Text:= 'SELECT parent_id, start_line, end_line FROM symbols WHERE file_id = :f AND kind = ''' + CKindProperty + ''''; // dl:ok sql-injection-concat@45a4 -- every concatenated part is a constant of this unit; the names are parameters
      Q.ParamByName('f').AsLargeInt:= pFileId;
      Q.Open;
      while not Q.Eof do
      begin
        var R:= Default(TSymRow);
        R.ParentId:= Q.Fields[0].AsLargeInt;
        R.Line:= Q.Fields[1].AsInteger;
        R.ImplLine:= Q.Fields[2].AsInteger; { the end line, in this cache }
        Props:= Props + [R];
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    FPropCache.Add(pFileId, Props);
  end;
  for var P in Props do
    if InRange(pLine, P.Line, P.ImplLine) then Exit(P.ParentId);
end;

{ True when the word before the token is a property specifier and the token is not behind a dot. }
function TProver.IsSpecifierToken(const pText: string; pStart: Integer): Boolean;
begin
  var P:= pStart - 1;
  while (P >= 1) and CharInSet(pText[P], [' ', #9, #13, #10]) do Dec(P);
  var E:= P;
  while (P >= 1) and CharInSet(pText[P], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(P);
  Result:= MatchText(Copy(pText, P + 1, E - P), ['read', 'write', 'stored']);
end;

{ True when the token names a parameter in a header the index keeps no symbol for (a procedural type, a forward header):
  a declaration binds to nothing. A token in the parameter's TYPE is not one. }
function TProver.IsDeclArgName(const pPath: string; pLine, pByteCol: Integer): Boolean;
var
  Found: Boolean;

  procedure Walk(const pNode, pParent: TTSNode);
  begin
    if Found or pNode.IsNull then Exit;
    var SL:= Integer(pNode.StartPoint.Row) + 1;
    var EL:= Integer(pNode.EndPoint.Row) + 1;
    if (pLine < SL) or (pLine > EL) then Exit;
    if (pNode.NodeType = 'identifier') and (SL = pLine) and (Integer(pNode.StartPoint.Column) + 1 = pByteCol) then
    begin
      if pParent.IsNull or (pParent.NodeType <> 'declArg') then Exit;
      var TypeNode:= pParent.ChildByField('type');
      Found:= TypeNode.IsNull or (pNode.StartByte < TypeNode.StartByte);
      Exit;
    end;
    for var I:= 0 to pNode.NamedChildCount - 1 do Walk(pNode.NamedChild(I), pNode);
  end;

begin
  Found:= False;
  var PF:= TAstParseCache.Get(pPath);
  if PF.Tree <> nil then Walk(PF.Tree.RootNode, Default(TTSNode));
  Result:= Found;
end;

{ `inherited Name` holds no ref: it names what the enclosing method's class's PARENT answers to. }
function TProver.DecideInherited(pFileId: Int64; pLine: Integer; out pKind, pWhy: string): TChainVerdict;
begin
  pKind:= CRefuseNoRefOccurrence;
  pWhy := 'an `inherited` call outside any method the index holds';
  Result:= cvUndecided;
  var Owner: Int64:= 0;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT parent_id FROM symbols WHERE file_id = :f AND impl_start_line <= :l AND impl_end_line >= :l ' +
                 'AND impl_start_line > 0 AND kind NOT IN (' + CNotLocal + ') ORDER BY impl_start_line DESC LIMIT 1';
    Q.ParamByName('f').AsLargeInt:= pFileId;
    Q.ParamByName('l').AsInteger:= pLine;
    Q.Open;
    if not Q.Eof then Owner:= Q.Fields[0].AsLargeInt;
  finally
    Q.Free;
  end;
  var OwnerRow:= SymRow(Owner);
  if not IsClassKind(OwnerRow.Kind) then Exit;
  var Next: Int64;
  case NextInChain(OwnerRow, Next, pKind, pWhy) of
    cvTarget: Result:= DecideChain(Next, pFileId, pKind, pWhy);
    cvOther: Result:= cvOther;
  end;
end;

function TProver.ChainMemberExists(pClass: Int64; const pName: string): Boolean;
begin
  Result:= False;
  var Cur:= pClass;
  for var Depth:= 1 to CMaxChainDepth do
  begin
    var T:= SymRow(Cur);
    if T.Id = 0 then Exit;
    if Length(Members(T.Id, pName)) > 0 then Exit(True);
    var Next: Int64;
    var K, W: string;
    var Step:= NextInChain(T, Next, K, W);
    if Step <> cvTarget then
    begin
      { above the project: ask the library when one is open }
      var Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= FConn;
        Q.SQL.Text:= 'SELECT ancestor_name FROM type_ancestors WHERE symbol_id = :i ORDER BY ordinal LIMIT 1';
        Q.ParamByName('i').AsLargeInt:= T.Id;
        Q.Open;
        var Root:= if Q.Eof then CRootClass else Q.Fields[0].AsString;
        Exit(LibChainDeclares(Root, pName) or ((Step = cvUndecided) and not FSeamNoLib));
      finally
        Q.Free;
      end;
    end;
    Cur:= Next;
  end;
end;

// ---------------------------------------------------------------------------
// The group and the family
// ---------------------------------------------------------------------------

procedure TProver.BuildGroup;
begin
  var Work:= TQueue<TSymRow>.Create;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT base_symbol_id, impl_symbol_id, confidence FROM dispatch_edges WHERE base_symbol_id = :i OR impl_symbol_id = :i';
    for var S in ReadSyms('qualified_name = :n COLLATE NOCASE', FQName) do
    begin
      FGroup.AddOrSetValue(S.Id, S);
      Work.Enqueue(S);
    end;
    while Work.Count > 0 do
    begin
      var S:= Work.Dequeue;
      var HasBase:= False;
      Q.Close;
      Q.ParamByName('i').AsLargeInt:= S.Id;
      Q.Open;
      while not Q.Eof do
      begin
        var Base:= Q.Fields[0].AsLargeInt;
        var Impl:= Q.Fields[1].AsLargeInt;
        if Impl = S.Id then HasBase:= True;
        var Peer:= SymRow(if Impl = S.Id then Base else Impl);
        if not SameText(Q.Fields[2].AsString, CCertain) then
          Refuse(CRefuseGroupUncertain, FStore.GetFilePath(Peer.FileId), Peer.Line, 0,
            Format('the dispatch edge between %s and %s is %s', [S.QName, Peer.QName, Q.Fields[2].AsString]));
        if not SameText(Peer.Name, FOld) then
          Refuse(CRefuseGroupNameDiffers, FStore.GetFilePath(Peer.FileId), Peer.Line, 0,
            Format('%s dispatches to %s, which has another name', [S.QName, Peer.QName]))
        else if not FGroup.ContainsKey(Peer.Id) then
        begin
          FGroup.Add(Peer.Id, Peer);
          Work.Enqueue(Peer);
        end;
        Q.Next;
      end;
      if HasWord(S.Directives, CDirOverride) and not HasBase then
        Refuse(CRefuseOverrideOfLibrary, FStore.GetFilePath(S.FileId), S.Line, 0,
          Format('%s overrides a method the index does not hold; its base cannot be renamed', [S.QName]));
    end;
  finally
    Q.Free;
    Work.Free;
  end;
end;

procedure TProver.BuildFamily;
begin
  var Up  := TQueue<Int64>.Create;
  var Down:= TQueue<Int64>.Create;
  var QUp := TFDQuery.Create(nil);
  var QDn := TFDQuery.Create(nil);
  try
    QUp.Connection:= FConn;
    QUp.SQL.Text:= 'SELECT ancestor_symbol_id, ancestor_name, ordinal FROM type_ancestors WHERE symbol_id = :i';
    QDn.Connection:= FConn;
    QDn.SQL.Text:= 'SELECT symbol_id FROM type_ancestors WHERE ancestor_symbol_id = :i';
    FIsRoutineLocal:= True;
    for var S in FGroup.Values do
    begin
      var Parent:= SymRow(S.ParentId);
      if IsClassKind(Parent.Kind) or SameText(Parent.Kind, CKindUnit) or (Parent.Id = 0) then FIsRoutineLocal:= False;
      if not IsClassKind(Parent.Kind) then Continue;
      FIsMember:= True;
      if not FStartCls.ContainsKey(Parent.Id) then
      begin
        FStartCls.Add(Parent.Id, True);
        Up.Enqueue(Parent.Id);
        Down.Enqueue(Parent.Id);
      end;
    end;
    while Up.Count > 0 do
    begin
      var Id:= Up.Dequeue;
      var Row:= SymRow(Id);
      if MatchText(Row.Kind, [CKindClass, CKindForm]) and not FLibRoots.Contains(CRootClass) then FLibRoots.Add(CRootClass);
      QUp.Close;
      QUp.ParamByName('i').AsLargeInt:= Id;
      QUp.Open;
      while not QUp.Eof do
      begin
        var Anc:= QUp.Fields[0].AsLargeInt;
        if Anc > 0 then
        begin
          if not FAncestors.ContainsKey(Anc) then
          begin
            FAncestors.Add(Anc, True);
            Up.Enqueue(Anc);
          end;
        end
        else if not FLibRoots.Contains(QUp.Fields[1].AsString) then
          FLibRoots.Add(QUp.Fields[1].AsString);
        QUp.Next;
      end;
    end;
    while Down.Count > 0 do
    begin
      var Id:= Down.Dequeue;
      QDn.Close;
      QDn.ParamByName('i').AsLargeInt:= Id;
      QDn.Open;
      while not QDn.Eof do
      begin
        var Kid:= QDn.Fields[0].AsLargeInt;
        if not FDescend.ContainsKey(Kid) then
        begin
          FDescend.Add(Kid, True);
          Down.Enqueue(Kid);
        end;
        QDn.Next;
      end;
    end;
  finally
    QDn.Free;
    QUp.Free;
    Down.Free;
    Up.Free;
  end;
end;

procedure TProver.CheckNewNameDeclarations;
begin
  var Path0:= '';
  for var S in FGroup.Values do
  begin
    Path0:= FStore.GetFilePath(S.FileId);
    Break;
  end;
  { The index holds no refs inside an include, so an occurrence of the new name there cannot be decided. }
  var IncReason:= TRenameRefactoring.IncludeUseReason(FStore, FNew);
  if IncReason <> '' then Refuse(CRefuseCaptureNoRef, Path0, 0, 0, 'the new name: ' + IncReason);
  for var S in FNewSyms do
  begin
    if MatchText(S.Kind, [CKindParam, CKindLocal]) then Continue;
    var P:= SymRow(S.ParentId);
    if FIsMember then
    begin
      if FStartCls.ContainsKey(P.Id) or FAncestors.ContainsKey(P.Id) or FDescend.ContainsKey(P.Id) then
        Refuse(CRefuseNewNameCollides, FStore.GetFilePath(S.FileId), S.Line, 0,
          Format('%s is in the renamed member''s class family: one would hide the other', [S.QName]));
    end
    else if SameText(P.Kind, CKindUnit) then
      Refuse(CRefuseNewNameCollides, FStore.GetFilePath(S.FileId), S.Line, 0,
        Format('%s is unit-level too: which one a bare name means depends on the uses order', [S.QName]));
  end;
  if (Length(FLibs) = 0) and not FSeamNoLib then
  begin
    Refuse(CRefuseNoLibrary, Path0, 0, 0, 'the proof that the new name meets nothing in the library needs the platform library: pass --library-db');
    Exit;
  end;
  if FIsMember then
  begin
    for var Root in FLibRoots do
      if LibChainDeclares(Root, FNew) then
        Refuse(CRefuseNewNameInLibrary, Path0, 0, 0, Format('the library class %s or an ancestor declares "%s"', [Root, FNew]));
  end
  else if LibHasUnitLevel(FNew) then
    Refuse(CRefuseNewNameInLibrary, Path0, 0, 0, Format('a library unit declares "%s" at unit level', [FNew]));
  { The members of each class's own implemented interfaces. }
  for var S in FGroup.Values do
    if SameText(S.Kind, CKindMethod) then
    begin
      var Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= FConn;
        Q.SQL.Text:= 'SELECT ancestor_name FROM type_ancestors WHERE symbol_id = :i AND ancestor_symbol_id IS NULL AND ordinal > 0';
        Q.ParamByName('i').AsLargeInt:= S.ParentId;
        Q.Open;
        while not Q.Eof do
        begin
          if (Length(FLibs) = 0) and not FSeamNoLib then
            Refuse(CRefuseImplementsUnindexed, FStore.GetFilePath(S.FileId), S.Line, 0,
              Format('%s implements %s, which no index holds', [SymRow(S.ParentId).Name, Q.Fields[0].AsString]))
          else if LibChainDeclares(Q.Fields[0].AsString, FOld) then
            Refuse(CRefuseImplementsUnindexed, FStore.GetFilePath(S.FileId), S.Line, 0,
              Format('%s implements %s, a library interface that declares "%s"', [SymRow(S.ParentId).Name, Q.Fields[0].AsString, FOld]));
          Q.Next;
        end;
      finally
        Q.Free;
      end;
    end;
end;

// ---------------------------------------------------------------------------
// The tokens
// ---------------------------------------------------------------------------

{ The token each symbol's declaration and implementation header sits on, per file: key 'line:charcol'. }
procedure TProver.AddDeclTokens(const pSyms: TArray<TSymRow>; pFileId: Int64; pLines: TStringList; pMap: TDeclMap);
begin
  for var S in pSyms do
  begin
    if S.FileId <> pFileId then Continue;
    if InRange(S.Line, 1, pLines.Count) then
    begin
      var L:= pLines[S.Line - 1];
      var C:= ByteColToCharCol(L, S.Col);
      if not IsIdentAt(L, S.Name, C) then C:= NameAfterDeclKeywords(L, S.Name, C);
      if C > 0 then pMap.AddOrSetValue(Format('%d:%d', [S.Line, C]), S);
    end;
    if (S.ImplLine > 0) and (S.ImplLine <> S.Line) and (S.ImplLine <= pLines.Count) then
    begin
      var L:= pLines[S.ImplLine - 1];
      var Hit:= 0;
      var At:= 1;
      while At <= Length(L) - Length(S.Name) + 1 do
      begin
        if IsIdentAt(L, S.Name, At) then
        begin
          if Hit = 0 then Hit:= At;
          if (At >= 2) and (L[At - 1] = '.') then
          begin
            Hit:= At;
            Break;
          end;
        end;
        Inc(At);
      end;
      if Hit > 0 then pMap.AddOrSetValue(Format('%d:%d', [S.ImplLine, Hit]), S);
    end;
  end;
end;

procedure TProver.CheckBareSite(const pTok: TTok; const pRef: TRefRow);
begin
  { A local or parameter of the enclosing routine, or of a routine around it, answers first. }
  var Cur:= pRef.Enclosing;
  for var Depth:= 1 to CMaxChainDepth do
  begin
    var Sc:= SymRow(Cur);
    if Sc.Id = 0 then Break;
    for var S in FNewSyms do
      if (S.ParentId = Sc.Id) and MatchText(S.Kind, [CKindParam, CKindLocal]) then
      begin
        Refuse(CRefuseShadowedAtSite, pTok.Path, pTok.Line, pTok.Col,
          Format('%s is in scope here: the renamed reference would bind to it, and that can compile', [S.QName]));
        Exit;
      end;
    Cur:= Sc.ParentId;
  end;
  { A unit-level target is met by a member of the enclosing class first. }
  if not FIsMember then
  begin
    var Cls:= EnclosingClass(pRef.Enclosing);
    if (Cls > 0) and ChainMemberExists(Cls, FNew) then
    begin
      Refuse(CRefuseShadowedAtSite, pTok.Path, pTok.Line, pTok.Col,
        Format('%s or an ancestor declares "%s": the renamed reference would bind to that member', [SymRow(Cls).QName, FNew]));
      Exit;
    end;
  end;
  if InWith(pTok.Path, pTok.Line, pTok.ByteCol) and
     ((Length(ReadSyms('name = :n COLLATE NOCASE AND kind NOT IN (' + CNotLocal + ')', FNew)) > 0) or LibHasMember(FNew)) then
    Refuse(CRefuseShadowedInWith, pTok.Path, pTok.Line, pTok.Col,
      Format('this site is inside a `with`, and a member named "%s" exists: its target may answer first', [FNew]));
end;

procedure TProver.TakeVerdict(const pTok: TTok; pVerdict: TChainVerdict; const pKind, pWhy: string);
begin
  case pVerdict of
    cvTarget:
    begin
      AddEdit(pTok.Path, pTok.Line, pTok.Col);
      Inc(FBound);
    end;
    cvOther: Inc(FOther);
    else Refuse(pKind, pTok.Path, pTok.Line, pTok.Col, pWhy);
  end;
end;

{ A token no ref sits on: a property's specifier, an `inherited` call and a parameter's declaration can still be decided. }
procedure TProver.ClassifyNoRef(const pTok: TTok);
const
  CInherited = 'inherited';
var
  Kind, Why: string;
begin
  var Owner:= PropertyOwnerAt(pTok.FileId, pTok.Line);
  if (Owner > 0) and not pTok.Qualified and IsSpecifierToken(pTok.Text, pTok.Start) then
  begin
    var V:= DecideChain(Owner, pTok.FileId, Kind, Why);
    TakeVerdict(pTok, V, Kind, 'a property specifier names "' + FOld + '": ' + Why);
    Exit;
  end;
  var Before:= pTok.Start - 1;
  while (Before >= 1) and CharInSet(pTok.Text[Before], [' ', #9, #13, #10]) do Dec(Before);
  if (Before >= Length(CInherited)) and SameText(Copy(pTok.Text, Before - Length(CInherited) + 1, Length(CInherited)), CInherited) then
  begin
    var V:= DecideInherited(pTok.FileId, pTok.Line, Kind, Why);
    TakeVerdict(pTok, V, Kind, '`inherited ' + FOld + '`: ' + Why);
    Exit;
  end;
  if IsDeclArgName(pTok.Path, pTok.Line, pTok.ByteCol) then
  begin
    Inc(FOther);
    Exit;
  end;
  Refuse(CRefuseNoRefOccurrence, pTok.Path, pTok.Line, pTok.Col,
    Format('"%s" sits here and the index holds no ref for it: an inactive {$IFDEF} branch, a chain the parse dropped, a field name in a record constant', [FOld]));
end;

{ Only unbound rows on the token: the receiver's static type decides, or nothing does. }
procedure TProver.ClassifyUnbound(const pTok: TTok; const pRow: TRefRow);
var
  Kind, Why: string;
begin
  { Nothing qualified can name a routine's local. }
  if FIsRoutineLocal and pTok.Qualified then
  begin
    Inc(FOther);
    Exit;
  end;
  var Prefix:= 'unresolved reference to "' + FOld + '" not renamed -- ';
  if not FHasFacts then
    Refuse(CRefuseNoFacts, pTok.Path, pTok.Line, pTok.Col, Prefix + 'the index predates ref_receivers: run index --resolve-only')
  else if pRow.ReceiverText = '' then
    Refuse(CRefuseBareUnbound, pTok.Path, pTok.Line, pTok.Col, Prefix + 'no receiver, and the resolver bound it to nothing')
  else if pRow.ReceiverType <= 0 then
    Refuse(CRefuseReceiverUntyped, pTok.Path, pTok.Line, pTok.Col,
      Prefix + Format('the receiver "%s" has no static type in the index', [pRow.ReceiverText]))
  else
  begin
    var Verdict:= DecideChain(pRow.ReceiverType, pTok.FileId, Kind, Why);
    case Verdict of
      cvTarget:
      begin
        AddEdit(pTok.Path, pTok.Line, pTok.Col);
        Inc(FTyped);
      end;
      cvOther:
      begin
        Inc(FTyped);
        Inc(FOther);
      end;
      else Refuse(Kind, pTok.Path, pTok.Line, pTok.Col, Prefix + Why);
    end;
  end;
end;

procedure TProver.ClassifyOldToken(const pTok: TTok; pDecls: TDeclMap);
var
  Rows: TList<TRefRow>;
  Decl: TSymRow;
begin
  { A declaration or an implementation header: the symbol's own token. }
  if pDecls.TryGetValue(Format('%d:%d', [pTok.Line, pTok.Col]), Decl) then
  begin
    if FGroup.ContainsKey(Decl.Id) then AddEdit(pTok.Path, pTok.Line, pTok.Col)
    else
    begin
      Inc(FOther);
      if SameText(Decl.Kind, CKindProperty) and FDescend.ContainsKey(Decl.ParentId) then
        Refuse(CRefuseRedeclaredProperty, pTok.Path, pTok.Line, pTok.Col, Format('%s republishes the property of the same name', [Decl.QName]));
    end;
    Exit;
  end;
  if not FOldRefs.TryGetValue(KeyOf(pTok.FileId, pTok.Line, pTok.ByteCol), Rows) then
  begin
    ClassifyNoRef(pTok);
    Exit;
  end;
  var ToTarget:= False;
  var ToOther := False;
  var LowConf := False;
  var UnboundRow: TRefRow:= Default(TRefRow);
  var BoundRow  : TRefRow:= Default(TRefRow);
  for var R in Rows do
    if R.SymbolId > 0 then
    begin
      if (R.Confidence <> '') and not SameText(R.Confidence, CCertain) then LowConf:= True;
      if FGroup.ContainsKey(R.SymbolId) then
      begin
        ToTarget:= True;
        BoundRow:= R;
      end
      else ToOther:= True;
    end
    else if R.ExternalTarget <> '' then ToOther:= True
    else UnboundRow:= R;
  if ToTarget and ToOther then
    Refuse(CRefuseConflictingBinding, pTok.Path, pTok.Line, pTok.Col, 'two refs on this token bind to the target and to another symbol')
  else if (ToTarget or ToOther) and LowConf then
    Refuse(CRefuseLowConfidence, pTok.Path, pTok.Line, pTok.Col, 'the resolver''s binding of this token is not certain')
  else if ToTarget then
  begin
    AddEdit(pTok.Path, pTok.Line, pTok.Col);
    Inc(FBound);
    if not pTok.Qualified then CheckBareSite(pTok, BoundRow);
  end
  else if ToOther then Inc(FOther)
  else ClassifyUnbound(pTok, UnboundRow);
end;

procedure TProver.ClassifyNewToken(const pTok: TTok; pDecls: TDeclMap);
var
  Rows: TList<TRefRow>;
begin
  if pDecls.ContainsKey(Format('%d:%d', [pTok.Line, pTok.Col])) then Exit;
  if not FNewRefs.TryGetValue(KeyOf(pTok.FileId, pTok.Line, pTok.ByteCol), Rows) then
  begin
    var Explained:= ((PropertyOwnerAt(pTok.FileId, pTok.Line) > 0) and IsSpecifierToken(pTok.Text, pTok.Start))
      or IsDeclArgName(pTok.Path, pTok.Line, pTok.ByteCol);
    if not Explained then
      Refuse(CRefuseCaptureNoRef, pTok.Path, pTok.Line, pTok.Col, Format('the new name "%s" sits here and the index holds no ref for it', [FNew]));
    Exit;
  end;
  if pTok.Qualified then
  begin
    for var R in Rows do
      if (R.SymbolId > 0) or (R.ExternalTarget <> '') then Exit;
    Refuse(CRefuseCaptureUnbound, pTok.Path, pTok.Line, pTok.Col,
      Format('"%s" here has a receiver nothing typed: it could become the renamed member', [FNew]));
    Exit;
  end;
  if InWith(pTok.Path, pTok.Line, pTok.ByteCol) then
  begin
    Refuse(CRefuseCaptureInWith, pTok.Path, pTok.Line, pTok.Col, Format('a bare "%s" inside a `with`: its target could answer after the rename', [FNew]));
    Exit;
  end;
  for var R in Rows do
  begin
    var S:= SymRow(R.SymbolId);
    if MatchText(S.Kind, [CKindParam, CKindLocal]) then Continue; { a nearer scope stays nearer }
    var BindsTo:= if S.Id > 0 then S.QName else 'something outside the index';
    if FIsMember then
    begin
      var Cls:= EnclosingClass(R.Enclosing);
      if FStartCls.ContainsKey(Cls) or FDescend.ContainsKey(Cls) then
        Refuse(CRefuseCaptureBare, pTok.Path, pTok.Line, pTok.Col,
          Format('this bare "%s" binds to %s; inside %s it would bind to the renamed member, and that can compile', [FNew, BindsTo, SymRow(Cls).QName]));
    end
    else if (S.Id = 0) or not IsClassKind(SymRow(S.ParentId).Kind) then
      Refuse(CRefuseCaptureBare, pTok.Path, pTok.Line, pTok.Col,
        Format('this bare "%s" binds to %s; a second unit-level "%s" makes the uses order decide', [FNew, BindsTo, FNew]));
  end;
end;

procedure TProver.ScanFile(pFileId: Int64; const pPath: string);
var
  Text: string;
begin
  if not TFile.Exists(pPath) then Exit;
  TTextFileFormat.ReadFile(pPath, Text);
  var HasOld:= ContainsText(Text, FOld);
  var HasNew:= ContainsText(Text, FNew);
  if not HasOld and not HasNew then Exit;
  var Lines:= TStringList.Create;
  var OldDecls:= TDeclMap.Create;
  var NewDecls:= TDeclMap.Create;
  try
    Lines.Text:= Text;
    AddDeclTokens(FOldSyms, pFileId, Lines, OldDecls);
    AddDeclTokens(FNewSyms, pFileId, Lines, NewDecls);
    var Len:= Length(Text);
    var I:= 1;
    var Line:= 1;
    var LineStart:= 1;

    { Moves the line count over [I, pTo). }
    var Advance:= procedure(pFrom, pTo: Integer)
      begin
        var K:= pFrom;
        while K < pTo do
        begin
          { CRLF counts once, whichever call sees which half: the LF of a CRLF only moves the line start. }
          if (Text[K] = #13) or ((Text[K] = #10) and ((K = 1) or (Text[K - 1] <> #13))) then Inc(Line);
          if (Text[K] = #13) or (Text[K] = #10) then LineStart:= K + 1;
          Inc(K);
        end;
      end;

    while I <= Len do
    begin
      var Next:= SkipNonIdent(Text, I);
      if Next > I then
      begin
        Advance(I, Next);
        I:= Next;
      end
      else if CharInSet(Text[I], ['A'..'Z', 'a'..'z', '_']) then
      begin
        var Start:= I;
        while (I <= Len) and CharInSet(Text[I], ['A'..'Z', 'a'..'z', '_', '0'..'9']) do Inc(I);
        var IsOld:= (I - Start = Length(FOld)) and SameText(Copy(Text, Start, I - Start), FOld);
        var IsNew:= (I - Start = Length(FNew)) and SameText(Copy(Text, Start, I - Start), FNew);
        if IsOld or IsNew then
        begin
          var Tok: TTok;
          Tok.Path   := pPath;
          Tok.FileId := pFileId;
          Tok.Line   := Line;
          Tok.Col    := Start - LineStart + 1;
          Tok.ByteCol:= TEncoding.UTF8.GetByteCount(Copy(Text, LineStart, Tok.Col - 1)) + 1;
          Tok.Text   := Text;
          Tok.Start  := Start;
          var P:= Start - 1;
          while (P >= 1) and CharInSet(Text[P], [' ', #9, #13, #10]) do Dec(P);
          Tok.Qualified:= (P >= 1) and (Text[P] = '.') and not ((P >= 2) and (Text[P - 1] = '.'));
          if IsOld then ClassifyOldToken(Tok, OldDecls)
          else ClassifyNewToken(Tok, NewDecls);
        end;
      end
      else
      begin
        Advance(I, I + 1);
        Inc(I);
      end;
    end;
  finally
    NewDecls.Free;
    OldDecls.Free;
    Lines.Free;
  end;
end;

{ Event bindings live in .dfm files: DfmBindingBelongsTo decides each, as Build does. }
procedure TProver.ProcessDfmRefs;
begin
  for var Rows in FOldRefs.Values do
    for var R in Rows do
    begin
      if not SameText(R.Kind, CKindEventBind) then Continue;
      if (R.SymbolId > 0) and not FGroup.ContainsKey(R.SymbolId) then
      begin
        Inc(FOther);
        Continue;
      end;
      var Path:= FStore.GetFilePath(R.FileId);
      var Mine:= False;
      for var S in FGroup.Values do
        if DfmBindingBelongsTo(FStore, Path, FStore.GetSymbolById(S.ParentId), FOld) then Mine:= True;
      if not Mine then
      begin
        Inc(FOther);
        Continue;
      end;
      var Text: string;
      TTextFileFormat.ReadFile(Path, Text);
      var Lines:= TStringList.Create;
      try
        Lines.Text:= Text;
        if (R.Line < 1) or (R.Line > Lines.Count) then Continue;
        AddEdit(Path, R.Line, ByteColToCharCol(Lines[R.Line - 1], R.Col));
        Inc(FBound);
      finally
        Lines.Free;
      end;
    end;
end;

procedure TProver.ScanDfmNames(const pPath, pText: string);
begin
  var Lines:= TStringList.Create;
  try
    Lines.Text:= pText;
    for var L:= 0 to Lines.Count - 1 do
    begin
      var S:= Lines[L];
      var At:= 1;
      var InStr:= False;
      while At <= Length(S) do
      begin
        if S[At] = '''' then InStr:= not InStr
        else if not InStr and IsIdentAt(S, FOld, At) then
        begin
          Refuse(CRefuseDfmNameUnbound, pPath, L + 1, At,
            Format('this form names "%s" (a component or a property value); nothing rewrites a form''s names', [FOld]));
          Break;
        end;
        Inc(At);
      end;
    end;
  finally
    Lines.Free;
  end;
end;

{ A published field or property named in a text form: nothing rewrites it, and a form that no longer loads is no compile
  error. Binary and unindexed forms: SkippedDfmNotes. }
procedure TProver.CheckDfmNames;
begin
  for var S in FGroup.Values do
    for var Note in TRenameRefactoring.SkippedDfmNotes(FStore, S.QName) do
      Refuse(CRefuseDfmNotRewritten, FStore.GetFilePath(S.FileId), S.Line, 0, Note);
  var Streamed:= False;
  for var S in FGroup.Values do
    if MatchText(S.Kind, [CKindField, CKindProperty]) and MatchText(SymRow(S.ParentId).Kind, [CKindClass, CKindForm])
       and (HasWord(S.Modifiers, 'published') or not S.VisExplicit) then Streamed:= True;
  if not Streamed then Exit;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT path FROM files';
    Q.Open;
    var Dfms:= TDictionary<string, Boolean>.Create;
    try
      while not Q.Eof do
      begin
        var Path:= Q.Fields[0].AsString;
        if SameText(ExtractFileExt(Path), '.dfm') then Dfms.AddOrSetValue(Path, True)
        else if SameText(ExtractFileExt(Path), '.pas') and TFile.Exists(ChangeFileExt(Path, '.dfm')) then
          Dfms.AddOrSetValue(ChangeFileExt(Path, '.dfm'), True);
        Q.Next;
      end;
      for var Path in Dfms.Keys do
      begin
        if not TFile.Exists(Path) then Continue;
        var Text: string;
        TTextFileFormat.ReadFile(Path, Text);
        if not ContainsText(Text, FOld) then Continue;
        ScanDfmNames(Path, Text);
      end;
    finally
      Dfms.Free;
    end;
  finally
    Q.Free;
  end;
end;

function TProver.Run: TRenameProof;
begin
  Result:= Default(TRenameProof);
  BuildGroup;
  if FGroup.Count = 0 then Exit;
  Result.Found:= True;
  for var S in FGroup.Values do
    if GetEnvironmentVariable(CSeamVar) = '1' then
      FSeamNoLib:= IsUnderTemp(FStore.GetFilePath(S.FileId));
  var Probe:= TFDQuery.Create(nil);
  try
    Probe.Connection:= FConn;
    Probe.SQL.Text:= 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = ''ref_receivers''';
    Probe.Open;
    FHasFacts:= not Probe.Eof;
  finally
    Probe.Free;
  end;
  BuildFamily;
  FTargetInLib:= LibHasQName(FQName);
  FOldSyms:= ReadSyms('name = :n COLLATE NOCASE', FOld);
  FNewSyms:= ReadSyms('name = :n COLLATE NOCASE', FNew);
  FOldRefs:= LoadRefs(FOld);
  FNewRefs:= LoadRefs(FNew);
  CheckNewNameDeclarations;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT id, path FROM files';
    Q.Open;
    while not Q.Eof do
    begin
      if IsSourceFile(Q.Fields[1].AsString) then ScanFile(Q.Fields[0].AsLargeInt, Q.Fields[1].AsString);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  ProcessDfmRefs;
  CheckDfmNames;
  Result:= ProofOf(FEdits, FRefusals);
  Result.Found:= True;
  Result.Bound:= FBound;
  Result.Typed:= FTyped;
  Result.Other:= FOther;
  for var S in FGroup.Values do Result.Group:= Result.Group + [S.QName];
end;

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

function ProveRename(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pQName, pNewName: string): TRenameProof;
begin
  if pStore is not TSQLiteSymbolStore then
  begin
    Result:= Default(TRenameProof);
    Result.Found:= True;
    var R: TRenameRefusal;
    R.Kind:= CRefuseNoFacts;
    R.FilePath:= '';
    R.Line:= 0;
    R.Col:= 0;
    R.Why:= 'the index is not a SQLite index';
    Result.Refusals:= [R];
    Exit;
  end;
  var Prover:= TProver.Create(pStore, pLibraries, pQName, pNewName);
  try
    Result:= Prover.Run;
  finally
    Prover.Free;
  end;
end;

function ProveLocalRename(const pStore: ISymbolStore; const pFile: string; pLine, pCol: Integer;
  const pNewName: string): TRenameProof;
var
  WithSites, NewSites: TArray<TRenameEdit>;
begin
  Result:= Default(TRenameProof);
  var Base:= TRenameRefactoring.BuildLocalScan(pFile, pLine, pCol, pNewName, WithSites, NewSites);
  Result.Found:= Length(Base) > 0;
  if not Result.Found then Exit;
  var Edits:= TList<TRenameEdit>.Create;
  var Refusals:= TList<TRenameRefusal>.Create;
  try
    Edits.AddRange(Base);
    Result.Bound:= Length(Base);

    var AddRefusal:= procedure(const pKind: string; const pAt: TRenameEdit; const pWhy: string)
      var
        R: TRenameRefusal;
      begin
        R.Kind:= pKind;
        R.FilePath:= pAt.FilePath;
        R.Line:= pAt.Line;
        R.Col:= pAt.Col;
        R.Why:= pWhy;
        Refusals.Add(R);
      end;

    for var Site in NewSites do
      AddRefusal(CRefuseCaptureLocal, Site, Format('the routine already uses "%s" here; it would bind to the renamed local, and that can compile', [pNewName]));
    if Length(WithSites) > 0 then
    begin
      if pStore is not TSQLiteSymbolStore then
        for var Site in WithSites do
          AddRefusal(CRefuseWithNeedsIndex, Site, 'an occurrence under a `with`: a target may declare the name; only the index can tell. Pass --db')
      else
      begin
        var Conn:= (pStore as TSQLiteSymbolStore).GetConnection;
        var Fid: Int64:= 0;
        var Target: Int64:= 0;
        var MemberNew: Boolean;
        var Q:= TFDQuery.Create(nil);
        try
          Q.Connection:= Conn;
          Q.SQL.Text:= 'SELECT id FROM files WHERE path = :p COLLATE NOCASE';
          Q.ParamByName('p').AsWideString:= ExpandFileName(pFile);
          Q.Open;
          if not Q.Eof then Fid:= Q.Fields[0].AsLargeInt;
          Q.Close;
          { the local's symbol: the row the declaration identifier sits on }
          Q.SQL.Text:= 'SELECT id FROM symbols WHERE file_id = :f AND name = :n COLLATE NOCASE AND kind IN (' + CNotLocal + ') AND start_line = :l'; // dl:ok sql-injection-concat@864f -- every concatenated part is a constant of this unit; the names are parameters
          Q.ParamByName('f').AsLargeInt:= Fid;
          Q.ParamByName('n').AsWideString:= WithSites[0].OldName;
          Q.ParamByName('l').AsInteger:= pLine;
          Q.Open;
          if not Q.Eof then Target:= Q.Fields[0].AsLargeInt;
          Q.Next;
          if not Q.Eof then Target:= 0; { two on the line: no identity }
          Q.Close;
          Q.SQL.Text:= 'SELECT 1 FROM symbols WHERE name = :n COLLATE NOCASE AND kind NOT IN (' + CNotLocal + ') LIMIT 1'; // dl:ok sql-injection-concat@9cf7 -- every concatenated part is a constant of this unit; the names are parameters
          Q.ParamByName('n').AsWideString:= pNewName;
          Q.Open;
          MemberNew:= not Q.Eof;
          Q.Close;
          Q.SQL.Text:= 'SELECT symbol_id FROM refs WHERE file_id = :f AND start_line = :l AND start_col = :c';
          Q.ParamByName('f').DataType:= ftLargeint;
          Q.ParamByName('l').DataType:= ftInteger;
          Q.ParamByName('c').DataType:= ftInteger;
          for var Site in WithSites do
          begin
            Q.Close;
            Q.ParamByName('f').AsLargeInt:= Fid;
            Q.ParamByName('l').AsInteger:= Site.Line;
            Q.ParamByName('c').AsInteger:= Site.Col;
            Q.Open;
            var ToTarget:= False;
            var ToOther := False;
            while not Q.Eof do
            begin
              var Sym:= Q.Fields[0].AsLargeInt;
              if (Sym > 0) and (Sym = Target) then ToTarget:= True
              else if Sym > 0 then ToOther:= True;
              Q.Next;
            end;
            if ToTarget and not ToOther then
            begin
              if MemberNew then
                AddRefusal(CRefuseShadowedInWith, Site, Format('this occurrence is inside a `with`, and a member named "%s" exists: its target may answer first', [pNewName]))
              else
              begin
                Edits.Add(Site);
                Inc(Result.Bound);
              end;
            end
            else if ToOther and not ToTarget then Inc(Result.Other)
            else
              AddRefusal(CRefuseWithUndecided, Site, 'an occurrence under a `with` the resolver did not bind: the target''s surface is not known');
          end;
        finally
          Q.Free;
        end;
      end;
    end;
    var Bound:= Result.Bound;
    var Other:= Result.Other;
    Result:= ProofOf(Edits, Refusals);
    Result.Bound:= Bound;
    Result.Other:= Other;
    Result.Found:= True;
  finally
    Refusals.Free;
    Edits.Free;
  end;
end;

function RefusalLine(const pRefusal: TRenameRefusal): string;
begin
  var Place:= '';
  if pRefusal.FilePath <> '' then
    Place:= if pRefusal.Line > 0 then Format('%s:%d:%d: ', [pRefusal.FilePath, pRefusal.Line, pRefusal.Col])
            else pRefusal.FilePath + ': ';
  Result:= Format('%srefused [%s]: %s', [Place, pRefusal.Kind, pRefusal.Why]);
end;

function RenderRenamePlan(const pProof: TRenameProof; const pQName, pNewName: string): string;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.AppendLine(Format('rename plan: %s -> %s', [pQName, pNewName]));
    if Length(pProof.Group) > 1 then
      SB.AppendLine('  renamed together: ' + string.Join(', ', pProof.Group));
    SB.AppendLine(Format('  decided: %d edit(s), %d by the resolver''s binding; %d unbound ref(s) decided by the receiver''s static type; %d occurrence(s) are another symbol''s',
      [Length(pProof.Edits), pProof.Bound, pProof.Typed, pProof.Other]));
    SB.AppendLine(Format('  undecided: %d', [Length(pProof.Refusals)]));
    for var R in pProof.Refusals do SB.AppendLine('  ' + RefusalLine(R));
    SB.Append(if Length(pProof.Refusals) = 0 then 'proved: --apply --project <X.dproj> writes it through the compile gate'
              else 'not proved: --apply refuses (exit 2)');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenamePlanJson(const pProof: TRenameProof; const pQName, pNewName: string): string;
begin
  var O:= TJSONObject.Create;
  try
    O.AddPair('target', pQName);
    O.AddPair('to', pNewName);
    O.AddPair('bound', TJSONNumber.Create(pProof.Bound));
    O.AddPair('typed', TJSONNumber.Create(pProof.Typed));
    O.AddPair('other', TJSONNumber.Create(pProof.Other));
    var G:= TJSONArray.Create;
    O.AddPair('group', G);
    for var Q in pProof.Group do G.Add(Q);
    var A:= TJSONArray.Create;
    O.AddPair('edits', A);
    for var E in pProof.Edits do
    begin
      var X:= TJSONObject.Create;
      X.AddPair('file', E.FilePath);
      X.AddPair('line', TJSONNumber.Create(E.Line));
      X.AddPair('col', TJSONNumber.Create(E.Col));
      A.AddElement(X);
    end;
    var B:= TJSONArray.Create;
    O.AddPair('refusals', B);
    for var R in pProof.Refusals do
    begin
      var X:= TJSONObject.Create;
      X.AddPair('kind', R.Kind);
      X.AddPair('file', R.FilePath);
      X.AddPair('line', TJSONNumber.Create(R.Line));
      X.AddPair('col', TJSONNumber.Create(R.Col));
      X.AddPair('why', R.Why);
      B.AddElement(X);
    end;
    Result:= O.ToJSON;
  finally
    O.Free;
  end;
end;

function ApplyRenameGated(const pEdits: TArray<TRenameEdit>; const pOpts: TRenameGateOptions): TGateOutcome;
var
  Req: TGateRequest;
begin
  Result:= Default(TGateOutcome);
  Req:= Default(TGateRequest);
  var ByFile:= TObjectDictionary<string, TList<TTextEdit>>.Create([doOwnsValues]);
  try
    try
      for var E in pEdits do
      begin
        var Rows: TList<TTextEdit>;
        if not ByFile.TryGetValue(E.FilePath, Rows) then
        begin
          Rows:= TList<TTextEdit>.Create;
          ByFile.Add(E.FilePath, Rows);
        end;
        var TE:= Default(TTextEdit);
        TE.FilePath  := E.FilePath;
        TE.Kind      := tekReplaceInLine;
        TE.Line      := E.Line;
        TE.Col       := E.Col;
        TE.EndCol    := E.Col + Length(E.OldName);
        TE.Text      := E.NewName;
        TE.ExpectText:= E.OldName;
        Rows.Add(TE);
      end;
      for var Pair in ByFile do
      begin
        var Text: string;
        var Fmt:= TTextFileFormat.ReadFile(Pair.Key, Text);
        var GF: TGateFile;
        GF.Path := ExpandFileName(Pair.Key);
        GF.Bytes:= Fmt.Encode(TTextEditApplier.ApplyToText(Pair.Key, Text, Pair.Value.ToArray));
        Req.Files:= Req.Files + [GF];
      end;
    except
      on Ex: Exception do
      begin
        Result.Refusal:= CGateWriteFailed;
        Result.Detail := 'the rewrite could not be computed: ' + Ex.Message + '; nothing written';
        Exit;
      end;
    end;
  finally
    ByFile.Free;
  end;
  GBuildTimeoutMs:= if pOpts.BuildTimeoutSecs <= 0 then INFINITE else Cardinal(pOpts.BuildTimeoutSecs) * CMsPerSec;
  Req.Project := ExpandFileName(pOpts.Project);
  Req.Platform:= pOpts.Platform;
  Req.Verb    := 'rename';
  Req.RsVars  := if pOpts.RsVars <> '' then ExpandFileName(pOpts.RsVars) else '';
  Req.NoBackup:= pOpts.NoBackup;
  Req.Header  := Format('[%s] rename --apply: %d edit(s)', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Length(pEdits)]);
  Req.LogDir  := FreshScratchName('_build');
  Result:= ApplyGated(Req);
  try
    if not GScratchCited and TDirectory.Exists(Req.LogDir) then TDirectory.Delete(Req.LogDir, True); // dl:ok taint-path-traversal@c08a -- LogDir is FreshScratchName's: a folder this run made under C:\TEMP
  except
    on EInOutError do Writeln(ErrOutput, 'drag-lint: note: scratch not deleted: ', Req.LogDir); // best effort: a locked log must not change the result
  end;
end;

function RenameUngatedSeam(const pEdits: TArray<TRenameEdit>): Boolean;
begin
  Result:= GetEnvironmentVariable(CSeamVar) = '1';
  if Result then
    for var E in pEdits do
      if not IsUnderTemp(E.FilePath) then Exit(False);
end;

end.
