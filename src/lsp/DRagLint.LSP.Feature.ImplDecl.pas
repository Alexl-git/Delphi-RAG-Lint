unit DRagLint.LSP.Feature.ImplDecl;

{ `textDocument/implementation` and `textDocument/declaration`, both starting
  from ILspServerContext.ResolveSymbolAt (the hover resolution).

  declaration    -- one Location at the symbol's interface-section declaration
                    (its ForwardLine when a forward declaration was folded in).
  implementation -- the routine's own body (ImplStartLine) plus, for a method,
                    the same-named method of every descendant of the owner type.

  Both answer [] when nothing resolves; neither raises an error for a position
  on whitespace. Registered through the S0 feature registry exactly as
  DRagLint.LSP.Feature.CodeLens is. No extractor change: every field read is
  already on TSymbol. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/implementation` and
  /// `textDocument/declaration` and advertises implementationProvider and
  /// declarationProvider.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines
  /// and characters in the replies are 0-based.</remarks>
  TLspImplDeclFeature = class(TLspFeature)
  public
    /// <summary>The two methods this feature answers.</summary>
    /// <returns>['textDocument/implementation', 'textDocument/declaration'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `implementationProvider: true` and
    /// `declarationProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies a Location[]. declaration: the resolved symbol's
    /// declaration (ForwardLine when &gt; 0, else StartLine/StartCol).
    /// implementation: a routine's ImplStartLine at character 0, and for a
    /// method also each descendant's same-named method (its ImplStartLine, or
    /// StartLine when it has no body). The list is ordered by uri then line
    /// and has no duplicates. Nothing resolving answers [].</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">One of the two methods.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{textDocument:{uri}, position:{line, character}}; a missing field answers [].</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  IMPL_METHOD = 'textDocument/implementation';
  DECL_METHOD = 'textDocument/declaration';

type
  TLoc = record
    Uri : string;
    Line: Integer; // 0-based
    Col : Integer; // 0-based
  end;

function IntField(const AObj: TJSONObject; const AName: string; out AValue: Integer): Boolean;
begin
  var V: TJSONValue:= nil;
  if AObj <> nil then V:= AObj.GetValue(AName);
  Result:= V is TJSONNumber;
  if Result then AValue:= (V as TJSONNumber).AsInt else AValue:= 0;
end;

function SymbolUri(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): string;
begin
  Result:= '';
  if AStore <> nil then Result:= ACtx.FileToUri(AStore.GetFilePath(ASym.FileId));
end;

function LocJson(const ALoc: TLoc): TJSONObject;
begin
  Result:= TJSONObject.Create;
  try
    Result.AddPair('uri', ALoc.Uri);
    var Rng: TJSONObject:= TJSONObject.Create;
    Result.AddPair('range', Rng);
    for var Key: string in ['start', 'end'] do
    begin
      var P: TJSONObject:= TJSONObject.Create;
      Rng.AddPair(Key, P);
      P.AddPair('line'     , TJSONNumber.Create(ALoc.Line));
      P.AddPair('character', TJSONNumber.Create(ALoc.Col));
    end;
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

procedure AddLoc(const ALocs: TList<TLoc>; const AUri: string; ALine, ACol: Integer);
begin
  if (AUri = '') or (ALine < 0) then Exit;
  var L: TLoc;
  L.Uri := AUri;
  L.Line:= ALine;
  L.Col := ACol;
  ALocs.Add(L);
end;

function IsTypeKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skClass, skInterface, skRecord];
end;

