unit DragLint.Plugin.Editor;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  Vcl.Menus, Vcl.Dialogs,
  ToolsAPI,
  DragLint.Plugin.LspClient,
  DragLint.Plugin.ProjectNotifier,
  DragLint.Plugin.SettingsForm;

procedure RegisterDragLintMenu;
procedure UnregisterDragLintMenu;

{ Invoke* procedures are also called by the keyboard binding unit }
procedure InvokeHover(Sender: TObject);
procedure InvokeCompletion(Sender: TObject);
procedure InvokeSignatureHelp(Sender: TObject);
procedure InvokeDiagnostics(Sender: TObject);

implementation

uses
  System.Generics.Collections,
  Vcl.Forms,
  Winapi.Windows,
  DragLint.Plugin.Keyboard;

{ ---- TMenuActionWrapper ---- }
{ OnClick is TNotifyEvent (method pointer); plain procedures cannot be
  assigned to it directly.  This tiny helper bridges the gap. }

type
  TMenuProc = procedure(Sender: TObject);

  TMenuActionWrapper = class
  private
    FProc: TMenuProc;
  public
    constructor Create(AProc: TMenuProc);
    procedure HandleClick(Sender: TObject);
  end;

constructor TMenuActionWrapper.Create(AProc: TMenuProc);
begin
  inherited Create;
  FProc := AProc;
end;

procedure TMenuActionWrapper.HandleClick(Sender: TObject);
begin
  if Assigned(FProc) then
    FProc(Sender);
end;

{ ---- notification handler ---- }

type
  TDiagEntry = record
    FileName: string;
    Msg: string;
    Rule: string;
    Line: Integer;
    Col: Integer;
  end;

procedure HandleNotification(const AMethod: string; AParams: TJSONValue);
var
  Diags: TJSONArray;
  UriStr: string;
  FileName: string;
  i: Integer;
  DiagObj: TJSONObject;
  RangeObj, StartObj: TJSONObject;
  Entries: TArray<TDiagEntry>;
  E: TDiagEntry;
begin
  if AMethod <> 'textDocument/publishDiagnostics' then Exit;
  if not (AParams is TJSONObject) then Exit;

  if not (AParams as TJSONObject).TryGetValue<string>('uri', UriStr) then Exit;
  if not (AParams as TJSONObject).TryGetValue<TJSONArray>('diagnostics', Diags) then Exit;

  { Convert file URI to local Windows path }
  FileName := UriStr;
  if (Length(FileName) > 8) and
     (LowerCase(Copy(FileName, 1, 8)) = 'file:///') then
    FileName := StringReplace(Copy(FileName, 9, MaxInt), '/', '\',
      [rfReplaceAll]);

  { Collect diagnostic entries before queuing (Diags is owned by AMsg which
    will be freed after this call returns) }
  SetLength(Entries, Diags.Count);
  for i := 0 to Diags.Count - 1 do
  begin
    E.FileName := FileName;
    E.Msg      := '';
    E.Rule     := 'drag-lint';
    E.Line     := 1;
    E.Col      := 1;

    if not (Diags.Items[i] is TJSONObject) then
    begin
      Entries[i] := E;
      Continue;
    end;
    DiagObj := Diags.Items[i] as TJSONObject;

    DiagObj.TryGetValue<string>('message', E.Msg);
    DiagObj.TryGetValue<string>('code',    E.Rule);

    if DiagObj.TryGetValue<TJSONObject>('range', RangeObj) then
      if RangeObj.TryGetValue<TJSONObject>('start', StartObj) then
      begin
        { LSP 0-based -> IOTAMessageServices 1-based }
        StartObj.TryGetValue<Integer>('line',      E.Line);
        StartObj.TryGetValue<Integer>('character', E.Col);
        Inc(E.Line);
        Inc(E.Col);
      end;

    Entries[i] := E;
  end;

  { Post everything to the main thread for the IDE message pane }
  TThread.Queue(nil,
    procedure
    var
      MS: IOTAMessageServices;
      j: Integer;
    begin
      if not Supports(BorlandIDEServices, IOTAMessageServices, MS) then Exit;

      if Length(Entries) = 0 then
      begin
        MS.AddTitleMessage(
          Format('drag-lint: no diagnostics for %s', [FileName]));
        Exit;
      end;

      MS.AddTitleMessage(
        Format('drag-lint: %d diagnostic(s) for %s',
          [Length(Entries), FileName]));

      for j := 0 to High(Entries) do
        MS.AddToolMessage(
          Entries[j].FileName,
          Entries[j].Msg,
          Entries[j].Rule,
          Entries[j].Line,
          Entries[j].Col);
    end);
