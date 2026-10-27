unit DRagLint.LSP.Feature.InlayHint;

{ `textDocument/inlayHint` (B6) -- parameter-name hints at call sites.

  For every call node inside the requested range of a tree-sitter parse of the
  live buffer (else the file on disk), the callee's name is looked up by exact
  name across the file's stores. A hint is emitted ONLY when that name means
  exactly ONE routine (one qualified name, one parameter list -- an overload
  set is silent) AND its parameter count equals the call's argument count;
  then each positional argument gets `<paramName>:` in front of it. Anything
  less certain shows nothing: a wrong hint is worse than none. Registered
  through the S0 feature registry exactly as DRagLint.LSP.Feature.CodeLens is. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/inlayHint` with parameter-name hints and
  /// advertises inlayHintProvider = true.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines are
  /// 0-based, columns UTF-16 code units. No inlayHint/resolve.</remarks>
  TLspInlayHintFeature = class(TLspFeature)
  public
    /// <summary>The one method: `textDocument/inlayHint`.</summary>
    /// <returns>['textDocument/inlayHint'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `inlayHintProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies an InlayHint[]: for each call whose callee resolves by
    /// exact name to exactly one routine whose parameter count (read from
    /// TSymbol.Signature) equals the argument count, one hint per argument
    /// {position: argument start, label: '&lt;paramName&gt;:', kind: 2,
    /// paddingRight: true}, in document order. Only arguments whose start lies
    /// inside the range (inclusive) are hinted.</summary>
    /// <param name="ACtx">The server surface; its store list is copied, never
    /// changed.</param>
    /// <param name="AMethod">Always `textDocument/inlayHint`.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{textDocument:{uri}, range}; a missing uri, an
    /// unknown/unreadable file or a missing range answers [].</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

/// <summary>The parameter names of a routine signature as the indexer stores
/// it, e.g. '(const pA, pB: Integer; var pC): Boolean' -> [pA, pB, pC].</summary>
/// <param name="ASignature">TSymbol.Signature of a routine.</param>
/// <param name="AHasList">Receives True when the signature carries a
/// parenthesised parameter list (an implementation that omits it is False).</param>
/// <returns>The names in declaration order; empty for '()' or no list.</returns>
function ParamNamesOfSignature(const ASignature: string; out AHasList: Boolean): TArray<string>;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Core.Encoding
  , DRagLint.Core.LiveDocs
  , DRagLint.LSP.SyntaxTree
  ;

const
  INLAY_METHOD = 'textDocument/inlayHint';
  HINT_KIND_PARAMETER = 2; // LSP InlayHintKind.Parameter

  // tree-sitter-delphi13 node types and fields of a call, the shape
  // DRagLint.Analysis.Cfg reads: (exprCall entity: <callee> args: (exprArgs ...)).
  // A qualified callee `T.Add(..)` has an exprDot entity whose last named child
  // is the member identifier.
  NT_CALL       = 'exprCall';
  NT_ARGS       = 'exprArgs';
  NT_DOT        = 'exprDot';
  NT_IDENT      = 'identifier';
  NT_COMMENT    = 'comment';
  FIELD_ENTITY  = 'entity';
  FIELD_ARGS    = 'args';

  PARAM_MODIFIERS: array[0..3] of string = ('const', 'var', 'out', 'constref');

function ParamNamesOfSignature(const ASignature: string; out AHasList: Boolean): TArray<string>;
begin
  Result:= nil;
  AHasList:= False;
  var Open: Integer:= Pos('(', ASignature);
  if Open = 0 then Exit;
  // the matching ')' and the ';' separators at depth 1
  var Depth: Integer:= 0;
  var Groups: TList<string>:= TList<string>.Create;
  try
    var Start: Integer:= Open + 1;
    for var I: Integer:= Open to Length(ASignature) do
    begin
      var C: Char:= ASignature[I];
      if CharInSet(C, ['(', '[']) then Inc(Depth)
      else if CharInSet(C, [')', ']']) then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Groups.Add(Copy(ASignature, Start, I - Start));
          AHasList:= True;
          Break;
        end;
      end
      else if (C = ';') and (Depth = 1) then
      begin
        Groups.Add(Copy(ASignature, Start, I - Start));
        Start:= I + 1;
      end;
    end;
    if not AHasList then Exit;
    for var G: string in Groups do
    begin
      var S: string:= Trim(G);
      if S.StartsWith('[') and (Pos(']', S) > 0) then S:= Trim(Copy(S, Pos(']', S) + 1, MaxInt)); // [ref] attribute
      var Colon: Integer:= Pos(':', S);
      if Colon > 0 then S:= Copy(S, 1, Colon - 1);
      S:= Trim(S);
      for var M: string in PARAM_MODIFIERS do
        if SameText(Copy(S, 1, Length(M) + 1), M + ' ') then
        begin
          S:= Trim(Copy(S, Length(M) + 1, MaxInt));
          Break;
        end;
      // S4: `const [ref] pA` -- the attribute can FOLLOW the modifier
      if S.StartsWith('[') and (Pos(']', S) > 0) then S:= Trim(Copy(S, Pos(']', S) + 1, MaxInt));
      for var N: string in S.Split([',']) do
        if Trim(N) <> '' then Result:= Result + [Trim(N)];
    end;
  finally
    Groups.Free;
  end;
end;

type
  /// The one routine a callee name means, or Known = False.
  TCallee = record
    Known : Boolean;
    Params: TArray<string>;
  end;

  THintWalker = class
  private
    FSource : TBytes;
    FStores : TArray<ISymbolStore>;
    FCache  : TDictionary<string, TCallee>;
    FFrom, FTo: TTSPoint; // 0-based (row, UTF-16 column), inclusive
    FResult : TJSONArray;
    function Text(const ANode: TTSNode): string;
    function Column16(const ANode: TTSNode): Integer;
    function Lookup(const AName: string): TCallee;
    function InRange(ALine, ACol: Integer): Boolean;
    function OutsideRange(const ANode: TTSNode): Boolean;
    procedure VisitCall(const ANode: TTSNode);
  public
    constructor Create(const ASource: TBytes; const AStores: TArray<ISymbolStore>; AResult: TJSONArray);
    destructor Destroy; override;
    procedure SetRange(AFromLine, AFromCol, AToLine, AToCol: Integer);
    procedure Walk(const ARoot: TTSNode);
    procedure WalkSource(const AFile: string);
  end;

constructor THintWalker.Create(const ASource: TBytes; const AStores: TArray<ISymbolStore>; AResult: TJSONArray);
begin
  inherited Create;
  FSource:= ASource;
  FStores:= AStores;
  FResult:= AResult;
  FCache := TDictionary<string, TCallee>.Create;
end;

destructor THintWalker.Destroy;
begin
  FCache.Free;
  inherited Destroy;
end;

procedure THintWalker.SetRange(AFromLine, AFromCol, AToLine, AToCol: Integer);
begin
  FFrom.row:= UInt32(AFromLine);
  FFrom.column:= UInt32(AFromCol);
  FTo.row:= UInt32(AToLine);
  FTo.column:= UInt32(AToCol);
end;

function THintWalker.Text(const ANode: TTSNode): string;
begin
  var S: Integer:= Integer(ANode.StartByte);
  var E: Integer:= Integer(ANode.EndByte);
  if (S < 0) or (E > Length(FSource)) or (E <= S) then Exit('');
  Result:= TEncoding.UTF8.GetString(FSource, S, E - S);
end;

function THintWalker.Column16(const ANode: TTSNode): Integer;
begin
  var P: TTSPoint:= ANode.StartPoint;
  var LineStart: Integer:= Integer(ANode.StartByte) - Integer(P.column);
  if LineStart < 0 then Exit(Integer(P.column));
  Result:= TEncoding.UTF8.GetCharCount(FSource, LineStart, Integer(P.column));
end;

function THintWalker.InRange(ALine, ACol: Integer): Boolean;
begin
  var AfterStart: Boolean:= (ALine > Integer(FFrom.row)) or ((ALine = Integer(FFrom.row)) and (ACol >= Integer(FFrom.column)));
  var BeforeEnd : Boolean:= (ALine < Integer(FTo.row)) or ((ALine = Integer(FTo.row)) and (ACol <= Integer(FTo.column)));
  Result:= AfterStart and BeforeEnd;
end;

function THintWalker.OutsideRange(const ANode: TTSNode): Boolean;
begin
  { Rows decide the far side: a tree-sitter column is a BYTE column and FTo a
    UTF-16 one, so a column test there could skip a node that is in range.
    On the near side the byte end column is >= the UTF-16 one, so
    EndByteCol < FFrom.column is safe. }
  var S: TTSPoint:= ANode.StartPoint;
  var E: TTSPoint:= ANode.EndPoint;
  Result:= (S.row > FTo.row) or (E.row < FFrom.row) or ((E.row = FFrom.row) and (E.column < FFrom.column));
end;

function THintWalker.Lookup(const AName: string): TCallee;
begin
  var Key: string:= LowerCase(AName);
  if FCache.TryGetValue(Key, Result) then Exit;
  Result.Known:= False;
  Result.Params:= nil;
  var Names: TDictionary<string, Byte>:= TDictionary<string, Byte>.Create;
  var Lists: TDictionary<string, TArray<string>>:= TDictionary<string, TArray<string>>.Create;
  try
    for var St: ISymbolStore in FStores do
    begin
      if St = nil then Continue;
      for var Sym: TSymbol in St.FindSymbolsByExactName(AName) do
      begin
        if not (Sym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) then Continue;
        Names.AddOrSetValue(LowerCase(Sym.QualifiedName), 1);
        var HasList: Boolean;
        var P: TArray<string>:= ParamNamesOfSignature(Sym.Signature, HasList);
        if HasList then Lists.AddOrSetValue(LowerCase(string.Join(',', P)), P); // a body that omits its list adds nothing
      end;
    end;
    if (Names.Count = 1) and (Lists.Count = 1) then
    begin
      Result.Known := True;
      Result.Params:= Lists.Values.ToArray[0];
    end;
  finally
    Lists.Free;
    Names.Free;
  end;
  FCache.Add(Key, Result);
end;

procedure THintWalker.VisitCall(const ANode: TTSNode);
begin
  var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
  var Args: TTSNode:= ANode.ChildByField(FIELD_ARGS);
  if Ent.IsNull or Args.IsNull or (Args.NodeType <> NT_ARGS) then Exit;
  if (Ent.NodeType = NT_DOT) and (Ent.NamedChildCount > 0) then Ent:= Ent.NamedChild(Ent.NamedChildCount - 1);
  if Ent.NodeType <> NT_IDENT then Exit;
  var ArgNodes: TArray<TTSNode>:= nil;
  for var I: Integer:= 0 to Args.NamedChildCount - 1 do
    if Args.NamedChild(I).NodeType <> NT_COMMENT then ArgNodes:= ArgNodes + [Args.NamedChild(I)];
  if Length(ArgNodes) = 0 then Exit;
  var Callee: TCallee:= Lookup(Text(Ent));
  if (not Callee.Known) or (Length(Callee.Params) <> Length(ArgNodes)) then Exit;
  for var I: Integer:= 0 to High(ArgNodes) do
  begin
    var Line: Integer:= Integer(ArgNodes[I].StartPoint.row);
    var Col : Integer:= Column16(ArgNodes[I]);
    if not InRange(Line, Col) then Continue;
    var Hint: TJSONObject:= TJSONObject.Create;
    FResult.AddElement(Hint);
    var Pos0: TJSONObject:= TJSONObject.Create;
    Hint.AddPair('position', Pos0);
    Pos0.AddPair('line'     , TJSONNumber.Create(Line));
    Pos0.AddPair('character', TJSONNumber.Create(Col));
    Hint.AddPair('label'       , Callee.Params[I] + ':');
    Hint.AddPair('kind'        , TJSONNumber.Create(HINT_KIND_PARAMETER));
    Hint.AddPair('paddingRight', TJSONBool.Create(True));
  end;
end;

procedure THintWalker.Walk(const ARoot: TTSNode);
begin
  if ARoot.IsNull then Exit;
  var Cur: TTSTreeCursor:= TTSTreeCursor.Create(ARoot);
  try
    // iterative pre-order walk: ts_node_child(i) is O(i), a cursor is O(1) per step
    while True do
    begin
      var N: TTSNode:= Cur.CurrentNode;
      // S3: a subtree wholly outside the viewport can hold no in-range hint
      // (every hint sits at an argument start inside its call's span), so it
      // is neither visited nor descended into.
      if not OutsideRange(N) then
      begin
        if N.NodeType = NT_CALL then VisitCall(N);
        if Cur.GotoFirstChild then Continue;
      end;
      var Moved: Boolean:= False;
      while not Moved do
      begin
        if Cur.GotoNextSibling then Moved:= True
        else if not Cur.GotoParent then Exit;
      end;
    end;
  finally
    Cur.Free;
  end;
end;

procedure THintWalker.WalkSource(const AFile: string);
begin
  var Tree: TTSTree:= ParseDelphiUtf8(FSource, AFile);
  try
    if Tree <> nil then Walk(Tree.RootNode);
  finally
    Tree.Free;
  end;
end;

function GetPos(const AObj: TJSONObject; const AName: string; out ALine, ACol: Integer): Boolean;
begin
  Result:= False;
  ALine:= 0;
  ACol := 0;
  if AObj = nil then Exit;
  var P: TJSONObject:= AObj.GetValue(AName) as TJSONObject;
  if (P = nil) or (P.GetValue('line') = nil) or (P.GetValue('character') = nil) then Exit;
  ALine:= P.GetValue<Integer>('line');
  ACol := P.GetValue<Integer>('character');
  Result:= True;
end;

/// The local path of params.textDocument.uri ('' when absent) and params.range
/// (nil when absent or not an object).
function RequestPath(const ACtx: ILspServerContext; const AParams: TJSONObject; out ARange: TJSONObject): string;
begin
  Result:= '';
  ARange:= nil;
  if AParams = nil then Exit;
  if AParams.GetValue('range') is TJSONObject then ARange:= TJSONObject(AParams.GetValue('range'));
  var Doc: TJSONValue:= AParams.GetValue('textDocument');
  if (Doc is TJSONObject) and (TJSONObject(Doc).GetValue('uri') <> nil) then
    Result:= ACtx.FileFromUri(TJSONObject(Doc).GetValue('uri').Value);
end;

class function TLspInlayHintFeature.Methods: TArray<string>;
begin
  Result:= [INLAY_METHOD];
end;

class procedure TLspInlayHintFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('inlayHintProvider', TJSONBool.Create(True));
end;

procedure TLspInlayHintFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONArray:= TJSONArray.Create;
  try
    var Rng: TJSONObject;
    var Path: string:= RequestPath(ACtx, AParams, Rng);
    var L0, C0, L1, C1: Integer;
    if (Path <> '') and GetPos(Rng, 'start', L0, C0) and GetPos(Rng, 'end', L1, C1) and TLiveDocuments.Readable(Path) then
    begin
      var FromOverlay: Boolean;
      var Source: TBytes:= TLiveDocuments.ReadBytes(Path, FromOverlay);
      if not FromOverlay then Source:= EnsureUtf8Bytes(Source); // overlay bytes are UTF-8 already
      var Stores: TArray<ISymbolStore>:= Copy(ACtx.StoresForFile(Path)); // a local copy; the server's list is never touched
      var W: THintWalker:= THintWalker.Create(Source, Stores, Res);
      try
        W.SetRange(L0, C0, L1, C1);
        W.WalkSource(Path);
      finally
        W.Free;
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
  RegisterLspFeature(TLspInlayHintFeature);

end.
