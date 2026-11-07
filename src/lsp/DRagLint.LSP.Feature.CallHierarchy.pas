unit DRagLint.LSP.Feature.CallHierarchy;

{ `textDocument/prepareCallHierarchy`, `callHierarchy/incomingCalls` and
  `callHierarchy/outgoingCalls` -- the editor's "Show Call Hierarchy" tree.

  prepare   -- the routine under the cursor (ILspServerContext.ResolveSymbolAt,
               the hover resolution); a position that is not on a routine, or
               that resolves to nothing, answers null.
  incoming  -- the RESOLVED callers (ISymbolStore.FindResolvedCallers, the
               find-callers --resolved facts), one item per calling routine with
               every call site as a fromRange. Property/field reads and the
               unresolved name-bucket callers are not calls and are left out.
  outgoing  -- the resolved callees (ISymbolStore.GetCallEdgesFromSymbol), one
               item per called routine with the call sites as fromRanges. A call
               the index did not resolve (RTL, cross-DB, unknown) is left out:
               a missing edge is honest, a guessed one is not.

  An item carries its symbol id and file in `data` (DRagLint.LSP.HierarchyUtil),
  so the follow-up requests need no position. Registered through the S0 feature
  registry. No extractor change. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers the three call-hierarchy methods and advertises
  /// callHierarchyProvider.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines and
  /// characters in replies are 0-based.</remarks>
  TLspCallHierarchyFeature = class(TLspFeature)
  public
    /// <summary>The three methods this feature answers.</summary>
    /// <returns>prepareCallHierarchy, incomingCalls, outgoingCalls.</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `callHierarchyProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>prepare: a CallHierarchyItem[] with one item, or null. incoming /
    /// outgoing: CallHierarchyIncomingCall[] / CallHierarchyOutgoingCall[], [] when
    /// the item no longer resolves or nothing is called.</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">One of the three methods.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">prepare: textDocument + position; the others: {item}.</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.LSP.HierarchyUtil
  ;

const
  PREPARE_METHOD  = 'textDocument/prepareCallHierarchy';
  INCOMING_METHOD = 'callHierarchy/incomingCalls';
  OUTGOING_METHOD = 'callHierarchy/outgoingCalls';

  ROUTINE_KINDS = [skProcedure, skFunction, skMethod, skConstructor, skDestructor];

type
  // One call-hierarchy node being assembled: the far-end symbol and the sites that reach it.
  TCallNode = class
  public
    Sym   : TSymbol;  // dl:ok public-field@a8d7 -- REVIEWED 2026-11-06: a node class private to this implementation section, no surface to encapsulate
    Ranges: TJSONArray;  // dl:ok public-field@7d5d -- REVIEWED 2026-11-06: a node class private to this implementation section, no surface to encapsulate
    constructor Create(const ASym: TSymbol);
    destructor Destroy; override;
  end;

constructor TCallNode.Create(const ASym: TSymbol);
begin
  inherited Create;
  Sym:= ASym;
  Ranges:= TJSONArray.Create;
end;

destructor TCallNode.Destroy;
begin
  Ranges.Free;
  inherited Destroy;
end;

procedure AddSite(const ANode: TCallNode; ALine1, ACol1, ALen: Integer);
begin
  if (ALine1 < 1) or (ACol1 < 1) then Exit;
  ANode.Ranges.AddElement(HierRange(ALine1 - 1, ACol1 - 1, ALine1 - 1, ACol1 - 1 + ALen));
end;

// Emits one {<AKey>: item, fromRanges: [...]} per node, ordered as the nodes were first seen.
function NodesToJson(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ANodes: TObjectList<TCallNode>; const AKey: string): TJSONArray;
begin
  Result:= TJSONArray.Create;
  try
    for var N: TCallNode in ANodes do
    begin
      if N.Ranges.Count = 0 then Continue;
      var Item: TJSONObject:= BuildHierarchyItem(ACtx, AStore, N.Sym);
      if Item = nil then Continue;
      var Obj: TJSONObject:= TJSONObject.Create;
      Result.AddElement(Obj);
      Obj.AddPair(AKey, Item);
      Obj.AddPair('fromRanges', N.Ranges.Clone as TJSONArray);
    end;
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function NodeFor(const ANodes: TObjectList<TCallNode>; const AIndex: TDictionary<Int64, TCallNode>; const ASym: TSymbol): TCallNode;
begin
  if not AIndex.TryGetValue(ASym.Id, Result) then
  begin
    Result:= TCallNode.Create(ASym);
    ANodes.Add(Result);
    AIndex.Add(ASym.Id, Result);
  end;
end;

function Incoming(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): TJSONArray;
begin
  var Nodes: TObjectList<TCallNode>:= TObjectList<TCallNode>.Create(True);
  var Index: TDictionary<Int64, TCallNode>:= TDictionary<Int64, TCallNode>.Create;
  try
    for var C: TResolvedCaller in AStore.FindResolvedCallers(ASym.Id) do
    begin
      if (C.Mode <> '') or (C.EnclosingSymbolId <= 0) then Continue; // a property/field access is not a call
      var Caller: TSymbol:= AStore.GetSymbolById(C.EnclosingSymbolId);
      if (Caller.Id = 0) or (Caller.Kind not in ROUTINE_KINDS) then Continue;
      AddSite(NodeFor(Nodes, Index, Caller), C.CallSiteLine, C.CallSiteCol, Length(ASym.Name));
    end;
    Result:= NodesToJson(ACtx, AStore, Nodes, 'from');
  finally
    Index.Free;
    Nodes.Free;
  end;
end;

function Outgoing(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): TJSONArray;
begin
  var Nodes: TObjectList<TCallNode>:= TObjectList<TCallNode>.Create(True);
  var Index: TDictionary<Int64, TCallNode>:= TDictionary<Int64, TCallNode>.Create;
  var Refs : TDictionary<Int64, TReference>:= TDictionary<Int64, TReference>.Create;
  try
    var Edges: TArray<TCallEdge>:= AStore.GetCallEdgesFromSymbol(ASym.Id);
    if Length(Edges) > 0 then
      for var R: TReference in AStore.GetReferencesFromFile(ASym.FileId) do Refs.AddOrSetValue(R.Id, R);
    for var E: TCallEdge in Edges do
    begin
      var Ref: TReference;
      if (E.TargetSymbolId <= 0) or not Refs.TryGetValue(E.RefId, Ref) then Continue;
      var Callee: TSymbol:= AStore.GetSymbolById(E.TargetSymbolId);
      if (Callee.Id = 0) or (Callee.Kind not in ROUTINE_KINDS) then Continue;
      var Node: TCallNode:= NodeFor(Nodes, Index, Callee);
      if (Ref.EndLine = Ref.StartLine) and (Ref.EndCol > Ref.StartCol) then AddSite(Node, Ref.StartLine, Ref.StartCol, Ref.EndCol - Ref.StartCol)
      else AddSite(Node, Ref.StartLine, Ref.StartCol, Length(Callee.Name));
    end;
    Result:= NodesToJson(ACtx, AStore, Nodes, 'to');
  finally
    Refs.Free;
    Index.Free;
    Nodes.Free;
  end;
end;

function Prepare(const ACtx: ILspServerContext; const AParams: TJSONObject): TJSONValue;
begin
  Result:= TJSONNull.Create;
  var Doc: TJSONObject:= nil;
  var PosObj: TJSONObject:= nil;
  if AParams <> nil then
  begin
    Doc:= AParams.GetValue('textDocument') as TJSONObject;
    PosObj:= AParams.GetValue('position') as TJSONObject;
  end;
  var Path: string:= '';
  if (Doc <> nil) and (Doc.GetValue('uri') <> nil) then Path:= ACtx.FileFromUri(Doc.GetValue('uri').Value);
  var Line0, Col0: Integer;
  var Sym  : TSymbol;
  var Store: ISymbolStore;
  if (Path = '') or not HierIntField(PosObj, 'line', Line0) or not HierIntField(PosObj, 'character', Col0)
     or not ACtx.ResolveSymbolAt(Path, Line0, Col0, Sym, Store) or (Sym.Kind not in ROUTINE_KINDS) then Exit;
  var Item: TJSONObject:= BuildHierarchyItem(ACtx, Store, Sym);
  if Item = nil then Exit;
  Result.Free;
  Result:= TJSONArray.Create;
  (Result as TJSONArray).AddElement(Item);
end;

class function TLspCallHierarchyFeature.Methods: TArray<string>;
begin
  Result:= [PREPARE_METHOD, INCOMING_METHOD, OUTGOING_METHOD];
end;

class procedure TLspCallHierarchyFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('callHierarchyProvider', TJSONBool.Create(True));
end;

procedure TLspCallHierarchyFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONValue:= nil;
  try
    if AMethod = PREPARE_METHOD then Res:= Prepare(ACtx, AParams)
    else
    begin
      var Sym  : TSymbol;
      var Store: ISymbolStore;
      var Item : TJSONObject:= nil;
      if AParams <> nil then Item:= AParams.GetValue('item') as TJSONObject;
      if not FindItemSymbol(ACtx, Item, Sym, Store) then Res:= TJSONArray.Create  // dl:ok ifthen-to-if-expression@e74c -- REVIEWED 2026-11-06: three outcomes, not two: the first arm is a guard, so one if-expression cannot replace the chain without nesting
      else Res:= if AMethod = INCOMING_METHOD then Incoming(ACtx, Store, Sym) else Outgoing(ACtx, Store, Sym);
    end;
  except
    on Exception do
    begin
      Res.Free;
      raise;
    end;
  end;
  ACtx.Reply(AId, Res);
end;

initialization
  RegisterLspFeature(TLspCallHierarchyFeature);

end.
