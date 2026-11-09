unit DRagLint.Report.CycleHubSurface;

/// <summary>`cycles --plan --hub-surface`: recipe R3 "hub surface" (spec
/// docs\superpowers\specs\2026-11-08-hub-scc-phased.md, phase P2). For a circular group with
/// exactly one hub (cycles --hub, phase P1) whose spokes reach it through ONE global instance of a
/// hub class, the recipe plans a new leaf unit `<HubUnit>.Hub` holding an interface with one
/// property per field and one method per method the spokes read through the global, a global of
/// that interface type, the hub class implementing it (heritage, accessors, an
/// AfterConstruction / BeforeDestruction hand-over) and a receiver-only rewrite in every spoke
/// (`frmMain.edtX.Text` becomes `MainHub.edtX.Text`). Phase P3 (lane 149 CYA): a free routine of the
/// hub's interface that a rewritten spoke still calls is inverted by recipe R1 into the same unit --
/// procedural type `T&lt;Name&gt;Ptr` and variable `&lt;Name&gt;Ptr` there, `&lt;Name&gt;Ptr := &lt;Name&gt;;`
/// in the hub's initialization, the spoke's calls through the pointer; the routine's body stays in the
/// hub. A spoke that no longer names anything else of the hub drops it from its uses: that uses edge is cut.</summary>
/// <remarks>OFF by default: nothing runs without `--hub-surface`. The dry run writes nothing;
/// `--apply` writes the new unit, the hub and the rewritten spokes (.BCK&lt;n&gt; backups unless
/// `--no-backup`) and runs NO compile gate (149): build the project after it. Refusals are per
/// member and per spoke, so one unsupported member leaves only the spokes that read it untouched.
/// Not thread-safe; reads the index and the sources, owns everything it allocates.</remarks>

interface

uses
  System.Classes, System.Generics.Collections, System.JSON,
  DRagLint.Core.Interfaces, DRagLint.Report.CyclePlan;

type
  /// <summary>What `cycles --plan --hub-surface` was asked for.</summary>
  THubSurfaceOptions = record
    /// <summary>True: write the plan of ONE group (the first that plans, or the chosen one).</summary>
    Apply: Boolean;
    /// <summary>True: write no .BCK&lt;n&gt; backups.</summary>
    NoBackup: Boolean;
    /// <summary>1-based group as `cycles` numbers them; 0 = every group (plan) / the first that plans (apply).</summary>
    CycleIndex: Integer;
    /// <summary>Lower-case unit stem: the group that contains it; '' = no filter.</summary>
    UnitStem: string;
    /// <summary>The platform library (read only), or nil: an ancestor's member the spokes read
    /// through the global (`frmMain.Invalidate`, TControl's) is on the surface only when the
    /// library declares it (lane 149 CYA); without one it stays refused member-unsupported.</summary>
    LibraryStore: ISymbolStore;
  end;

/// <summary>Plans recipe R3 for the circular groups and, with Apply, writes one of them.</summary>
/// <param name="pStore">The index the groups came from; read only.</param>
/// <param name="pSccs">The circular groups (ComputeSccs), lower-case unit stems.</param>
/// <param name="pGraph">The uses graph the groups were computed from; read only.</param>
/// <param name="pOptions">Group choice, apply, backups.</param>
/// <param name="pOut">Receives the plan text (markdown lines); owned by the caller.</param>
/// <returns>0 = at least one group planned (and, with Apply, written); 1 = no group could be
/// planned (every reason is in pOut); 2 = a file could not be written or a bad group choice.</returns>
/// <remarks>Planned only for a group with exactly one hub, one hub global and a hub class declared
/// in the hub unit; members a spoke reads that are not plain fields or methods of that class, a
/// `with &lt;global&gt; do`, a write to the global or a designer field, or a var-parameter use (also
/// `FreeAndNil` / `CreateForm` / `@` of the global) refuse that spoke, never the group; Inc / Dec of an
/// integer plain field is rewritten to an assignment. Phase P4 (lane 149 CYB): `Assigned(&lt;global&gt;)`
/// becomes `Assigned(&lt;var&gt;)`; any other bare use (the global passed as a value, compared with nil, cast)
/// becomes `&lt;var&gt;AsForm`, a nil-safe function in the surface unit over the interface's
/// `AsForm` property, typed with the hub class's one library class ancestor (refused bare-use when
/// there is not exactly one). A hub routine
/// is refused (overloaded, unsupported-directive, signature-in-cycle, duplicate-identifier) as a whole;
/// one a spoke names from its initialization / finalization, by address or under a shadowing
/// declaration stays named in that spoke only (init-order, address-of, name-shadowed), which keeps
/// that spoke's uses edge.</remarks>
function RunHubSurface(const pStore: ISymbolStore; const pSccs: TList<TArray<string>>;
  const pGraph: TCycleGraph; const pOptions: THubSurfaceOptions; const pOut: TStrings): Integer;

/// <summary>Hub-SCC phase P6 prep (lane 149 CYA; the planner's TCycleGroupHook under `cycles --plan
/// --hub-surface`): plans R3 for ONE group and, when it plans, appends the P1 hub block (`cycles --hub`)
/// and the R3 plan to pOut, so the planner skips that group's Part A / Part B.</summary>
/// <param name="pStore">The index; read only.</param>
/// <param name="pLibrary">The platform library or nil (ancestor members).</param>
/// <param name="pGroup">The group's lower-case unit stems.</param>
/// <param name="pIndex">1-based group number.</param>
/// <param name="pGraph">The uses graph.</param>
/// <param name="pOut">Receives the lines; when False only a one-line note naming R3's refusal (the planner's plan follows it).</param>
/// <returns>True when R3 planned the group (one hub, one global, at least one spoke).</returns>
/// <remarks>Writes nothing (a dry run); a group R3 refuses gets nothing here and the planner as before.</remarks>
function HubSurfaceGroupLines(const pStore, pLibrary: ISymbolStore; const pGroup: TArray<string>; pIndex: Integer;
  const pGraph: TCycleGraph; const pOut: TStrings): Boolean;

/// <summary>Hub-SCC phase P6 prep: the `cycles --causes --format json --hub-surface` fix object of ONE
/// group when R3 plans it (the planner's TCycleFixHook): `available` = the prediction breaks the group,
/// `part` = "r3", `recipe` = "hub-surface", the dry-run / apply commands, one edge per cut spoke->hub
/// edge, `reason` = '' or what keeps the group.</summary>
/// <param name="pStore">The index; read only.</param>
/// <param name="pLibrary">The platform library or nil.</param>
/// <param name="pGroup">The group's lower-case unit stems.</param>
/// <param name="pIndex">1-based group number.</param>
/// <param name="pGraph">The uses graph.</param>
/// <param name="pDbPath">The index path quoted in the commands.</param>
/// <param name="pFix">Receives the object (the caller owns it) when True; nil otherwise.</param>
/// <returns>True when R3 planned the group.</returns>
function HubSurfaceFixJson(const pStore, pLibrary: ISymbolStore; const pGroup: TArray<string>; pIndex: Integer;
  const pGraph: TCycleGraph; const pDbPath: string; out pFix: TJSONObject): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils, System.Math, System.IOUtils, System.RegularExpressions, System.Generics.Defaults,
  DRagLint.Core.Model, DRagLint.Report.CycleHub;

