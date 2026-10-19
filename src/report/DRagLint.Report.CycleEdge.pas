unit DRagLint.Report.CycleEdge;

// ---------------------------------------------------------------------------
// E18 Task 4 -- the SURFACE of one unit edge A -> B of a circular group: what
// A actually does with B, read from index facts only (refs, member_accesses,
// symbols). The `cycles --fix` rewrites (R1 routine-call inversion, R2 member
// hand-over through an extracted interface) decide from this record whether an
// edge has their shape; `cycles --format json --causes` prints it per edge.
//
// Index facts this unit relies on (demo DB, 2026-10-19): an `is` / `as`
// operand, a cast and a var declaration are all refs.kind 'type_use' -- told
// apart by the line text (ClassifyTypeUse); a construction / class-method call
// is a 'read' of the class name plus a 'call' whose receiver_text is the class
// name; member reads and writes are member_accesses rows; class refs carry no
// symbol_id and are bound by NAME against the units the citing unit uses.
//
// F2047 ruling: this unit's interface must not use DRagLint.Report.CyclePlan
// (CyclePlan uses this unit). The planner hands its index access in through
// IEdgeSurfaceSource instead.
// ---------------------------------------------------------------------------

interface

uses
  System.JSON,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>What one reference on an edge A -&gt; B does with unit B.</summary>
  /// <remarks>erTypeIs / erTypeAs / erTypeCast / erTypeDecl split refs.kind
  /// 'type_use' by the line text; erClassReceiver is a call through a class of B
  /// (`TFoo.Create`, `TFoo.CreateForFolder`); erMemberRead is a member of a type of
  /// B read through an instance; erMemberWrite is any write to a variable or member
  /// of B; erOther is everything else bound to B (a plain read, a class name passed
  /// as a value).</remarks>
  TEdgeRefKind = (erCall, erTypeIs, erTypeAs, erTypeCast, erTypeDecl, erClassReceiver,
                  erMemberRead, erMemberWrite, erOther);

  /// <summary>One reference of unit A that binds to unit B.</summary>
  TEdgeRef = record
    /// <summary>1-based line in A.</summary>
    Line: Integer;
    /// <summary>What the reference does.</summary>
    Kind: TEdgeRefKind;
    /// <summary>The name as the ref records it (refs.name_text).</summary>
    Name: string;
    /// <summary>Name of the routine whose body holds the ref; '' outside a body.</summary>
    Enclosing: string;
    /// <summary>The trimmed source line.</summary>
    LineText: string;
    /// <summary>Id of the symbol of B the ref binds to (the member for a member
    /// access, the top-level declaration otherwise).</summary>
    SymbolId: Int64;
  end;

  /// <summary>One type a routine signature names.</summary>
  TSigType = record
    /// <summary>The identifier as written in the signature (a dotted name keeps its unit prefix).</summary>
    Name: string;
    /// <summary>Lower-case stem of the unit that declares it; '' when no index row resolves it.</summary>
    DeclStem: string;
    /// <summary>True when DeclStem is a unit of the circular group.</summary>
    InScc: Boolean;
  end;

  /// <summary>Everything unit FromStem takes from unit ToStem, as index facts.</summary>
  TEdgeSurface = record
    /// <summary>Lower-case stem of the citing unit A.</summary>
    FromStem: string;
    /// <summary>Lower-case stem of the used unit B.</summary>
    ToStem: string;
    /// <summary>Every reference of A bound to B, in index order.</summary>
    Refs: TArray<TEdgeRef>;
    /// <summary>Distinct classes of B that A references, sorted.</summary>
    ClassNames: TArray<string>;
    /// <summary>Distinct members of B's types that A READS (member_accesses mode
    /// 'read'), sorted.</summary>
    Members: TArray<string>;
    /// <summary>A writes a variable or member of B.</summary>
    HasWrite: Boolean;
    /// <summary>A calls a constructor through a class of B.</summary>
    HasConstruction: Boolean;
    /// <summary>A calls a non-constructor method through a class of B.</summary>
    HasClassMethod: Boolean;
    /// <summary>A passes a class of B as a value (a read of the class name with no
    /// call through it on that line -- the `FindMDIChildForFolder(TfrmX, ...)` shape).</summary>
    HasClassRefArg: Boolean;
    /// <summary>A declares something of a type of B (`X: TFoo`).</summary>
    HasDecl: Boolean;
    /// <summary>Set when the edge binds exactly ONE declaration of B and it is a
    /// routine: its name; '' otherwise.</summary>
    RoutineName: string;
    /// <summary>That routine's verbatim symbols.signature; '' otherwise.</summary>
    RoutineSig: string;
    /// <summary>The types RoutineSig names (see SignatureTypes); empty otherwise.</summary>
    SigTypes: TArray<TSigType>;
    /// <summary>Number of call refs of A bound to B.</summary>
    CallCount: Integer;
  end;

  /// <summary>The index access BuildEdgeSurface needs from the cycle planner.</summary>
  /// <remarks>Implemented by the planner of DRagLint.Report.CyclePlan, which keeps
  /// its own lifetime (not reference counted). All stems are lower-case unit stems.</remarks>
  IEdgeSurfaceSource = interface
    ['{006CBD32-42DF-4902-BDF8-4DCA48B4C968}']
    /// <summary>The open index.</summary>
    /// <returns>The store; never nil.</returns>
    function Store: ISymbolStore;
    /// <summary>The source lines of an indexed file.</summary>
    /// <param name="pFid">File id.</param>
    /// <returns>The lines, empty when the file is gone.</returns>
    function FileLines(pFid: Int64): TArray<string>;
    /// <summary>File id of a unit stem.</summary>
    /// <param name="pStem">Lower-case unit stem.</param>
    /// <returns>The id, or 0 when no indexed file has that stem.</returns>
    function FidOfStem(const pStem: string): Int64;
    /// <summary>Binds a bare name the way Delphi does at one line of a file: its
    /// own declaration first, else the LAST visible used unit that exports it.</summary>
    /// <param name="pFid">The citing file.</param>
    /// <param name="pLine">The line of the reference (selects the visible uses section).</param>
    /// <param name="pName">The identifier.</param>
    /// <param name="pOwner">Receives the top-level declaration it binds to.</param>
    /// <param name="pStem">Receives the stem of the declaring unit.</param>
    /// <returns>False when no visible declaration has that name.</returns>
    function BindName(pFid: Int64; pLine: Integer; const pName: string; out pOwner: TSymbol;
      out pStem: string): Boolean;
    /// <summary>Whether a stem is a unit of the circular group being planned.</summary>
    /// <param name="pStem">Lower-case unit stem.</param>
    /// <returns>True for a member of the group.</returns>
    function IsSccStem(const pStem: string): Boolean;
    /// <summary>The member_accesses row of a reference.</summary>
    /// <param name="pRefId">refs.id.</param>
    /// <param name="pAccess">Receives the row (TargetSymbolId = the member, MemberMode).</param>
    /// <returns>False when the ref has no member_accesses row.</returns>
    function MemberAccessOf(pRefId: Int64; out pAccess: TCallEdge): Boolean;
  end;

