unit DRagLint.LSP.Feature.Rename;

{ `textDocument/prepareRename` and `textDocument/rename` (spec
  docs\superpowers\specs\2026-05-29-v024-rename-design.md), both starting from
  ILspServerContext.ResolveSymbolAt (the hover resolution).

  rename is a WRITE surface, so this unit only ever DESCRIBES the edit: it
  replies a WorkspaceEdit built by TRenameRefactoring.Build and never calls
  TRenameRefactoring.Apply -- the client applies the edit to its buffers.
  It refuses (error -32803, RequestFailed) everything the CLI `rename` verb
  refuses: a reserved word, a sibling-name collision (skipped for a case-only
  rename, the spec's case-insensitive rule), a use inside an indexed .inc, plus
  a new name that is not an identifier, a position that resolves to nothing
  this document's store declares, and an edit whose token is no longer where
  the index says (stale index or unsaved buffer), the declaration's
  edit included -- no edit is ever retargeted by a forward scan.

  Column units: IdentifierAtPosition takes a tree-sitter BYTE column while rename
  passes a UTF-16 column, so a non-ASCII character earlier on the line makes it
  refuse the edit (fail-safe, never a wrong rewrite).

  Registered through the S0 feature registry exactly as
  DRagLint.LSP.Feature.ImplDecl is. No extractor change. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/prepareRename` and `textDocument/rename`
  /// and advertises `renameProvider: {prepareProvider: true}`.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Never
  /// writes a file and never mutates the server's store list. Lines and
  /// characters in the replies are 0-based.</remarks>
  TLspRenameFeature = class(TLspFeature)
  public
    /// <summary>The two methods this feature answers.</summary>
    /// <returns>['textDocument/prepareRename', 'textDocument/rename'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `renameProvider: {prepareProvider: true}`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>prepareRename replies {range, placeholder} -- the identifier
    /// token under the cursor and the resolved symbol's Name -- or null when
    /// the position resolves to no symbol the document's own store
    /// (StoresForFile[0]) declares. rename replies a WorkspaceEdit
    /// {changes: {uri: TextEdit[]}}: one TextEdit per TRenameRefactoring.Build
    /// edit, its range the OldName token starting exactly at the edit's column
    /// as a whole word (every edit, the declaration included), newText the new name.</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">One of the two methods.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">{textDocument:{uri}, position:{line, character}}
    /// and, for rename, newName. A missing position answers null
    /// (prepareRename) or -32803 (rename).</param>
    /// <remarks>A refusal is an error reply, never an exception: -32602 for a
    /// missing newName, -32803 for every rule in the unit header.</remarks>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Refactor.Rename
  ;

const
  PREPARE_METHOD    = 'textDocument/prepareRename';
  RENAME_METHOD     = 'textDocument/rename';
  ERR_INVALID_PARAMS = -32602;
  ERR_REQUEST_FAILED = -32803;

type
  /// Disk lines per file, read once per request (ANSI, as the indexer reads).
  TLineCache = TObjectDictionary<string, TStringList>;

function IntField(const AObj: TJSONObject; const AName: string; out AValue: Integer): Boolean;
begin
  var V: TJSONValue:= nil;
  if AObj <> nil then V:= AObj.GetValue(AName);
  Result:= V is TJSONNumber;
  if Result then AValue:= (V as TJSONNumber).AsInt else AValue:= 0;
end;

function IsIdentChar(AChar: Char): Boolean;
begin
  Result:= CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// The 1-based line ALine1 of APath from disk; '' when the file or line is missing.
function DiskLine(const ACache: TLineCache; const APath: string; ALine1: Integer): string;
begin
  var Lines: TStringList;
  if not ACache.TryGetValue(APath, Lines) then
  begin
    Lines:= TStringList.Create;
    ACache.Add(APath, Lines);
    if TFile.Exists(APath) then Lines.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
  end;
  if (ALine1 >= 1) and (ALine1 <= Lines.Count) then Result:= Lines[ALine1 - 1] else Result:= '';
end;

function PositionJson(ALine0, AChar0: Integer): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('line'     , TJSONNumber.Create(ALine0));
  Result.AddPair('character', TJSONNumber.Create(AChar0));
end;

function RangeJson(ALine0, AStart0, AEnd0: Integer): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('start', PositionJson(ALine0, AStart0));
  Result.AddPair('end'  , PositionJson(ALine0, AEnd0));
end;

type
  /// What a request position resolves to, shared by both methods.
  TRenameTarget = record
    Path : string;
    Line0: Integer;
    Col0 : Integer;
    Sym  : TSymbol;
    Store: ISymbolStore; // the document's own store: StoresForFile(Path)[0]
  end;

// True when textDocument is an object holding a uri and position is an object (no EInvalidCast on a malformed request).
function ParamsShapeOk(const AParams: TJSONObject; out ADoc, APos: TJSONObject): Boolean;
begin
  ADoc:= nil;
  APos:= nil;
  if AParams = nil then Exit(False);
  if AParams.GetValue('textDocument') is TJSONObject then ADoc:= TJSONObject(AParams.GetValue('textDocument'));
  if AParams.GetValue('position') is TJSONObject then APos:= TJSONObject(AParams.GetValue('position'));
  Result:= (ADoc <> nil) and (APos <> nil) and (ADoc.GetValue('uri') <> nil);
end;

// True when the position names a symbol that the document's own store declares (so Build can find it by qualified name).
function ResolveTarget(const ACtx: ILspServerContext; const AParams: TJSONObject; out ATarget: TRenameTarget): Boolean;
begin
  Result:= False;
  ATarget:= Default(TRenameTarget);
  if AParams = nil then Exit;
  var Doc: TJSONObject:= nil;
  var PosObj: TJSONObject:= nil;
  if not ParamsShapeOk(AParams, Doc, PosObj) then Exit;
  ATarget.Path:= ACtx.FileFromUri(Doc.GetValue('uri').Value);
  if (ATarget.Path = '') or not IntField(PosObj, 'line', ATarget.Line0) or not IntField(PosObj, 'character', ATarget.Col0) then Exit;
  var HitStore: ISymbolStore;
  if not ACtx.ResolveSymbolAt(ATarget.Path, ATarget.Line0, ATarget.Col0, ATarget.Sym, HitStore) then Exit;
  var Own: TArray<ISymbolStore>:= ACtx.StoresForFile(ATarget.Path); // a copy; the server's list is untouched
  if Length(Own) = 0 then Exit;
  ATarget.Store:= Own[0];
  Result:= (ATarget.Sym.QualifiedName <> '') and (Length(ATarget.Store.FindSymbolsByQualifiedName(ATarget.Sym.QualifiedName)) > 0);
end;

procedure HandlePrepare(const ACtx: ILspServerContext; const AId: TJSONValue; const AParams: TJSONObject);
begin
  var T: TRenameTarget;
  if not ResolveTarget(ACtx, AParams, T) then
  begin
    ACtx.Reply(AId, nil);
    Exit;
  end;
  var Ident: string:= ACtx.IdentifierAtPosition(T.Path, T.Line0, T.Col0);
  var Start0: Integer:= T.Col0;
  var Cache: TLineCache:= TLineCache.Create([doOwnsValues]);
  try
    var Ln: string:= DiskLine(Cache, T.Path, T.Line0 + 1);
    var S0: Integer:= T.Col0;
    while (S0 > 0) and (S0 <= Length(Ln)) and IsIdentChar(Ln[S0]) do Dec(S0);
    if SameText(Copy(Ln, S0 + 1, Length(Ident)), Ident) then Start0:= S0;
  finally
    Cache.Free;
  end;
  var Res: TJSONObject:= TJSONObject.Create;
  try
    Res.AddPair('range', RangeJson(T.Line0, Start0, Start0 + Length(Ident)));
    Res.AddPair('placeholder', T.Sym.Name);
  except
    on Exception do
    begin
      Res.Free;
      raise;
    end;
  end;
  ACtx.Reply(AId, Res);
end;

// '' and AResult = the WorkspaceEdit, or the refusal message and AResult = nil.
function BuildWorkspaceEdit(const ACtx: ILspServerContext; const AEdits: TArray<TRenameEdit>; out AResult: TJSONObject): string;
begin
  Result:= '';
  AResult:= nil;
  var Changes: TJSONObject:= TJSONObject.Create;
  var Cache: TLineCache:= TLineCache.Create([doOwnsValues]);
  var Seen: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var Ed: TRenameEdit in AEdits do
    begin
      var DiskTxt: string:= DiskLine(Cache, Ed.FilePath, Ed.Line);
      var Col0: Integer;
      // Build reports the identifier token's column for EVERY edit, the declaration included: each must start exactly there
      // as a whole word, or the file changed after indexing (a forward scan could retarget a shifted token).
      if SameText(Copy(DiskTxt, Ed.Col, Length(Ed.OldName)), Ed.OldName) and ((Ed.Col = 1) or not IsIdentChar(DiskTxt[Ed.Col - 1])) and ((Ed.Col + Length(Ed.OldName) > Length(DiskTxt)) or not IsIdentChar(DiskTxt[Ed.Col + Length(Ed.OldName)])) then Col0:= Ed.Col - 1
      else Col0:= -1;
      // The live buffer must hold the same token, or the client would rewrite the wrong text.
      // IdentifierAtPosition takes a tree-sitter BYTE column, B3 passes a UTF-16 column: a non-ASCII char earlier on the line makes it refuse (fail-safe).
      if (Col0 < 0) or not SameText(ACtx.IdentifierAtPosition(Ed.FilePath, Ed.Line - 1, Col0), Ed.OldName) then
        Exit(Format('index out of date for %s:%d (no "%s" there) -- save and reindex, then retry', [Ed.FilePath, Ed.Line, Ed.OldName]));
      var Key: string:= UpperCase(Ed.FilePath) + '|' + IntToStr(Ed.Line) + '|' + IntToStr(Col0);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      var Uri: string:= ACtx.FileToUri(Ed.FilePath);
      var Arr: TJSONArray:= Changes.GetValue(Uri) as TJSONArray;
      if Arr = nil then
      begin
        Arr:= TJSONArray.Create;
        Changes.AddPair(Uri, Arr);
      end;
      var TE: TJSONObject:= TJSONObject.Create;
      Arr.AddElement(TE);
      TE.AddPair('range', RangeJson(Ed.Line - 1, Col0, Col0 + Length(Ed.OldName)));
      TE.AddPair('newText', Ed.NewName);
    end;
    AResult:= TJSONObject.Create;
    AResult.AddPair('changes', Changes);
    Changes:= nil;
  finally
    Changes.Free;
    Seen.Free;
    Cache.Free;
  end;
end;

procedure HandleRename(const ACtx: ILspServerContext; const AId: TJSONValue; const AParams: TJSONObject);
begin
  var NewNameVal: TJSONValue:= nil;
  if AParams <> nil then NewNameVal:= AParams.GetValue('newName');
  var ShapeDoc, ShapePos: TJSONObject;
  var ParamsErr: string:= '';
  if not (NewNameVal is TJSONString) then ParamsErr:= 'rename: newName (string) is required'
  else if not ParamsShapeOk(AParams, ShapeDoc, ShapePos) then ParamsErr:= 'rename: textDocument {uri} and position {line, character} are required';
  if ParamsErr <> '' then
  begin
    ACtx.ReplyError(AId, ERR_INVALID_PARAMS, ParamsErr);
    Exit;
  end;
  var NewName: string:= NewNameVal.Value;
  if not IsValidIdent(NewName) then
  begin
    ACtx.ReplyError(AId, ERR_REQUEST_FAILED, Format('cannot rename -- "%s" is not a valid identifier', [NewName]));
    Exit;
  end;
  if TRenameRefactoring.IsReservedWord(NewName) then
  begin
    ACtx.ReplyError(AId, ERR_REQUEST_FAILED, Format('cannot rename -- "%s" is a reserved word', [NewName]));
    Exit;
  end;
  var T: TRenameTarget;
  if not ResolveTarget(ACtx, AParams, T) then
  begin
    ACtx.ReplyError(AId, ERR_REQUEST_FAILED, 'cannot rename -- no symbol declared in this project''s index at this position');
    Exit;
  end;
  var QN: string:= T.Sym.QualifiedName;
  var Reason: string:= '';
  // The spec's collision rule applies only when the names differ beyond case.
  if not SameText(T.Sym.Name, NewName) then Reason:= TRenameRefactoring.ConflictReason(T.Store, QN, NewName);
  if Reason = '' then Reason:= TRenameRefactoring.IncludeUseReason(T.Store, QN);
  if Reason = '' then Reason:= TRenameRefactoring.BinaryDfmReason(T.Store, QN);
  var Edits: TArray<TRenameEdit>;
  if Reason = '' then
  begin
    Edits:= TRenameRefactoring.Build(T.Store, QN, NewName);
    if Length(Edits) = 0 then Reason:= Format('no edits computed for %s', [QN]);
  end;
  var Res: TJSONObject:= nil;
  if Reason = '' then Reason:= BuildWorkspaceEdit(ACtx, Edits, Res);
  if Reason <> '' then
  begin
    ACtx.ReplyError(AId, ERR_REQUEST_FAILED, 'cannot rename -- ' + Reason);
    Exit;
  end;
  ACtx.Reply(AId, Res);
end;

class function TLspRenameFeature.Methods: TArray<string>;
begin
  Result:= [PREPARE_METHOD, RENAME_METHOD];
end;

class procedure TLspRenameFeature.AddCapabilities(ACaps: TJSONObject);
begin
  var Opts: TJSONObject:= TJSONObject.Create;
  ACaps.AddPair('renameProvider', Opts);
  Opts.AddPair('prepareProvider', TJSONBool.Create(True));
end;

procedure TLspRenameFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  if AMethod = PREPARE_METHOD then HandlePrepare(ACtx, AId, AParams)
  else HandleRename(ACtx, AId, AParams);
end;

initialization
  RegisterLspFeature(TLspRenameFeature);

end.
