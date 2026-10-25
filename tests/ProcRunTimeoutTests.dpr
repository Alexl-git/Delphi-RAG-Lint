program ProcRunTimeoutTests;
{$APPTYPE CONSOLE}
{ B-19: the plugin's job timeout is enforced WHILE the child runs.

  WHAT THIS PINS. Before 1.31.5 RunCore read the child's stdout to EOF and
  only then waited ATimeoutMs for the exit, so the deadline bounded the wait
  AFTER the child had finished writing. A child that ran ten minutes held the
  caller ten minutes whatever ATimeoutMs said, and with the job queue single-
  threaded one hung engine blocked every later plugin job and IDE shutdown.

  THE CASES, and what each one would catch being undone:
    1 positive control: a quick child completes, exit 0, output intact.
    2 positive control: a child that writes ~3000 lines keeps every line --
      a bounded read loop that drops a chunk fails here, not in the IDE.
    3 a SILENT child (cmd /c ping >nul) past its deadline: returns within
      timeout + 2 s, reports the timeout distinctly, and the whole TREE is
      gone -- cmd.exe AND its ping.exe grandchild. A kill of the direct
      child alone leaves the grandchild holding the pipe's write end, which
      is exactly the parked-in-ReadFile shape this bug is about.
    4 a CHATTY child (ping prints every second) past its deadline: same
      bound. A read loop that only checks the clock when the pipe is idle
      would never time out here.
    5 ONE sleeping child (ping -n 4) under a 1 s deadline is killed, output
      kept; the same command under a 30 s deadline exits 0 (positive control).
    6 an 8 MB burst (cmd /c type) arrives whole and is not throttled by the
      idle poll slice of the bounded read loop.

  The grandchild is found by parent PID (Toolhelp) while the run is still in
  progress and held open by handle, so its PID cannot be reused under the
  liveness check. }
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Winapi.Windows,
  Winapi.TlHelp32,
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas';

const
  CExpectedTimedOut = -2;   { PROCRUN_TIMED_OUT_EXIT_CODE }
  CTimeoutMs        = 2000;
  CSlackMs          = 2000;
  CLineCount        = 3000;
  CSleeperPings     = 4;        { ping -n 4: ~3 s, a line about every second }
  CShortTimeoutMs   = 1000;
  CLongTimeoutMs    = 30000;
  CBigBytes         = 8 * 1024 * 1024;
  CBigLineLen       = 100;
  CBigRunMs         = 120000;
  CBigBoundMs       = 8000;     { at 100% CPU: 4 KB pipe 15.4 s, 1 MB pipe 3.4 s }

var
  GPass, GFail: Integer;
  GOut   : string ;
  GRc    : Integer;
  GHandle: THandle;
  GPid   : DWORD  ;
  GDone  : Boolean;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

function SysExe(const AName: string): string;
begin
  Result:= TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\' + AName);
end;

