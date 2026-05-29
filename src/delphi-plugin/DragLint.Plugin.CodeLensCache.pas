unit DragLint.Plugin.CodeLensCache;

{ Singleton cache for per-file code-lens data (caller counts).

  PopulateOnce shells out to drag-lint surface to discover method
  declarations, then for each method shells drag-lint query find-callers
  to get the caller count.  Results are stored as a map:
    lowercase(filepath) -> (0-based line number -> "[N callers]" label)

  PaintLine reads from the cache only -- no subprocess calls during paint.
  Cache is invalidated (file entry dropped) on BufferSaved via
  InvalidateFile so it repopulates on the next EditorViewActivated. }

interface

uses
  System.SysUtils, System.Generics.Collections, System.SyncObjs;

type
  TDragLintCodeLensCache = class
  strict private
    { outer key: lowercase filepath; inner key: 0-based line number }
    FByFile: TDictionary<string,
               TDictionary<Integer, string>>;
    FLock:   TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    { Returns "[N callers]" string for the given file + 0-based line,
      or "" if nothing is cached for that line. }
    function GetForLine(const AFilePath: string; ALine: Integer): string;

    { Drop the cached entry for AFilePath so the next Populate re-runs. }
    procedure InvalidateFile(const AFilePath: string);

    { Shells out once per file.  Discovers method declarations via
      "drag-lint surface", then queries caller count for each method via
      "drag-lint query find-callers".  Cached result is stored
      synchronously (called from EditorViewActivated, off the paint path).
      If AExePath or ADbPath is empty the call is a no-op. }
    procedure PopulateOnce(const AFilePath, AExePath, ADbPath: string);

    procedure Clear;
  end;

function CodeLensCache: TDragLintCodeLensCache;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils;

{ ---- module-level singleton ---- }

var
  GCodeLensCache: TDragLintCodeLensCache = nil;

function CodeLensCache: TDragLintCodeLensCache;
begin
  if GCodeLensCache = nil then
    GCodeLensCache := TDragLintCodeLensCache.Create;
  Result := GCodeLensCache;
end;

{ ---- helper: spawn and capture stdout+stderr ---- }

function RunCapture(const ACmdLine: string; out AOutput: string): Boolean;
var
  SA:         TSecurityAttributes;
  ReadPipe,
  WritePipe:  THandle;
  SI:         TStartupInfoW;
  PI:         TProcessInformation;
  Buf:        array[0..4095] of AnsiChar;
  BytesRead:  DWORD;
  WideCmd:    string;
  SB:         TStringBuilder;
begin
  Result  := False;
  AOutput := '';
  SA.nLength              := SizeOf(SA);
  SA.bInheritHandle       := True;
  SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb         := SizeOf(SI);
    SI.dwFlags    := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd := ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd),
       nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil)
          then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    WaitForSingleObject(PI.hProcess, 15000);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
    Result := True;
  finally
    CloseHandle(ReadPipe);
  end;
end;

{ ---- parse "drag-lint surface" output to extract method names + lines ----

  Typical surface line:
    function  MyUnit.TMyClass.MyMethod  path/to/file.pas:42
  We only want impl-side methods (procedure/function) and their line. }

type
  TMethodEntry = record
    Name: string;   { short leaf name, e.g. "MyMethod" }
    Line: Integer;  { 1-based declaration line }
  end;

function ParseSurfaceForMethods(const AOutput: string):
  TArray<TMethodEntry>;
var
  Lines:   TStringList;
  List:    TList<TMethodEntry>;
  i:       Integer;
  L:       string;
  Parts:   TArray<string>;
  KindStr: string;
  QName:   string;
  LocPart: string;
  ColPos:  Integer;
  Entry:   TMethodEntry;
  LK:      string;
begin
  List := TList<TMethodEntry>.Create;
  try
    Lines := TStringList.Create;
    try
      Lines.Text := AOutput;
      for i := 0 to Lines.Count - 1 do
      begin
        L := Trim(Lines[i]);
        if L = '' then Continue;
        if (L[1] = '-') or (L[1] = '[') then Continue;

        Parts := L.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        if Length(Parts) < 2 then Continue;

        KindStr := Parts[0];
        LK      := LowerCase(KindStr);
        if (LK <> 'procedure') and (LK <> 'function') and
           (LK <> 'proc')      and (LK <> 'func') then Continue;

        QName := Parts[1];
        Entry.Name := QName;
        ColPos := LastDelimiter('.', QName);
        if ColPos > 0 then
          Entry.Name := Copy(QName, ColPos + 1, MaxInt);

        Entry.Line := 0;
        if Length(Parts) >= 3 then
        begin
          LocPart := Parts[2];
          ColPos  := LastDelimiter(':', LocPart);
          if ColPos > 1 then
            Entry.Line := StrToIntDef(
              Copy(LocPart, ColPos + 1, MaxInt), 0);
        end;

        if Entry.Name <> '' then
          List.Add(Entry);
      end;
    finally
      Lines.Free;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ ---- parse caller count from "drag-lint query find-callers" output ---- }