/// <summary>Tells which kind of type use a refs.kind 'type_use' row is, from its line.</summary>
/// <param name="pLineText">The source line of the reference.</param>
/// <param name="pName">The type name the ref records.</param>
/// <returns>Checked in this order, case-insensitively: `is Name` -&gt; erTypeIs;
/// `as Name` -&gt; erTypeAs; `Name(` -&gt; erTypeCast; `: Name` -&gt; erTypeDecl;
/// else erOther.</returns>
function ClassifyTypeUse(const pLineText, pName: string): TEdgeRefKind;

/// <summary>The types a routine's stored signature names, each resolved to its
/// declaring unit as seen from the routine's own unit.</summary>
/// <param name="pSource">Index access; must not be nil.</param>
/// <param name="pDeclFid">File id of the unit that declares the routine.</param>
/// <param name="pDeclLine">Line of the routine's declaration (selects the visible uses).</param>
/// <param name="pSig">symbols.signature, e.g. `(const pFolderId: Integer): IFoo`.</param>
/// <returns>One entry per distinct type identifier, in signature order.</returns>
/// <remarks>Only the text after a ':' of each `;`/`,`/`(`/`)` group is read (parameter
/// names are not types); `= default` tails and the words const var out array of
/// function procedure reference to packed are dropped. A dotted `Unit.TFoo` keeps its
/// name as written and is declared in the unit its prefix names. An identifier no
/// visible index row declares (e.g. Integer) gets DeclStem ''.</remarks>
function SignatureTypes(const pSource: IEdgeSurfaceSource; pDeclFid: Int64; pDeclLine: Integer;
  const pSig: string): TArray<TSigType>;

