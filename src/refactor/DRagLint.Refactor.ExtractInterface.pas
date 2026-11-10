unit DRagLint.Refactor.ExtractInterface;

// ---------------------------------------------------------------------------
// `extract-interface` (E-REFACTOR-5): declares an interface holding the members of a class that the rest of the project
// uses, and adds it to the class's heritage. Purely additive: no consumer is retyped, so no lifetime changes.
// Spec: docs\superpowers\specs\2026-11-06-extract-interface-lazy-init.md
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, DRagLint.Core.Interfaces;

type
  /// <summary>The flags of one `extract-interface` run.</summary>
  TExtractInterfaceOptions = record
    /// <summary>--class: the class's name or qualified name.</summary>
    ClassRef: string;
    /// <summary>--members: comma list that replaces the computed set; '' = the members used from outside the class.</summary>
    Members: string;
    /// <summary>--name: the interface's name; '' = I + the class's name without its T.</summary>
    IfaceName: string;
    /// <summary>--reparent-interfaced: a class whose direct parent is TObject becomes a TInterfacedObject.</summary>
    Reparent: Boolean;
    /// <summary>--reparent-interfaced=norefcount: with Reparent, the new parent is TSingletonImplementation (System.Generics.Defaults), an IInterface base that never counts references, so Free stays the owner's call. The unit must already use System.Generics.Defaults.</summary>
    NoRefCount: Boolean;
    /// <summary>--project: required with --apply; bounds the edit to the project's own roots.</summary>
    Project: string;
    /// <summary>--platform, '' = win64.</summary>
    Platform: string;
    /// <summary>--rsvars, '' = the Studio the registry / BDS names.</summary>
    RsVars: string;
    /// <summary>--build-timeout in whole seconds, as typed; '' or '0' = no limit.</summary>
    BuildTimeout: string;
    /// <summary>--apply: write through the scratch build and the compile gate; otherwise the plan is printed.</summary>
    Apply: Boolean;
    /// <summary>--no-backup (apply only).</summary>
    NoBackup: Boolean;
    /// <summary>--no-compile: legal on the plan only; refused with --apply.</summary>
    NoCompile: Boolean;
    /// <summary>--format json.</summary>
    Json: Boolean;
  end;

/// <summary>Runs the verb: prints the plan and, with --apply, writes through ApplyThroughScratch.</summary>
/// <param name="pStore">The project's index; must be a SQLite store.</param>
/// <param name="pLibraries">The platform library indexes, or none; without them an ancestor the project does not declare is
/// unresolved-ancestor unless it is TInterfacedObject or another class known to implement IInterface.</param>
/// <param name="pOpts">The flags.</param>
/// <returns>0: plan (a refusal included, named in it), or applied and built. 1: --apply refused or a gate refused, the project is
/// unchanged. 2: bad flags, no such class, an ambiguous class, or a rollback that failed.</returns>
/// <remarks>A member counts as used when a reference from outside the class resolves to it, or names it through a receiver
/// typed as the class or a descendant; a reference in the class or an implicit-Self one in a descendant does not. Left out, the
/// run carrying on: field, not-public, class-member, generic-method, class-scope-name, field-backed-property,
/// property-specifier, no-such-member. Refused whole, in this order: include-file, stale-file, outside-roots, class-helper,
/// generic-class, nested-class, ifdef-in-class, type-on-same-line, name-taken, unresolved-ancestor, no-iinterface,
/// no-used-members. The GUID is a hash of the unit, the interface and its members, so the plan shows the bytes --apply
/// writes.</remarks>
function RunExtractInterface(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TExtractInterfaceOptions): Integer;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.StrUtils, System.RegularExpressions, System.Hash,
  System.Generics.Collections, Winapi.Windows,
  FireDAC.Comp.Client,
  DRagLint.Project.OwnRoots, DRagLint.Report.CyclePlan, DRagLint.Refactor.CompileGate, DRagLint.Refactor.VerbShape,
  DRagLint.Refactor.RedundantCast, DRagLint.Storage.SQLite;

const
  CExitOk      = 0;
  CExitRefused = 1;
  CExitError   = 2;
  CMaxChain    = 64;
  CVerb        = 'extract-interface';
  CSchema      = 'extract-interface/1';
  CKeptDirectives: array[0..10] of string = ('overload', 'stdcall', 'cdecl', 'pascal', 'safecall', 'register', 'winapi',
    'deprecated', 'platform', 'experimental', 'library');
  CKnownInterfaced: array[0..4] of string = ('TInterfacedObject', 'TComponent', 'TAggregatedObject', 'TContainedObject',
    'TInterfacedPersistent');
  CIUnknownMembers: array[0..2] of string = ('QueryInterface', '_AddRef', '_Release');