const
  CMaxNamedKeepers = 6;   { hub symbols named per "kept by" line }
  CMaxNamedSpokes  = 12;  { refused spokes named one per line }
  CSectionWordSpan = 20;  { characters from a section keyword's line start that hold the keyword }

type
  TMemberShape = (msReadOnly, msReadWrite, msMethod);

  { one member the spokes read through the hub global }
  THubMember = record
    Name    : string;  { as declared in the hub class }
    Shape   : TMemberShape;
    TypeText: string;  { field type; '' for a method }
    Decl    : string;  { the method's interface line; '' for a field }
    Refusal : string;  { refusal kind; '' = on the surface }
    Why     : string;
  end;

  { one spoke: a unit of the group that uses the hub }
  THubSpoke = record
    Stem     : string;
    Path     : string;
    Receivers: Integer;
    Refusal  : string;
    Why      : string;
    Keepers  : TArray<string>;  { other hub symbols the spoke still names: the edge stays }
    Kept     : TArray<string>;  { P3: why a planned hub routine stays named here (`Name`: kind -- why) }
    Values   : Integer;  { P4: bare uses passed as a value through the AsForm function }
    Assigns  : Integer;  { P4: `Assigned(<global>)` rewritten to `Assigned(<var>)` }
    NewText  : string;
  end;

  { P3: one hub free routine the rewritten spokes still call, inverted by recipe R1: a procedural
    type and variable in the surface unit, assigned in the hub's initialization, called by the spokes }
  THubRoutine = record
    Name    : string;
    PtrVar  : string;  { <Name>Ptr }
    TypeDecl: string;  { T<Name>Ptr = procedure|function<signature>; [convention;] }
    Spokes  : Integer; { spokes whose calls go through the pointer }
    Refusal : string;  { '' = inverted }
    Why     : string;
  end;

  { the plan of one group }
  THubGroupPlan = record
    Index      : Integer;
    Size       : Integer;
    Refusal    : string;
    Why        : string;
    HubStem    : string;
    HubUnit    : string;
    HubPath    : string;
    GlobalName : string;
    ClassName  : string;
    IntfName   : string;
    VarName    : string;
    SurfaceUnit: string;
    SurfacePath: string;
    SurfaceText: string;
    HubNewText : string;
    Members    : TArray<THubMember>;
    Spokes     : TArray<THubSpoke>;
    Routines   : TArray<THubRoutine>;  { P3 }
    FormType   : string;   { P4: the library class the hub class descends from (AsForm's type); '' = bare uses refused }
    FormWhy    : string;   { P4: why FormType is '' }
    FormFunc   : string;   { P4: <VarName>AsForm, the nil-safe function the spokes pass instead of the global }
    AsForm     : Boolean;  { P4: a spoke passes the global as a value: AsForm is on the surface }
    EdgesLeft  : Integer;
    Breaks     : Boolean;
  end;

  { code mask: True where a character is code (not a comment, a string or a directive) }
  TCodeMask = TArray<Boolean>;

  THubSurfacePlanner = class  // dl:ok high-response@c76f -- implementation-private; one planner per run holding the per-group state its short steps share
  private
    FStore    : ISymbolStore;
    FLib      : ISymbolStore;  { the platform library, or nil }
    FGraph    : TCycleGraph;
    FGroup    : TArray<string>;
    FHubSyms  : TArray<TSymbol>;
    FClass    : TSymbol;
    FGlobal   : TSymbol;
    FMembers  : TDictionary<string, THubMember>;  { lower-case name -> member }
    FHubIds   : TDictionary<Int64, TSymbol>;
    FEncodings: TDictionary<string, TEncoding>;  { path -> its source encoding }
    FRoutines : TDictionary<string, THubRoutine>;  { P3: lower-case routine name -> its R1 plan }
    function InGroup(const pStem: string): Boolean;
    function ReadText(const pPath: string): string;
    function FindHubSymbols(var pPlan: THubGroupPlan): Boolean;
    function MemberOf(const pName: string): THubMember;
    function AncestorMember(const pName: string; out pSym: TSymbol): Boolean;
    procedure PlanMembers(var pPlan: THubGroupPlan; const pNames: TArray<string>);
    function TypeDeclaredInGroup(const pType: string): Boolean;
    function NamesClash(var pPlan: THubGroupPlan): Boolean;
    procedure PlanFormType(var pPlan: THubGroupPlan);
    function SurfaceUsesList(const pHubText: string): string;
    function BuildSurfaceText(const pPlan: THubGroupPlan; const pUses: string): string;
    function BuildHubText(var pPlan: THubGroupPlan; const pHubText: string): Boolean;
    function PlanSpoke(const pPlan: THubGroupPlan; const pStem: string): THubSpoke;
    procedure RewriteReceivers(const pPlan: THubGroupPlan; var pSpoke: THubSpoke; const pText: string);
    procedure CollectKeepers(var pSpoke: THubSpoke);
    function RoutineOf(const pName: string): THubRoutine;
    procedure PlanRoutines(var pPlan: THubGroupPlan);
    procedure InvertCalls(const pPlan: THubGroupPlan; var pSpoke: THubSpoke);
    procedure FinishSpoke(const pPlan: THubGroupPlan; var pSpoke: THubSpoke);
    function AddRoutineAssigns(var pPlan: THubGroupPlan): Boolean;
    procedure Predict(var pPlan: THubGroupPlan);
  public
    constructor Create(const pStore, pLibrary: ISymbolStore; const pGraph: TCycleGraph);
    destructor Destroy; override;
    function PlanGroup(const pGroup: TArray<string>; pIndex: Integer): THubGroupPlan;
    function Write(const pPlan: THubGroupPlan; pNoBackup: Boolean; out pMessage: string): Boolean;
  end;

{ --- text helpers --------------------------------------------------------------------------- }

function IsIdentStart(pC: Char): Boolean;
begin
  Result:= CharInSet(pC, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(pC: Char): Boolean;
begin
  Result:= CharInSet(pC, ['A'..'Z', 'a'..'z', '_', '0'..'9']);
end;

{ the code mask of a Delphi source text: comments (braces, paren-star, double slash), directives and string literals are not code }
function CodeMaskOf(const pText: string): TCodeMask;
var
  I, N: Integer;
  procedure SkipTo(const pClose: string);
  begin
    var P:= Pos(pClose, pText, I);
    if P = 0 then P:= N + 1 - Length(pClose);
    I:= P + Length(pClose);
  end;
begin
  N:= Length(pText);
  SetLength(Result, N + 2);
  I:= 1;
  while I <= N do
  begin
    var Start:= I;
    var C:= pText[I];
    if C = '{' then SkipTo('}')
    else if (C = '(') and (I < N) and (pText[I + 1] = '*') then SkipTo('*)')
    else if (C = '/') and (I < N) and (pText[I + 1] = '/') then SkipTo(#10)
    else if C = '''' then
    begin
      Inc(I);
      while (I <= N) and (pText[I] <> '''') and (pText[I] <> #10) do Inc(I);
      Inc(I);
    end
    else
    begin
      Result[I]:= True;
      Inc(I);
      Continue;
    end;
    for var K:= Start to Min(I - 1, N) do Result[K]:= False;
  end;
end;

function LineOfPos(const pText: string; pPos: Integer): Integer;
begin
  Result:= 1;
  for var K:= 1 to pPos - 1 do
    if pText[K] = #10 then Inc(Result);
end;

function SkipBlanks(const pText: string; pPos: Integer; pCrossLines: Boolean): Integer;
begin
  Result:= pPos;
  while (Result <= Length(pText)) and CharInSet(pText[Result], [' ', #9, #13, #10]) do
  begin
    if (not pCrossLines) and CharInSet(pText[Result], [#13, #10]) then Exit;
    Inc(Result);
  end;
end;

function IdentAt(const pText: string; pPos: Integer): string;
var
  E: Integer;
begin
  E:= pPos;
  while (E <= Length(pText)) and IsIdentChar(pText[E]) do Inc(E);
  Result:= Copy(pText, pPos, E - pPos);
end;

{ the identifier that ends right before pPos (blanks skipped), '' when none }
function IdentBefore(const pText: string; pPos: Integer): string;
var
  E, S: Integer;
begin
  E:= pPos - 1;
  while (E >= 1) and CharInSet(pText[E], [' ', #9]) do Dec(E);
  S:= E;
  while (S >= 1) and IsIdentChar(pText[S]) do Dec(S);
  Result:= Copy(pText, S + 1, E - S);
end;

function CharBefore(const pText: string; pPos: Integer): Char;
var
  E: Integer;
begin
  E:= pPos - 1;
  while (E >= 1) and CharInSet(pText[E], [' ', #9, #13, #10]) do Dec(E);
  Result:= if E >= 1 then pText[E] else #0;
end;

{ the position of the '(' right before pPos (blanks skipped); the caller checked it is one }
function OpenParenBefore(const pText: string; pPos: Integer): Integer;
begin
  Result:= pPos - 1;
  while (Result > 1) and (pText[Result] <> '(') do Dec(Result);
end;

{ P4: the name of the call whose open argument list holds pPos (`Foo` of `Foo(a, <pPos>)`), searched
  back to the statement's `;`; '' when pPos is in no call }
function EnclosingCall(const pText: string; const pMask: TCodeMask; pPos: Integer): string;
var
  Depth: Integer;
begin
  Result:= '';
  Depth := 0;
  for var K:= pPos - 1 downto 1 do
    if pMask[K] then
      case pText[K] of
        ';': Exit;
        ')', ']': Inc(Depth);
        '[': Dec(Depth);
        '(':
          if Depth = 0 then Exit(IdentBefore(pText, K))
          else Dec(Depth);
      end;
end;

{ P4: True when pPos sits in the head of a `with ... do` (a `with` since the statement's `;` and no `do` after it) }
function InWithHead(const pText: string; const pMask: TCodeMask; pPos: Integer): Boolean;
var
  Seg: TStringBuilder;
  Start: Integer;
begin
  Start:= pPos - 1;
  while (Start >= 1) and not (pMask[Start] and (pText[Start] = ';')) do Dec(Start);
  Seg:= TStringBuilder.Create;
  try
    for var K:= Start + 1 to pPos - 1 do Seg.Append(if pMask[K] then pText[K] else ' ');
    var Words:= TRegEx.Matches(Seg.ToString, '(?i)\b(with|do)\b');
    Result:= (Words.Count > 0) and SameText(Words[Words.Count - 1].Value, 'with');
  finally
    Seg.Free;
  end;
end;

{ the [start, end) span of the uses clause that holds pUnit as an entry, in code; False when none }
function FindUsesEntry(const pText: string; const pMask: TCodeMask; const pUnit: string;
  out pEntryPos, pEntryLen: Integer): Boolean;
var
  M: TMatch;
begin
  pEntryPos:= 0;
  pEntryLen:= 0;
  var Pattern:= '';
  for var Seg in pUnit.Split(['.']) do Pattern:= Pattern + (if Pattern = '' then '' else '\s*\.\s*') + TRegEx.Escape(Seg);
  for M in TRegEx.Matches(pText, '(?i)\buses\b') do
  begin
    if not pMask[M.Index] then Continue;
    var EndPos:= M.Index + M.Length;
    while (EndPos <= Length(pText)) and not ((pText[EndPos] = ';') and pMask[EndPos]) do Inc(EndPos);
    var Clause:= Copy(pText, M.Index, EndPos - M.Index);
    for var E in TRegEx.Matches(Clause, '(?i)(?<![\w.])' + Pattern + '(?![\w.]|\s+\.)') do
      if pMask[M.Index + E.Index - 1] then
      begin
        pEntryPos:= M.Index + E.Index - 1;
        pEntryLen:= E.Length;
        Exit(True);
      end;
  end;
  Result:= False;
end;

function JoinCrLf(const pLines: TArray<string>): string;
begin
  Result:= string.Join(#13#10, pLines);
end;

{ --- THubSurfacePlanner ---------------------------------------------------------------------- }

constructor THubSurfacePlanner.Create(const pStore, pLibrary: ISymbolStore; const pGraph: TCycleGraph);
begin
  inherited Create;
  FStore    := pStore;
  FLib      := pLibrary;
  FGraph    := pGraph;
  FMembers  := TDictionary<string, THubMember>.Create;
  FHubIds   := TDictionary<Int64, TSymbol>.Create;
  FEncodings:= TDictionary<string, TEncoding>.Create;
  FRoutines := TDictionary<string, THubRoutine>.Create;
end;

destructor THubSurfacePlanner.Destroy;
begin
  FRoutines.Free;
  FEncodings.Free;
  FHubIds.Free;
  FMembers.Free;
  inherited Destroy;
end;

function THubSurfacePlanner.InGroup(const pStem: string): Boolean;
begin
  Result:= False;
  for var U in FGroup do
    if SameText(U, pStem) then Exit(True);
end;

function THubSurfacePlanner.ReadText(const pPath: string): string;
var
  Enc: TEncoding;
begin
  Result:= DecodeSource(TFile.ReadAllBytes(pPath), Enc);
  FEncodings.AddOrSetValue(pPath, Enc);
end;

{ the hub global (the P1 spoke->hub var), its class and the class members, from the index }
function THubSurfacePlanner.FindHubSymbols(var pPlan: THubGroupPlan): Boolean;
begin
  FHubSyms:= CycleSymbolsByFile(FGraph, FStore, pPlan.HubPath);
  FHubIds.Clear;
  FGlobal:= Default(TSymbol);
  FClass := Default(TSymbol);
  for var S in FHubSyms do
  begin
    FHubIds.AddOrSetValue(S.Id, S);
    if (S.Kind = skVarDecl) and (FGlobal.Id = 0) and SameText(S.Name, pPlan.GlobalName) then FGlobal:= S;  { the unit-level var: its parent is the unit symbol }
  end;
  for var S in FHubSyms do
    if (S.Kind = skClass) and (FGlobal.Id > 0) and SameText(S.Name, Trim(FGlobal.Signature)) and (S.EndLine > S.StartLine) then FClass:= S;
  Result:= FClass.Id > 0;
  if not Result then
  begin
    pPlan.Refusal:= 'global-type';
    pPlan.Why    := Format('the type of `%s` (`%s`) is not a class declared in `%s`', [pPlan.GlobalName, Trim(FGlobal.Signature), pPlan.HubUnit]);
    Exit;
  end;
  pPlan.ClassName:= FClass.Name;
end;

function THubSurfacePlanner.TypeDeclaredInGroup(const pType: string): Boolean;
begin
  Result:= False;
  for var S in CycleSymbolsByExactName(FGraph, FStore, pType) do
    for var U in FGroup do
    begin
      var Fid: Int64;
      if FGraph.UnitFid.TryGetValue(U, Fid) and (S.FileId = Fid) and (S.Kind <> skField) and (S.Kind <> skVarDecl) then Exit(True);
    end;
end;

{ one member name read through the global: a plain field (read-only when it sits in the default
  section, i.e. a designer component; read/write under an explicit visibility) or a method }
function THubSurfacePlanner.MemberOf(const pName: string): THubMember;
var
  Found: TList<TSymbol>;
begin
  Result:= Default(THubMember);
  Result.Name:= pName;
  Found:= TList<TSymbol>.Create;
  try
    for var S in FHubSyms do
      if (S.ParentId = FClass.Id) and SameText(S.Name, pName) then Found.Add(S);
    var IsInherited:= Found.Count = 0;
    var Anc: TSymbol;
    if IsInherited then
    begin
      if not AncestorMember(pName, Anc) then
      begin
        Result.Refusal:= 'member-unsupported';
        Result.Why    := Format('`%s` is not declared in `%s` nor found in its ancestors%s', [pName, FClass.Name,
          if FLib = nil then ' (no platform library read: --library-db)' else '']);
        Exit;
      end;
      if not ContainsText(' public published ', ' ' + LowerCase(Trim(Anc.Modifiers)) + ' ') then
      begin
        Result.Refusal:= 'member-unsupported';
        Result.Why    := Format('`%s` is a %s member of an ancestor of `%s`', [Anc.Name, Trim(Anc.Modifiers), FClass.Name]);
        Exit;
      end;
      Found.Add(Anc);
    end;
    if (Found.Count > 1) or ContainsText(' ' + LowerCase(Found[0].Directives) + ' ', ' overload ') then
    begin
      Result.Refusal:= 'member-overloaded';
      Result.Why    := Format('`%s` has %d declarations in `%s`', [pName, Found.Count, FClass.Name]);
      Exit;
    end;
    var S:= Found[0];
    Result.Name:= S.Name;
    if IsInherited and (S.Kind = skField) then S.VisExplicit:= True;  { a public field of an ancestor: read/write }
    case S.Kind of
      skProperty:
        begin
          { lane 149 CYA: a property (own or inherited) goes through accessors like a field; `ro` and a bare
            redeclaration read-only, `rw` read/write, `wo` refused }
          Result.TypeText:= Trim(S.Signature.TrimLeft([':', ' ']));
          Result.Shape   := if SameText(S.PropAccess, 'rw') then msReadWrite else msReadOnly;
          if SameText(S.PropAccess, 'wo') then
          begin
            Result.Refusal:= 'member-unsupported';
            Result.Why    := Format('`%s` is a write-only property', [S.Name]);
          end
          else if not TRegEx.IsMatch(Result.TypeText, '^[A-Za-z_][\w.]*(<[\w., ]+>)?$') then
          begin
            Result.Refusal:= 'member-type';
            Result.Why    := Format('`%s: %s` is not a named type (an array property?)', [S.Name, Result.TypeText]);
          end
          else if TypeDeclaredInGroup(Result.TypeText) then
          begin
            Result.Refusal:= 'member-type-in-cycle';
            Result.Why    := Format('the type of `%s` (`%s`) is declared in a unit of the cycle', [S.Name, Result.TypeText]);
          end;
        end;
      skField:
        begin
          Result.TypeText:= Trim(S.Signature);
          Result.Shape   := if S.VisExplicit then msReadWrite else msReadOnly;
          if not TRegEx.IsMatch(Result.TypeText, '^[A-Za-z_][\w.]*(<[\w., ]+>)?$') then
          begin
            Result.Refusal:= 'member-type';
            Result.Why    := Format('`%s: %s` is not a named type (a property needs one)', [S.Name, Result.TypeText]);
          end
          else if TypeDeclaredInGroup(Result.TypeText) then
          begin
            Result.Refusal:= 'member-type-in-cycle';
            Result.Why    := Format('the type of `%s` (`%s`) is declared in a unit of the cycle', [S.Name, Result.TypeText]);
          end;
        end;
      skMethod:
        if S.IsClassMethod then
        begin
          Result.Refusal:= 'class-method';
          Result.Why    := Format('`%s` is a class method', [S.Name]);
        end
        else
        begin
          var Sig:= Trim(S.Signature);
          var Close:= Sig.LastIndexOf(')');
          var Tail:= Trim(if Close >= 0 then Sig.Substring(Close + 1) else Sig);
          Result.Shape:= msMethod;
          Result.Decl := (if Tail.StartsWith(':') then 'function ' else 'procedure ') + S.Name + Sig + ';';
        end;
    else
      Result.Refusal:= 'member-unsupported';
      Result.Why    := Format('`%s` is a %s of `%s`; the surface carries fields and methods (149)', [S.Name, if S.Kind = skProperty then 'property' else 'non-field member', FClass.Name]);
    end;
  finally
    Found.Free;
  end;
end;

{ lane 149 CYA: pName declared by an ancestor of the hub class -- the project's linked ancestors
  nearest first, then, from each name the project could not link (a library class), the library's
  classes of that name (forward declarations skipped) and their ancestors. False when none declares
  it, or when two library classes of one name disagree (VCL / FMX): the surface never guesses. A one-line `TX = class(TY);` is a class, `TX = class;` a forward. }
function THubSurfacePlanner.AncestorMember(const pName: string; out pSym: TSymbol): Boolean;
begin
  pSym:= Default(TSymbol);
  for var A in FStore.GetTransitiveAncestors(FClass.Id) do
    if A.Resolved and (A.SymbolId > 0) then
    begin
      var M:= FStore.FindChildSymbolByName(A.SymbolId, pName);
      if (M.Id > 0) and (M.Kind not in [skParam, skLocalVar]) then
      begin
        pSym:= M;
        Exit(True);
      end;
    end;
  Result:= False;
  if FLib = nil then Exit;
  var Hits:= 0;
  for var Root in FStore.UnresolvedAncestorNames(FClass.Name, FClass.FileId) do
    for var C in FLib.FindSymbolsByExactName(Root) do
    begin
      if (C.Kind <> skClass) or ((C.EndLine <= C.StartLine) and (Trim(C.Heritage) = '')) then Continue;  { a forward declaration; `TX = class(TY);` is a class }
      var Found:= Default(TSymbol);
      var M:= FLib.FindChildSymbolByName(C.Id, pName);
      if (M.Id > 0) and (M.Kind not in [skParam, skLocalVar]) then Found:= M
      else
        for var A in FLib.GetTransitiveAncestors(C.Id) do
          if (Found.Id = 0) and A.Resolved and (A.SymbolId > 0) then
          begin
            M:= FLib.FindChildSymbolByName(A.SymbolId, pName);
            if (M.Id > 0) and (M.Kind not in [skParam, skLocalVar]) then Found:= M;
          end;
      if Found.Id = 0 then Continue;
      Inc(Hits);
      if (Hits > 1) and not (SameText(Found.Signature, pSym.Signature) and (Found.Kind = pSym.Kind)) then Exit(False);
      pSym:= Found;
    end;
  Result:= Hits > 0;
end;

procedure THubSurfacePlanner.PlanMembers(var pPlan: THubGroupPlan; const pNames: TArray<string>);
var
  List: TList<THubMember>;
begin
  FMembers.Clear;
  List:= TList<THubMember>.Create;
  try
    for var N in pNames do
    begin
      if FMembers.ContainsKey(LowerCase(N)) then Continue;  { NRECS and NRecs are one field }
      var M:= MemberOf(N);
      FMembers.Add(LowerCase(N), M);
      List.Add(M);
    end;
    pPlan.Members:= List.ToArray;
  finally
    List.Free;
  end;
end;

{ the interface, its global and every accessor name must be new: no clash in the index or the class }
function THubSurfacePlanner.NamesClash(var pPlan: THubGroupPlan): Boolean;
begin
  for var N in TArray<string>.Create(pPlan.IntfName, pPlan.VarName, 'AfterConstruction', 'BeforeDestruction') do
  begin
    var Hit:= False;
    if (N = pPlan.IntfName) or (N = pPlan.VarName) then Hit:= Length(CycleSymbolsByExactName(FGraph, FStore, N)) > 0
    else
      for var S in FHubSyms do
        if (S.ParentId = FClass.Id) and SameText(S.Name, N) then Hit:= True;
    if Hit then
    begin
      pPlan.Refusal:= if (N = pPlan.IntfName) or (N = pPlan.VarName) then 'duplicate-identifier' else 'hand-over-exists';
      pPlan.Why    := Format('`%s` already exists (%s)', [N, if pPlan.Refusal = 'duplicate-identifier' then 'the index declares it' else FClass.Name + ' declares it; the hand-over would need a merge (149)']);
      Exit(True);
    end;
  end;
  for var M in pPlan.Members do
    for var S in FHubSyms do
      if (S.ParentId = FClass.Id) and (SameText(S.Name, 'HubGet' + M.Name) or SameText(S.Name, 'HubSet' + M.Name)) then
      begin
        pPlan.Refusal:= 'duplicate-identifier';
        pPlan.Why    := Format('`%s` already declares `%s`', [FClass.Name, S.Name]);
        Exit(True);
      end;
  if TFile.Exists(pPlan.SurfacePath) then
  begin
    pPlan.Refusal:= 'duplicate-identifier';
    pPlan.Why    := Format('`%s` already exists', [pPlan.SurfacePath]);
    Exit(True);
  end;
  Result:= False;
end;

{ P4: the type of AsForm -- the one library class (a heritage name the project does not declare,
  `T`-named: an interface ancestor is `I`-named) the hub class descends from, so a spoke
  that passes the global where a TForm / TdxRibbonForm / TComponent is expected still compiles; the
  hub's interface uses (the surface unit's uses) already name its unit. '' with FormWhy when there is
  none, more than one, or AsForm's names clash. }
procedure THubSurfacePlanner.PlanFormType(var pPlan: THubGroupPlan);
var
  Roots: TList<string>;
begin
  pPlan.FormType:= '';
  pPlan.FormFunc:= pPlan.VarName + 'AsForm';
  Roots:= TList<string>.Create;
  try
    for var N in FStore.UnresolvedAncestorNames(FClass.Name, FClass.FileId) do
      if N.StartsWith('T', True) and not Roots.Contains(N) then Roots.Add(N);
    if Roots.Count <> 1 then
    begin
      pPlan.FormWhy:= Format('`%s` has %d library class ancestors (AsForm needs exactly one: %s)', [FClass.Name, Roots.Count, string.Join(', ', Roots.ToArray)]);
      Exit;
    end;
    if Length(CycleSymbolsByExactName(FGraph, FStore, pPlan.FormFunc)) > 0 then
    begin
      pPlan.FormWhy:= Format('`%s` already exists (the index declares it)', [pPlan.FormFunc]);
      Exit;
    end;
    for var S in FHubSyms do
      if (S.ParentId = FClass.Id) and MatchText(S.Name, ['AsForm', 'HubGetAsForm']) then
      begin
        pPlan.FormWhy:= Format('`%s` already declares `%s`', [FClass.Name, S.Name]);
        Exit;
      end;
    pPlan.FormType:= Roots[0];
  finally
    Roots.Free;
  end;
end;

{ the hub's interface uses entries that are not units of the cycle: the surface unit's uses (a leaf:
  a unit the hub's interface uses and that is not in the group cannot reach the hub) }
function THubSurfacePlanner.SurfaceUsesList(const pHubText: string): string;
var
  Mask: TCodeMask;
  Keep: TList<string>;
begin
  Result:= '';
  Mask:= CodeMaskOf(pHubText);
  var M:= TRegEx.Match(pHubText, '(?is)\binterface\b.*?\buses\b');
  if not M.Success then Exit;
  var P:= M.Index + M.Length;
  var Q:= P;
  while (Q <= Length(pHubText)) and not ((pHubText[Q] = ';') and Mask[Q]) do Inc(Q);
  var Code: string;
  var CodeSB:= TStringBuilder.Create;
  try
    for var K:= P to Q - 1 do CodeSB.Append(if Mask[K] then pHubText[K] else ' ');
    Code:= CodeSB.ToString;
  finally
    CodeSB.Free;
  end;
  Keep:= TList<string>.Create;
  try
    for var Entry in Code.Split([',']) do
    begin
      { `Name in 'x.pas'` (its string masked out) and `FireDAC.Comp .Client` (blanks before a dot) }
      var Name:= TRegEx.Replace(TRegEx.Replace(Trim(Entry), '\s+in\s*$', ''), '\s', '');
      if (Name <> '') and not InGroup(LowerCase(Name)) then Keep.Add(Name);
    end;
    Result:= string.Join(', ', Keep.ToArray);
  finally
    Keep.Free;
  end;
end;

function THubSurfacePlanner.BuildSurfaceText(const pPlan: THubGroupPlan; const pUses: string): string;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    L.Add('unit ' + pPlan.SurfaceUnit + ';');
    L.Add('');
    L.Add('{ drag-lint cycles --hub-surface (recipe R3): what the units of the circular group read');
    L.Add('  through ' + pPlan.GlobalName + ', as an interface, so they no longer use ' + pPlan.HubUnit + '.');
    L.Add('  ' + pPlan.ClassName + ' implements it; ' + pPlan.VarName + ' is set in its AfterConstruction');
    L.Add('  and cleared in its BeforeDestruction. }');
    L.Add('');
    L.Add('interface');
    L.Add('');
    if pUses <> '' then
    begin
      L.Add('uses');
      L.Add('  ' + pUses + ';');
      L.Add('');
    end;
    L.Add('type');
    L.Add('  ' + pPlan.IntfName + ' = interface');
    for var M in pPlan.Members do
    begin
      if M.Refusal <> '' then Continue;
      case M.Shape of
        msMethod   : L.Add('    ' + M.Decl);
        msReadOnly :
          begin
            L.Add(Format('    function HubGet%s: %s;', [M.Name, M.TypeText]));
            L.Add(Format('    property %s: %s read HubGet%0:s;', [M.Name, M.TypeText]));
          end;
        msReadWrite:
          begin
            L.Add(Format('    function HubGet%s: %s;', [M.Name, M.TypeText]));
            L.Add(Format('    procedure HubSet%s(const pValue: %s);', [M.Name, M.TypeText]));
            L.Add(Format('    property %s: %s read HubGet%0:s write HubSet%0:s;', [M.Name, M.TypeText]));
          end;
      end;
    end;
    if pPlan.AsForm then
    begin
      L.Add(Format('    function HubGetAsForm: %s;', [pPlan.FormType]));
      L.Add(Format('    property AsForm: %s read HubGetAsForm;', [pPlan.FormType]));
    end;
    L.Add('  end;');
    L.Add('');
    for var R in pPlan.Routines do
      if (R.Refusal = '') and (R.Spokes > 0) then
      begin
        L.Add(Format('  /// <summary>Signature of %s (%s), copied verbatim.</summary>', [R.Name, pPlan.HubUnit]));
        L.Add('  ' + R.TypeDecl);
        L.Add('');
      end;
    L.Add('var');
    L.Add('  ' + pPlan.VarName + ': ' + pPlan.IntfName + ';');
    for var R in pPlan.Routines do
      if (R.Refusal = '') and (R.Spokes > 0) then
      begin
        L.Add(Format('  /// <summary>Holds %s, assigned by %s in its initialization section; the units of ' +
          'its former cycle call it instead of naming the routine.</summary>', [R.Name, pPlan.HubUnit]));
        L.Add(Format('  %s: T%0:s;', [R.PtrVar]));
      end;
    L.Add('');
    if pPlan.AsForm then
    begin
      L.Add(Format('/// <summary>%s as a %s for the units that passed %s as a value; nil while %0:s is nil.</summary>',
        [pPlan.VarName, pPlan.FormType, pPlan.GlobalName]));
      L.Add(Format('function %s: %s;', [pPlan.FormFunc, pPlan.FormType]));
      L.Add('');
    end;
    L.Add('implementation');
    L.Add('');
    if pPlan.AsForm then
      L.AddRange([Format('function %s: %s;', [pPlan.FormFunc, pPlan.FormType]), 'begin',
        Format('  if %s = nil then Result:= nil else Result:= %0:s.AsForm;', [pPlan.VarName]), 'end;', '']);
    L.Add('end.');
    Result:= JoinCrLf(L.ToArray) + #13#10;
  finally
    L.Free;
  end;
end;

{ the hub's new text: interface uses + the surface unit, heritage + the interface, accessors and the
  hand-over declared before the class's `end;`, their bodies before initialization / finalization / end. }
function THubSurfacePlanner.BuildHubText(var pPlan: THubGroupPlan; const pHubText: string): Boolean;
var
  Lines: TList<string>;
  Decls, Bodies: TList<string>;
  procedure Refuse(const pWhy: string);
  begin
    pPlan.Refusal:= 'manual-edit';
    pPlan.Why    := pWhy;
  end;
begin
  Result:= False;
  Lines := TList<string>.Create;
  Decls := TList<string>.Create;
  Bodies:= TList<string>.Create;
  try
    Lines.AddRange(StringReplace(pHubText, #13#10, #10, [rfReplaceAll]).Split([#10]));
    { the class's last line and the unit's end, located before anything moves }
    var EndIdx:= FClass.EndLine - 1;
    if (EndIdx < 0) or (EndIdx >= Lines.Count) or not TRegEx.IsMatch(Lines[EndIdx], '(?i)^\s*end\s*;') then
    begin
      Refuse(Format('line %d of `%s` is not the `end;` of `%s`', [FClass.EndLine, ExtractFileName(pPlan.HubPath), FClass.Name]));
      Exit;
    end;
    var BodyIdx:= -1;
    for var K:= Lines.Count - 1 downto EndIdx + 1 do
      if TRegEx.IsMatch(Lines[K], '(?i)^\s*(initialization|finalization)\b') then BodyIdx:= K
      else if (BodyIdx < 0) and TRegEx.IsMatch(Lines[K], '(?i)^\s*end\s*\.') then BodyIdx:= K;
    var HeadIdx:= FClass.StartLine - 1;
    var Head:= TRegEx.Match(Lines[HeadIdx], '(?i)=\s*class\s*\(([^)]*)\)');
    if (BodyIdx < 0) or not Head.Success then
    begin
      Refuse(Format('`%s`: no one-line `class(...)` heritage on line %d, or no unit end', [ExtractFileName(pPlan.HubPath), FClass.StartLine]));
      Exit;
    end;
    Decls.Add('    private { drag-lint cycles --hub-surface: the ' + pPlan.IntfName + ' accessors }');
    for var M in pPlan.Members do
    begin
      if (M.Refusal <> '') or (M.Shape = msMethod) then Continue;
      Decls.Add(Format('      function HubGet%s: %s;', [M.Name, M.TypeText]));
      Bodies.AddRange([Format('function %s.HubGet%s: %s;', [FClass.Name, M.Name, M.TypeText]), 'begin', '  Result:= ' + M.Name + ';', 'end;', '']);
      if M.Shape = msReadWrite then
      begin
        Decls.Add(Format('      procedure HubSet%s(const pValue: %s);', [M.Name, M.TypeText]));
        Bodies.AddRange([Format('procedure %s.HubSet%s(const pValue: %s);', [FClass.Name, M.Name, M.TypeText]), 'begin', '  ' + M.Name + ':= pValue;', 'end;', '']);
      end;
    end;
    if pPlan.AsForm then
    begin
      Decls.Add(Format('      function HubGetAsForm: %s;', [pPlan.FormType]));
      Bodies.AddRange([Format('function %s.HubGetAsForm: %s;', [FClass.Name, pPlan.FormType]), 'begin', '  Result:= Self;', 'end;', '']);
    end;
    Decls.AddRange(['    public', '      procedure AfterConstruction; override;', '      procedure BeforeDestruction; override;']);
    Bodies.AddRange([Format('procedure %s.AfterConstruction;', [FClass.Name]), 'begin',
      Format('  %s:= Self; { before inherited: OnCreate code that reads %0:s already sees it }', [pPlan.VarName]),
      '  inherited AfterConstruction;', 'end;', '',
      Format('procedure %s.BeforeDestruction;', [FClass.Name]), 'begin', Format('  %s:= nil;', [pPlan.VarName]),
      '  inherited BeforeDestruction;', 'end;', '']);
    { bottom-up, so the earlier line numbers still hold }
    Lines.InsertRange(BodyIdx, Bodies);
    Lines.InsertRange(EndIdx, Decls);
    var G:= Head.Groups[1];
    Lines[HeadIdx]:= Lines[HeadIdx].Insert(G.Index - 1 + G.Length, ', ' + pPlan.IntfName);
    var Text:= JoinCrLf(Lines.ToArray);
    var Mask:= CodeMaskOf(Text);
    var UsesHit:= TRegEx.Match(Text, '(?is)\binterface\b.*?\buses\b');
    if not UsesHit.Success then
    begin
      Refuse(Format('`%s` has no interface uses clause to add `%s` to', [ExtractFileName(pPlan.HubPath), pPlan.SurfaceUnit]));
      Exit;
    end;
    var Q:= UsesHit.Index + UsesHit.Length;
    while (Q <= Length(Text)) and not ((Text[Q] = ';') and Mask[Q]) do Inc(Q);
    pPlan.HubNewText:= Text.Insert(Q - 1, ', ' + pPlan.SurfaceUnit);
    Result:= True;
  finally
    Bodies.Free;
    Decls.Free;
    Lines.Free;
  end;
end;

{ the receiver-only rewrite of one spoke; a use of the global that is not `<global>.<member>` with a
  member on the surface refuses the spoke (bare use, write, var parameter, qualified, split line) }
procedure THubSurfacePlanner.RewriteReceivers(const pPlan: THubGroupPlan; var pSpoke: THubSpoke; const pText: string);
var
  Mask: TCodeMask;
  Emit: TStringBuilder;
  Last, I: Integer;
  procedure Refuse(const pKind, pWhy: string; pAt: Integer);
  begin
    if pSpoke.Refusal <> '' then Exit;
    pSpoke.Refusal:= pKind;
    pSpoke.Why    := Format('line %d: %s', [LineOfPos(pText, pAt), pWhy]);
  end;
  { `Inc(<global>.<field>[, N])` on an integer plain field becomes `<var>.<field>:= <var>.<field> + N`
    (a property cannot be a var parameter); False leaves it to the refusal }
  function TryIncDec(pAt, pMemEnd: Integer; const pMember: THubMember): Boolean;
  var
    Open, Start, Close, Depth, Comma: Integer;
  begin
    Result:= False;
    if (pMember.Shape <> msReadWrite) or not MatchText(pMember.TypeText, ['Integer', 'Int64', 'Cardinal', 'NativeInt',
      'NativeUInt', 'Word', 'Byte', 'SmallInt', 'ShortInt', 'LongInt', 'LongWord', 'UInt64']) then Exit;
    Open := OpenParenBefore(pText, pAt);
    var Op:= IdentBefore(pText, Open);
    Start:= Open - 1;
    while (Start >= 1) and CharInSet(pText[Start], [' ', #9]) do Dec(Start);
    Start:= Start - Length(Op) + 1;
    if Start < Last then Exit;
    Close:= pMemEnd;
    Depth:= 1;
    Comma:= 0;
    while (Close <= Length(pText)) and (Depth > 0) do
    begin
      if Mask[Close] then
        case pText[Close] of
          '(', '[': Inc(Depth);
          ')', ']': Dec(Depth);
          ',': if (Depth = 1) and (Comma = 0) then Comma:= Close;
          ';': Exit;
        end;
      if Depth > 0 then Inc(Close);
    end;
    if Depth > 0 then Exit;
    if Trim(Copy(pText, pMemEnd, (if Comma > 0 then Comma else Close) - pMemEnd)) <> '' then Exit;
    var Step:= if Comma > 0 then '(' + Trim(Copy(pText, Comma + 1, Close - Comma - 1)) + ')' else '1';
    var Target:= pPlan.VarName + '.' + pMember.Name;
    Emit.Append(pText, Last - 1, Start - Last).Append(Format('%s:= %0:s %s %s', [Target, if SameText(Op, 'Inc') then '+' else '-', Step]));
    Last:= Close + 1;
    I   := Close + 1;
    Inc(pSpoke.Receivers);
    Result:= True;
  end;
begin
  Mask:= CodeMaskOf(pText);
  Emit:= TStringBuilder.Create;
  try
    Last:= 1;
    I:= 1;
    while I <= Length(pText) do
    begin
      if not (Mask[I] and IsIdentStart(pText[I]) and ((I = 1) or not IsIdentChar(pText[I - 1]))) then
      begin
        Inc(I);
        Continue;
      end;
      var Id:= IdentAt(pText, I);
      if not SameText(Id, pPlan.GlobalName) then
      begin
        Inc(I, Length(Id));
        Continue;
      end;
      var Dot:= SkipBlanks(pText, I + Length(Id), False);
      if CharBefore(pText, I) = '.' then Refuse('qualified-ref', Format('`%s` qualified by its unit', [Id]), I)
      else if (Dot <= Length(pText)) and (pText[Dot] = '.') then
      begin
        var MemPos:= SkipBlanks(pText, Dot + 1, False);
        var Mem:= IdentAt(pText, MemPos);
        var After:= SkipBlanks(pText, MemPos + Length(Mem), True);
        var Member: THubMember;
        if Mem = '' then Refuse('manual-edit', Format('`%s.` continues on the next line', [Id]), I)
        else if not FMembers.TryGetValue(LowerCase(Mem), Member) then Refuse('member-unsupported', Format('`%s.%s` is not in the surface', [Id, Mem]), I)
        else if Member.Refusal <> '' then Refuse(Member.Refusal, Format('reads `%s`: %s', [Mem, Member.Why]), I)
        else if (Member.Shape = msReadOnly) and (Copy(pText, After, 2) = ':=') then Refuse('member-write', Format('`%s.%s :=` writes a component field', [Id, Mem]), I)
        else if (CharBefore(pText, I) = '(') and MatchText(IdentBefore(pText, OpenParenBefore(pText, I)), ['Inc', 'Dec']) then
        begin
          if TryIncDec(I, MemPos + Length(Mem), Member) then Continue;
          Refuse('member-write', Format('`%s.%s` is a var parameter', [Id, Mem]), I);
        end;
        Emit.Append(pText, Last - 1, I - Last).Append(pPlan.VarName);
        Last:= I + Length(Id);
        Inc(pSpoke.Receivers);
      end
      else if Copy(pText, Dot, 2) = ':=' then Refuse('member-write', Format('`%s :=` writes the global', [Id]), I)
      else if InWithHead(pText, Mask, I) then Refuse('with-member', Format('`with %s do`: a with block needs restructuring', [Id]), I)
      else if CharBefore(pText, I) = '@' then Refuse('member-write', Format('`@%s` takes the global''s address', [Id]), I)
      else
      begin
        { P4: `Assigned(<global>)` asks the surface global; any other bare use passes <var>AsForm }
        var Call:= EnclosingCall(pText, Mask, I);
        if MatchText(Call, ['FreeAndNil', 'CreateForm']) then Refuse('member-write', Format('`%s` is passed to %s by reference', [Id, Call]), I)
        else if SameText(Call, 'Assigned') and (CharBefore(pText, I) = '(') and (Dot <= Length(pText)) and (pText[Dot] = ')') then
        begin
          Emit.Append(pText, Last - 1, I - Last).Append(pPlan.VarName);
          Last:= I + Length(Id);
          Inc(pSpoke.Assigns);
        end
        else if pPlan.FormType = '' then Refuse('bare-use', Format('`%s` used as a value: %s', [Id, pPlan.FormWhy]), I)
        else
        begin
          Emit.Append(pText, Last - 1, I - Last).Append(pPlan.FormFunc);
          Last:= I + Length(Id);
          Inc(pSpoke.Values);
        end;
      end;
      Inc(I, Length(Id));
    end;
    Emit.Append(pText, Last - 1, Length(pText) - Last + 1);
    pSpoke.NewText:= Emit.ToString;
  finally
    Emit.Free;
  end;
end;

{ every other hub symbol the spoke names, by the index: while one is left the uses edge stays }
procedure THubSurfacePlanner.CollectKeepers(var pSpoke: THubSpoke);
var
  Fid : Int64;
  Seen: TDictionary<string, Integer>;
  Keys: TList<string>;
begin
  if not FGraph.UnitFid.TryGetValue(pSpoke.Stem, Fid) then Exit;
  Seen:= TDictionary<string, Integer>.Create;
  Keys:= TList<string>.Create;
  try
    for var R in CycleRefsFromFile(FGraph, FStore, Fid) do
    begin
      var S: TSymbol;
      if not FHubIds.TryGetValue(R.SymbolId, S) then Continue;
      if S.Id = FGlobal.Id then Continue;
      if (S.ParentId = FClass.Id) and SameText(R.ReceiverText, FGlobal.Name) then Continue;
      if not Seen.ContainsKey(S.Name) then Keys.Add(S.Name);
      Seen.AddOrSetValue(S.Name, 0);
    end;
    pSpoke.Keepers:= Keys.ToArray;
  finally
    Keys.Free;
    Seen.Free;
  end;
end;

function THubSurfacePlanner.PlanSpoke(const pPlan: THubGroupPlan; const pStem: string): THubSpoke;
begin
  Result:= Default(THubSpoke);
  Result.Stem:= pStem;
  FGraph.UnitFile.TryGetValue(pStem, Result.Path);
  if (Result.Path = '') or not TFile.Exists(Result.Path) then
  begin
    Result.Refusal:= 'outside-roots';
    Result.Why    := 'no source file';
    Exit;
  end;
  for var S in CycleSymbolsByFile(FGraph, FStore, Result.Path) do
    if SameText(S.Name, pPlan.GlobalName) or SameText(S.Name, pPlan.VarName) then
    begin
      Result.Refusal:= 'name-shadowed';
      Result.Why    := Format('line %d declares `%s` itself', [S.StartLine, S.Name]);
      Exit;
    end;
  var Text:= ReadText(Result.Path);
  RewriteReceivers(pPlan, Result, Text);
  if Result.Refusal <> '' then Exit;
  CollectKeepers(Result);
end;

{ the spoke's uses entry of the hub: the surface unit replaces it, or joins it while a keeper is left }
procedure THubSurfacePlanner.FinishSpoke(const pPlan: THubGroupPlan; var pSpoke: THubSpoke);
var
  Entry, EntryLen: Integer;
begin
  if pSpoke.Refusal <> '' then Exit;
  var NewText:= pSpoke.NewText;
  if not FindUsesEntry(NewText, CodeMaskOf(NewText), pPlan.HubUnit, Entry, EntryLen) then
  begin
    pSpoke.Refusal:= 'manual-edit';
    pSpoke.Why    := Format('no uses entry `%s` found', [pPlan.HubUnit]);
    Exit;
  end;
  var Repl:= if Length(pSpoke.Keepers) > 0 then pPlan.HubUnit + ', ' + pPlan.SurfaceUnit else pPlan.SurfaceUnit;
  pSpoke.NewText:= Copy(NewText, 1, Entry - 1) + Repl + Copy(NewText, Entry + EntryLen, MaxInt);
end;

{ P3: one hub free routine as recipe R1 inverts it (CycleEdge PlanRoutineInversion's shape: `<Name>Ptr`
  of type `T<Name>Ptr`, the signature verbatim); refused when it is overloaded, takes varargs, or its
  signature names a type declared in a unit of the cycle (the surface unit could not name it) }
function THubSurfacePlanner.RoutineOf(const pName: string): THubRoutine;
var
  Found: TList<TSymbol>;
  Owner: TSymbol;
begin
  Result:= Default(THubRoutine);
  Result.Name:= pName;
  Found:= TList<TSymbol>.Create;
  try
    for var S in FHubSyms do
      if (S.Kind in [skProcedure, skFunction]) and SameText(S.Name, pName) and FHubIds.TryGetValue(S.ParentId, Owner) and
        (Owner.Kind = skUnit) and SameText(S.Section, 'interface') then Found.Add(S);
    if Found.Count = 0 then Exit(Default(THubRoutine));  { not a free routine of the hub's interface }
    var S:= Found[0];
    Result.Name  := S.Name;
    Result.PtrVar:= S.Name + 'Ptr';
    var Dirs:= ' ' + LowerCase(S.Directives) + ' ';
    var Conv:= '';
    for var C in TArray<string>.Create('stdcall', 'cdecl', 'pascal', 'safecall', 'winapi') do
      if Dirs.Contains(' ' + C + ' ') then Conv:= C;
    if (Found.Count > 1) or Dirs.Contains(' overload ') then
    begin
      Result.Refusal:= 'overloaded';
      Result.Why    := Format('`%s` is overloaded (one pointer cannot carry every overload)', [S.Name]);
    end
    else if Dirs.Contains(' varargs ') then
    begin
      Result.Refusal:= 'unsupported-directive';
      Result.Why    := Format('`%s` takes varargs', [S.Name]);
    end
    else
      for var M in TRegEx.Matches(S.Signature, ':\s*(?:array\s+of\s+)?([A-Za-z_][\w.]*)', [roIgnoreCase]) do
        if (Result.Refusal = '') and TypeDeclaredInGroup(M.Groups[1].Value) then
        begin
          Result.Refusal:= 'signature-in-cycle';
          Result.Why    := Format('its signature names `%s`, declared in a unit of the cycle', [M.Groups[1].Value]);
        end;
    if (Result.Refusal = '') and ((Length(CycleSymbolsByExactName(FGraph, FStore, Result.PtrVar)) > 0) or
      (Length(CycleSymbolsByExactName(FGraph, FStore, 'T' + Result.PtrVar)) > 0)) then
    begin
      Result.Refusal:= 'duplicate-identifier';
      Result.Why    := Format('`%s` or `T%0:s` already exists', [Result.PtrVar]);
    end;
    Result.TypeDecl:= Format('T%s = %s%s;%s', [Result.PtrVar, if S.Kind = skFunction then 'function' else 'procedure',
      S.Signature, if Conv <> '' then ' ' + Conv + ';' else '']);
  finally
    Found.Free;
  end;
end;

{ P3: every keeper of a rewritten spoke that is a free routine of the hub gets its R1 plan }
procedure THubSurfacePlanner.PlanRoutines(var pPlan: THubGroupPlan);
var
  List: TList<THubRoutine>;
begin
  FRoutines.Clear;
  List:= TList<THubRoutine>.Create;
  try
    for var Sp in pPlan.Spokes do
      if Sp.Refusal = '' then
        for var K in Sp.Keepers do
        begin
          if FRoutines.ContainsKey(LowerCase(K)) then Continue;
          var R:= RoutineOf(K);
          if R.Name = '' then Continue;
          FRoutines.Add(LowerCase(K), R);
          List.Add(R);
        end;
    pPlan.Routines:= List.ToArray;
  finally
    List.Free;
  end;
end;

{ P3: the spoke's calls of every inverted routine go through its pointer (`Hub.F` too); a routine named
  from the spoke's initialization / finalization (the hub may not have assigned it yet), taken by address,
  or shadowed by a declaration of the spoke stays a keeper, with the reason in Kept }
procedure THubSurfacePlanner.InvertCalls(const pPlan: THubGroupPlan; var pSpoke: THubSpoke);
var
  Left: TList<string>;
  R   : THubRoutine;
begin
  if pSpoke.Refusal <> '' then Exit;
  var Qual:= '';
  for var Seg in pPlan.HubUnit.Split(['.']) do Qual:= Qual + TRegEx.Escape(Seg) + '\s*\.\s*';
  var Own:= CycleSymbolsByFile(FGraph, FStore, pSpoke.Path);
  Left:= TList<string>.Create;
  try
    for var K in pSpoke.Keepers do
    begin
      if not FRoutines.TryGetValue(LowerCase(K), R) or (R.Refusal <> '') then
      begin
        Left.Add(K);
        Continue;
      end;
      var Why:= '';
      for var S in Own do
        if (Why = '') and (SameText(S.Name, R.Name) or SameText(S.Name, R.PtrVar)) then
          Why:= Format('name-shadowed -- line %d declares `%s`', [S.StartLine, S.Name]);
      var Text:= pSpoke.NewText;
      var Mask:= CodeMaskOf(Text);
      var InitAt:= MaxInt;
      for var M in TRegEx.Matches(Text, '(?im)^\s*(initialization|finalization)\b') do
        if Mask[M.Index + M.Length - 1] and (M.Index < InitAt) then InitAt:= M.Index;
      var Hits:= TRegEx.Matches(Text, '(?i)(?<![\w.])(?:' + Qual + ')?' + TRegEx.Escape(R.Name) + '\b');
      for var M in Hits do
      begin
        if (Why <> '') or not Mask[M.Index] then Continue;
        if M.Index > InitAt then
          Why:= Format('init-order -- line %d calls it from the %s section', [LineOfPos(Text, M.Index),
            if ContainsText(Copy(Text, InitAt, CSectionWordSpan), 'final') then 'finalization' else 'initialization'])
        else if CharBefore(Text, M.Index) = '@' then
          Why:= Format('address-of -- line %d takes `@%s`', [LineOfPos(Text, M.Index), R.Name]);
      end;
      if Why <> '' then
      begin
        pSpoke.Kept:= pSpoke.Kept + [Format('`%s`: %s', [R.Name, Why])];
        Left.Add(K);
        Continue;
      end;
      for var I:= Hits.Count - 1 downto 0 do
        if Mask[Hits[I].Index] then Text:= Copy(Text, 1, Hits[I].Index - 1) + R.PtrVar + Copy(Text, Hits[I].Index + Hits[I].Length, MaxInt);
      pSpoke.NewText:= Text;
      R.Spokes:= R.Spokes + 1;
      FRoutines[LowerCase(K)]:= R;
    end;
    pSpoke.Keepers:= Left.ToArray;
  finally
    Left.Free;
  end;
end;

{ P3: the hub assigns every inverted routine's pointer in its initialization section (created before
  `finalization` / the unit's `end.` when it has none) }
function THubSurfacePlanner.AddRoutineAssigns(var pPlan: THubGroupPlan): Boolean;
var
  Lines  : TList<string>;
  Assigns: TList<string>;
begin
  Result:= True;
  Assigns:= TList<string>.Create;
  Lines  := TList<string>.Create;
  try
    for var R in pPlan.Routines do
      if (R.Refusal = '') and (R.Spokes > 0) then Assigns.Add(Format('  %s := %s;', [R.PtrVar, R.Name]));
    if Assigns.Count = 0 then Exit;
    Lines.AddRange(StringReplace(pPlan.HubNewText, #13#10, #10, [rfReplaceAll]).Split([#10]));
    var InitIdx:= -1;
    var FinIdx := -1;
    var EndIdx := -1;
    for var K:= Lines.Count - 1 downto 0 do
      if TRegEx.IsMatch(Lines[K], '(?i)^initialization\b') then InitIdx:= K
      else if TRegEx.IsMatch(Lines[K], '(?i)^finalization\b') then FinIdx:= K
      else if (EndIdx < 0) and TRegEx.IsMatch(Lines[K], '(?i)^end\s*\.') then EndIdx:= K;
    if InitIdx >= 0 then Lines.InsertRange(InitIdx + 1, Assigns)
    else if (FinIdx >= 0) or (EndIdx >= 0) then
    begin
      Assigns.Insert(0, 'initialization');
      Assigns.Add('');
      Lines.InsertRange(if FinIdx >= 0 then FinIdx else EndIdx, Assigns);
    end
    else
    begin
      pPlan.Refusal:= 'manual-edit';
      pPlan.Why    := Format('`%s` has no initialization section and no final `end.`', [ExtractFileName(pPlan.HubPath)]);
      Exit(False);
    end;
    pPlan.HubNewText:= JoinCrLf(Lines.ToArray);
  finally
    Lines.Free;
    Assigns.Free;
  end;
end;

{ the group after the plan: the cut spoke->hub edges removed, is it acyclic? (Kahn) }
procedure THubSurfacePlanner.Predict(var pPlan: THubGroupPlan);
var
  Cut  : TDictionary<string, Boolean>;
  InDeg: TDictionary<string, Integer>;
  Queue: TQueue<string>;
  L    : TList<string>;
  D    : Integer;
begin
  Cut  := TDictionary<string, Boolean>.Create;
  InDeg:= TDictionary<string, Integer>.Create;
  Queue:= TQueue<string>.Create;
  try
    for var S in pPlan.Spokes do
      if (S.Refusal = '') and (Length(S.Keepers) = 0) then Cut.AddOrSetValue(S.Stem, True);
    pPlan.EdgesLeft:= 0;
    for var U in FGroup do InDeg.AddOrSetValue(U, 0);
    for var U in FGroup do
      if FGraph.Adj.TryGetValue(U, L) then
        for var V in L do
          if (V <> U) and InDeg.TryGetValue(V, D) and not ((V = pPlan.HubStem) and Cut.ContainsKey(U)) then
          begin
            InDeg[V]:= D + 1;
            if V = pPlan.HubStem then Inc(pPlan.EdgesLeft);
          end;
    for var P in InDeg do
      if P.Value = 0 then Queue.Enqueue(P.Key);
    var Seen:= 0;
    while Queue.Count > 0 do
    begin
      var U:= Queue.Dequeue;
      Inc(Seen);
      if FGraph.Adj.TryGetValue(U, L) then
        for var V in L do
          if (V <> U) and InDeg.TryGetValue(V, D) and not ((V = pPlan.HubStem) and Cut.ContainsKey(U)) then
          begin
            InDeg[V]:= D - 1;
            if D = 1 then Queue.Enqueue(V);
          end;
    end;
    pPlan.Breaks:= Seen = InDeg.Count;
  finally
    Queue.Free;
    InDeg.Free;
    Cut.Free;
  end;
end;

function THubSurfacePlanner.PlanGroup(const pGroup: TArray<string>; pIndex: Integer): THubGroupPlan;
var
  L: TList<string>;
  Spokes: TList<THubSpoke>;
begin
  Result:= Default(THubGroupPlan);
  Result.Index:= pIndex;
  Result.Size := Length(pGroup);
  FGroup:= pGroup;
  var Hub:= AnalyseCycleHubs(FStore, pGroup, FGraph);
  if Length(Hub.Hubs) <> 1 then
  begin
    Result.Refusal:= 'not-hub-shaped';
    Result.Why    := Format('%d hubs (the recipe needs exactly one; cycles --hub names them)', [Length(Hub.Hubs)]);
    Exit;
  end;
  Result.HubStem:= Hub.Hubs[0].UnitStem;
  var Globals:= TList<TCycleHubSymbol>.Create;
  try
    for var S in Hub.Hubs[0].SpokeToHub do
      if S.Kind = 'var' then Globals.Add(S);
    if Globals.Count <> 1 then
    begin
      Result.Refusal:= 'not-hub-shaped';
      Result.Why    := Format('the spokes read %d hub globals (the recipe plans one; 149)', [Globals.Count]);
      Exit;
    end;
    Result.GlobalName:= Globals[0].Name;
    var Names: TArray<string>;
    for var M in Globals[0].Members do Names:= Names + [M.Name];
    FGraph.UnitFile.TryGetValue(Result.HubStem, Result.HubPath);
    if (Result.HubPath = '') or not TFile.Exists(Result.HubPath) or not FindHubSymbols(Result) then
    begin
      if Result.Refusal = '' then
      begin
        Result.Refusal:= 'outside-roots';
        Result.Why    := Format('no source for `%s`', [Result.HubStem]);
      end;
      Exit;
    end;
    var HubText:= ReadText(Result.HubPath);
    var UnitHead:= TRegEx.Match(HubText, '(?im)^\s*unit\s+([\w.]+)\s*;');
    Result.HubUnit:= if UnitHead.Success then UnitHead.Groups[1].Value else ChangeFileExt(ExtractFileName(Result.HubPath), '');
    var Seg:= Result.HubUnit.Substring(Result.HubUnit.LastIndexOf('.') + 1);
    Result.IntfName   := 'I' + Seg + 'Hub';
    Result.VarName    := Seg + 'Hub';
    Result.SurfaceUnit:= Result.HubUnit + '.Hub';
    Result.SurfacePath:= TPath.Combine(ExtractFilePath(Result.HubPath), Result.SurfaceUnit + '.pas');
    PlanMembers(Result, Names);
    if NamesClash(Result) then Exit;
    PlanFormType(Result);
    Spokes:= TList<THubSpoke>.Create;
    try
      for var U in pGroup do
        if (U <> Result.HubStem) and FGraph.Adj.TryGetValue(U, L) and L.Contains(Result.HubStem) then Spokes.Add(PlanSpoke(Result, U));
      Result.Spokes:= Spokes.ToArray;
    finally
      Spokes.Free;
    end;
    { P4: AsForm joins the surface (and the hub's accessors) only when a rewritten spoke passes the global }
    for var S in Result.Spokes do
      if (S.Refusal = '') and (S.Values > 0) then Result.AsForm:= True;
    { P3: the hub's free routines the rewritten spokes still call go through R1 pointers in the surface unit }
    PlanRoutines(Result);
    for var I:= 0 to High(Result.Spokes) do
    begin
      InvertCalls(Result, Result.Spokes[I]);
      FinishSpoke(Result, Result.Spokes[I]);
    end;
    for var I:= 0 to High(Result.Routines) do Result.Routines[I]:= FRoutines[LowerCase(Result.Routines[I].Name)];
    if not BuildHubText(Result, HubText) or not AddRoutineAssigns(Result) then Exit;
    Result.SurfaceText:= BuildSurfaceText(Result, SurfaceUsesList(HubText));
  finally
    Globals.Free;
  end;
  Predict(Result);
end;

function THubSurfacePlanner.Write(const pPlan: THubGroupPlan; pNoBackup: Boolean; out pMessage: string): Boolean;
var
  Files: TDictionary<string, string>;
  procedure Backup(const pPath: string);
  begin
    var N:= 1;
    while TFile.Exists(pPath + '.BCK' + IntToStr(N)) do Inc(N);
    TFile.Copy(pPath, pPath + '.BCK' + IntToStr(N));
  end;
  function EncodingOf(const pPath: string): TEncoding;
  begin
    if not FEncodings.TryGetValue(pPath, Result) then Result:= TEncoding.ANSI;
  end;
begin
  Files:= TDictionary<string, string>.Create;
  try
    Files.Add(pPlan.HubPath, pPlan.HubNewText);
    for var S in pPlan.Spokes do
      if S.Refusal = '' then Files.Add(S.Path, S.NewText);
    try
      for var P in Files do
      begin
        if not pNoBackup then Backup(P.Key);
        TFile.WriteAllBytes(P.Key, EncodeSource(P.Value, EncodingOf(P.Key)));
      end;
      TFile.WriteAllBytes(pPlan.SurfacePath, EncodeSource(pPlan.SurfaceText, EncodingOf(pPlan.HubPath)));
      pMessage:= Format('written: %d files + new `%s`%s', [Files.Count, ExtractFileName(pPlan.SurfacePath),
        if pNoBackup then ' (no backups)' else ' (.BCK<n> backups beside them)']);
      Result:= True;
    except
      on E: Exception do
      begin
        pMessage:= 'write failed part-way: ' + E.Message + ' -- restore from the .BCK<n> backups';
        Result:= False;
      end;
    end;
  finally
    Files.Free;
  end;
end;

{ --- rendering -------------------------------------------------------------------------------- }

procedure RenderMembers(const pPlan: THubGroupPlan; const pOut: TStrings);
var
  RO, RW, Meth, Bad: Integer;
begin
  RO  := 0;
  RW  := 0;
  Meth:= 0;
  Bad := 0;
  for var M in pPlan.Members do
    if M.Refusal <> '' then Inc(Bad)
    else case M.Shape of
      msReadOnly : Inc(RO);
      msReadWrite: Inc(RW);
      msMethod   : Inc(Meth);
    end;
  pOut.Add(Format('- surface: %d of %d members -- %d read-only (designer fields), %d read/write (plain fields), %d methods',
    [Length(pPlan.Members) - Bad, Length(pPlan.Members), RO, RW, Meth]));
  for var M in pPlan.Members do
    if M.Refusal <> '' then pOut.Add(Format('  - refused member `%s`: %s -- %s', [M.Name, M.Refusal, M.Why]));
end;

procedure RenderSpokes(const pPlan: THubGroupPlan; const pOut: TStrings);
var
  Done, Refused, Rec, Cut: Integer;
  Keep: TDictionary<string, Integer>;
  Named: Integer;
begin
  Done   := 0;
  Refused:= 0;
  Rec    := 0;
  Cut    := 0;
  Named  := 0;
  Keep:= TDictionary<string, Integer>.Create;
  try
    for var S in pPlan.Spokes do
      if S.Refusal <> '' then Inc(Refused)
      else
      begin
        Inc(Done);
        Inc(Rec, S.Receivers);
        if Length(S.Keepers) = 0 then Inc(Cut);
        for var K in S.Keepers do
        begin
          var C: Integer;
          if not Keep.TryGetValue(K, C) then C:= 0;
          Keep.AddOrSetValue(K, C + 1);
        end;
      end;
    pOut.Add(Format('- spokes: %d rewritten (%d receivers `%s.` -> `%s.`), %d refused', [Done, Rec, pPlan.GlobalName, pPlan.VarName, Refused]));
    for var S in pPlan.Spokes do
      if (S.Refusal <> '') and (Named < CMaxNamedSpokes) then
      begin
        pOut.Add(Format('  - refused `%s`: %s -- %s', [ExtractFileName(S.Path), S.Refusal, S.Why]));
        Inc(Named);
      end;
    if Refused > Named then pOut.Add(Format('  - (+%d more refused spokes)', [Refused - Named]));
    var KeepText: string;
    var KeepList:= TList<string>.Create;
    try
      var Pairs:= Keep.ToArray;
      TArray.Sort<TPair<string, Integer>>(Pairs, TComparer<TPair<string, Integer>>.Construct(
        function(const A, B: TPair<string, Integer>): Integer
        begin
          Result:= B.Value - A.Value;
          if Result = 0 then Result:= CompareText(A.Key, B.Key);
        end));
      for var K:= 0 to Min(High(Pairs), CMaxNamedKeepers - 1) do KeepList.Add(Format('`%s` %d', [Pairs[K].Key, Pairs[K].Value]));
      KeepText:= string.Join(', ', KeepList.ToArray);
    finally
      KeepList.Free;
    end;
    pOut.Add(Format('- uses: %d spokes drop `%s` (edge cut); %d keep it for other hub symbols%s', [Cut, pPlan.HubUnit, Done - Cut,
      if KeepText = '' then '' else ': ' + KeepText]));
  finally
    Keep.Free;
  end;
end;

{ P3: the hub routines R1 inverts, the refused ones and the spokes that keep a routine by name }
procedure RenderRoutines(const pPlan: THubGroupPlan; const pOut: TStrings);
var
  Done : TList<string>;
  Named: Integer;
begin
  if Length(pPlan.Routines) = 0 then Exit;
  Done:= TList<string>.Create;
  try
    for var R in pPlan.Routines do
      if (R.Refusal = '') and (R.Spokes > 0) then Done.Add(Format('`%s` -> `%s` (%d spokes)', [R.Name, R.PtrVar, R.Spokes]));
    pOut.Add(Format('- hub routines (R1, phase P3): %d of %d inverted through pointers in `%s`%s', [Done.Count, Length(pPlan.Routines),
      pPlan.SurfaceUnit, if Done.Count = 0 then '' else ': ' + string.Join(', ', Done.ToArray)]));
  finally
    Done.Free;
  end;
  for var R in pPlan.Routines do
    if R.Refusal <> '' then pOut.Add(Format('  - refused routine `%s`: %s -- %s', [R.Name, R.Refusal, R.Why]));
  Named:= 0;
  for var S in pPlan.Spokes do
    for var K in S.Kept do
    begin
      if Named < CMaxNamedSpokes then pOut.Add(Format('  - `%s` keeps %s', [ExtractFileName(S.Path), K]));
      Inc(Named);
    end;
  if Named > CMaxNamedSpokes then pOut.Add(Format('  - (+%d more spokes keep a routine)', [Named - CMaxNamedSpokes]));
end;

{ P4: the bare uses of the global the rewritten spokes carry }
procedure RenderBareUses(const pPlan: THubGroupPlan; const pOut: TStrings);
var
  Values, Assigns: Integer;
begin
  Values := 0;
  Assigns:= 0;
  for var S in pPlan.Spokes do
    if S.Refusal = '' then
    begin
      Inc(Values, S.Values);
      Inc(Assigns, S.Assigns);
    end;
  if Values + Assigns = 0 then Exit;
  if Values = 0 then
    pOut.Add(Format('- bare uses (phase P4): %d `Assigned(%s)` -> `Assigned(%s)`; 0 passed as a value', [Assigns, pPlan.GlobalName, pPlan.VarName]))
  else
    pOut.Add(Format('- bare uses (phase P4): %d `Assigned(%s)` -> `Assigned(%s)`; %d passed as a value through `%s: %s` (`%2:s.AsForm`, nil while `%2:s` is nil)',
      [Assigns, pPlan.GlobalName, pPlan.VarName, Values, pPlan.FormFunc, pPlan.FormType]));
end;

procedure RenderGroup(const pPlan: THubGroupPlan; const pOut: TStrings);
begin
  pOut.Add(Format('## Group %d (%d units): hub-surface recipe R3', [pPlan.Index, pPlan.Size]));
  if pPlan.Refusal <> '' then
  begin
    pOut.Add(Format('- no plan: refused: %s -- %s', [pPlan.Refusal, pPlan.Why]));
    pOut.Add('');
    Exit;
  end;
  pOut.Add(Format('- hub `%s`, global `%s`: `%s` -> interface `%s` in the new unit `%s` (%s), global `%s`',
    [pPlan.HubUnit, pPlan.GlobalName, pPlan.ClassName, pPlan.IntfName, pPlan.SurfaceUnit, ExtractFileName(pPlan.SurfacePath), pPlan.VarName]));
  RenderMembers(pPlan, pOut);
  RenderRoutines(pPlan, pOut);
  RenderSpokes(pPlan, pOut);
  RenderBareUses(pPlan, pOut);
  pOut.Add(Format('- hub edits (`%s`): interface uses + `%s`; heritage + `%s`; accessors; hand-over `%s:= Self` in AfterConstruction (before inherited), `%3:s:= nil` in BeforeDestruction',
    [ExtractFileName(pPlan.HubPath), pPlan.SurfaceUnit, pPlan.IntfName, pPlan.VarName]));
  if pPlan.Breaks then pOut.Add(Format('- prediction: the group breaks -- no cycle left among these %d units', [pPlan.Size]))
  else pOut.Add(Format('- prediction: the group stays -- %d spoke->hub edges remain', [pPlan.EdgesLeft]));
  pOut.Add(Format('- new unit `%s`:', [ExtractFileName(pPlan.SurfacePath)]));
  pOut.Add('```pascal');
  pOut.AddStrings(pPlan.SurfaceText.TrimRight.Split([#13#10]));
  pOut.Add('```');
end;

function RunHubSurface(const pStore: ISymbolStore; const pSccs: TList<TArray<string>>;
  const pGraph: TCycleGraph; const pOptions: THubSurfaceOptions; const pOut: TStrings): Integer;
var
  Planner: THubSurfacePlanner;
begin
  if (pOptions.CycleIndex < 0) or (pOptions.CycleIndex > pSccs.Count) then
  begin
    pOut.Add(Format('ERROR: --cycle %d: there are %d circular groups', [pOptions.CycleIndex, pSccs.Count]));
    Exit(2);
  end;
  Result:= 1;
  Planner:= THubSurfacePlanner.Create(pStore, pOptions.LibraryStore, pGraph);
  try
    for var I:= 0 to pSccs.Count - 1 do
    begin
      if (pOptions.CycleIndex > 0) and (I <> pOptions.CycleIndex - 1) then Continue;
      if (pOptions.UnitStem <> '') and not MatchText(pOptions.UnitStem, pSccs[I]) then Continue;
      var Plan:= Planner.PlanGroup(pSccs[I], I + 1);
      RenderGroup(Plan, pOut);
      var Planned:= (Plan.Refusal = '') and (Length(Plan.Spokes) > 0);
      if Planned and (Result = 1) then Result:= 0;
      if not (pOptions.Apply and Planned) then
      begin
        if Planned then pOut.Add('- dry run: nothing written (add --apply to write this group)');
        pOut.Add('');
        Continue;
      end;
      var Msg: string;
      if Planner.Write(Plan, pOptions.NoBackup, Msg) then
        pOut.Add('- ' + Msg + '; the engine runs no compile gate for R3 yet: build the project now (149)')
      else
      begin
        pOut.Add('- ERROR: ' + Msg);
        Result:= 2;
      end;
      pOut.Add('');
      Break;  { --apply writes ONE group }
    end;
  finally
    Planner.Free;
  end;
  if pSccs.Count = 0 then pOut.Add('No circular unit dependencies found.');
end;

function HubSurfaceGroupLines(const pStore, pLibrary: ISymbolStore; const pGroup: TArray<string>; pIndex: Integer;
  const pGraph: TCycleGraph; const pOut: TStrings): Boolean;
var
  Planner: THubSurfacePlanner;
begin
  Planner:= THubSurfacePlanner.Create(pStore, pLibrary, pGraph);
  try
    var Plan:= Planner.PlanGroup(pGroup, pIndex);
    Result:= (Plan.Refusal = '') and (Length(Plan.Spokes) > 0);
    if not Result then
    begin
      if Plan.Refusal <> '' then pOut.Add(Format('- group %d: hub-surface recipe R3 refused: %s -- %s; the planner''s plan follows', [pIndex, Plan.Refusal, Plan.Why]));
      Exit;
    end;
    pOut.Add(Format('## Group %d (%d units): hub-shaped -- recipe R3 in place of Part A / Part B (--hub-surface)', [pIndex, Length(pGroup)]));
    pOut.AddStrings(CycleHubLines(AnalyseCycleHubs(pStore, pGroup, pGraph)));
    pOut.Add('');
    RenderGroup(Plan, pOut);
    pOut.Add(Format('- dry run: nothing written (write it: cycles --plan --hub-surface --cycle %d --apply)', [pIndex]));
    pOut.Add('');
  finally
    Planner.Free;
  end;
end;

function HubSurfaceFixJson(const pStore, pLibrary: ISymbolStore; const pGroup: TArray<string>; pIndex: Integer;
  const pGraph: TCycleGraph; const pDbPath: string; out pFix: TJSONObject): Boolean;
var
  Planner: THubSurfacePlanner;
begin
  pFix:= nil;
  Planner:= THubSurfacePlanner.Create(pStore, pLibrary, pGraph);
  try
    var Plan:= Planner.PlanGroup(pGroup, pIndex);
    Result:= (Plan.Refusal = '') and (Length(Plan.Spokes) > 0);
    if not Result then Exit;
    var Cmd:= Format('drag-lint cycles --plan --hub-surface --db "%s" --cycle %d', [pDbPath, pIndex]);
    pFix:= TJSONObject.Create;
    pFix.AddPair('available', TJSONBool.Create(Plan.Breaks));
    pFix.AddPair('part', 'r3');
    pFix.AddPair('recipe', 'hub-surface');
    pFix.AddPair('dry_run', Cmd);
    pFix.AddPair('apply', Cmd + ' --apply');
    var Edges:= TJSONArray.Create;
    pFix.AddPair('edges', Edges);
    for var S in Plan.Spokes do
      if (S.Refusal = '') and (Length(S.Keepers) = 0) then
      begin
        var E:= TJSONObject.Create;
        E.AddPair('from', ChangeFileExt(ExtractFileName(S.Path), ''));
        E.AddPair('to', Plan.HubUnit);
        E.AddPair('recipe', 'hub-surface');
        E.AddPair('chosen', TJSONBool.Create(True));
        Edges.AddElement(E);
      end;
    pFix.AddPair('reason', if Plan.Breaks then '' else Format('the group stays -- %d spoke->hub edges remain', [Plan.EdgesLeft]));
  finally
    Planner.Free;
  end;
end;

end.