/// <summary>Whether every resolved type of a signature lives outside the circular group.</summary>
/// <param name="pTypes">The result of SignatureTypes.</param>
/// <param name="pStems">Receives the distinct declaring stems of the resolved types.</param>
/// <returns>True when at least one type resolved and none is InScc -- a pointer /
/// event type for the routine could then be declared in pStems without touching
/// the cycle.</returns>
function SigTypesOutsideScc(const pTypes: TArray<TSigType>; out pStems: TArray<string>): Boolean;

/// <summary>Collects what unit pFromFid takes from unit pToStem.</summary>
/// <param name="pSource">Index access; must not be nil. Its IsSccStem must answer for
/// the group the edge belongs to (it fills SigTypes[].InScc).</param>
/// <param name="pFromFid">File id of the citing unit A.</param>
/// <param name="pToStem">Lower-case stem of the used unit B.</param>
/// <returns>The surface; only FromStem / ToStem are set when either unit is not indexed.</returns>
/// <remarks>Reads the index only. A ref with a member_accesses row counts as a member
/// access; the companion 'member-access' rows of a call are skipped; a bare name is
/// bound by its symbol_id when it has one, else by name (BindName), and a name that
/// is a local or parameter of its routine is never bound.</remarks>
function BuildEdgeSurface(const pSource: IEdgeSurfaceSource; const pFromFid: Int64;
  const pToStem: string): TEdgeSurface;

/// <summary>The JSON `cycles --causes` prints for one edge.</summary>
/// <param name="pS">The surface.</param>
/// <returns>A new object {from, to, surface:{members, classes, has_write,
/// has_construction, has_class_method, has_class_ref_arg, has_decl, routine,
/// routine_sig, sig_types:[{name, unit, in_scc}], call_count}}; the caller owns it.</returns>
function EdgeSurfaceToJson(const pS: TEdgeSurface): TJSONObject;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.RegularExpressions,
  System.Generics.Collections;

const
  CNotTypeWords = ' const var out array of function procedure reference to packed ';

function StemOfPath(const pPath: string): string;
begin
  Result:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), ''));
end;

function ClassifyTypeUse(const pLineText, pName: string): TEdgeRefKind;
var
  N: string;
begin
  N:= TRegEx.Escape(pName);
  if TRegEx.IsMatch(pLineText, '\bis\s+' + N + '\b', [roIgnoreCase]) then Exit(erTypeIs);
  if TRegEx.IsMatch(pLineText, '\bas\s+' + N + '\b', [roIgnoreCase]) then Exit(erTypeAs);
  if TRegEx.IsMatch(pLineText, '\b' + N + '\s*\(', [roIgnoreCase]) then Exit(erTypeCast);
  if TRegEx.IsMatch(pLineText, ':\s*' + N + '\b', [roIgnoreCase]) then Exit(erTypeDecl);
  Result:= erOther;
end;

function SignatureTypes(const pSource: IEdgeSurfaceSource; pDeclFid: Int64; pDeclLine: Integer;
  const pSig: string): TArray<TSigType>;
var
  L    : TList<TSigType>;
  Seen : TDictionary<string, Boolean>;
  T    : TSigType;
  Owner: TSymbol;
  Stem : string;
begin
  L   := TList<TSigType>.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for var Group in pSig.Split([';', ',', '(', ')']) do
    begin
      var P:= Group.LastIndexOf(':');
      if P < 0 then Continue;
      var TypeText:= Group.Substring(P + 1);
      var Eq:= TypeText.IndexOf('=');
      if Eq >= 0 then TypeText:= TypeText.Substring(0, Eq);
      for var M in TRegEx.Matches(TypeText, '[A-Za-z_][A-Za-z0-9_.]*') do
      begin
        var Dot  := M.Value.LastIndexOf('.');
        var Ident:= M.Value.Substring(Dot + 1);
        if (Ident = '') or ContainsText(CNotTypeWords, ' ' + Ident + ' ') then Continue;
        if Seen.ContainsKey(LowerCase(M.Value)) then Continue;
        Seen.Add(LowerCase(M.Value), True);
        T:= Default(TSigType);
        T.Name:= M.Value;
        if Dot > 0 then T.DeclStem:= LowerCase(M.Value.Substring(0, Dot))
        else if pSource.BindName(pDeclFid, pDeclLine, Ident, Owner, Stem) then T.DeclStem:= Stem;
        T.InScc:= (T.DeclStem <> '') and pSource.IsSccStem(T.DeclStem);
        L.Add(T);
      end;
    end;
    Result:= L.ToArray;
  finally
    Seen.Free;
    L.Free;
  end;