type
  TClassRow = record
    Id, FileId, ParentId: Int64;
    Name, QName, Heritage, GenericParams, Path, ParentKind: string;
    IsHelper: Boolean;
    StartLine, StartCol, EndLine, EndCol: Integer;
  end;

  TMemberRow = record
    Id: Int64;
    Kind, Name, Modifiers, GenericParams: string;
    VisExplicit, IsClassMethod: Boolean;
    StartLine, StartCol, EndLine, EndCol: Integer;
  end;

  TUseCount = record
    Count: Integer;
    First: string;
  end;

  TUseRow = record
    Enclosing, Target, Symbol: Int64;
    Receiver, ReceiverType, Place: string;
  end;

  TPlannedMember = record
    Name, Kind: string;
    Uses_: Integer;
    FirstUse: string;
    Reason: string; // the left-out reason's words; '' for a member that went in
    LeftKind: string;
  end;

  TIfacePlan = record
    ClassQName, FilePath, IfaceName, Guid, RefusalKind, RefusalReason: string;
    Line: Integer;
    Text: string;            // the interface's declaration, as inserted
    HeritageBefore, HeritageAfter: string;
    NeedsForward: Boolean;
    Members, LeftOut: TArray<TPlannedMember>;
    NewText: string;         // the whole file after the edit; '' on a refusal
    Enc: TEncoding;
  end;

  TIfacePlanner = class  // dl:ok high-response@e0ef -- one planner class holds one proof and its connections; the split would hide the order of the refusals
  strict private
    FConn    : TFDConnection;
    FLibs    : TArray<TFDConnection>;
    FOpts    : TExtractInterfaceOptions;
    FStore   : ISymbolStore;
    FOwn     : TOwnRoots;
    FSource  : TMaskedSource;
    FClass   : TClassRow;
    FMembers : TArray<TMemberRow>;
    FPlan    : TIfacePlan;
    procedure Refuse(const pKind, pReason: string);
    procedure LeaveOut(const pName, pKind, pReason: string; const pUse: TUseCount);
    function Rows(pConn: TFDConnection; const pSql: string; const pName: string): TArray<TClassRow>;
    function ReadMembers: TArray<TMemberRow>;
    function ComputeUses: TDictionary<string, TUseCount>;
    function Descendants: TDictionary<Int64, Boolean>;
    function ChainVerdict(out pReparentable: Boolean): string;
    function Slice(const pM: TMemberRow): string;
    function HeaderEnd(pFrom, pTo: Integer): Integer;
    function MethodText(const pM: TMemberRow): string;
    function NamesClassScope(const pM: TMemberRow): Boolean;
    function RefuseClass: Boolean;
    function ReparentBase: string;
    function HeritageEdit(out pOffset, pRemove: Integer; out pInsert: string): Boolean;
    function PropertyFits(const pM: TMemberRow; const pUse: TUseCount; out pAccessors: TArray<TMemberRow>; out pDecl: string): Boolean;
    procedure Build(const pInGoes: TArray<TMemberRow>; const pProps: TArray<string>);
    procedure Choose(const pUsed: TDictionary<string, TUseCount>);
  public
    constructor Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pOpts: TExtractInterfaceOptions);
    destructor Destroy; override;
    /// <summary>Plans the run.</summary>
    /// <param name="pError">Receives the message of an exit-2 failure.</param>
    /// <returns>The plan.</returns>
    function Run(out pError: string): TIfacePlan;
  end;

function Leaf(const pName: string): string;
begin
  Result:= Trim(TRegEx.Replace(pName, '<.*$', ''));
  while Result.Contains('.') do Result:= Copy(Result, Pos('.', Result) + 1, MaxInt);
end;

function HeritageList(const pHeritage: string): TArray<string>;
begin
  Result:= nil;
  for var P in pHeritage.Split([',']) do
    if Trim(P) <> '' then Result:= Result + [Leaf(P)];
end;

function NameBasedGuid(const pSeed: string): string;
begin
  Result:= GUIDToString(TGUID.Create(THashMD5.GetHashBytes(LowerCase(pSeed))));
end;

// One row of the class query.
function ClassRowOf(pQ: TFDQuery): TClassRow;
begin
  Result:= Default(TClassRow);
  Result.Id:= pQ.FieldByName('id').AsLargeInt;
  Result.FileId:= pQ.FieldByName('file_id').AsLargeInt;
  Result.ParentId:= pQ.FieldByName('pid').AsLargeInt;
  Result.Name:= pQ.FieldByName('name').AsString;
  Result.QName:= pQ.FieldByName('qualified_name').AsString;
  Result.Heritage:= pQ.FieldByName('h').AsString;
  Result.GenericParams:= pQ.FieldByName('g').AsString;
  Result.Path:= pQ.FieldByName('path').AsString;
  Result.ParentKind:= pQ.FieldByName('pk').AsString;
  Result.IsHelper:= pQ.FieldByName('hp').AsInteger <> 0;
  Result.StartLine:= pQ.FieldByName('start_line').AsInteger;
  Result.StartCol:= pQ.FieldByName('start_col').AsInteger;
  Result.EndLine:= pQ.FieldByName('end_line').AsInteger;
  Result.EndCol:= pQ.FieldByName('end_col').AsInteger;
end;

// One row of the member query.
function MemberRowOf(pQ: TFDQuery): TMemberRow;
begin
  Result:= Default(TMemberRow);
  Result.Id:= pQ.FieldByName('id').AsLargeInt;
  Result.Kind:= pQ.FieldByName('kind').AsString;
  Result.Name:= pQ.FieldByName('name').AsString;
  Result.Modifiers:= pQ.FieldByName('m').AsString;
  Result.GenericParams:= pQ.FieldByName('g').AsString;
  Result.VisExplicit:= pQ.FieldByName('ve').AsInteger <> 0;
  Result.IsClassMethod:= pQ.FieldByName('cm').AsInteger <> 0;
  Result.StartLine:= pQ.FieldByName('start_line').AsInteger;
  Result.StartCol:= pQ.FieldByName('start_col').AsInteger;
  Result.EndLine:= pQ.FieldByName('end_line').AsInteger;
  Result.EndCol:= pQ.FieldByName('end_col').AsInteger;
end;

// One row of the reference query.
function UseRowOf(pQ: TFDQuery): TUseRow;
begin
  Result.Enclosing:= pQ.FieldByName('enc').AsLargeInt;
  Result.Target:= pQ.FieldByName('tgt').AsLargeInt;
  Result.Symbol:= pQ.FieldByName('sym').AsLargeInt;
  Result.Receiver:= pQ.FieldByName('rcv').AsString;
  Result.ReceiverType:= pQ.FieldByName('rty').AsString;
  Result.Place:= pQ.FieldByName('path').AsString + ':' + pQ.FieldByName('start_line').AsString;
end;

constructor TIfacePlanner.Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pOpts: TExtractInterfaceOptions);
begin
  inherited Create;
  FStore:= pStore;
  FOpts := pOpts;
  FConn := (pStore as TSQLiteSymbolStore).GetConnection;
  for var L in pLibraries do
    if L is TSQLiteSymbolStore then FLibs:= FLibs + [(L as TSQLiteSymbolStore).GetConnection];
  if pOpts.Project <> '' then FOwn:= TOwnRoots.Load(ExtractFilePath(ExpandFileName(pOpts.Project)));