end;

{ ---- shared LSP client ---- }

var
  GLspClient:   TDragLintLspClient = nil;
  GMenuItems:   TObjectList<TMenuItem> = nil;
  GWrappers:    TObjectList<TMenuActionWrapper> = nil;

function EnsureLspClient: TDragLintLspClient;
var
  ExePath: string;
begin
  if GLspClient = nil then
  begin
    GLspClient := TDragLintLspClient.Create;
    GLspClient.OnNotification := HandleNotification;

    { Look for drag-lint.exe next to the BPL first, then fall back to PATH }
    ExePath := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(ExePath) then
      ExePath := 'drag-lint.exe';

    if not GLspClient.Start(ExePath) then
    begin
      ShowMessage(
        'drag-lint: LSP server failed to start.'#13#10 +
        'Ensure drag-lint.exe is on PATH or next to the BPL.');
      FreeAndNil(GLspClient);
      Exit(nil);
    end;

    if not GLspClient.Initialize then
    begin
      ShowMessage('drag-lint: LSP initialize handshake failed.');
      GLspClient.Stop;
      FreeAndNil(GLspClient);
      Exit(nil);
    end;
  end;
  Result := GLspClient;
end;

{ ---- OTAPI helpers ---- }

function GetActiveEditorInfo(out AUri: string;
  out ALine, ACol: Integer): Boolean;
