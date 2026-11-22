unit DRagLint.Wiring;

/// <summary>
///   Shared builder for the "wiring" view (Spring4D DI + DFM event edges), used by
///   BOTH the CLI `wiring` command and the MCP `get_wiring` tool so the two
///   surfaces always return identical data.
/// </summary>
interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

/// <summary>Drops the UNBOUND DFM event bindings that belong to a form class unrelated to AOwnerClass.</summary>
/// <param name="AStore">Open symbol store (GetDfmObjects, FindSymbolsByExactName, IsDescendantOf).</param>
/// <param name="ARefs">Reference rows; only rows with SymbolId = 0 and Kind 'event-binding' are tested, all others pass through.</param>
/// <param name="AOwnerClass">The class whose handler is queried (bare name, e.g. TFormA); '' keeps every row.</param>
/// <returns>ARefs without the bindings of foreign forms.</returns>
/// <remarks>GitHub #15 / #21: an unbound binding (`OnShow = FormShow`) names the handler only; the method it reaches
/// belongs to the DFM's ROOT object class. A binding is kept when that root class is AOwnerClass or descends from it,
/// or when the index cannot tell (no root row, root class not indexed); it is dropped when the root class is a known
/// class that is not a descendant. Shared by `context` (Context.Bundler) and `wiring` / get_wiring so the verbs stay
/// in step. Pinned by run_v152_GH15.ps1 and run_v1523_GH21.ps1. A descendant that redeclares the handler is kept.</remarks>
function DropForeignFormBindings(const AStore: ISymbolStore; const ARefs: TArray<TReference>;
  const AOwnerClass: string): TArray<TReference>;

/// <summary>The DFM event bindings of the handlers of one form class, owner-filtered.</summary>
/// <param name="AStore">Open symbol store.</param>
/// <param name="AQName">Qualified or bare form class name (Unit.TForm).</param>
/// <returns>FindEventHandlersForForm(AQName) passed through DropForeignFormBindings with the class's leaf name.</returns>
/// <remarks>GitHub #21. Used by BuildWiringJson and the CLI text `wiring`.</remarks>
function FormEventHandlers(const AStore: ISymbolStore; const AQName: string): TArray<TReference>;

/// <summary>The transitive callers of ASyms over the RESOLVED caller rows, level by level.</summary>
/// <param name="AStore">Open symbol store (FindResolvedCallers).</param>
/// <param name="ASyms">The symbols the qname resolved to; only routines seed the walk.</param>
/// <param name="ADepth">Maximum depth.</param>
/// <param name="ALevels">One TImpactLevel per depth that found callers; empty for a routine nobody calls.</param>
/// <returns>False when ASyms holds no routine (the caller keeps the by-name walk for a type or variable).</returns>
/// <remarks>GitHub #14 / #20: the rows `find-callers --resolved` prints; a caller counts once, at the first level
/// that reaches it; a site with no enclosing routine counts per file and is not walked on. Shared by the CLI
/// `impact` and the MCP get_impact.</remarks>
function WalkResolvedImpact(const AStore: ISymbolStore; const ASyms: TArray<TSymbol>; ADepth: Integer;
  out ALevels: TArray<TImpactLevel>): Boolean;

/// <summary>The impact levels of a qualified name, as the CLI `impact` computes them.</summary>
/// <param name="AStore">Open symbol store.</param>
/// <param name="AQName">Qualified name (Unit.TClass.Method).</param>
/// <param name="ADepth">Maximum depth.</param>
/// <param name="ALevels">The levels.</param>
/// <returns>False when AQName names no symbol in the database (the caller reports an error).</returns>
/// <remarks>GitHub #20: resolved walk for routines, by-name walk (FindTransitiveCallers) for a type or variable.</remarks>
function ImpactLevelsForQName(const AStore: ISymbolStore; const AQName: string; ADepth: Integer;
  out ALevels: TArray<TImpactLevel>): Boolean;

/// <summary>Builds the wiring JSON object for a qualified name: DI
/// implementations (+lifetime), DI resolve-sites, and DFM event handlers.</summary>
/// <param name="AQName">Interface name (DI) or form/class name (DFM handlers).</param>
/// <param name="AStore">Open symbol store to query.</param>
/// <returns>A new TJSONObject { qname, implementations[], resolved_at[],
/// event_handlers[] }. The caller owns and must free it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Wiring.DoWiring (DRagLint.CLI.Wiring.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindDiResolveSites, DRagLint.Core.Interfaces.ISymbolStore.FindEventHandlersForForm, DRagLint.Core.Interfaces.ISymbolStore.FindImplementationsOf, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath</para>
/// <para>Returns: TJSONObject.Create</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDiResolveSites"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindEventHandlersForForm"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindImplementationsOf"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildWiringJson(const AQName: string;
  const AStore: ISymbolStore): TJSONObject;

implementation

function DropForeignFormBindings(const AStore: ISymbolStore; const ARefs: TArray<TReference>;
  const AOwnerClass: string): TArray<TReference>;
var
  KeepByFile: TDictionary<Int64, Boolean>;
  Keep      : Boolean;
