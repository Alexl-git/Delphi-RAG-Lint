unit DRagLint.Format.Yadf;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Winapi.Windows;

type
  TFormatResult = record
    ExitCode:   Integer;
    StdoutText: string;
    Success:    Boolean;
  end;

  TYadfFormatter = class
  public
    class function Format(const AFile: string;
      const AYadfPath: string = ''): TFormatResult;
    class function FindYadfPath: string;
  private
    class function SpawnAndCapture(const ACmd: string;
      ATimeoutMs: DWORD; out AOutput: string): Integer;
  end;

implementation

uses
  System.Win.Registry;

{ TYadfFormatter }

// ---------------------------------------------------------------------------
// FindYadfPath: registry first, then two known hardcoded locations.
// ---------------------------------------------------------------------------
class function TYadfFormatter.FindYadfPath: string;
const
  REGISTRY_KEY = 'Software\YADF';
  REGISTRY_VAL = 'ExePath';
  KNOWN_RELEASE = 'C:\Projects\YADF\Win32\Release\EXE\YADF.exe';
  KNOWN_DEBUG   = 'C:\Projects\YADF\Win32\Debug\EXE\YADF.exe';
var
  Reg: TRegistry;
  RegPath: string;
begin
  Result := '';
  // 1. Check HKCU registry
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REGISTRY_KEY) then
    begin
      if Reg.ValueExists(REGISTRY_VAL) then
        RegPath := Trim(Reg.ReadString(REGISTRY_VAL));
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
  if (RegPath <> '') and TFile.Exists(RegPath) then
  begin
    Result := RegPath;
    Exit;
  end;
  // 2. Hardcoded Release path
  if TFile.Exists(KNOWN_RELEASE) then
  begin
    Result := KNOWN_RELEASE;
    Exit;
  end;
  // 3. Hardcoded Debug path
  if TFile.Exists(KNOWN_DEBUG) then
    Result := KNOWN_DEBUG;
end;

// ---------------------------------------------------------------------------
// SpawnAndCapture: runs ACmd, captures stdout+stderr, returns exit code.
// Times out after ATimeoutMs milliseconds.
// ---------------------------------------------------------------------------
class function TYadfFormatter.SpawnAndCapture(const ACmd: string;
  ATimeoutMs: DWORD; out AOutput: string): Integer;
var
  SA: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  Buf: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  ExitCode: DWORD;
  SB: TStringBuilder;
  WideCmd: string;
  WaitResult: DWORD;
begin
  Result := -1;
  AOutput := '';
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then
    raise Exception.Create('CreatePipe failed');
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd := ACmd;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd),
       nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      raise Exception.CreateFmt('CreateProcessW failed: %d', [GetLastError]);
    end;
    CloseHandle(WritePipe);
    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then
          Break;
        if BytesRead = 0 then
          Break;
        Buf[BytesRead] := #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;
    WaitResult := WaitForSingleObject(PI.hProcess, ATimeoutMs);
    if WaitResult = WAIT_TIMEOUT then
    begin
      TerminateProcess(PI.hProcess, $FFFFFFFF);
      Result := -2; // timeout sentinel
    end
    else
    begin
      GetExitCodeProcess(PI.hProcess, ExitCode);
      Result := Integer(ExitCode);
    end;
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(ReadPipe);
  end;
end;

// ---------------------------------------------------------------------------
// Format: validates file, resolves YADF path, spawns synchronously.
// ---------------------------------------------------------------------------
class function TYadfFormatter.Format(const AFile: string;
  const AYadfPath: string = ''): TFormatResult;
const
  TIMEOUT_MS = 30000;
var
  ResolvedYadf: string;
  Cmd, Output: string;
  ExitCode: Integer;
begin
  Result.ExitCode   := -1;
  Result.StdoutText := '';
  Result.Success    := False;

  if not TFile.Exists(AFile) then
    raise Exception.CreateFmt('File not found: %s', [AFile]);

  if AYadfPath <> '' then
    ResolvedYadf := AYadfPath
  else
    ResolvedYadf := FindYadfPath;

  if ResolvedYadf = '' then
  begin
    Result.StdoutText :=
      'YADF.exe not found. Install YADF or pass --yadf-path, or set ' +
      'HKCU\Software\YADF\ExePath in the registry.';
    Result.ExitCode := -3;
    Exit;
  end;

  if not TFile.Exists(ResolvedYadf) then
  begin
    Result.StdoutText :=
      System.SysUtils.Format('YADF.exe not found at: %s', [ResolvedYadf]);
    Result.ExitCode := -3;
    Exit;
  end;

  Cmd := System.SysUtils.Format('"%s" "%s"', [ResolvedYadf, AFile]);
  try
    ExitCode := SpawnAndCapture(Cmd, TIMEOUT_MS, Output);
  except
    on E: Exception do
    begin
      Result.StdoutText := 'Spawn error: ' + E.Message;
      Exit;
    end;
  end;

  Result.ExitCode   := ExitCode;
  Result.StdoutText := Output;
  Result.Success    := (ExitCode = 0);
end;

end.
