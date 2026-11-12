unit DRagLint.Refactor.NarrowParam;

// ---------------------------------------------------------------------------
// `narrow-param`: retypes a class-typed parameter to the deepest ancestor that still declares every member the routine
// uses (lane 144, item 2 of docs\wiki\narrow-param.md).
//
// The proof: Delphi binds `p.m` to the first class from p's type upward that declares m. So take D(m), that first class,
// for every member used; TNarrow is the D(m) nearest p's type. No class strictly below D(m) declares m, so from TNarrow
// every use binds to what it binds to today, hidden non-virtuals included, and virtual dispatch is dynamic and unchanged.
// Callers still compile: an argument of the old type is an argument of an ancestor. dcc does NOT catch a rebound hidden
// member; this rule does. The compile gate is the backstop, not the proof.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, DRagLint.Core.Interfaces;

type
  /// <summary>The flags of one `narrow-param` run.</summary>
  TNarrowParamOptions = record
    /// <summary>--routine: the routine's qualified name; '' with All.</summary>
    Routine: string;
    /// <summary>--param: only this parameter; '' = every parameter of the routine.</summary>
    Param: string;
    /// <summary>--all: every routine of the index.</summary>
    All: Boolean;
    /// <summary>--project: required with --apply; bounds the edit to the project's own roots.</summary>
    Project: string;
    /// <summary>--platform, '' = win64.</summary>
    Platform: string;
    /// <summary>--rsvars, '' = the Studio the registry / BDS names.</summary>
    RsVars: string;
    /// <summary>--build-timeout in whole seconds, as typed; '' or '0' = no limit.</summary>
    BuildTimeout: string;
    /// <summary>--apply: write through the compile gate; otherwise the plan is printed (--plan says so explicitly).</summary>
    Apply: Boolean;
    /// <summary>--no-backup (apply only).</summary>
    NoBackup: Boolean;
    /// <summary>--no-compile: legal on the plan only; refused with --apply.</summary>
    NoCompile: Boolean;
    /// <summary>--format json.</summary>
    Json: Boolean;
  end;

  /// <summary>One parameter the planner decided.</summary>
  TNarrowSite = record
    /// <summary>The file holding the routine's declaration.</summary>
    FilePath: string;
    /// <summary>The declaration's line.</summary>
    Line: Integer;
    /// <summary>The routine's qualified name.</summary>
    Routine: string;
    /// <summary>The parameter's name.</summary>
    Param: string;
    /// <summary>The declared type.</summary>
    FromType: string;
    /// <summary>The type to narrow to; '' on a refusal.</summary>
    ToType: string;
    /// <summary>The unit that must join the uses clause; '' when the type is already in scope.</summary>
    AddUses: string;
    /// <summary>'' for a fix; else the refusal's name.</summary>
    Kind: string;
    /// <summary>Why, in words; '' for a fix.</summary>
    Reason: string;
  end;

  /// <summary>The verdict over the parameters in scope.</summary>
  TNarrowPlan = record
    /// <summary>The parameters that can narrow.</summary>
    Fixes: TArray<TNarrowSite>;
    /// <summary>The class-typed parameters that cannot be proved, each with a named reason.</summary>
    Refused: TArray<TNarrowSite>;
    /// <summary>Parameters whose uses already need their declared type.</summary>
    AlreadyNarrow: Integer;
  end;

/// <summary>Decides the class-typed parameters in scope.</summary>
/// <param name="pStore">The project's index; must be a SQLite store.</param>
/// <param name="pLibraries">The platform library indexes, or none; without them an ancestor or member the project does
/// not declare is unproved.</param>
/// <param name="pOpts">Routine, Param, All and Project bound the run.</param>
/// <returns>The plan. Reads the source files; writes nothing.</returns>
/// <remarks>A parameter narrows only when ALL of these hold; the first that fails names the refusal: the file is what the
/// index read and is a source unit in the project's roots (stale-file, include-file, outside-roots); no directive in the
/// routine (ifdef-in-routine); it has a body, no asm (no-body, asm-body); the routine is not virtual, override, dynamic,
/// abstract or message (virtual-routine), not overloaded (overloaded-routine), not published (published-routine), declares
/// no interface's method of its name (implements-interface), is no property's accessor (property-accessor) and is never
/// taken as a value (routine-as-value); the parameter is by value or const (by-reference), declared alone (grouped-param),
/// not shadowed inside (shadowed); its type has a whole chain (unresolved-ancestor), no generic form (generic-type), one
/// meaning (ambiguous-type-name); every use is `p.m` read, written or called, or a nil test, with no `with` in the body
/// (with-body, other-use, no-member-use); each m has a first declaring class in the chain (member-not-in-chain), is
/// not overloaded (overloaded-member), and an index binding agrees with it (binding-mismatch); the narrow type is not generic (generic-ancestor) and is in scope
/// or its unit can be added without a cycle (uses-cycle).</remarks>
function PlanNarrowParams(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TNarrowParamOptions): TNarrowPlan;

/// <summary>Runs the verb: prints the plan and, with --apply, writes through ApplyGated.</summary>
/// <param name="pStore">The project's index.</param>
/// <param name="pLibraries">The platform library indexes, or none.</param>
/// <param name="pOpts">The flags.</param>
/// <returns>0: plan, or applied and built, or nothing to do. 1: the gate refused and the project is unchanged; or --apply
/// on one routine whose parameter was refused. 2: bad flags, no such routine, or a rollback that failed.</returns>
function RunNarrowParam(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TNarrowParamOptions): Integer;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.StrUtils, System.RegularExpressions,
  System.Generics.Collections, System.Generics.Defaults, System.Math, Winapi.Windows,
  FireDAC.Comp.Client,
  DRagLint.Project.OwnRoots, DRagLint.Report.CyclePlan, DRagLint.Refactor.CompileGate,
  DRagLint.Refactor.RedundantCast, DRagLint.Storage.SQLite;

const
  CExitOk      = 0;
  CExitRefused = 1;
  CExitError   = 2;
  CMsPerSec    = 1000;
  CMaxChain    = 64;
  CVerb        = 'narrow-param';
  CSchema      = 'narrow-param/1';
  CRoutineKinds = '''method'',''function'',''procedure'',''constructor''';