end;

destructor TIfacePlanner.Destroy;
begin
  FSource.Free;
  inherited Destroy;
end;

procedure TIfacePlanner.Refuse(const pKind, pReason: string);
begin
  FPlan.RefusalKind  := pKind;
  FPlan.RefusalReason:= pReason;
end;

procedure TIfacePlanner.LeaveOut(const pName, pKind, pReason: string; const pUse: TUseCount);
begin
  var M:= Default(TPlannedMember);
  M.Name    := pName;
  M.LeftKind:= pKind;
  M.Reason  := pReason;
  M.Uses_   := pUse.Count;
  M.FirstUse:= pUse.First;
  FPlan.LeftOut:= FPlan.LeftOut + [M];
end;

function TIfacePlanner.Rows(pConn: TFDConnection; const pSql: string; const pName: string): TArray<TClassRow>;
begin
  Result:= nil;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pConn;
    Q.SQL.Text:= 'SELECT s.id, s.file_id, COALESCE(s.parent_id, 0) AS pid, s.name, s.qualified_name, COALESCE(s.heritage, '''') AS h, ' +
      'COALESCE(s.generic_params, '''') AS g, f.path, COALESCE(p.kind, '''') AS pk, COALESCE(s.is_helper, 0) AS hp, ' +
      's.start_line, s.start_col, s.end_line, s.end_col, ' +
      '(SELECT COUNT(*) FROM symbols c WHERE c.parent_id = s.id) AS kids ' +
      'FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbols p ON p.id = s.parent_id ' +
      'WHERE s.kind = ''class'' AND ' + pSql;
    Q.ParamByName('n').AsWideString:= pName;
    Q.Open;
    var KidsField:= Q.FieldByName('kids');
    while not Q.Eof do
    begin
      var R:= ClassRowOf(Q);
      { a forward `TFoo = class;` is one line, no heritage, no members }
      var Forward_:= (R.StartLine = R.EndLine) and (R.Heritage = '') and (KidsField.AsInteger = 0);
      if not Forward_ then Result:= Result + [R];
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TIfacePlanner.ReadMembers: TArray<TMemberRow>;
begin
  Result:= nil;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT id, kind, name, COALESCE(modifiers, '''') AS m, COALESCE(generic_params, '''') AS g, COALESCE(vis_explicit, 0) AS ve, ' +
      'COALESCE(is_class_method, 0) AS cm, start_line, start_col, end_line, end_col FROM symbols WHERE parent_id = :c ORDER BY start_line, start_col';
    Q.ParamByName('c').AsLargeInt:= FClass.Id;
    Q.Open;
    while not Q.Eof do
    begin
      Result:= Result + [MemberRowOf(Q)];

      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TIfacePlanner.Descendants: TDictionary<Int64, Boolean>;
begin
  Result:= TDictionary<Int64, Boolean>.Create;
  var Names:= TDictionary<string, Boolean>.Create;
  var Q:= TFDQuery.Create(nil);
  try
    Names.Add(LowerCase(FClass.Name), True);
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT id, name, heritage FROM symbols WHERE kind = ''class'' AND heritage IS NOT NULL AND heritage <> ''''';
    Q.Open;
    var IdField:= Q.FieldByName('id');
    var NameField:= Q.FieldByName('name');
    var HeritageField:= Q.FieldByName('heritage');
    var Grew:= True;
    while Grew do
    begin
      Grew:= False;
      Q.First;
      while not Q.Eof do
      begin
        var Parents:= HeritageList(HeritageField.AsString);
        var Id:= IdField.AsLargeInt;
        if (Length(Parents) > 0) and Names.ContainsKey(LowerCase(Parents[0])) and not Result.ContainsKey(Id) then
        begin
          Result.Add(Id, True);
          Names.AddOrSetValue(LowerCase(NameField.AsString), True);
          Grew:= True;
        end;
        Q.Next;
      end;
    end;
  finally
    Q.Free;
    Names.Free;
  end;
end;

function TIfacePlanner.ComputeUses: TDictionary<string, TUseCount>;
var
  Parent: TDictionary<Int64, Int64>;
  Family: TDictionary<Int64, Boolean>;
  Ids: TDictionary<Int64, Boolean>;
  FamilyNames: TDictionary<string, Boolean>;
  Counts: TDictionary<string, TUseCount>;

  function ReachesOwner(pFrom: Int64; out pInDescendant: Boolean): Boolean;
  begin
    Result:= False;
    pInDescendant:= False;
    var Cur:= pFrom;
    var Guard:= 0;
    while (Cur > 0) and (Guard < CMaxChain) do
    begin
      if Cur = FClass.Id then Exit(True);
      if Family.ContainsKey(Cur) then pInDescendant:= True;
      var Up: Int64;
      if not Parent.TryGetValue(Cur, Up) then
      begin
        var Q:= TFDQuery.Create(nil);
        try
          Q.Connection:= FConn;
          Q.SQL.Text:= 'SELECT COALESCE(parent_id, 0) FROM symbols WHERE id = :i';
          Q.ParamByName('i').AsLargeInt:= Cur;
          Q.Open;
          Up:= if Q.Eof then 0 else Q.Fields[0].AsLargeInt;
        finally
          Q.Free;
        end;
        Parent.Add(Cur, Up);
      end;
      Cur:= Up;
      Inc(Guard);
    end;
  end;

  function IsOutsideUse(const pRow: TUseRow): Boolean;
  begin
    Result:= Ids.ContainsKey(pRow.Target) or Ids.ContainsKey(pRow.Symbol) or
      ((pRow.ReceiverType <> '') and FamilyNames.ContainsKey(LowerCase(Leaf(pRow.ReceiverType))));
    if not Result then Exit;
    var InDescendant: Boolean;
    var Owned:= ReachesOwner(pRow.Enclosing, InDescendant);
    var ImplicitSelf:= InDescendant and ((pRow.Receiver = '') or SameText(pRow.Receiver, 'Self') or SameText(pRow.Receiver, 'inherited'));
    Result:= not Owned and not ImplicitSelf;
  end;

  procedure Tally(const pName, pPlace: string);
  begin
    var U: TUseCount;
    if not Counts.TryGetValue(LowerCase(pName), U) then
    begin
      U:= Default(TUseCount);
      U.First:= pPlace;
    end;
    Inc(U.Count);
    Counts.AddOrSetValue(LowerCase(pName), U);
  end;

