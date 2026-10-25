unit DRagLint.LSP.Feature.DocumentSymbol;

{ `textDocument/documentSymbol` -- the editor's outline / breadcrumb / "go to
  symbol in file" list, answered from the index as a hierarchical
  DocumentSymbol[] (TSymbol.ParentId gives the nesting). Registered through the
  S0 feature registry exactly as DRagLint.LSP.Feature.Ping is. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/documentSymbol` with a DocumentSymbol[]
  /// tree and advertises documentSymbolProvider = true.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines and
  /// columns on the wire are 0-based; the store's are 1-based.</remarks>
  TLspDocumentSymbolFeature = class(TLspFeature)
  public
    /// <summary>The one method: `textDocument/documentSymbol`.</summary>
    /// <returns>['textDocument/documentSymbol'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `documentSymbolProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies the document's symbols as a tree: the unit's members
    /// at the top level (the unit symbol itself is not a root), members under
    /// their type, sorted by source position. Local variables, parameters and
    /// anything declared inside a routine are left out. A file no store knows
    /// answers [].</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">Always `textDocument/documentSymbol`.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{textDocument:{uri}}; a missing uri answers [].</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , System.IOUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Core.LiveDocs
  ;

const
  DOCSYM_METHOD = 'textDocument/documentSymbol';

  // LSP SymbolKind numbers (3.17).
  LSP_MODULE      = 2;
  LSP_CLASS       = 5;
  LSP_METHOD      = 6;
  LSP_PROPERTY    = 7;
  LSP_FIELD       = 8;
  LSP_CONSTRUCTOR = 9;
  LSP_ENUM        = 10;
  LSP_INTERFACE   = 11;
  LSP_FUNCTION    = 12;
  LSP_VARIABLE    = 13;
  LSP_CONSTANT    = 14;
  LSP_ENUMMEMBER  = 22;
  LSP_STRUCT      = 23;

  ROUTINE_KINDS = [skProcedure, skFunction, skMethod, skConstructor, skDestructor];

type
  TSymList = TList<TSymbol>;

function LspKind(AKind: TSymbolKind): Integer;
begin
  case AKind of
    skUnit, skProgram, skPackage            : Result:= LSP_MODULE;
    skMethod                                : Result:= LSP_METHOD;
    skConstructor, skDestructor             : Result:= LSP_CONSTRUCTOR;
    skProperty                              : Result:= LSP_PROPERTY;
    skField, skSqlColumn                    : Result:= LSP_FIELD;
    skEnum                                  : Result:= LSP_ENUM;
    skEnumValue                             : Result:= LSP_ENUMMEMBER;
    skInterface                             : Result:= LSP_INTERFACE;
    skProcedure, skFunction, skSqlProcedure : Result:= LSP_FUNCTION;
    skVarDecl                               : Result:= LSP_VARIABLE;
    skConstDecl                             : Result:= LSP_CONSTANT;
    skRecord                                : Result:= LSP_STRUCT;
  else
    Result:= LSP_CLASS; // class, type alias, form, component, SQL tables/views/...
  end;
end;

function Position(ALine0, ACol0: Integer): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('line'     , TJSONNumber.Create(ALine0));
  Result.AddPair('character', TJSONNumber.Create(ACol0 ));
end;

function Range(ASLine, ASCol, AELine, AECol: Integer): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('start', Position(ASLine, ASCol));
  Result.AddPair('end'  , Position(AELine, AECol));
end;

function Wanted(const ASym: TSymbol): Boolean;
begin
  Result:= (ASym.Name <> '') and (ASym.StartLine > 0)
    and not (ASym.Kind in [skLocalVar, skParam, skUnit, skProgram, skPackage, skInitialization, skFinalization]);
end;

/// Zero-based column of the whole-word, case-insensitive ASym.Name on its
/// declaration line, searching from the symbol's start; the start column
/// itself when the text is unavailable or the name is not found (the store's
/// start column is the declaration KEYWORD for routines, properties and
/// fields, not the name).
function NameColumn(const ASym: TSymbol; const ALines: TArray<string>): Integer;
begin
  Result:= ASym.StartCol - 1;
  if (ASym.StartLine < 1) or (ASym.StartLine > Length(ALines)) or (ASym.Name = '') then Exit;
  var Line: string:= ALines[ASym.StartLine - 1];
  var From: Integer:= Result + 1;
  if From < 1 then From:= 1;
  while True do
  begin
    var P: Integer:= Pos(LowerCase(ASym.Name), LowerCase(Line), From);
    if P = 0 then Exit;
    var After: Integer:= P + Length(ASym.Name);
    var BeforeOk: Boolean:= (P = 1) or not CharInSet(Line[P - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
    var AfterOk : Boolean:= (After > Length(Line)) or not CharInSet(Line[After], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
    if BeforeOk and AfterOk then
    begin
      Result:= P - 1;
      Exit;
    end;
    From:= P + 1;
  end;
end;

function BuildNode(const ASym: TSymbol; const AKids: TDictionary<Int64, TSymList>; const ALines: TArray<string>): TJSONObject;
begin
  Result:= TJSONObject.Create;
  try
    var SLine: Integer:= ASym.StartLine - 1;
    var SCol : Integer:= ASym.StartCol  - 1;
    var ELine: Integer:= ASym.EndLine   - 1;
    var ECol : Integer:= ASym.EndCol    - 1;
    var NCol : Integer:= NameColumn(ASym, ALines);
    // range must contain selectionRange (LSP): the end is clamped against the
    // NAME token's end (NCol + Length), not the declaration keyword's start.
    if (ELine < SLine) or ((ELine = SLine) and (ECol < NCol + Length(ASym.Name))) then
    begin
      ELine:= SLine;
      ECol := NCol + Length(ASym.Name);
    end;
    Result.AddPair('name', ASym.Name);
    Result.AddPair('kind', TJSONNumber.Create(LspKind(ASym.Kind)));
    Result.AddPair('range', Range(SLine, SCol, ELine, ECol));
    Result.AddPair('selectionRange', Range(SLine, NCol, SLine, NCol + Length(ASym.Name)));
    var Kids: TSymList;
    if (ASym.Kind in ROUTINE_KINDS) or not AKids.TryGetValue(ASym.Id, Kids) then Exit;
    var Arr: TJSONArray:= TJSONArray.Create;
    Result.AddPair('children', Arr);
    for var K: TSymbol in Kids do Arr.AddElement(BuildNode(K, AKids, ALines));
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;
class function TLspDocumentSymbolFeature.Methods: TArray<string>;
begin
  Result:= [DOCSYM_METHOD];
end;

class procedure TLspDocumentSymbolFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('documentSymbolProvider', TJSONBool.Create(True));
end;

procedure TLspDocumentSymbolFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONArray:= TJSONArray.Create;
  var Path: string:= '';
  var Doc: TJSONObject:= nil;
  if AParams <> nil then Doc:= AParams.GetValue('textDocument') as TJSONObject;
  if (Doc <> nil) and (Doc.GetValue('uri') <> nil) then Path:= ACtx.FileFromUri(Doc.GetValue('uri').Value);
  var Stores: TArray<ISymbolStore>:= nil;
  if Path <> '' then Stores:= ACtx.StoresForFile(Path);
  if Length(Stores) > 0 then
  begin
    var Syms: TArray<TSymbol>:= Stores[0].FindSymbolsByFile(Path);
    var ById : TDictionary<Int64, TSymbol>:= TDictionary<Int64, TSymbol>.Create;
    var Kids : TDictionary<Int64, TSymList>:= TDictionary<Int64, TSymList>.Create;
    var Roots: TSymList:= TSymList.Create;
    var Lines: TArray<string>;
    try
      try Lines:= TLiveDocuments.ReadLines(Path); except on Exception do Lines:= nil; end; // an unreadable file only costs the name column; the start column is the fallback
      for var S: TSymbol in Syms do ById.AddOrSetValue(S.Id, S);
      // Only a symbol whose parent is a unit/absent, or a wanted non-routine
      // symbol, is shown: everything under a routine is a local.
      var Cmp: IComparer<TSymbol>:= TComparer<TSymbol>.Construct(
        function(const A, B: TSymbol): Integer
        begin
          Result:= A.StartLine - B.StartLine;
          if Result = 0 then Result:= A.StartCol - B.StartCol;
        end);
      TArray.Sort<TSymbol>(Syms, Cmp);
      for var S: TSymbol in Syms do
      begin
        if not Wanted(S) then Continue;
        var P: TSymbol;
        if (S.ParentId <= 0) or not ById.TryGetValue(S.ParentId, P) or (P.Kind in [skUnit, skProgram, skPackage]) then
          Roots.Add(S)
        else if Wanted(P) and not (P.Kind in ROUTINE_KINDS) then
        begin
          var L: TSymList;
          if not Kids.TryGetValue(P.Id, L) then
          begin
            L:= TSymList.Create;
            Kids.Add(P.Id, L);
          end;
          L.Add(S);
        end;
      end;
      try
        for var R: TSymbol in Roots do Res.AddElement(BuildNode(R, Kids, Lines));
      except
        on Exception do
        begin
          Res.Free;
          raise;
        end;
      end;
    finally
      for var L: TSymList in Kids.Values do L.Free;
      Kids .Free;
      ById .Free;
      Roots.Free;
    end;
  end;
  ACtx.Reply(AId, Res);
end;

initialization
  RegisterLspFeature(TLspDocumentSymbolFeature);

end.
