unit DRagLint.LSP.Feature.FoldingRange;

{ `textDocument/foldingRange` -- the editor's fold arrows, from the tree-sitter
  parse of the live buffer (or the file on disk). No index is consulted, so it
  works on a file no project holds.

  Folded: a routine (defProc / defFunc), a class / record / interface / helper
  type, a begin..end block, try, case and asm statements, a multi-line `uses`
  clause, and a multi-line comment (kind "comment"; a uses clause is kind
  "imports"). For a construct closed by a keyword (`end`) the fold stops one line
  short, so the closing line stays visible. One fold per start line: where two
  constructs open on the same line the outer, longer one is kept.

  A file that cannot be read or parsed answers []; a construct on one line is not
  a fold. Registered through the S0 feature registry. No extractor change. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/foldingRange` and advertises
  /// foldingRangeProvider.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines in the
  /// reply are 0-based.</remarks>
  TLspFoldingRangeFeature = class(TLspFeature)
  public
    /// <summary>The method this feature answers.</summary>
    /// <returns>['textDocument/foldingRange'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `foldingRangeProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies a FoldingRange[] ({startLine, endLine[, kind]}) ordered by start line.</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">textDocument/foldingRange.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{textDocument}; a missing field answers [].</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Encoding
  , DRagLint.Core.LiveDocs
  , DRagLint.Preprocess.Types
  , DRagLint.LSP.SyntaxTree
  ;

const
  FOLD_METHOD = 'textDocument/foldingRange';

  NT_COMMENT = 'comment';
  NT_USES    = 'declUses';

  // Node types whose closing line is a keyword (`end`) that should stay visible after folding.
  CLOSED_BY_KEYWORD: array[0..9] of string = ('defProc', 'defFunc', 'declClass', 'declIntf', 'declHelper', 'block', 'try', 'case', 'asm', 'declRecord');

type
  TFold = record
    StartLine, EndLine: Integer;
    Kind: string;
  end;

function IsKeywordClosed(const AType: string): Boolean;
begin
  Result:= False;
  for var T: string in CLOSED_BY_KEYWORD do
    if T = AType then Exit(True);
end;

// Records the fold of ANode when it is a foldable multi-line construct; the longer fold wins a shared start line.
procedure CollectFold(const ANode: TTSNode; const AFolds: TDictionary<Integer, TFold>);
begin
  var T: string:= ANode.NodeType;
  var Closed: Boolean:= IsKeywordClosed(T);
  if not (Closed or (T = NT_COMMENT) or (T = NT_USES)) then Exit;
  var F: TFold;
  F.StartLine:= Integer(ANode.StartPoint.row);
  F.EndLine  := Integer(ANode.EndPoint.row);
  F.Kind     := '';
  if T = NT_COMMENT then F.Kind:= 'comment'
  else if T = NT_USES then F.Kind:= 'imports';
  if Closed then Dec(F.EndLine);
  if F.EndLine <= F.StartLine then Exit;
  var Old: TFold;
  if AFolds.TryGetValue(F.StartLine, Old) and (Old.EndLine >= F.EndLine) then Exit;
  AFolds.AddOrSetValue(F.StartLine, F);
end;

procedure WalkFolds(const ARoot: TTSNode; const AFolds: TDictionary<Integer, TFold>);
begin
  if ARoot.IsNull then Exit;
  var Cur: TTSTreeCursor:= TTSTreeCursor.Create(ARoot);
  try
    while True do
    begin
      CollectFold(Cur.CurrentNode, AFolds);
      if Cur.GotoFirstChild then Continue;
      while not Cur.GotoNextSibling do
        if not Cur.GotoParent then Exit;
    end;
  finally
    Cur.Free;
  end;
end;

class function TLspFoldingRangeFeature.Methods: TArray<string>;
begin
  Result:= [FOLD_METHOD];
end;

class procedure TLspFoldingRangeFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('foldingRangeProvider', TJSONBool.Create(True));
end;

procedure TLspFoldingRangeFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONArray:= TJSONArray.Create;
  var Folds: TDictionary<Integer, TFold>:= TDictionary<Integer, TFold>.Create;
  try
    var Path: string:= '';
    var Doc: TJSONObject:= nil;
    if AParams <> nil then Doc:= AParams.GetValue('textDocument') as TJSONObject;
    if (Doc <> nil) and (Doc.GetValue('uri') <> nil) then Path:= ACtx.FileFromUri(Doc.GetValue('uri').Value);
    if (Path <> '') and TLiveDocuments.Readable(Path) then
    begin
      var FromOverlay: Boolean;
      var Source: TBytes:= TLiveDocuments.ReadBytes(Path, FromOverlay);
      if not FromOverlay then Source:= EnsureUtf8Bytes(Source);
      Source:= NormalizeLoneCR(Source);
      var Tree: TTSTree:= ParseDelphiUtf8(Source, Path);
      try
        if Tree <> nil then WalkFolds(Tree.RootNode, Folds);
      finally
        Tree.Free;
      end;
    end;
    var Keys: TArray<Integer>:= Folds.Keys.ToArray;
    TArray.Sort<Integer>(Keys);
    for var K: Integer in Keys do
    begin
      var F: TFold:= Folds[K];
      var O: TJSONObject:= TJSONObject.Create;
      Res.AddElement(O);
      O.AddPair('startLine', TJSONNumber.Create(F.StartLine));
      O.AddPair('endLine', TJSONNumber.Create(F.EndLine));
      if F.Kind <> '' then O.AddPair('kind', F.Kind);
    end;
  except
    on Exception do
    begin
      Res.Free;
      Folds.Free;
      raise;
    end;
  end;
  Folds.Free;
  ACtx.Reply(AId, Res);
end;

initialization
  RegisterLspFeature(TLspFoldingRangeFeature);

end.