var
  ESS: IOTAEditorServices;
  EditView: IOTAEditView;
  FileName: string;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EditView := ESS.TopView;
  if EditView = nil then Exit;

  FileName := EditView.Buffer.FileName;
  if FileName = '' then Exit;

  { Convert Windows path to LSP file URI }
  AUri := 'file:///' +
    StringReplace(FileName, '\', '/', [rfReplaceAll]);

  { IOTAEditView.Position is 1-based; LSP is 0-based }
  ALine := EditView.Position.Row    - 1;
  ACol  := EditView.Position.Column - 1;
  if ALine < 0 then ALine := 0;
  if ACol  < 0 then ACol  := 0;

  Result := True;
end;

function MakeTextDocumentPositionParams(const AUri: string;
  ALine, ACol: Integer): TJSONObject;
var
  TextDoc, Pos: TJSONObject;
begin
  Result  := TJSONObject.Create;
  TextDoc := TJSONObject.Create;
  TextDoc.AddPair('uri', AUri);
  Result.AddPair('textDocument', TextDoc);
  Pos := TJSONObject.Create;
  Pos.AddPair('line',      TJSONNumber.Create(ALine));
  Pos.AddPair('character', TJSONNumber.Create(ACol));
  Result.AddPair('position', Pos);
end;

{ ---- menu action procedures ---- }

procedure InvokeHover(Sender: TObject);
var
  Client: TDragLintLspClient;
  Uri: string;
  Line, Col: Integer;
  Params: TJSONObject;
  Resp: TJSONValue;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Params := MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp := Client.Request('textDocument/hover', Params, 5000);
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    ShowMessage('drag-lint hover: request timed out or no result.');
    Exit;
  end;
  try
    ShowMessage('drag-lint hover:'#13#10 + Resp.Format(2));
  finally
    Resp.Free;
  end;
end;

procedure InvokeCompletion(Sender: TObject);
var
  Client: TDragLintLspClient;
  Uri: string;
  Line, Col: Integer;
  Params: TJSONObject;
  Resp: TJSONValue;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Params := MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp := Client.Request('textDocument/completion', Params, 5000);
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    ShowMessage('drag-lint completion: request timed out or no result.');
    Exit;
  end;
  try
    ShowMessage('drag-lint completion:'#13#10 + Resp.Format(2));
  finally
    Resp.Free;
  end;
end;

procedure InvokeSignatureHelp(Sender: TObject);
var
  Client: TDragLintLspClient;
  Uri: string;
  Line, Col: Integer;
  Params: TJSONObject;
  Resp: TJSONValue;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  Params := MakeTextDocumentPositionParams(Uri, Line, Col);
  try
    Resp := Client.Request('textDocument/signatureHelp', Params, 5000);
  finally
    Params.Free;
  end;

  if Resp = nil then
  begin
    ShowMessage('drag-lint signatureHelp: request timed out or no result.');
    Exit;
  end;
  try
    ShowMessage('drag-lint signatureHelp:'#13#10 + Resp.Format(2));
  finally
    Resp.Free;
  end;
end;

procedure InvokeDiagnostics(Sender: TObject);
var
  Client: TDragLintLspClient;
  Uri: string;
  Line, Col: Integer;
  Params: TJSONObject;
  TextDoc: TJSONObject;
begin
  if not GetActiveEditorInfo(Uri, Line, Col) then
  begin
    ShowMessage('drag-lint: No active editor view.');
    Exit;
  end;
  Client := EnsureLspClient;
  if Client = nil then Exit;

  { textDocument/didSave triggers publishDiagnostics notification }
  Params  := TJSONObject.Create;
  TextDoc := TJSONObject.Create;
  TextDoc.AddPair('uri', Uri);
  Params.AddPair('textDocument', TextDoc);
  try
    Client.Notify('textDocument/didSave', Params);
  finally
    Params.Free;
  end;

  ShowMessage(
    'drag-lint: diagnostics requested for'#13#10 + Uri + #13#10 +
    'Results will appear in the Messages pane.');
end;

procedure InvokeSettings(Sender: TObject);
begin
  ShowSettingsDialog;
end;

{ ---- menu registration ---- }

function AddWrappedItem(AParent: TMenuItem; const ACaption: string;
  AProc: TMenuProc): TMenuItem;
var
  W: TMenuActionWrapper;
begin
  Result := TMenuItem.Create(AParent);
  Result.Caption := ACaption;
  W := TMenuActionWrapper.Create(AProc);
  GWrappers.Add(W);
  Result.OnClick := W.HandleClick;
  AParent.Add(Result);
end;

procedure RegisterDragLintMenu;
var
  Services: INTAServices;
  RootMenu: TMenuItem;
begin
  if not Supports(BorlandIDEServices, INTAServices, Services) then Exit;

  GMenuItems := TObjectList<TMenuItem>.Create(True);
  GWrappers  := TObjectList<TMenuActionWrapper>.Create(True);

  RootMenu := TMenuItem.Create(nil);
  RootMenu.Caption := 'drag-lint';
  Services.AddActionMenu('ToolsMenu', nil, RootMenu, True, True);
  GMenuItems.Add(RootMenu);

  AddWrappedItem(RootMenu, 'Hover at Cursor',           InvokeHover);
  AddWrappedItem(RootMenu, 'Show Completion',            InvokeCompletion);
  AddWrappedItem(RootMenu, 'Show Signature Help',        InvokeSignatureHelp);
  AddWrappedItem(RootMenu, 'Run Diagnostics (didSave)',  InvokeDiagnostics);
  AddWrappedItem(RootMenu, 'Settings...',                InvokeSettings);

  RegisterProjectNotifier;
  RegisterDragLintKeystrokes;
end;

procedure UnregisterDragLintMenu;
begin
  UnregisterDragLintKeystrokes;
  UnregisterProjectNotifier;

  { Stop LSP client first }
  if GLspClient <> nil then
  begin
    GLspClient.Stop;
    FreeAndNil(GLspClient);
  end;
  { Wrappers hold the OnClick method pointers; free them before the menu items }
  FreeAndNil(GWrappers);
  FreeAndNil(GMenuItems);
end;

initialization

finalization
  UnregisterDragLintMenu;

end.
