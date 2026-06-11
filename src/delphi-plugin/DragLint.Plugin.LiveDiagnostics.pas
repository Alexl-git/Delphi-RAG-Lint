unit DragLint.Plugin.LiveDiagnostics;

{ v0.42: live, edit-time diagnostics that can never hang the IDE.

  Pipeline:
    editor Modified -> NotifyEdit (debounce) -> on idle: snapshot the UNSAVED
    buffer to a temp file -> AggregateDiagnostics() over every registered
    provider (the lint provider below now; an LLM/compiler provider later) ->
    rebuild the file's entry in the DiagnosticCache -> repaint edit views so the
    squiggle painter (EditViewNotifier.PaintLine) shows them.

  Everything runs out-of-process (drag-lint.exe), debounced, and try/except
  guarded, so a slow or failing run only delays a result -- it never freezes the
  editor (the core reliability win over the IDE's in-process Error Insight).

  Status: GLiveStatus reflects what's happening ('Analyzing...', 'N errors,
  M warnings', 'idle') for a Diagnostics status line. }

interface

procedure StartLiveDiagnostics;
procedure StopLiveDiagnostics;
{ Called from the edit-view notifier's Modified hook. }
procedure NotifyEditDirty;

var
  GLiveStatus: string = '';   { shown in the dock Diagnostics status line }

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.StrUtils, System.Generics.Collections,
  Vcl.ExtCtrls,
  Winapi.Windows,
  ToolsAPI,
  DragLint.Plugin.Providers,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.DbResolver,
  DragLint.Plugin.Settings;

const
  DEBOUNCE_MS = 700;   { idle time after the last keystroke before we analyze }

{ ---------- small process-capture helper ---------- }

function RunCapture(const ACmdLine: string; out AOutput: string;
  ATimeoutMs: Cardinal): Boolean;
var
  SA: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  Buf: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  WideCmd: string;
  SB: TStringBuilder;
begin
  Result := False; AOutput := '';
  SA.nLength := SizeOf(SA); SA.bInheritHandle := True; SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe; SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd := ACmdLine; UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True,
       CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe); Exit;
    end;
    CloseHandle(WritePipe);
    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    WaitForSingleObject(PI.hProcess, ATimeoutMs);
    CloseHandle(PI.hProcess); CloseHandle(PI.hThread);
    Result := True;
  finally
    CloseHandle(ReadPipe);
  end;
end;

{ ---------- the lint diagnostic provider ---------- }
{ Parses `drag-lint lint <buffer>`'s text output:
    <path>:<line>:<col>  [<severity>] <rule>: <message>             }

type
  TLintDiagnosticProvider = class(TInterfacedObject, IDragLintDiagnosticProvider)
  public
    function Name: string;
    function GetDiagnostics(const ACtx: TDragLintDiagContext): TDragLintDiagItems;
  end;

function TLintDiagnosticProvider.Name: string;
begin
  Result := 'lint';
end;

function SeverityFromTag(const ATag: string): Integer;
var L: string;
begin
  L := LowerCase(ATag);
  if Pos('error', L) > 0 then Result := 1
  else if Pos('warn', L) > 0 then Result := 2
  else if Pos('hint', L) > 0 then Result := 4
  else Result := 3;   { info }
end;

function TLintDiagnosticProvider.GetDiagnostics(
  const ACtx: TDragLintDiagContext): TDragLintDiagItems;
var
  Cmd, Output, Line, Rest, Tag, Rule, Msg: string;
  Loc, ColStr, Loc2, LineStr: string;
  Lines: TStringList;
  Acc: TList<TDragLintDiagItem>;
  D: TDragLintDiagItem;
  i, p, lb, rb, c1, c2: Integer;
begin
  SetLength(Result, 0);
  if (ACtx.BufferPath = '') or (ACtx.ExePath = '') then Exit;
  Cmd := Format('"%s" lint "%s"', [ACtx.ExePath, ACtx.BufferPath]);
  if not RunCapture(Cmd, Output, 8000) then Exit;

  Acc := TList<TDragLintDiagItem>.Create;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      lb := Pos('[', Line);
      rb := Pos(']', Line);
      if (lb = 0) or (rb = 0) or (rb < lb) then Continue;   { not a finding line }
      { left of '[' is  <path>:<line>:<col>   -- col is after the last two ':' }
      Loc := Trim(Copy(Line, 1, lb - 1));
      c2 := LastDelimiter(':', Loc);
      if c2 <= 1 then Continue;
      ColStr := Copy(Loc, c2 + 1, MaxInt);
      Loc2 := Copy(Loc, 1, c2 - 1);
      c1 := LastDelimiter(':', Loc2);
      if c1 <= 1 then Continue;
      LineStr := Copy(Loc2, c1 + 1, MaxInt);
      Tag := Copy(Line, lb + 1, rb - lb - 1);            { severity word }
      Rest := Trim(Copy(Line, rb + 1, MaxInt));          { rule: message }
      p := Pos(':', Rest);
      if p > 0 then
      begin
        Rule := Trim(Copy(Rest, 1, p - 1));
        Msg  := Trim(Copy(Rest, p + 1, MaxInt));
      end
      else
      begin
        Rule := ''; Msg := Rest;
      end;

      D := Default(TDragLintDiagItem);
      D.FilePath := ACtx.FilePath;    { map back to the real (saved) path }
      D.Line     := StrToIntDef(Trim(LineStr), 1);
      D.Col      := StrToIntDef(Trim(ColStr), 1);
      D.EndLine  := D.Line;
      D.EndCol   := D.Col + 1;
      D.Severity := SeverityFromTag(Tag);
      D.Message  := Msg;
      D.Rule     := Rule;
      D.Source   := 'lint';
      Acc.Add(D);
    end;
    Result := Acc.ToArray;
  finally
    Lines.Free;
    Acc.Free;
  end;
end;

{ ---------- the runner ---------- }

type
  TLiveRunner = class
  private
    FTimer:     TTimer;
    FDirty:     Boolean;
    FLastEdit:  Cardinal;
    FBusy:      Boolean;
    procedure OnTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  GRunner:   TLiveRunner = nil;
  GProvider: IDragLintDiagnosticProvider = nil;

function ActiveBufferText(out AFilePath: string): string;
var
  ES: IOTAEditorServices;
  Buf: IOTAEditBuffer;
  Reader: IOTAEditReader;
  Read, Pos: Integer;
  Chunk: array[0..8191] of AnsiChar;
  SB: TStringBuilder;
begin
  Result := ''; AFilePath := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
  Buf := ES.TopBuffer;
  if Buf = nil then Exit;
  AFilePath := Buf.FileName;
  Reader := Buf.CreateReader;
  if Reader = nil then Exit;
  SB := TStringBuilder.Create;
  try
    Pos := 0;
    repeat
      Read := Reader.GetText(Pos, @Chunk[0], SizeOf(Chunk) - 1);
      if Read <= 0 then Break;
      Chunk[Read] := #0;
      SB.Append(string(AnsiString(Chunk)));
      Inc(Pos, Read);
    until Read < SizeOf(Chunk) - 1;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure RepaintEditViews;
var
  ES: IOTAEditorServices;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ES) then Exit;
  if ES.TopView <> nil then
    try ES.TopView.Paint; except end;
end;

procedure PublishToCache(const AFile: string; const ADiags: TDragLintDiagItems);
var
  Params, DObj, Range, S, E: TJSONObject;
  Arr: TJSONArray;
  D: TDragLintDiagItem;
  Uri: string;
begin
  Params := TJSONObject.Create;
  try
    Uri := 'file:///' + StringReplace(AFile, '\', '/', [rfReplaceAll]);
    Params.AddPair('uri', Uri);
    Arr := TJSONArray.Create;
    for D in ADiags do
    begin
      DObj := TJSONObject.Create;
      S := TJSONObject.Create;
      S.AddPair('line', TJSONNumber.Create(D.Line - 1));
      S.AddPair('character', TJSONNumber.Create(D.Col - 1));
      E := TJSONObject.Create;
      E.AddPair('line', TJSONNumber.Create(D.EndLine - 1));
      E.AddPair('character', TJSONNumber.Create(D.EndCol - 1));
      Range := TJSONObject.Create;
      Range.AddPair('start', S);
      Range.AddPair('end', E);
      DObj.AddPair('range', Range);
      DObj.AddPair('severity', TJSONNumber.Create(D.Severity));
      DObj.AddPair('source', D.Source);
      DObj.AddPair('code', D.Rule);
      DObj.AddPair('message', D.Message);
      Arr.AddElement(DObj);
    end;
    Params.AddPair('diagnostics', Arr);
    Cache.Update(AFile, Params);
  finally
    Params.Free;
  end;
end;

constructor TLiveRunner.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := OnTick;
  FTimer.Enabled := True;
end;

destructor TLiveRunner.Destroy;
begin
  FTimer.Free;
  inherited;
end;

procedure TLiveRunner.OnTick(Sender: TObject);
var
  Settings: TDragLintSettings;
  BufText, FilePath, Tmp, Exe: string;
  Bytes: TBytes;
begin
  try
    if FBusy or not FDirty then Exit;
    if GetTickCount - FLastEdit < DEBOUNCE_MS then Exit;

    Settings := LoadSettings;
    if not Settings.AutoDiagnosticsOnSave then begin FDirty := False; Exit; end;

    { Snapshot the buffer on the MAIN thread (OTAPI access), then hand the
      analysis to a BACKGROUND thread so a slow lint can never block the editor.
      Results are marshalled back with TThread.Queue. }
    BufText := ActiveBufferText(FilePath);
    if (FilePath = '') or not SameText(ExtractFileExt(FilePath), '.pas') then
    begin
      FDirty := False;
      Exit;
    end;

    Exe := Settings.ExePath;
    if (Exe = '') or not FileExists(Exe) then
      Exe := ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
    if not FileExists(Exe) then Exe := 'drag-lint.exe';

    Tmp := TPath.Combine(TPath.GetTempPath,
      Format('drag-lint-live-%d.pas', [GetTickCount]));
    Bytes := TEncoding.UTF8.GetBytes(BufText);
    try
      TFile.WriteAllBytes(Tmp, Bytes);
    except
      Exit;
    end;

    FBusy := True;
    FDirty := False;
    GLiveStatus := 'Analyzing ' + ExtractFileName(FilePath) + '...';

    TThread.CreateAnonymousThread(
      procedure
      var
        Ctx: TDragLintDiagContext;
        Diags: TDragLintDiagItems;
      begin
        try
          Ctx := Default(TDragLintDiagContext);
          Ctx.FilePath   := FilePath;
          Ctx.BufferPath := Tmp;
          Ctx.ExePath    := Exe;
          Diags := AggregateDiagnostics(Ctx);   { runs the lint -- background }
        except
          SetLength(Diags, 0);
        end;
        try TFile.Delete(Tmp); except end;

        TThread.Queue(nil,
          procedure
          var nErr, nWarn, i: Integer;
          begin
            try
              PublishToCache(FilePath, Diags);
              RepaintEditViews;
              nErr := 0; nWarn := 0;
              for i := 0 to High(Diags) do
                if Diags[i].Severity = 1 then Inc(nErr)
                else if Diags[i].Severity = 2 then Inc(nWarn);
              GLiveStatus := Format('%d error(s), %d warning(s)', [nErr, nWarn]);
            except
            end;
            FBusy := False;
          end);
      end).Start;
  except
    FBusy := False;
    { never propagate into the IDE message loop }
  end;
end;

procedure NotifyEditDirty;
begin
  if GRunner <> nil then
  begin
    GRunner.FDirty := True;
    GRunner.FLastEdit := GetTickCount;
  end;
end;

procedure StartLiveDiagnostics;
begin
  if GProvider = nil then
  begin
    GProvider := TLintDiagnosticProvider.Create;
    RegisterDiagnosticProvider(GProvider);
  end;
  if GRunner = nil then
    GRunner := TLiveRunner.Create;
end;

procedure StopLiveDiagnostics;
begin
  if GProvider <> nil then
  begin
    UnregisterDiagnosticProvider(GProvider);
    GProvider := nil;
  end;
  FreeAndNil(GRunner);
end;

initialization

finalization
  try StopLiveDiagnostics; except end;

end.
