unit DRagLint.LSP.Server;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.NetEncoding,
  Winapi.Windows,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite,
  DRagLint.Parser.Delphi13,
  DRagLint.Hover.Renderer,
  DRagLint.Resolver.TypeAt,
  DRagLint.Lint.Linter,
  DRagLint.LSP.Completion;

type
  // Language Server Protocol over stdio with Content-Length framing.
  // Implements the subset that's actually useful when backed by a static
  // symbol index: initialize, shutdown, workspace/symbol,
  // textDocument/definition, textDocument/references.
  //
  // v0.6 deliberately does NOT implement textDocument/didChange - files are
  // indexed via `drag-lint index` ahead of time. Editing a file in-place
  // and getting fresh results requires a re-run of `index` (which is
  // sub-second per file thanks to v0.4 incremental).
  TLSPServer = class
  strict private
    FStore: ISymbolStore;
    FStdIn: THandleStream;
    FLinter: TLinter;
    FInitialized: Boolean;
    FShuttingDown: Boolean;
    function ReadMessage: TJSONObject;
    procedure SendMessage(const AObj: TJSONObject);
    procedure SendRawNotification(const AObj: TJSONObject);
    procedure SendError(const AId: TJSONValue; ACode: Integer;
      const AMessage: string);
    function FileFromUri(const AUri: string): string;
    function FileToUri(const APath: string): string;
    procedure HandleInitialize(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleShutdown(const AId: TJSONValue);
    procedure HandleWorkspaceSymbol(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleDefinition(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleReferences(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleHover(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleCompletion(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleSignatureHelp(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleDidOpenOrSave(const AParams: TJSONObject);
    function LocationFromSymbol(const ASym: TSymbol): TJSONObject;
    function LocationFromRef(const ARef: TReference): TJSONObject;
    // v0.7: reparse the file at APath and find the identifier text under
    // (ALine, ACol) - both 0-based (LSP convention). Returns empty string
    // if the file doesn't exist or the cursor isn't on an identifier.
    function IdentifierAtPosition(const APath: string;
      ALine, ACol: Integer): string;
    function EnsureLinter: TLinter;
  public
    constructor Create(const ADbPath: string);
    destructor Destroy; override;
    procedure Run;
  end;

implementation

constructor TLSPServer.Create(const ADbPath: string);
begin
  inherited Create;
  FStdIn := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
  FLinter := nil;
  if ADbPath <> '' then
  begin
    FStore := TSQLiteSymbolStore.Create(ADbPath);
    FStore.Migrate;
  end;
end;

destructor TLSPServer.Destroy;
begin
  FLinter.Free;
  FStdIn.Free;
  FStore := nil;
  inherited;
end;

function TLSPServer.EnsureLinter: TLinter;
begin
  if FLinter = nil then
    FLinter := TLinter.Create('');
  Result := FLinter;
end;

function TLSPServer.ReadMessage: TJSONObject;
var
  Headers: TStringList;
  Line: TStringBuilder;
  Ch: Byte;
  Header, ContentLengthStr: string;
  ContentLength: Integer;
  Body: TBytes;
  ReadBytes: Integer;
  Parsed: TJSONValue;
  i: Integer;
begin
  Result := nil;
  Headers := TStringList.Create;
  Line := TStringBuilder.Create;
  try
    // Read CRLF-terminated header lines until empty line.
    while True do
    begin
      if FStdIn.Read(Ch, 1) <> 1 then Exit;
      if Ch = 13 then  // CR - expect LF next
      begin
        if FStdIn.Read(Ch, 1) <> 1 then Exit;
        if Ch = 10 then
        begin
          if Line.Length = 0 then
            Break;  // empty line - end of headers
          Headers.Add(Line.ToString);
          Line.Clear;
        end;
      end
      else if Ch = 10 then
      begin
        if Line.Length = 0 then Break;
        Headers.Add(Line.ToString);
        Line.Clear;
      end
      else
        Line.Append(Char(Ch));
    end;
    ContentLength := 0;
    for Header in Headers do
    begin
      if Header.StartsWith('Content-Length:', True) then
      begin
        ContentLengthStr := Trim(Copy(Header, Length('Content-Length:') + 1,
          MaxInt));
        ContentLength := StrToIntDef(ContentLengthStr, 0);
      end;
    end;
    if ContentLength <= 0 then Exit;
    SetLength(Body, ContentLength);
    ReadBytes := 0;
    while ReadBytes < ContentLength do
    begin
      i := FStdIn.Read(Body[ReadBytes], ContentLength - ReadBytes);
      if i <= 0 then Exit;
      Inc(ReadBytes, i);
    end;
    Parsed := TJSONObject.ParseJSONValue(Body, 0);
    if Parsed is TJSONObject then
      Result := TJSONObject(Parsed)
    else
      Parsed.Free;
  finally
    Line.Free;
    Headers.Free;
  end;
end;

procedure TLSPServer.SendMessage(const AObj: TJSONObject);
var
  Body: string;
  BodyBytes: TBytes;
  Header: AnsiString;
  HeaderBytes: TBytes;
  StdOutHandle: THandle;
  Written: DWORD;
begin
  Body := AObj.ToJSON;
  BodyBytes := TEncoding.UTF8.GetBytes(Body);
  Header := AnsiString('Content-Length: ' + IntToStr(Length(BodyBytes)) +
    #13#10#13#10);
  SetLength(HeaderBytes, Length(Header));
  if Length(Header) > 0 then
    Move(Header[1], HeaderBytes[0], Length(Header));
  StdOutHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  if Length(HeaderBytes) > 0 then
    WriteFile(StdOutHandle, HeaderBytes[0], Length(HeaderBytes), Written, nil);
  if Length(BodyBytes) > 0 then
    WriteFile(StdOutHandle, BodyBytes[0], Length(BodyBytes), Written, nil);
end;

// SendRawNotification sends a notification (no id) with Content-Length framing.
// Identical to SendMessage but semantically distinct — used for server-pushed
// notifications such as textDocument/publishDiagnostics.
procedure TLSPServer.SendRawNotification(const AObj: TJSONObject);
begin
  SendMessage(AObj);
end;

procedure TLSPServer.SendError(const AId: TJSONValue; ACode: Integer;
  const AMessage: string);
var
  Obj, Err: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Obj.AddPair('id', AId.Clone as TJSONValue)
    else
      Obj.AddPair('id', TJSONNull.Create);
    Err := TJSONObject.Create;
    Err.AddPair('code', TJSONNumber.Create(ACode));
    Err.AddPair('message', AMessage);
    Obj.AddPair('error', Err);
    SendMessage(Obj);
  finally
    Obj.Free;
  end;
end;

function TLSPServer.FileFromUri(const AUri: string): string;
var
  Decoded: string;
begin
  Result := AUri;
  if Result.StartsWith('file:///') then
    Result := Copy(Result, 9, MaxInt);
  Decoded := TNetEncoding.URL.Decode(Result);
  Result := StringReplace(Decoded, '/', '\', [rfReplaceAll]);
end;

function TLSPServer.FileToUri(const APath: string): string;
var
  Normalised, Encoded: string;
begin
  Normalised := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Encoded := TNetEncoding.URL.EncodePath(Normalised);
  // EncodePath preserves the leading slash if it exists, so we'd end up
  // with file://// for absolute Windows paths. Strip it before prepending.
  if Encoded.StartsWith('/') then
    Encoded := Copy(Encoded, 2, MaxInt);
  Result := 'file:///' + Encoded;
end;

function TLSPServer.LocationFromSymbol(const ASym: TSymbol): TJSONObject;
var
  Range, Start, EndPos: TJSONObject;
  Path: string;
begin
  Result := TJSONObject.Create;
  Path := FStore.GetFilePath(ASym.FileId);
  Result.AddPair('uri', FileToUri(Path));
  Range := TJSONObject.Create;
  Start := TJSONObject.Create;
  // LSP positions are 0-based; our DB stores 1-based.
  Start.AddPair('line', TJSONNumber.Create(ASym.StartLine - 1));
  Start.AddPair('character', TJSONNumber.Create(ASym.StartCol - 1));
  EndPos := TJSONObject.Create;
  EndPos.AddPair('line', TJSONNumber.Create(ASym.EndLine - 1));
  EndPos.AddPair('character', TJSONNumber.Create(ASym.EndCol - 1));
  Range.AddPair('start', Start);
  Range.AddPair('end', EndPos);
  Result.AddPair('range', Range);
end;

function TLSPServer.LocationFromRef(const ARef: TReference): TJSONObject;
var
  Range, Start, EndPos: TJSONObject;
  Path: string;
begin
  Result := TJSONObject.Create;
  Path := FStore.GetFilePath(ARef.FileId);
  Result.AddPair('uri', FileToUri(Path));
  Range := TJSONObject.Create;
  Start := TJSONObject.Create;
  Start.AddPair('line', TJSONNumber.Create(ARef.StartLine - 1));
  Start.AddPair('character', TJSONNumber.Create(ARef.StartCol - 1));
  EndPos := TJSONObject.Create;
  EndPos.AddPair('line', TJSONNumber.Create(ARef.EndLine - 1));
  EndPos.AddPair('character', TJSONNumber.Create(ARef.EndCol - 1));
  Range.AddPair('start', Start);
  Range.AddPair('end', EndPos);
  Result.AddPair('range', Range);
end;

procedure TLSPServer.HandleInitialize(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Reply, ResObj, Caps, Info: TJSONObject;
  CompProvider, SigProvider: TJSONObject;
  TriggerCharsCompletion, TriggerCharsSig: TJSONArray;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    ResObj := TJSONObject.Create;
    Caps := TJSONObject.Create;
    Caps.AddPair('definitionProvider', TJSONBool.Create(True));
    Caps.AddPair('referencesProvider', TJSONBool.Create(True));
    Caps.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
    Caps.AddPair('hoverProvider', TJSONBool.Create(True));
    // v0.20: completion provider
    CompProvider := TJSONObject.Create;
    TriggerCharsCompletion := TJSONArray.Create;
    TriggerCharsCompletion.AddElement(TJSONString.Create('.'));
    TriggerCharsCompletion.AddElement(TJSONString.Create('('));
    TriggerCharsCompletion.AddElement(TJSONString.Create(','));
    CompProvider.AddPair('triggerCharacters', TriggerCharsCompletion);
    CompProvider.AddPair('resolveProvider', TJSONBool.Create(False));
    Caps.AddPair('completionProvider', CompProvider);
    // v0.20: signatureHelp provider
    SigProvider := TJSONObject.Create;
    TriggerCharsSig := TJSONArray.Create;
    TriggerCharsSig.AddElement(TJSONString.Create('('));
    TriggerCharsSig.AddElement(TJSONString.Create(','));
    SigProvider.AddPair('triggerCharacters', TriggerCharsSig);
    Caps.AddPair('signatureHelpProvider', SigProvider);
    ResObj.AddPair('capabilities', Caps);
    Info := TJSONObject.Create;
    Info.AddPair('name', 'drag-lint LSP');
    Info.AddPair('version', '0.33.0-alpha');
    ResObj.AddPair('serverInfo', Info);
    Reply.AddPair('result', ResObj);
    SendMessage(Reply);
    FInitialized := True;
  finally
    Reply.Free;
  end;
end;

function ContainsPosition(const ANode: TTSNode; ALine, ACol: Integer): Boolean;
var
  Sp, Ep: TTSPoint;
begin
  Sp := ANode.StartPoint;
  Ep := ANode.EndPoint;
  // Tree-sitter rows/cols are 0-based, matching LSP.
  if (ALine < Integer(Sp.row)) or (ALine > Integer(Ep.row)) then
    Exit(False);
  if (ALine = Integer(Sp.row)) and (ACol < Integer(Sp.column)) then
    Exit(False);
  // EndPoint is exclusive - cursor right at the end is past the token.
  if (ALine = Integer(Ep.row)) and (ACol >= Integer(Ep.column)) then
    Exit(False);
  Result := True;
end;

function FindSmallestNamedAt(const ANode: TTSNode; ALine, ACol: Integer): TTSNode;
var
  i: Integer;
  Child, Hit: TTSNode;
begin
  Result := Default(TTSNode);
  if ANode.IsNull then Exit;
  if not ContainsPosition(ANode, ALine, ACol) then Exit;
  for i := 0 to ANode.NamedChildCount - 1 do
  begin
    Child := ANode.NamedChild(i);
    if ContainsPosition(Child, ALine, ACol) then
    begin
      Hit := FindSmallestNamedAt(Child, ALine, ACol);
      if not Hit.IsNull then
        Exit(Hit);
    end;
  end;
  Result := ANode;
end;

function NodeTextLocal(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx, EndIdx, Len: Integer;
begin
  Result := '';
  if ANode.IsNull then Exit;
  StartIdx := Integer(ANode.StartByte);
  EndIdx := Integer(ANode.EndByte);
  Len := EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then
    Exit;
  Result := TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

function TLSPServer.IdentifierAtPosition(const APath: string;
  ALine, ACol: Integer): string;
var
  Parser: TTSParser;
  Tree: TTSTree;
  Source: TBytes;
  Node: TTSNode;
begin
  Result := '';
  if not TFile.Exists(APath) then Exit;
  Source := TFile.ReadAllBytes(APath);
  Parser := nil;
  Tree := nil;
  try
    Parser := TTSParser.Create;
    Parser.Language := tree_sitter_delphi13;
    Tree := Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint;
        var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining := Length(Source) - Integer(AByteIndex);
        if Remaining <= 0 then
        begin
          ABytesRead := 0;
          SetLength(Result, 0);
          Exit;
        end;
        SetLength(Result, Remaining);
        Move(Source[AByteIndex], Result[0], Remaining);
        ABytesRead := Remaining;
      end,
      TTSInputEncoding.TSInputEncodingUTF8);

    Node := FindSmallestNamedAt(Tree.RootNode, ALine, ACol);
    if Node.IsNull then Exit;
    // Prefer an identifier-shaped node. If the smallest enclosing is e.g.
    // a `genericDot` (qualified name like Foo.Bar), drill into its rhs.
    if Node.NodeType = 'genericDot' then
    begin
      var Rhs := Node.ChildByField('rhs');
      if (not Rhs.IsNull) and ContainsPosition(Rhs, ALine, ACol) then
        Node := Rhs;
    end
    else if Node.NodeType = 'exprDot' then
    begin
      var Rhs := Node.ChildByField('rhs');
      if (not Rhs.IsNull) and ContainsPosition(Rhs, ALine, ACol) then
        Node := Rhs;
    end;
    if (Node.NodeType <> 'identifier') and
       (Node.NodeType <> 'moduleName') then
    begin
      // Try to find an identifier descendant covering the cursor.
      var ChildIt := Node;
      while (ChildIt.NamedChildCount > 0) and
            (ChildIt.NodeType <> 'identifier') do
      begin
        var Found := False;
        for var i := 0 to ChildIt.NamedChildCount - 1 do
        begin
          var C := ChildIt.NamedChild(i);
          if ContainsPosition(C, ALine, ACol) then
          begin
            ChildIt := C;
            Found := True;
            Break;
          end;
        end;
        if not Found then Break;
      end;
      Node := ChildIt;
    end;
    Result := Trim(NodeTextLocal(Node, Source));
  finally
    Tree.Free;
    Parser.Free;
  end;
end;

procedure TLSPServer.HandleShutdown(const AId: TJSONValue);
var
  Reply: TJSONObject;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    Reply.AddPair('result', TJSONNull.Create);
    SendMessage(Reply);
    FShuttingDown := True;
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleWorkspaceSymbol(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Reply: TJSONObject;
  Arr: TJSONArray;
  QueryStr: string;
  Symbols: TArray<TSymbol>;
  Sym: TSymbol;
  SymObj, Loc: TJSONObject;
begin
  Reply := TJSONObject.Create;
  Arr := TJSONArray.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    if FStore = nil then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    QueryStr := '';
    if (AParams <> nil) and (AParams.GetValue('query') <> nil) then
      QueryStr := AParams.GetValue('query').Value;
    if QueryStr = '' then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    Symbols := FStore.FindSymbolsByExactName(QueryStr);
    if Length(Symbols) = 0 then
      Symbols := FStore.FindSymbolsFuzzy(QueryStr, 50);
    for Sym in Symbols do
    begin
      SymObj := TJSONObject.Create;
      SymObj.AddPair('name', Sym.Name);
      // LSP SymbolKind enum: 5=Class, 11=Interface, 23=Struct, 10=Enum,
      // 6=Method, 12=Function, 7=Property, 8=Field, ...
      var Kind: Integer;
      case Sym.Kind of
        skClass: Kind := 5;
        skInterface: Kind := 11;
        skRecord: Kind := 23;
        skEnum: Kind := 10;
        skEnumValue: Kind := 22;
        skMethod, skConstructor, skDestructor: Kind := 6;
        skProcedure, skFunction: Kind := 12;
        skProperty: Kind := 7;
        skField: Kind := 8;
        skVarDecl: Kind := 13;
        skConstDecl: Kind := 14;
        skUnit, skPackage, skProgram: Kind := 2;
        skForm: Kind := 5;
        skComponent: Kind := 8;
      else Kind := 1;
      end;
      SymObj.AddPair('kind', TJSONNumber.Create(Kind));
      SymObj.AddPair('containerName', Sym.QualifiedName);
      Loc := LocationFromSymbol(Sym);
      SymObj.AddPair('location', Loc);
      Arr.AddElement(SymObj);
    end;
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleDefinition(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Reply: TJSONObject;
  Arr: TJSONArray;
  TextDoc, Position: TJSONObject;
  Uri, Path, Ident: string;
  Line, Col: Integer;
  Symbols: TArray<TSymbol>;
  Sym: TSymbol;
begin
  Reply := TJSONObject.Create;
  Arr := TJSONArray.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position := AParams.GetValue('position') as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    Uri := TextDoc.GetValue('uri').Value;
    Path := FileFromUri(Uri);
    Line := StrToIntDef(Position.GetValue('line').Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);

    Ident := IdentifierAtPosition(Path, Line, Col);
    if Ident <> '' then
    begin
      Symbols := FStore.FindSymbolsByExactName(Ident);
      for Sym in Symbols do
        Arr.AddElement(LocationFromSymbol(Sym));
    end;
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleReferences(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Reply: TJSONObject;
  Arr: TJSONArray;
  TextDoc, Position, Context: TJSONObject;
  Uri, Path, Ident: string;
  Line, Col: Integer;
  Refs: TArray<TReference>;
  Symbols: TArray<TSymbol>;
  IncludeDecl: Boolean;
  R: TReference;
  Sym: TSymbol;
begin
  Reply := TJSONObject.Create;
  Arr := TJSONArray.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position := AParams.GetValue('position') as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    Uri := TextDoc.GetValue('uri').Value;
    Path := FileFromUri(Uri);
    Line := StrToIntDef(Position.GetValue('line').Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);

    IncludeDecl := True;
    Context := AParams.GetValue('context') as TJSONObject;
    if Context <> nil then
    begin
      var IncDeclVal := Context.GetValue('includeDeclaration');
      if IncDeclVal is TJSONBool then
        IncludeDecl := TJSONBool(IncDeclVal).AsBoolean;
    end;

    Ident := IdentifierAtPosition(Path, Line, Col);
    if Ident <> '' then
    begin
      Refs := FStore.FindCallersByName(Ident);
      for R in Refs do
        Arr.AddElement(LocationFromRef(R));
      if IncludeDecl then
      begin
        Symbols := FStore.FindSymbolsByExactName(Ident);
        for Sym in Symbols do
          Arr.AddElement(LocationFromSymbol(Sym));
      end;
    end;
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleHover(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Reply, HoverObj, Contents: TJSONObject;
  TextDoc, Position: TJSONObject;
  Uri, Path, Ident, MdValue: string;
  Line, Col: Integer;
  Symbols: TArray<TSymbol>;
  Sym: TSymbol;
  Doc: TParsedDoc;
  Sb: TStringBuilder;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position := AParams.GetValue('position') as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    Uri := TextDoc.GetValue('uri').Value;
    Path := FileFromUri(Uri);
    Line := StrToIntDef(Position.GetValue('line').Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);
    Ident := IdentifierAtPosition(Path, Line, Col);
    if Ident = '' then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    Symbols := FStore.FindSymbolsByExactName(Ident);
    if Length(Symbols) = 0 then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    // v0.16: try to enrich the hover with doc-comment content.
    // GetSymbolDoc returns a zeroed TParsedDoc with HasContent=False when
    // no row exists; in that case fall back to the legacy signature listing.
    Doc := FStore.GetSymbolDoc(Symbols[0].Id);
    if Doc.HasContent then
      MdValue := DRagLint.Hover.Renderer.RenderHoverMarkdown(Symbols[0], Doc)
    else
    begin
      Sb := TStringBuilder.Create;
      try
        Sb.AppendLine(Format('**%s** `%s`', [Ident, Symbols[0].Kind.ToText]));
        Sb.AppendLine('');
        for Sym in Symbols do
        begin
          Sb.AppendLine(Format('- `%s` - line %d', [Sym.QualifiedName,
            Sym.StartLine]));
          if Sym.Signature <> '' then
            Sb.AppendLine('    ' + Sym.Signature);
        end;
        // v0.19: enrich with type-at-position resolution when the identifier
        // is a reference (no doc comment found on the declaration).
        // LSP uses 0-based line/col; TTypeAtResolver uses 1-based.
        var TAResult := TTypeAtResolver.Resolve(
          FStore, Path, Line + 1, Col + 1);
        if TAResult.HasResolved and
           (TAResult.Resolved.QualifiedName <> Symbols[0].QualifiedName) then
        begin
          Sb.AppendLine('');
          Sb.AppendLine('## Type');
          Sb.AppendLine('');
          Sb.AppendLine(Format('Resolved: `%s`',
            [TAResult.Resolved.QualifiedName]));
          if TAResult.Resolved.Signature <> '' then
            Sb.AppendLine(Format('Signature: `%s`',
              [TAResult.Resolved.Signature]));
        end;
        MdValue := Sb.ToString;
      finally
        Sb.Free;
      end;
    end;
    HoverObj := TJSONObject.Create;
    Contents := TJSONObject.Create;
    Contents.AddPair('kind', 'markdown');
    Contents.AddPair('value', MdValue);
    HoverObj.AddPair('contents', Contents);
    Reply.AddPair('result', HoverObj);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleCompletion(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Reply, WrapObj: TJSONObject;
  TextDoc, Position: TJSONObject;
  Uri, Path: string;
  Line, Col: Integer;
  Items: TJSONArray;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      WrapObj := TJSONObject.Create;
      WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
      WrapObj.AddPair('items', TJSONArray.Create);
      Reply.AddPair('result', WrapObj);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position := AParams.GetValue('position') as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      WrapObj := TJSONObject.Create;
      WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
      WrapObj.AddPair('items', TJSONArray.Create);
      Reply.AddPair('result', WrapObj);
      SendMessage(Reply);
      Exit;
    end;
    Uri := TextDoc.GetValue('uri').Value;
    Path := FileFromUri(Uri);
    // LSP positions are 0-based; completion builder uses 1-based.
    Line := StrToIntDef(Position.GetValue('line').Value, 0) + 1;
    Col  := StrToIntDef(Position.GetValue('character').Value, 0) + 1;
    Items := TLspCompletion.BuildCompletionItems(FStore, Path, Line, Col);
    WrapObj := TJSONObject.Create;
    WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
    WrapObj.AddPair('items', Items);
    Reply.AddPair('result', WrapObj);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleSignatureHelp(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Reply: TJSONObject;
  TextDoc, Position: TJSONObject;
  Uri, Path: string;
  Line, Col: Integer;
  SigHelp: TJSONObject;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position := AParams.GetValue('position') as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    Uri := TextDoc.GetValue('uri').Value;
    Path := FileFromUri(Uri);
    // LSP positions are 0-based; signatureHelp builder uses 1-based.
    Line := StrToIntDef(Position.GetValue('line').Value, 0) + 1;
    Col  := StrToIntDef(Position.GetValue('character').Value, 0) + 1;
    SigHelp := TLspCompletion.BuildSignatureHelp(FStore, Path, Line, Col);
    if SigHelp <> nil then
      Reply.AddPair('result', SigHelp)
    else
      Reply.AddPair('result', TJSONNull.Create);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleDidOpenOrSave(const AParams: TJSONObject);
var
  TextDoc: TJSONObject;
  Uri, Path: string;
  Diags: TJSONArray;
  Notif, ParamsObj: TJSONObject;
begin
  if AParams = nil then Exit;
  TextDoc := AParams.GetValue('textDocument') as TJSONObject;
  if TextDoc = nil then Exit;
  Uri := TextDoc.GetValue('uri').Value;
  Path := FileFromUri(Uri);
  // v0.26: pass FStore so compiler_findings are merged into publishDiagnostics.
  Diags := TLspCompletion.BuildDiagnostics(EnsureLinter, Path, FStore);
  Notif := TJSONObject.Create;
  try
    Notif.AddPair('jsonrpc', '2.0');
    Notif.AddPair('method', 'textDocument/publishDiagnostics');
    ParamsObj := TJSONObject.Create;
    ParamsObj.AddPair('uri', Uri);
    ParamsObj.AddPair('diagnostics', Diags);
    Notif.AddPair('params', ParamsObj);
    SendRawNotification(Notif);
  finally
    Notif.Free;
  end;
end;

procedure TLSPServer.Run;
var
  Msg: TJSONObject;
  Method: string;
  Id: TJSONValue;
  Params: TJSONObject;
  ParamsVal: TJSONValue;
begin
  while not FShuttingDown do
  begin
    Msg := ReadMessage;
    if Msg = nil then Break;
    try
      Method := '';
      if Msg.GetValue('method') <> nil then
        Method := Msg.GetValue('method').Value;
      Id := Msg.GetValue('id');
      ParamsVal := Msg.GetValue('params');
      if ParamsVal is TJSONObject then
        Params := TJSONObject(ParamsVal)
      else
        Params := nil;

      if Method = 'initialize' then
        HandleInitialize(Id, Params)
      else if Method = 'initialized' then
        // notification, no response
      else if Method = 'shutdown' then
        HandleShutdown(Id)
      else if Method = 'exit' then
        Break
      else if Method = 'workspace/symbol' then
        HandleWorkspaceSymbol(Id, Params)
      else if Method = 'textDocument/definition' then
        HandleDefinition(Id, Params)
      else if Method = 'textDocument/references' then
        HandleReferences(Id, Params)
      else if Method = 'textDocument/hover' then
        HandleHover(Id, Params)
      else if Method = 'textDocument/completion' then
        HandleCompletion(Id, Params)
      else if Method = 'textDocument/signatureHelp' then
        HandleSignatureHelp(Id, Params)
      else if Method = 'textDocument/didOpen' then
        HandleDidOpenOrSave(Params)
      else if Method = 'textDocument/didSave' then
        HandleDidOpenOrSave(Params)
      else if (Id <> nil) and (Method <> '') then
        SendError(Id, -32601, 'method not found: ' + Method);
    finally
      Msg.Free;
    end;
  end;
end;

end.