begin
  if AOwnerClass = '' then Exit(ARefs);
  Result:= [];
  KeepByFile:= TDictionary<Int64, Boolean>.Create;
  try
    for var R in ARefs do
    begin
      if (R.SymbolId <> 0) or not SameText(R.Kind, 'event-binding') then
      begin
        Result:= Result + [R];
        Continue;
      end;
      if not KeepByFile.TryGetValue(R.FileId, Keep) then
      begin
        Keep:= True;
        var Root:= '';
        for var O in AStore.GetDfmObjects(R.FileId) do
          if O.Depth = 0 then
          begin
            Root:= O.ClassName;
            Break;
          end;
        if (Root <> '') and not SameText(Root, AOwnerClass) then
        begin
          var Known:= False;
          for var S in AStore.FindSymbolsByExactName(Root) do
            if S.Kind = skClass then Known:= True;
          if Known then Keep:= AStore.IsDescendantOf(Root, AOwnerClass, 0);
        end;
        KeepByFile.Add(R.FileId, Keep);
      end;
      if Keep then Result:= Result + [R];
    end;
  finally
    KeepByFile.Free;
  end; // try
end; // function

function FormEventHandlers(const AStore: ISymbolStore; const AQName: string): TArray<TReference>;
begin
  var Leaf:= AQName;
  var Dot := LastDelimiter('.', Leaf);
  if Dot > 0 then Leaf:= Copy(Leaf, Dot + 1, MaxInt);
  Result:= DropForeignFormBindings(AStore, AStore.FindEventHandlersForForm(AQName), Leaf);
end; // function

function WalkResolvedImpact(const AStore: ISymbolStore; const ASyms: TArray<TSymbol>; ADepth: Integer;
  out ALevels: TArray<TImpactLevel>): Boolean;
begin
  ALevels:= nil;
  var Frontier: TArray<Int64>:= [];
  for var S in ASyms do
    if S.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor] then Frontier:= Frontier + [S.Id];
  Result:= Length(Frontier) > 0;
  if not Result then Exit;
  var Seen := TDictionary<string, Boolean>.Create;
  var Units: TDictionary<string, Boolean>:= nil;
  try
    for var Id in Frontier do Seen.AddOrSetValue(IntToStr(Id), True);
    for var Lvl:= 1 to ADepth do
    begin
      var Next : TArray<Int64>:= [];
      var Count: Integer:= 0;
      FreeAndNil(Units);
      Units:= TDictionary<string, Boolean>.Create;
      for var Id in Frontier do
        for var C in AStore.FindResolvedCallers(Id) do
        begin
          var Key:= if C.EnclosingSymbolId > 0 then IntToStr(C.EnclosingSymbolId) else 'file:' + LowerCase(C.FullPath);
          if Seen.ContainsKey(Key) then Continue;
          Seen.Add(Key, True);
          Inc(Count);
          Units.AddOrSetValue(LowerCase(C.FullPath), True);
          if C.EnclosingSymbolId > 0 then Next:= Next + [C.EnclosingSymbolId];
        end;
      if Count = 0 then Break;
      var L:= Default(TImpactLevel);
      L.Depth      := Lvl;
      L.CallerCount:= Count;
      L.UnitCount  := Units.Count;
      ALevels:= ALevels + [L];
      Frontier:= Next;
    end;
  finally
    Units.Free;
    Seen.Free;
  end; // try
end; // function

function ImpactLevelsForQName(const AStore: ISymbolStore; const AQName: string; ADepth: Integer;
  out ALevels: TArray<TImpactLevel>): Boolean;
begin
  var Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Syms:= AStore.FindSymbolsByExactName(AQName);
  Result:= Length(Syms) > 0;
  if not Result then
  begin
    ALevels:= nil;
    Exit;
  end;
  if not WalkResolvedImpact(AStore, Syms, ADepth, ALevels) then
  begin
    var Dot:= LastDelimiter('.', AQName);
    ALevels:= AStore.FindTransitiveCallers(if Dot > 0 then Copy(AQName, Dot + 1, MaxInt) else AQName, ADepth);
  end;
end; // function

function BuildWiringJson(const AQName: string;
  const AStore: ISymbolStore): TJSONObject;
var
  Impls: TArray<TDiBindingRow>;
  Sites, Handlers: TArray<TReference>;
  B: TDiBindingRow;
  R: TReference;
  JImpls, JSites, JHandlers: TJSONArray;
  JO: TJSONObject;
begin
  Impls := AStore.FindImplementationsOf(AQName);
  Sites := AStore.FindDiResolveSites(AQName);
  Handlers := FormEventHandlers(AStore, AQName);

  Result := TJSONObject.Create;
  try
    // Adopt the arrays into Result up front, and each JO into its array BEFORE
    // calling GetFilePath (a live DB query that can raise). That way any
    // mid-build exception leaves the whole tree owned by Result, which the
    // except clause frees -- no orphaned arrays/objects (review fix).
    JImpls := TJSONArray.Create;
    JSites := TJSONArray.Create;
    JHandlers := TJSONArray.Create;
    Result.AddPair('qname', AQName);
    Result.AddPair('implementations', JImpls);
    Result.AddPair('resolved_at', JSites);
    Result.AddPair('event_handlers', JHandlers);

    for B in Impls do
    begin
      JO := TJSONObject.Create;
      JImpls.AddElement(JO);
      JO.AddPair('impl', B.ImplName);
      JO.AddPair('lifetime', B.Lifetime);
      JO.AddPair('file', AStore.GetFilePath(B.FileId));
      JO.AddPair('line', TJSONNumber.Create(B.StartLine));
    end;
    for R in Sites do
    begin
      JO := TJSONObject.Create;
      JSites.AddElement(JO);
      JO.AddPair('file', AStore.GetFilePath(R.FileId));
      JO.AddPair('line', TJSONNumber.Create(R.StartLine));
    end;
    for R in Handlers do
    begin
      JO := TJSONObject.Create;
      JHandlers.AddElement(JO);
      JO.AddPair('handler', R.NameText);
      JO.AddPair('file', AStore.GetFilePath(R.FileId));
      JO.AddPair('line', TJSONNumber.Create(R.StartLine));
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
