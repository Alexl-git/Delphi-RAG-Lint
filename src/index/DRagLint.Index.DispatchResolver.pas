unit DRagLint.Index.DispatchResolver;

/// <summary>R1 of docs\superpowers\specs\2026-10-26-extract-polymorphic-form-launches.md:
/// derives the two polymorphism tables the calls stage cannot express --
/// dispatch_edges (base method -> override / implementing method) and
/// classref_args (call site -> class passed to a `class of` parameter).</summary>
/// <remarks>
/// Both are DERIVED from rows the parse already wrote (symbols, type_ancestors,
/// call_edges, refs) plus the call-site source text for classref_args. The
/// resolver only READS; TSQLiteSymbolStore.ResolveDispatch wipes and writes.
/// </remarks>

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  DRagLint.Core.Interfaces;

const
  /// <summary>dispatch_edges.kind of a class-chain override.</summary>
  DISPATCH_KIND_OVERRIDE   = 'override';
  /// <summary>dispatch_edges.kind of an interface method -> its implementing class method.</summary>
  DISPATCH_KIND_IMPLEMENTS = 'implements';
  /// <summary>Confidence of a row with exactly one candidate.</summary>
  DISPATCH_CONF_CERTAIN    = 'certain';
  /// <summary>Confidence of a row whose name matched more than one candidate (all are written).</summary>
  DISPATCH_CONF_AMBIGUOUS  = 'ambiguous';

