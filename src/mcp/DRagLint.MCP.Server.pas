unit DRagLint.MCP.Server;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite,
  DRagLint.Lint.Linter;

type
  // Newline-delimited JSON-RPC 2.0 server speaking MCP-2024-11-05 over stdio.
  // Holds one open ISymbolStore for the lifetime of the session.
  TMCPServer = class
  strict private
    FStore: ISymbolStore;
    FLinter: TLinter;
    FDbPaths: TArray<string>;
    procedure SendRaw(const AText: string);
    procedure SendResult(const AId: TJSONValue; const AResult: TJSONValue);
    procedure SendError(const AId: TJSONValue; ACode: Integer;
      const AMessage: string);
    procedure HandleInitialize(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleToolsList(const AId: TJSONValue);
    procedure HandleToolsCall(const AId: TJSONValue;
      const AParams: TJSONObject);
    function ToolDescriptor(const AName, ADesc: string;
      const ASchemaJSON: string): TJSONObject;
    function TextContent(const AText: string): TJSONArray;
    function FormatSymbols(const ASymbols: TArray<TSymbol>): string;
    function FormatReferences(const ARefs: TArray<TReference>): string;
    function FormatFindings(const AFindings: TArray<TLintFinding>): string;
    function FormatDocAsJson(const AQName: string;
      const ADoc: TParsedDoc): string;
    function FormatSymbolsAsJsonArray(const ASymbols: TArray<TSymbol>;
      AStore: ISymbolStore): string;
    function ResolveStore(const AArgs: TJSONObject): ISymbolStore;
  public
    constructor Create(const ADbPaths: TArray<string>);
    destructor Destroy; override;
    procedure Run;
  end;

implementation

constructor TMCPServer.Create(const ADbPaths: TArray<string>);
begin
  inherited Create;
  FDbPaths := ADbPaths;
  // For simplicity v0.4 holds ONE primary store. Multi-DB at MCP call time
  // is v0.5; for now the AI passes a single --db on the serve invocation.
  if Length(FDbPaths) > 0 then
  begin
    FStore := TSQLiteSymbolStore.Create(FDbPaths[0]);
    FStore.Migrate;
  end;
  FLinter := TLinter.Create;
end;

destructor TMCPServer.Destroy;
begin
  FLinter.Free;
  FStore := nil;
  inherited;
end;

procedure TMCPServer.SendRaw(const AText: string);
var
  Bytes: TBytes;
begin
  // Write directly to stdout as UTF-8, manually flushed. Avoids the
  // Delphi RTL TextFile layer's interpretation of newlines.
  Bytes := TEncoding.UTF8.GetBytes(AText + #10);
  System.Write(StringOf(Bytes));
  Flush(Output);
end;

procedure TMCPServer.SendResult(const AId: TJSONValue;
  const AResult: TJSONValue);
var
  Reply: TJSONObject;
  Wire: string;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue)
    else
      Reply.AddPair('id', TJSONNull.Create);
    Reply.AddPair('result', AResult);
    Wire := Reply.ToJSON;
    SendRaw(Wire);
  finally
    Reply.Free;
  end;
end;

procedure TMCPServer.SendError(const AId: TJSONValue; ACode: Integer;
  const AMessage: string);
var
  Reply, Err: TJSONObject;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      Reply.AddPair('id', AId.Clone as TJSONValue)
    else
      Reply.AddPair('id', TJSONNull.Create);
    Err := TJSONObject.Create;
    Err.AddPair('code', TJSONNumber.Create(ACode));
    Err.AddPair('message', AMessage);
    Reply.AddPair('error', Err);
    SendRaw(Reply.ToJSON);
  finally
    Reply.Free;
  end;
end;

procedure TMCPServer.HandleInitialize(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  Res, Caps, Info: TJSONObject;
begin
  Res := TJSONObject.Create;
  Res.AddPair('protocolVersion', '2024-11-05');
  Caps := TJSONObject.Create;
  Caps.AddPair('tools', TJSONObject.Create);
  Res.AddPair('capabilities', Caps);
  Info := TJSONObject.Create;
  Info.AddPair('name', 'drag-lint');
  Info.AddPair('version', '0.4.0-alpha');
  Res.AddPair('serverInfo', Info);
  SendResult(AId, Res);
end;

function TMCPServer.ToolDescriptor(const AName, ADesc, ASchemaJSON: string):
  TJSONObject;
var
  Schema: TJSONValue;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('description', ADesc);
  Schema := TJSONObject.ParseJSONValue(ASchemaJSON);
  if Schema = nil then
    Schema := TJSONObject.Create;
  Result.AddPair('inputSchema', Schema);
end;

procedure TMCPServer.HandleToolsList(const AId: TJSONValue);
var
  Res: TJSONObject;
  Tools: TJSONArray;
begin
  Res := TJSONObject.Create;
  Tools := TJSONArray.Create;

  Tools.AddElement(ToolDescriptor(
    'find_symbol',
    'Find Delphi/Pascal symbols by exact name (with fuzzy fallback) or by ' +
    'qualified name (e.g. UnitName.TClass.MethodName). Returns matching ' +
    'symbols with file:line:col.',
    '{"type":"object","properties":{' +
    '"name":{"type":"string","description":"Bare symbol name"},' +
    '"qname":{"type":"string","description":"Qualified name"}' +
    '},"additionalProperties":false}'));

  Tools.AddElement(ToolDescriptor(
    'find_callers',
    'Find every reference site to a method/event-handler by name. Returns ' +
    'file:line:col rows. Includes DFM event-handler bindings when the .dfm ' +
    'files are indexed.',
    '{"type":"object","properties":{' +
    '"name":{"type":"string","description":"Callee/handler name"}' +
    '},"required":["name"],"additionalProperties":false}'));

  Tools.AddElement(ToolDescriptor(
    'lint',
    'Run the linter on a file or folder. Returns each finding with rule id, ' +
    'severity, file:line:col, and message. Built-in rules + any *.scm rule ' +
    'files in <exedir>/rules/.',
    '{"type":"object","properties":{' +
    '"path":{"type":"string","description":"File or folder to lint"}' +
    '},"required":["path"],"additionalProperties":false}'));

  Tools.AddElement(ToolDescriptor(
    'get_symbol_doc',
    'Return the structured doc comment for a Delphi symbol by its qualified ' +
    'name. Returns format, summary, params, returns, exceptions, since, ' +
    'deprecated flag, and raw_block.',
    '{"type":"object","properties":{' +
    '"qname":{"type":"string","description":"Qualified symbol name (e.g. Unit.TClass.Method)"},' +
    '"db":{"type":"string","description":"Path to .sqlite database (optional if --db passed at startup)"}' +
    '},"required":["qname"]}'));

  Tools.AddElement(ToolDescriptor(
    'find_by_doc_tag',
    'Find symbols whose doc comment has a given tag. Supported tags: ' +
    '"deprecated" (symbols marked deprecated) and "since" (symbols with ' +
    'a @since / <since> annotation).',
    '{"type":"object","properties":{' +
    '"tag":{"type":"string","description":"Tag to search: deprecated | since"},' +
    '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' +
    '},"required":["tag"]}'));

  Tools.AddElement(ToolDescriptor(
    'find_undocumented',
    'Find symbols that have no doc comment. Optionally filter by symbol kind ' +
    '(method, function, procedure, class, ...) and restrict to public symbols.',
    '{"type":"object","properties":{' +
    '"kind":{"type":"string","description":"Symbol kind filter (optional)"},' +
    '"public_only":{"type":"boolean","description":"Only include public symbols (optional)"},' +
    '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' +
    '}}'));

  Res.AddPair('tools', Tools);
  SendResult(AId, Res);
end;

function TMCPServer.TextContent(const AText: string): TJSONArray;
var
  Obj: TJSONObject;
begin
  Result := TJSONArray.Create;
  Obj := TJSONObject.Create;
  Obj.AddPair('type', 'text');
  Obj.AddPair('text', AText);
  Result.AddElement(Obj);
end;

function TMCPServer.FormatSymbols(const ASymbols: TArray<TSymbol>): string;
var
  S: TSymbol;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    for S in ASymbols do
      Sb.AppendLine(Format('%s %s (%s) - line %d:%d',
        [S.Kind.ToText, S.QualifiedName, S.Name, S.StartLine, S.StartCol]));
    if Length(ASymbols) = 0 then
      Sb.AppendLine('No matches.')
    else
      Sb.AppendLine(Format('%d match(es).', [Length(ASymbols)]));
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function TMCPServer.FormatReferences(const ARefs: TArray<TReference>): string;
var
  R: TReference;
  Sb: TStringBuilder;
  Path: string;
begin
  Sb := TStringBuilder.Create;
  try
    for R in ARefs do
    begin
      Path := FStore.GetFilePath(R.FileId);
      Sb.AppendLine(Format('%s:%d:%d  %s  [%s]',
        [Path, R.StartLine, R.StartCol, R.NameText, R.Kind]));
    end;
    if Length(ARefs) = 0 then
      Sb.AppendLine('No references.')
    else
      Sb.AppendLine(Format('%d reference(s).', [Length(ARefs)]));
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function TMCPServer.FormatFindings(
  const AFindings: TArray<TLintFinding>): string;
var
  F: TLintFinding;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    for F in AFindings do
      Sb.AppendLine(Format('%s:%d:%d  [%s] %s: %s',
        [F.FilePath, F.StartLine, F.StartCol, F.Severity, F.RuleId,
         F.Message]));
    if Length(AFindings) = 0 then
      Sb.AppendLine('No findings.')
    else
      Sb.AppendLine(Format('%d finding(s).', [Length(AFindings)]));
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function TMCPServer.ResolveStore(const AArgs: TJSONObject): ISymbolStore;
var
  DbVal: TJSONValue;
  DbPath: string;
begin
  // If the caller supplies a "db" argument, open a per-call store.
  // Otherwise fall back to the session-level FStore.
  if AArgs <> nil then
    DbVal := AArgs.GetValue('db')
  else
    DbVal := nil;
  if DbVal <> nil then
  begin
    DbPath := DbVal.Value;
    Result := TSQLiteSymbolStore.Create(DbPath);
    Result.Migrate;
  end
  else
    Result := FStore;
end;

function TMCPServer.FormatDocAsJson(const AQName: string;
  const ADoc: TParsedDoc): string;
var
  DepStr: string;
begin
  if ADoc.Deprecated then DepStr := 'true' else DepStr := 'false';
  Result :=
    '{"qname":"' + JsonEscape(AQName) + '"' +
    ',"format":"' + JsonEscape(DocFormatToStr(ADoc.Format)) + '"' +
    ',"summary":"' + JsonEscape(ADoc.Summary) + '"' +
    ',"returns":"' + JsonEscape(ADoc.ReturnsText) + '"' +
    ',"since":"' + JsonEscape(ADoc.SinceText) + '"' +
    ',"deprecated":' + DepStr +
    ',"params_json":"' + JsonEscape(ADoc.ParamsJsonRaw) + '"' +
    ',"exceptions_json":"' + JsonEscape(ADoc.ExceptionsJsonRaw) + '"' +
    ',"seealso_json":"' + JsonEscape(ADoc.SeeAlsoJsonRaw) + '"' +
    ',"raw_block":"' + JsonEscape(ADoc.RawBlock) + '"' +
    '}';
end;

function TMCPServer.FormatSymbolsAsJsonArray(const ASymbols: TArray<TSymbol>;
  AStore: ISymbolStore): string;
var
  Parts: TArray<string>;
  I: Integer;
  FilePath: string;
begin
  if Length(ASymbols) = 0 then
  begin
    Result := '[]';
    Exit;
  end;
  SetLength(Parts, Length(ASymbols));
  for I := 0 to High(ASymbols) do
  begin
    if AStore <> nil then
      FilePath := AStore.GetFilePath(ASymbols[I].FileId)
    else
      FilePath := '';
    Parts[I] :=
      '{"qname":"' + JsonEscape(ASymbols[I].QualifiedName) + '"' +
      ',"kind":"' + JsonEscape(ASymbols[I].Kind.ToText) + '"' +
      ',"file":"' + JsonEscape(FilePath) + '"' +
      ',"line":' + IntToStr(ASymbols[I].StartLine) +
      '}';
  end;
  Result := '[' + string.Join(',', Parts) + ']';
end;

procedure TMCPServer.HandleToolsCall(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  ToolName: string;
  Args: TJSONObject;
  ResultText: string;
  Reply: TJSONObject;
  Name, QName: string;
  Symbols: TArray<TSymbol>;
  Refs: TArray<TReference>;
  Findings: TArray<TLintFinding>;
  LintPath: string;
begin
  if (AParams = nil) or (AParams.GetValue('name') = nil) then
  begin
    SendError(AId, -32602, 'tools/call requires name + arguments');
    Exit;
  end;
  ToolName := AParams.GetValue('name').Value;
  var ArgsVal := AParams.GetValue('arguments');
  if ArgsVal is TJSONObject then
    Args := TJSONObject(ArgsVal)
  else
    Args := TJSONObject.Create;
  try
    if ToolName = 'find_symbol' then
    begin
      if FStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve');
        Exit;
      end;
      Name := '';
      QName := '';
      if Args.GetValue('name') <> nil then
        Name := Args.GetValue('name').Value;
      if Args.GetValue('qname') <> nil then
        QName := Args.GetValue('qname').Value;
      if QName <> '' then
        Symbols := FStore.FindSymbolsByQualifiedName(QName)
      else if Name <> '' then
      begin
        Symbols := FStore.FindSymbolsByExactName(Name);
        if Length(Symbols) = 0 then
          Symbols := FStore.FindSymbolsFuzzy(Name, 10);
      end
      else
      begin
        SendError(AId, -32602, 'find_symbol requires name or qname');
        Exit;
      end;
      ResultText := FormatSymbols(Symbols);
    end
    else if ToolName = 'find_callers' then
    begin
      if FStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve');
        Exit;
      end;
      if Args.GetValue('name') = nil then
      begin
        SendError(AId, -32602, 'find_callers requires name');
        Exit;
      end;
      Name := Args.GetValue('name').Value;
      Refs := FStore.FindCallersByName(Name);
      ResultText := FormatReferences(Refs);
    end
    else if ToolName = 'lint' then
    begin
      if Args.GetValue('path') = nil then
      begin
        SendError(AId, -32602, 'lint requires path');
        Exit;
      end;
      LintPath := Args.GetValue('path').Value;
      if TFile.Exists(LintPath) then
        Findings := FLinter.LintFile(LintPath)
      else if TDirectory.Exists(LintPath) then
        Findings := FLinter.LintFolder(LintPath, True)
      else
      begin
        SendError(AId, -32602, 'lint path does not exist');
        Exit;
      end;
      ResultText := FormatFindings(Findings);
    end
    else if ToolName = 'get_symbol_doc' then
    begin
      var CallStore := ResolveStore(Args);
      if CallStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var QNameVal := '';
      if Args.GetValue('qname') <> nil then
        QNameVal := Args.GetValue('qname').Value;
      if QNameVal = '' then
      begin
        SendError(AId, -32602, 'get_symbol_doc requires qname');
        Exit;
      end;
      var SymsForDoc := CallStore.FindSymbolsByQualifiedName(QNameVal);
      if Length(SymsForDoc) = 0 then
        ResultText := '{"error":"symbol not found","qname":"' +
          JsonEscape(QNameVal) + '"}'
      else
      begin
        var DocResult := CallStore.GetSymbolDoc(SymsForDoc[0].Id);
        if not DocResult.HasContent then
          ResultText := '{"error":"no doc comment","qname":"' +
            JsonEscape(QNameVal) + '"}'
        else
          ResultText := FormatDocAsJson(SymsForDoc[0].QualifiedName, DocResult);
      end;
    end
    else if ToolName = 'find_by_doc_tag' then
    begin
      var CallStore2 := ResolveStore(Args);
      if CallStore2 = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var TagVal := '';
      if Args.GetValue('tag') <> nil then
        TagVal := Args.GetValue('tag').Value;
      if TagVal = '' then
      begin
        SendError(AId, -32602, 'find_by_doc_tag requires tag');
        Exit;
      end;
      var TagSyms := CallStore2.FindByDocTag(TagVal);
      ResultText := FormatSymbolsAsJsonArray(TagSyms, CallStore2);
    end
    else if ToolName = 'find_undocumented' then
    begin
      var CallStore3 := ResolveStore(Args);
      if CallStore3 = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var KindVal := '';
      var PubOnly := False;
      if Args.GetValue('kind') <> nil then
        KindVal := Args.GetValue('kind').Value;
      if Args.GetValue('public_only') <> nil then
        PubOnly := Args.GetValue('public_only').Value = 'true';
      var UndocSyms := CallStore3.FindUndocumented(KindVal, PubOnly);
      ResultText := FormatSymbolsAsJsonArray(UndocSyms, CallStore3);
    end
    else
    begin
      SendError(AId, -32601, 'unknown tool: ' + ToolName);
      Exit;
    end;
  finally
    if (AParams.GetValue('arguments') = nil) then
      Args.Free;
  end;

  Reply := TJSONObject.Create;
  Reply.AddPair('content', TextContent(ResultText));
  Reply.AddPair('isError', TJSONBool.Create(False));
  SendResult(AId, Reply);
end;

procedure TMCPServer.Run;
var
  Line: string;
  Msg: TJSONObject;
  Method: string;
  Id: TJSONValue;
  Params: TJSONObject;
  Parsed: TJSONValue;
begin
  while not Eof(Input) do
  begin
    ReadLn(Input, Line);
    Line := Trim(Line);
    if Line = '' then Continue;
    Parsed := TJSONObject.ParseJSONValue(Line);
    if not (Parsed is TJSONObject) then
    begin
      Parsed.Free;
      Continue;
    end;
    Msg := TJSONObject(Parsed);
    try
      Method := '';
      if Msg.GetValue('method') <> nil then
        Method := Msg.GetValue('method').Value;
      Id := Msg.GetValue('id');
      var ParamsVal := Msg.GetValue('params');
      if ParamsVal is TJSONObject then
        Params := TJSONObject(ParamsVal)
      else
        Params := nil;

      if Method = 'initialize' then
        HandleInitialize(Id, Params)
      else if (Method = 'initialized') or (Method = 'notifications/initialized') then
        // notification, no response
      else if Method = 'tools/list' then
        HandleToolsList(Id)
      else if Method = 'tools/call' then
        HandleToolsCall(Id, Params)
      else if Method = 'ping' then
        SendResult(Id, TJSONObject.Create)
      else if (Method = 'prompts/list') or (Method = 'resources/list') then
        // We don't expose prompts or resources; return empty arrays.
        SendResult(Id, TJSONObject.Create.AddPair(
          'prompts',
          TJSONArray.Create))
      else if Method <> '' then
        SendError(Id, -32601, 'method not found: ' + Method);
    finally
      Msg.Free;
    end;
  end;
end;

end.