type
  // One class of a chain: which index holds it, under which id.
  TChainClass = record
    Name, QName, Heritage, GenericParams: string;
    Conn: TFDConnection;
    Id, FileId: Int64;
    ProjectStore: Boolean;
  end;

  TRoutineRow = record
    Id, FileId, ParentId: Int64;
    Name, QName, Kind, Signature, Modifiers, Directives, Section, Path: string;
    IsVirtual, VisExplicit: Boolean;
    StartLine, EndLine, ImplStart, ImplEnd: Integer;
  end;

  TParamRow = record
    Id: Int64;
    Name, TypeText: string;
  end;

  // Why a decision stopped: Exit with this set.
  TVerdict = record
    Kind, Reason: string;
  end;

  TNarrowPlanner = class  // dl:ok high-response@40f3 -- one planner class holds one proof and its caches
  strict private
    FStore    : ISymbolStore;
    FConn     : TFDConnection;
    FLibConns : TArray<TFDConnection>;
    FOpts     : TNarrowParamOptions;
    FOwn      : TOwnRoots;
    FFiles    : TObjectDictionary<string, TMaskedSource>;
    FChains   : TDictionary<string, TArray<TChainClass>>;
    FClasses  : TDictionary<string, TArray<TChainClass>>;
    FFixes    : TList<TNarrowSite>;
    FRefused  : TList<TNarrowSite>;
    FAlready  : Integer;
    FAccessors: TDictionary<string, Boolean>;  // every name after `read` / `write` in the index's files; nil = not read yet
    function SourceOf(const pPath: string): TMaskedSource;
    function ClassesNamed(const pName: string): TArray<TChainClass>;
    function ChainOf(const pClass: TChainClass; out pMissing: string): TArray<TChainClass>;
    function MemberRows(const pClass: TChainClass; const pName: string; out pOverload: Boolean): Integer;
    function Scalar(const pSql: string; const pParams: array of const): Int64;
    function CheckRoutine(const pR: TRoutineRow; const pParam: TParamRow; out pVerdict: TVerdict): Boolean;
    function ScanBody(const pR: TRoutineRow; const pParam: TParamRow; pSource: TMaskedSource; pMembers: TList<string>; out pVerdict: TVerdict): Boolean;
    function ReachesUnit(pFromFile, pToFile: Int64): Boolean;
    function IsAccessor(const pName: string): Boolean;
    function UsesPlan(const pR: TRoutineRow; const pNarrow: TChainClass; out pAdd: string; out pVerdict: TVerdict): Boolean;
    procedure Decide(const pR: TRoutineRow; const pParam: TParamRow);
    procedure AddRefused(const pR: TRoutineRow; const pParam: TParamRow; const pKind, pReason: string);
    function ReadRoutines: TArray<TRoutineRow>;
    function ParamsOf(pRoutine: Int64): TArray<TParamRow>;
  public
    constructor Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pOpts: TNarrowParamOptions);
    destructor Destroy; override;
    function Run(out pNoSuchRoutine: Boolean): TNarrowPlan;
  end;

{ ---- small helpers ---------------------------------------------------------------------------------- }

function Verdict(const pKind, pReason: string): TVerdict;
begin
  Result.Kind  := pKind;
  Result.Reason:= pReason;
end;

function Leaf(const pName: string): string;
begin
  Result:= Trim(pName);
  while Result.Contains('.') do Result:= Copy(Result, Pos('.', Result) + 1, MaxInt);
end;

function HeritageParent(const pHeritage: string): string;
begin
  Result:= Trim(pHeritage);
  if Result.Contains(',') then Result:= Trim(Copy(Result, 1, Pos(',', Result) - 1));
  if Result.Contains('<') then Result:= Trim(Copy(Result, 1, Pos('<', Result) - 1));
  Result:= Leaf(Result);
end;

function HeritageList(const pHeritage: string): TArray<string>;
begin
  Result:= nil;
  for var P in pHeritage.Split([',']) do
    if Trim(P) <> '' then Result:= Result + [Leaf(TRegEx.Replace(P, '<.*$', ''))];
end;

{ ---- the planner ------------------------------------------------------------------------------------ }

constructor TNarrowPlanner.Create(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>; const pOpts: TNarrowParamOptions);
begin
  inherited Create;
  FStore:= pStore;
  FOpts := pOpts;
  FConn := (pStore as TSQLiteSymbolStore).GetConnection;
  for var L in pLibraries do
    if L is TSQLiteSymbolStore then FLibConns:= FLibConns + [(L as TSQLiteSymbolStore).GetConnection];
  if pOpts.Project <> '' then FOwn:= TOwnRoots.Load(ExtractFilePath(ExpandFileName(pOpts.Project)));
  FFiles  := TObjectDictionary<string, TMaskedSource>.Create([doOwnsValues]);
  FChains := TDictionary<string, TArray<TChainClass>>.Create;
  FClasses:= TDictionary<string, TArray<TChainClass>>.Create;
  FFixes  := TList<TNarrowSite>.Create;
  FRefused:= TList<TNarrowSite>.Create;
end;

destructor TNarrowPlanner.Destroy;
begin
  FAccessors.Free;
  FRefused.Free;
  FFixes.Free;
  FClasses.Free;
  FChains.Free;
  FFiles.Free;
  inherited Destroy;
end;

function TNarrowPlanner.SourceOf(const pPath: string): TMaskedSource;
begin
  var Key:= LowerCase(pPath);
  if not FFiles.TryGetValue(Key, Result) then
  begin
    Result:= TMaskedSource.Create(pPath);
    FFiles.Add(Key, Result);
  end;
end;

// One integer from one row; params are :a, :b, ... in order.
function TNarrowPlanner.Scalar(const pSql: string; const pParams: array of const): Int64;
const
  CFirstParam = Ord('a');
begin
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= pSql;
    for var I:= 0 to High(pParams) do
    begin
      var Name:= Chr(CFirstParam + I);
      case pParams[I].VType of
        vtInteger : Q.ParamByName(Name).AsLargeInt:= pParams[I].VInteger;
        vtInt64   : Q.ParamByName(Name).AsLargeInt:= pParams[I].VInt64^;
        vtUnicodeString: Q.ParamByName(Name).AsWideString:= string(pParams[I].VUnicodeString);
      end;
    end;
    Q.Open;
    Result:= if Q.Eof then 0 else Q.Fields[0].AsLargeInt;
  finally
    Q.Free;
  end;
end;

function TNarrowPlanner.ClassesNamed(const pName: string): TArray<TChainClass>;
var
  Rows: TList<TChainClass>;

  procedure ReadFrom(pConn: TFDConnection; pProject: Boolean);
  begin
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= pConn;
      Q.SQL.Text:= 'SELECT id, file_id, name, qualified_name, heritage, generic_params FROM symbols ' +
                   'WHERE name = :n COLLATE NOCASE AND kind = ''class'' ORDER BY (heritage IS NULL)';
      Q.ParamByName('n').AsWideString:= pName;
      Q.Open;
      while not Q.Eof do
      begin
        var C: TChainClass;
        C.Id           := Q.FieldByName('id').AsLargeInt;  // dl:ok field-by-name-in-loop@c05f -- a few thousand rows at most; column names beat positions (magic-literal) here
        C.FileId       := Q.FieldByName('file_id').AsLargeInt;
        C.Name         := Q.FieldByName('name').AsString;
        C.QName        := Q.FieldByName('qualified_name').AsString;
        C.Heritage     := Q.FieldByName('heritage').AsString;
        C.GenericParams:= Q.FieldByName('generic_params').AsString;
        C.Conn         := pConn;
        C.ProjectStore := pProject;
        { a forward declaration is the same class: keep the row with the heritage }
        var Dup:= False;
        for var E in Rows do
          if SameText(E.QName, C.QName) then Dup:= True;
        if not Dup then Rows.Add(C);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  end;