end;

function SigTypesOutsideScc(const pTypes: TArray<TSigType>; out pStems: TArray<string>): Boolean;
var
  Stems: TList<string>;
begin
  pStems:= nil;
  Stems := TList<string>.Create;
  try
    for var T in pTypes do
    begin
      if T.InScc then Exit(False);
      if (T.DeclStem <> '') and not Stems.Contains(T.DeclStem) then Stems.Add(T.DeclStem);
    end;
    pStems:= Stems.ToArray;
    Result:= Stems.Count > 0;
  finally
    Stems.Free;
  end;
end;

type
  { One BuildEdgeSurface run: the edge, its caches, and the record being filled. }
  TSurfaceBuilder = class  // dl:ok high-response@2506 -- implementation-private one-shot builder of one edge; the response set is its small Take/Bind steps plus the store and RTL calls they make, not a design smell
  private
    FSource   : IEdgeSurfaceSource;
    FStore    : ISymbolStore;
    FFromFid  : Int64;
    FToFid    : Int64;
    FLines    : TArray<string>;
    FSyms     : TDictionary<Int64, TSymbol>;
    FRefs     : TList<TEdgeRef>;
    FClasses  : TStringList;
    FMembers  : TStringList;
    FOwners   : TDictionary<Int64, TSymbol>;
    FRcvLines : TDictionary<string, Boolean>;
    FClassUses: TList<TReference>;
    FSurface  : TEdgeSurface;
    function Sym(pId: Int64): TSymbol;
    function TopLevel(const pSym: TSymbol): TSymbol;
    function IsLocal(const pR: TReference): Boolean;
    function LineText(pLine: Integer): string;
    function BindBare(const pR: TReference; const pName: string; out pOwner: TSymbol): Boolean;
    procedure AddRef(const pR: TReference; pKind: TEdgeRefKind; pSymbolId: Int64);
    function TakeMemberAccess(const pR: TReference): Boolean;
    function TakeReceiverRef(const pR: TReference): Boolean;
    procedure TakeBareRef(const pR: TReference);
    procedure Finish;
    procedure Collect;
  public
    constructor Create(const pSource: IEdgeSurfaceSource; pFromFid: Int64; const pToStem: string);
    destructor Destroy; override;
    function Run: TEdgeSurface;
  end;

constructor TSurfaceBuilder.Create(const pSource: IEdgeSurfaceSource; pFromFid: Int64; const pToStem: string);
begin
  inherited Create;
  FSource := pSource;
  FStore  := pSource.Store;
  FFromFid:= pFromFid;
  FToFid  := pSource.FidOfStem(pToStem);
  FSurface := Default(TEdgeSurface);
  FSurface.ToStem:= pToStem;
  if pFromFid > 0 then FSurface.FromStem:= StemOfPath(FStore.GetFilePath(pFromFid));
  FSyms     := TDictionary<Int64, TSymbol>.Create;
  FRefs     := TList<TEdgeRef>.Create;
  FClasses  := TStringList.Create(dupIgnore, True, False);
  FMembers  := TStringList.Create(dupIgnore, True, False);
  FOwners   := TDictionary<Int64, TSymbol>.Create;
  FRcvLines := TDictionary<string, Boolean>.Create;
  FClassUses:= TList<TReference>.Create;
end;

destructor TSurfaceBuilder.Destroy;
begin
  FClassUses.Free;
  FRcvLines.Free;
  FOwners.Free;
  FMembers.Free;
  FClasses.Free;
  FRefs.Free;
  FSyms.Free;
  inherited Destroy;
end;

function TSurfaceBuilder.Sym(pId: Int64): TSymbol;
begin
  if FSyms.TryGetValue(pId, Result) then Exit;
  Result:= FStore.GetSymbolById(pId);
  FSyms.Add(pId, Result);
end;

function TSurfaceBuilder.TopLevel(const pSym: TSymbol): TSymbol;
begin
  Result:= pSym;
  while Result.ParentId > 0 do
  begin
    var Parent:= Sym(Result.ParentId);
    if (Parent.Id <= 0) or (Parent.Kind in [skUnit, skProgram, skPackage]) then Break;
    Result:= Parent;
  end;
end;

function TSurfaceBuilder.IsLocal(const pR: TReference): Boolean;
var
  Local: TSymbol;