// Every descendant's same-named method, across the configured stores plus the store that resolved the symbol.
procedure AddDescendantMethods(const ACtx: ILspServerContext; const AHitStore: ISymbolStore; const ASym: TSymbol; const ALocs: TList<TLoc>);
begin
  var Owner: TSymbol:= AHitStore.GetSymbolById(ASym.ParentId);
  if (Owner.Id = 0) or (Owner.Name = '') then Exit;
  var Stores: TArray<ISymbolStore>:= ACtx.Stores;
  var Seen: Boolean:= False;
  for var S: ISymbolStore in Stores do
    if S = AHitStore then Seen:= True;
  if not Seen then Stores:= Stores + [AHitStore];
  for var S: ISymbolStore in Stores do
    for var DName: string in S.FindDescendantNames(Owner.Name) do
    begin
      var Types: TArray<TSymbol>;
      if DName.Contains('.') then Types:= S.FindSymbolsByQualifiedName(DName)
      else Types:= S.FindSymbolsByExactName(DName);
      for var T: TSymbol in Types do
      begin
        if not IsTypeKind(T.Kind) then Continue;
        var M: TSymbol:= S.FindChildSymbolByName(T.Id, ASym.Name);
        if (M.Id = 0) or (M.Id = ASym.Id) then Continue;
        // A descendant without a body (abstract re-declaration) still has a declaration worth jumping to.
        var Line1: Integer:= M.ImplStartLine;
        var Col0 : Integer:= 0;
        if Line1 <= 0 then
        begin
          Line1:= M.StartLine;
          Col0 := M.StartCol - 1;
        end;
        AddLoc(ALocs, SymbolUri(ACtx, S, M), Line1 - 1, Col0);
      end;
    end;
end;

procedure CollectImplementations(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol; const ALocs: TList<TLoc>);
begin
  if not (ASym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) then Exit;
  if ASym.ImplStartLine > 0 then AddLoc(ALocs, SymbolUri(ACtx, AStore, ASym), ASym.ImplStartLine - 1, 0);
  if (ASym.Kind in [skMethod, skConstructor, skDestructor]) and (ASym.ParentId > 0) then
    AddDescendantMethods(ACtx, AStore, ASym, ALocs);
end;

procedure SortAndDedupe(const ALocs: TList<TLoc>);
begin
  ALocs.Sort(TComparer<TLoc>.Construct(
    function(const A, B: TLoc): Integer
    begin
      Result:= CompareStr(A.Uri, B.Uri);
      if Result = 0 then Result:= A.Line - B.Line;
    end));
  for var I: Integer:= ALocs.Count - 1 downto 1 do
    if (ALocs[I].Uri = ALocs[I - 1].Uri) and (ALocs[I].Line = ALocs[I - 1].Line) then ALocs.Delete(I);
end;

class function TLspImplDeclFeature.Methods: TArray<string>;
begin
  Result:= [IMPL_METHOD, DECL_METHOD];
end;

class procedure TLspImplDeclFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('implementationProvider', TJSONBool.Create(True));
  ACaps.AddPair('declarationProvider'   , TJSONBool.Create(True));
end;

procedure TLspImplDeclFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONArray:= TJSONArray.Create;
  try
    var Uri: string:= '';
    var Doc: TJSONObject:= nil;
    var PosObj: TJSONObject:= nil;
    if AParams <> nil then
    begin
      Doc:= AParams.GetValue('textDocument') as TJSONObject;
      PosObj:= AParams.GetValue('position') as TJSONObject;
    end;
    if (Doc <> nil) and (Doc.GetValue('uri') <> nil) then Uri:= Doc.GetValue('uri').Value;
    var Line0, Col0: Integer;
    var Path: string:= '';
    if Uri <> '' then Path:= ACtx.FileFromUri(Uri);
    var Sym  : TSymbol;
    var Store: ISymbolStore;
    if (Path <> '') and IntField(PosObj, 'line', Line0) and IntField(PosObj, 'character', Col0)
       and ACtx.ResolveSymbolAt(Path, Line0, Col0, Sym, Store) then
    begin
      var Locs: TList<TLoc>:= TList<TLoc>.Create;
      try
        if AMethod = DECL_METHOD then
        begin
          if Sym.ForwardLine > 0 then AddLoc(Locs, SymbolUri(ACtx, Store, Sym), Sym.ForwardLine - 1, 0)
          else AddLoc(Locs, SymbolUri(ACtx, Store, Sym), Sym.StartLine - 1, Sym.StartCol - 1);
        end
        else CollectImplementations(ACtx, Store, Sym, Locs);
        SortAndDedupe(Locs);
        for var L: TLoc in Locs do Res.AddElement(LocJson(L));
      finally
        Locs.Free;
      end;
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
  RegisterLspFeature(TLspImplDeclFeature);

end.