function ParseCallerCount(const AOutput: string): Integer;
var
  Lines: TStringList;
  i:     Integer;
  L:     string;
  P:     Integer;
begin
  { Last line often has "N result(s)" or similar.
    We count non-blank, non-header lines that look like caller entries. }
  Result := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
    begin
      L := Trim(Lines[i]);
      if L = '' then Continue;
      { Skip leading header lines that contain "---" or start with known
        prefixes. Any other non-blank line is a caller entry. }
      if (L = '---') or (Pos('---', L) = 1) then Continue;
      if (L[1] = '[') then Continue;
      { Lines ending with "result(s)" are summary -- extract number }
      P := Pos('result(s)', L);
      if P > 0 then
      begin
        { e.g. "3 result(s)" }
        Result := StrToIntDef(Trim(Copy(L, 1, P - 1)), Result);
        Break;
      end;
      Inc(Result);
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- TDragLintCodeLensCache ---- }

constructor TDragLintCodeLensCache.Create;
begin
  inherited Create;
  FByFile := TDictionary<string,
               TDictionary<Integer, string>>.Create;
  FLock   := TCriticalSection.Create;
end;

destructor TDragLintCodeLensCache.Destroy;
var
  Inner: TDictionary<Integer, string>;
begin
  FLock.Enter;
  try
    for Inner in FByFile.Values do
      Inner.Free;
    FByFile.Free;
  finally
    FLock.Leave;
  end;
  FLock.Free;
  inherited;
end;

function TDragLintCodeLensCache.GetForLine(const AFilePath: string;
  ALine: Integer): string;
var
  Key:   string;
  Inner: TDictionary<Integer, string>;
begin
  Result := '';
  Key    := LowerCase(AFilePath);
  FLock.Enter;
  try
    if FByFile.TryGetValue(Key, Inner) then
      Inner.TryGetValue(ALine, Result);
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintCodeLensCache.InvalidateFile(const AFilePath: string);
var
  Key:   string;
  Inner: TDictionary<Integer, string>;
begin
  Key := LowerCase(AFilePath);
  FLock.Enter;
  try
    if FByFile.TryGetValue(Key, Inner) then
    begin
      Inner.Free;
      FByFile.Remove(Key);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintCodeLensCache.PopulateOnce(
  const AFilePath, AExePath, ADbPath: string);
var
  Key:      string;
  HaveIt:   Boolean;
  UnitName: string;
  SurfCmd:  string;
  SurfOut:  string;
  Methods:  TArray<TMethodEntry>;
  M:        TMethodEntry;
  CallerCmd: string;
  CallerOut: string;
  Count:    Integer;
  Inner:    TDictionary<Integer, string>;
  ZeroLine: Integer;
begin
  if (AExePath = '') or (ADbPath = '') then Exit;
  if AFilePath = '' then Exit;

  Key := LowerCase(AFilePath);

  { Skip if already populated }
  FLock.Enter;
  try
    HaveIt := FByFile.ContainsKey(Key);
  finally
    FLock.Leave;
  end;
  if HaveIt then Exit;

  { Get symbol list via surface }
  UnitName := TPath.GetFileNameWithoutExtension(AFilePath);
  SurfCmd  := Format('"%s" surface --qname "%s" --db "%s"',
                     [AExePath, UnitName, ADbPath]);
  if not RunCapture(SurfCmd, SurfOut) then Exit;
  Methods := ParseSurfaceForMethods(SurfOut);
  if Length(Methods) = 0 then
  begin
    { Store empty inner dict so we don't re-shell }
    Inner := TDictionary<Integer, string>.Create;
    FLock.Enter;
    try
      FByFile.AddOrSetValue(Key, Inner);
    finally
      FLock.Leave;
    end;
    Exit;
  end;

  Inner := TDictionary<Integer, string>.Create;
  for M in Methods do
  begin
    CallerCmd := Format('"%s" query find-callers --name "%s" --db "%s"',
                        [AExePath, M.Name, ADbPath]);
    CallerOut := '';
    RunCapture(CallerCmd, CallerOut);
    Count := ParseCallerCount(CallerOut);
    if M.Line > 0 then
    begin
      { Store on 0-based line (surface returns 1-based) }
      ZeroLine := M.Line - 1;
      if Count = 1 then
        Inner.AddOrSetValue(ZeroLine, '[1 caller]')
      else
        Inner.AddOrSetValue(ZeroLine,
          Format('[%d callers]', [Count]));
    end;
  end;

  FLock.Enter;
  try
    FByFile.AddOrSetValue(Key, Inner);
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintCodeLensCache.Clear;
var
  Inner: TDictionary<Integer, string>;
begin
  FLock.Enter;
  try
    for Inner in FByFile.Values do
      Inner.Free;
    FByFile.Clear;
  finally
    FLock.Leave;
  end;
end;

initialization

finalization
  FreeAndNil(GCodeLensCache);

end.
