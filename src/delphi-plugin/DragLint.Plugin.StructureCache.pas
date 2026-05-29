unit DragLint.Plugin.StructureCache;

{ Singleton cache for per-file symbol/code-element data.
  Shells out to "drag-lint surface --qname <UnitName>" once per file,
  caches the result keyed by lower-case file path.
  Thread-safe: Update/Invalidate may be called from a background thread. }

interface

uses
  System.SysUtils, System.Generics.Collections, System.SyncObjs;

type
  TSymbolKind = (skUnknown, skUnit, skClass, skInterface, skRecord,
                 skProcedure, skFunction, skProperty, skField,
                 skConstant, skType, skVariable);

  TSymbolInfo = record
    Name:     string;
    Kind:     TSymbolKind;
    Line:     Integer;      { 1-based, 0 = unknown }
    QName:    string;       { fully-qualified name from surface output }
    KindStr:  string;       { raw kind string from CLI }
  end;

  TDragLintStructureCache = class
  strict private
    FByFile: TDictionary<string, TArray<TSymbolInfo>>;
    FLock:   TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    { Returns cached symbols for AFilePath, shelling out if not cached.
      AExePath is the path to drag-lint.exe. }
    function GetSymbolsForFile(const AFilePath, AExePath: string):
      TArray<TSymbolInfo>;

    { Drop the cached entry for AFilePath so the next call re-shells. }
    procedure InvalidateForFile(const AFilePath: string);

    procedure Clear;
  end;

function StructureCache: TDragLintStructureCache;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils;

{ ---- module-level singleton ---- }

var
  GStructureCache: TDragLintStructureCache = nil;

function StructureCache: TDragLintStructureCache;
begin
  if GStructureCache = nil then
    GStructureCache := TDragLintStructureCache.Create;
  Result := GStructureCache;
end;

{ ---- helper: parse one line from "drag-lint surface" output ---- }
{ Output lines look like (space-separated tokens):
    <kind>  <qname>  [<file>:<line>]
  or just   <kind>  <qname>
  We accept whatever the CLI produces and extract name + kind + line. }

function ParseKind(const KindStr: string): TSymbolKind;
var
  S: string;
begin
  S := LowerCase(KindStr);
  if S = 'unit'       then Result := skUnit
  else if S = 'class'     then Result := skClass
  else if S = 'interface' then Result := skInterface
  else if S = 'record'    then Result := skRecord
  else if (S = 'procedure') or (S = 'proc') then Result := skProcedure
  else if (S = 'function')  or (S = 'func') then Result := skFunction
  else if S = 'property'  then Result := skProperty
  else if S = 'field'     then Result := skField
  else if S = 'const'     then Result := skConstant
  else if S = 'type'      then Result := skType
  else if S = 'var'       then Result := skVariable
  else                         Result := skUnknown;
end;

function ParseSurfaceLine(const ALine: string): TSymbolInfo;
var
  Parts: TArray<string>;
  LocPart: string;
  ColonPos: Integer;
begin
  Result.KindStr := '';
  Result.Kind    := skUnknown;
  Result.QName   := '';
  Result.Name    := '';
  Result.Line    := 0;

  Parts := ALine.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(Parts) < 2 then Exit;

  Result.KindStr := Parts[0];
  Result.Kind    := ParseKind(Parts[0]);
  Result.QName   := Parts[1];

  { Extract leaf name: part after last '.' }
  ColonPos := LastDelimiter('.', Result.QName);
  if ColonPos > 0 then
    Result.Name := Copy(Result.QName, ColonPos + 1, MaxInt)
  else
    Result.Name := Result.QName;

  { Optional third token: file:line }
  if Length(Parts) >= 3 then
  begin
    LocPart := Parts[2];
    ColonPos := LastDelimiter(':', LocPart);
    if ColonPos > 1 then
      Result.Line := StrToIntDef(Copy(LocPart, ColonPos + 1, MaxInt), 0);
  end;
end;

{ ---- RunAndCaptureSurface: shell out to drag-lint surface ---- }

{ We cannot call Editor.RunAndCaptureStdout from here (circular dep).
  Duplicate the minimal spawn logic instead. }
function RunAndCaptureSurface(const ACmdLine: string;
  out AOutput: string): Boolean;
var
  SA:          TSecurityAttributes;
  ReadPipe,
  WritePipe:   THandle;
  SI:          TStartupInfoW;
  PI:          TProcessInformation;
  Buf:         array[0..4095] of AnsiChar;
  BytesRead:   DWORD;
  ExitCode:    DWORD;
  WideCmd:     string;
  SB:          TStringBuilder;
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
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    WaitForSingleObject(PI.hProcess, 15000);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
    Result := True;
  finally
    CloseHandle(ReadPipe);
  end;
end;

{ ---- parse full surface output into TArray<TSymbolInfo> ---- }

function ParseSurfaceOutput(const AOutput: string): TArray<TSymbolInfo>;
var
  Lines: TStringList;
  S:     TSymbolInfo;
  List:  TList<TSymbolInfo>;
  i:     Integer;
  L:     string;
begin
  List := TList<TSymbolInfo>.Create;
  try
    Lines := TStringList.Create;
    try
      Lines.Text := AOutput;
      for i := 0 to Lines.Count - 1 do
      begin
        L := Trim(Lines[i]);
        if L = '' then Continue;
        { Skip header/error lines that don't start with a letter token }
        if (L[1] = '-') or (L[1] = '[') then Continue;
        S := ParseSurfaceLine(L);
        if S.QName <> '' then
          List.Add(S);
      end;
    finally
      Lines.Free;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ ---- TDragLintStructureCache ---- }

constructor TDragLintStructureCache.Create;
begin
  inherited Create;
  FByFile := TDictionary<string, TArray<TSymbolInfo>>.Create;
  FLock   := TCriticalSection.Create;
end;

destructor TDragLintStructureCache.Destroy;
begin
  FLock.Free;
  FByFile.Free;
  inherited;
end;

function TDragLintStructureCache.GetSymbolsForFile(
  const AFilePath, AExePath: string): TArray<TSymbolInfo>;
var
  Key:      string;
  Cached:   TArray<TSymbolInfo>;
  HaveIt:   Boolean;
  UnitName: string;
  CmdLine:  string;
  Output:   string;
  Symbols:  TArray<TSymbolInfo>;
begin
  Key := LowerCase(AFilePath);

  FLock.Enter;
  try
    HaveIt := FByFile.TryGetValue(Key, Cached);
  finally
    FLock.Leave;
  end;

  if HaveIt then
  begin
    Result := Cached;
    Exit;
  end;

  { Derive unit name: file stem without extension }
  UnitName := TPath.GetFileNameWithoutExtension(AFilePath);

  { Shell out }
  CmdLine := Format('"%s" surface --qname "%s"', [AExePath, UnitName]);
  RunAndCaptureSurface(CmdLine, Output);
  Symbols := ParseSurfaceOutput(Output);

  { Cache even an empty result so we don't re-shell on every refresh }
  FLock.Enter;
  try
    FByFile.AddOrSetValue(Key, Symbols);
  finally
    FLock.Leave;
  end;

  Result := Symbols;
end;

procedure TDragLintStructureCache.InvalidateForFile(const AFilePath: string);
begin
  FLock.Enter;
  try
    FByFile.Remove(LowerCase(AFilePath));
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintStructureCache.Clear;
begin
  FLock.Enter;
  try
    FByFile.Clear;
  finally
    FLock.Leave;
  end;
end;

initialization

finalization
  FreeAndNil(GStructureCache);

end.