begin
  if pR.EnclosingSymbolId <= 0 then Exit(False);
  Local:= FStore.FindChildSymbolByName(pR.EnclosingSymbolId, pR.NameText);
  Result:= (Local.Id > 0) and (Local.Kind in [skLocalVar, skParam]);
end;

function TSurfaceBuilder.LineText(pLine: Integer): string;
begin
  if (pLine >= 1) and (pLine <= Length(FLines)) then Result:= Trim(FLines[pLine - 1])
  else Result:= '';
end;

function TSurfaceBuilder.BindBare(const pR: TReference; const pName: string; out pOwner: TSymbol): Boolean;
var
  Stem: string;
begin
  if pR.SymbolId > 0 then
  begin
    pOwner:= TopLevel(Sym(pR.SymbolId));
    Exit(pOwner.FileId = FToFid);
  end;
  Result:= FSource.BindName(FFromFid, pR.StartLine, pName, pOwner, Stem) and (Stem = FSurface.ToStem);
end;

procedure TSurfaceBuilder.AddRef(const pR: TReference; pKind: TEdgeRefKind; pSymbolId: Int64);
var
  E: TEdgeRef;
begin
  E:= Default(TEdgeRef);
  E.Line    := pR.StartLine;
  E.Kind    := pKind;
  E.Name    := pR.NameText;
  E.LineText:= LineText(pR.StartLine);
  E.SymbolId:= pSymbolId;
  if pR.EnclosingSymbolId > 0 then E.Enclosing:= Sym(pR.EnclosingSymbolId).Name;
  FRefs.Add(E);
end;

{ A ref with a member_accesses row: a member (or unit-level var) access, never bound by name. }
function TSurfaceBuilder.TakeMemberAccess(const pR: TReference): Boolean;
var
  MA: TCallEdge;
begin
  if not FSource.MemberAccessOf(pR.Id, MA) then Exit(False);
  Result:= True;
  if MA.TargetSymbolId <= 0 then Exit;
  var M:= Sym(MA.TargetSymbolId);
  if M.FileId <> FToFid then Exit;
  FOwners.AddOrSetValue(TopLevel(M).Id, TopLevel(M));
  if SameText(MA.MemberMode, 'write') then
  begin
    FSurface.HasWrite:= True;
    AddRef(pR, erMemberWrite, M.Id);
  end
  else if (M.ParentId > 0) and (Sym(M.ParentId).Kind in [skClass, skRecord, skInterface]) then
  begin
    FMembers.Add(M.Name);
    AddRef(pR, erMemberRead, M.Id);
  end
  else AddRef(pR, erOther, M.Id);
end;

{ A ref with a receiver: a call through a class of B, or a call bound to a routine of B. }
function TSurfaceBuilder.TakeReceiverRef(const pR: TReference): Boolean;
var
  Cls : TSymbol;
  Stem: string;
begin
  if pR.ReceiverText = '' then Exit(False);
  Result:= True;
  if not SameText(pR.Kind, 'call') then Exit;
  var Rcv:= pR.ReceiverText.Substring(pR.ReceiverText.LastIndexOf('.') + 1);
  if FSource.BindName(FFromFid, pR.StartLine, Rcv, Cls, Stem) and (Stem = FSurface.ToStem) and
    (Cls.Kind = skClass) then
  begin
    var Ctor:= if pR.SymbolId > 0 then Sym(pR.SymbolId).Kind = skConstructor
      else SameText(pR.NameText, 'Create') or (FStore.FindChildSymbolByName(Cls.Id, pR.NameText).Kind = skConstructor);
    if Ctor then FSurface.HasConstruction:= True
    else FSurface.HasClassMethod:= True;
    Inc(FSurface.CallCount);
    FClasses.Add(Cls.Name);
    FOwners.AddOrSetValue(Cls.Id, Cls);
    FRcvLines.AddOrSetValue(Format('%d:%s', [pR.StartLine, LowerCase(Cls.Name)]), True);
    AddRef(pR, erClassReceiver, Cls.Id);
    Exit;
  end;
  if (pR.SymbolId <= 0) or (Sym(pR.SymbolId).FileId <> FToFid) then Exit;
  Inc(FSurface.CallCount);
  FOwners.AddOrSetValue(TopLevel(Sym(pR.SymbolId)).Id, TopLevel(Sym(pR.SymbolId)));
  AddRef(pR, erCall, pR.SymbolId);
end;

procedure TSurfaceBuilder.TakeBareRef(const pR: TReference);
var
  Owner: TSymbol;
  Kind : TEdgeRefKind;
