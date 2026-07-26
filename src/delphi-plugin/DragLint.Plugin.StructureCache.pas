unit DragLint.Plugin.StructureCache;

{ Singleton cache for per-file symbol/code-element data.

  v0.42: shells out to "drag-lint outline --file <path> --format json --db <db>"
  once per file -- the FILE-scoped outline, ordered by position. Replaces the
  old "surface --qname <UnitName>" call, which required a CLASS qname and emitted
  signature lines, so for a normal unit it returned "No symbol matched" and the
  tree showed a single "[?] Symbol". Now every symbol in the file is listed with
  its correct kind, name, line, and signature.

  Caches the result keyed by lower-case file path.
  Thread-safe: Update/Invalidate may be called from a background thread. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , System.SyncObjs
  ;

type
  TSymbolKind = (
    skUnknown, skUnit, skClass, skInterface, skRecord, skEnum, skEnumValue, skProcedure, skFunction, skMethod, skConstructor, skDestructor, skProperty, skField, skConstant, skType,
    skVariable);

  TSymbolInfo = record
    Name     : string     ;
    Kind     : TSymbolKind;
    Line     : Integer    ; { 1-based, 0 = unknown }
    QName    : string     ; { fully-qualified name from outline output }
    KindStr  : string     ; { raw kind string from CLI }
    Signature: string     ; { param list + return type / member type }
  end;

  TDragLintStructureCache = class
    strict private
      FByFile: TDictionary<string, TArray<TSymbolInfo>>;
      FLock  : TCriticalSection                        ;
    public
      constructor Create;
      destructor Destroy; override;

      { Returns cached symbols for AFilePath, shelling out if not cached.
      AExePath is the path to drag-lint.exe; ADbPath is the resolved project
      database to query (empty = let the exe use its default resolution). }
      function GetSymbolsForFile(const AFilePath, AExePath, ADbPath: string): TArray<TSymbolInfo>;

      { Drop the cached entry for AFilePath so the next call re-shells. }
      procedure InvalidateForFile(const AFilePath: string);

      procedure Clear;
  end;

function StructureCache: TDragLintStructureCache;

implementation

uses
  Winapi.Windows
  , System.Classes
  , System.JSON
  , System.IOUtils
  , DragLint.Plugin.Telemetry
  ;

{ ---- module-level singleton ---- }

var
  GStructureCache: TDragLintStructureCache = nil;

function StructureCache: TDragLintStructureCache;
begin
  if GStructureCache = nil then GStructureCache:= TDragLintStructureCache.Create;
  Result:= GStructureCache;
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
  S:= LowerCase(KindStr);
  if S      = 'unit' then Result:= skUnit
  else if S = 'class'      then Result:= skClass
  else if S = 'interface'  then Result:= skInterface
  else if S = 'record'     then Result:= skRecord
  else if S = 'enum'       then Result:= skEnum
  else if S = 'enum_value' then Result:= skEnumValue
  else if (S = 'procedure') or (S = 'proc') then Result:= skProcedure
  else if (S = 'function' ) or (S = 'func') then Result:= skFunction
  else if S = 'method'      then Result:= skMethod
  else if S = 'constructor' then Result:= skConstructor
  else if S = 'destructor'  then Result:= skDestructor
  else if S = 'property'    then Result:= skProperty
  else if S = 'field'       then Result:= skField
  else if S = 'const'       then Result:= skConstant
  else if S = 'type'        then Result:= skType
  else if S = 'var'         then Result:= skVariable
  else Result:= skUnknown;
end; // function

{ ---- RunAndCaptureSurface: shell out to drag-lint surface ---- }

{ We cannot call Editor.RunAndCaptureStdout from here (circular dep).
  Duplicate the minimal spawn logic instead.

  v0.86 (spec Finding 1): stdout and stderr used to share ONE pipe
  (SI.hStdOutput = SI.hStdError = WritePipe), so any stale-exe startup
  chatter or error text landed IN the JSON stream ParseOutlineJson has to
  parse. stderr now gets its OWN pipe: stdout is drained first (unchanged --
  the outline JSON is the thing we actually need and can be arbitrarily
  large), then stderr is drained into a small side buffer once the child has
  exited. This is safe from deadlock only because outline's stderr is
  expected to be tiny (a few diagnostic lines at most) and comfortably fits
  the pipe's kernel buffer without the child blocking on a full-buffer write
  while we're still busy reading stdout; see LspClient.pas for the general
  two-stream case, which this unit intentionally does not need. }
function RunAndCaptureSurface(const ACmdLine: string; out AOutput: string): Boolean;
var
  SA        : TSecurityAttributes       ;
  ReadPipe  : THandle                   ;
  WritePipe : THandle                   ;
  ReadErr   : THandle                   ;
  WriteErr  : THandle                   ;
  SI        : TStartupInfoW             ;
  PI        : TProcessInformation       ;
  Buf       : array[0..4095] of AnsiChar;
  BytesRead : DWORD                     ;
  ExitCode  : DWORD                     ;
  WideCmd   : string                    ;
  SB        : TStringBuilder            ;
  ErrText   : string                    ;
  ErrTail   : string                    ;
begin
  Result := False;
  AOutput:= '';
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    if not CreatePipe(ReadErr, WriteErr, @SA, 0) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    try
      SetHandleInformation(ReadErr, HANDLE_FLAG_INHERIT, 0);
      FillChar(SI, SizeOf(SI), 0);
      SI.cb:= SizeOf(SI);
      SI.dwFlags   := STARTF_USESTDHANDLES;
      SI.hStdOutput:= WritePipe;
      SI.hStdError := WriteErr;
      SI.hStdInput:= GetStdHandle(STD_INPUT_HANDLE);
      FillChar(PI, SizeOf(PI), 0);
      WideCmd:= ACmdLine;
      UniqueString(WideCmd);
      if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
      begin
        CloseHandle(WritePipe);
        CloseHandle(WriteErr );
        Exit;
      end;
      CloseHandle(WritePipe);
      CloseHandle(WriteErr );
      SB:= TStringBuilder.Create;
      try
        repeat
          BytesRead:= 0;
          if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
          if BytesRead = 0 then Break;
          Buf[BytesRead]:= #0;
          SB.Append(string(AnsiString(Buf)));
        until False;
        AOutput:= SB.ToString;
      finally
        SB.Free;
      end;
      WaitForSingleObject(PI.hProcess, 15000   );
      GetExitCodeProcess (PI.hProcess, ExitCode);

      { Drain stderr AFTER stdout + the wait -- by now the child has exited
        (or been given up on) so its stderr write end is closed/quiescent
        and this loop cannot block indefinitely. }
      ErrText:= '';
      SB:= TStringBuilder.Create;
      try
        repeat
          BytesRead:= 0;
          if not ReadFile(ReadErr, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
          if BytesRead = 0 then Break;
          Buf[BytesRead]:= #0;
          SB.Append(string(AnsiString(Buf)));
        until False;
        ErrText:= SB.ToString;
      finally
        SB.Free;
      end;
      if (ExitCode <> 0) and (ErrText <> '') then
      begin
        ErrTail:= ErrText;
        if Length(ErrTail) > 300 then ErrTail:= Copy(ErrTail, Length(ErrTail) - 299, 300);
        DLT('structure', 'outline stderr: ' + ErrTail);
      end;

      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread );
      Result:= True;
    finally
      CloseHandle(ReadErr);
    end; // try
  finally
    CloseHandle(ReadPipe);
  end; // try
end; // function

{ ---- parse "outline --format json" output into TArray<TSymbolInfo> ---- }
{ JSON is an array of objects with keys: kind, name, qname, line, signature,
  modifiers. }

{ v0.86 (spec Finding 1): a STALE Win32 drag-lint.exe prints a startup preamble
  (e.g. "loaded defaults"/"FTS5 probe" lines) plus a DROP-TRIGGER block on
  stdout BEFORE the JSON array, and RunAndCaptureSurface historically merged
  stderr into the same pipe -- so the raw output can have non-JSON text ahead
  of (or after) the "[...]" array. Slice from the first '[' to the last ']'
  before handing the text to ParseJSONValue so the parse is tolerant of that
  noise regardless of its source. Task 1 fixed the exe resolver to prefer
  Win64 by default; this is defense in depth on the plugin side. }
function ParseOutlineJson(const AOutput: string): TArray<TSymbolInfo>;
var
  Root     : TJSONValue        ;
  Arr      : TJSONArray        ;
  Obj      : TJSONObject       ;
  S        : TSymbolInfo       ;
  List     : TList<TSymbolInfo>;
  i        : Integer           ;
  ParseText: string             ;
  PosOpen  : Integer            ;
  PosClose : Integer            ;
begin
  List:= TList<TSymbolInfo>.Create;
  try
    ParseText:= AOutput;
    PosOpen  := Pos('[', AOutput);
    PosClose := LastDelimiter(']', AOutput);
    if (PosOpen > 0) and (PosClose > PosOpen) then
      ParseText:= Copy(AOutput, PosOpen, PosClose - PosOpen + 1);
    Root:= nil;
    try
      Root:= TJSONObject.ParseJSONValue(ParseText);
    except
      Root:= nil;
    end;
    try
      if Root is TJSONArray then
      begin
        Arr:= TJSONArray(Root);
        for i:= 0 to Arr.Count - 1 do
        begin
          if not (Arr.Items[i] is TJSONObject) then Continue;
          Obj:= TJSONObject(Arr.Items[i]);
          S:= Default(TSymbolInfo);
          S.KindStr:= Obj.GetValue<string>('kind', '');
          S.Kind:= ParseKind(S.KindStr);
          S.Name := Obj.GetValue<string>('name' , '');
          S.QName:= Obj.GetValue<string>('qname', '');
          S.Line:= Obj.GetValue<Integer>('line', 0);
          S.Signature:= Obj.GetValue<string>('signature', '');
          if S.Name = '' then S.Name:= S.QName;
          { v(outline-polish): the D5 index now emits a 'local_var'/'param' symbol
            for every routine local and parameter (added for call-site type
            resolution). They are NOISE in a code outline -- and the plugin's kind
            parser has no case for them, so they rendered with a '[?]' prefix.
            Exclude them from Code Elements entirely. }
          if (S.QName <> '') and (S.KindStr <> 'local_var') and (S.KindStr <> 'param') then List.Add(S);
        end;
      end; // if
    finally
      Root.Free;
    end; // try
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

{ ---- TDragLintStructureCache ---- }

constructor TDragLintStructureCache.Create;
begin
  inherited Create;
  FByFile:= TDictionary<string, TArray<TSymbolInfo>>.Create;
  FLock:= TCriticalSection.Create;
end;

destructor TDragLintStructureCache.Destroy;
begin
  FLock.Free;
  FByFile.Free;
  inherited;
end;

function TDragLintStructureCache.GetSymbolsForFile( const AFilePath, AExePath, ADbPath: string): TArray<TSymbolInfo>;
var
  Key    : string             ;
  Cached : TArray<TSymbolInfo>;
  HaveIt : Boolean            ;
  CmdLine: string             ;
  Output : string             ;
  Symbols: TArray<TSymbolInfo>;
begin
  Key:= LowerCase(AFilePath);

  FLock.Enter;
  try
    HaveIt:= FByFile.TryGetValue(Key, Cached);
  finally
    FLock.Leave;
  end;

  if HaveIt then
  begin
    Result:= Cached;
    Exit;
  end;

  { v0.42: file-scoped outline as JSON. Pass --db when we have a resolved
    project database; without it the exe falls back to its own default
    resolution (.drag-lint.json / drag-lint.sqlite in cwd). }
  if ADbPath <> '' then CmdLine:= Format('"%s" outline --file "%s" --format json --db "%s"', [AExePath, AFilePath, ADbPath])
  else CmdLine:= Format('"%s" outline --file "%s" --format json', [AExePath, AFilePath]);
  RunAndCaptureSurface(CmdLine, Output);
  Symbols:= ParseOutlineJson(Output);

  { Cache even an empty result so we don't re-shell on every refresh }
  FLock.Enter;
  try
    FByFile.AddOrSetValue(Key, Symbols);
  finally
    FLock.Leave;
  end;

  Result:= Symbols;
end; // function

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
