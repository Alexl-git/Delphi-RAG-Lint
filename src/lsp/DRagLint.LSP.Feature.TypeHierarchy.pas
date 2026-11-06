unit DRagLint.LSP.Feature.TypeHierarchy;

{ `textDocument/prepareTypeHierarchy`, `typeHierarchy/supertypes` and
  `typeHierarchy/subtypes` -- the editor's "Show Type Hierarchy".

  prepare    -- the class, interface or record under the cursor
                (ILspServerContext.ResolveSymbolAt); anything else answers null.
  supertypes -- the DIRECT ancestors named in the heritage list that the index
                resolved to a type (type_ancestors); an ancestor outside the
                index (TObject, an RTL class) or one the resolver could not link
                is left out, never guessed.
  subtypes   -- the types whose heritage list names this one and whose resolved
                ancestor edge lands on THIS symbol (a homonym in another unit is
                not a subtype). Types in another index are not searched.

  An item carries its symbol id and file in `data` (DRagLint.LSP.HierarchyUtil).
  Registered through the S0 feature registry. No extractor change. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers the three type-hierarchy methods and advertises
  /// typeHierarchyProvider.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines and
  /// characters in replies are 0-based.</remarks>
  TLspTypeHierarchyFeature = class(TLspFeature)
  public
    /// <summary>The three methods this feature answers.</summary>
    /// <returns>prepareTypeHierarchy, supertypes, subtypes.</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `typeHierarchyProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>prepare: a TypeHierarchyItem[] with one item, or null. supertypes /
    /// subtypes: TypeHierarchyItem[], [] when the item no longer resolves or has none.</summary>
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
  PREPARE_METHOD = 'textDocument/prepareTypeHierarchy';
  SUPER_METHOD   = 'typeHierarchy/supertypes';
  SUB_METHOD     = 'typeHierarchy/subtypes';

  TYPE_KINDS = [skClass, skInterface, skRecord];

// Leaf name of one heritage entry: `System.Generics.TList<T>` -> `TList`.
function HeritageLeaf(const AEntry: string): string;
begin
  Result:= Trim(AEntry);
  var Lt: Integer:= Pos('<', Result);
  if Lt > 0 then Result:= Trim(Copy(Result, 1, Lt - 1));
  var Dot: Integer:= LastDelimiter('.', Result);
  if Dot > 0 then Result:= Copy(Result, Dot + 1, MaxInt);
end;

// The leaf names of a heritage list `TBar, IBaz<T, U>`, commas inside <> not splitting.
function HeritageLeaves(const AHeritage: string): TArray<string>;
begin
  var List: TList<string>:= TList<string>.Create;
  try
    var Depth: Integer:= 0;
    var Start: Integer:= 1;
    for var I: Integer:= 1 to Length(AHeritage) + 1 do
    begin
      var C: Char:= if I <= Length(AHeritage) then AHeritage[I] else ',';
      if C = '<' then Inc(Depth)
      else if (C = '>') and (Depth > 0) then Dec(Depth)
      else if (C = ',') and (Depth = 0) then
      begin
        var Leaf: string:= HeritageLeaf(Copy(AHeritage, Start, I - Start));
        if Leaf <> '' then List.Add(Leaf);
        Start:= I + 1;
      end;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

procedure AddItem(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol; const AArr: TJSONArray; const ASeen: TDictionary<Int64, Boolean>);
begin
  if ASeen.ContainsKey(ASym.Id) then Exit;
  ASeen.Add(ASym.Id, True);
  var Item: TJSONObject:= BuildHierarchyItem(ACtx, AStore, ASym);
  if Item <> nil then AArr.AddElement(Item);
end;

function Supertypes(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): TJSONArray;
begin
  Result:= TJSONArray.Create;
  var Seen: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  try
    try
      var Anc: TArray<TTypeAncestor>:= AStore.GetTransitiveAncestors(ASym.Id);
      for var Leaf: string in HeritageLeaves(ASym.Heritage) do
        for var A: TTypeAncestor in Anc do
        begin
          if not A.Resolved or (A.SymbolId <= 0) or not (SameText(A.Name, Leaf) or SameText(HeritageLeaf(A.Name), Leaf)) then Continue;
          var T: TSymbol:= AStore.GetSymbolById(A.SymbolId);
          if (T.Id = A.SymbolId) and (T.Kind in TYPE_KINDS) then AddItem(ACtx, AStore, T, Result, Seen);
          Break;
        end;
    except
      on Exception do
      begin
        Result.Free;
        raise;
      end;
    end;
  finally
    Seen.Free;
  end;
end;

// True when T's resolved ancestor edges include ASym itself and its heritage list names ASym directly.
function IsDirectSubtype(const AStore: ISymbolStore; const ASym, ACand: TSymbol): Boolean;
begin
  Result:= False;
  var Named: Boolean:= False;
  for var Leaf: string in HeritageLeaves(ACand.Heritage) do
    if SameText(Leaf, ASym.Name) then Named:= True;
  if not Named then Exit;
  for var A: TTypeAncestor in AStore.GetTransitiveAncestors(ACand.Id) do
    if A.Resolved and (A.SymbolId = ASym.Id) then Exit(True);
end;

function Subtypes(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): TJSONArray;
begin
  Result:= TJSONArray.Create;
  var Seen: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  try
    try
      for var DName: string in AStore.FindDescendantNames(ASym.Name) do
      begin
        var Cands: TArray<TSymbol>;
        if DName.Contains('.') then Cands:= AStore.FindSymbolsByQualifiedName(DName)
        else Cands:= AStore.FindSymbolsByExactName(DName);
        for var T: TSymbol in Cands do
          if (T.Kind in TYPE_KINDS) and (T.Id <> ASym.Id) and IsDirectSubtype(AStore, ASym, T) then AddItem(ACtx, AStore, T, Result, Seen);
      end;
    except
      on Exception do
      begin
        Result.Free;
        raise;
      end;
    end;
  finally
    Seen.Free;
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
     or not ACtx.ResolveSymbolAt(Path, Line0, Col0, Sym, Store) or not (Sym.Kind in TYPE_KINDS) then Exit;
  var Item: TJSONObject:= BuildHierarchyItem(ACtx, Store, Sym);
  if Item = nil then Exit;
  Result.Free;
  Result:= TJSONArray.Create;
  (Result as TJSONArray).AddElement(Item);
end;

class function TLspTypeHierarchyFeature.Methods: TArray<string>;
begin
  Result:= [PREPARE_METHOD, SUPER_METHOD, SUB_METHOD];
end;

class procedure TLspTypeHierarchyFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('typeHierarchyProvider', TJSONBool.Create(True));
end;

procedure TLspTypeHierarchyFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
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
      if not FindItemSymbol(ACtx, Item, Sym, Store) or not (Sym.Kind in TYPE_KINDS) then Res:= TJSONArray.Create
      else if AMethod = SUPER_METHOD then Res:= Supertypes(ACtx, Store, Sym)
      else Res:= Subtypes(ACtx, Store, Sym);
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
  RegisterLspFeature(TLspTypeHierarchyFeature);

end.
