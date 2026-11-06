unit DRagLint.LSP.Feature.TypeDefinition;

{ `textDocument/typeDefinition` -- "go to the declaration of the TYPE of the
  thing under the cursor".

  Resolution, most certain first:
    1. the symbol under the cursor is itself a type -> that type;
    2. the static type the index recorded for this reference (ref_types, index
       fact F1; DRagLint.Lint.RefTypeRules.RefStaticTypeAt);
    3. the type the symbol was DECLARED with (the text after the last colon of
       its signature: a variable, field, parameter, property, or a function's
       result).
  The type name is then looked up in the index. A name that matches exactly one
  class / interface / record / enum / alias answers that Location; no match, or
  two homonyms that cannot be told apart, answers [] -- a miss, never a wrong
  place. An index with no ref_types table skips step 2 and behaves as steps 1
  and 3 only. A file the index does not hold answers [].

  Registered through the S0 feature registry. No extractor change. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/typeDefinition` and advertises
  /// typeDefinitionProvider.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines and
  /// characters in the reply are 0-based.</remarks>
  TLspTypeDefinitionFeature = class(TLspFeature)
  public
    /// <summary>The method this feature answers.</summary>
    /// <returns>['textDocument/typeDefinition'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `typeDefinitionProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies a Location[]: the declaration of the type, or [].</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">textDocument/typeDefinition.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">textDocument + position; a missing field answers [].</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Core.LiveDocs
  , DRagLint.Lint.RefTypeRules
  , DRagLint.LSP.HierarchyUtil
  ;

const
  TYPEDEF_METHOD = 'textDocument/typeDefinition';
  TYPE_KINDS = [skClass, skInterface, skRecord, skEnum, skTypeAlias];

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// 1-based column where the identifier under the 0-based cursor starts; 0 when the cursor is on no identifier.
function IdentStartCol1(const APath: string; ALine0, ACol0: Integer): Integer;
begin
  Result:= 0;
  var Lines: TArray<string>;
  try Lines:= TLiveDocuments.ReadLines(APath); except on Exception do Exit; end;
  if (ALine0 < 0) or (ALine0 >= Length(Lines)) then Exit;
  var L: string:= Lines[ALine0];
  var I: Integer:= ACol0 + 1;
  if (I < 1) or (I > Length(L)) or not IsIdentChar(L[I]) then Exit;
  while (I > 1) and IsIdentChar(L[I - 1]) do Dec(I);
  Result:= I;
end;

// The bare type name a symbol was declared with: after the last colon of its signature, or the whole text for a variable-like symbol; '' when none.
function DeclaredTypeLeaf(const ASym: TSymbol): string;
begin
  Result:= '';
  var P: Integer:= LastDelimiter(':', ASym.Signature);
  if (P = 0) and not (ASym.Kind in [skField, skVarDecl, skConstDecl, skParam, skLocalVar, skProperty]) then Exit; // a variable-like signature is the bare type text
  var S: string:= Trim(Copy(ASym.Signature, P + 1, MaxInt));
  var E: Integer:= 1;
  while (E <= Length(S)) and (IsIdentChar(S[E]) or (S[E] = '.')) do Inc(E);
  S:= Copy(S, 1, E - 1);
  var Dot: Integer:= LastDelimiter('.', S);
  if Dot > 0 then S:= Copy(S, Dot + 1, MaxInt);
  Result:= S;
end;

// The one type symbol named ALeaf across the stores (AHit first); a homonym that is not alone is no answer.
function UniqueType(const ACtx: ILspServerContext; const AHit: ISymbolStore; const ALeaf: string; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
begin
  Result:= False;
  if ALeaf = '' then Exit;
  var Stores: TArray<ISymbolStore>:= [AHit] + ACtx.Stores;
  var Found: Integer:= 0;
  for var S: ISymbolStore in Stores do
  begin
    if S = nil then Continue;
    for var T: TSymbol in S.FindSymbolsByExactName(ALeaf) do
      if T.Kind in TYPE_KINDS then
      begin
        Inc(Found);
        ASym  := T;
        AStore:= S;
      end;
    if Found > 0 then Break; // the nearest store that knows the name decides
  end;
  Result:= Found = 1;
end;

function LocationOf(const ACtx: ILspServerContext; const AStore: ISymbolStore; const ASym: TSymbol): TJSONObject;
begin
  Result:= nil;
  var Item: TJSONObject:= BuildHierarchyItem(ACtx, AStore, ASym);
  if Item = nil then Exit;
  try
    Result:= TJSONObject.Create;
    Result.AddPair('uri', Item.GetValue('uri').Value);
    Result.AddPair('range', Item.GetValue('selectionRange').Clone as TJSONObject);
  finally
    Item.Free;
  end;
end;

class function TLspTypeDefinitionFeature.Methods: TArray<string>;
begin
  Result:= [TYPEDEF_METHOD];
end;

class procedure TLspTypeDefinitionFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('typeDefinitionProvider', TJSONBool.Create(True));
end;

procedure TLspTypeDefinitionFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONArray:= TJSONArray.Create;
  try
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
    if (Path <> '') and HierIntField(PosObj, 'line', Line0) and HierIntField(PosObj, 'character', Col0)
       and ACtx.ResolveSymbolAt(Path, Line0, Col0, Sym, Store) then
    begin
      var Target: TSymbol;
      var TStore: ISymbolStore:= nil;
      var Found : Boolean;
      if Sym.Kind in TYPE_KINDS then
      begin
        Target:= Sym;
        TStore:= Store;
        Found := True;
      end
      else
      begin
        var Leaf: string:= '';
        var Col1: Integer:= IdentStartCol1(Path, Line0, Col0);
        var FileId: Int64:= 0;
        for var S: ISymbolStore in ACtx.StoresForFile(Path) do
          if FileId = 0 then FileId:= S.FindFileIdByPath(Path);
        if (Col1 > 0) and (FileId > 0) then
          for var S: ISymbolStore in ACtx.StoresForFile(Path) do
            if (Leaf = '') and (S.FindFileIdByPath(Path) = FileId) then RefStaticTypeAt(S, FileId, Line0 + 1, Col1, Sym.Name, Leaf);
        if Leaf = '' then Leaf:= DeclaredTypeLeaf(Sym);
        Found:= UniqueType(ACtx, Store, Leaf, Target, TStore);
      end;
      if Found then
      begin
        var Loc: TJSONObject:= LocationOf(ACtx, TStore, Target);
        if Loc <> nil then Res.AddElement(Loc);
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
  RegisterLspFeature(TLspTypeDefinitionFeature);

end.
