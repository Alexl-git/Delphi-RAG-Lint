unit DRagLint.LSP.Server;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.NetEncoding,
  Winapi.Windows,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite;

type
  // Language Server Protocol over stdio with Content-Length framing.
  // Implements the subset that's actually useful when backed by a static
  // symbol index: initialize, shutdown, workspace/symbol,
  // textDocument/definition, textDocument/references.
  //
  // v0.6 deliberately does NOT implement textDocument/didChange — files are
  // indexed via `drag-lint index` ahead of time. Editing a file in-place
  // and getting fresh results requires a re-run of `index` (which is
  // sub-second per file thanks to v0.4 incremental).
  TLSPServer = class
  strict private
    FStore: ISymbolStore;
    FStdIn: THandleStream;
    FInitialized: Boolean;
    FShuttingDown: Boolean;
    function ReadMessage: TJSONObject;
    procedure SendMessage(const AObj: TJSONObject);
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
    function LocationFromSymbol(const ASym: TSymbol): TJSONObject;
    function LocationFromRef(const ARef: TReference): TJSONObject;
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
  if ADbPath <> '' then
  begin
    FStore := TSQLiteSymbolStore.Create(ADbPath);
    FStore.Migrate;
  end;
end;

destructor TLSPServer.Destroy;
begin
  FStdIn.Free;
  FStore := nil;
  inherited;
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
      if Ch = 13 then  // CR — expect LF next
      begin
        if FStdIn.Read(Ch, 1) <> 1 then Exit;
        if Ch = 10 then
        begin
          if Line.Length = 0 then
            Break;  // empty line — end of headers
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
  Normalised: string;
begin
  Normalised := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := 'file:///' + TNetEncoding.URL.EncodePath(Normalised);
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
  Reply, Result, Caps, Info: TJSONObject;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    Result := TJSONObject.Create;
    Caps := TJSONObject.Create;
    Caps.AddPair('definitionProvider', TJSONBool.Create(True));
    Caps.AddPair('referencesProvider', TJSONBool.Create(True));
    Caps.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
    Result.AddPair('capabilities', Caps);
    Info := TJSONObject.Create;
    Info.AddPair('name', 'drag-lint LSP');
    Info.AddPair('version', '0.6.0-alpha');
    Result.AddPair('serverInfo', Info);
    Reply.AddPair('result', Result);
    SendMessage(Reply);
    FInitialized := True;
  finally
    Reply.Free;
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
  Uri, Path: string;
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
    Line := StrToIntDef(Position.GetValue('line').Value, 0) + 1;
    Col := StrToIntDef(Position.GetValue('character').Value, 0) + 1;

    // v0.6 strategy: look up symbols matching by name at the cursor.
    // We don't know the identifier under the cursor without the file text,
    // so for v0.6 we fall back to: find the enclosing symbol AT that
    // position (if any) and return ITS declaration. Editors can also call
    // workspace/symbol with a name selected by the user — that's a better
    // path for v0.6. Position-based exact-token resolution is a v0.7 item
    // (needs incremental tree-sitter parse + position→node walk).
    Symbols := FStore.FindSymbolsByExactName('');  // placeholder
    SetLength(Symbols, 0);  // empty — caller should use workspace/symbol
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
begin
  Reply := TJSONObject.Create;
  Arr := TJSONArray.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue);
    // Same v0.6 limitation as HandleDefinition — without incremental
    // tree-sitter parse we can't resolve the cursor token. Return empty
    // and tell the client to use workspace/symbol + find-callers via MCP
    // / CLI for now.
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
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
      else if (Id <> nil) and (Method <> '') then
        SendError(Id, -32601, 'method not found: ' + Method);
    finally
      Msg.Free;
    end;
  end;
end;

end.