begin
  Counts:= TDictionary<string, TUseCount>.Create;
  Result:= Counts;
  Parent:= TDictionary<Int64, Int64>.Create;
  Family:= Descendants;
  Ids:= TDictionary<Int64, Boolean>.Create;
  FamilyNames:= TDictionary<string, Boolean>.Create;
  var Q:= TFDQuery.Create(nil);
  try
    FamilyNames.AddOrSetValue(LowerCase(FClass.Name), True);
    for var M in FMembers do Ids.AddOrSetValue(M.Id, True);
    Q.Connection:= FConn;
    { the descendants' names: a receiver typed as one of them still reaches the class's members }
    Q.SQL.Text:= 'SELECT name FROM symbols WHERE id = :i';
    for var D in Family.Keys do
    begin
      Q.Close;
      Q.ParamByName('i').AsLargeInt:= D;
      Q.Open;
      if not Q.Eof then FamilyNames.AddOrSetValue(LowerCase(Q.Fields[0].AsString), True);
    end;
    Q.Close;
    Q.SQL.Text:= 'SELECT COALESCE(r.enclosing_symbol_id, 0) AS enc, COALESCE(r.receiver_text, '''') AS rcv, COALESCE(r.receiver_type_text, '''') AS rty, ' +
      'COALESCE(c.target_symbol_id, 0) AS tgt, COALESCE(r.symbol_id, 0) AS sym, f.path, r.start_line ' +
      'FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN call_edges c ON c.ref_id = r.id WHERE r.name_text = :n COLLATE NOCASE ORDER BY f.path, r.start_line';
    var Asked:= TDictionary<string, Boolean>.Create;
    try
      for var M in FMembers do
      begin
        if Asked.ContainsKey(LowerCase(M.Name)) then Continue;
        Asked.Add(LowerCase(M.Name), True);
        Q.Close;
        Q.ParamByName('n').AsWideString:= M.Name;
        Q.Open;
        var Seen:= TDictionary<string, Boolean>.Create;  { a call has a call row and a member-access row at one place }
        try
          while not Q.Eof do
          begin
            var Row:= UseRowOf(Q);
            if IsOutsideUse(Row) and not Seen.ContainsKey(LowerCase(Row.Place)) then
            begin
              Seen.Add(LowerCase(Row.Place), True);
              Tally(M.Name, Row.Place);
            end;
            Q.Next;
          end;
        finally
          Seen.Free;
        end;
      end;
    finally
      Asked.Free;
    end;
  finally
    Q.Free;
    FamilyNames.Free;
    Ids.Free;
    Family.Free;
    Parent.Free;
  end;
end;

