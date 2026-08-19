program drag_lint_switch;

{ Turns language-server integrations on and off from a terminal.

  WHY IT IS A SEPARATE EXE, and deliberately dependency-free (RTL only -- no
  drag-lint units, no SQLite, no tree-sitter): its whole purpose is to work WHEN
  THE THING IT SWITCHES IS BROKEN. If drag-lint is ever registered as the IDE's
  Code Insight LSP and wedges, the recovery path cannot be "open Tools > Options
  in the IDE that is currently misbehaving", and it certainly cannot be "run the
  drag-lint binary that is the problem".

  Two jobs:

  * --delphi   the IDE's custom LSP registration. Task D0 (2026-08-18) settled
               the schema by diffing HKCU\Software\Embarcadero\BDS\37.0 across
               creating one entry through the New LSP Server Integration dialog.
               The diff was PURELY ADDITIVE -- 0 lines removed, 0 modified --
               which answered the blocking question in an unexpected way:
               THERE IS NO "SELECTED MANAGER" VALUE. The EXISTENCE of the
               subkey LSP\UserDefined\<Name> is the enabled state, so on/off is
               a subkey create/delete rather than a value rewrite.

  * --kill-orphans  reaps stray DelphiLSP.exe / DelphiLSPMCPServer.exe. Not a
               nicety: on 2026-08-18, with bds.exe NOT RUNNING, 32 such
               processes were holding 375 MB, respawned by VS Code's Delphi MCP
               registration. They spawn on demand and nothing reaps them.

  Exit codes: 0 = did what was asked, 1 = already in that state (not an error),
  2 = target unavailable (host running, file locked), 3 = failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Win.Registry,
  Winapi.Windows,
  Winapi.TlHelp32;

const
  BDS_VER      = '37.0';
  REG_LSP_ROOT = 'Software\Embarcadero\BDS\' + BDS_VER + '\LSP\UserDefined';
  REG_CI_ROOT  = 'Software\Embarcadero\BDS\' + BDS_VER + '\Code Insight';
  ENTRY_NAME   = 'drag-lint';

  EXIT_OK        = 0;
  EXIT_ALREADY   = 1;
  EXIT_BLOCKED   = 2;
  EXIT_FAILED    = 3;

type
  TAction = (acStatus, acOn, acOff, acKillOrphans);
  TTarget = (tgBoth, tgDelphi, tgVSCode);

var
  { The HKCU subkey holding custom LSP entries. Overridable ONLY so the guard
    can exercise create/backup/delete/restore against a scratch key.

    This is not test-only plumbing for its own sake: without it the only way to
    test the mutating paths is against HKCU\...\BDS\37.0, i.e. the developer's
    live IDE configuration -- which the battery would then rewrite on every one
    of its 300+ runs. A guard that damages the machine it runs on does not get
    run, and a path that does not get run is not guarded. }
  GRegLspRoot: string = REG_LSP_ROOT;

{ ---------------------------------------------------------------- process -- }

function ProcessCount(const ANames: array of string; out ATotalBytes: UInt64): Integer;
var
  Snap: THandle;
  PE  : TProcessEntry32;
  I   : Integer;
  Nm  : string;
begin
  Result     := 0;
  ATotalBytes:= 0;
  Snap:= CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then Exit;
  try
    PE.dwSize:= SizeOf(PE);
    if not Process32First(Snap, PE) then Exit;
    repeat
      Nm:= PE.szExeFile;
      for I:= Low(ANames) to High(ANames) do
        if SameText(Nm, ANames[I]) then
        begin
          Inc(Result);
          Break;
        end;
    until not Process32Next(Snap, PE);
  finally
    CloseHandle(Snap);
  end;
end;

function KillByNames(const ANames: array of string; out AKilled: Integer): Boolean;
var
  Snap: THandle;
  PE  : TProcessEntry32;
  H   : THandle;
  I   : Integer;
  Nm  : string;
begin
  Result := True;
  AKilled:= 0;
  Snap:= CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then Exit(False);
  try
    PE.dwSize:= SizeOf(PE);
    if not Process32First(Snap, PE) then Exit;
    repeat
      Nm:= PE.szExeFile;
      for I:= Low(ANames) to High(ANames) do
        if SameText(Nm, ANames[I]) then
        begin
          H:= OpenProcess(PROCESS_TERMINATE, False, PE.th32ProcessID);
          if H <> 0 then
          try
            if TerminateProcess(H, 1) then Inc(AKilled);
          finally
            CloseHandle(H);
          end;
          Break;
        end;
    until not Process32Next(Snap, PE);
  finally
    CloseHandle(Snap);
  end;
end;

{ --------------------------------------------------------------- registry -- }

function EntryExists: Boolean;
var
  R: TRegistry;
begin
  R:= TRegistry.Create(KEY_READ);
  try
    R.RootKey:= HKEY_CURRENT_USER;
    Result:= R.KeyExists(GRegLspRoot + '\' + ENTRY_NAME);
  finally
    R.Free;
  end;
end;

function ListEntries: TArray<string>;
var
  R : TRegistry;
  SL: TStringList;
begin
  SetLength(Result, 0);
  R := TRegistry.Create(KEY_READ);
  SL:= TStringList.Create;
  try
    R.RootKey:= HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly(GRegLspRoot) then
    begin
      R.GetKeyNames(SL);
      Result:= SL.ToStringArray;
    end;
  finally
    SL.Free;
    R.Free;
  end;
end;

{ A .reg file regedit can import, so a revert never depends on THIS tool being
  present or working -- which is the whole point of the tool.

  Every REG_SZ is written as hex(1): UTF-16LE bytes. That is not gold-plating:
  InitString is legitimately MULTI-LINE -- for an empty JSON blob the dialog
  stores an open brace, CRLF, CRLF, a close brace, CRLF -- and a plain
  "key"="value" line cannot represent an embedded newline at all. Writing it
  the easy way would produce a backup that silently loses content, which is the
  worst possible defect in a backup.

  (Described in words rather than shown, deliberately: a CLOSING BRACE anywhere
  in this comment would END it, and the rest would be parsed as code. That is
  exactly how the first draft of this file failed to compile -- E2038 Illegal
  character -- and it is the same trap the header of drag-lint.dpr warns about.) }
function BackupEntry(const APath: string): Boolean;
var
  R   : TRegistry ;
  SL  : TStringList;
  Vals: TStringList;
  I   : Integer   ;
  Key : string    ;

  function HexSz(const AText: string): string;
  var
    Bytes: TBytes;
    K    : Integer;
  begin
    { REG_SZ is stored NUL-terminated; regedit's hex(1) includes the terminator. }
    Bytes:= TEncoding.Unicode.GetBytes(AText + #0);
    Result:= '';
    for K:= 0 to High(Bytes) do
    begin
      if Result <> '' then Result:= Result + ',';
      Result:= Result + LowerCase(IntToHex(Bytes[K], 2));
    end;
  end;

begin
  Result:= False;
  Key:= GRegLspRoot + '\' + ENTRY_NAME;
  R   := TRegistry.Create(KEY_READ);
  SL  := TStringList.Create;
  Vals:= TStringList.Create;
  try
    R.RootKey:= HKEY_CURRENT_USER;
    if not R.OpenKeyReadOnly(Key) then Exit;
    SL.Add('Windows Registry Editor Version 5.00');
    SL.Add('');
    SL.Add('[HKEY_CURRENT_USER\' + Key + ']');
    R.GetValueNames(Vals);
    for I:= 0 to Vals.Count - 1 do
      case R.GetDataType(Vals[I]) of
        rdInteger:
          SL.Add(Format('"%s"=dword:%s', [Vals[I], LowerCase(IntToHex(R.ReadInteger(Vals[I]), 8))]));
        rdString, rdExpandString:
          SL.Add(Format('"%s"=hex(1):%s', [Vals[I], HexSz(R.ReadString(Vals[I]))]));
      end;
    SL.Add('');
    { UTF-16LE with BOM: what regedit writes, and what it expects for the
      "Version 5.00" header. An ANSI file here imports as mojibake. }
    SL.SaveToFile(APath, TEncoding.Unicode);
    Result:= True;
  finally
    Vals.Free;
    SL.Free;
    R.Free;
  end;
end;

function DeleteEntry: Boolean;
var
  R: TRegistry;
begin
  Result:= False;
  R:= TRegistry.Create(KEY_ALL_ACCESS);
  try
    R.RootKey:= HKEY_CURRENT_USER;
    if not R.KeyExists(GRegLspRoot + '\' + ENTRY_NAME) then Exit(True);
    Result:= R.DeleteKey(GRegLspRoot + '\' + ENTRY_NAME);
  finally
    R.Free;
  end;
end;

function CreateEntry(const AExePath, AParams, ALanguageId: string; ATimeoutMs: Integer): Boolean;
var
  R: TRegistry;
begin
  Result:= False;
  R:= TRegistry.Create(KEY_ALL_ACCESS);
  try
    R.RootKey:= HKEY_CURRENT_USER;
    if not R.OpenKey(GRegLspRoot + '\' + ENTRY_NAME, True) then Exit;
    R.WriteString ('Name'      , ENTRY_NAME );
    R.WriteString ('FileName'  , AExePath   );
    R.WriteString ('Parameters', AParams    );
    R.WriteString ('LanguageId', ALanguageId);
    R.WriteInteger('Timeout'   , ATimeoutMs );
    R.WriteString ('InitString', '{'#13#10#13#10'}'#13#10);
    Result:= True;
  finally
    R.Free;
  end;
end;

{ ----------------------------------------------------------------- report -- }

procedure Banner;
begin
  Writeln('drag-lint-switch -- turn language-server integrations on and off');
  Writeln('');
  Writeln('  drag-lint-switch [--status]                   report both targets (default; never changes anything)');
  Writeln('  drag-lint-switch --delphi --status|--on|--off  the IDE''s custom Code Insight LSP entry');
  Writeln('  drag-lint-switch --vscode --status             VS Code''s Delphi LSP/MCP (status only for now)');
  Writeln('  drag-lint-switch --kill-orphans                kill stray DelphiLSP / DelphiLSPMCPServer processes');
  Writeln('');
  Writeln('  --exe <path>      with --delphi --on: the server executable to register');
  Writeln('  --backup-dir <d>  where --off writes its .reg backup (default: %TEMP%)');
  Writeln('  --reg-root <key>  HKCU subkey holding the entries (testing only; defaults to');
  Writeln('                    Software\Embarcadero\BDS\' + BDS_VER + '\LSP\UserDefined)');
  Writeln('');
  Writeln('  exit 0 = done, 1 = already in that state, 2 = blocked (host running), 3 = failed');
end;

procedure ReportDelphi;
var
  Names: TArray<string>;
  I    : Integer       ;
begin
  Writeln('--delphi  (HKCU\' + GRegLspRoot + ')');
  Names:= ListEntries;
  if Length(Names) = 0 then
    Writeln('    no custom LSP entries registered')
  else
    for I:= 0 to High(Names) do
      Writeln('    entry: ' + Names[I] + (if SameText(Names[I], ENTRY_NAME) then '   <-- ours' else ''));
  Writeln('    drag-lint registered: ' + (if EntryExists then 'YES' else 'no'));
end;

procedure ReportVSCode;
var
  N    : Integer;
  Bytes: UInt64 ;
begin
  Writeln('--vscode');
  N:= ProcessCount(['DelphiLSP.exe', 'DelphiLSPMCPServer.exe'], Bytes);
  Writeln(Format('    DelphiLSP / MCP processes running: %d', [N]));
  { Deliberately reports processes rather than claiming to know the persistent
    setting. That registration lives inside VS Code's state.vscdb (a SQLite
    blob store), and this tool is dependency-free on purpose. Saying "disabled"
    without having read it would be a guess presented as a fact. }
  Writeln('    persistent on/off: NOT IMPLEMENTED (registration lives in VS Code''s state.vscdb)');
end;

procedure ReportHosts;
var
  Bytes: UInt64;
begin
  Writeln('hosts');
  Writeln(Format('    bds.exe running : %d', [ProcessCount(['bds.exe' ], Bytes)]));
  Writeln(Format('    Code.exe running: %d', [ProcessCount(['Code.exe'], Bytes)]));
end;

{ ------------------------------------------------------------------- main -- }

var
  Action    : TAction;
  Target    : TTarget;
  I         : Integer;
  A         : string ;
  ExePath   : string ;
  BackupDir : string ;
  BackupPath: string ;
  Killed    : Integer;
  Bytes     : UInt64 ;
begin
  Action   := acStatus;
  Target   := tgBoth  ;
  ExePath  := ''      ;
  BackupDir:= ''      ;
  try
    I:= 1;
    while I <= ParamCount do
    begin
      A:= LowerCase(ParamStr(I));
      if      A = '--delphi'       then Target:= tgDelphi
      else if A = '--vscode'       then Target:= tgVSCode
      else if A = '--status'       then Action:= acStatus
      else if A = '--on'           then Action:= acOn
      else if A = '--off'          then Action:= acOff
      else if A = '--kill-orphans' then Action:= acKillOrphans
      else if (A = '--exe') and (I < ParamCount) then begin Inc(I); ExePath  := ParamStr(I); end
      else if (A = '--backup-dir') and (I < ParamCount) then begin Inc(I); BackupDir:= ParamStr(I); end
      else if (A = '--reg-root') and (I < ParamCount) then begin Inc(I); GRegLspRoot:= ParamStr(I); end
      else if (A = '--help') or (A = '-h') or (A = '/?') then begin Banner; Halt(EXIT_OK); end
      else begin Writeln('ERROR: unknown argument: ' + ParamStr(I)); Banner; Halt(EXIT_FAILED); end;
      Inc(I);
    end;

    case Action of
      acKillOrphans:
        begin
          { The 2026-08-18 caveat, honoured rather than glossed: these are often
            NOT orphans in the strict sense -- their parent VS Code window may
            still be alive, and killing them breaks the Delphi MCP in that
            window until it is reopened. Say so instead of claiming a cleanup. }
          if ProcessCount(['Code.exe'], Bytes) > 0 then
            Writeln('NOTE: VS Code is running. Any of these owned by a live window will break');
          Writeln('      that window''s Delphi MCP until it is reopened. They respawn on demand.');
          if not KillByNames(['DelphiLSP.exe', 'DelphiLSPMCPServer.exe'], Killed) then
          begin
            Writeln('ERROR: could not enumerate processes');
            Halt(EXIT_FAILED);
          end;
          Writeln(Format('killed %d process(es)', [Killed]));
          if Killed = 0 then Halt(EXIT_ALREADY);
          Halt(EXIT_OK);
        end;

      acStatus:
        begin
          ReportHosts;
          Writeln('');
          if Target in [tgBoth, tgDelphi] then begin ReportDelphi; Writeln(''); end;
          if Target in [tgBoth, tgVSCode] then begin ReportVSCode; Writeln(''); end;
          Halt(EXIT_OK);
        end;

      acOff:
        begin
          if Target <> tgDelphi then
          begin
            Writeln('ERROR: --off is implemented for --delphi only');
            Halt(EXIT_FAILED);
          end;
          { The IDE holds its settings in memory and flushes on exit, so an
            external delete during a live session is simply resurrected. Refuse
            rather than appear to work. }
          if ProcessCount(['bds.exe'], Bytes) > 0 then
          begin
            Writeln('BLOCKED: bds.exe is running. Close RAD Studio first -- it rewrites these');
            Writeln('         settings on exit and would undo this change.');
            Halt(EXIT_BLOCKED);
          end;
          if not EntryExists then
          begin
            Writeln('already off: no "' + ENTRY_NAME + '" entry registered');
            Halt(EXIT_ALREADY);
          end;
          if BackupDir = '' then BackupDir:= TPath.GetTempPath;
          BackupPath:= TPath.Combine(BackupDir,
            Format('draglint-lsp-entry-backup-%s.reg', [FormatDateTime('yyyymmdd-hhnnss', Now)]));
          if not BackupEntry(BackupPath) then
          begin
            Writeln('ERROR: could not write the backup; refusing to delete without one');
            Halt(EXIT_FAILED);
          end;
          Writeln('backup: ' + BackupPath);
          if not DeleteEntry then
          begin
            Writeln('ERROR: backup written but the delete failed');
            Halt(EXIT_FAILED);
          end;
          Writeln('off: "' + ENTRY_NAME + '" unregistered. Restore with:');
          Writeln('     reg import "' + BackupPath + '"');
          Halt(EXIT_OK);
        end;

      acOn:
        begin
          if Target <> tgDelphi then
          begin
            Writeln('ERROR: --on is implemented for --delphi only');
            Halt(EXIT_FAILED);
          end;
          if ProcessCount(['bds.exe'], Bytes) > 0 then
          begin
            Writeln('BLOCKED: bds.exe is running. Close RAD Studio first.');
            Halt(EXIT_BLOCKED);
          end;
          if EntryExists then
          begin
            Writeln('already on: "' + ENTRY_NAME + '" is registered');
            Halt(EXIT_ALREADY);
          end;
          if ExePath = '' then
          begin
            Writeln('ERROR: --on needs --exe <path to the LSP server executable>');
            Halt(EXIT_FAILED);
          end;
          { A registered entry pointing at a missing file is NOT inert: the IDE
            launches it and retries forever, reporting "LSP server is not
            responding. Sending restart." Observed on 2026-08-18 with a
            throwaway entry. Refuse to create one. }
          if not TFile.Exists(ExePath) then
          begin
            Writeln('ERROR: no such file: ' + ExePath);
            Writeln('       Registering a missing executable makes the IDE retry it forever.');
            Halt(EXIT_FAILED);
          end;
          if not CreateEntry(ExePath, '', 'pascal', 15000) then
          begin
            Writeln('ERROR: could not write the registry entry');
            Halt(EXIT_FAILED);
          end;
          Writeln('on: "' + ENTRY_NAME + '" -> ' + ExePath);
          Halt(EXIT_OK);
        end;
    end;
  except
    on E: Exception do
    begin
      Writeln('ERROR: ' + E.ClassName + ': ' + E.Message);
      Halt(EXIT_FAILED);
    end;
  end;
end.