begin
  var Key:= LowerCase(pName);
  if FClasses.TryGetValue(Key, Result) then Exit;
  Rows:= TList<TChainClass>.Create;
  try
    ReadFrom(FConn, True);
    for var C in FLibConns do ReadFrom(C, False);
    Result:= Rows.ToArray;
  finally
    Rows.Free;
  end;
  FClasses.Add(Key, Result);
end;

// pClass and its ancestors, nearest first. pMissing names the first ancestor no index holds, or one that means two
// classes: the chain is then unproved.
function TNarrowPlanner.ChainOf(const pClass: TChainClass; out pMissing: string): TArray<TChainClass>;
begin
  pMissing:= '';
  Result:= [pClass];
  var Cur:= pClass;
  while Length(Result) < CMaxChain do
  begin
    var Up:= HeritageParent(Cur.Heritage);
    if Up = '' then
    begin
      if SameText(Cur.Name, 'TObject') then Exit;
      { no heritage: TObject is the implicit parent, which only a library index holds }
      Up:= 'TObject';
    end;
    var Rows:= ClassesNamed(Up);
    if Length(Rows) = 0 then
    begin
      if SameText(Up, 'TObject') then Exit; { the chain is whole; its members are simply not known }
      pMissing:= Up;
      Exit;
    end;
    if Length(Rows) > 1 then
    begin
      pMissing:= Up + ' (more than one class of that name)';
      Exit;
    end;
    Cur:= Rows[0];
    Result:= Result + [Cur];
  end;
  pMissing:= Cur.Name + ' (the chain does not end)';
end;