// '' when the chain implements IInterface; else the refusal's kind.
function TIfacePlanner.ChainVerdict(out pReparentable: Boolean): string;  // dl:ok too-many-exit-points@48b8 -- one guard per named refusal, in the documented order: the exits are the contract
begin
  Result:= '';
  pReparentable:= False;
  var Cur:= FClass.Heritage;
  var Depth:= 0;
  var All:= [FConn] + FLibs;
  while Depth < CMaxChain do
  begin
    var Entries:= HeritageList(Cur);
    if Length(Entries) >= 2 then Exit; { it already takes an interface and compiles }
    if (Length(Entries) = 0) or SameText(Entries[0], 'TObject') then
    begin
      pReparentable:= Depth = 0;
      Exit('no-iinterface');
    end;
    if MatchText(Entries[0], CKnownInterfaced) then Exit;
    var Found: TArray<TClassRow>:= nil;
    var FromConn: TFDConnection:= nil;
    for var C in All do
    begin
      Found:= Rows(C, 's.name = :n COLLATE NOCASE', Entries[0]);
      if Length(Found) > 0 then
      begin
        FromConn:= C;
        Break;
      end;
    end;
    if Length(Found) = 0 then
    begin
      { an interface as the first entry: `TFoo = class(IBar)` }
      var Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= FConn;
        Q.SQL.Text:= 'SELECT 1 FROM symbols WHERE kind = ''interface'' AND name = :n COLLATE NOCASE';
        Q.ParamByName('n').AsWideString:= Entries[0];
        Q.Open;
        if not Q.Eof then Exit;
      finally
        Q.Free;
      end;
      Exit('unresolved-ancestor');
    end;
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= FromConn;
      Q.SQL.Text:= 'SELECT COUNT(DISTINCT name) FROM symbols WHERE parent_id = :p AND name IN (''' + String.Join(''',''', CIUnknownMembers) + ''')';
      Q.ParamByName('p').AsLargeInt:= Found[0].Id;
      Q.Open;
      if Q.Fields[0].AsInteger = Length(CIUnknownMembers) then Exit;
    finally
      Q.Free;
    end;
    Cur:= Found[0].Heritage;
    Inc(Depth);
  end;
  Result:= 'unresolved-ancestor';
end;

function TIfacePlanner.Slice(const pM: TMemberRow): string;
begin
  var A:= FSource.OffsetOf(pM.StartLine, pM.StartCol);
  var B:= FSource.OffsetOf(pM.EndLine, pM.EndCol);
  Result:= Copy(FSource.Text, A, B - A);
end;

// The offset of the first `;` outside parentheses and brackets in [pFrom, pTo); 0 when there is none.
function TIfacePlanner.HeaderEnd(pFrom, pTo: Integer): Integer;
begin
  Result:= 0;
  var Depth:= 0;
  for var I:= pFrom to pTo - 1 do
    case FSource.Masked[I] of
      '(', '[': Inc(Depth);
      ')', ']': Dec(Depth);
      ';': if Depth = 0 then Exit(I);
    end;
end;

function TIfacePlanner.MethodText(const pM: TMemberRow): string;
begin
  var A:= FSource.OffsetOf(pM.StartLine, pM.StartCol);
  var B:= FSource.OffsetOf(pM.EndLine, pM.EndCol);
  var H:= HeaderEnd(A, B);
  if H = 0 then Exit(Trim(Copy(FSource.Text, A, B - A)));
  Result:= Copy(FSource.Text, A, H - A + 1);
  { the directives after the header: each kept one in its source form }
  var P:= H + 1;
  while P < B do
  begin
    var Q:= HeaderEnd(P, B);
    if Q = 0 then Q:= B;
    var Word_:= LowerCase(Trim(Copy(FSource.Masked, P, Q - P)));
    if Word_.Contains(' ') then Word_:= Copy(Word_, 1, Pos(' ', Word_) - 1);
    if MatchText(Word_, CKeptDirectives) then Result:= Result + ' ' + Trim(Copy(FSource.Text, P, Q - P)) + ';';
    P:= Q + 1;
  end;
end;

// True when the member's declaration names a type or constant declared inside the class: not in scope in front of it.
function TIfacePlanner.NamesClassScope(const pM: TMemberRow): Boolean;
begin
  Result:= False;
  var A:= FSource.OffsetOf(pM.StartLine, pM.StartCol);
  var B:= FSource.OffsetOf(pM.EndLine, pM.EndCol);
  var Masked:= Copy(FSource.Masked, A, B - A);
  for var Other in FMembers do
    if not MatchText(Other.Kind, ['method', 'property', 'field', 'function', 'procedure', 'constructor', 'destructor']) and
       TRegEx.IsMatch(Masked, '\b' + TRegEx.Escape(Other.Name) + '\b', [roIgnoreCase]) then Exit(True);
end;

function TIfacePlanner.RefuseClass: Boolean;  // dl:ok too-many-exit-points@dda4 -- one guard per named refusal, in the documented order: the exits are the contract
begin
  Result:= True;
  if not MatchText(ExtractFileExt(FClass.Path), ['.pas', '.dpr', '.dpk']) then
  begin
    Refuse('include-file', 'an include file compiles in every unit that includes it');
    Exit;
  end;
  if not TFile.Exists(FClass.Path) or not IsFileCurrent(FStore, FClass.Path) then
  begin
    Refuse('stale-file', 'the file changed since it was indexed; re-index');
    Exit;
  end;
  if (FOpts.Project <> '') and not FOwn.IsOurs(FClass.Path) then
  begin
    Refuse('outside-roots', 'the file lies outside the project''s own roots');
    Exit;
  end;
  if FClass.IsHelper then
  begin
    Refuse('class-helper', 'a class helper cannot implement an interface');
    Exit;
  end;
  if FClass.GenericParams <> '' then
  begin
    Refuse('generic-class', 'the interface would have to be generic over the same parameters');
    Exit;
  end;
  if MatchText(FClass.ParentKind, ['class', 'record']) then
  begin
    Refuse('nested-class', 'a nested class has no type block of its own to take the interface');
    Exit;
  end;
  FSource:= TMaskedSource.Create(FClass.Path);
  for var L:= FClass.StartLine to FClass.EndLine do
    if FSource.CondAt[L] or FSource.DirAt[L] then
    begin
      Refuse('ifdef-in-class', Format('line %d holds a directive: the plan would see one branch', [L]));
      Exit;
    end;
  var LineStart:= FSource.OffsetOf(FClass.StartLine, 1);
  if Trim(Copy(FSource.Masked, LineStart, FClass.StartCol - 1)) <> '' then
  begin
    Refuse('type-on-same-line', 'the class does not start its own line; there is no line to insert in front of');
    Exit;
  end;
  FPlan.IfaceName:= if FOpts.IfaceName <> '' then FOpts.IfaceName else 'I' + (if StartsText('T', FClass.Name) then Copy(FClass.Name, 2, MaxInt) else FClass.Name);
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT qualified_name FROM symbols WHERE name = :n COLLATE NOCASE AND kind NOT IN (''param'', ''local_var'')';
    Q.ParamByName('n').AsWideString:= FPlan.IfaceName;
    Q.Open;
    if not Q.Eof then
    begin
      Refuse('name-taken', Format('%s already names %s; pass --name', [FPlan.IfaceName, Q.Fields[0].AsString]));
      Exit;
    end;
  finally
    Q.Free;
  end;
  var Reparentable: Boolean;
  var Chain:= ChainVerdict(Reparentable);
  if Chain = 'unresolved-ancestor' then
  begin
    Refuse(Chain, 'an ancestor is in no index given: --library-db / --platform name the platform library');
    Exit;
  end;
  if Chain = 'no-iinterface' then
  begin
    if not Reparentable then
    begin
      Refuse(Chain, 'no class of the chain implements IInterface, and the direct parent is not TObject: give the base class IInterface first');
      Exit;
    end;
    if not FOpts.Reparent then
    begin
      Refuse(Chain, 'the class does not implement IInterface; --reparent-interfaced makes its parent TInterfacedObject');
      Exit;
    end;
    if FOpts.NoRefCount and not TRegEx.IsMatch(FSource.Masked, '\bSystem\.Generics\.Defaults\b', [roIgnoreCase]) then
    begin
      Refuse('base-unit-missing', 'norefcount makes the parent TSingletonImplementation: add System.Generics.Defaults to the unit''s uses first');
      Exit;
    end;
  end;
  Result:= False;
end;

// The parent --reparent-interfaced writes: TInterfacedObject counts references, norefcount's TSingletonImplementation never does.
function TIfacePlanner.ReparentBase: string;
begin
  Result:= if FOpts.NoRefCount then 'TSingletonImplementation' else 'TInterfacedObject';
end;

// The edit of `TFoo = class(...)`; False when the shape is not understood.
function TIfacePlanner.HeritageEdit(out pOffset, pRemove: Integer; out pInsert: string): Boolean;
begin
  pOffset:= 0;
  pRemove:= 0;
  pInsert:= '';
  var A:= FSource.OffsetOf(FClass.StartLine, FClass.StartCol);
  var B:= FSource.OffsetOf(FClass.EndLine, FClass.EndCol);
  var M:= TRegEx.Match(Copy(FSource.Masked, A, B - A), '^\w+\s*=\s*(packed\s+)?class(\s+(abstract|sealed))?(\s*\()?', [roIgnoreCase]);
  Result:= M.Success;
  if not Result then Exit;
  var After:= A + M.Index - 1 + M.Length;
  var Bare:= not EndsStr('(', M.Value);
  if Bare then
  begin
    pOffset:= After;
    pInsert:= '(' + (if FOpts.Reparent then ReparentBase else 'TObject') + ', ' + FPlan.IfaceName + ')';
    FPlan.HeritageBefore:= Copy(FSource.Text, A, After - A);
    FPlan.HeritageAfter := FPlan.HeritageBefore + pInsert;
    Exit;
  end;
  var Close_:= PosEx(')', FSource.Masked, After);
  Result:= Close_ > 0;
  if not Result then Exit;
  var Inner:= Copy(FSource.Text, After, Close_ - After);
  FPlan.HeritageBefore:= Copy(FSource.Text, A, Close_ - A + 1);
  if FOpts.Reparent and SameText(Trim(Inner), 'TObject') then
  begin
    pOffset:= After;
    pRemove:= Close_ - After;
    pInsert:= ReparentBase + ', ' + FPlan.IfaceName;
  end
  else
  begin
    pOffset:= Close_;
    pInsert:= ', ' + FPlan.IfaceName;
  end;
  FPlan.HeritageAfter:= Copy(FSource.Text, A, pOffset - A) + pInsert + Copy(FSource.Text, pOffset + pRemove, Close_ - pOffset - pRemove + 1);
end;

procedure TIfacePlanner.Build(const pInGoes: TArray<TMemberRow>; const pProps: TArray<string>);
begin
  var Eol:= if FSource.Text.Contains(#13#10) then #13#10 else #10;
  var Pad:= StringOfChar(' ', FClass.StartCol - 1);
  var Inner:= Pad + '  ';
  var Seed: TArray<string>:= [FClass.QName, FPlan.IfaceName];
  var Decls: TArray<string>:= nil;
  for var M in pInGoes do
  begin
    Seed:= Seed + [M.Name];
    Decls:= Decls + [Inner + MethodText(M) + Eol];
  end;
  for var P in pProps do Decls:= Decls + [Inner + P + Eol];
  FPlan.Guid:= NameBasedGuid(String.Join('|', Seed));
  var Body:= String.Join('', Decls);
  { the class's own name in a signature needs a forward declaration, unless the block has one }
  var Forward_:= '';
  if TRegEx.IsMatch(Body, '\b' + TRegEx.Escape(FClass.Name) + '\b', [roIgnoreCase]) then
  begin
    var Before:= Copy(FSource.Masked, 1, FSource.OffsetOf(FClass.StartLine, 1) - 1);
    if not TRegEx.IsMatch(Before, '\b' + TRegEx.Escape(FClass.Name) + '\s*=\s*class\s*;', [roIgnoreCase]) then
    begin
      Forward_:= Pad + FClass.Name + ' = class;' + Eol + Eol;
      FPlan.NeedsForward:= True;
    end;
  end;
  FPlan.Text:= Forward_ +
    Pad + '/// <summary>The members of ' + FClass.Name + ' the project uses (drag-lint extract-interface).</summary>' + Eol +
    Pad + FPlan.IfaceName + ' = interface' + Eol +
    Inner + '[''' + FPlan.Guid + ''']' + Eol +
    Body +
    Pad + 'end;' + Eol + Eol;
  { in front of the class AND its doc comment or attributes }
  var InsertLine:= FClass.StartLine;
  while InsertLine > 1 do
  begin
    var Prev:= Trim(Copy(FSource.Text, FSource.OffsetOf(InsertLine - 1, 1), FSource.LineEnd(InsertLine - 1) - FSource.OffsetOf(InsertLine - 1, 1)));
    if StartsStr('//', Prev) or StartsStr('{', Prev) or StartsStr('(*', Prev) or (StartsStr('[', Prev) and EndsStr(']', Prev)) then Dec(InsertLine)
    else Break;
  end;
  var Offset, Remove: Integer;
  var Ins: string;
  if not HeritageEdit(Offset, Remove, Ins) then
  begin
    Refuse('type-on-same-line', 'the class''s declaration line is not of the form `TFoo = class(...)`');
    Exit;
  end;
  var At:= FSource.OffsetOf(InsertLine, 1);
  FPlan.NewText:= Copy(FSource.Text, 1, At - 1) + FPlan.Text + Copy(FSource.Text, At, Offset - At) + Ins + Copy(FSource.Text, Offset + Remove, MaxInt);
  FPlan.Enc:= FSource.Enc;
end;

// False, with the member left out, when the property cannot join an interface.
function TIfacePlanner.PropertyFits(const pM: TMemberRow; const pUse: TUseCount; out pAccessors: TArray<TMemberRow>; out pDecl: string): Boolean;
begin
  Result:= False;
  pAccessors:= nil;
  pDecl:= '';
  var A:= FSource.OffsetOf(pM.StartLine, pM.StartCol);
  var B:= FSource.OffsetOf(pM.EndLine, pM.EndCol);
  var H:= HeaderEnd(A, B);
  var Masked:= Copy(FSource.Masked, A, B - A);
  if TRegEx.IsMatch(Masked, '\b(index|stored|nodefault|implements|dispid|readonly|writeonly)\b', [roIgnoreCase]) or
     TRegEx.IsMatch(Copy(FSource.Masked, A, H - A), '\bdefault\b', [roIgnoreCase]) then
  begin
    LeaveOut(pM.Name, 'property-specifier', 'an interface property takes only read and write', pUse);
    Exit;
  end;
  var Bad:= not TRegEx.IsMatch(Masked, '\b(read|write)\b', [roIgnoreCase]);
  for var Am in TRegEx.Matches(Masked, '\b(read|write)\s+([\w.]+)', [roIgnoreCase]) do
  begin
    var Found:= False;
    for var Acc in FMembers do
      if SameText(Acc.Name, Am.Groups[2].Value) and (Acc.Kind <> 'field') and (Acc.Kind <> 'property') then
      begin
        Bad:= Bad or NamesClassScope(Acc) or Acc.IsClassMethod;
        pAccessors:= pAccessors + [Acc];
        Found:= True;
      end;
    Bad:= Bad or not Found;
  end;
  if Bad then
  begin
    LeaveOut(pM.Name, 'field-backed-property', 'an interface property needs method accessors declared by this class', pUse);
    Exit;
  end;
  pDecl:= Copy(FSource.Text, A, H - A + 1);
  if TRegEx.IsMatch(Copy(FSource.Masked, H + 1, B - H - 1), '\bdefault\b', [roIgnoreCase]) then pDecl:= pDecl + ' default;';
  Result:= True;
end;

procedure TIfacePlanner.Choose(const pUsed: TDictionary<string, TUseCount>);
begin
  var Asked: TArray<string>:= nil;
  var NoUse:= Default(TUseCount);
  if FOpts.Members <> '' then
  begin
    for var P in FOpts.Members.Split([',']) do
      if Trim(P) <> '' then Asked:= Asked + [Trim(P)];
    for var P in Asked do
    begin
      var Known:= False;
      for var M in FMembers do Known:= Known or SameText(M.Name, P);
      if not Known then LeaveOut(P, 'no-such-member', 'the class declares no member of that name', NoUse);
    end;
  end
  else
    for var M in FMembers do
      if pUsed.ContainsKey(LowerCase(M.Name)) and not MatchText(M.Name, Asked) then Asked:= Asked + [M.Name];
  var InGoes: TArray<TMemberRow>:= nil;
  var Props: TArray<string>:= nil;
  var Added:= TDictionary<Int64, Boolean>.Create;
  try
    var AddMethod:= procedure(const pM: TMemberRow)
      begin
        if Added.ContainsKey(pM.Id) then Exit;
        Added.Add(pM.Id, True);
        InGoes:= InGoes + [pM];
      end;
    var Done:= TDictionary<string, Boolean>.Create;
    try
      for var M in FMembers do
      begin
        if not MatchText(M.Name, Asked) then Continue;
        var Use:= Default(TUseCount);
        pUsed.TryGetValue(LowerCase(M.Name), Use);
        var Public_:= ContainsText(M.Modifiers, 'public') or ContainsText(M.Modifiers, 'published') or not M.VisExplicit;
        var Text:= Slice(M);
        var PM:= Default(TPlannedMember);
        PM.Name:= M.Name;
        PM.Kind:= M.Kind;
        PM.Uses_:= Use.Count;
        PM.FirstUse:= Use.First;
        if M.Kind = 'field' then LeaveOut(M.Name, 'field', 'an interface has no fields', Use)
        else if not MatchText(M.Kind, ['method', 'property', 'function', 'procedure', 'constructor', 'destructor']) then LeaveOut(M.Name, 'class-scope-name', 'a nested type or constant cannot join an interface', Use)
        else if not Public_ then LeaveOut(M.Name, 'not-public', 'it would widen the member''s visibility', Use)
        else if M.IsClassMethod or TRegEx.IsMatch(Text, '^(class|constructor|destructor|operator)\b', [roIgnoreCase]) then LeaveOut(M.Name, 'class-member', 'class methods, constructors and destructors do not go in an interface', Use)
        else if M.GenericParams <> '' then LeaveOut(M.Name, 'generic-method', 'an interface method cannot have type parameters', Use)
        else if NamesClassScope(M) then LeaveOut(M.Name, 'class-scope-name', 'the declaration names something declared inside the class, out of scope in front of it', Use)
        else if M.Kind = 'property' then
        begin
          var Accessors: TArray<TMemberRow>;
          var Decl: string;
          if not PropertyFits(M, Use, Accessors, Decl) then Continue;
          for var Acc in Accessors do AddMethod(Acc);
          Props:= Props + [Decl];
          FPlan.Members:= FPlan.Members + [PM];
        end
        else
        begin
          AddMethod(M);
          if not Done.ContainsKey(LowerCase(M.Name)) then FPlan.Members:= FPlan.Members + [PM];
          Done.AddOrSetValue(LowerCase(M.Name), True);
        end;
      end;
    finally
      Done.Free;
    end;
  finally
    Added.Free;
  end;
  if Length(InGoes) + Length(Props) = 0 then
  begin
    Refuse('no-used-members', if Length(Asked) = 0 then 'no reference from outside the class reaches a member; --members names them' else 'every member asked for was left out');
    Exit;
  end;
  Build(InGoes, Props);
end;

function TIfacePlanner.Run(out pError: string): TIfacePlan;
begin
  pError:= '';
  FPlan:= Default(TIfacePlan);
  var Found:= Rows(FConn, '(s.qualified_name = :n COLLATE NOCASE OR s.name = :n COLLATE NOCASE)', FOpts.ClassRef);
  if Length(Found) = 0 then
  begin
    pError:= Format('%s: the index has no class %s', [CVerb, FOpts.ClassRef]);
    Exit(FPlan);
  end;
  if Length(Found) > 1 then
  begin
    pError:= Format('%s: %s names %d classes, qualify it: %s', [CVerb, FOpts.ClassRef, Length(Found), Found[0].QName]);
    Exit(FPlan);
  end;
  FClass:= Found[0];
  FPlan.ClassQName:= FClass.QName;
  FPlan.FilePath  := FClass.Path;
  FPlan.Line      := FClass.StartLine;
  if RefuseClass then Exit(FPlan);
  FMembers:= ReadMembers;
  var Used:= ComputeUses;
  try
    Choose(Used);
  finally
    Used.Free;
  end;
  Result:= FPlan;
end;

function MemberJson(const pM: TPlannedMember): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name', pM.Name);
  if pM.Kind <> '' then Result.AddPair('kind', pM.Kind);
  Result.AddPair('uses', TJSONNumber.Create(pM.Uses_));
  if pM.FirstUse <> '' then Result.AddPair('first_use', pM.FirstUse);
  if pM.LeftKind <> '' then
  begin
    Result.AddPair('left_kind', pM.LeftKind);
    Result.AddPair('reason', pM.Reason);
  end;
end;

procedure PrintJson(const pPlan: TIfacePlan; pRan: Boolean; const pGate: TGateOutcome);
begin
  var J:= TJSONObject.Create;
  try
    J.AddPair('schema', CSchema);
    J.AddPair('applied', TJSONBool.Create(pRan and pGate.Applied));
    J.AddPair('class', pPlan.ClassQName);
    J.AddPair('file', pPlan.FilePath);
    J.AddPair('line', TJSONNumber.Create(pPlan.Line));
    J.AddPair('interface', pPlan.IfaceName);
    if pPlan.RefusalKind <> '' then
    begin
      var R:= TJSONObject.Create;
      R.AddPair('kind', pPlan.RefusalKind);
      R.AddPair('reason', pPlan.RefusalReason);
      J.AddPair('refusal', R);
    end
    else
    begin
      J.AddPair('guid', pPlan.Guid);
      J.AddPair('text', pPlan.Text);
      J.AddPair('heritage_before', pPlan.HeritageBefore);
      J.AddPair('heritage_after', pPlan.HeritageAfter);
      J.AddPair('adds_forward', TJSONBool.Create(pPlan.NeedsForward));
    end;
    var Ms:= TJSONArray.Create;
    J.AddPair('members', Ms);
    for var M in pPlan.Members do Ms.AddElement(MemberJson(M));
    var Ls:= TJSONArray.Create;
    J.AddPair('left_out', Ls);
    for var M in pPlan.LeftOut do Ls.AddElement(MemberJson(M));
    if pRan then
    begin
      var G:= TJSONObject.Create;
      G.AddPair('refusal', pGate.Refusal);
      G.AddPair('detail', pGate.Detail);
      G.AddPair('rolled_back', TJSONBool.Create(pGate.RolledBack));
      G.AddPair('rollback_failed', TJSONBool.Create(pGate.RollbackFailed));
      J.AddPair('gate', G);
    end;
    Writeln(J.Format(2));
  finally
    J.Free;
  end;
end;

procedure PrintText(const pPlan: TIfacePlan; pApply, pRan: Boolean; const pGate: TGateOutcome);
begin
  if pPlan.RefusalKind <> '' then
    Writeln(Format('extract-interface: %s refused: %s -- %s', [pPlan.ClassQName, pPlan.RefusalKind, pPlan.RefusalReason]))
  else
    Writeln(Format('extract-interface: %s -> %s: %d member(s), %d left out%s', [pPlan.ClassQName, pPlan.IfaceName, Length(pPlan.Members), Length(pPlan.LeftOut),
      if pApply then '' else ' (plan; add --apply --project <X.dproj> to write)']));
  for var M in pPlan.Members do Writeln(Format('member   %-24s %-9s uses=%d %s', [M.Name, M.Kind, M.Uses_, M.FirstUse]));
  for var M in pPlan.LeftOut do Writeln(Format('left out %-24s %s -- %s', [M.Name, M.LeftKind, M.Reason]));
  if pPlan.RefusalKind = '' then
  begin
    Writeln(Format('%s:%d', [pPlan.FilePath, pPlan.Line]));
    Write(pPlan.Text);
    Writeln('- ' + pPlan.HeritageBefore);
    Writeln('+ ' + pPlan.HeritageAfter);
  end;
  if pRan then
    if pGate.Applied then Writeln('applied and built; re-index the project')
    else Writeln(Format('refused [%s]: %s', [pGate.Refusal, pGate.Detail]));
end;

function RunExtractInterface(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TExtractInterfaceOptions): Integer;

  function Fail(const pMessage: string): Integer;
  begin
    Result:= ReportVerbError(pOpts.Json, CSchema, pMessage);
  end;

begin
  if pOpts.ClassRef = '' then Exit(Fail(CVerb + ' needs --class <name>'));
  if pOpts.Apply and pOpts.NoCompile then Exit(Fail(CVerb + ' --apply cannot take --no-compile: every applied rewrite is built'));
  if pOpts.Apply and (pOpts.Project = '') then Exit(Fail(CVerb + ' --apply needs --project <X.dproj>: the gates build it'));
  if pStore is not TSQLiteSymbolStore then Exit(Fail(CVerb + ' needs a SQLite index'));
  Result:= CExitOk;
  var Plan: TIfacePlan;
  var Error: string;
  var Planner:= TIfacePlanner.Create(pStore, pLibraries, pOpts);
  try
    Plan:= Planner.Run(Error);
  finally
    Planner.Free;
  end;
  if Error <> '' then Exit(Fail(Error));
  var Gate:= Default(TGateOutcome);
  var Ran:= False;
  if pOpts.Apply then
    if Plan.RefusalKind <> '' then Result:= CExitRefused
    else
    begin
      var Args:= Default(TOneFileApplyArgs);
      Args.Verb:= CVerb;
      Args.HeaderTail:= Format('%s on %s', [Plan.IfaceName, Plan.ClassQName]);
      Args.Project:= pOpts.Project;
      Args.Platform:= pOpts.Platform;
      Args.RsVars:= pOpts.RsVars;
      Args.BuildTimeout:= pOpts.BuildTimeout;
      Args.NoBackup:= pOpts.NoBackup;
      Args.FilePath:= Plan.FilePath;
      Gate:= ApplyOneFileThroughScratch((pStore as TSQLiteSymbolStore).GetConnection, Args, EncodeSource(Plan.NewText, Plan.Enc));
      Ran:= True;
      if not Gate.Applied then Result:= if Gate.RollbackFailed then CExitError else CExitRefused;
    end;
  if pOpts.Json then PrintJson(Plan, Ran, Gate) else PrintText(Plan, pOpts.Apply, Ran, Gate);
end;

end.
