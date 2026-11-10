unit DRagLint.Refactor.Unwith;

// ---------------------------------------------------------------------------
// `unwith`: removes a `with E do S` by writing `E.` before every bare identifier of S that E's member closure declares.
// Delphi resolves a bare name in a with body to the innermost with first, so prefixing exactly the closure's members
// reproduces the compiler's binding -- IF the closure is complete. Under-prefixing a member an outer symbol also names
// compiles and silently rebinds: dcc cannot catch it, so nothing here relies on the compile gate for that.
//
// THE PROOF, three independent answers per identifier:
//  1. before, static: the closure (type chain + ancestors + visible helpers) decides prefix or keep;
//  2. before, index: the ref the resolver bound at that position must agree, else `binding-conflict`;
//  3. after, index (--apply): the rewritten tree is re-indexed into a COPY of the DB and every ref of every rewritten
//     body must bind to what it bound before, else `rebind-after` and a byte-identical rollback. The gate's build
//     happens first; it proves the text compiles, this proves it means the same.
// And one thing the design note missed: `with` evaluates E ONCE, the rewrite N times, so E must also be STABLE across the
// body: a chain of locals / params / fields whose class-typed links nothing rebinds.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils,
  DRagLint.Core.Interfaces;

const
  /// <summary>The target's last link has no ref_types row: the index cannot type it.</summary>
  CUwNoTypeRow = 'no-type-row';
  /// <summary>F1 typed the target by text only (ambiguous, or a type outside this index).</summary>
  CUwNullType = 'null-type';
  /// <summary>The type is neither a class nor a record (interface, alias, pointer, ...).</summary>
  CUwTargetKind = 'unsupported-target-kind';
  /// <summary>An ancestor does not resolve in the project or the platform library.</summary>
  CUwUnresolvedAncestor = 'unresolved-ancestor';
  /// <summary>`with A, B do`.</summary>
  CUwMultipleTargets = 'multiple-targets';
  /// <summary>A function or method call as (a link of) the target.</summary>
  CUwTargetCall = 'target-call';
  /// <summary>`with TFoo.Create do`: needs a declared temporary.</summary>
  CUwTargetCtor = 'target-constructor';
  /// <summary>An indexer in the target.</summary>
  CUwTargetIndexer = 'target-indexer';
  /// <summary>A hard cast as the target, or an `as` whose right side is not one plain type name.</summary>
  CUwTargetCast = 'target-cast';
  /// <summary>`with X as T`: a call stands before the first use. The cast raises at with today; after the rewrite it would
  /// raise at the first use, with that call already made.</summary>
  CUwCastOrder = 'cast-after-side-effect';
  /// <summary>A property whose read names a method: a getter runs once under with, N times after.</summary>
  CUwTargetGetter = 'target-property-getter';
  /// <summary>Any other target expression (dereference, parentheses, ...).</summary>
  CUwTargetNotChain = 'target-not-chain';
  /// <summary>A link of the target the index did not bind.</summary>
  CUwTargetUnbound = 'target-unbound';
  /// <summary>A link that is no variable (a type, a unit, a const).</summary>
  CUwTargetNotVariable = 'target-not-variable';
  /// <summary>The body uses the target itself, or a prefix of it, other than as a receiver (assignment, argument, @).</summary>
  CUwTargetUsedBare = 'target-used-bare';
  /// <summary>A class-typed field or global of the target has a writer other than a constructor, destructor or unit
  /// section, or is passed as an argument: any call in the body might rebind it.</summary>
  CUwFieldReassigned = 'target-field-reassigned';
  /// <summary>A var or out parameter of class type: an alias of a slot a call can rebind.</summary>
  CUwVarParam = 'target-var-param';
  /// <summary>A conditional or include directive inside the statement: another configuration may use any name.</summary>
  CUwConditional = 'conditional-in-body';
  /// <summary>A conditional directive inside a project type of the chain: another configuration has other members.</summary>
  CUwClosureConditional = 'closure-conditional';
  /// <summary>An inner with: it goes first, the outer waits for the next index.</summary>
  CUwInnerFirst = 'inner-with-first';
  /// <summary>An anonymous method in the body: E would be read when it runs, not when with ran.</summary>
  CUwAnonymous = 'anonymous-method';
  /// <summary>Inline assembler in the body.</summary>
  CUwAsm = 'asm-in-body';
  /// <summary>An inline declaration in the body: it may shadow E's root or a member.</summary>
  CUwInlineDecl = 'inline-decl';
  /// <summary>A body name matches a member whose visibility here is not proved.</summary>
  CUwInvisible = 'invisible-member';
  /// <summary>A body name matches a nested type or its enum values: `E.Name` is not a rewrite of it.</summary>
  CUwNestedType = 'nested-type-member';
  /// <summary>A type-position name matches a member.</summary>
  CUwTypeName = 'type-name-member';
  /// <summary>Two helpers in scope for one type, and the body names a member of one.</summary>
  CUwHelperAmbiguous = 'helper-ambiguous';
  /// <summary>The resolver bound the name differently from what the closure says.</summary>
  CUwBindingConflict = 'binding-conflict';
  /// <summary>A comment or line break inside `with E do` that the removal would lose or mangle.</summary>
  CUwHeader = 'target-header';
  /// <summary>The parser reports an error in the statement.</summary>
  CUwParseError = 'parse-error';
  /// <summary>The DB holds no ref_types (it predates F1): reindex.</summary>
  CUwNoFacts = 'no-facts';
  /// <summary>The file changed after it was indexed.</summary>
  CUwStale = 'stale-file';
  /// <summary>The file's encoding does not round-trip, so a rewrite could change bytes outside the edits.</summary>
  CUwEncoding = 'encoding-roundtrip';
  /// <summary>--apply: after the rewrite a ref binds to something else; rolled back.</summary>
  CUwRebindAfter = 'rebind-after';
  /// <summary>--apply: the after-proof's re-index could not run; rolled back.</summary>
  CUwProofUnavailable = 'after-proof-unavailable';

type
  /// <summary>One bare identifier of a with body and what the plan does to it.</summary>
  TUnwithBinding = record
    /// <summary>1-based line in the current file.</summary>
    Line: Integer;
    /// <summary>1-based column.</summary>
    Col: Integer;
    /// <summary>The name as written.</summary>
    Name: string;
    /// <summary>True when it gets the target's prefix; False when it stays bare.</summary>
    Prefixed: Boolean;
    /// <summary>What the name binds to today, by the index; '' when the index has no binding (a keep with no ref, or a
    /// prefix proved by the closure alone).</summary>
    Before: string;
  end;

  /// <summary>The verdict on one with statement.</summary>
  TUnwithSite = record
    /// <summary>1-based line of `with`.</summary>
    Line: Integer;
    /// <summary>1-based column of `with`.</summary>
    Col: Integer;
    /// <summary>The target as written; '' when it spans lines.</summary>
    Target: string;
    /// <summary>The target's type, qualified, when known.</summary>
    TargetType: string;
    /// <summary>'' = candidate; else one of the CUw* kinds.</summary>
    Refusal: string;
    /// <summary>The refusal in words, naming the identifier or the file:line that decided it.</summary>
    Detail: string;
    /// <summary>Every bare identifier of the body (candidates only).</summary>
    Bindings: TArray<TUnwithBinding>;
  end;

  /// <summary>One ref of a rewritten body with its position after the rewrite and what it bound to before.</summary>
  TUnwithProofPoint = record
    /// <summary>Line before.</summary>
    OldLine: Integer;
    /// <summary>Column before.</summary>
    OldCol: Integer;
    /// <summary>Line after.</summary>
    NewLine: Integer;
    /// <summary>Column after.</summary>
    NewCol: Integer;
    /// <summary>The ref's name.</summary>
    Name: string;
    /// <summary>The binding before: 'QName|Signature', 'ext:Target' or ''.</summary>
    Before: string;
    /// <summary>True when the identifier gets a prefix (an unbound-before may bind after, to a closure member only).</summary>
    Prefixed: Boolean;
    /// <summary>The closure's QNames of the name, lower case, ';'-joined (Prefixed only).</summary>
    Members: string;
  end;

  /// <summary>The verdicts on one file and, when any is a candidate, the rewritten bytes.</summary>
  TUnwithFilePlan = record
    /// <summary>The file.</summary>
    FilePath: string;
    /// <summary>Its with statements, in source order.</summary>
    Sites: TArray<TUnwithSite>;
    /// <summary>The bytes the file is to hold; nil when no site is a candidate.</summary>
    NewBytes: TBytes;
    /// <summary>What --apply checks after the rewrite.</summary>
    Proof: TArray<TUnwithProofPoint>;
  end;

  /// <summary>What UnwithApply needs besides the plans.</summary>
  TUnwithApplyOptions = record
    /// <summary>The .dproj the gate builds and the after-proof indexes.</summary>
    Project: string;
    /// <summary>win32 / win64; '' = Win64.</summary>
    Platform: string;
    /// <summary>The project DB; only a copy of it is written.</summary>
    Db: string;
    /// <summary>--no-backup.</summary>
    NoBackup: Boolean;
  end;

  /// <summary>What UnwithApply did.</summary>
  TUnwithApplyResult = record
    /// <summary>True when the files are written, the project builds and every proof point held.</summary>
    Applied: Boolean;
    /// <summary>'' when Applied; a CGate* or CUw* kind otherwise.</summary>
    Refusal: string;
    /// <summary>One line for the user.</summary>
    Detail: string;
    /// <summary>True when the rollback itself failed: the project may be PARTLY changed.</summary>
    RollbackFailed: Boolean;
    /// <summary>The files written.</summary>
    Written: TArray<string>;
    /// <summary>The refs the after-proof compared.</summary>
    ProofPoints: Integer;
    /// <summary>The refs that bound elsewhere after the rewrite: `file:line:col name: before -> after`.</summary>
    Rebinds: TArray<string>;
  end;