begin
  if IsLocal(pR) or not BindBare(pR, pR.NameText, Owner) then Exit;
  FOwners.AddOrSetValue(Owner.Id, Owner);
  if Owner.Kind = skClass then FClasses.Add(Owner.Name);
  Kind:= erOther;
  if SameText(pR.Kind, 'call') then
  begin
    Kind:= erCall;
    Inc(FSurface.CallCount);
  end
  else if SameText(pR.Kind, 'type_use') then
  begin
    Kind:= ClassifyTypeUse(LineText(pR.StartLine), pR.NameText);
    if Kind = erTypeDecl then FSurface.HasDecl:= True;
  end
  else if SameText(pR.Kind, 'write') then
  begin
    Kind:= erMemberWrite;
    FSurface.HasWrite:= True;
  end
  else if SameText(pR.Kind, 'read') and (Owner.Kind = skClass) then FClassUses.Add(pR);
  AddRef(pR, Kind, Owner.Id);
end;

procedure TSurfaceBuilder.Finish;
var
  Owner: TSymbol;
begin
  Owner:= Default(TSymbol);
  for var R in FClassUses do
    if not FRcvLines.ContainsKey(Format('%d:%s', [R.StartLine, LowerCase(R.NameText)])) then
      FSurface.HasClassRefArg:= True;
  FSurface.Refs      := FRefs.ToArray;
  FSurface.ClassNames:= FClasses.ToStringArray;
  FSurface.Members   := FMembers.ToStringArray;
  if FOwners.Count <> 1 then Exit;
  for var O in FOwners.Values do Owner:= O;
  if not (Owner.Kind in [skProcedure, skFunction]) then Exit;
  FSurface.RoutineName:= Owner.Name;
  FSurface.RoutineSig := Owner.Signature;
  FSurface.SigTypes   := SignatureTypes(FSource, FToFid, Owner.StartLine, Owner.Signature);
end;

function TSurfaceBuilder.Run: TEdgeSurface;
begin
  if (FFromFid > 0) and (FToFid > 0) then Collect;
  Result:= FSurface;
end;

procedure TSurfaceBuilder.Collect;
begin
  FLines:= FSource.FileLines(FFromFid);
  for var R in FStore.GetReferencesFromFile(FFromFid) do
  begin
    if TakeMemberAccess(R) then Continue;
    if SameText(R.Kind, 'member-access') then Continue;  { the companion row of a call }
    if TakeReceiverRef(R) then Continue;
    TakeBareRef(R);
  end;
  Finish;
end;

function BuildEdgeSurface(const pSource: IEdgeSurfaceSource; const pFromFid: Int64;
  const pToStem: string): TEdgeSurface;
var
  B: TSurfaceBuilder;
begin
  B:= TSurfaceBuilder.Create(pSource, pFromFid, pToStem);
  try
    Result:= B.Run;
  finally
    B.Free;
  end;
end;

function StringsToJson(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pItems do Result.Add(S);
end;

function EdgeSurfaceToJson(const pS: TEdgeSurface): TJSONObject;
var
  Surf : TJSONObject;
  Types: TJSONArray;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('from', pS.FromStem);
  Result.AddPair('to', pS.ToStem);
  Surf:= TJSONObject.Create;
  Result.AddPair('surface', Surf);
  Surf.AddPair('members', StringsToJson(pS.Members));
  Surf.AddPair('classes', StringsToJson(pS.ClassNames));
  Surf.AddPair('has_write', TJSONBool.Create(pS.HasWrite));
  Surf.AddPair('has_construction', TJSONBool.Create(pS.HasConstruction));
  Surf.AddPair('has_class_method', TJSONBool.Create(pS.HasClassMethod));
  Surf.AddPair('has_class_ref_arg', TJSONBool.Create(pS.HasClassRefArg));
  Surf.AddPair('has_decl', TJSONBool.Create(pS.HasDecl));
  Surf.AddPair('routine', pS.RoutineName);
  Surf.AddPair('routine_sig', pS.RoutineSig);
  Types:= TJSONArray.Create;
  Surf.AddPair('sig_types', Types);
  for var T in pS.SigTypes do
  begin
    var JT:= TJSONObject.Create;
    Types.AddElement(JT);
    JT.AddPair('name', T.Name);
    JT.AddPair('unit', T.DeclStem);
    JT.AddPair('in_scc', TJSONBool.Create(T.InScc));
  end;
  Surf.AddPair('call_count', TJSONNumber.Create(pS.CallCount));
end;

end.
