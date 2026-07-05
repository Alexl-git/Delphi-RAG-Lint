unit DRagLint.LSP.Server;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.NetEncoding
  , Winapi.Windows
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Core    .Encoding
  , DRagLint.Storage .SQLite
  , DRagLint.Parser  .Delphi13
  , DRagLint.Hover   .Renderer
  , DRagLint.Resolver.TypeAt
  , DRagLint.Lint    .Linter
  , DRagLint.LSP     .Completion
  ;

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
      FStore       : ISymbolStore        ; { v0.40.3: FStores[0]; kept for legacy single-store callers }
      FStores      : TArray<ISymbolStore>; { v0.40.3: every --db opened, queried + merged across all }
      FStdIn       : THandleStream       ;
      FLinter      : TLinter             ;
      FInitialized : Boolean             ;
      FShuttingDown: Boolean             ;
      function ReadMessage: TJSONObject  ;
      procedure SendMessage        (const AObj: TJSONObject);
      procedure SendRawNotification(const AObj: TJSONObject);
      procedure SendError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
      function FileFromUri(const AUri : string): string;
      function FileToUri  (const APath: string): string;
      procedure HandleInitialize(const AId: TJSONValue; const AParams: TJSONObject);
      procedure HandleShutdown(const AId: TJSONValue);
      procedure HandleWorkspaceSymbol(const AId: TJSONValue; const AParams: TJSONObject);
      procedure HandleDefinition     (const AId: TJSONValue; const AParams: TJSONObject);
      procedure HandleReferences     (const AId: TJSONValue; const AParams: TJSONObject);
      procedure HandleHover          (const AId: TJSONValue; const AParams: TJSONObject);
      procedure HandleCompletion     (const AId: TJSONValue; const AParams: TJSONObject);
      procedure HandleSignatureHelp  (const AId: TJSONValue; const AParams: TJSONObject);
      procedure HandleDidOpenOrSave(const AParams: TJSONObject);
      function LocationFromSymbol(const ASym: TSymbol   ): TJSONObject; overload;
      function LocationFromRef   (const ARef: TReference): TJSONObject; overload;
      { v0.40.3: explicit-store overloads — preferred for multi-DB queries
      so each Location URI resolves against the store that owns the row. }
      function LocationFromSymbol(const ASym: TSymbol   ; const AStore: ISymbolStore): TJSONObject; overload;
      function LocationFromRef   (const ARef: TReference; const AStore: ISymbolStore): TJSONObject; overload;
      // v0.7: reparse the file at APath and find the identifier text under
      // (ALine, ACol) - both 0-based (LSP convention). Returns empty string
      // if the file doesn't exist or the cursor isn't on an identifier.
      function IdentifierAtPosition(const APath: string; ALine, ACol: Integer): string;
      function EnsureLinter: TLinter                                                  ;
    public
      constructor Create(const ADbPath: string); overload;
      { v0.40.3: multi-DB constructor. Opens every path; missing paths are
      logged via stderr (LSP doesn't see them) and skipped. The first
      surviving store becomes FStore for legacy code paths. }
      constructor Create(const ADbPaths: TArray<string>); overload;
      destructor Destroy; override;
      procedure Run;
  end;

implementation

constructor TLSPServer.Create(const ADbPath: string);
begin
  Create(TArray<string>.Create(ADbPath));
end;

constructor TLSPServer.Create(const ADbPaths: TArray<string>);
var
  I   : Integer     ;
  Path: string      ;
  S   : ISymbolStore;
begin
  inherited Create;
  FStdIn:= THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
  FLinter:= nil;
  SetLength(FStores, 0);
  for I:= 0 to High(ADbPaths) do
  begin
    Path:= ADbPaths[I];
    if Path = '' then Continue;
    if not TFile.Exists(Path) then
    begin
      { Server protocol doesn't have a startup-message channel; write to
        stderr so the spawning plugin / shell can surface it. The plugin's
        DebugLog will capture this if redirected. }
      Writeln(ErrOutput, 'drag-lint LSP: db not found, skipping: ', Path);
      Continue;
    end;
    try
      S:= TSQLiteSymbolStore.Create(Path);
      S.Migrate;
      SetLength(FStores, Length(FStores) + 1);
      FStores[High(FStores)]:= S;
    except
      on E: Exception do Writeln(ErrOutput, 'drag-lint LSP: could not open ', Path, ': ', E.Message);
    end;
  end; // for
  if Length(FStores) > 0 then FStore:= FStores[0];
end; // constructor

destructor TLSPServer.Destroy;
begin
  FLinter.Free;
  FStdIn.Free;
  FStore:= nil;
  inherited;
end;

function TLSPServer.EnsureLinter: TLinter;
begin
  if FLinter = nil then FLinter:= TLinter.Create('');
  Result:= FLinter;
end;

function TLSPServer.ReadMessage: TJSONObject;
var
  Headers         : TStringList   ;
  Line            : TStringBuilder;
  Ch              : Byte          ;
  Header          : string        ;
  ContentLengthStr: string        ;
  ContentLength   : Integer       ;
  Body            : TBytes        ;
  ReadBytes       : Integer       ;
  Parsed          : TJSONValue    ;
  I               : Integer       ;
begin
  Result:= nil;
  Headers:= TStringList   .Create;
  Line   := TStringBuilder.Create;
  try
    // Read CRLF-terminated header lines until empty line.
    while True do
    begin
      if FStdIn.Read(Ch, 1) <> 1 then Exit;
      if Ch = 13 then // CR - expect LF next
      begin
        if FStdIn.Read(Ch, 1) <> 1 then Exit;
        if Ch = 10 then
        begin
          if Line.Length = 0 then Break; // empty line - end of headers
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
      else Line.Append(Char(Ch));
    end; // while
    ContentLength:= 0;
    for Header in Headers do
    begin
      if Header.StartsWith('Content-Length:', True) then
      begin
        ContentLengthStr:= Trim(Copy(Header, Length('Content-Length:') + 1, MaxInt));
        ContentLength:= StrToIntDef(ContentLengthStr, 0);
      end;
    end;
    if ContentLength <= 0 then Exit;
    SetLength(Body, ContentLength);
    ReadBytes:= 0;
    while ReadBytes < ContentLength do
    begin
      I:= FStdIn.Read(Body[ReadBytes], ContentLength - ReadBytes);
      if I <= 0 then Exit;
      Inc(ReadBytes, I);
    end;
    Parsed:= TJSONObject.ParseJSONValue(Body, 0);
    if Parsed is TJSONObject then Result:= TJSONObject(Parsed)
    else Parsed.Free;
  finally
    Line.Free;
    Headers.Free;
  end; // try
end; // function

procedure TLSPServer.SendMessage(const AObj: TJSONObject);
var
  Body        : string    ;
  BodyBytes   : TBytes    ;
  Header      : AnsiString;
  HeaderBytes : TBytes    ;
  StdOutHandle: THandle   ;
  Written     : DWORD     ;
begin
  Body:= AObj.ToJSON;
  BodyBytes:= TEncoding.UTF8.GetBytes(Body);
  Header:= AnsiString('Content-Length: ' + IntToStr(Length(BodyBytes)) + #13#10#13#10);
  SetLength(HeaderBytes, Length(Header));
  if Length(Header) > 0 then Move(Header[1], HeaderBytes[0], Length(Header));
  StdOutHandle:= GetStdHandle(STD_OUTPUT_HANDLE);
  if Length(HeaderBytes) > 0 then WriteFile(StdOutHandle, HeaderBytes[0], Length(HeaderBytes), Written, nil);
  if Length(BodyBytes  ) > 0 then WriteFile(StdOutHandle, BodyBytes  [0], Length(BodyBytes  ), Written, nil);
end;

// SendRawNotification sends a notification (no id) with Content-Length framing.
// Identical to SendMessage but semantically distinct — used for server-pushed
// notifications such as textDocument/publishDiagnostics.
procedure TLSPServer.SendRawNotification(const AObj: TJSONObject);
begin
  SendMessage(AObj);
end;

procedure TLSPServer.SendError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
var
  Obj: TJSONObject;
  Err: TJSONObject;
begin
  Obj:= TJSONObject.Create;
  try
    Obj.AddPair('jsonrpc', '2.0');
    if AId <> nil then Obj.AddPair('id', AId.Clone as TJSONValue)
    else Obj.AddPair('id', TJSONNull.Create);
    Err:= TJSONObject.Create;
    Err.AddPair('code', TJSONNumber.Create(ACode));
    Err.AddPair('message', AMessage);
    Obj.AddPair('error'  , Err     );
    SendMessage(Obj);
  finally
    Obj.Free;
  end;
end; // procedure

function TLSPServer.FileFromUri(const AUri: string): string;
var
  Decoded: string;
begin
  Result:= AUri;
  if Result.StartsWith('file:///') then Result:= Copy(Result, 9, MaxInt);
  Decoded:= TNetEncoding.URL.Decode(Result);
  Result:= StringReplace(Decoded, '/', '\', [rfReplaceAll]);
end;

function TLSPServer.FileToUri(const APath: string): string;
var
  Normalised: string;
  Encoded   : string;
begin
  Normalised:= StringReplace(APath, '\', '/', [rfReplaceAll]);
  Encoded:= TNetEncoding.URL.EncodePath(Normalised);
  // EncodePath preserves the leading slash if it exists, so we'd end up
  // with file://// for absolute Windows paths. Strip it before prepending.
  if Encoded.StartsWith('/') then Encoded:= Copy(Encoded, 2, MaxInt);
  Result:= 'file:///' + Encoded;
end;

function TLSPServer.LocationFromSymbol(const ASym: TSymbol): TJSONObject;
begin
  { Legacy single-store path: defer to the explicit-store overload using
    FStore (= FStores[0]). New multi-DB code paths should pass the
    originating store explicitly. }
  Result:= LocationFromSymbol(ASym, FStore);
end;

function TLSPServer.LocationFromRef(const ARef: TReference): TJSONObject;
begin
  Result:= LocationFromRef(ARef, FStore);
end;

function TLSPServer.LocationFromSymbol(const ASym: TSymbol; const AStore: ISymbolStore): TJSONObject;
var
  Range : TJSONObject;
  Start : TJSONObject;
  EndPos: TJSONObject;
  Path  : string     ;
begin
  Result:= TJSONObject.Create;
  if AStore <> nil then Path:= AStore.GetFilePath(ASym.FileId)
  else Path:= '';
  Result.AddPair('uri', FileToUri(Path));
  Range:= TJSONObject.Create;
  Start:= TJSONObject.Create;
  // LSP positions are 0-based; our DB stores 1-based.
  Start.AddPair('line'     , TJSONNumber.Create(ASym.StartLine - 1));
  Start.AddPair('character', TJSONNumber.Create(ASym.StartCol  - 1));
  EndPos:= TJSONObject.Create;
  EndPos.AddPair('line'     , TJSONNumber.Create(ASym.EndLine - 1));
  EndPos.AddPair('character', TJSONNumber.Create(ASym.EndCol  - 1));
  Range .AddPair('start', Start );
  Range .AddPair('end'  , EndPos);
  Result.AddPair('range', Range );
end; // function

function TLSPServer.LocationFromRef(const ARef: TReference; const AStore: ISymbolStore): TJSONObject;
var
  Range : TJSONObject;
  Start : TJSONObject;
  EndPos: TJSONObject;
  Path  : string     ;
begin
  Result:= TJSONObject.Create;
  if AStore <> nil then Path:= AStore.GetFilePath(ARef.FileId)
  else Path:= '';
  Result.AddPair('uri', FileToUri(Path));
  Range:= TJSONObject.Create;
  Start:= TJSONObject.Create;
  Start.AddPair('line'     , TJSONNumber.Create(ARef.StartLine - 1));
  Start.AddPair('character', TJSONNumber.Create(ARef.StartCol  - 1));
  EndPos:= TJSONObject.Create;
  EndPos.AddPair('line'     , TJSONNumber.Create(ARef.EndLine - 1));
  EndPos.AddPair('character', TJSONNumber.Create(ARef.EndCol  - 1));
  Range .AddPair('start', Start );
  Range .AddPair('end'  , EndPos);
  Result.AddPair('range', Range );
end; // function

procedure TLSPServer.HandleInitialize(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply                 : TJSONObject;
  ResObj                : TJSONObject;
  Caps                  : TJSONObject;
  Info                  : TJSONObject;
  CompProvider          : TJSONObject;
  SigProvider           : TJSONObject;
  TriggerCharsCompletion: TJSONArray ;
  TriggerCharsSig       : TJSONArray ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    ResObj:= TJSONObject.Create;
    Caps  := TJSONObject.Create;
    Caps.AddPair('definitionProvider'     , TJSONBool.Create(True));
    Caps.AddPair('referencesProvider'     , TJSONBool.Create(True));
    Caps.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
    Caps.AddPair('hoverProvider'          , TJSONBool.Create(True));
    // v0.20: completion provider
    CompProvider          := TJSONObject.Create;
    TriggerCharsCompletion:= TJSONArray .Create;
    TriggerCharsCompletion.AddElement(TJSONString.Create('.'));
    TriggerCharsCompletion.AddElement(TJSONString.Create('('));
    TriggerCharsCompletion.AddElement(TJSONString.Create(','));
    CompProvider.AddPair('triggerCharacters', TriggerCharsCompletion);
    CompProvider.AddPair('resolveProvider', TJSONBool.Create(False));
    Caps.AddPair('completionProvider', CompProvider);
    // v0.20: signatureHelp provider
    SigProvider    := TJSONObject.Create;
    TriggerCharsSig:= TJSONArray .Create;
    TriggerCharsSig.AddElement(TJSONString.Create('('));
    TriggerCharsSig.AddElement(TJSONString.Create(','));
    SigProvider.AddPair('triggerCharacters'    , TriggerCharsSig);
    Caps       .AddPair('signatureHelpProvider', SigProvider    );
    ResObj     .AddPair('capabilities'         , Caps           );
    Info:= TJSONObject.Create;
    Info  .AddPair('name'      , 'drag-lint LSP');
    Info  .AddPair('version'   , '0.40.5-alpha' );
    ResObj.AddPair('serverInfo', Info           );
    Reply .AddPair('result'    , ResObj         );
    SendMessage(Reply);
    FInitialized:= True;
  finally
    Reply.Free;
  end; // try
end; // procedure

function ContainsPosition(const ANode: TTSNode; ALine, ACol: Integer): Boolean;
var
  Sp: TTSPoint;
  Ep: TTSPoint;
begin
  Sp:= ANode.StartPoint;
  Ep:= ANode.EndPoint;
  // Tree-sitter rows/cols are 0-based, matching LSP.
  if (ALine < Integer(Sp.row)) or (ALine > Integer(Ep.row)) then Exit(False);
  if (ALine = Integer(Sp.row)) and (ACol < Integer(Sp.column)) then Exit(False);
  // EndPoint is exclusive - cursor right at the end is past the token.
  if (ALine = Integer(Ep.row)) and (ACol >= Integer(Ep.column)) then Exit(False);
  Result:= True;
end;

function FindSmallestNamedAt(const ANode: TTSNode; ALine, ACol: Integer): TTSNode;
var
  I    : Integer;
  Child: TTSNode;
  Hit  : TTSNode;
begin
  Result:= Default(TTSNode);
  if ANode.IsNull then Exit;
  if not ContainsPosition(ANode, ALine, ACol) then Exit;
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(I);
    if ContainsPosition(Child, ALine, ACol) then
    begin
      Hit:= FindSmallestNamedAt(Child, ALine, ACol);
      if not Hit.IsNull then Exit(Hit);
    end;
  end;
  Result:= ANode;
end; // function

function NodeTextLocal(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx: Integer;
  EndIdx  : Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

function TLSPServer.IdentifierAtPosition(const APath: string; ALine, ACol: Integer): string;
var
  Parser: TTSParser;
  Tree  : TTSTree  ;
  Source: TBytes   ;
  Node  : TTSNode  ;
begin
  Result:= '';
  if not TFile.Exists(APath) then Exit;
  // v0.86 (Task 3): transcode ANSI/UTF-16 sources to valid UTF-8 before the
  // parse/slice pipeline (both assume UTF-8); a valid CP1252 file (SOFTWID
  // class) errored here otherwise.
  Source:= EnsureUtf8Bytes(TFile.ReadAllBytes(APath));
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes var Remaining: Integer; begin Remaining:= Length(Source)
        - Integer(AByteIndex); if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end; SetLength(Result, Remaining); Move(Source[AByteIndex], Result[0],
          Remaining); ABytesRead:= Remaining; end, TTSInputEncoding.TSInputEncodingUTF8);

    Node:= FindSmallestNamedAt(Tree.RootNode, ALine, ACol);
    if Node.IsNull then Exit;
    // Prefer an identifier-shaped node. If the smallest enclosing is e.g.
    // a `genericDot` (qualified name like Foo.Bar), drill into its rhs.
    if Node.NodeType = 'genericDot' then
    begin
      var Rhs:= Node.ChildByField('rhs');
      if (not Rhs.IsNull) and ContainsPosition(Rhs, ALine, ACol) then Node:= Rhs;
    end
    else if Node.NodeType = 'exprDot' then
    begin
      var Rhs:= Node.ChildByField('rhs');
      if (not Rhs.IsNull) and ContainsPosition(Rhs, ALine, ACol) then Node:= Rhs;
    end;
    if (Node.NodeType <> 'identifier') and (Node.NodeType <> 'moduleName') then
    begin
      // Try to find an identifier descendant covering the cursor.
      var ChildIt:= Node;
      while (ChildIt.NamedChildCount > 0) and (ChildIt.NodeType <> 'identifier') do
      begin
        var Found:= False;
        for var I:= 0 to ChildIt.NamedChildCount - 1 do
        begin
          var C:= ChildIt.NamedChild(I);
          if ContainsPosition(C, ALine, ACol) then
          begin
            ChildIt:= C;
            Found  := True;
            Break;
          end;
        end;
        if not Found then Break;
      end;
      Node:= ChildIt;
    end; // if
    Result:= Trim(NodeTextLocal(Node, Source));
  finally
    Tree.Free;
    Parser.Free;
  end; // try
end; // function

procedure TLSPServer.HandleShutdown(const AId: TJSONValue);
var
  Reply: TJSONObject;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    Reply.AddPair('result', TJSONNull.Create);
    SendMessage(Reply);
    FShuttingDown:= True;
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleWorkspaceSymbol(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject    ;
  Arr     : TJSONArray     ;
  QueryStr: string         ;
  Symbols : TArray<TSymbol>;
  Sym     : TSymbol        ;
  SymObj  : TJSONObject    ;
  Loc     : TJSONObject    ;
  StIdx   : Integer        ;
  StCur   : ISymbolStore   ;
begin
  Reply:= TJSONObject.Create;
  Arr  := TJSONArray .Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if Length(FStores) = 0 then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    QueryStr:= '';
    if (AParams <> nil) and (AParams.GetValue('query') <> nil) then QueryStr:= AParams.GetValue('query').Value;
    if QueryStr = '' then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;

    { v0.40.3: iterate every store, merge results. For each store, prefer
      exact-name matches; fall back to fuzzy when exact returns nothing.
      Per-store fallback is intentional — if project DB has an exact hit
      we don't want library DB's fuzzy noise diluting the result. }
    for StIdx:= 0 to High(FStores) do
    begin
      StCur:= FStores[StIdx];
      Symbols:= StCur.FindSymbolsByExactName(QueryStr);
      if Length(Symbols) = 0 then Symbols:= StCur.FindSymbolsFuzzy(QueryStr, 50);
      for Sym in Symbols do
      begin
        SymObj:= TJSONObject.Create;
        SymObj.AddPair('name', Sym.Name);
        var Kind: Integer;
        case Sym.Kind of
          skClass     : Kind:= 5;
          skInterface : Kind:= 11;
          skRecord    : Kind:= 23;
          skEnum      : Kind:= 10;
          skEnumValue : Kind:= 22;
          skMethod, skConstructor, skDestructor: Kind:= 6 ;
          skProcedure, skFunction              : Kind:= 12;
          skProperty  : Kind:= 7;
          skField     : Kind:= 8;
          skVarDecl   : Kind:= 13;
          skConstDecl : Kind:= 14;
          skUnit, skPackage, skProgram         : Kind:= 2 ;
          skForm      : Kind:= 5;
          skComponent : Kind:= 8;
          else Kind:= 1;
        end; // case
        SymObj.AddPair('kind', TJSONNumber.Create(Kind));
        SymObj.AddPair('containerName', Sym.QualifiedName);
        Loc:= LocationFromSymbol(Sym, StCur);
        SymObj.AddPair('location', Loc);
        Arr.AddElement(SymObj);
      end; // for
    end; // for
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleDefinition(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject    ;
  Arr     : TJSONArray     ;
  TextDoc : TJSONObject    ;
  Position: TJSONObject    ;
  Uri     : string         ;
  Path    : string         ;
  Ident   : string         ;
  Line    : Integer        ;
  Col     : Integer        ;
  Symbols : TArray<TSymbol>;
  Sym     : TSymbol        ;
begin
  Reply:= TJSONObject.Create;
  Arr  := TJSONArray .Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (Length(FStores) = 0) or (AParams = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);

    Ident:= IdentifierAtPosition(Path, Line, Col);
    if Ident <> '' then
    begin
      { v0.40.3: iterate every store, accumulate definitions. }
      for var StIdx:= 0 to High(FStores) do
      begin
        Symbols:= FStores[StIdx].FindSymbolsByExactName(Ident);
        for Sym in Symbols do Arr.AddElement(LocationFromSymbol(Sym, FStores[StIdx]));
      end;
    end;
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleReferences(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply      : TJSONObject       ;
  Arr        : TJSONArray        ;
  TextDoc    : TJSONObject       ;
  Position   : TJSONObject       ;
  Context    : TJSONObject       ;
  Uri        : string            ;
  Path       : string            ;
  Ident      : string            ;
  Line       : Integer           ;
  Col        : Integer           ;
  Refs       : TArray<TReference>;
  Symbols    : TArray<TSymbol>   ;
  IncludeDecl: Boolean           ;
  R          : TReference        ;
  Sym        : TSymbol           ;
begin
  Reply:= TJSONObject.Create;
  Arr  := TJSONArray .Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (Length(FStores) = 0) or (AParams = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);

    IncludeDecl:= True;
    Context:= AParams.GetValue('context') as TJSONObject;
    if Context <> nil then
    begin
      var IncDeclVal:= Context.GetValue('includeDeclaration');
      if IncDeclVal is TJSONBool then IncludeDecl:= TJSONBool(IncDeclVal).AsBoolean;
    end;

    Ident:= IdentifierAtPosition(Path, Line, Col);
    if Ident <> '' then
    begin
      { v0.40.3: iterate every store for both callers and declarations. }
      for var StIdx:= 0 to High(FStores) do
      begin
        Refs:= FStores[StIdx].FindCallersByName(Ident);
        for R in Refs do Arr.AddElement(LocationFromRef(R, FStores[StIdx]));
        if IncludeDecl then
        begin
          Symbols:= FStores[StIdx].FindSymbolsByExactName(Ident);
          for Sym in Symbols do Arr.AddElement(LocationFromSymbol(Sym, FStores[StIdx]));
        end;
      end;
    end;
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

// v0.42: render a symbol as a Code-Insight-style declaration line, e.g.
//   function TShape.Area: Double          (proc-likes: sig has params+return)
//   constructor Create(const AName: string)
//   property Name: string                 (prop/field/const/var: sig is type)
//   class TShape                          (containers: no signature)
// Signature already carries the leading '(' or ': ' for proc-likes, so we
// concatenate directly; for type-valued kinds we insert ': ' before the type.
function DeclLineFor(const ASym: TSymbol): string;
var
  Keyword: string;
  Sig    : string;
begin
  Sig:= ASym.Signature;
  case ASym.Kind of
    skFunction   : Keyword:= 'function';
    skProcedure  : Keyword:= 'procedure';
    skConstructor: Keyword:= 'constructor';
    skDestructor : Keyword:= 'destructor';
    skMethod     : { class/interface methods: tell function from procedure by whether the
        signature carries a return type. }
      if (Sig <> '') and ((Sig[1] = ':') or (Pos('): ', Sig) > 0)) then Keyword:= 'function'
    else Keyword:= 'procedure';
    skProperty : Keyword:= 'property';
    skField    : Keyword:= 'var';
    skVarDecl  : Keyword:= 'var';
    skConstDecl: Keyword:= 'const';
    else Keyword:= ASym.Kind.ToText;
  end; // case

  case ASym.Kind of
    skFunction, skProcedure, skConstructor, skDestructor, skMethod:
      // Sig is '(args): Ret' or ': Ret' or '(args)' or '' -- concat directly.
      Result:= Format('%s %s%s', [Keyword, ASym.Name, Sig]);
    skProperty, skField, skVarDecl, skConstDecl: if Sig <> '' then Result:= Format('%s %s: %s', [Keyword, ASym.Name, Sig])
    else Result:= Format('%s %s', [Keyword, ASym.Name]);
    else Result:= Format('%s %s', [Keyword, ASym.Name]);
  end;
end; // function

// v0.46 hover polish. Two passes over the candidate symbols:
//   1. De-duplicate by (QualifiedName, FileId, StartLine). A doubled index (the
//      pre-0.46 accumulate bug) otherwise renders a phantom "N overloads".
//   2. If any source declaration (not skForm/skComponent) is present, drop the
//      DFM component/form entries: a published field in the .pas and its
//      generated DFM object describe the same thing, and the source declaration
//      carries the real declared type (what the IDE shows on hover).
// The candidate list is small (capped at 50 upstream), so a linear dedup is fine.
function DedupAndPreferSource(const ASyms: TArray<TSymbol>): TArray<TSymbol>;
  function IsSourceKind(AKind: TSymbolKind): Boolean                        ;
  begin
    Result:= not (AKind in [skForm, skComponent]);
  end;
var
  I        : Integer        ;
  J        : Integer        ;
  Dup      : Boolean        ;
  HasSource: Boolean        ;
  Deduped  : TArray<TSymbol>;
begin
  SetLength(Deduped, 0);
  HasSource:= False;
  for I:= 0 to High(ASyms) do
  begin
    Dup:= False;
    for J:= 0 to High(Deduped) do
      if (Deduped[J].QualifiedName = ASyms[I].QualifiedName) and (Deduped[J].FileId = ASyms[I].FileId) and (Deduped[J].StartLine = ASyms[I].StartLine) then
      begin
        Dup:= True;
        Break;
      end;
    if Dup then Continue;
    SetLength(Deduped, Length(Deduped) + 1);
    Deduped[High(Deduped)]:= ASyms[I];
    if IsSourceKind(ASyms[I].Kind) then HasSource:= True;
  end; // for

  if not HasSource then Exit(Deduped);

  // A source declaration is present -> drop the generated DFM components.
  SetLength(Result, 0);
  for I:= 0 to High(Deduped) do
    if IsSourceKind(Deduped[I].Kind) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)]:= Deduped[I];
    end;
end; // begin

// v0.46: compiler intrinsics that are NOT real indexed symbols. Hovering one
// (e.g. `Assigned(X)`) otherwise matched a random library symbol of the same
// name (FMX.Graphics.TCanvasSaveState.Assigned, a property) because the project
// DB has no such symbol and the search fell through to the library DB.
// IntrinsicSignature returns the System-unit signature so the hover can show
// the full declaration like the IDE; '' = not a recognized intrinsic. The set
// is deliberately RESTRICTED to names virtually never user-defined (so a real
// method called Copy/Insert/Delete/etc. is NOT mislabeled).
function IntrinsicSignature(const AName: string): string;
begin
  if SameText(AName, 'Assigned') then Result:= 'function System.Assigned(var P): Boolean'
  else if SameText(AName, 'Length'   ) then Result:= 'function System.Length(const S): Integer'
  else if SameText(AName, 'SetLength') then Result:= 'procedure System.SetLength(var S; NewLength: Integer)'
  else if SameText(AName, 'Inc'      ) then Result:= 'procedure System.Inc(var X [; N: Integer])'
  else if SameText(AName, 'Dec'      ) then Result:= 'procedure System.Dec(var X [; N: Integer])'
  else if SameText(AName, 'Ord'      ) then Result:= 'function System.Ord(X): Integer'
  else if SameText(AName, 'Chr'      ) then Result:= 'function System.Chr(B: Byte): AnsiChar'
  else if SameText(AName, 'High'     ) then Result:= 'function System.High(X): <ordinal>'
  else if SameText(AName, 'Low'      ) then Result:= 'function System.Low(X): <ordinal>'
  else if SameText(AName, 'SizeOf'   ) then Result:= 'function System.SizeOf(X): Integer'
  else if SameText(AName, 'TypeInfo' ) then Result:= 'function System.TypeInfo(X): Pointer'
  else if SameText(AName, 'Succ'     ) then Result:= 'function System.Succ(X): <ordinal>'
  else if SameText(AName, 'Pred'     ) then Result:= 'function System.Pred(X): <ordinal>'
  else if SameText(AName, 'Trunc'    ) then Result:= 'function System.Trunc(X: Extended): Int64'
  else if SameText(AName, 'Round'    ) then Result:= 'function System.Round(X: Extended): Int64'
  else if SameText(AName, 'Frac'     ) then Result:= 'function System.Frac(X: Extended): Extended'
  else if SameText(AName, 'Abs'      ) then Result:= 'function System.Abs(X): <numeric>'
  else if SameText(AName, 'Sqr'      ) then Result:= 'function System.Sqr(X): <numeric>'
  else if SameText(AName, 'Sqrt'     ) then Result:= 'function System.Sqrt(X: Extended): Extended'
  else if SameText(AName, 'Exit'     ) then Result:= 'procedure System.Exit [(Result)]'
  else if SameText(AName, 'Break'    ) then Result:= 'procedure System.Break'
  else if SameText(AName, 'Continue' ) then Result:= 'procedure System.Continue'
  else if SameText(AName, 'Halt'     ) then Result:= 'procedure System.Halt [(ExitCode: Integer)]'
  else if SameText(AName, 'Assert'   ) then Result:= 'procedure System.Assert(expr: Boolean [; const msg: string])'
  else Result:= '';
end; // function

function IsBuiltinIntrinsic(const AName: string): Boolean;
begin
  Result:= IntrinsicSignature(AName) <> '';
end;

procedure TLSPServer.HandleHover(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject    ;
  HoverObj: TJSONObject    ;
  Contents: TJSONObject    ;
  TextDoc : TJSONObject    ;
  Position: TJSONObject    ;
  Uri     : string         ;
  Path    : string         ;
  Ident   : string         ;
  MdValue : string         ;
  Line    : Integer        ;
  Col     : Integer        ;
  Symbols : TArray<TSymbol>;
  Sym     : TSymbol        ;
  Doc     : TParsedDoc     ;
  Sb      : TStringBuilder ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (Length(FStores) = 0) or (AParams = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);
    Ident:= IdentifierAtPosition(Path, Line, Col);
    if Ident = '' then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    { v0.46: a compiler intrinsic has no real indexed symbol -- show it as a
      built-in with its System-unit signature (like the IDE) instead of falling
      through to a wrong library match. The "- `System.X` - line 1" row keeps the
      clickable shape the popup parses (opens System.pas if on the source path). }
    if IsBuiltinIntrinsic(Ident) then
    begin
      MdValue:= Format(
        '**%s** `intrinsic`'#10#10 + '- `System.%s` - line 1'#10 + '    %s'#10#10 + '_Delphi compiler built-in (System unit)._', [Ident, Ident, IntrinsicSignature(Ident)]);
      HoverObj:= TJSONObject.Create;
      Contents:= TJSONObject.Create;
      Contents.AddPair('kind'    , 'markdown');
      Contents.AddPair('value'   , MdValue   );
      HoverObj.AddPair('contents', Contents  );
      Reply   .AddPair('result'  , HoverObj  );
      SendMessage(Reply);
      Exit;
    end;
    { v0.40.3: hover returns the FIRST hit across stores in declared order
      (project DB before library DB, per CLI arg ordering). For multi-hit
      cases the user can use Find Usages to see all stores' results. }
    Symbols:= nil;
    var HitStore: ISymbolStore:= nil;
    for var StIdx:= 0 to High(FStores) do
    begin
      Symbols:= FStores[StIdx].FindSymbolsByExactName(Ident);
      if Length(Symbols) > 0 then
      begin
        HitStore:= FStores[StIdx];
        Break;
      end;
    end;
    if (Length(Symbols) = 0) or (HitStore = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    // v0.16: try to enrich the hover with doc-comment content.
    // GetSymbolDoc returns a zeroed TParsedDoc with HasContent=False when
    // no row exists; in that case fall back to the legacy signature listing.
    Doc:= HitStore.GetSymbolDoc(Symbols[0].Id);
    if Doc.HasContent then MdValue:= DRagLint.Hover.Renderer.RenderHoverMarkdown(Symbols[0], Doc)
    else
    begin
      Sb:= TStringBuilder.Create;
      try
        { v0.40.8f: try to resolve the actual type at cursor first. If we
          can, narrow the candidate list to symbols on THAT type (else a
          common member like DataBinding lists every class that has one). }
        var TAResult:= TTypeAtResolver.Resolve( HitStore, Path, Line + 1, Col + 1);

        var Filtered: TArray<TSymbol>;
        SetLength(Filtered, 0);
        var ResolvedQName: string:= '';
        if TAResult.HasResolved then ResolvedQName:= TAResult.Resolved.QualifiedName;

        if ResolvedQName <> '' then
        begin
          { Keep only candidates whose QualifiedName matches the resolved
            symbol exactly, or whose QualifiedName begins with the resolved
            qname plus '.' (member access on a record/interface). }
          for Sym in Symbols do
          begin
            if (Sym.QualifiedName = ResolvedQName) or (Pos(ResolvedQName + '.', Sym.QualifiedName) = 1) then
            begin
              SetLength(Filtered, Length(Filtered) + 1);
              Filtered[High(Filtered)]:= Sym;
            end;
          end;
        end;

        { v0.46: owner-type / unit fallback. When the exact-type filter found
          nothing because the member is INHERITED (resolved to the owner type,
          not the member itself), narrow by the resolved type's UNIT prefix.
          Turns ~50 same-named properties across unrelated types into the few
          in the right library unit (e.g. AButton: TdxBarButton -> only dxBar). }
        if (Length(Filtered) = 0) and (ResolvedQName <> '') then
        begin
          var DotP: Integer:= Pos('.', ResolvedQName);
          if DotP > 1 then
          begin
            var UnitPfx: string:= Copy(ResolvedQName, 1, DotP); { incl. '.' }
            for Sym in Symbols do
              if Pos(UnitPfx, Sym.QualifiedName) = 1 then
              begin
                SetLength(Filtered, Length(Filtered) + 1);
                Filtered[High(Filtered)]:= Sym;
              end;
          end;
        end;

        { Fallback: if filtering yielded nothing (no LHS info, or qname
          mismatch across stores), keep the original list capped at 50 so
          mega-common members like DataBinding don't blow up the popup. }
        if Length(Filtered) = 0 then
        begin
          if Length(Symbols) <= 50 then Filtered:= Symbols
          else
          begin
            SetLength(Filtered, 50);
            for var I:= 0 to 49 do Filtered[I]:= Symbols[I];
          end;
        end;

        { v0.46 hover polish: de-duplicate candidates and prefer the source
          declaration over a generated DFM component (see DedupAndPreferSource),
          so a published field shows once with its real declared type instead of
          a phantom "2 overloads" (field + DFM object, possibly doubled by a
          stale index). The mislabeled "_Resolved type: <qname>_" line is gone --
          the indented declaration line below already shows "name: Type" exactly
          as the IDE does. }
        Filtered:= DedupAndPreferSource(Filtered);

        Sb.AppendLine(Format('**%s** `%s`', [Ident, Filtered[0].Kind.ToText]));
        Sb.AppendLine('');
        { v0.42: render each candidate (every overload) as a Code-Insight-style
          declaration. Signature now carries the full param list + return type,
          e.g. '(const A: Integer): Boolean'. The "- `qname` - line N" shape is
          preserved exactly so the popup's single-click navigation still parses
          the qname + line; the declaration line is shown indented underneath. }
        if Length(Filtered) > 1 then Sb.AppendLine(Format('_%d overloads:_', [Length(Filtered)]));
        for Sym in Filtered do
        begin
          Sb.AppendLine(Format('- `%s` - line %d', [Sym.QualifiedName, Sym.StartLine]));
          Sb.AppendLine('    ' + DeclLineFor(Sym));
          { v0.43: break the signature into an IDE-style Parameters block
            (name + type per line, + Returns). Only for a focused candidate
            set so a 50-hit common member doesn't explode the popup. }
          if Length(Filtered) <= 5 then
          begin
            var ParamBlock: string:= DRagLint.Hover.Renderer.RenderSignatureParamsMarkdown(Sym.Signature);
            if ParamBlock <> '' then
            begin
              Sb.AppendLine(''        );
              Sb.Append    (ParamBlock);
            end;
          end;
        end;
        { Partial-list note: only when the original hit set actually exceeded the
          50-candidate cap (the DataBinding case), NOT when dedup/prefer-source
          shrank the list -- otherwise a field+DFM pair would read "showing 1 of 2". }
        if (Length(Symbols) > 50) and (ResolvedQName = '') then
          Sb.AppendLine(Format(#10'_(showing %d of %d -- use Find Usages for full list)_', [Length(Filtered), Length(Symbols)]));

        MdValue:= Sb.ToString;
      finally
        Sb.Free;
      end; // try
    end; // else
    HoverObj:= TJSONObject.Create;
    Contents:= TJSONObject.Create;
    Contents.AddPair('kind'    , 'markdown');
    Contents.AddPair('value'   , MdValue   );
    HoverObj.AddPair('contents', Contents  );
    Reply   .AddPair('result'  , HoverObj  );
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleCompletion(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject;
  WrapObj : TJSONObject;
  TextDoc : TJSONObject;
  Position: TJSONObject;
  Uri     : string     ;
  Path    : string     ;
  Line    : Integer    ;
  Col     : Integer    ;
  Items   : TJSONArray ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      WrapObj:= TJSONObject.Create;
      WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
      WrapObj.AddPair('items', TJSONArray.Create);
      Reply.AddPair('result', WrapObj);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      WrapObj:= TJSONObject.Create;
      WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
      WrapObj.AddPair('items', TJSONArray.Create);
      Reply.AddPair('result', WrapObj);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    // LSP positions are 0-based; completion builder uses 1-based.
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0) + 1;
    Col := StrToIntDef(Position.GetValue('character').Value, 0) + 1;
    Items:= TLspCompletion.BuildCompletionItems(FStore, Path, Line, Col);
    WrapObj:= TJSONObject.Create;
    WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
    WrapObj.AddPair('items' , Items  );
    Reply  .AddPair('result', WrapObj);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleSignatureHelp(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject;
  TextDoc : TJSONObject;
  Position: TJSONObject;
  Uri     : string     ;
  Path    : string     ;
  Line    : Integer    ;
  Col     : Integer    ;
  SigHelp : TJSONObject;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    // LSP positions are 0-based; signatureHelp builder uses 1-based.
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0) + 1;
    Col := StrToIntDef(Position.GetValue('character').Value, 0) + 1;
    SigHelp:= TLspCompletion.BuildSignatureHelp(FStore, Path, Line, Col);
    if SigHelp <> nil then Reply.AddPair('result', SigHelp)
    else Reply.AddPair('result', TJSONNull.Create);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleDidOpenOrSave(const AParams: TJSONObject);
var
  TextDoc  : TJSONObject;
  Uri      : string     ;
  Path     : string     ;
  Diags    : TJSONArray ;
  Notif    : TJSONObject;
  ParamsObj: TJSONObject;
begin
  if AParams = nil then Exit;
  TextDoc:= AParams.GetValue('textDocument') as TJSONObject;
  if TextDoc = nil then Exit;
  Uri:= TextDoc.GetValue('uri').Value;
  Path:= FileFromUri(Uri);
  // v0.26: pass FStore so compiler_findings are merged into publishDiagnostics.
  Diags:= TLspCompletion.BuildDiagnostics(EnsureLinter, Path, FStore);
  Notif:= TJSONObject.Create;
  try
    Notif.AddPair('jsonrpc', '2.0'                            );
    Notif.AddPair('method' , 'textDocument/publishDiagnostics');
    ParamsObj:= TJSONObject.Create;
    ParamsObj.AddPair('uri'        , Uri      );
    ParamsObj.AddPair('diagnostics', Diags    );
    Notif    .AddPair('params'     , ParamsObj);
    SendRawNotification(Notif);
  finally
    Notif.Free;
  end;
end; // procedure

procedure TLSPServer.Run;
var
  Msg      : TJSONObject;
  Method   : string     ;
  Id       : TJSONValue ;
  Params   : TJSONObject;
  ParamsVal: TJSONValue ;
begin
  while not FShuttingDown do
  begin
    Msg:= ReadMessage;
    if Msg = nil then Break;
    try
      Method:= '';
      if Msg.GetValue('method') <> nil then Method:= Msg.GetValue('method').Value;
      Id       := Msg.GetValue('id'    );
      ParamsVal:= Msg.GetValue('params');
      if ParamsVal is TJSONObject then Params:= TJSONObject(ParamsVal)
      else Params:= nil;

      if Method      = 'initialize' then HandleInitialize(Id, Params)
      else if Method = 'initialized' then
        // notification, no response
      else if Method = 'shutdown' then HandleShutdown(Id)
      else if Method = 'exit' then Break
      else if Method = 'workspace/symbol' then HandleWorkspaceSymbol(Id, Params)
      else if Method = 'textDocument/definition' then HandleDefinition(Id, Params)
      else if Method = 'textDocument/references' then HandleReferences(Id, Params)
      else if Method = 'textDocument/hover' then HandleHover(Id, Params)
      else if Method = 'textDocument/completion' then HandleCompletion(Id, Params)
      else if Method = 'textDocument/signatureHelp' then HandleSignatureHelp(Id, Params)
      else if Method = 'textDocument/didOpen' then HandleDidOpenOrSave(Params)
      else if Method = 'textDocument/didSave' then HandleDidOpenOrSave(Params)
      else if (Id <> nil) and (Method <> '') then SendError(Id, -32601, 'method not found: ' + Method);
    finally
      Msg.Free;
    end; // try
  end; // while
end; // procedure

end.