/// <summary>Analyzes the with statements of one file: which are candidates, which refuse and why.</summary>
/// <param name="pStore">The project index; must hold the file with F1 facts.</param>
/// <param name="pLib">The platform library, for ancestors outside the project; nil = such an ancestor refuses.</param>
/// <param name="pFile">The file, absolute.</param>
/// <param name="pLine">Only the with on this line; 0 = all.</param>
/// <returns>The verdicts and, when any site is a candidate, the rewritten bytes. Writes nothing.</returns>
/// <remarks>Sound only with a complete member closure and a stable target; every doubt is a named refusal, never a guess.
/// A nested with is decided innermost-first: the outer one refuses (inner-with-first) until the next index.
/// Parses through TAstParseCache: the caller sets its preprocess profile.</remarks>
function UnwithPlanFile(const pStore, pLib: ISymbolStore; const pFile: string; pLine: Integer = 0): TUnwithFilePlan;

/// <summary>Writes the candidates of pPlans through the shared compile gate, then proves every binding unchanged.</summary>
/// <param name="pPlans">The plans; a plan with no NewBytes is skipped.</param>
/// <param name="pOpts">Project, platform, DB.</param>
/// <returns>What happened. Not Applied = every file is back byte-identical (unless RollbackFailed).</returns>
/// <remarks>Order: ApplyGated (baseline build, write under backups, after build); then a child `index --project` into a
/// copy of the DB under the gate's scratch; then each proof point is compared; any difference rolls back and refuses
/// rebind-after, which a compile gate alone can never see. The real DB is not written: reindex after a good apply.</remarks>
function UnwithApply(const pPlans: TArray<TUnwithFilePlan>; const pOpts: TUnwithApplyOptions): TUnwithApplyResult;

implementation

uses
  System.Classes, System.IOUtils, System.Math, System.StrUtils, System.Hash, System.Generics.Collections, System.Generics.Defaults,
  FireDAC.Comp.Client,
  TreeSitter,
  DRagLint.Core.Model, DRagLint.Core.FileTime,
  DRagLint.Diagnostics.ParseCache, DRagLint.Storage.SQLite,
  DRagLint.Refactor.TextEdit, DRagLint.Refactor.CompileGate;

const
  /// <summary>Test seam, project under %TEMP% / C:\TEMP only: the rewrite leaves this name bare although the closure
  /// says prefix. It makes the static side wrong on purpose, so the guard can watch the after-proof catch what the build
  /// cannot.</summary>
  CTestSkipPrefixVar = 'DRAGLINT_UNWITH_TEST_SKIP_PREFIX';
  CConditionals: array[0..6] of string = ('{$IF', '{$ELSE', '{$ENDIF', '(*$IF', '(*$ELSE', '{$I ', '{$INCLUDE');
  CBackslashLf = 10;
  CCr = 13;
  CSpace = 32;
  CTab = 9;
  CSemicolon = Ord(';');

type
  TRow = record
    SymbolId: Int64;
    Kind: string;
    Name: string;
    Target: string;     { 'QName|Signature', 'ext:Target', '' }
    HasTypeRow: Boolean;
    TypeSymbolId: Int64;
    TypeQName: string;
    Via: string;
  end;

  TRows = TDictionary<string, TRow>;

  TMember = record
    Id: Int64;
    FromLib: Boolean;
    QName: string;
    NestedType: Boolean;
    Invisible: string;  { '' = visible here; else the reason }
    HelperAmbiguous: Boolean;
  end;

  TClosure = class
  public
    Members: TDictionary<string, TArray<TMember>>;  // dl:ok public-field@7b90 -- REVIEWED 2026-11-05: a private implementation class of this unit, invisible outside it
    ChainIds: TDictionary<Int64, Boolean>;   { project-store ids of the chain and the visible helpers }  // dl:ok public-field@94b6 -- REVIEWED 2026-11-05: a private implementation class of this unit, invisible outside it
    Failure: string;  // dl:ok public-field@f7f8 -- REVIEWED 2026-11-05: a private implementation class of this unit, invisible outside it
    FailureKind: string;  // dl:ok public-field@a676 -- REVIEWED 2026-11-05: a private implementation class of this unit, invisible outside it
    constructor Create;
    destructor Destroy; override;
  end;

  TSplice = record
    Pos: Integer;
    DelLen: Integer;
    Ins: TBytes;
  end;

  TLink = record
    Text: string;
    Row: TRow;
    HasRow: Boolean;
  end;

  ERefuse = class(Exception)
  public
    Kind: string;  // dl:ok public-field@92af -- REVIEWED 2026-11-05: a private implementation class of this unit, invisible outside it
    constructor CreateKind(const pKind, pDetail: string);
  end;

  TAnalyzer = class  // dl:ok god-class@35c9, high-response@35c9 -- REVIEWED 2026-11-05: one analysis of one file sharing its position tables; private to this unit
  private
    FStore, FLib: ISymbolStore;
    FFile: string;
    FFileId: Int64;
    FSrc, FRaw: TBytes;
    FRows: TRows;
    FClosures: TObjectDictionary<Int64, TClosure>;
    FFileUses: TArray<string>;
    FLineStart: TArray<Integer>;
    FSplices: TList<TSplice>;
    FProof: TList<TUnwithProofPoint>;
    FProofOffsets: TList<Integer>;
    FSkipPrefix: string;
    FTypeSpanMemo: TDictionary<Int64, Boolean>;
    FWriterMemo: TDictionary<Int64, string>;
    function NodeStr(const N: TTSNode): string;
    function RowAt(const N: TTSNode; out pRow: TRow): Boolean;
    function KeyOf(const N: TTSNode): string;
    function Closure(pTypeId: Int64): TClosure;
    procedure BuildClosure(C: TClosure; pTypeId: Int64);
    function RawHas(pFrom, pTo: Integer; const pNeedle: string): Boolean;
    function OffsetOf(pLine, pCol: Integer): Integer;
    function TypeHasConditional(const S: TSymbol): Boolean;
    function FieldWriter(const pField: TSymbol; out pWhere: string): Boolean;
    function ArgumentUse(const pRef: TReference; out pWhere: string): Boolean;
    procedure CollectWiths(const N: TTSNode; L: TList<TTSNode>);
    procedure ScanStructure(const N: TTSNode);
    function TargetLinks(const E: TTSNode): TArray<TLink>;
    procedure CheckTargetStable(const pLinks: TArray<TLink>; pCast: Boolean; out pTypeId: Int64; out pTypeText: string);
    function CastType(const E: TTSNode): TSymbol;
    procedure CheckHeader(const W, E, Body: TTSNode);
    procedure VisitBody(const N: TTSNode; pInType: Boolean; pC: TClosure; const pLinks: TArray<TLink>;
      const pSite: TList<TUnwithBinding>; const pPrefixAt: TList<Integer>);
    function UsesTargetBare(const N: TTSNode; const pLinks: TArray<TLink>): Boolean;
    procedure AddBodySplices(const W, Body: TTSNode; const pPrefix: string; const pPrefixAt: TList<Integer>;
      const pRootBefore, pRootName: string; pRootLead: Integer);
    function TryUnwrap(const W, Body: TTSNode; out pSplices: TArray<TSplice>): Boolean;
    function AnalyzeSite(const W: TTSNode): TUnwithSite;
    procedure LoadRows;
    procedure Render(const pFmt: TTextFileFormat; var pPlan: TUnwithFilePlan);
  public
    constructor Create(const pStore, pLib: ISymbolStore; const pFile: string);
    destructor Destroy; override;
    function Run(pLine: Integer): TUnwithFilePlan;
  end;

constructor ERefuse.CreateKind(const pKind, pDetail: string);
begin
  inherited Create(pDetail);
  Kind:= pKind;
end;

constructor TClosure.Create;
begin
  inherited Create;
  Members:= TDictionary<string, TArray<TMember>>.Create;
  ChainIds:= TDictionary<Int64, Boolean>.Create;
end;

destructor TClosure.Destroy;
begin
  ChainIds.Free;
  Members.Free;
  inherited Destroy;
end;

procedure Refuse(const pKind, pDetail: string);
begin
  raise ERefuse.CreateKind(pKind, pDetail);
end;

function PosKey(pLine, pCol: Integer): string;
begin
  Result:= IntToStr(pLine) + ':' + IntToStr(pCol);
end;

/// <summary>True when pNew tells more than pOld about the same position: a binding, or the static type of the same binding.</summary>
function RowIsBetter(const pNew, pOld: TRow): Boolean;
begin
  if pOld.SymbolId <= 0 then
    Exit((pNew.SymbolId > 0) or ((pOld.Target = '') and (pNew.Target <> '')));
  Result:= (not pOld.HasTypeRow) and pNew.HasTypeRow and (pOld.SymbolId = pNew.SymbolId);
end;

/// <summary>The refs of one file by position, bound row preferred where two share one (`M.Free`: call + member-access).</summary>
procedure LoadRowsOf(const pStore: ISymbolStore; pFileId: Int64; pRows: TRows; out pHasFacts: Boolean);
var
  Q: TFDQuery;