// How many members of that name pClass itself declares.
function TNarrowPlanner.MemberRows(const pClass: TChainClass; const pName: string; out pOverload: Boolean): Integer;
begin
  Result:= 0;
  pOverload:= False;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pClass.Conn;
    Q.SQL.Text:= 'SELECT directives FROM symbols WHERE parent_id = :p AND name = :n COLLATE NOCASE AND kind NOT IN (''param'', ''local_var'')';
    Q.ParamByName('p').AsLargeInt  := pClass.Id;
    Q.ParamByName('n').AsWideString:= pName;
    Q.Open;
    while not Q.Eof do
    begin
      Inc(Result);
      if ContainsText(Q.FieldByName('directives').AsString, 'overload') then pOverload:= True;  // dl:ok field-by-name-in-loop@0aa8 -- a few thousand rows at most; column names beat positions (magic-literal) here
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TNarrowPlanner.CheckRoutine(const pR: TRoutineRow; const pParam: TParamRow; out pVerdict: TVerdict): Boolean;  // dl:ok deep-nesting@3d4c, too-many-exit-points@4afe -- the guard list of the refusals; a split would hide their order
begin
  Result:= False;
  pVerdict:= Default(TVerdict);
  if pR.ImplStart <= 0 then
  begin
    pVerdict:= Verdict('no-body', 'abstract, external or implemented elsewhere: no body shows what is used');
    Exit;
  end;
  if pR.IsVirtual or TRegEx.IsMatch(pR.Directives, '\b(virtual|override|dynamic|abstract|message|reintroduce)\b', [roIgnoreCase]) then
  begin
    pVerdict:= Verdict('virtual-routine', 'the signature is shared with the overriding and overridden methods');
    Exit;
  end;
  var Siblings:= Scalar('SELECT COUNT(*) FROM symbols WHERE file_id = :a AND COALESCE(parent_id, 0) = :b AND name = :c COLLATE NOCASE',
    [pR.FileId, pR.ParentId, pR.Name]);
  if ContainsText(pR.Directives, 'overload') or (Siblings > 1) then
  begin
    pVerdict:= Verdict('overloaded-routine', 'a new parameter type could change which overload a caller gets');
    Exit;
  end;
  if ContainsText(pR.Modifiers, 'published') or ((pR.ParentId > 0) and not pR.VisExplicit) then
  begin
    pVerdict:= Verdict('published-routine', 'a published method may be an event handler a .dfm binds by name and signature');
    Exit;
  end;
  if pR.ParentId > 0 then
  begin
    { an interface's method is implemented by name AND signature, the ancestors' interfaces included }
    var Host:= Scalar('SELECT 1 FROM symbols WHERE id = :a AND kind = ''class''', [pR.ParentId]);
    if Host > 0 then
    begin
      var Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= FConn;
        Q.SQL.Text:= 'SELECT heritage, name FROM symbols WHERE id = :i';
        Q.ParamByName('i').AsLargeInt:= pR.ParentId;
        Q.Open;
        var Entries:= HeritageList(Q.FieldByName('heritage').AsString);
        for var I:= 1 to High(Entries) do
          if ClassesNamed(Entries[I]) = nil then
          begin
            var Hit:= Scalar('SELECT COUNT(*) FROM symbols m JOIN symbols i ON i.id = m.parent_id WHERE i.kind = ''interface'' ' +
              'AND i.name = :a COLLATE NOCASE AND m.name = :b COLLATE NOCASE', [Entries[I], pR.Name]);
            var Known:= Scalar('SELECT COUNT(*) FROM symbols WHERE kind = ''interface'' AND name = :a COLLATE NOCASE', [Entries[I]]);
            if (Hit > 0) or (Known = 0) then
            begin
              pVerdict:= Verdict('implements-interface', Format('%s is declared by %s, or that interface is not indexed', [pR.Name, Entries[I]]));
              Exit;
            end;
          end;
      finally
        Q.Free;
      end;
    end;
    if IsAccessor(pR.Name) then
    begin
      pVerdict:= Verdict('property-accessor', 'a property''s accessor must take exactly the property''s type');
      Exit;
    end;
  end;
  { any ref to the routine that is not a parenthesised call takes it as a value: it has a parameter, so a call must have a list }
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT DISTINCT f.path, r.start_line, r.start_col, r.end_col FROM refs r JOIN files f ON f.id = r.file_id WHERE r.symbol_id = :s';
    Q.ParamByName('s').AsLargeInt:= pR.Id;
    Q.Open;
    while not Q.Eof do
    begin
      var Path:= Q.FieldByName('path').AsString;  // dl:ok field-by-name-in-loop@9da5 -- a few thousand rows at most; column names beat positions (magic-literal) here
      if not TFile.Exists(Path) then
      begin
        pVerdict:= Verdict('routine-as-value', 'a reference to it lies in a file that is gone: re-index');
        Exit;
      end;
      var Src:= SourceOf(Path);
      var After:= Src.OffsetOf(Q.FieldByName('start_line').AsInteger, Q.FieldByName('end_col').AsInteger);
      while InRange(After, 1, Length(Src.Masked)) and CharInSet(Src.Masked[After], [' ', #9, #13, #10]) do Inc(After);
      if (After < 1) or (After > Length(Src.Masked)) or (Src.Masked[After] <> '(') then
      begin
        pVerdict:= Verdict('routine-as-value', Format('%s:%d takes it as a value: a method pointer''s type names the old parameter type',
          [ExtractFileName(Path), Q.FieldByName('start_line').AsInteger]));
        Exit;
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  { also a by-name reference the resolver left unbound: `H.ViaPointed` with no list }
  var Stray:= Scalar('SELECT COUNT(*) FROM refs r WHERE r.symbol_id IS NULL AND r.name_text = :a COLLATE NOCASE AND r.kind IN (''read'', ''member-access'') ' +
    'AND NOT EXISTS (SELECT 1 FROM refs c WHERE c.file_id = r.file_id AND c.start_line = r.start_line AND c.start_col = r.start_col AND c.kind = ''call'')', [pR.Name]);
  if Stray > 0 then
  begin
    pVerdict:= Verdict('routine-as-value', Format('%d unbound reference(s) to the name %s may take it as a value', [Stray, pR.Name]));
    Exit;
  end;
  if TRegEx.IsMatch(pR.Signature, '\b(var|out)\s+[^;:]*\b' + pParam.Name + '\b', [roIgnoreCase]) then
  begin
    pVerdict:= Verdict('by-reference', 'a var or out parameter must have the argument''s exact type');
    Exit;
  end;
  Result:= True;
end;

// Classifies every use of the parameter in the body. True and the member names when each is a member read or call, or a
// nil test.
function TNarrowPlanner.ScanBody(const pR: TRoutineRow; const pParam: TParamRow; pSource: TMaskedSource; pMembers: TList<string>;  // dl:ok too-many-exit-points@e7d7 -- one guard per named refusal, in the documented order: the exits are the contract
  out pVerdict: TVerdict): Boolean;
const
  CNilRight = '^\s*(=|<>)\s*nil\b';
  CNilLeft  = '\bnil\s*(=|<>)\s*$';
begin
  Result:= False;
  pVerdict:= Default(TVerdict);
  var From:= pSource.OffsetOf(pR.ImplStart, 1);
  var Stop:= pSource.LineEnd(pR.ImplEnd);
  var Body:= Copy(pSource.Masked, From, Stop - From);
  { past the header: the parameter's own declaration is not a use }
  var Begins:= TRegEx.Match(Body, '\b(var|const|type|label|begin|asm)\b', [roIgnoreCase]);
  if not Begins.Success then
  begin
    pVerdict:= Verdict('no-body', 'the body could not be read');
    Exit;
  end;
  var BodyFrom:= Begins.Index;
  var ParenClose:= Pos(')', Body);
  if (ParenClose > 0) and (Begins.Index < ParenClose) then
    { `const` or `var` inside the parameter list: start after the list }
    BodyFrom:= ParenClose + 1;
  var Code:= Copy(Body, BodyFrom, MaxInt);
  if TRegEx.IsMatch(Code, '\basm\b', [roIgnoreCase]) then
  begin
    pVerdict:= Verdict('asm-body', 'an asm block uses names the index does not type');
    Exit;
  end;
  if TRegEx.IsMatch(Code, '\bwith\b', [roIgnoreCase]) then
  begin
    pVerdict:= Verdict('with-body', 'inside a with a bare name may be a member of the parameter');
    Exit;
  end;
  for var M in TRegEx.Matches(Code, '\b' + pParam.Name + '\b', [roIgnoreCase]) do
  begin
    var Abs:= From + BodyFrom - 1 + M.Index - 1;
    var LineNo:= pSource.LineOf(Abs);
    var Left:= Copy(Code, 1, M.Index - 1);
    var Right:= Copy(Code, M.Index + M.Length, MaxInt);
    var Prev:= TrimRight(Left);
    if EndsStr('.', Prev) then Continue; { receiver.pP: another name }
    var Member:= TRegEx.Match(Right, '^\s*\.\s*([A-Za-z_&][A-Za-z0-9_]*)\s*(:=)?', [roNone]);
    if Member.Success then
    begin
      var MemberName:= Member.Groups[1].Value;
      if EndsStr('@', Prev) then
      begin
        pVerdict:= Verdict('other-use', Format('line %d takes an address through it', [LineNo]));
        Exit;
      end;
      { A write `p.m:= v` binds m like a read (148 RN): the first class declaring m in the chain is the narrowest
        target, and a descendant that redeclares m stops the narrowing there, so the written member and its type are
        the same ones after the retype. }
      if not pMembers.Contains(MemberName) then pMembers.Add(MemberName);
      Continue;
    end;
    if TRegEx.IsMatch(Right, CNilRight, [roIgnoreCase]) or TRegEx.IsMatch(Prev, CNilLeft, [roIgnoreCase]) or
      (TRegEx.IsMatch(Prev, '\bAssigned\s*\($', [roIgnoreCase]) and TRegEx.IsMatch(Right, '^\s*\)', [roNone])) then
    begin
      if EndsStr('@', Prev) then
      begin
        pVerdict:= Verdict('other-use', Format('line %d takes its address', [LineNo]));
        Exit;
      end;
      Continue;
    end;
    pVerdict:= Verdict('other-use', Format('line %d uses %s other than to read a member or test it for nil', [LineNo, pParam.Name]));
    Exit;
  end;
  Result:= True;
end;

// True when any property in the index's source names pName as an accessor. The index keeps only `rw` in prop_access, and
// a descendant's property may name an ancestor's method, so every file is read once.
function TNarrowPlanner.IsAccessor(const pName: string): Boolean;
begin
  if FAccessors = nil then
  begin
    FAccessors:= TDictionary<string, Boolean>.Create;
    var Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= FConn;
      Q.SQL.Text:= 'SELECT path FROM files';
      Q.Open;
      while not Q.Eof do
      begin
        var Path:= Q.FieldByName('path').AsString;  // dl:ok field-by-name-in-loop@9da5 -- a few thousand rows at most; column names beat positions (magic-literal) here
        if TFile.Exists(Path) then
          for var M in TRegEx.Matches(TFile.ReadAllText(Path, TEncoding.ANSI), '\b(?:read|write)\s+([A-Za-z_][A-Za-z0-9_]*)', [roIgnoreCase]) do
            FAccessors.AddOrSetValue(LowerCase(M.Groups[1].Value), True);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  end;
  Result:= FAccessors.ContainsKey(LowerCase(pName));
end;

// True when unit pFromFile reaches unit pToFile over the uses clauses, either section.
function TNarrowPlanner.ReachesUnit(pFromFile, pToFile: Int64): Boolean;
begin
  if pFromFile = pToFile then Exit(True);
  Result:= Scalar('WITH RECURSIVE reach(id) AS (SELECT :a UNION SELECT u.target_file_id FROM unit_uses u JOIN reach r ON r.id = u.file_id ' +
    'WHERE u.target_file_id IS NOT NULL) SELECT COUNT(*) FROM reach WHERE id = :b', [pFromFile, pToFile]) > 0;
end;

// Whether pNarrow's name is in scope where the header needs it, or which unit to add; refuses a cycle.
function TNarrowPlanner.UsesPlan(const pR: TRoutineRow; const pNarrow: TChainClass; out pAdd: string; out pVerdict: TVerdict): Boolean;  // dl:ok too-many-exit-points@6f37 -- one guard per named refusal, in the documented order: the exits are the contract
begin
  Result:= False;
  pVerdict:= Default(TVerdict);
  pAdd:= '';
  if SameText(pNarrow.Name, 'TObject') then Exit(True);
  if pNarrow.ProjectStore and (pNarrow.FileId = pR.FileId) then Exit(True);
  var UnitName:= '';
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pNarrow.Conn;
    Q.SQL.Text:= 'SELECT path FROM files WHERE id = :i';
    Q.ParamByName('i').AsLargeInt:= pNarrow.FileId;
    Q.Open;
    if not Q.Eof then UnitName:= TPath.GetFileNameWithoutExtension(Q.FieldByName('path').AsString);
  finally
    Q.Free;
  end;
  if UnitName = '' then
  begin
    pVerdict:= Verdict('uses-cycle', Format('the unit declaring %s is unknown', [pNarrow.Name]));
    Exit;
  end;
  { the header in the interface section needs the unit in the interface's clause; an implementation-only routine in either }
  var InIntf:= Scalar('SELECT COUNT(*) FROM unit_uses WHERE file_id = :a AND unit_name_norm = :b AND section = ''interface''', [pR.FileId, LowerCase(Leaf(UnitName))]) > 0;
  var InImpl:= Scalar('SELECT COUNT(*) FROM unit_uses WHERE file_id = :a AND unit_name_norm = :b AND section <> ''interface''', [pR.FileId, LowerCase(Leaf(UnitName))]) > 0;
  if InIntf or (InImpl and not SameText(pR.Section, 'interface')) then Exit(True);
  if InImpl then
  begin
    pVerdict:= Verdict('uses-cycle', Format('%s is used from the implementation only and the header is in the interface: moving it could make a cycle', [UnitName]));
    Exit;
  end;
  if pNarrow.ProjectStore and ReachesUnit(pNarrow.FileId, pR.FileId) then
  begin
    pVerdict:= Verdict('uses-cycle', Format('%s already reaches this unit: adding it could make a cycle', [UnitName]));
    Exit;
  end;
  pAdd:= UnitName;
  Result:= True;
end;

procedure TNarrowPlanner.AddRefused(const pR: TRoutineRow; const pParam: TParamRow; const pKind, pReason: string);
begin
  var S:= Default(TNarrowSite);
  S.FilePath:= pR.Path;
  S.Line    := pR.StartLine;
  S.Routine := pR.QName;
  S.Param   := pParam.Name;
  S.FromType:= pParam.TypeText;
  S.Kind    := pKind;
  S.Reason  := pReason;
  FRefused.Add(S);
end;

procedure TNarrowPlanner.Decide(const pR: TRoutineRow; const pParam: TParamRow);  // dl:ok cyclomatic-complexity@0bf7, too-many-exit-points@0beb -- one branch per named refusal, documented on the public function
var
  V: TVerdict;
begin
  if not TRegEx.IsMatch(pParam.TypeText, '^[A-Za-z_&][A-Za-z0-9_.]*$') then Exit; { not a plain type name: no candidate }
  var Named:= ClassesNamed(Leaf(pParam.TypeText));
  if Length(Named) = 0 then Exit; { not a class: scalars, records and interfaces are not candidates }
  if not MatchText(ExtractFileExt(pR.Path), ['.pas', '.dpr', '.dpk']) then
  begin
    AddRefused(pR, pParam, 'include-file', 'an include file compiles in every unit that includes it');
    Exit;
  end;
  if not TFile.Exists(pR.Path) or not IsFileCurrent(FStore, pR.Path) then
  begin
    AddRefused(pR, pParam, 'stale-file', 'the file changed since it was indexed; re-index');
    Exit;
  end;
  if (FOpts.Project <> '') and not FOwn.IsOurs(pR.Path) then
  begin
    AddRefused(pR, pParam, 'outside-roots', 'the file lies outside the project''s own roots');
    Exit;
  end;
  if Length(Named) > 1 then
  begin
    AddRefused(pR, pParam, 'ambiguous-type-name', Format('%s names %d classes', [pParam.TypeText, Length(Named)]));
    Exit;
  end;
  var Derived:= Named[0];
  if Derived.GenericParams <> '' then
  begin
    AddRefused(pR, pParam, 'generic-type', Format('%s is generic', [pParam.TypeText]));
    Exit;
  end;
  if not CheckRoutine(pR, pParam, V) then
  begin
    AddRefused(pR, pParam, V.Kind, V.Reason);
    Exit;
  end;
  var Src:= SourceOf(pR.Path);
  for var L:= pR.StartLine to pR.EndLine do
    if (L <= High(Src.DirAt)) and (Src.DirAt[L] or Src.CondAt[L]) then
    begin
      AddRefused(pR, pParam, 'ifdef-in-routine', 'a compiler directive in the header: another configuration may differ');
      Exit;
    end;
  for var L:= pR.ImplStart to pR.ImplEnd do
    if (L <= High(Src.DirAt)) and (Src.DirAt[L] or Src.CondAt[L]) then
    begin
      AddRefused(pR, pParam, 'ifdef-in-routine', 'a compiler directive in the routine: the other branch cannot be seen');
      Exit;
    end;
  if Scalar('SELECT COUNT(*) FROM symbols WHERE file_id = :a AND name = :b COLLATE NOCASE AND id <> :c AND start_line BETWEEN :d AND :e',
    [pR.FileId, pParam.Name, pParam.Id, pR.ImplStart, pR.ImplEnd]) > 0 then
  begin
    AddRefused(pR, pParam, 'shadowed', Format('a nested declaration inside the routine also names %s', [pParam.Name]));
    Exit;
  end;
  var Missing: string;
  var Chain:= ChainOf(Derived, Missing);
  if Missing <> '' then
  begin
    AddRefused(pR, pParam, 'unresolved-ancestor', Format('%s descends from %s, which no index holds: what it declares is unknown', [Derived.Name, Missing]));
    Exit;
  end;
  var Members:= TList<string>.Create;
  try
    if not ScanBody(pR, pParam, Src, Members, V) then
    begin
      AddRefused(pR, pParam, V.Kind, V.Reason);
      Exit;
    end;
    if Members.Count = 0 then
    begin
      AddRefused(pR, pParam, 'no-member-use', 'nothing in the body says which class is enough; leave an unused parameter to its own rule');
      Exit;
    end;
    var Deepest:= High(Chain);
    for var M in Members do
    begin
      var First:= -1;
      for var I:= 0 to High(Chain) do
      begin
        var Over: Boolean;
        var Rows:= MemberRows(Chain[I], M, Over);
        if Over or (Rows > 1) then
        begin
          AddRefused(pR, pParam, 'overloaded-member', Format('%s is overloaded on %s: the set a call sees depends on the class', [M, Chain[I].Name]));
          Exit;
        end;
        if (Rows = 1) and (First < 0) then First:= I;
      end;
      if First < 0 then
      begin
        AddRefused(pR, pParam, 'member-not-in-chain', Format('no index holds %s on the chain of %s (a helper, or an unindexed root)', [M, Derived.Name]));
        Exit;
      end;
      { an ancestor's helper-free binding the index holds must agree with the walk }
      var Bound:= Scalar('SELECT r.symbol_id FROM refs r WHERE r.file_id = :a AND r.receiver_text = :b COLLATE NOCASE AND r.name_text = :c COLLATE NOCASE ' +
        'AND r.start_line BETWEEN :d AND :e AND r.symbol_id IS NOT NULL LIMIT 1', [pR.FileId, pParam.Name, M, pR.ImplStart, pR.ImplEnd]);
      if (Bound > 0) and Chain[First].ProjectStore and
        (Scalar('SELECT COUNT(*) FROM symbols WHERE id = :a AND parent_id = :b', [Bound, Chain[First].Id]) = 0) then
      begin
        AddRefused(pR, pParam, 'binding-mismatch', Format('the index binds %s elsewhere than the first class declaring it, %s', [M, Chain[First].Name]));
        Exit;
      end;
      if First < Deepest then Deepest:= First;
    end;
    if Deepest = 0 then
    begin
      Inc(FAlready);
      Exit;
    end;
    var Narrow:= Chain[Deepest];
    { the chain holds an ancestor by its bare name: `TBase<T>` written as `TBase` does not compile, and the type
      arguments the heritage gives are not carried (148 RN; found on Micronite TmcPLANLIST -> TMicObjectBase<I>) }
    if Narrow.GenericParams <> '' then
    begin
      AddRefused(pR, pParam, 'generic-ancestor', Format('%s is generic: the narrow type needs the type arguments %s''s heritage gives', [Narrow.Name, Chain[Deepest - 1].Name]));
      Exit;
    end;
    if Length(ClassesNamed(Narrow.Name)) > 1 then
    begin
      AddRefused(pR, pParam, 'ambiguous-type-name', Format('%s names more than one class', [Narrow.Name]));
      Exit;
    end;
    var Add: string;
    if not UsesPlan(pR, Narrow, Add, V) then
    begin
      AddRefused(pR, pParam, V.Kind, V.Reason);
      Exit;
    end;
    { the headers: `p: T` written alone }
    var Pattern:= '\b' + pParam.Name + '\s*:\s*' + TRegEx.Escape(pParam.TypeText) + '\b';
    var DeclFrom:= Src.OffsetOf(pR.StartLine, 1);
    var DeclText:= Copy(Src.Masked, DeclFrom, Src.LineEnd(pR.EndLine) - DeclFrom);
    var DeclHit:= TRegEx.Match(DeclText, Pattern, [roIgnoreCase]);
    var Before: Integer;
    if not DeclHit.Success or (LastCodeChar(Src.Masked, DeclFrom + DeclHit.Index - 1, Before) = ',') then
    begin
      AddRefused(pR, pParam, 'grouped-param', Format('%s shares its type with another parameter in the header', [pParam.Name]));
      Exit;
    end;
    var Site:= Default(TNarrowSite);
    Site.FilePath:= pR.Path;
    Site.Line    := pR.StartLine;
    Site.Routine := pR.QName;
    Site.Param   := pParam.Name;
    Site.FromType:= pParam.TypeText;
    Site.ToType  := Narrow.Name;
    Site.AddUses := Add;
    FFixes.Add(Site);
  finally
    Members.Free;
  end;
end;

function TNarrowPlanner.ReadRoutines: TArray<TRoutineRow>;
var
  Rows: TList<TRoutineRow>;
begin
  Rows:= TList<TRoutineRow>.Create;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT s.id, s.file_id, COALESCE(s.parent_id, 0) AS parent_id, s.name, s.qualified_name, s.kind, s.signature, s.modifiers, s.directives, s.section, ' +
                 'f.path, s.is_virtual, s.vis_explicit, s.start_line, s.end_line, s.impl_start_line, s.impl_end_line ' +
                 'FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind IN (' + CRoutineKinds + ') ' +
                 'AND EXISTS (SELECT 1 FROM symbols p WHERE p.parent_id = s.id AND p.kind = ''param'') ' +
                 (if FOpts.All then '' else 'AND s.qualified_name = :q COLLATE NOCASE ') + 'ORDER BY f.path, s.start_line';
    if not FOpts.All then Q.ParamByName('q').AsWideString:= FOpts.Routine;
    Q.Open;
    while not Q.Eof do
    begin
      var R: TRoutineRow;
      R.Id         := Q.FieldByName('id').AsLargeInt;  // dl:ok field-by-name-in-loop@7c6b -- a few thousand rows at most; column names beat positions (magic-literal) here
      R.FileId     := Q.FieldByName('file_id').AsLargeInt;
      R.ParentId   := Q.FieldByName('parent_id').AsLargeInt;
      R.Name       := Q.FieldByName('name').AsString;
      R.QName      := Q.FieldByName('qualified_name').AsString;
      R.Kind       := Q.FieldByName('kind').AsString;
      R.Signature  := Q.FieldByName('signature').AsString;
      R.Modifiers  := Q.FieldByName('modifiers').AsString;
      R.Directives := Q.FieldByName('directives').AsString;
      R.Section    := Q.FieldByName('section').AsString;
      R.Path       := Q.FieldByName('path').AsString;
      R.IsVirtual  := Q.FieldByName('is_virtual').AsInteger <> 0;
      R.VisExplicit:= Q.FieldByName('vis_explicit').AsInteger <> 0;
      R.StartLine  := Q.FieldByName('start_line').AsInteger;
      R.EndLine    := Q.FieldByName('end_line').AsInteger;
      R.ImplStart  := Q.FieldByName('impl_start_line').AsInteger;
      R.ImplEnd    := Q.FieldByName('impl_end_line').AsInteger;
      Rows.Add(R);
      Q.Next;
    end;
    Result:= Rows.ToArray;
  finally
    Q.Free;
    Rows.Free;
  end;
end;

function TNarrowPlanner.ParamsOf(pRoutine: Int64): TArray<TParamRow>;
begin
  Result:= nil;
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text:= 'SELECT id, name, signature FROM symbols WHERE parent_id = :p AND kind = ''param'' ORDER BY start_line, start_col';
    Q.ParamByName('p').AsLargeInt:= pRoutine;
    Q.Open;
    while not Q.Eof do
    begin
      var P: TParamRow;
      P.Id      := Q.FieldByName('id').AsLargeInt;  // dl:ok field-by-name-in-loop@f3e7 -- a few thousand rows at most; column names beat positions (magic-literal) here
      P.Name    := Q.FieldByName('name').AsString;
      P.TypeText:= Trim(Q.FieldByName('signature').AsString);
      if (FOpts.Param = '') or SameText(FOpts.Param, P.Name) then Result:= Result + [P];
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TNarrowPlanner.Run(out pNoSuchRoutine: Boolean): TNarrowPlan;
begin
  var Routines:= ReadRoutines;
  pNoSuchRoutine:= (Length(Routines) = 0) and not FOpts.All;
  for var R in Routines do
    for var P in ParamsOf(R.Id) do Decide(R, P);
  Result.Fixes        := FFixes.ToArray;
  Result.Refused      := FRefused.ToArray;
  Result.AlreadyNarrow:= FAlready;
end;

function PlanNarrowParams(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;
  const pOpts: TNarrowParamOptions): TNarrowPlan;
begin
  var Planner:= TNarrowPlanner.Create(pStore, pLibraries, pOpts);
  try
    var NoRoutine: Boolean;
    Result:= Planner.Run(NoRoutine);
  finally
    Planner.Free;
  end;
end;

{ ---- the rewrite ------------------------------------------------------------------------------------- }

// Retypes the parameter in the routine's two headers, on one file's text. The offsets come from the masked copy of the
// text as it stands, so each fix re-reads the file it edits. Raises when a header no longer holds what the plan read.
procedure RetypeHeaders(var pText: string; const pSite: TNarrowSite; const pStore: TFDConnection);

  procedure RetypeIn(pStartLine, pEndLine: Integer; pRequired: Boolean);
  begin
    var Src:= TMaskedSource.CreateFromText(pText);
    try
      var From:= Src.OffsetOf(pStartLine, 1);
      var Span:= Copy(Src.Masked, From, Src.LineEnd(pEndLine) - From);
      { an implementation header may drop its parameter list: only the part up to the first ; after the list counts }
      var M:= TRegEx.Match(Span, '\b' + pSite.Param + '\s*:\s*(' + TRegEx.Escape(pSite.FromType) + ')\b', [roIgnoreCase]);
      if not M.Success then
      begin
        if pRequired then raise EInOutError.CreateFmt('the header of %s no longer declares %s: %s', [pSite.Routine, pSite.Param, pSite.FromType]);
        Exit;
      end;
      var G:= M.Groups[1];
      pText:= Copy(pText, 1, From + G.Index - 2) + pSite.ToType + Copy(pText, From + G.Index - 1 + G.Length, MaxInt);
    finally
      Src.Free;
    end;
  end;

begin
  var Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pStore;
    Q.SQL.Text:= 'SELECT start_line, end_line, impl_start_line FROM symbols WHERE qualified_name = :q COLLATE NOCASE AND start_line = :l';
    Q.ParamByName('q').AsWideString:= pSite.Routine;
    Q.ParamByName('l').AsInteger   := pSite.Line;
    Q.Open;
    if Q.Eof then raise EInOutError.CreateFmt('%s is no longer indexed at line %d', [pSite.Routine, pSite.Line]);
    { same line count in both edits: the implementation's offsets hold after the declaration's }
    RetypeIn(Q.FieldByName('start_line').AsInteger, Q.FieldByName('end_line').AsInteger, True);
    RetypeIn(Q.FieldByName('impl_start_line').AsInteger, Q.FieldByName('impl_start_line').AsInteger, False);
  finally
    Q.Free;
  end;
end;

function BuildGateFiles(const pPlan: TNarrowPlan; pConn: TFDConnection): TArray<TGateFile>;
begin
  Result:= nil;
  var Paths:= TList<string>.Create;
  try
    for var S in pPlan.Fixes do
      if not Paths.Contains(S.FilePath) then Paths.Add(S.FilePath);
    for var P in Paths do
    begin
      var Enc: TEncoding;
      var Text:= DecodeSource(TFile.ReadAllBytes(P), Enc);
      for var S in pPlan.Fixes do
        if SameText(S.FilePath, P) then RetypeHeaders(Text, S, pConn);
      var Lines:= TStringList.Create;
      try
        var Trailing:= EndsStr(#10, Text);
        Lines.LineBreak:= #13#10;
        Lines.Text:= Text;
        var Added:= False;
        for var S in pPlan.Fixes do
          if SameText(S.FilePath, P) and (S.AddUses <> '') and AddToUses(Lines, SectionNameOf(Lines, Max(0, S.Line - 1)), S.AddUses) then Added:= True;
        if Added then
        begin
          Text:= Lines.Text;
          if not Trailing and EndsStr(#13#10, Text) then SetLength(Text, Length(Text) - Length(#13#10));
        end;
      finally
        Lines.Free;
      end;
      var G: TGateFile;
      G.Path := P;
      G.Bytes:= EncodeSource(Text, Enc);
      Result:= Result + [G];
    end;
  finally
    Paths.Free;
  end;
end;

function SiteToJson(const pS: TNarrowSite): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('file', pS.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pS.Line));
  Result.AddPair('routine', pS.Routine);
  Result.AddPair('param', pS.Param);
  Result.AddPair('from', pS.FromType);
  if pS.Kind = '' then
  begin
    Result.AddPair('to', pS.ToType);
    if pS.AddUses <> '' then Result.AddPair('adds_uses', pS.AddUses);
  end
  else
  begin
    Result.AddPair('kind', pS.Kind);
    Result.AddPair('reason', pS.Reason);
  end;
end;

procedure PrintPlanText(const pPlan: TNarrowPlan; pApply: Boolean);
begin
  Writeln(Format('narrow-param: %d can narrow, %d refused, %d already as narrow as their uses%s',
    [Length(pPlan.Fixes), Length(pPlan.Refused), pPlan.AlreadyNarrow, if pApply then '' else ' (plan; add --apply --project <X.dproj> to write)']));
  var Counts:= TDictionary<string, Integer>.Create;
  try
    for var S in pPlan.Refused do
    begin
      var N: Integer;
      if not Counts.TryGetValue(S.Kind, N) then N:= 0;
      Counts.AddOrSetValue(S.Kind, N + 1);
    end;
    var Pairs:= Counts.ToArray;
    TArray.Sort<TPair<string, Integer>>(Pairs, TComparer<TPair<string, Integer>>.Construct(
      function(const pA, pB: TPair<string, Integer>): Integer
      begin
        Result:= pB.Value - pA.Value;
        if Result = 0 then Result:= CompareStr(pA.Key, pB.Key);
      end));
    for var C in Pairs do Writeln(Format('  refused %-24s %d', [C.Key, C.Value]));
  finally
    Counts.Free;
  end;
  for var S in pPlan.Fixes do
    Writeln(Format('narrow   %s:%d  %s  %s: %s -> %s%s', [S.FilePath, S.Line, S.Routine, S.Param, S.FromType, S.ToType,
      if S.AddUses <> '' then ' (adds uses ' + S.AddUses + ')' else '']));
  for var S in pPlan.Refused do
    Writeln(Format('refused  %s:%d  %s  %s: %s  %s -- %s', [S.FilePath, S.Line, S.Routine, S.Param, S.FromType, S.Kind, S.Reason]));
end;

function RunNarrowParam(const pStore: ISymbolStore; const pLibraries: TArray<ISymbolStore>;  // dl:ok too-many-exit-points@8d31 -- one guard per named refusal, in the documented order: the exits are the contract
  const pOpts: TNarrowParamOptions): Integer;
var
  Gate: TGateOutcome;
  Ran : Boolean;

  procedure SayError(const pMessage: string);
  begin
    if pOpts.Json then
    begin
      var J:= TJSONObject.Create;
      try
        J.AddPair('schema', CSchema);
        J.AddPair('error', pMessage);
        J.AddPair('exit_code', TJSONNumber.Create(CExitError));
        Writeln(J.Format(2));
      finally
        J.Free;
      end;
    end
    else Writeln('ERROR: ', pMessage);
  end;

begin
  Result:= CExitOk;
  Gate:= Default(TGateOutcome);
  Ran := False;
  if (pOpts.Routine = '') and not pOpts.All then
  begin
    SayError(CVerb + ' needs --routine <QName> or --all');
    Exit(CExitError);
  end;
  if pOpts.Apply and pOpts.NoCompile then
  begin
    SayError(CVerb + ' --apply cannot take --no-compile: every applied rewrite passes the compile gate');
    Exit(CExitError);
  end;
  if pOpts.Apply and (pOpts.Project = '') then
  begin
    SayError(CVerb + ' --apply needs --project <X.dproj>: the compile gate builds it before and after the rewrite');
    Exit(CExitError);
  end;
  if pStore is not TSQLiteSymbolStore then
  begin
    SayError(CVerb + ' needs a SQLite index');
    Exit(CExitError);
  end;
  var Planner:= TNarrowPlanner.Create(pStore, pLibraries, pOpts);
  var Plan: TNarrowPlan;
  var NoRoutine: Boolean;
  try
    Plan:= Planner.Run(NoRoutine);
  finally
    Planner.Free;
  end;
  if NoRoutine then
  begin
    SayError(Format('%s: the index has no routine %s with a parameter', [CVerb, pOpts.Routine]));
    Exit(CExitError);
  end;
  if pOpts.Apply and (Length(Plan.Fixes) > 0) then
  begin
    var Secs:= StrToIntDef(pOpts.BuildTimeout, 0);
    GBuildTimeoutMs:= if Secs <= 0 then INFINITE else Cardinal(Secs) * CMsPerSec;
    var Req:= Default(TGateRequest);
    Req.Project := ExpandFileName(pOpts.Project);
    Req.Platform:= pOpts.Platform;
    Req.Verb    := CVerb;
    Req.RsVars  := if pOpts.RsVars <> '' then ExpandFileName(pOpts.RsVars) else '';
    Req.NoBackup:= pOpts.NoBackup;
    Req.Header  := Format('[%s] %s --apply: %d parameter(s) narrowed', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), CVerb, Length(Plan.Fixes)]);
    Req.LogDir  := FreshScratchName('_build');
    try
      Req.Files:= BuildGateFiles(Plan, (pStore as TSQLiteSymbolStore).GetConnection);
    except
      on E: EInOutError do
      begin
        SayError(E.Message + '; nothing written; re-index');
        Exit(CExitError);
      end;
    end;
    Gate:= ApplyGated(Req);
    Ran := True;
    if not GScratchCited and TDirectory.Exists(Req.LogDir) then
    try
      TDirectory.Delete(Req.LogDir, True);  // dl:ok taint-path-traversal@ff48 -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
    except
      on EInOutError do Writeln(ErrOutput, 'drag-lint: note: scratch not deleted: ', Req.LogDir); // best effort: a locked log must not change the result
    end;
    if not Gate.Applied then Result:= if Gate.RollbackFailed then CExitError else CExitRefused;
  end
  else if pOpts.Apply and not pOpts.All and (Length(Plan.Refused) > 0) then Result:= CExitRefused;
  if pOpts.Json then
  begin
    var J:= TJSONObject.Create;
    try
      J.AddPair('schema', CSchema);
      J.AddPair('applied', TJSONBool.Create(Ran and Gate.Applied));
      J.AddPair('already_narrow', TJSONNumber.Create(Plan.AlreadyNarrow));
      var Fixes:= TJSONArray.Create;
      J.AddPair('fixes', Fixes);
      for var S in Plan.Fixes do Fixes.AddElement(SiteToJson(S));
      var Refused:= TJSONArray.Create;
      J.AddPair('refused', Refused);
      for var S in Plan.Refused do Refused.AddElement(SiteToJson(S));
      if Ran then
      begin
        var G:= TJSONObject.Create;
        J.AddPair('gate', G);
        G.AddPair('refusal', Gate.Refusal);
        G.AddPair('detail', Gate.Detail);
        G.AddPair('rolled_back', TJSONBool.Create(Gate.RolledBack));
        var Written:= TJSONArray.Create;
        G.AddPair('written', Written);
        for var W in Gate.Tx.Written do Written.Add(W);
      end;
      J.AddPair('exit_code', TJSONNumber.Create(Result));
      Writeln(J.Format(2));
    finally
      J.Free;
    end;
    Exit;
  end;
  PrintPlanText(Plan, pOpts.Apply);
  if Ran then
    if Gate.Applied then Writeln(Format('applied: %d file(s) written, the project builds; re-index', [Length(Gate.Tx.Written)]))
    else Writeln(Format('NOT applied: %s -- %s', [Gate.Refusal, Gate.Detail]));
end;

end.