{ First process named AExe whose parent is AParentPid, or 0. By name, because
  cmd.exe's console host (conhost.exe) is also its child. }
function FindChildPid(AParentPid: DWORD; const AExe: string): DWORD;
var
  Snap : THandle;
  Entry: TProcessEntry32W;
begin
  Result:= 0;
  Snap:= CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then Exit;
  try
    Entry.dwSize:= SizeOf(Entry);
    if Process32FirstW(Snap, Entry) then
      repeat
        if (Entry.th32ParentProcessID = AParentPid) and SameText(string(Entry.szExeFile), AExe) then Exit(Entry.th32ProcessID);
      until not Process32NextW(Snap, Entry);
  finally
    CloseHandle(Snap);
  end;
end;

procedure TestQuickChild;
var
  Outp: string ;
  Rc  : Integer;
begin
  Rc:= RunCaptureStdout(Format('"%s" /c echo hello-procrun', [SysExe('cmd.exe')]), Outp, 10000);
  Check('1a quick child exits 0', Rc = 0, Format('rc=%d', [Rc]));
  Check('1b quick child output intact', Pos('hello-procrun', Outp) > 0, 'output=' + Outp);
end;

procedure TestBigOutput;
var
  Outp : string ;
  Rc   : Integer;
  Lines: TStringList;
begin
  Rc:= RunCaptureStdout(Format('"%s" /c for /l %%i in (1,1,%d) do @echo line%%i',
                               [SysExe('cmd.exe'), CLineCount]), Outp, 30000);
  Lines:= TStringList.Create;
  try
    Lines.Text:= Trim(Outp);
    Check('2a big-output child exits 0', Rc = 0, Format('rc=%d', [Rc]));
    Check('2b every line arrives', Lines.Count = CLineCount, Format('lines=%d', [Lines.Count]));
    Check('2c last line intact',
          (Lines.Count > 0) and (Lines[Lines.Count - 1] = 'line' + IntToStr(CLineCount)),
          'last=' + (if Lines.Count > 0 then Lines[Lines.Count - 1] else ''));
  finally
    Lines.Free;
  end;
end;

procedure TestSilentTree;
var
  Worker  : TThread;
  SW      : TStopwatch;
  GrandPid: DWORD;
  Grand   : THandle;
begin
  GDone:= False; GHandle:= 0; GPid:= 0; GOut:= ''; GRc:= 0;
  SW:= TStopwatch.StartNew;
  Worker:= TThread.CreateAnonymousThread(
    procedure
    begin
      GRc:= RunCaptureStdoutCancellable(
              Format('"%s" /c "%s" -n 12 127.0.0.1 >nul', [SysExe('cmd.exe'), SysExe('ping.exe')]),
              GOut, CTimeoutMs, 0, GHandle, GPid);
      GDone:= True;
    end);
  Worker.FreeOnTerminate:= False;
  Worker.Start;
  try
    { find ping.exe under cmd.exe while the run is live; hold it by handle }
    Grand:= 0; GrandPid:= 0;
    while (not GDone) and (Grand = 0) and (SW.ElapsedMilliseconds < CTimeoutMs) do
    begin
      if GPid <> 0 then GrandPid:= FindChildPid(GPid, 'ping.exe');
      if GrandPid <> 0 then Grand:= OpenProcess(SYNCHRONIZE, False, GrandPid);
      if Grand = 0 then Sleep(20);
    end;
    while (not GDone) and (SW.ElapsedMilliseconds < 20000) do Sleep(20);
    SW.Stop;
    Check('3a silent child returns within timeout + 2 s', GDone and (SW.ElapsedMilliseconds <= CTimeoutMs + CSlackMs),
          Format('elapsed=%d ms done=%s', [SW.ElapsedMilliseconds, BoolToStr(GDone, True)]));
    Check('3b timeout reported distinctly', GRc = CExpectedTimedOut, Format('rc=%d', [GRc]));
    Check('3c output names the timeout', Pos('timed out after 2 s', GOut) > 0, 'output=' + GOut);
    Check('3d direct child is gone', (GHandle <> 0) and (WaitForSingleObject(GHandle, 0) = WAIT_OBJECT_0));
    Check('3e grandchild was observed', Grand <> 0, 'no ping.exe under cmd.exe pid ' + IntToStr(GPid));
    Check('3f grandchild (tree) is gone', (Grand <> 0) and (WaitForSingleObject(Grand, 0) = WAIT_OBJECT_0));
    if Grand <> 0 then CloseHandle(Grand);
  finally
    Worker.WaitFor;
    Worker.Free;
    CloseProcessHandle(GHandle);
  end;
end;

procedure TestChattyChild;
var
  Outp: string ;
  Rc  : Integer;
  SW  : TStopwatch;
begin
  SW:= TStopwatch.StartNew;
  Rc:= RunCaptureStdout(Format('"%s" -n 12 127.0.0.1', [SysExe('ping.exe')]), Outp, CTimeoutMs);
  SW.Stop;
  Check('4a chatty child returns within timeout + 2 s', SW.ElapsedMilliseconds <= CTimeoutMs + CSlackMs,
        Format('elapsed=%d ms', [SW.ElapsedMilliseconds]));
  Check('4b chatty timeout reported distinctly', Rc = CExpectedTimedOut, Format('rc=%d', [Rc]));
  Check('4c output read before the deadline is kept', Pos('127.0.0.1', Outp) > 0, 'output=' + Outp);
end;

{ 5: ONE sleeping child under two deadlines. Under CTimeoutMs it is killed and
  reports the timeout; under CLongTimeoutMs the very same command line ends on
  its own, exit 0, no timeout notice. The control is what proves 5a-5c come
  from the deadline and not from a child that cannot run here. }
procedure TestSleeperBothWays;
var
  Cmd : string ;
  Outp: string ;
  Rc  : Integer;
  SW  : TStopwatch;
begin
  Cmd:= Format('"%s" -n %d 127.0.0.1', [SysExe('ping.exe'), CSleeperPings]);
  SW:= TStopwatch.StartNew;
  Rc:= RunCaptureStdout(Cmd, Outp, CShortTimeoutMs);
  SW.Stop;
  Check('5a sleeper past a short deadline returns within it + 2 s',
        SW.ElapsedMilliseconds <= CShortTimeoutMs + CSlackMs, Format('elapsed=%d ms', [SW.ElapsedMilliseconds]));
  Check('5b sleeper reports the timeout', Rc = CExpectedTimedOut, Format('rc=%d', [Rc]));
  Check('5c sleeper output read before the kill is kept', Pos('127.0.0.1', Outp) > 0, 'output=' + Outp);  // dl:ok hardcoded-ip-address@8ae1 -- the loopback the test child pings, matched in its own output; not a host to configure
  Rc:= RunCaptureStdout(Cmd, Outp, CLongTimeoutMs);
  Check('5d control: same sleeper under a long deadline exits 0', Rc = 0, Format('rc=%d', [Rc]));
  Check('5e control: no timeout notice', Pos('timed out', Outp) = 0, 'output=' + Outp);
end;

{ 6: a child that writes CBigBytes as fast as it can (cmd /c type of a file)
  must not be throttled by the bounded read loop. A loop that parks
  PROCRUN_POLL_MS whenever a small pipe buffer is momentarily empty caps the
  rate near one buffer per slice (4 KB / 25 ms = 160 KB/s), so a large engine
  report would crawl -- and hit the very deadline B-19 made real. }
procedure TestThroughput;
var
  FileName: string ;
  Outp    : string ;
  Rc      : Integer;
  SW      : TStopwatch;
  Line    : string ;
  SB      : TStringBuilder;
begin
  FileName:= TPath.Combine(TPath.GetTempPath, Format('procrun-throughput-%d.txt', [GetCurrentProcessId]));
  Line:= StringOfChar('x', CBigLineLen - 2) + sLineBreak;
  SB:= TStringBuilder.Create(CBigBytes);
  try
    while SB.Length < CBigBytes do SB.Append(Line);
    TFile.WriteAllText(FileName, SB.ToString, TEncoding.ASCII);
  finally
    SB.Free;
  end;
  try
    SW:= TStopwatch.StartNew;
    Rc:= RunCaptureStdout(Format('"%s" /c type "%s"', [SysExe('cmd.exe'), FileName]), Outp, CBigRunMs);
    SW.Stop;
    Writeln(Format('      (8 MB in %d ms)', [SW.ElapsedMilliseconds]));
    Check('6a big write exits 0', Rc = 0, Format('rc=%d elapsed=%d ms', [Rc, SW.ElapsedMilliseconds]));
    Check('6b every byte arrives', Length(Outp) >= CBigBytes, Format('len=%d', [Length(Outp)]));
    Check('6c not throttled by the poll slice', SW.ElapsedMilliseconds <= CBigBoundMs,
          Format('elapsed=%d ms', [SW.ElapsedMilliseconds]));
  finally
    TFile.Delete(FileName);
  end;
end;

begin
  try
    TestQuickChild;
    TestBigOutput;
    TestSilentTree;
    TestChattyChild;
    TestSleeperBothWays;
    TestThroughput;
  except
    on E: Exception do begin Inc(GFail); Writeln('FAIL  exception: ', E.ClassName, ': ', E.Message); end;
  end;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then ExitCode:= 1;
end.