begin
  pHasFacts:= False;
  if pStore is not TSQLiteSymbolStore then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= (pStore as TSQLiteSymbolStore).GetConnection;
    Q.SQL.Text:= 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = ''ref_types''';
    Q.Open;
    pHasFacts:= not Q.Eof;
    Q.Close;
    if not pHasFacts then Exit;
    Q.SQL.Text:= 'SELECT r.start_line, r.start_col, r.kind, r.name_text, r.symbol_id, s.qualified_name, s.signature, ' +
      'r.external_target, t.ref_id, t.type_symbol_id, t.type_qname, t.via ' +
      'FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id LEFT JOIN ref_types t ON t.ref_id = r.id ' +
      'WHERE r.file_id = :f';
    Q.ParamByName('f').AsLargeInt:= pFileId;
    Q.Open;
    while not Q.Eof do
    begin
      var R: TRow:= Default(TRow);
      R.Kind:= Q.FieldByName('kind').AsString;  // dl:ok field-by-name-in-loop@bdc2 -- REVIEWED 2026-11-05: row counts are one file's refs, a few thousand at most, and names beat twelve positional indexes
      R.Name:= Q.FieldByName('name_text').AsString;
      R.SymbolId:= Q.FieldByName('symbol_id').AsLargeInt;
      var Ext:= Q.FieldByName('external_target').AsString;
      if R.SymbolId > 0 then R.Target:= Q.FieldByName('qualified_name').AsString + '|' + Q.FieldByName('signature').AsString
      else if Ext <> '' then R.Target:= 'ext:' + Ext;
      R.HasTypeRow:= not Q.FieldByName('ref_id').IsNull;
      R.TypeSymbolId:= Q.FieldByName('type_symbol_id').AsLargeInt;
      R.TypeQName:= Q.FieldByName('type_qname').AsString;
      R.Via:= Q.FieldByName('via').AsString;
      var Key:= PosKey(Q.FieldByName('start_line').AsInteger, Q.FieldByName('start_col').AsInteger);
      var Old: TRow;
      if (not pRows.TryGetValue(Key, Old)) or RowIsBetter(R, Old) then pRows.AddOrSetValue(Key, R);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

{ TAnalyzer }

constructor TAnalyzer.Create(const pStore, pLib: ISymbolStore; const pFile: string);
begin
  inherited Create;
  FStore:= pStore;
  FLib:= pLib;
  FFile:= pFile;
  FRows:= TRows.Create;
  FClosures:= TObjectDictionary<Int64, TClosure>.Create([doOwnsValues]);
  FSplices:= TList<TSplice>.Create;
  FProof:= TList<TUnwithProofPoint>.Create;
  FProofOffsets:= TList<Integer>.Create;
  FTypeSpanMemo:= TDictionary<Int64, Boolean>.Create;
  FWriterMemo:= TDictionary<Int64, string>.Create;
end;

destructor TAnalyzer.Destroy;
begin
  FWriterMemo.Free;
  FTypeSpanMemo.Free;
  FProofOffsets.Free;
  FProof.Free;
  FSplices.Free;
  FClosures.Free;
  FRows.Free;
  inherited Destroy;
end;

function TAnalyzer.NodeStr(const N: TTSNode): string;
var
  B: TBytes;
begin
  if N.IsNull or (N.StartByte >= N.EndByte) then Exit('');
  SetLength(B, Integer(N.EndByte) - Integer(N.StartByte));
  Move(FSrc[N.StartByte], B[0], Length(B));
  Result:= TEncoding.UTF8.GetString(B);
end;

function TAnalyzer.KeyOf(const N: TTSNode): string;
begin
  var P:= N.StartPoint;
  Result:= PosKey(Integer(P.Row) + 1, Integer(P.Column) + 1);
end;

function TAnalyzer.RowAt(const N: TTSNode; out pRow: TRow): Boolean;
begin
  Result:= FRows.TryGetValue(KeyOf(N), pRow) and SameText(pRow.Name, Trim(NodeStr(N)));
end;

procedure TAnalyzer.LoadRows;
var
  Has: Boolean;
begin
  LoadRowsOf(FStore, FFileId, FRows, Has);
  if not Has then Refuse(CUwNoFacts, 'this DB holds no ref_types (F1): reindex it with this engine');
end;

function TAnalyzer.OffsetOf(pLine, pCol: Integer): Integer;
begin
  if (pLine < 1) or (pLine > Length(FLineStart)) then Exit(-1);
  Result:= FLineStart[pLine - 1] + pCol - 1;
end;

function TAnalyzer.RawHas(pFrom, pTo: Integer; const pNeedle: string): Boolean;
begin
  Result:= False;
  var Needle:= TEncoding.ASCII.GetBytes(pNeedle);
  for var I: Integer:= pFrom to pTo - Length(Needle) do
  begin
    var J:= 0;
    while (J < Length(Needle)) and (UpCase(Char(FRaw[I + J])) = UpCase(Char(Needle[J]))) do Inc(J);
    if J = Length(Needle) then Exit(True);
  end;
end;

{ ---- the closure ---- }

function TAnalyzer.TypeHasConditional(const S: TSymbol): Boolean;
begin
  if FTypeSpanMemo.TryGetValue(S.Id, Result) then Exit;
  Result:= False;
  var Path:= FStore.GetFilePath(S.FileId);
  if (Path <> '') and TFile.Exists(Path) and (S.EndLine >= S.StartLine) then
  begin
    var Lines:= TFile.ReadAllLines(Path, TEncoding.ANSI);
    for var I: Integer:= S.StartLine - 1 to S.EndLine - 1 do
      if (I >= 0) and (I < Length(Lines)) then
        for var C: string in CConditionals do
          if ContainsText(Lines[I], C) then Result:= True;
  end;
  FTypeSpanMemo.Add(S.Id, Result);
end;

procedure TAnalyzer.BuildClosure(C: TClosure; pTypeId: Int64);
var
  Visited: TDictionary<string, Boolean>;
  Chain: TList<TSymbol>;
  ChainLib: TList<Boolean>;

  function VisibilityProblem(const M: TSymbol; pFromLib: Boolean): string;
  begin
    Result:= '';
    var SameFile:= (not pFromLib) and (M.FileId = FFileId);
    if ContainsText(M.Modifiers, 'strict') then Result:= M.Modifiers
    else if ContainsText(M.Modifiers, 'private') and not SameFile then Result:= 'private of another unit'
    else if ContainsText(M.Modifiers, 'protected') and not SameFile then Result:= 'protected of another unit';
  end;

  procedure AddMember(const M: TSymbol; pFromLib, pNested, pHelperAmbiguous: Boolean);
  var
    Arr: TArray<TMember>;
    One: TMember;
  begin
    if M.Name = '' then Exit;
    One:= Default(TMember);
    One.Id:= M.Id;
    One.FromLib:= pFromLib;
    One.QName:= M.QualifiedName;
    One.NestedType:= pNested;
    One.Invisible:= VisibilityProblem(M, pFromLib);
    One.HelperAmbiguous:= pHelperAmbiguous;
    if not C.Members.TryGetValue(LowerCase(M.Name), Arr) then Arr:= nil;
    C.Members.AddOrSetValue(LowerCase(M.Name), Arr + [One]);
  end;

  procedure AddMembersOf(const S: ISymbolStore; pId: Int64; pFromLib, pHelperAmbiguous: Boolean);
  begin
    for var M: TSymbol in S.FindAllChildSymbols(pId) do
    begin
      if M.Kind in [skParam, skLocalVar] then Continue;
      if M.Kind in [skClass, skRecord, skEnum, skInterface, skTypeAlias] then
      begin
        AddMember(M, pFromLib, True, pHelperAmbiguous);
        if M.Kind = skEnum then
          for var V: TSymbol in S.FindAllChildSymbols(M.Id) do AddMember(V, pFromLib, True, pHelperAmbiguous);
      end
      else
        AddMember(M, pFromLib, False, pHelperAmbiguous);
    end;
  end;

  function FindLibClass(const pName: string; const pUsesOfFile: Int64): TSymbol;
  begin
    Result:= Default(TSymbol);
    if FLib = nil then Exit;
    var Cands: TArray<TSymbol>:= nil;
    for var L: TSymbol in FLib.FindSymbolsByExactName(pName) do
      if (L.Kind = skClass) and not L.IsHelper then Cands:= Cands + [L];
    if Length(Cands) > 1 then
    begin
      var Uses1: TArray<TSymbol>:= nil;
      for var L: TSymbol in Cands do
        for var U: TUnitUse in FStore.GetUnitUsesForFile(pUsesOfFile) do
          if StartsText(U.UnitName + '.', L.QualifiedName) or ContainsText(L.QualifiedName, '.' + U.UnitName + '.') then
          begin
            Uses1:= Uses1 + [L];
            Break;
          end;
      Cands:= Uses1;
    end;
    if Length(Cands) = 1 then Result:= Cands[0];
  end;

  procedure Visit(const S: ISymbolStore; const Y: TSymbol; pFromLib: Boolean);
  begin
    var Key:= IfThen(pFromLib, 'L', 'P') + IntToStr(Y.Id);
    if Visited.ContainsKey(Key) then Exit;
    Visited.Add(Key, True);
    Chain.Add(Y);
    ChainLib.Add(pFromLib);
    if not pFromLib then
    begin
      C.ChainIds.AddOrSetValue(Y.Id, True);
      if TypeHasConditional(Y) then
      begin
        C.FailureKind:= CUwClosureConditional;
        C.Failure:= Format('%s has a conditional directive in its declaration (%s:%d): another configuration has other members',
          [Y.QualifiedName, ExtractFileName(FStore.GetFilePath(Y.FileId)), Y.StartLine]);
      end;
    end;
    AddMembersOf(S, Y.Id, pFromLib, False);
    for var A: TTypeAncestor in S.GetTransitiveAncestors(Y.Id) do
    begin
      if SameText(A.Kind, 'interface') then Continue;
      if A.Resolved and (A.SymbolId > 0) then
      begin
        var AS1:= S.GetSymbolById(A.SymbolId);
        if AS1.Kind = skClass then Visit(S, AS1, pFromLib);
        Continue;
      end;
      { THE BRIDGE: the project index stops at a library class. By name, unique among the classes the declaring unit
        can see; a guess between two is a refusal. An unresolved interface is harmless, but nothing tells it from a
        class here unless the library holds it. }
      if not pFromLib then
      begin
        var L:= FindLibClass(A.Name, Y.FileId);
        if L.Id > 0 then
        begin
          Visit(FLib, L, True);
          Continue;
        end;
        if (FLib <> nil) then
        begin
          var IsIface:= False;
          for var LI: TSymbol in FLib.FindSymbolsByExactName(A.Name) do
            if LI.Kind = skInterface then IsIface:= True;
          if IsIface then Continue;
        end;
      end;
      C.FailureKind:= CUwUnresolvedAncestor;
      C.Failure:= Format('%s: ancestor %s does not resolve%s, it may declare anything',
        [Y.QualifiedName, A.Name, IfThen(FLib = nil, ' (no platform library)')]);
    end;
  end;

  procedure AddHelpers;
  var
    Vis: TList<TSymbol>;
    VisLib: TList<Boolean>;
    UsedLc: TDictionary<string, Boolean>;

    { A helper is active only where its unit is used directly (or it is declared right here). }
    procedure Offer(const S: ISymbolStore; const E: THelperEdge; pLibSide: Boolean);
    begin
      var H:= S.GetSymbolById(E.HelperSymbolId);
      if H.Id <= 0 then Exit;
      for var V: TSymbol in Vis do
        if V.Id = H.Id then Exit;
      var HFile:= ChangeFileExt(ExtractFileName(S.GetFilePath(H.FileId)), '');
      var Seen:= (not pLibSide) and (H.FileId = FFileId);
      if not Seen then
        for var Lc: string in UsedLc.Keys do
          if SameText(Lc, HFile) or EndsText('.' + Lc, HFile) then Seen:= True;
      if Seen then
      begin
        Vis.Add(H);
        VisLib.Add(pLibSide);
      end;
    end;

  begin
    UsedLc:= TDictionary<string, Boolean>.Create;
    try
      for var U: string in FFileUses do UsedLc.AddOrSetValue(LowerCase(U), True);
      for var I: Integer:= 0 to Chain.Count - 1 do
      begin
        Vis:= TList<TSymbol>.Create;
        VisLib:= TList<Boolean>.Create;
        try
          var Tgt:= Chain[I];
          if ChainLib[I] then
          begin
            for var E: THelperEdge in FLib.FindHelpersOfTypeSymbol(Tgt.Id) do Offer(FLib, E, True);
            for var E: THelperEdge in FStore.FindHelpersOfType(Tgt.Name) do Offer(FStore, E, False);
          end
          else
            for var E: THelperEdge in FStore.FindHelpersOfType(Tgt.Name) do
              if (E.TargetSymbolId = Tgt.Id) or (E.TargetSymbolId <= 0) then Offer(FStore, E, False);
          for var H: Integer:= 0 to Vis.Count - 1 do
          begin
            if not VisLib[H] then C.ChainIds.AddOrSetValue(Vis[H].Id, True);
            AddMembersOf(if VisLib[H] then FLib else FStore, Vis[H].Id, VisLib[H], Vis.Count > 1);
          end;
        finally
          VisLib.Free;
          Vis.Free;
        end;
      end;
    finally
      UsedLc.Free;
    end;
  end;

begin
  Visited:= TDictionary<string, Boolean>.Create;
  Chain:= TList<TSymbol>.Create;
  ChainLib:= TList<Boolean>.Create;
  try
    var T:= FStore.GetSymbolById(pTypeId);
    Visit(FStore, T, False);
    { Every class ends at TObject, and its members are bare names like any other (`Free`, `ClassName`). }
    if (C.Failure = '') and (T.Kind = skClass) and not Visited.ContainsKey('LTObject') then
    begin
      var HasRoot:= False;
      for var Y: TSymbol in Chain do
        if SameText(Y.Name, 'TObject') then HasRoot:= True;
      if not HasRoot then
      begin
        var Root:= FindLibClass('TObject', T.FileId);
        if Root.Id > 0 then Visit(FLib, Root, True)
        else
        begin
          C.FailureKind:= CUwUnresolvedAncestor;
          C.Failure:= T.QualifiedName + ': TObject''s members are not known (no platform library)';
        end;
      end;
    end;
    if C.Failure = '' then AddHelpers;
  finally
    ChainLib.Free;
    Chain.Free;
    Visited.Free;
  end;
end;

function TAnalyzer.Closure(pTypeId: Int64): TClosure;
begin
  if FClosures.TryGetValue(pTypeId, Result) then Exit;
  Result:= TClosure.Create;
  FClosures.Add(pTypeId, Result);
  BuildClosure(Result, pTypeId);
end;

{ ---- the target ---- }

function TAnalyzer.TargetLinks(const E: TTSNode): TArray<TLink>;

  procedure Add(const N: TTSNode);
  var
    L: TLink;
  begin
    L:= Default(TLink);
    L.Text:= Trim(NodeStr(N));
    L.HasRow:= RowAt(N, L.Row);
    Result:= Result + [L];
  end;

  procedure Chain(const N: TTSNode);
  var
    NT: string;
  begin
    NT:= N.NodeType;
    if NT = 'identifier' then Add(N)
    else if NT = 'exprDot' then
    begin
      Chain(N.ChildByField('lhs'));
      var R:= N.ChildByField('rhs');
      if R.NodeType <> 'identifier' then Refuse(CUwTargetNotChain, 'target ' + NodeStr(E));
      if SameText(Trim(NodeStr(R)), 'Create') then
        Refuse(CUwTargetCtor, 'target ' + NodeStr(E) + ': needs a declared temporary');
      Add(R);
    end
    else if NT = 'exprCall' then
    begin
      var Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') and SameText(Trim(NodeStr(Ent.ChildByField('rhs'))), 'Create') then
        Refuse(CUwTargetCtor, 'target ' + NodeStr(E) + ': needs a declared temporary');
      { `TFoo(x)` parses as a call too: the bound symbol tells the cast from the call. }
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then
      begin
        var Rw: TRow;
        if RowAt(Ent, Rw) and ((Rw.Via = 'cast') or ((Rw.SymbolId > 0) and (FStore.GetSymbolById(Rw.SymbolId).Kind in [skClass, skRecord, skInterface, skTypeAlias]))) then
          Refuse(CUwTargetCast, 'target ' + NodeStr(E));
      end;
      Refuse(CUwTargetCall, 'target ' + NodeStr(E) + ': evaluated once by with, N times after');
    end
    else if (NT = 'exprSubscript') or (NT = 'exprBrackets') or (NT = 'exprIndex') then
      Refuse(CUwTargetIndexer, 'target ' + NodeStr(E))
    else if NT = 'exprBinary' then
      Refuse(CUwTargetNotChain, 'target ' + NodeStr(E))
    else
      Refuse(CUwTargetNotChain, 'target ' + NodeStr(E) + ' (' + NT + ')');
  end;

begin
  Result:= nil;
  Chain(E);
end;

function TAnalyzer.ArgumentUse(const pRef: TReference; out pWhere: string): Boolean;
var
  Lines: TArray<string>;
begin
  Result:= False;
  pWhere:= '';
  var Path:= FStore.GetFilePath(pRef.FileId);
  if (Path = '') or not TFile.Exists(Path) then Exit;
  Lines:= TFile.ReadAllLines(Path, TEncoding.ANSI);
  if (pRef.StartLine < 1) or (pRef.StartLine > Length(Lines)) then Exit;
  var Ln:= Lines[pRef.StartLine - 1];
  var Before:= TrimRight(Copy(Ln, 1, pRef.StartCol - 1));
  var After:= TrimLeft(Copy(Ln, pRef.StartCol + Length(pRef.NameText), MaxInt));
  { The ref's own receiver may stand before it (`Self.FX`, `pOwner.FX`): the receiver's left side decides. }
  if (Before <> '') and (Before[Length(Before)] = '.') then
  begin
    var P:= Length(Before) - 1;
    while (P > 0) and CharInSet(Before[P], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Dec(P);
    Before:= TrimRight(Copy(Before, 1, P));
  end;
  if (Before <> '') and (Before[Length(Before)] = '@') then Result:= True;
  if (Before <> '') and CharInSet(Before[Length(Before)], ['(', ',']) and
     ((After = '') or CharInSet(After[1], [')', ','])) then Result:= True;
  if Result then pWhere:= Format('%s:%d', [ExtractFileName(Path), pRef.StartLine]);
end;

function TAnalyzer.FieldWriter(const pField: TSymbol; out pWhere: string): Boolean;

  function Allowed(pEnclosing: Int64): Boolean;
  begin
    if pEnclosing <= 0 then Exit(False);
    var Enc:= FStore.GetSymbolById(pEnclosing);
    Result:= Enc.Kind in [skConstructor, skDestructor, skInitialization, skFinalization];
  end;

var
  Q: TFDQuery;
begin
  if FWriterMemo.TryGetValue(pField.Id, pWhere) then Exit(pWhere <> '');
  pWhere:= '';
  { A direct write: refs.kind = 'write' for a bare one, member_accesses.mode for a qualified one. }
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= (FStore as TSQLiteSymbolStore).GetConnection;
    Q.SQL.Text:= 'SELECT r.file_id, r.start_line, r.enclosing_symbol_id FROM refs r ' +
      'LEFT JOIN member_accesses m ON m.ref_id = r.id WHERE r.symbol_id = :s AND (r.kind = ''write'' OR m.mode = ''write'')';
    Q.ParamByName('s').AsLargeInt:= pField.Id;
    Q.Open;
    while (pWhere = '') and not Q.Eof do
    begin
      if not Allowed(Q.Fields[2].AsLargeInt) then
        pWhere:= Format('written at %s:%d', [ExtractFileName(FStore.GetFilePath(Q.Fields[0].AsLargeInt)), Q.Fields[1].AsInteger]);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  { An argument or @: a var parameter or a pointer can rebind it, and the index records those as reads. }
  if pWhere = '' then
    for var R: TReference in FStore.FindReferencesTo(pField.Id) do
    begin
      if Allowed(R.EnclosingSymbolId) then Continue;
      var W: string;
      if ArgumentUse(R, W) then
      begin
        pWhere:= 'passed as an argument at ' + W;
        Break;
      end;
    end;
  FWriterMemo.Add(pField.Id, pWhere);
  Result:= pWhere <> '';
end;

function TAnalyzer.CastType(const E: TTSNode): TSymbol;
var
  Rw: TRow;
begin
  var R:= E.ChildByField('rhs');
  if R.NodeType <> 'identifier' then Refuse(CUwTargetCast, 'target ' + NodeStr(E) + ': the type is not one plain name');
  if (not RowAt(R, Rw)) or (Rw.SymbolId <= 0) then
    Refuse(CUwNullType, Format('%s: type %s has no symbol id (ambiguous, or outside this index)', [NodeStr(E), Trim(NodeStr(R))]));
  Result:= FStore.GetSymbolById(Rw.SymbolId);
  if (Result.Kind <> skClass) or Result.IsHelper then
    Refuse(CUwTargetKind, Format('%s is a %s', [Result.QualifiedName, Result.Kind.ToText]));
end;

procedure TAnalyzer.CheckTargetStable(const pLinks: TArray<TLink>; pCast: Boolean; out pTypeId: Int64; out pTypeText: string);

  function BackingField(const pProp: TSymbol): TSymbol;
  var
    Src: TArray<string>;
  begin
    Result:= Default(TSymbol);
    { The property's declaration text names its getter; the index keeps the accessor shape, not the name. }
    var Path:= FStore.GetFilePath(pProp.FileId);
    if (Path = '') or not TFile.Exists(Path) then Exit;
    Src:= TFile.ReadAllLines(Path, TEncoding.ANSI);
    var Decl:= '';
    for var I: Integer:= pProp.StartLine - 1 to pProp.EndLine - 1 do
      if (I >= 0) and (I < Length(Src)) then Decl:= Decl + ' ' + Src[I];
    var Words:= Decl.Replace(';', ' ').Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    for var I: Integer:= 0 to High(Words) - 1 do
      if SameText(Words[I], 'read') then
      begin
        for var M: TSymbol in FStore.FindAllChildSymbols(pProp.ParentId) do
          if SameText(M.Name, Words[I + 1]) then Exit(M);
        Exit;
      end;
  end;

begin
  pTypeId:= 0;
  pTypeText:= '';
  var FirstIdx:= 0;
  if (Length(pLinks) > 0) and SameText(pLinks[0].Text, 'Self') then FirstIdx:= 1;
  if FirstIdx > High(pLinks) then Refuse(CUwTargetNotVariable, 'with Self');
  for var I: Integer:= FirstIdx to High(pLinks) do
  begin
    var L:= pLinks[I];
    if (not L.HasRow) or (L.Row.SymbolId <= 0) then
      Refuse(CUwTargetUnbound, Format('link %s of the target is not bound by the index', [L.Text]));
    var Sym:= FStore.GetSymbolById(L.Row.SymbolId);
    var IsLast:= I = High(pLinks);
    var IsValueType:= False;
    if L.Row.TypeSymbolId > 0 then IsValueType:= FStore.GetSymbolById(L.Row.TypeSymbolId).Kind = skRecord;
    var Slot:= Sym;
    case Sym.Kind of
      skLocalVar, skField, skVarDecl:
        Slot:= Sym;
      skParam:
        if (not IsValueType) and (ContainsText(FStore.GetSymbolById(Sym.ParentId).Signature, 'var ' + Sym.Name) or
             ContainsText(FStore.GetSymbolById(Sym.ParentId).Signature, 'out ' + Sym.Name)) then
          Refuse(CUwVarParam, Format('%s is a var/out parameter of class type: a call can rebind it', [L.Text]));
      skProperty:
        begin
          Slot:= BackingField(Sym);
          if Slot.Kind <> skField then
            Refuse(CUwTargetGetter, Format('property %s: its read is not a field of %s, so it runs once under with, N times after',
              [L.Text, FStore.GetSymbolById(Sym.ParentId).Name]));
        end;
      skFunction, skMethod, skProcedure:
        Refuse(CUwTargetCall, Format('%s is a routine: evaluated once by with, N times after', [L.Text]));
      skConstructor:
        Refuse(CUwTargetCtor, L.Text);
    else
      Refuse(CUwTargetNotVariable, Format('link %s is a %s', [L.Text, Sym.Kind.ToText]));
    end;
    { A record link is the slot itself: with takes its ADDRESS, and so does the rewrite; only a reference can move. }
    if (Slot.Kind in [skField, skVarDecl]) and not IsValueType then
    begin
      var Where: string;
      if FieldWriter(Slot, Where) then
        Refuse(CUwFieldReassigned, Format('%s is %s: any call in the body might rebind it', [Slot.QualifiedName, Where]));
    end;
    if IsLast and not pCast then
    begin
      if not L.Row.HasTypeRow then
        Refuse(CUwNoTypeRow, Format('the index has no static type for %s', [L.Text]));
      pTypeText:= L.Row.TypeQName;
      if L.Row.TypeSymbolId <= 0 then
        Refuse(CUwNullType, Format('%s: %s has no symbol id (ambiguous, or outside this index)', [L.Text, L.Row.TypeQName]));
      var T:= FStore.GetSymbolById(L.Row.TypeSymbolId);
      if (T.Kind not in [skClass, skRecord]) or T.IsHelper then
        Refuse(CUwTargetKind, Format('%s is a %s', [T.QualifiedName, T.Kind.ToText]));
      pTypeId:= T.Id;
    end;
  end;
end;

procedure TAnalyzer.CheckHeader(const W, E, Body: TTSNode);

  function BlankBetween(pFrom, pTo: Integer): Boolean;
  begin
    Result:= True;
    for var I: Integer:= pFrom to pTo - 1 do
      if FRaw[I] not in [CSpace, CTab, CCr, CBackslashLf] then Exit(False);
  end;

begin
  for var I: Integer:= Integer(E.StartByte) to Integer(E.EndByte) - 1 do
    if FRaw[I] in [CCr, CBackslashLf] then Refuse(CUwHeader, 'the target spans lines');
  { `with` + E + `do` + Body: nothing but blanks between them, or a comment would be lost. }
  if (Integer(E.StartByte) < Integer(W.StartByte) + Length('with')) or not BlankBetween(Integer(W.StartByte) + Length('with'), E.StartByte) then
    Refuse(CUwHeader, 'a comment between with and the target');
  var P:= Integer(E.EndByte);
  while (P < Length(FRaw)) and (FRaw[P] in [CSpace, CTab, CCr, CBackslashLf]) do Inc(P);
  if not ((P + 2 <= Length(FRaw)) and (UpCase(Char(FRaw[P])) = 'D') and (UpCase(Char(FRaw[P + 1])) = 'O')) then
    Refuse(CUwHeader, 'a comment between the target and do');
  if not BlankBetween(P + 2, Body.StartByte) then
    Refuse(CUwHeader, 'a comment between do and the body');
end;

{ ---- the body ---- }

procedure TAnalyzer.ScanStructure(const N: TTSNode);
var
  NT: string;
begin
  if N.IsNull then Exit;
  NT:= N.NodeType;
  if NT = 'with' then
    Refuse(CUwInnerFirst, Format('the with at line %d goes first; reindex, then this one', [Integer(N.StartPoint.Row) + 1]));
  if NT = 'lambda' then
    Refuse(CUwAnonymous, Format('anonymous method at line %d: the target would be read when it runs', [Integer(N.StartPoint.Row) + 1]));
  if (NT = 'asm') or (NT = 'kAsm') then Refuse(CUwAsm, Format('line %d', [Integer(N.StartPoint.Row) + 1]));
  if (NT = 'varAssignDef') or (NT = 'varDef') then
    Refuse(CUwInlineDecl, Format('inline declaration at line %d: it may shadow the target or a member', [Integer(N.StartPoint.Row) + 1]));
  for var I: Integer:= 0 to N.NamedChildCount - 1 do ScanStructure(N.NamedChild(I));
end;

function TAnalyzer.UsesTargetBare(const N: TTSNode; const pLinks: TArray<TLink>): Boolean;
begin
  { Normalise a leading Self on both sides: the slot is the same. }
  var Want: TArray<string>:= nil;
  for var I: Integer:= 0 to High(pLinks) do
    if not ((I = 0) and SameText(pLinks[I].Text, 'Self')) then Want:= Want + [pLinks[I].Text];
  var Nm:= Trim(NodeStr(N));
  var Idx:= 0;
  if SameText(Nm, 'Self') then
  begin
    if pLinks[0].Text <> 'Self' then Exit(False);
    Idx:= -1;
  end
  else if (Length(Want) = 0) or not SameText(Nm, Want[0]) then Exit(False);
  { Follow the dotted chain upward while it spells the target. }
  var Cur:= N;
  var Parent:= Cur.Parent;
  while (not Parent.IsNull) and (Parent.NodeType = 'exprDot') and (Parent.ChildByField('lhs').StartByte = Cur.StartByte)
        and (Parent.ChildByField('lhs').EndByte = Cur.EndByte) do
  begin
    Inc(Idx);
    if Idx > High(Want) then Exit(False);     { the target is its receiver }
    if not SameText(Trim(NodeStr(Parent.ChildByField('rhs'))), Want[Idx]) then Exit(False); { another member }
    Cur:= Parent;
    Parent:= Cur.Parent;
  end;
  Result:= Idx >= 0;
end;

procedure TAnalyzer.VisitBody(const N: TTSNode; pInType: Boolean; pC: TClosure; const pLinks: TArray<TLink>;
  const pSite: TList<TUnwithBinding>; const pPrefixAt: TList<Integer>);
var
  NT: string;

  procedure Classify;
  var
    Hits: TArray<TMember>;
    Row: TRow;
    HasRow: Boolean;
    B: TUnwithBinding;
  begin
    var Nm:= Trim(NodeStr(N));
    if (Nm = '') or SameText(Nm, 'Self') then
    begin
      if SameText(Nm, 'Self') and UsesTargetBare(N, pLinks) then
        Refuse(CUwTargetUsedBare, Format('line %d uses the target itself: %s', [Integer(N.StartPoint.Row) + 1, Nm]));
      Exit;
    end;
    HasRow:= RowAt(N, Row);
    var Line:= Integer(N.StartPoint.Row) + 1;
    B:= Default(TUnwithBinding);
    B.Line:= Line;
    B.Col:= Integer(N.StartPoint.Column) + 1;
    B.Name:= Nm;
    if HasRow then B.Before:= Row.Target;
    if pC.Members.TryGetValue(LowerCase(Nm), Hits) then
    begin
      { Nearest first: Delphi looks from the target's type upward and stops at the first declarer it can see, so an
        ancestor's private of the same name (TComponent.FName under a class's own fNAME) changes nothing. }
      if Hits[0].Invisible <> '' then
        Refuse(CUwInvisible, Format('line %d: %s matches %s (%s): whether the compiler sees it here is not proved', [Line, Nm, Hits[0].QName, Hits[0].Invisible]));
      for var H: TMember in Hits do
      begin
        if H.NestedType then
          Refuse(CUwNestedType, Format('line %d: %s is %s, a nested type or its value', [Line, Nm, H.QName]));
        if H.HelperAmbiguous then
          Refuse(CUwHelperAmbiguous, Format('line %d: %s is in one of two helpers in scope', [Line, Nm]));
      end;
      if pInType then
        Refuse(CUwTypeName, Format('line %d: %s in a type position matches member %s', [Line, Nm, Hits[0].QName]));
      if HasRow and (Row.SymbolId > 0) then
      begin
        var Agrees:= False;
        for var H: TMember in Hits do
          if (not H.FromLib) and (H.Id = Row.SymbolId) then Agrees:= True;
        if not Agrees then
          Refuse(CUwBindingConflict, Format('line %d: the closure says %s, the index bound %s', [Line, Hits[0].QName, Row.Target]));
      end;
      B.Prefixed:= True;
      var Off:= Integer(N.StartByte);
      if not SameText(Nm, FSkipPrefix) then pPrefixAt.Add(Off);
      pSite.Add(B);
    end
    else
    begin
      if UsesTargetBare(N, pLinks) then
        Refuse(CUwTargetUsedBare, Format('line %d uses the target itself (%s): with read it once', [Line, Nm]));
      if HasRow and (Row.SymbolId > 0) and pC.ChainIds.ContainsKey(FStore.GetSymbolById(Row.SymbolId).ParentId) then
        Refuse(CUwBindingConflict, Format('line %d: %s is not in the closure, the index bound %s', [Line, Nm, Row.Target]));
      pSite.Add(B);
    end;
  end;

begin
  if N.IsNull then Exit;
  NT:= N.NodeType;
  if NT = 'identifier' then
  begin
    Classify;
    Exit;
  end;
  if (NT = 'exprDot') or (NT = 'genericDot') or (NT = 'typerefDot') then
  begin
    VisitBody(N.ChildByField('lhs'), pInType or (NT = 'typerefDot'), pC, pLinks, pSite, pPrefixAt);
    var R:= N.ChildByField('rhs');
    if (not R.IsNull) and (R.NodeType <> 'identifier') then
    begin
      { `A.B<T>`: the entity is a member name, only the arguments are bare. }
      if R.NodeType = 'exprTpl' then VisitBody(R.ChildByField('args'), True, pC, pLinks, pSite, pPrefixAt)
      else VisitBody(R, pInType, pC, pLinks, pSite, pPrefixAt);
    end;
    Exit;
  end;
  if NT = 'inherited' then
  begin
    { `inherited Foo(1)` binds through the enclosing class, never through with; its arguments are ordinary. }
    for var I: Integer:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType <> 'identifier' then VisitBody(N.NamedChild(I), pInType, pC, pLinks, pSite, pPrefixAt);
    Exit;
  end;
  var InT:= pInType or StartsText('typeref', NT) or (NT = 'exprTplArgs');
  for var I: Integer:= 0 to N.NamedChildCount - 1 do
    VisitBody(N.NamedChild(I), InT, pC, pLinks, pSite, pPrefixAt);
end;

function TAnalyzer.TryUnwrap(const W, Body: TTSNode; out pSplices: TArray<TSplice>): Boolean;  // dl:ok too-many-exit-points@9282, cyclomatic-complexity@5c4b -- REVIEWED 2026-11-05: each branch is one precondition for unwrapping; failing any keeps the begin..end, which is safe
var
  Block: TTSNode;

  function LineStartOf(pPos: Integer): Integer;
  begin
    Result:= pPos;
    while (Result > 0) and (FRaw[Result - 1] <> CBackslashLf) do Dec(Result);
  end;

  function OnlyBlanks(pFrom, pTo: Integer): Boolean;
  begin
    Result:= True;
    for var I: Integer:= pFrom to pTo - 1 do
      if FRaw[I] not in [CSpace, CTab] then Exit(False);
  end;

  function NextLineStart(pPos: Integer): Integer;
  begin
    Result:= pPos;
    while (Result < Length(FRaw)) and (FRaw[Result] <> CBackslashLf) do Inc(Result);
    if Result < Length(FRaw) then Inc(Result);
  end;

  function LineEndOf(pPos: Integer): Integer;
  begin
    Result:= pPos;
    while (Result < Length(FRaw)) and (FRaw[Result] not in [CCr, CBackslashLf]) do Inc(Result);
  end;

begin
  Result:= False;
  pSplices:= nil;
  Block:= Body;
  if (Block.NodeType = 'statement') and (Block.NamedChildCount = 1) then Block:= Block.NamedChild(0);
  if Block.NodeType <> 'block' then Exit;
  { Only in a statement list: `if c then with E do begin .. end else` needs its block. }
  var Par:= W.Parent;
  if (not Par.IsNull) and (Par.NodeType = 'statement') then Par:= Par.Parent;
  if Par.IsNull or ((Par.NodeType <> 'statements') and (Par.NodeType <> 'block')) then Exit;
  var WStart:= Integer(W.StartByte);
  var LS:= LineStartOf(WStart);
  if not OnlyBlanks(LS, WStart) then Exit;
  var BStart:= Integer(Block.StartByte);
  { The grammar puts the `;` after `end` inside the block node when it can: find `end` itself. }
  var EndKw:= -1;
  for var I: Integer:= 0 to Block.ChildCount - 1 do
    if Block.Child(I).NodeType = 'kEnd' then EndKw:= Block.Child(I).StartByte;
  if EndKw < 0 then Exit;
  var BEnd:= EndKw + Length('end');
  { `begin` alone on its line; `end` or `end;` alone on its line. }
  var BeginEnd:= BStart + Length('begin');
  if not OnlyBlanks(BeginEnd, LineEndOf(BeginEnd)) then Exit;
  if not OnlyBlanks(LineStartOf(EndKw), EndKw) then Exit;
  var AfterEnd:= BEnd;
  var HasSemi:= (AfterEnd < Length(FRaw)) and (FRaw[AfterEnd] = CSemicolon);
  if HasSemi then Inc(AfterEnd);
  if not OnlyBlanks(AfterEnd, LineEndOf(AfterEnd)) then Exit;
  { Inner text: first line after begin .. line of end. A semicolon after `end` must survive as the last inner
    statement's own, or the next statement glues on; a multi-line string must not move. }
  var InnerFrom:= NextLineStart(BeginEnd);
  var InnerTo:= LineStartOf(EndKw);
  if InnerFrom >= InnerTo then Exit;
  if RawHas(InnerFrom, InnerTo, '''''''') then Exit;
  var Last:= InnerTo - 1;
  while (Last >= InnerFrom) and (FRaw[Last] in [CSpace, CTab, CCr, CBackslashLf]) do Dec(Last);
  if HasSemi and ((Last < InnerFrom) or (FRaw[Last] <> CSemicolon)) then Exit;
  { A comment ending the block: the last byte test above cannot see past it, so leave the block. }
  if (Last >= InnerFrom) and (FRaw[Last] in [Ord('}'), Ord(')')]) then Exit;
  { Dedent by what the block's lines stand right of `with`. }
  var WithIndent:= WStart - LS;
  var MinIndent:= MaxInt;
  var P:= InnerFrom;
  while P < InnerTo do
  begin
    var E:= LineEndOf(P);
    var Q:= P;
    while (Q < E) and (FRaw[Q] = CSpace) do Inc(Q);
    if (Q < E) and (FRaw[Q] = CTab) then Exit;
    if Q < E then MinIndent:= Min(MinIndent, Q - P);
    P:= NextLineStart(E);
  end;
  if MinIndent = MaxInt then Exit;
  var Delta:= MinIndent - WithIndent;
  var S: TSplice:= Default(TSplice);
  S.Pos:= LS;
  S.DelLen:= InnerFrom - LS;
  pSplices:= pSplices + [S];
  if Delta > 0 then
  begin
    P:= InnerFrom;
    while P < InnerTo do
    begin
      var E:= LineEndOf(P);
      if E - P >= Delta then
      begin
        S:= Default(TSplice);
        S.Pos:= P;
        S.DelLen:= Delta;
        pSplices:= pSplices + [S];
      end;
      P:= NextLineStart(E);
    end;
  end;
  S:= Default(TSplice);
  S.Pos:= InnerTo;
  S.DelLen:= NextLineStart(EndKw) - InnerTo;
  pSplices:= pSplices + [S];
  Result:= True;
end;

procedure TAnalyzer.AddBodySplices(const W, Body: TTSNode; const pPrefix: string; const pPrefixAt: TList<Integer>;
  const pRootBefore, pRootName: string; pRootLead: Integer);
var
  Own: TArray<TSplice>;
begin
  if not TryUnwrap(W, Body, Own) then
  begin
    var S: TSplice:= Default(TSplice);
    S.Pos:= W.StartByte;
    S.DelLen:= Integer(Body.StartByte) - Integer(W.StartByte);
    Own:= [S];
  end;
  var Ins:= TEncoding.UTF8.GetBytes(pPrefix + '.');
  for var Off: Integer in pPrefixAt do
  begin
    var S: TSplice:= Default(TSplice);
    S.Pos:= Off;
    S.Ins:= Ins;
    Own:= Own + [S];
    if pRootBefore <> '' then
    begin
      { The prefix's root must bind to what the entity's root bound: proof point at the insertion itself. }
      var PP: TUnwithProofPoint:= Default(TUnwithProofPoint);
      PP.Name:= pRootName;
      PP.Before:= pRootBefore;
      PP.NewCol:= pRootLead;
      FProof.Add(PP);
      FProofOffsets.Add(-Off - 1);
    end;
  end;
  FSplices.AddRange(Own);
end;

function TAnalyzer.AnalyzeSite(const W: TTSNode): TUnwithSite;
var
  Entities: TArray<TTSNode>;
  Body: TTSNode;
  Binds: TList<TUnwithBinding>;
  PrefixAt: TList<Integer>;
begin
  Result:= Default(TUnwithSite);
  Result.Line:= Integer(W.StartPoint.Row) + 1;
  Result.Col:= Integer(W.StartPoint.Column) + 1;
  Binds:= TList<TUnwithBinding>.Create;
  PrefixAt:= TList<Integer>.Create;
  try
    try
      if W.HasError then Refuse(CUwParseError, 'the parser reports an error inside this with');
      Body:= W.ChildByField('body');
      if Body.IsNull then Refuse(CUwParseError, 'a with with no body');
      Entities:= nil;
      for var I: Integer:= 0 to W.ChildCount - 1 do
      begin
        var C:= W.Child(I);
        if C.NodeType = 'kDo' then Break;
        if (C.NodeType = 'kWith') or (C.NodeType = ',') then Continue;
        if C.NodeType = 'comment' then Refuse(CUwHeader, 'a comment in the with header');
        Entities:= Entities + [C];
      end;
      if Length(Entities) <> 1 then
      begin
        var Names:= '';
        for var Ent: TTSNode in Entities do Names:= Names + IfThen(Names <> '', ', ') + Trim(NodeStr(Ent));
        Refuse(CUwMultipleTargets, 'with ' + Names + ': v1 takes one target');
      end;
      Result.Target:= Trim(NodeStr(Entities[0]));
      // Only a directive that can change the TEXT: a $REGION or $R+ cannot hide a name.
      for var Cond: string in CConditionals do
        if RawHas(W.StartByte, W.EndByte, Cond) then
          Refuse(CUwConditional, Format('%s inside the statement: another configuration may use any name', [Cond]));
      ScanStructure(Body);
      { `X as T` with a stable X: no side effect but the check, and the check's outcome cannot change between evaluations. }
      var IsCast:= (Entities[0].NodeType = 'exprBinary') and SameText(Trim(NodeStr(Entities[0].ChildByField('operator'))), 'as');
      var Links:= TargetLinks(if IsCast then Entities[0].ChildByField('lhs') else Entities[0]);
      var TypeId: Int64;
      var TypeText: string;
      try
        CheckTargetStable(Links, IsCast, TypeId, TypeText);
      finally
        Result.TargetType:= TypeText;
      end;
      if IsCast then TypeId:= CastType(Entities[0]).Id;
      Result.TargetType:= FStore.GetSymbolById(TypeId).QualifiedName;
      CheckHeader(W, Entities[0], Body);
      var C:= Closure(TypeId);
      if C.Failure <> '' then Refuse(C.FailureKind, C.Failure);
      VisitBody(Body, False, C, Links, Binds, PrefixAt);
      Result.Bindings:= Binds.ToArray;
      if IsCast then
        for var B: TUnwithBinding in Result.Bindings do
        begin
          if B.Prefixed then Break;
          var Rw: TRow;
          if (not FRows.TryGetValue(PosKey(B.Line, B.Col), Rw)) or (Rw.Kind = 'call') or (Rw.SymbolId <= 0) then
            Refuse(CUwCastOrder, Format('line %d: %s runs before the first use of the target: a failing cast would raise after it, not before', [B.Line, B.Name]));
        end;
      { Every ref of the body is a proof point, not only the identifiers walked. }
      var BodyFrom:= Integer(Body.StartByte);
      var BodyTo:= Integer(Body.EndByte);
      for var Pair: TPair<string, TRow> in FRows do
      begin
        var Parts:= Pair.Key.Split([':']);
        var Off:= OffsetOf(StrToInt(Parts[0]), StrToInt(Parts[1]));
        if (Off < BodyFrom) or (Off >= BodyTo) then Continue;
        var PP: TUnwithProofPoint:= Default(TUnwithProofPoint);
        PP.OldLine:= StrToInt(Parts[0]);
        PP.OldCol:= StrToInt(Parts[1]);
        PP.Name:= Pair.Value.Name;
        PP.Before:= Pair.Value.Target;
        PP.Prefixed:= False;
        for var B: TUnwithBinding in Binds do
          if B.Prefixed and (B.Line = PP.OldLine) and (B.Col = PP.OldCol) then PP.Prefixed:= True;
        if PP.Prefixed then
        begin
          var Hits: TArray<TMember>;
          if C.Members.TryGetValue(LowerCase(PP.Name), Hits) then
            for var H: TMember in Hits do PP.Members:= PP.Members + LowerCase(H.QName) + ';';
        end;
        FProof.Add(PP);
        FProofOffsets.Add(Off);
      end;
      var RootBefore:= '';
      var RootName:= Links[0].Text;
      if Links[0].HasRow then RootBefore:= Links[0].Row.Target;
      AddBodySplices(W, Body, if IsCast then '(' + Result.Target + ')' else Result.Target, PrefixAt, RootBefore, RootName,
        if IsCast then 1 else 0);
    except
      on E: ERefuse do
      begin
        Result.Refusal:= E.Kind;
        Result.Detail:= E.Message;
        Result.Bindings:= nil;
      end;
    end;
  finally
    PrefixAt.Free;
    Binds.Free;
  end;
end;

procedure TAnalyzer.CollectWiths(const N: TTSNode; L: TList<TTSNode>);
begin
  if N.IsNull then Exit;
  if N.NodeType = 'with' then L.Add(N);
  for var I: Integer:= 0 to N.NamedChildCount - 1 do CollectWiths(N.NamedChild(I), L);
end;

function TAnalyzer.Run(pLine: Integer): TUnwithFilePlan;  // dl:ok too-many-exit-points@5bb0 -- REVIEWED 2026-11-05: each early exit is one named precondition

  procedure RefuseAll(const pList: TList<TTSNode>; const pKind, pDetail: string);
  begin
    for var W: TTSNode in pList do
    begin
      var S: TUnwithSite:= Default(TUnwithSite);
      S.Line:= Integer(W.StartPoint.Row) + 1;
      S.Col:= Integer(W.StartPoint.Column) + 1;
      S.Target:= '';
      S.Refusal:= pKind;
      S.Detail:= pDetail;
      Result.Sites:= Result.Sites + [S];
    end;
  end;

var
  PF: TParsedFile;
  Withs: TList<TTSNode>;
  Fmt: TTextFileFormat;
  DiskText: string;
begin
  Result:= Default(TUnwithFilePlan);
  Result.FilePath:= FFile;
  PF:= TAstParseCache.Get(FFile);
  if PF.Tree = nil then Exit;
  FSrc:= PF.Src;
  FRaw:= if Length(PF.RawSrc) > 0 then PF.RawSrc else PF.Src;
  if IsUnderTemp(FFile) then FSkipPrefix:= GetEnvironmentVariable(CTestSkipPrefixVar);
  Withs:= TList<TTSNode>.Create;
  try
    CollectWiths(PF.Tree.RootNode, Withs);
    if pLine > 0 then
      for var I: Integer:= Withs.Count - 1 downto 0 do
        if Integer(Withs[I].StartPoint.Row) + 1 <> pLine then Withs.Delete(I);
    if Withs.Count = 0 then Exit;
    FFileId:= FStore.FindFileIdByPath(FFile);
    if FFileId <= 0 then
    begin
      RefuseAll(Withs, CUwStale, 'the file is not in this index');
      Exit;
    end;
    var DiskBytes:= TFile.ReadAllBytes(FFile);
    var Sha:= THashSHA2.GetHashString(TEncoding.ANSI.GetString(DiskBytes));
    if not FStore.FileIsUpToDate(FFile, FileMTimeUnix(FFile), Sha) then
    begin
      RefuseAll(Withs, CUwStale, 'the file changed after it was indexed; reindex and retry');
      Exit;
    end;
    { The tree's offsets are into the UTF-8 form of the file. It must convert back byte for byte. }
    Fmt:= TTextFileFormat.Decode(DiskBytes, DiskText);
    var RoundTrip:= Fmt.Encode(TEncoding.UTF8.GetString(FRaw));
    if (Length(RoundTrip) <> Length(DiskBytes)) or ((Length(DiskBytes) > 0) and not CompareMem(@RoundTrip[0], @DiskBytes[0], Length(DiskBytes))) then
    begin
      RefuseAll(Withs, CUwEncoding, 'the file''s encoding or line breaks would not survive the rewrite');
      Exit;
    end;
    var LS: TList<Integer>:= TList<Integer>.Create;
    try
      LS.Add(0);
      for var I: Integer:= 0 to High(FRaw) do
        if FRaw[I] = CBackslashLf then LS.Add(I + 1);
      FLineStart:= LS.ToArray;
    finally
      LS.Free;
    end;
    try
      LoadRows;
    except
      on E: ERefuse do
      begin
        RefuseAll(Withs, E.Kind, E.Message);
        Exit;
      end;
    end;
    for var U: TUnitUse in FStore.GetUnitUsesForFile(FFileId) do FFileUses:= FFileUses + [U.UnitName];
    for var W: TTSNode in Withs do Result.Sites:= Result.Sites + [AnalyzeSite(W)];
    if FSplices.Count = 0 then Exit;
    Render(Fmt, Result);
  finally
    Withs.Free;
  end;
end;

procedure TAnalyzer.Render(const pFmt: TTextFileFormat; var pPlan: TUnwithFilePlan);  // dl:ok deep-nesting@41c3 -- REVIEWED 2026-11-05: one linear rendering pass; splitting it would only pass its locals around
begin
  { Apply the splices: sorted, never overlapping (the candidates are disjoint, nested ones refused). }
  FSplices.Sort(TComparer<TSplice>.Construct(
    function(const A, B: TSplice): Integer
    begin
      Result:= A.Pos - B.Pos;
      if Result = 0 then Result:= B.DelLen - A.DelLen;
    end));
  var Out1:= TBytesStream.Create;
  try
    var Cur:= 0;
    for var S: TSplice in FSplices do
    begin
      if S.Pos < Cur then
        raise EInvalidOpException.CreateFmt('unwith: overlapping edits at byte %d of %s', [S.Pos, FFile]);
      if S.Pos > Cur then Out1.Write(FRaw[Cur], S.Pos - Cur);
      if Length(S.Ins) > 0 then Out1.Write(S.Ins[0], Length(S.Ins));
      Cur:= S.Pos + S.DelLen;
    end;
    if Cur < Length(FRaw) then Out1.Write(FRaw[Cur], Length(FRaw) - Cur);
    var NewRaw: TBytes;
    SetLength(NewRaw, Out1.Size);
    if Out1.Size > 0 then Move(Out1.Bytes[0], NewRaw[0], Out1.Size);
    pPlan.NewBytes:= pFmt.Encode(TEncoding.UTF8.GetString(NewRaw));
    { Map every proof point to its position after the rewrite. }
    var NewStarts: TList<Integer>:= TList<Integer>.Create;
    try
      NewStarts.Add(0);
      for var I: Integer:= 0 to High(NewRaw) do
        if NewRaw[I] = CBackslashLf then NewStarts.Add(I + 1);
      var Delta: TArray<Integer>:= nil;
      var Poss: TArray<Integer>:= nil;
      var Acc:= 0;
      for var S: TSplice in FSplices do
      begin
        Acc:= Acc + Length(S.Ins) - S.DelLen;
        Poss:= Poss + [S.Pos];
        Delta:= Delta + [Acc];
      end;
      var Mapped: TArray<TUnwithProofPoint>:= nil;
      for var I: Integer:= 0 to FProof.Count - 1 do
      begin
        var PP:= FProof[I];
        var Off:= FProofOffsets[I];
        var IsRoot:= Off < 0;
        if IsRoot then Off:= -Off - 1;
        { A prefix root sits at the insertion, before its own Ins; an identifier sits after every splice at or before it. }
        var NewOff:= Off;
        for var J: Integer:= 0 to High(Poss) do
          if (Poss[J] < Off) or ((Poss[J] = Off) and not IsRoot) then NewOff:= Off + Delta[J]
          else if Poss[J] > Off then Break;
        if IsRoot then
        begin
          var Before:= 0;
          for var J: Integer:= 0 to High(Poss) do
            if Poss[J] < Off then Before:= Delta[J];
          NewOff:= Off + Before;
        end;
        var Lo:= 0;
        var Hi:= NewStarts.Count - 1;
        while Lo < Hi do
        begin
          var Mid:= (Lo + Hi + 1) div 2;
          if NewStarts[Mid] <= NewOff then Lo:= Mid else Hi:= Mid - 1;
        end;
        PP.NewLine:= Lo + 1;
        PP.NewCol:= NewOff - NewStarts[Lo] + 1 + PP.NewCol;     { a root proof point carries its lead in NewCol until here }
        Mapped:= Mapped + [PP];
      end;
      pPlan.Proof:= Mapped;
    finally
      NewStarts.Free;
    end;
  finally
    Out1.Free;
  end;
end;

function UnwithPlanFile(const pStore, pLib: ISymbolStore; const pFile: string; pLine: Integer): TUnwithFilePlan;
begin
  var A:= TAnalyzer.Create(pStore, pLib, pFile);
  try
    Result:= A.Run(pLine);
  finally
    A.Free;
  end;
end;

{ ---- apply ---- }

function CopyDbFor(const pDb, pDir: string): string;
begin
  Result:= TPath.Combine(pDir, 'after-proof.sqlite');
  TFile.Copy(pDb, Result, True);  // dl:ok taint-path-traversal@b47e -- REVIEWED 2026-11-05: the path is the user's own --db or a fresh scratch dir; a CLI writing where its user says is the contract
  if TFile.Exists(pDb + '-wal') then TFile.Copy(pDb + '-wal', Result + '-wal', True);  // dl:ok taint-path-traversal@d26f -- REVIEWED 2026-11-05: the path is the user's own --db or a fresh scratch dir; a CLI writing where its user says is the contract
  if TFile.Exists(pDb + '-shm') then TFile.Copy(pDb + '-shm', Result + '-shm', True);  // dl:ok taint-path-traversal@af1c -- REVIEWED 2026-11-05: the path is the user's own --db or a fresh scratch dir; a CLI writing where its user says is the contract
end;

/// <summary>Deletes the run's log folder, unless a message of this run sends the reader to a file in it.</summary>
/// <param name="pDir">The folder FreshScratchName gave.</param>
/// <param name="pDetail">What the run tells the user.</param>
/// <remarks>An I/O failure is swallowed: a log folder that will not go is no reason to fail the verb.</remarks>
procedure DropUnwithLogs(const pDir, pDetail: string);
begin
  if GScratchCited or pDetail.Contains(ExcludeTrailingPathDelimiter(pDir)) then Exit;
  try
    if TDirectory.Exists(pDir) then TDirectory.Delete(pDir, True);  // dl:ok taint-path-traversal@b8f1 -- a fresh scratch dir; only its PID part can come from the environment, a test seam
  except  // dl:ok try-except-swallowed@a59f -- leftovers in the scratch root are harmless; see the remarks
    on E: EInOutError do ;  // dl:ok empty-on-handler@8192 -- the log folder is left behind, harmless; see the remarks
    on E: EDirectoryNotFoundException do ;  // dl:ok empty-on-handler@431d -- the log folder is left behind, harmless; see the remarks
  end;
end;

function UnwithApply(const pPlans: TArray<TUnwithFilePlan>; const pOpts: TUnwithApplyOptions): TUnwithApplyResult;
var
  Req: TGateRequest;
  Dir: string;

  procedure Compare(const pPlan: TUnwithFilePlan; const pAfter: ISymbolStore);
  var
    Has: Boolean;
    Rows: TRows;
  begin
    var Fid:= pAfter.FindFileIdByPath(pPlan.FilePath);
    Rows:= TRows.Create;
    try
      if Fid > 0 then LoadRowsOf(pAfter, Fid, Rows, Has);
      for var PP: TUnwithProofPoint in pPlan.Proof do
      begin
        Inc(Result.ProofPoints);
        var R: TRow;
        var After:= '';
        if Rows.TryGetValue(PosKey(PP.NewLine, PP.NewCol), R) then
          After:= if SameText(R.Name, PP.Name) then R.Target else Format('(another name at this position: %s)', [R.Name]);
        { Same binding; or a prefixed name the index lost (the closure alone proves it) or gained, to a closure member only. }
        var Good:= SameText(After, PP.Before) or (PP.Prefixed and (After = ''))  // dl:ok boolean-expression-complexity@54ae -- REVIEWED 2026-11-05: the three accepted outcomes of a proof point, stated together on purpose
          or (PP.Prefixed and (PP.Before = '') and not StartsText('ext:', After)
              and ContainsText(PP.Members, LowerCase(Copy(After, 1, Pos('|', After) - 1)) + ';'));
        if not Good then
          Result.Rebinds:= Result.Rebinds + [Format('%s:%d:%d %s: %s -> %s', [ExtractFileName(pPlan.FilePath), PP.OldLine, PP.OldCol, PP.Name,
            if PP.Before = '' then '(unbound)' else PP.Before, if After = '' then '(unbound)' else After])];
      end;
    finally
      Rows.Free;
    end;
  end;

begin
  Result:= Default(TUnwithApplyResult);
  Req:= Default(TGateRequest);
  Req.Project:= pOpts.Project;
  Req.Platform:= pOpts.Platform;
  Req.Verb:= 'unwith';
  Req.Header:= 'unwith --apply';
  Req.NoBackup:= pOpts.NoBackup;
  Dir:= FreshScratchName('_unwith');
  Req.LogDir:= Dir;
  TDirectory.CreateDirectory(Dir);  // dl:ok taint-path-traversal@159a -- REVIEWED 2026-11-05: the path is the user's own --db or a fresh scratch dir; a CLI writing where its user says is the contract
  for var P: TUnwithFilePlan in pPlans do
    if Length(P.NewBytes) > 0 then
    begin
      var F: TGateFile:= Default(TGateFile);
      F.Path:= P.FilePath;
      F.Bytes:= P.NewBytes;
      Req.Files:= Req.Files + [F];
    end;
  if Length(Req.Files) = 0 then
  begin
    Result.Refusal:= 'nothing-to-apply';
    Result.Detail:= 'no with statement is a candidate';
    DropUnwithLogs(Dir, Result.Detail);
    Exit;
  end;
  GGateVerb:= 'unwith';
  var Gate:= ApplyGated(Req);
  Result.Written:= Gate.Tx.Written;
  if not Gate.Applied then
  begin
    Result.Refusal:= Gate.Refusal;
    Result.Detail:= Gate.Detail;
    Result.RollbackFailed:= Gate.RollbackFailed;
    DropUnwithLogs(Dir, Result.Detail);
    Exit;
  end;
  { The build says it compiles. Now: does it still MEAN the same? }
  var ProofFailure:= '';
  try
    var AfterDb:= CopyDbFor(pOpts.Db, Dir);
    var TimedOut: Boolean;
    var Code:= RunBounded('after-proof re-index',
      Format('"%s" index --project "%s" --db "%s"', [ParamStr(0), pOpts.Project, AfterDb]),
      TPath.Combine(Dir, 'after-proof-index.log'), INFINITE, TimedOut);
    if Code <> 0 then ProofFailure:= Format('the re-index exited %d (log %s)', [Code, TPath.Combine(Dir, 'after-proof-index.log')])
    else
    begin
      var AfterStore: ISymbolStore:= TSQLiteSymbolStore.CreateReadable(AfterDb, True);
      for var P: TUnwithFilePlan in pPlans do
        if Length(P.NewBytes) > 0 then Compare(P, AfterStore);
      AfterStore:= nil;
    end;
  except
    on E: ECompileGateCancelled do ProofFailure:= 'cancelled';
    on E: Exception do ProofFailure:= E.ClassName + ': ' + E.Message;
  end;
  { The copy can be gigabytes: it never outlives the run. The logs stay only when a message names one (DropUnwithLogs). }
  for var Tail: string in ['', '-wal', '-shm'] do
    System.SysUtils.DeleteFile(TPath.Combine(Dir, 'after-proof.sqlite') + Tail);  // dl:ok taint-path-traversal@ce76 -- a fresh scratch dir; only its PID part can come from the environment, a test seam
  if (ProofFailure = '') and (Length(Result.Rebinds) = 0) then
  begin
    Result.Applied:= True;
    TDirectory.Delete(Dir, True);  // dl:ok taint-path-traversal@8e7d -- a fresh scratch dir; only its PID part can come from the environment, a test seam
    Exit;
  end;
  var Failure:= RollBack(Gate.Tx);
  Result.RollbackFailed:= Failure <> '';
  if ProofFailure <> '' then
  begin
    Result.Refusal:= CUwProofUnavailable;
    Result.Detail:= ProofFailure;
  end
  else
  begin
    Result.Refusal:= CUwRebindAfter;
    Result.Detail:= Format('%d of %d ref(s) bind elsewhere after the rewrite, first: %s; it compiled, it does not mean the same',
      [Length(Result.Rebinds), Result.ProofPoints, Result.Rebinds[0]]);
  end;
  Result.Detail:= Result.Detail + (if Failure = '' then '; rolled back, project not changed' else '; ROLLBACK FAILED: ' + Failure);
  DropUnwithLogs(Dir, Result.Detail);
end;

end.
