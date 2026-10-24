unit DRagLint.LSP.Feature.SemanticTokens;

{ `textDocument/semanticTokens/full` (B5, slice 1: no resolver) -- the editor's
  semantic colouring, answered as the LSP relative 5-tuple `data` array.

  Two sources, merged and sorted by (line, column):
    * SYNTACTIC classes from a tree-sitter parse of the live buffer (else the
      file on disk), read the way TLSPServer.IdentifierAtPosition reads it:
      keywords, comments, string literals, number literals.
    * DECLARATION names from the index (ISymbolStore.FindSymbolsByFile), each
      with the `declaration` modifier.
  A token that spans lines is split into one token per line (the LSP default,
  multilineTokenSupport is not assumed). Registered through the S0 feature
  registry exactly as DRagLint.LSP.Feature.DocumentSymbol is. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/semanticTokens/full` and advertises
  /// semanticTokensProvider with a fixed legend and full = true.</summary>
  /// <remarks>
  /// <para>Legend tokenTypes, in this exact order (clients decode by index):
  /// namespace, type, class, interface, enum, function, method, property,
  /// variable, parameter, keyword, comment, string, number, operator.
  /// tokenModifiers: declaration (bit 0).</para>
  /// <para>Stateless; registered from this unit's initialization. Columns are
  /// UTF-16 code units, lines 0-based.</para>
  /// </remarks>
  TLspSemanticTokensFeature = class(TLspFeature)
  public
    /// <summary>The one method: `textDocument/semanticTokens/full`.</summary>
    /// <returns>['textDocument/semanticTokens/full'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `semanticTokensProvider: {legend: {tokenTypes,
    /// tokenModifiers}, full: true}`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies {data: [...]}: keyword, comment, string and number
    /// tokens from the parse tree plus the index's declaration names
    /// (class, interface, enum, function, method, property, variable,
    /// parameter, type, namespace) with the declaration modifier; sorted,
    /// non-overlapping, multi-line tokens split per line, encoded as
    /// (deltaLine, deltaStart, length, tokenType, tokenModifiers).</summary>
    /// <param name="ACtx">The server surface; its store list is copied, never
    /// changed.</param>
    /// <param name="AMethod">Always `textDocument/semanticTokens/full`.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{textDocument:{uri}}; a missing uri or an
    /// unknown/unreadable file answers {data: []}.</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Core.Encoding
  , DRagLint.Core.LiveDocs
  , DRagLint.Parser.Delphi13
  ;

const
  SEMTOK_METHOD = 'textDocument/semanticTokens/full';

  // Legend indices -- FIXED: they are the positions in LEGEND_TYPES below.
  TT_NAMESPACE = 0;
  TT_TYPE      = 1;
  TT_CLASS     = 2;
  TT_INTERFACE = 3;
  TT_ENUM      = 4;
  TT_FUNCTION  = 5;
  TT_METHOD    = 6;
  TT_PROPERTY  = 7;
  TT_VARIABLE  = 8;
  TT_PARAMETER = 9;
  TT_KEYWORD   = 10;
  TT_COMMENT   = 11;
  TT_STRING    = 12;
  TT_NUMBER    = 13;
  TT_NONE      = -1;

  LEGEND_TYPES: array[0..14] of string = ('namespace', 'type', 'class', 'interface', 'enum', 'function', 'method', 'property', 'variable', 'parameter', 'keyword', 'comment', 'string', 'number', 'operator');
  MOD_DECLARATION = 1; // bit 0 = 'declaration'
  MOD_NONE        = 0;

  // tree-sitter-delphi13 node types, read by parsing the B5 guard's fixture
  // (tests\autotest\run_lsp_semantic_tokens_guard.ps1) with the bundled
  // grammar, 2026-10-23. Keywords are NAMED nodes `k<Word>` (kUnit, kClass,
  // kBegin...), not anonymous ones; `kAssign` / `kEq` are k-nodes whose text is
  // punctuation, which is why a keyword also needs alphabetic text. `#13'x'`
  // parses as a literalString holding literalChar children; a lone `#13` is a
  // literalChar. `//` and `{ }` comments are both `comment`.
  NT_COMMENT     = 'comment';
  NT_STRING      = 'literalString';
  NT_CHAR        = 'literalChar';
  NT_NUMBER      = 'literalNumber';
  KEYWORD_PREFIX = 'k';

  UTF8_CONT_MASK  = $C0; // a byte b with (b and $C0) = $80 continues a sequence
  UTF8_CONT_VALUE = $80;
  UTF8_FOUR_LEAD  = $F0; // a lead byte >= $F0 starts a 4-byte (surrogate-pair) code point
  BYTE_LF         = 10;

type
  TSemTok = record
    Line, Col, Len, TokType, Mods: Integer;
  end;

  /// Byte offset -> (0-based line, UTF-16 column) map of one UTF-8 buffer,
  /// plus each line's UTF-16 length without its CR/LF.
  TByteMap = record
    Lines: TArray<Integer>;
    Cols : TArray<Integer>;
    LineLen: TArray<Integer>;
    procedure Build(const ASource: TBytes);
  end;

procedure TByteMap.Build(const ASource: TBytes);
begin
  var N: Integer:= Length(ASource);
  SetLength(Lines, N + 1);
  SetLength(Cols , N + 1);
  SetLength(LineLen, N + 1); // at most one line per byte, plus the last; trimmed below
  var L: Integer:= 0;
  var C: Integer:= 0;
  for var I: Integer:= 0 to N - 1 do
  begin
    Lines[I]:= L;
    Cols [I]:= C;
    var B: Byte:= ASource[I];
    if B = BYTE_LF then
    begin
      var EndCol: Integer:= C;
      if (I > 0) and (ASource[I - 1] = Ord(#13)) then Dec(EndCol);
      LineLen[L]:= EndCol;
      Inc(L);
      C:= 0;
    end
    else if (B and UTF8_CONT_MASK) <> UTF8_CONT_VALUE then
      Inc(C, if B >= UTF8_FOUR_LEAD then 2 else 1);
  end;
  Lines[N]:= L;
  Cols [N]:= C;
  LineLen[L]:= C;
  SetLength(LineLen, L + 1);
end;

/// Adds the bytes [AStart, AEnd) as one token per line it touches.
procedure AddSpan(const AToks: TList<TSemTok>; const AMap: TByteMap; AStart, AEnd: Integer; ATokType, AMods: Integer);
begin
  var Hi: Integer:= Length(AMap.Lines) - 1;
  if (AStart < 0) or (AEnd > Hi) or (AEnd <= AStart) then Exit;
  var L0: Integer:= AMap.Lines[AStart];
  var L1: Integer:= AMap.Lines[AEnd];
  for var L: Integer:= L0 to L1 do
  begin
    var T: TSemTok;
    T.Line   := L;
    T.Col    := if L = L0 then AMap.Cols[AStart] else 0;
    var E: Integer:= if L = L1 then AMap.Cols[AEnd] else AMap.LineLen[L];
    T.Len    := E - T.Col;
    T.TokType:= ATokType;
    T.Mods   := AMods;
    if T.Len > 0 then AToks.Add(T);
  end;
end;

function IsAlphaSpan(const ASource: TBytes; AStart, AEnd: Integer): Boolean;
begin
  Result:= (AEnd > AStart) and (AStart >= 0) and (AEnd <= Length(ASource));
  if not Result then Exit;
  for var I: Integer:= AStart to AEnd - 1 do
    if not CharInSet(Char(ASource[I]), ['A'..'Z', 'a'..'z']) then Exit(False);
end;

function IsKeywordType(const ANode: TTSNode; const AType: string): Boolean;
begin
  Result:= (not ANode.IsNamed)
    or ((Length(AType) >= 2) and (AType[1] = KEYWORD_PREFIX) and CharInSet(AType[2], ['A'..'Z']));
end;

procedure WalkSyntax(const ANode: TTSNode; const ASource: TBytes; const AMap: TByteMap; const AToks: TList<TSemTok>);
begin
  if ANode.IsNull then Exit;
  var S: Integer:= Integer(ANode.StartByte);
  var E: Integer:= Integer(ANode.EndByte);
  var T: string:= ANode.NodeType;
  if T = NT_COMMENT then
    AddSpan(AToks, AMap, S, E, TT_COMMENT, MOD_NONE)
  else if (T = NT_STRING) or (T = NT_CHAR) then
    AddSpan(AToks, AMap, S, E, TT_STRING, MOD_NONE)
  else if T = NT_NUMBER then
    AddSpan(AToks, AMap, S, E, TT_NUMBER, MOD_NONE)
  else if IsKeywordType(ANode, T) and IsAlphaSpan(ASource, S, E) then
    AddSpan(AToks, AMap, S, E, TT_KEYWORD, MOD_NONE)
  else
    for var I: Integer:= 0 to ANode.ChildCount - 1 do
      WalkSyntax(ANode.Child(I), ASource, AMap, AToks);
end;

function DeclTokenType(AKind: TSymbolKind): Integer;
begin
  case AKind of
    skUnit, skProgram, skPackage            : Result:= TT_NAMESPACE;
    skClass                                 : Result:= TT_CLASS;
    skInterface                             : Result:= TT_INTERFACE;
    skEnum                                  : Result:= TT_ENUM;
    skProcedure, skFunction                 : Result:= TT_FUNCTION;
    skMethod, skConstructor, skDestructor   : Result:= TT_METHOD;
    skProperty                              : Result:= TT_PROPERTY;
    skVarDecl, skField, skLocalVar          : Result:= TT_VARIABLE;
    skParam                                 : Result:= TT_PARAMETER;
    skRecord, skTypeAlias                   : Result:= TT_TYPE;
  else
    Result:= TT_NONE;
  end;
end;

/// Zero-based UTF-16 column of the whole-word, case-insensitive AName on
/// ALine at or after AFromCol0; -1 when it is not there (the buffer moved
/// since the index was built, or the name is not on its start line).
function NameColumn(const AName, ALine: string; AFromCol0: Integer): Integer;
begin
  Result:= -1;
  var LName: string:= LowerCase(AName);
  var LLine: string:= LowerCase(ALine);
  var From: Integer:= if AFromCol0 < 0 then 1 else AFromCol0 + 1;
  while True do
  begin
    var P: Integer:= Pos(LName, LLine, From);
    if P = 0 then Exit;
    var After: Integer:= P + Length(AName);
    var BeforeOk: Boolean:= (P = 1) or not CharInSet(ALine[P - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
    var AfterOk : Boolean:= (After > Length(ALine)) or not CharInSet(ALine[After], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
    if BeforeOk and AfterOk then Exit(P - 1);
    From:= P + 1;
  end;
end;

procedure AddDeclarations(const AStores: TArray<ISymbolStore>; const APath: string; const ALines: TArray<string>; const AToks: TList<TSemTok>);
begin
  var Syms: TArray<TSymbol>:= nil;
  for var St: ISymbolStore in AStores do
  begin
    Syms:= St.FindSymbolsByFile(APath);
    if Length(Syms) > 0 then Break;
  end;
  for var Sym: TSymbol in Syms do
  begin
    var TT: Integer:= DeclTokenType(Sym.Kind);
    if (TT = TT_NONE) or (Sym.Name = '') or (Sym.StartLine < 1) or (Sym.StartLine > Length(ALines)) then Continue;
    var Col: Integer:= NameColumn(Sym.Name, ALines[Sym.StartLine - 1], Sym.StartCol - 1);
    if Col < 0 then Continue;
    var T: TSemTok;
    T.Line   := Sym.StartLine - 1;
    T.Col    := Col;
    T.Len    := Length(Sym.Name);
    T.TokType:= TT;
    T.Mods   := MOD_DECLARATION;
    AToks.Add(T);
  end;
end;

/// Sorts by (line, col), drops every token that overlaps the one kept before
/// it, and encodes the LSP relative 5-tuples.
function Encode(const AToks: TList<TSemTok>): TJSONArray;
begin
  AToks.Sort(TComparer<TSemTok>.Construct(
    function(const A, B: TSemTok): Integer
    begin
      Result:= A.Line - B.Line;
      if Result = 0 then Result:= A.Col - B.Col;
    end));
  Result:= TJSONArray.Create;
  var PrevLine: Integer:= 0;
  var PrevCol : Integer:= 0;
  var PrevEnd : Integer:= -1;
  var Any: Boolean:= False;
  for var T: TSemTok in AToks do
  begin
    if Any and (T.Line = PrevLine) and (T.Col < PrevEnd) then Continue;
    var DL: Integer:= T.Line - PrevLine;
    Result.Add(DL);
    Result.Add(if DL = 0 then T.Col - PrevCol else T.Col);
    Result.Add(T.Len);
    Result.Add(T.TokType);
    Result.Add(T.Mods);
    PrevLine:= T.Line;
    PrevCol := T.Col;
    PrevEnd := T.Col + T.Len;
    Any     := True;
  end;
end;

function SplitLines(const AText: string): TArray<string>;
begin
  Result:= AText.Split([#10]);
  for var I: Integer:= 0 to High(Result) do
    if Result[I].EndsWith(#13) then SetLength(Result[I], Length(Result[I]) - 1);
end;

class function TLspSemanticTokensFeature.Methods: TArray<string>;
begin
  Result:= [SEMTOK_METHOD];
end;

class procedure TLspSemanticTokensFeature.AddCapabilities(ACaps: TJSONObject);
begin
  var Types: TJSONArray:= TJSONArray.Create;
  for var S: string in LEGEND_TYPES do Types.Add(S);
  var Mods: TJSONArray:= TJSONArray.Create;
  Mods.Add('declaration');
  var Legend: TJSONObject:= TJSONObject.Create;
  Legend.AddPair('tokenTypes'    , Types);
  Legend.AddPair('tokenModifiers', Mods );
  var Prov: TJSONObject:= TJSONObject.Create;
  Prov.AddPair('legend', Legend);
  Prov.AddPair('full'  , TJSONBool.Create(True));
  ACaps.AddPair('semanticTokensProvider', Prov);
end;

procedure TLspSemanticTokensFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Path: string:= '';
  var Doc: TJSONObject:= nil;
  if AParams <> nil then Doc:= AParams.GetValue('textDocument') as TJSONObject;
  if (Doc <> nil) and (Doc.GetValue('uri') <> nil) then Path:= ACtx.FileFromUri(Doc.GetValue('uri').Value);
  var Toks: TList<TSemTok>:= TList<TSemTok>.Create;
  try
    if (Path <> '') and TLiveDocuments.Readable(Path) then
    begin
      var FromOverlay: Boolean;
      var Source: TBytes:= TLiveDocuments.ReadBytes(Path, FromOverlay);
      if not FromOverlay then Source:= EnsureUtf8Bytes(Source); // overlay bytes are UTF-8 already (see IdentifierAtPosition)
      var Map: TByteMap;
      Map.Build(Source);
      var Parser: TTSParser:= TTSParser.Create;
      try
        Parser.Language:= tree_sitter_delphi13;
        var Tree: TTSTree:= Parser.Parse(
          function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
          begin
            var Remaining: Integer:= Length(Source) - Integer(AByteIndex);
            if Remaining <= 0 then
            begin
              ABytesRead:= 0;
              Exit(nil);
            end;
            SetLength(Result, Remaining);
            Move(Source[AByteIndex], Result[0], Remaining);
            ABytesRead:= Remaining;
          end, TTSInputEncoding.TSInputEncodingUTF8);
        try
          if Tree <> nil then WalkSyntax(Tree.RootNode, Source, Map, Toks);
        finally
          Tree.Free;
        end;
      finally
        Parser.Free;
      end;
      var Stores: TArray<ISymbolStore>:= Copy(ACtx.StoresForFile(Path)); // a local copy; the server's list is never touched
      AddDeclarations(Stores, Path, SplitLines(TEncoding.UTF8.GetString(Source)), Toks);
    end;
    var Res: TJSONObject:= TJSONObject.Create;
    try
      Res.AddPair('data', Encode(Toks));
    except
      on Exception do
      begin
        Res.Free;
        raise;
      end;
    end;
    ACtx.Reply(AId, Res);
  finally
    Toks.Free;
  end;
end;

initialization
  RegisterLspFeature(TLspSemanticTokensFeature);

end.