type
  /// <summary>One dispatch_edges row.</summary>
  TDispatchEdge = record
    BaseId    : Int64;
    ImplId    : Int64;
    Kind      : string;
    Confidence: string;
  end;

  /// <summary>One classref_args row.</summary>
  TClassRefArg = record
    RefId     : Int64;
    ArgIndex  : Integer;
    ParamId   : Int64;
    ClassId   : Int64;
    Confidence: string;
  end;

  /// <summary>Rows written and every decline, by reason, for the ResolveLog line.</summary>
  TDispatchCounters = record
    Overrides   : Integer; // dispatch_edges rows of kind override
    Implements  : Integer; // dispatch_edges rows of kind implements
    ClassRefArgs: Integer; // classref_args rows
    NoBase      : Integer; // an override whose chain ends without a virtual of that name
    External    : Integer; // the chain reaches an ancestor with no local id (library) first
    NoImpl      : Integer; // an interface method no method of the implementing chain answers
    Generic     : Integer; // (class, generic interface) pairs resolved by bare name (skipped before resolver 1.17.0-alpha)
    Indirect    : Integer; // a classref argument that is not a bare class name (variable, call, ClassType)
    Stale       : Integer; // a call site in a file changed since it was indexed
    Unread      : Integer; // a call site whose argument list could not be read
  end;

  /// <summary>Builds dispatch_edges and classref_args in memory from one index.</summary>
  /// <remarks>Maps are built once per Run. Not thread-safe. Owns nothing it
  /// is given; AConn and AStore must outlive the instance.</remarks>
  TDispatchResolver = class  // dl:ok high-response@cc6c -- the response set is the FireDAC/dictionary calls of three passes sharing one set of maps; splitting would rebuild the maps per pass
  strict private
    type
      TMeth = record
        Id       : Int64;
        Name     : string; // lower-case
        Signature: string;
        IsVirtual: Boolean;
        Override_: Boolean;
      end;
    var
      FConn       : TFDConnection;
      FStore      : ISymbolStore;
      FExtraStores: TArray<ISymbolStore>;
      FKindOf     : TDictionary<Int64, string>;                    // class/interface id -> kind
      FGenericOf  : TDictionary<Int64, Boolean>;                   // interface id -> generic
      FMethods    : TObjectDictionary<Int64, TList<TMeth>>;        // type id -> its methods
      FParentOf   : TDictionary<Int64, Int64>;                     // class id -> ordinal-0 ancestor id (0 = unresolved row)
      FIntfsOf    : TObjectDictionary<Int64, TList<Int64>>;        // type id -> resolved interface ancestors
      FUsedFiles  : TObjectDictionary<Int64, TDictionary<Int64, Boolean>>;
      FLines      : TDictionary<Int64, TArray<string>>;
      FStaleFiles : TDictionary<Int64, Boolean>;
      FEdges      : TList<TDispatchEdge>;
      FArgs       : TList<TClassRefArg>;
      FEdgeKeys   : TDictionary<string, Boolean>;
      FCounters   : TDispatchCounters;
    procedure LoadTypes;
    procedure LoadUses;
    function  ArityMatches(const ABaseSig, AImplSig: string): Boolean;
    procedure NarrowByParamTypes(const ABaseSig: string; AHits: TList<Int64>; AHitSigs: TList<string>);
    procedure AddEdge(ABase, AImpl: Int64; const AKind, AConf: string);
    procedure ResolveOverrides;
    procedure ResolveImplements;
    procedure ResolveClassRefArgs;
    function  IsClassRefTypeName(const ATypeText: string; ACache: TDictionary<string, Boolean>): Boolean;
    function  LinesOf(AFileId: Int64): TArray<string>;
    function  ClassByName(const AName: string; ASiteFile: Int64; out AConf: string): Int64;
  public
    /// <summary>Prepares a resolver over one index.</summary>
    /// <param name="AStore">The store being resolved; used for file paths and the staleness probe.</param>
    /// <param name="AConn">An open connection to the same database; only SELECTs run on it.</param>
    /// <param name="AExtraStores">Library stores consulted ONLY to recognise a library
    /// `class of` type (Vcl.Forms.TFormClass) as a parameter type; may be nil.</param>
    constructor Create(const AStore: ISymbolStore; AConn: TFDConnection; const AExtraStores: TArray<ISymbolStore>);
    /// <summary>Frees the maps and the row lists.</summary>
    destructor Destroy; override;
    /// <summary>Computes every row. Call once.</summary>
    /// <remarks>Overrides: each `override` method -> the nearest class-chain
    /// ancestor's virtual of that name and arity. Implements: each interface a
    /// class LISTS (transitively through interface ancestors) -> the nearest
    /// method of that name and arity on the class's chain; subclasses are
    /// reached through the override edges, never directly. A GENERIC interface
    /// (IStore&lt;T&gt;, listed as IStore&lt;Integer&gt; or IStore&lt;T&gt;) is
    /// resolved like any other: its ancestor row already names the bare
    /// interface, and arity does not depend on the type arguments. Several
    /// same-arity candidates are narrowed to the one whose parameter type list
    /// equals the interface method's; when that does not leave exactly one,
    /// every arity hit is written 'ambiguous'. ClassRefArgs: a bare
    /// class name passed to a parameter whose type is a class reference.</remarks>
    procedure Run;
    /// <summary>dispatch_edges rows, unique on (BaseId, ImplId).</summary>
    property Edges: TList<TDispatchEdge> read FEdges;
    /// <summary>classref_args rows, unique on (RefId, ArgIndex).</summary>
    property Args: TList<TClassRefArg> read FArgs;
    /// <summary>Row and decline counts of the last Run.</summary>
    property Counters: TDispatchCounters read FCounters;
  end;

implementation

uses
  System.IOUtils,
  System.Hash,
  System.DateUtils,
  System.StrUtils,
  Data.DB,
  FireDAC.Stan.Param,
  DRagLint.Core.Model,
  DRagLint.Analysis.Purity,     { LexCallArguments -- the shared argument lexer }
  DRagLint.Index.CallResolver;  { SignatureArityRange -- read-only reuse }

const
  CHAIN_MAX_DEPTH    = 64; // a deeper class chain is a cycle in bad data

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsBareName(const S: string): Boolean;
begin
  Result:= (S <> '') and CharInSet(S[1], ['A'..'Z', 'a'..'z', '_']);
  if not Result then Exit;
  for var i:= 2 to Length(S) do
    if not (IsIdentChar(S[i]) or (S[i] = '.')) then Exit(False);
end;

/// <summary>The parameter part of a routine signature as a comparable key:
/// per parameter, its modifier and declared type, lower-case, without names,
/// default values or whitespace. `(var A: Integer; const B, C: string = 'x')`
/// gives `var:integer;const:string;const:string;`.</summary>
/// <remarks>Only the text inside the first top-level parentheses counts, so the
/// return type never takes part (Delphi overloads cannot differ by it). An
/// untyped parameter (`var ABuffer`) has an empty type. Parentheses, brackets
/// and angle brackets nest, so a `;` inside them never splits a group.</remarks>
function ParamTypeKey(const ASignature: string): string;
var
  Depth, Open, Close, Start: Integer;
  Inner, Names, TypeText, Modifier: string;
  Groups: TList<string>;
