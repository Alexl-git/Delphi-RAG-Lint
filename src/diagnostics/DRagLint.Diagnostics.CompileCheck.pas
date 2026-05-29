unit DRagLint.Diagnostics.CompileCheck;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.DateUtils,
  Winapi.Windows,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  TCompileCheckResult = record
    Findings:   TArray<TCompilerFinding>;
    ExitCode:   Integer;
    StdoutText: string;
  end;

  TCompileChecker = class
  public
    class function Run(const ATarget: string; const AMsbuildPath: string = '';
      const ARsvarsPath: string = ''): TCompileCheckResult;
    class function ParseLine(const ALine: string;
      out AFinding: TCompilerFinding): Boolean;
    class procedure InsertFindings(const AStore: ISymbolStore;
      const AFindings: TArray<TCompilerFinding>);
  private
    class function SpawnAndCapture(const ACmd: string;
      out AOutput: string): Integer;
    class function NormalizeSeverity(const ARaw: string): string;
  end;

implementation

const
  DEFAULT_RSVARS =
    'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat';

{ TCompileChecker }

class function TCompileChecker.NormalizeSeverity(const ARaw: string): string;
var
  L: string;
begin
  L := LowerCase(ARaw);
  if (L = 'error') or (L = 'fatal') then
    Result := 'Error'
  else if L = 'warning' then
    Result := 'Warning'
  else if L = 'hint' then
    Result := 'Hint'
  else if L = 'information' then
    Result := 'Information'
  else
    Result := ARaw;
end;

// Spawn ACmd via CreateProcessW with redirected stdout+stderr.
// Returns process exit code. AOutput receives the merged output.
class function TCompileChecker.SpawnAndCapture(const ACmd: string;
  out AOutput: string): Integer;
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
    WaitForSingleObject(PI.hProcess, INFINITE);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    Result := Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(ReadPipe);
  end;
end;

class function TCompileChecker.ParseLine(const ALine: string;
  out AFinding: TCompilerFinding): Boolean;
const
  // dcc64 native: path(line) Severity: [Code] message
  // Example: C:\foo\Bar.pas(42) Warning: W1002 Symbol "Foo" is specific to a platform
  DCC_PATTERN =
    '^(.+?\.(?:pas|dpr|dpk))\((\d+)\)\s+(Hint|Warning|Error|Fatal|Information):' +
    '\s*([HWEF]\d+)?\s*(.*)$';

  // msbuild: path(line,col): severity code: message
  // Example: C:\foo\Bar.pas(99,5): error E2003: Undeclared identifier: "Foo"
  MSB_PATTERN =
    '^(.+?\.(?:pas|dpr|dpk))\((\d+),(\d+)\):\s+(error|warning|hint|fatal|information)' +
    '\s+([HWEF]\d+):\s+(.*)$';
var
  M: TMatch;
begin
  Result := False;
  AFinding := Default(TCompilerFinding);

  // Try msbuild format first (more specific)
  M := TRegEx.Match(ALine, MSB_PATTERN, [roIgnoreCase]);
  if M.Success then
  begin
    AFinding.RawPath  := M.Groups[1].Value;
    AFinding.LineNo   := StrToIntDef(M.Groups[2].Value, 0);
    AFinding.ColNo    := StrToIntDef(M.Groups[3].Value, 0);
    AFinding.Severity := NormalizeSeverity(M.Groups[4].Value);
    AFinding.Code     := M.Groups[5].Value;
    AFinding.Message  := Trim(M.Groups[6].Value);
    AFinding.FileId   := -1;
    Exit(True);
  end;

  // Try dcc64 native format
  M := TRegEx.Match(ALine, DCC_PATTERN, [roIgnoreCase]);
  if M.Success then
  begin
    AFinding.RawPath  := M.Groups[1].Value;
    AFinding.LineNo   := StrToIntDef(M.Groups[2].Value, 0);
    AFinding.ColNo    := 0;
    AFinding.Severity := NormalizeSeverity(M.Groups[3].Value);
    AFinding.Code     := Trim(M.Groups[4].Value);
    AFinding.Message  := Trim(M.Groups[5].Value);
    AFinding.FileId   := -1;
    Exit(True);
  end;
end;

class function TCompileChecker.Run(const ATarget: string;
  const AMsbuildPath: string = '';
  const ARsvarsPath: string = ''): TCompileCheckResult;
var
  RsVars, Cmd, RawOutput, Line: string;
  Lines: TStringList;
  F: TCompilerFinding;
  Findings: TList<TCompilerFinding>;
  Ext: string;
begin
  Result := Default(TCompileCheckResult);
  RsVars := ARsvarsPath;
  if RsVars = '' then
    RsVars := DEFAULT_RSVARS;

  Ext := LowerCase(ExtractFileExt(ATarget));
  if Ext = '.dproj' then
  begin
    if AMsbuildPath <> '' then
      Cmd := Format('cmd.exe /c "call "%s" && "%s" "%s" /v:normal /t:Build /nologo"',
        [RsVars, AMsbuildPath, ATarget])
    else
      Cmd := Format('cmd.exe /c "call "%s" && msbuild "%s" /v:normal /t:Build /nologo"',
        [RsVars, ATarget]);
  end
  else
  begin
    Cmd := Format('cmd.exe /c "call "%s" && dcc64 -Q -B "%s" 2>&1"',
      [RsVars, ATarget]);
  end;

  Result.ExitCode := SpawnAndCapture(Cmd, RawOutput);
  Result.StdoutText := RawOutput;

  Lines := TStringList.Create;
  Findings := TList<TCompilerFinding>.Create;
  try
    Lines.Text := RawOutput;
    for Line in Lines do
      if ParseLine(Line, F) then
        Findings.Add(F);
    Result.Findings := Findings.ToArray;
  finally
    Lines.Free;
    Findings.Free;
  end;
end;

class procedure TCompileChecker.InsertFindings(const AStore: ISymbolStore;
  const AFindings: TArray<TCompilerFinding>);
var
  F: TCompilerFinding;
  FileId: Int64;
  Rec: TCompilerFinding;
begin
  for F in AFindings do
  begin
    Rec := F;
    // Attempt to resolve file_id from the indexed files table.
    FileId := AStore.FindFileIdByPath(F.RawPath);
    if FileId > 0 then
      Rec.FileId := FileId
    else
      Rec.FileId := -1; // not indexed; store with NULL file_id
    AStore.InsertCompilerFinding(Rec);
  end;
end;

end.