begin
  Result:= '';
  Open:= Pos('(', ASignature);
  if Open = 0 then Exit;
  Depth:= 0;
  Close:= 0;
  for var i:= Open to Length(ASignature) do
  begin
    if CharInSet(ASignature[i], ['(', '[', '<']) then Inc(Depth)
    else if CharInSet(ASignature[i], [')', ']', '>']) then Dec(Depth);
    if Depth = 0 then
    begin
      Close:= i;
      Break;
    end;
  end;
  if Close = 0 then Exit;
  Inner:= Copy(ASignature, Open + 1, Close - Open - 1);
  Groups:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    for var i:= 1 to Length(Inner) + 1 do
    begin
      if (i > Length(Inner)) or ((Depth = 0) and (Inner[i] = ';')) then
      begin
        Groups.Add(Trim(Copy(Inner, Start, i - Start)));
        Start:= i + 1;
      end
      else if CharInSet(Inner[i], ['(', '[', '<']) then Inc(Depth)
      else if CharInSet(Inner[i], [')', ']', '>']) then Dec(Depth);
    end;
    for var G in Groups do
    begin
      if G = '' then Continue;
      var Decl:= G;
      var Eq:= Pos('=', Decl);
      if Eq > 0 then Decl:= Trim(Copy(Decl, 1, Eq - 1));
      var Colon:= Pos(':', Decl);
      Names   := Trim(if Colon > 0 then Copy(Decl, 1, Colon - 1) else Decl);
      TypeText:= if Colon > 0 then Copy(Decl, Colon + 1, MaxInt) else '';
      Modifier:= '';
      var Sp:= Pos(' ', Names);
      if Sp > 0 then
      begin
        var W:= LowerCase(Copy(Names, 1, Sp - 1));
        if MatchStr(W, ['const', 'var', 'out', 'constref']) then
        begin
          Modifier:= W;
          Names:= Trim(Copy(Names, Sp + 1, MaxInt));
        end;
      end;
      TypeText:= LowerCase(StringReplace(StringReplace(TypeText, ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
      for var k:= 1 to Length(Names.Split([','])) do
        Result:= Result + Modifier + ':' + TypeText + ';';
    end;
  finally
    Groups.Free;
  end;
end;

function LastSegment(const S: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', S);
  Result:= if P > 0 then Copy(S, P + 1, MaxInt) else S;
end;

{ TDispatchResolver }

constructor TDispatchResolver.Create(const AStore: ISymbolStore; AConn: TFDConnection; const AExtraStores: TArray<ISymbolStore>);
begin
  inherited Create;
  FStore      := AStore;
  FConn       := AConn;
  FExtraStores:= AExtraStores;
  FKindOf     := TDictionary<Int64, string>.Create;
  FGenericOf  := TDictionary<Int64, Boolean>.Create;
  FMethods    := TObjectDictionary<Int64, TList<TMeth>>.Create([doOwnsValues]);
  FParentOf   := TDictionary<Int64, Int64>.Create;
  FIntfsOf    := TObjectDictionary<Int64, TList<Int64>>.Create([doOwnsValues]);
  FUsedFiles  := TObjectDictionary<Int64, TDictionary<Int64, Boolean>>.Create([doOwnsValues]);
  FLines      := TDictionary<Int64, TArray<string>>.Create;
  FStaleFiles := TDictionary<Int64, Boolean>.Create;
  FEdges      := TList<TDispatchEdge>.Create;
  FArgs       := TList<TClassRefArg>.Create;
  FEdgeKeys   := TDictionary<string, Boolean>.Create;
end;

destructor TDispatchResolver.Destroy;
begin
  FEdgeKeys.Free;
  FArgs.Free;
  FEdges.Free;
  FStaleFiles.Free;
  FLines.Free;
  FUsedFiles.Free;
  FIntfsOf.Free;
  FParentOf.Free;
  FMethods.Free;
  FGenericOf.Free;
  FKindOf.Free;
  inherited Destroy;
end;

procedure TDispatchResolver.LoadTypes;
var
  Q    : TFDQuery;
  M    : TMeth;
  List : TList<TMeth>;
  FldId, FldKind, FldGen, FldPar, FldName, FldSig, FldVirt, FldDir, FldOrd, FldAnc: TField;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT id, kind, generic_params FROM symbols WHERE kind IN (''class'', ''interface'')';
    Q.Open;
    FldId  := Q.FieldByName('id');
    FldKind:= Q.FieldByName('kind');
    FldGen := Q.FieldByName('generic_params');
    while not Q.Eof do
    begin
      FKindOf.AddOrSetValue(FldId.AsLargeInt, FldKind.AsString);
      if FldKind.AsString = 'interface' then FGenericOf.AddOrSetValue(FldId.AsLargeInt, Trim(FldGen.AsString) <> '');
      Q.Next;
    end;
    Q.Close;
    Q.SQL.Text:=
      'SELECT s.id, s.parent_id, s.name, s.signature, s.is_virtual, s.directives FROM symbols s ' +
      'JOIN symbols p ON p.id = s.parent_id ' +
      'WHERE p.kind IN (''class'', ''interface'') ' +
      'AND s.kind IN (''method'', ''procedure'', ''function'', ''constructor'', ''destructor'') ORDER BY s.id';
    Q.Open;
    FldId  := Q.FieldByName('id');
    FldPar := Q.FieldByName('parent_id');
    FldName:= Q.FieldByName('name');
    FldSig := Q.FieldByName('signature');
    FldVirt:= Q.FieldByName('is_virtual');
    FldDir := Q.FieldByName('directives');
    while not Q.Eof do
    begin
      M.Id       := FldId.AsLargeInt;
      M.Name     := LowerCase(FldName.AsString);
      M.Signature:= FldSig.AsString;
      M.IsVirtual:= FldVirt.AsInteger = 1;
      M.Override_:= ContainsText(' ' + FldDir.AsString + ' ', ' override ');
      if not FMethods.TryGetValue(FldPar.AsLargeInt, List) then
      begin
        List:= TList<TMeth>.Create;
        FMethods.Add(FldPar.AsLargeInt, List);
      end;
      List.Add(M);
      Q.Next;
    end;
    Q.Close;
    { Ancestors: ordinal 0 of a CLASS is its parent class (an unresolved row is
      recorded as 0 so the walk can tell "library ancestor" from "no ancestor");
      every resolved row naming an INTERFACE is an implemented / inherited
      interface, whatever its ordinal. }
    Q.SQL.Text:= 'SELECT symbol_id, ordinal, ancestor_symbol_id FROM type_ancestors ORDER BY symbol_id, ordinal';
    Q.Open;
    FldId  := Q.FieldByName('symbol_id');
    FldOrd := Q.FieldByName('ordinal');
    FldAnc := Q.FieldByName('ancestor_symbol_id');
    while not Q.Eof do
    begin
      var Sym:= FldId.AsLargeInt;
      var Anc:= if FldAnc.IsNull then Int64(0) else FldAnc.AsLargeInt;
      var SymKind, AncKind: string;
      if FKindOf.TryGetValue(Sym, SymKind) then
      begin
        if not FKindOf.TryGetValue(Anc, AncKind) then AncKind:= '';
        if (FldOrd.AsInteger = 0) and (SymKind = 'class') and (AncKind <> 'interface') then
          FParentOf.AddOrSetValue(Sym, Anc);
        if AncKind = 'interface' then
        begin
          var IL: TList<Int64>;
          if not FIntfsOf.TryGetValue(Sym, IL) then
          begin
            IL:= TList<Int64>.Create;
            FIntfsOf.Add(Sym, IL);
          end;
          IL.Add(Anc);
        end;
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TDispatchResolver.LoadUses;
var
  Q    : TFDQuery;
  D    : TDictionary<Int64, Boolean>;
  FldFile: TField;
  FldTgt : TField;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT DISTINCT file_id, target_file_id FROM unit_uses WHERE target_file_id IS NOT NULL';
    Q.Open;
    FldFile:= Q.FieldByName('file_id');
    FldTgt := Q.FieldByName('target_file_id');
    while not Q.Eof do
    begin
      if not FUsedFiles.TryGetValue(FldFile.AsLargeInt, D) then
      begin
        D:= TDictionary<Int64, Boolean>.Create;
        FUsedFiles.Add(FldFile.AsLargeInt, D);
      end;
      D.AddOrSetValue(FldTgt.AsLargeInt, True);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TDispatchResolver.ArityMatches(const ABaseSig, AImplSig: string): Boolean;
var
  BMin, BMax, IMin, IMax: Integer;
  BKnown, IKnown        : Boolean;
begin
  { An empty signature is a parameterless routine: arity 0..0. A signature
    SignatureArityRange cannot shape does not filter (same rule as CallResolver). }
  BKnown:= (Trim(ABaseSig) = '') or SignatureArityRange(ABaseSig, BMin, BMax);
  if Trim(ABaseSig) = '' then
  begin
    BMin:= 0;
    BMax:= 0;
  end;
  IKnown:= (Trim(AImplSig) = '') or SignatureArityRange(AImplSig, IMin, IMax);
  if Trim(AImplSig) = '' then
  begin
    IMin:= 0;
    IMax:= 0;
  end;
  Result:= not (BKnown and IKnown) or ((BMin = IMin) and (BMax = IMax));
end;

procedure TDispatchResolver.NarrowByParamTypes(const ABaseSig: string; AHits: TList<Int64>; AHitSigs: TList<string>);
var
  Key : string;
  Keep: Int64;
  N   : Integer;
begin
  { Same-arity overloads (IABZMemoryStream.Read x20 on ORM3 CLIENT) tie on
    arity; the implementing method repeats the interface method's parameter
    types, so an exact type-list match picks it. Narrowing only: unless exactly
    ONE hit matches (a generic T against Integer matches none), the hits stay. }
  if AHits.Count < 2 then Exit;
  Key := ParamTypeKey(ABaseSig);
  Keep:= 0;
  N   := 0;
  for var i:= 0 to AHits.Count - 1 do
    if ParamTypeKey(AHitSigs[i]) = Key then
    begin
      Inc(N);
      Keep:= AHits[i];
    end;
  if N <> 1 then Exit;
  AHits.Clear;
  AHits.Add(Keep);
end;

procedure TDispatchResolver.AddEdge(ABase, AImpl: Int64; const AKind, AConf: string);
var
  E: TDispatchEdge;
begin
  if ABase = AImpl then Exit;
  var Key:= IntToStr(ABase) + ':' + IntToStr(AImpl);
  if FEdgeKeys.ContainsKey(Key) then Exit;
  FEdgeKeys.Add(Key, True);
  E.BaseId    := ABase;
  E.ImplId    := AImpl;
  E.Kind      := AKind;
  E.Confidence:= AConf;
  FEdges.Add(E);
  if AKind = DISPATCH_KIND_OVERRIDE then Inc(FCounters.Overrides) else Inc(FCounters.Implements);
end;

procedure TDispatchResolver.ResolveOverrides;
var
  Pair : TPair<Int64, TList<TMeth>>;
  M, B : TMeth;
  Cur  : Int64;
  Anc  : Int64;
  Hits : TList<Int64>;
  Kind : string;
  Ms   : TList<TMeth>;
begin
  Hits:= TList<Int64>.Create;
  try
    for Pair in FMethods do
    begin
      if not (FKindOf.TryGetValue(Pair.Key, Kind) and (Kind = 'class')) then Continue;
      for M in Pair.Value do
      begin
        if not M.Override_ then Continue;
        Cur:= Pair.Key;
        Hits.Clear;
        for var Depth:= 1 to CHAIN_MAX_DEPTH do
        begin
          if not FParentOf.TryGetValue(Cur, Anc) then
          begin
            Inc(FCounters.NoBase);
            Break;
          end;
          if Anc = 0 then
          begin
            Inc(FCounters.External);
            Break;
          end;
          if FMethods.TryGetValue(Anc, Ms) then
            for B in Ms do
              if (B.Name = M.Name) and B.IsVirtual and ArityMatches(B.Signature, M.Signature) then Hits.Add(B.Id);
          if Hits.Count > 0 then
          begin
            for var H in Hits do
              AddEdge(H, M.Id, DISPATCH_KIND_OVERRIDE, if Hits.Count = 1 then DISPATCH_CONF_CERTAIN else DISPATCH_CONF_AMBIGUOUS);
            Break;
          end;
          Cur:= Anc;
        end; // for Depth
      end; // for M
    end; // for Pair
  finally
    Hits.Free;
  end;
end;

procedure TDispatchResolver.ResolveImplements;
var
  Pair   : TPair<Int64, string>;
  Todo   : TList<Int64>;
  Seen   : TDictionary<Int64, Boolean>;
  Direct : TList<Int64>;
  Up     : TList<Int64>;
  Intf   : Int64;
  IMeths : TList<TMeth>;
  Ms     : TList<TMeth>;
  IM, B  : TMeth;
  Hits   : TList<Int64>;
  Cur    : Int64;
  Anc    : Int64;
  IsGen  : Boolean;
  HitSigs: TList<string>;
begin
  Todo   := TList<Int64>.Create;
  Seen   := TDictionary<Int64, Boolean>.Create;
  Hits   := TList<Int64>.Create;
  HitSigs:= TList<string>.Create;
  try
    for Pair in FKindOf do
    begin
      if Pair.Value <> 'class' then Continue;
      if not FIntfsOf.TryGetValue(Pair.Key, Direct) then Continue;
      { The interfaces this class LISTS, closed over interface ancestry. }
      Todo.Clear;
      Seen.Clear;
      Todo.AddRange(Direct);
      while Todo.Count > 0 do
      begin
        Intf:= Todo[Todo.Count - 1];
        Todo.Delete(Todo.Count - 1);
        if Seen.ContainsKey(Intf) then Continue;
        Seen.Add(Intf, True);
        if FIntfsOf.TryGetValue(Intf, Up) then Todo.AddRange(Up);
      end;
      for Intf in Seen.Keys do
      begin
        { Resolver 1.17.0-alpha (RB-5 P2): generic interfaces are no longer
          skipped -- the ancestor row of `IStore<Integer>` already resolves to
          the bare IStore, and name + arity do not depend on the type arguments. }
        if FGenericOf.TryGetValue(Intf, IsGen) and IsGen then Inc(FCounters.Generic);
        if not FMethods.TryGetValue(Intf, IMeths) then Continue;
        for IM in IMeths do
        begin
          Hits.Clear;
          HitSigs.Clear;
          Cur:= Pair.Key;
          for var Depth:= 1 to CHAIN_MAX_DEPTH do
          begin
            if FMethods.TryGetValue(Cur, Ms) then
              for B in Ms do
                if (B.Name = IM.Name) and ArityMatches(IM.Signature, B.Signature) then
                begin
                  Hits.Add(B.Id);
                  HitSigs.Add(B.Signature);
                end;
            if Hits.Count > 0 then Break;
            if not FParentOf.TryGetValue(Cur, Anc) then
            begin
              Inc(FCounters.NoImpl);
              Break;
            end;
            if Anc = 0 then
            begin
              Inc(FCounters.External);
              Break;
            end;
            Cur:= Anc;
          end; // for Depth
          NarrowByParamTypes(IM.Signature, Hits, HitSigs);
          for var H in Hits do
            AddEdge(IM.Id, H, DISPATCH_KIND_IMPLEMENTS, if Hits.Count = 1 then DISPATCH_CONF_CERTAIN else DISPATCH_CONF_AMBIGUOUS);
        end; // for IM
      end; // for Intf
    end; // for Pair
  finally
    HitSigs.Free;
    Hits.Free;
    Seen.Free;
    Todo.Free;
  end;
end;

function TDispatchResolver.IsClassRefTypeName(const ATypeText: string; ACache: TDictionary<string, Boolean>): Boolean;
var
  Name: string;
  Q   : TFDQuery;
begin
  Name:= LowerCase(LastSegment(Trim(ATypeText)));
  if not IsBareName(Name) then Exit(False);
  if ACache.TryGetValue(Name, Result) then Exit;
  Result:= False;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    { 'classref' after the 1.25.0 re-parse; a pre-E1 row is a 'type' whose
      signature is the class-of text. Both mean the same declaration. }
    Q.SQL.Text:= 'SELECT 1 FROM symbols WHERE name = :n COLLATE NOCASE AND (kind = ''classref'' ' +
                 'OR (kind = ''type'' AND signature LIKE ''class of %'')) LIMIT 1';
    Q.ParamByName('n').AsWideString:= Name;
    Q.Open;
    Result:= not Q.IsEmpty;
  finally
    Q.Free;
  end;
  if not Result then
    for var X in FExtraStores do
    begin
      for var S in X.FindSymbolsByExactName(LastSegment(Trim(ATypeText))) do
        if (S.Kind = skClassRef) or ((S.Kind = skTypeAlias) and StartsText('class of ', S.Signature)) then
        begin
          Result:= True;
          Break;
        end;
      if Result then Break;
    end;
  ACache.Add(Name, Result);
end;

function TDispatchResolver.LinesOf(AFileId: Int64): TArray<string>;
var
  Path: string;
  Txt : string;
  SL  : TStringList;
begin
  if FLines.TryGetValue(AFileId, Result) then Exit;
  Result:= [];
  FLines.Add(AFileId, Result);
  Path:= FStore.GetFilePath(AFileId);
  try
    if (Path = '') or not TFile.Exists(Path) then
    begin
      FStaleFiles.AddOrSetValue(AFileId, True);
      Exit;
    end;
    { Same probe as TCallResolver.LinesOf: the index's line/col are only valid
      for the bytes it parsed. ANSI, as the indexer hashed them. }
    Txt:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Path));
    if not FStore.FileIsUpToDate(Path, DateTimeToUnix(TFile.GetLastWriteTime(Path), False), THashSHA2.GetHashString(Txt)) then
      FStaleFiles.AddOrSetValue(AFileId, True)
    else
    begin
      SL:= TStringList.Create;
      try
        SL.Text:= Txt;
        Result := SL.ToStringArray;
      finally
        SL.Free;
      end;
      FLines.AddOrSetValue(AFileId, Result);
    end;
  except // dl:ok try-except-swallowed@c7b1 -- not swallowed: the file is RECORDED stale and every site in it is counted (Stale)
    on E: EInOutError do FStaleFiles.AddOrSetValue(AFileId, True);
    on E: EFOpenError do FStaleFiles.AddOrSetValue(AFileId, True);
  end;
end;

function TDispatchResolver.ClassByName(const AName: string; ASiteFile: Int64; out AConf: string): Int64;
var
  Q      : TFDQuery;
  Ids    : TList<Int64>;
  InScope: TList<Int64>;
  Used   : TDictionary<Int64, Boolean>;
  FldId    : TField;
  FldFile  : TField;
begin
  Result:= 0;
  AConf := '';
  Q:= TFDQuery.Create(nil);
  Ids:= TList<Int64>.Create;
  InScope:= TList<Int64>.Create;
  try
    Q.Connection:= FConn;
    Q.SQL.Text  := 'SELECT id, file_id FROM symbols WHERE kind = ''class'' AND name = :n COLLATE NOCASE ORDER BY id';
    Q.ParamByName('n').AsWideString:= AName;
    Q.Open;
    if not FUsedFiles.TryGetValue(ASiteFile, Used) then Used:= nil;
    FldId  := Q.FieldByName('id');
    FldFile:= Q.FieldByName('file_id');
    while not Q.Eof do
    begin
      Ids.Add(FldId.AsLargeInt);
      if (FldFile.AsLargeInt = ASiteFile) or ((Used <> nil) and Used.ContainsKey(FldFile.AsLargeInt)) then
        InScope.Add(FldId.AsLargeInt);
      Q.Next;
    end;
    if InScope.Count = 1 then
    begin
      Result:= InScope[0];
      AConf := DISPATCH_CONF_CERTAIN;
    end
    else if (InScope.Count = 0) and (Ids.Count = 1) then
    begin
      Result:= Ids[0];
      AConf := DISPATCH_CONF_CERTAIN;
    end
    else if Ids.Count > 1 then
    begin
      Result:= if InScope.Count > 0 then InScope[0] else Ids[0];
      AConf := DISPATCH_CONF_AMBIGUOUS;
    end;
  finally
    InScope.Free;
    Ids.Free;
    Q.Free;
  end;
end;

procedure TDispatchResolver.ResolveClassRefArgs;
type
  TParamAt = record Id: Int64; Index: Integer; end;
var
  Q       : TFDQuery;
  Cache   : TDictionary<string, Boolean>;
  ByRoutine: TObjectDictionary<Int64, TList<TParamAt>>;
  PA      : TParamAt;
  PL      : TList<TParamAt>;
  LastPar : Int64;
  Idx     : Integer;
  Known   : Boolean;
  Texts   : TArray<string>;
  A       : TClassRefArg;
  Conf    : string;
  FldId, FldPar, FldSig, FldRef, FldFile, FldLine, FldCol, FldName: TField;
begin
  Cache    := TDictionary<string, Boolean>.Create;
  ByRoutine:= TObjectDictionary<Int64, TList<TParamAt>>.Create([doOwnsValues]);
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    { Params of every routine some call edge targets, in declaration order --
      the parser emits one param row per name, in source order, so id order is
      argument order. }
    Q.SQL.Text:=
      'SELECT p.id, p.parent_id, p.signature FROM symbols p ' +
      'WHERE p.kind = ''param'' AND p.parent_id IN (SELECT DISTINCT target_symbol_id FROM call_edges) ' +
      'ORDER BY p.parent_id, p.id';
    Q.Open;
    FldId := Q.FieldByName('id');
    FldPar:= Q.FieldByName('parent_id');
    FldSig:= Q.FieldByName('signature');
    LastPar:= -1;
    Idx    := 0;
    while not Q.Eof do
    begin
      if FldPar.AsLargeInt <> LastPar then
      begin
        LastPar:= FldPar.AsLargeInt;
        Idx    := 0;
      end;
      if IsClassRefTypeName(FldSig.AsString, Cache) then
      begin
        if not ByRoutine.TryGetValue(LastPar, PL) then
        begin
          PL:= TList<TParamAt>.Create;
          ByRoutine.Add(LastPar, PL);
        end;
        PA.Id   := FldId.AsLargeInt;
        PA.Index:= Idx;
        PL.Add(PA);
      end;
      Inc(Idx);
      Q.Next;
    end;
    Q.Close;
    if ByRoutine.Count = 0 then Exit;
    Q.SQL.Text:=
      'SELECT ce.ref_id, r.file_id, r.start_line, r.start_col, r.name_text FROM call_edges ce ' +
      'JOIN refs r ON r.id = ce.ref_id WHERE ce.target_symbol_id = :t ORDER BY ce.ref_id';
    for var R in ByRoutine do
    begin
      Q.ParamByName('t').AsLargeInt:= R.Key;
      Q.Open;
      FldRef := Q.FieldByName('ref_id');
      FldFile:= Q.FieldByName('file_id');
      FldLine:= Q.FieldByName('start_line');
      FldCol := Q.FieldByName('start_col');
      FldName:= Q.FieldByName('name_text');
      while not Q.Eof do
      begin
        var RefId := FldRef.AsLargeInt;
        var FileId:= FldFile.AsLargeInt;
        var Lines := LinesOf(FileId);
        if FStaleFiles.ContainsKey(FileId) then
          Inc(FCounters.Stale)
        else
        begin
          Known:= LexCallArguments(Lines, FldLine.AsInteger, FldCol.AsInteger + Length(FldName.AsString), Texts);
          if not Known then Inc(FCounters.Unread)
          else
            for PA in R.Value do
            begin
              if PA.Index >= Length(Texts) then Continue; // a defaulted argument left out
              var ArgText:= Texts[PA.Index];
              var ClsId: Int64:= 0;
              if IsBareName(ArgText) then ClsId:= ClassByName(LastSegment(ArgText), FileId, Conf);
              if ClsId = 0 then
              begin
                Inc(FCounters.Indirect);
                Continue;
              end;
              A.RefId     := RefId;
              A.ArgIndex  := PA.Index;
              A.ParamId   := PA.Id;
              A.ClassId   := ClsId;
              A.Confidence:= Conf;
              FArgs.Add(A);
              Inc(FCounters.ClassRefArgs);
            end;
        end;
        Q.Next;
      end;
      Q.Close;
    end;
  finally
    Q.Free;
    ByRoutine.Free;
    Cache.Free;
  end;
end;

procedure TDispatchResolver.Run;
begin
  FCounters:= Default(TDispatchCounters);
  FEdges.Clear;
  FArgs.Clear;
  FEdgeKeys.Clear;
  LoadTypes;
  LoadUses;
  ResolveOverrides;
  ResolveImplements;
  ResolveClassRefArgs;
end;

end.
