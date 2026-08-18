unit DragLint.Plugin.Diagnose;

{ Session 27 (2026-08-17): "what is drag-lint actually doing right now?"

  This unit exists because of a specific, expensive failure. The IDE spent
  months resolving RTL/VCL symbols against a 1.5 GB library index left over from
  before the 2026-08-11 layout change. Nothing was broken in a way anyone could
  see: a stale index answers confidently, just with older and fewer results. The
  cause was a manifest probe built from Settings.ExePath, which defaults to the
  bare name 'drag-lint.exe' -- so ExtractFilePath returned '' and the probe
  looked for a RELATIVE drag-lint.json against the IDE's working directory,
  found nothing, and silently fell back.

  Every one of those steps was invisible. One line of UI -- which library index
  is in use, and why -- would have exposed it in seconds instead of a day.

  PERFORMANCE CONTRACT, load-bearing: nothing here may COUNT rows or open a
  database. Measured on the 3 GB library-Win32.sqlite, `schema --format json`
  takes 38 s because it runs COUNT(*) per table, while opening the same file and
  doing an indexed lookup takes 0.5 s. Index facts below come from the FILE
  SYSTEM only (path, size, mtime). A status screen that is slow does not get
  opened, and a status screen nobody opens reports nothing. }

interface

uses
  System.SysUtils
  ;

type
  /// <summary>How a diagnose line should read: healthy, suspicious, broken, or
  /// merely informational.</summary>
  TDiagSeverity = (dsOk, dsInfo, dsWarn, dsBad);

  /// <summary>A configuration problem this plugin can correct by itself.</summary>
  /// <remarks>Only settings with ONE unambiguous correct value belong here. A
  /// "Fix" button that guesses is worse than no button: it turns a visible
  /// warning into an invisible wrong setting.</remarks>
  TDiagFix = (
    dfNone,       { nothing to offer                                        }
    dfExePath,    { Settings.ExePath -> the full path of the resolved engine }
    dfDbTemplate  { DbPathTemplate   -> the current _D-RAG default           }
  );

  /// <summary>One caption/value row of the diagnose report.</summary>
  /// <remarks>The About screen colours Value by Severity (dsBad = red); the
  /// text report renders the same rows with a leading marker, so both surfaces
  /// are generated from one source and cannot drift.</remarks>
  TDiagLine = record
    Caption : string       ;
    Value   : string       ;
    Severity: TDiagSeverity;
    Fix     : TDiagFix     ;
  end;

  TDiagLines = TArray<TDiagLine>;

/// <summary>Describes what a fix would change, WITHOUT changing it.</summary>
/// <param name="AFix">The fix to describe.</param>
/// <param name="ACurrent">Receives the current value.</param>
/// <param name="AProposed">Receives the value that would be written.</param>
/// <returns>True when the fix applies and the two values differ.</returns>
/// <remarks>Separate from ApplyDiagFix so the confirmation prompt shows the
/// exact before/after. Writing to a user's registry without showing what
/// changes is not a fix, it is a surprise. Main thread only.</remarks>
function DescribeDiagFix(AFix: TDiagFix; out ACurrent, AProposed: string): Boolean;

/// <summary>Applies a fix by writing the corrected setting to the registry.</summary>
/// <param name="AFix">The fix to apply.</param>
/// <param name="AError">Receives the failure reason when the result is False.</param>
/// <returns>True when the setting was written.</returns>
/// <remarks>Caller is expected to have confirmed with the user first -- see
/// DescribeDiagFix. Main thread only.</remarks>
function ApplyDiagFix(AFix: TDiagFix; out AError: string): Boolean;

/// <summary>Plugin, engine, tree-sitter and graph-viewer versions.</summary>
/// <returns>Rows for the Versions group.</returns>
/// <remarks>Shells `drag-lint info --json` synchronously with a short budget --
/// acceptable because the user asked for this screen. Main thread only.</remarks>
function DiagVersions: TDiagLines;

/// <summary>LSP state, engine exe presence, and whether every resolved DB
/// exists on disk.</summary>
/// <returns>Rows for the Connections group; dsBad on anything not usable.</returns>
/// <remarks>Never starts an LSP server -- reads the existing client only, via
/// CurrentLspClient. Main thread only.</remarks>
function DiagConnections: TDiagLines;

/// <summary>Free system RAM, this process's private bytes, and handle count.</summary>
/// <returns>Rows for the Process group.</returns>
/// <remarks>The IDE is a 32-bit process, so its ~4 GB address space and handle
/// count are real operating limits, not trivia. Main thread only.</remarks>
function DiagProcess: TDiagLines;

/// <summary>Which index files are actually in use: the library index (with the
/// rule that chose it) and every DB resolved for the active editor.</summary>
/// <returns>Rows for the Indexes group.</returns>
/// <remarks>File-system facts only -- see this unit's PERFORMANCE CONTRACT.
/// Main thread only.</remarks>
function DiagIndexes: TDiagLines;

/// <summary>Settings that commonly misconfigure the plugin without any visible
/// symptom, checked against what the current layout actually requires.</summary>
/// <returns>Rows for the Configuration group.</returns>
/// <remarks>Added because two live misconfigurations on the author's own box --
/// a bare-name ExePath and a pre-_D-RAG DbPathTemplate -- were both invisible
/// and both changed which index answered. Main thread only.</remarks>
function DiagConfiguration: TDiagLines;

/// <summary>The full copyable "Diagnose current state" report.</summary>
/// <param name="ALogTailLines">How many trailing plugin-log lines to append.</param>
/// <returns>A plain-text report intended to be pasted into an issue.</returns>
/// <remarks>Composes every DiagX group plus the log tail. Main thread only.</remarks>
function BuildDiagnoseReport(ALogTailLines: Integer = 40): string;

/// <summary>True when any row in ALines is dsBad.</summary>
function HasProblem(const ALines: TDiagLines): Boolean;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.JSON
  , Winapi.Windows
  , ToolsAPI
  , DragLint.Plugin.Editor
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.LspClient
  , DragLint.Plugin.Settings
  , DragLint.Plugin.DbResolver
  ;

type
  { Declared locally rather than taken from Winapi.PsAPI: the extended
    (_EX) counters are not consistently exposed across Delphi versions, and this
    unit must not fail to compile over a diagnostic nicety. }
  TDLProcessMemoryCounters = record
    cb                        : DWORD ;
    PageFaultCount            : DWORD ;
    PeakWorkingSetSize        : SIZE_T;
    WorkingSetSize            : SIZE_T;
    QuotaPeakPagedPoolUsage   : SIZE_T;
    QuotaPagedPoolUsage       : SIZE_T;
    QuotaPeakNonPagedPoolUsage: SIZE_T;
    QuotaNonPagedPoolUsage    : SIZE_T;
    PagefileUsage             : SIZE_T;
    PeakPagefileUsage         : SIZE_T;
  end;

function GetProcessMemoryInfo(AProcess: THandle; var ACounters: TDLProcessMemoryCounters;
  ACb: DWORD): BOOL; stdcall; external 'psapi.dll' name 'GetProcessMemoryInfo';
function GetProcessHandleCount(AProcess: THandle;
  var APdwHandleCount: DWORD): BOOL; stdcall; external 'kernel32.dll' name 'GetProcessHandleCount';

{ ---- small helpers ---- }

function Line(const ACaption, AValue: string; ASeverity: TDiagSeverity = dsInfo;
  AFix: TDiagFix = dfNone): TDiagLine;
begin
  Result.Caption := ACaption;
  Result.Value   := AValue;
  Result.Severity:= ASeverity;
  Result.Fix     := AFix;
end;

{ ---- self-correcting configuration ---- }

function DescribeDiagFix(AFix: TDiagFix; out ACurrent, AProposed: string): Boolean;
var
  Settings: TDragLintSettings;
begin
  Result   := False;
  ACurrent := '';
  AProposed:= '';
  Settings := LoadSettings;

  case AFix of
    dfExePath:
      begin
        ACurrent := Settings.ExePath;
        { The engine we would actually run. DragLintExe already performs the
          full resolution (Win64 sibling, then beside the BPL, then PATH), so
          the proposal is not a guess -- it is the path in use right now. }
        AProposed:= DragLintExe;
        { Refuse to propose a path that is itself directory-less or absent:
          replacing one unusable value with another is not a fix. }
        if (AProposed = '') or (ExtractFilePath(AProposed) = '') then Exit;
        if not FileExists(AProposed) then Exit;
      end;
    dfDbTemplate:
      begin
        ACurrent := Settings.DbPathTemplate;
        AProposed:= DefaultSettings.DbPathTemplate;
      end;
  else
    Exit;
  end;

  Result:= not SameText(Trim(ACurrent), Trim(AProposed));
end;

function ApplyDiagFix(AFix: TDiagFix; out AError: string): Boolean;
var
  Settings: TDragLintSettings;
  Cur, Prop: string;
begin
  Result:= False;
  AError:= '';
  if not DescribeDiagFix(AFix, Cur, Prop) then
  begin
    AError:= 'nothing to change';
    Exit;
  end;
  try
    { Read-modify-write the WHOLE settings record: SaveSettings writes every
      value, so building one from scratch here would silently reset unrelated
      preferences. }
    Settings:= LoadSettings;
    case AFix of
      dfExePath   : Settings.ExePath       := Prop;
      dfDbTemplate: Settings.DbPathTemplate:= Prop;
    else
      AError:= 'unknown fix';
      Exit;
    end;
    SaveSettings(Settings);
    Result:= True;
  except
    on E: Exception do AError:= E.ClassName + ': ' + E.Message;
  end;
end;

procedure Add(var ALines: TDiagLines; const ALine: TDiagLine);
begin
  SetLength(ALines, Length(ALines) + 1);
  ALines[High(ALines)]:= ALine;
end;

function HasProblem(const ALines: TDiagLines): Boolean;
var
  L: TDiagLine;
begin
  Result:= False;
  for L in ALines do
    if L.Severity = dsBad then Exit(True);
end;

function FormatBytes(ABytes: Int64): string;
begin
  if ABytes < 0 then Exit('n/a');
  if ABytes >= Int64(1024) * 1024 * 1024 then
    Result:= Format('%.2f GB', [ABytes / (1024.0 * 1024.0 * 1024.0)])
  else if ABytes >= 1024 * 1024 then
    Result:= Format('%.1f MB', [ABytes / (1024.0 * 1024.0)])
  else
    Result:= Format('%d KB', [ABytes div 1024]);
end;

{ File size + last-write, with an age note. NEVER opens the database -- see the
  PERFORMANCE CONTRACT at the top of this unit. }
function DescribeIndexFile(const APath: string): string;
var
  Age    : TDateTime;
  Size   : Int64    ;
  Days   : Integer  ;
  Fs     : TFileStream;
begin
  if APath = '' then Exit('(none)');
  if not TFile.Exists(APath) then Exit('MISSING: ' + APath);

  Size:= -1;
  try
    Fs:= TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      Size:= Fs.Size;
    finally
      Fs.Free;
    end;
  except
    { Locked by an indexer mid-write is normal; report what we can. }
  end;

  Result:= FormatBytes(Size);
  if FileAge(APath, Age) then
  begin
    Days:= Trunc(Now - Age);
    Result:= Result + '   written ' + FormatDateTime('yyyy-mm-dd hh:nn', Age);
    if Days > 0 then Result:= Result + Format('  (%d day(s) ago)', [Days]);
  end;
end;

{ ---- Versions ---- }

function EngineInfoJson(out AJson: TJSONObject; out AError: string): Boolean;
var
  Exe   : string ;
  Output: string ;
  Code  : Integer;
  OpenP : Integer;
  CloseP: Integer;
  Slice : string ;
  Val   : TJSONValue;
begin
  Result:= False;
  AJson := nil;
  AError:= '';
  Exe:= DragLintExe;
  if not FileExists(Exe) then
  begin
    AError:= 'engine exe not found at ' + Exe;
    Exit;
  end;
  Output:= '';
  try
    Code:= RunAndCaptureStdout('"' + Exe + '" info --json', Output, 8000);
  except
    on E: Exception do
    begin
      AError:= E.ClassName + ': ' + E.Message;
      Exit;
    end;
  end;
  if Code <> 0 then
  begin
    AError:= Format('info exited %d', [Code]);
    Exit;
  end;
  OpenP := Pos('{', Output);
  CloseP:= LastDelimiter('}', Output);
  if (OpenP = 0) or (CloseP <= OpenP) then
  begin
    AError:= 'unparseable info output';
    Exit;
  end;
  Slice:= Copy(Output, OpenP, CloseP - OpenP + 1);
  Val:= nil;
  try
    Val:= TJSONObject.ParseJSONValue(Slice);
  except
    on E: Exception do begin Val:= nil; DebugLog('diagnose: info JSON parse failed -- ' + E.Message); end;
  end;
  if not (Val is TJSONObject) then
  begin
    Val.Free;
    AError:= 'info output was not a JSON object';
    Exit;
  end;
  AJson := TJSONObject(Val);
  Result:= True;
end;

function DiagVersions: TDiagLines;
var
  ModName : string;
  Age     : TDateTime;
  Info    : TJSONObject;
  Err     : string;
  TsObj   : TJSONObject;
  GraphExe: string;
begin
  Result:= nil;

  ModName:= GetModuleName(HInstance);
  if (ModName <> '') and FileAge(ModName, Age) then
    Add(Result, Line('Plugin (BPL)', PLUGIN_VERSION + '   built ' +
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Age), dsOk))
  else
    Add(Result, Line('Plugin (BPL)', PLUGIN_VERSION + '   (build time unknown)', dsWarn));
  Add(Result, Line('BPL path', ModName));

  Info:= nil;
  if EngineInfoJson(Info, Err) then
  try
    Add(Result, Line('Engine', Info.GetValue<string>('version', '?') + '   built ' +
      Info.GetValue<string>('build_date', '?') + '   (' +
      Info.GetValue<string>('platform', '?') + ')', dsOk));
    Add(Result, Line('Engine exe', Info.GetValue<string>('exe_path', DragLintExe)));
    TsObj:= nil;
    if Info.TryGetValue<TJSONObject>('tree_sitter', TsObj) and (TsObj <> nil) then
      Add(Result, Line('tree-sitter', 'delphi13 ' + TsObj.GetValue<string>('delphi13', '?') +
        ' / dfm ' + TsObj.GetValue<string>('dfm', '?')));
  finally
    Info.Free;
  end
  else
    Add(Result, Line('Engine', 'UNAVAILABLE -- ' + Err, dsBad));

  GraphExe:= ExtractFilePath(GetModuleName(HInstance)) + 'drag_lint_graph.exe';
  if FileExists(GraphExe) then
  begin
    if FileAge(GraphExe, Age) then
      Add(Result, Line('Graph viewer', 'present, built ' + FormatDateTime('yyyy-mm-dd', Age), dsOk))
    else
      Add(Result, Line('Graph viewer', 'present', dsOk));
  end
  else
    Add(Result, Line('Graph viewer', 'not deployed beside the BPL (Graph window will not open)', dsWarn));
end;

{ ---- Connections ---- }

function DiagConnections: TDiagLines;
var
  Client : TDragLintLspClient;
  Exe    : string            ;
  Dbs    : TArray<string>    ;
  P      : string            ;
  Missing: Integer           ;
  DbsErr : string            ;
begin
  Result:= nil;

  { Deliberately CurrentLspClient, not EnsureLspClient: a status screen must
    observe, never spawn. }
  Client:= CurrentLspClient;
  if Client = nil then
    Add(Result, Line('LSP server', 'not started yet (starts on first hover / completion)', dsInfo))
  else
  begin
    case Client.State of
      dlsConnected:
        if Client.IsAlive then
          Add(Result, Line('LSP server', Format('connected   pid %d   since %s',
            [Client.ProcessId, FormatDateTime('hh:nn:ss', Client.StartedAt)]), dsOk))
        else
          Add(Result, Line('LSP server', 'handshake succeeded but the process has EXITED', dsBad));
      dlsStarting:
        Add(Result, Line('LSP server', 'starting (handshake outstanding)', dsWarn));
      dlsFailed:
        Add(Result, Line('LSP server', 'DOWN -- ' + Client.LastError, dsBad));
    else
      Add(Result, Line('LSP server', 'not started', dsInfo));
    end;
  end;

  Exe:= DragLintExe;
  if FileExists(Exe) then Add(Result, Line('Engine exe', Exe, dsOk))
  else Add(Result, Line('Engine exe', 'NOT FOUND at ' + Exe, dsBad));

  Dbs   := nil;
  DbsErr:= '';
  { Keep the REASON. An earlier version swallowed it and reported only "NONE",
    which is the same fail-open shape this whole window exists to expose: a
    resolver that raised and one that legitimately found nothing looked
    identical, in the one place whose job is to tell them apart. }
  try
    Dbs:= ResolveActiveIndexDbs(LoadSettings);
  except
    on E: Exception do
    begin
      DbsErr:= E.ClassName + ': ' + E.Message;
      DebugLog('diagnose: ResolveActiveIndexDbs raised -- ' + DbsErr);
    end;
  end;
  if DbsErr <> '' then
    Add(Result, Line('Resolved indexes', 'resolution FAILED -- ' + DbsErr, dsBad))
  else if Length(Dbs) = 0 then
    Add(Result, Line('Resolved indexes', 'NONE -- symbol features cannot answer', dsBad))
  else
  begin
    Missing:= 0;
    for P in Dbs do
      if not TFile.Exists(P) then Inc(Missing);
    if Missing = 0 then
      Add(Result, Line('Resolved indexes', Format('%d, all present', [Length(Dbs)]), dsOk))
    else
      Add(Result, Line('Resolved indexes', Format('%d resolved, %d MISSING on disk',
        [Length(Dbs), Missing]), dsBad));
  end;
end;

{ ---- Process ---- }

function DiagProcess: TDiagLines;
var
  MemStat : TMemoryStatusEx        ;
  Counters: TDLProcessMemoryCounters;
  Handles : DWORD                  ;
  Sev     : TDiagSeverity          ;
begin
  Result:= nil;

  FillChar(MemStat, SizeOf(MemStat), 0);
  MemStat.dwLength:= SizeOf(MemStat);
  if GlobalMemoryStatusEx(MemStat) then
  begin
    if MemStat.dwMemoryLoad >= 90 then Sev:= dsWarn else Sev:= dsOk;
    Add(Result, Line('System RAM', Format('%s free of %s  (%d%% in use)',
      [FormatBytes(Int64(MemStat.ullAvailPhys)), FormatBytes(Int64(MemStat.ullTotalPhys)),
       MemStat.dwMemoryLoad]), Sev));
  end
  else
    Add(Result, Line('System RAM', 'unavailable', dsWarn));

  FillChar(Counters, SizeOf(Counters), 0);
  Counters.cb:= SizeOf(Counters);
  if GetProcessMemoryInfo(GetCurrentProcess, Counters, SizeOf(Counters)) then
  begin
    { The IDE is 32-bit: ~2 GB of user address space by default, ~3-4 GB when
      large-address-aware. Past roughly 1.5 GB private bytes it starts failing in
      ways that look like unrelated bugs, so this is a real health number. }
    if Counters.PagefileUsage > Int64(1500) * 1024 * 1024 then Sev:= dsBad
    else if Counters.PagefileUsage > Int64(1200) * 1024 * 1024 then Sev:= dsWarn
    else Sev:= dsOk;
    Add(Result, Line('IDE private bytes', FormatBytes(Int64(Counters.PagefileUsage)), Sev));
    Add(Result, Line('IDE working set', FormatBytes(Int64(Counters.WorkingSetSize))));
  end
  else
    Add(Result, Line('IDE memory', 'unavailable', dsWarn));

  Handles:= 0;
  if GetProcessHandleCount(GetCurrentProcess, Handles) then
  begin
    if Handles > 20000 then Sev:= dsWarn else Sev:= dsOk;
    Add(Result, Line('IDE handles', IntToStr(Handles), Sev));
  end
  else
    Add(Result, Line('IDE handles', 'unavailable', dsWarn));
end;

{ ---- Indexes ---- }

function DiagIndexes: TDiagLines;
var
  Settings: TDragLintSettings;
  LibPath : string           ;
  LibWhy  : string           ;
  Plat    : string           ;
  Proj    : string           ;
  Dbs     : TArray<string>   ;
  P       : string           ;
  Sev     : TDiagSeverity    ;
begin
  Result:= nil;
  Settings:= LoadSettings;

  Plat:= GetActivePlatformForLibrary;
  if Plat = '' then Plat:= '(no active project)';
  Proj:= GetActiveProjectFilePath;
  if Proj = '' then Proj:= '(none open)';
  Add(Result, Line('Active project', Proj));
  Add(Result, Line('Active platform', Plat));

  { THE most valuable line on this screen. When the manifest rule fires the
    answer is trustworthy; when it does not, we are on a fallback and the index
    may be from any era -- which is exactly the condition that went unnoticed
    for months. Say which one it is, in words, every time. }
  LibWhy := '';
  LibPath:= '';
try
    LibPath:= GetPlatformAwareLibraryDbPathEx(Settings, LibWhy);
  except
    on E: Exception do
    begin
      LibWhy:= 'resolution RAISED -- ' + E.ClassName + ': ' + E.Message;
      DebugLog('diagnose: library resolution raised -- ' + LibWhy);
    end;
  end;

  if not TFile.Exists(LibPath) then Sev:= dsBad
  else if Pos('manifest ', LibWhy) = 1 then Sev:= dsOk
  else Sev:= dsBad; { a fallback IS the defect, not a lesser mode }

  Add(Result, Line('Library index', LibPath, Sev));
  Add(Result, Line('  size / written', DescribeIndexFile(LibPath), Sev));
  if Sev = dsOk then
    Add(Result, Line('  chosen by', LibWhy, dsOk))
  else
    Add(Result, Line('  chosen by', 'FALLBACK -- ' + LibWhy, dsBad));

Dbs:= nil;
  try
    Dbs:= ResolveActiveIndexDbs(Settings);
  except
    on E: Exception do
    begin
      Add(Result, Line('Index', 'resolution FAILED -- ' + E.ClassName + ': ' + E.Message, dsBad));
      DebugLog('diagnose: ResolveActiveIndexDbs raised (indexes) -- ' + E.Message);
    end;
  end;
  for P in Dbs do
  begin
    if SameText(P, LibPath) then Continue; { already reported above }
    Add(Result, Line('Index', P, dsOk));
    Add(Result, Line('  size / written', DescribeIndexFile(P)));
  end;
  if Length(Dbs) = 0 then
    Add(Result, Line('Index', 'no project index resolved for the active file', dsBad));
end;

{ ---- Configuration ---- }

function DiagConfiguration: TDiagLines;
var
  Settings: TDragLintSettings;
  Sev     : TDiagSeverity    ;
begin
  Result  := nil;
  Settings:= LoadSettings;

  { A bare exe name is the specific misconfiguration that broke library
    resolution: ExtractFilePath('drag-lint.exe') is '', so anything derived from
    the engine DIRECTORY silently resolved relative to the IDE's working
    directory. It still "works" for spawning, because PATH lookup covers that --
    which is why it survived so long. }
  if Settings.ExePath = '' then
    Add(Result, Line('Settings.ExePath', '(empty) -- engine directory unknown', dsWarn, dfExePath))
  else if ExtractFilePath(Settings.ExePath) = '' then
    Add(Result, Line('Settings.ExePath', Settings.ExePath +
      '   BARE NAME -- no directory, so manifest lookups beside the engine cannot resolve', dsWarn, dfExePath))
  else if FileExists(Settings.ExePath) then
    Add(Result, Line('Settings.ExePath', Settings.ExePath, dsOk))
  else
    Add(Result, Line('Settings.ExePath', Settings.ExePath + '   (does not exist)', dsBad, dfExePath));

  { The current layout is <projdir>\_D-RAG\<projname>.sqlite. A template without
    <projname> predates that move and resolves to a file that no longer exists,
    so project-DB resolution quietly falls through to the manifest or the
    ancestor walk. }
  if Pos('<projname>', Settings.DbPathTemplate) = 0 then Sev:= dsWarn else Sev:= dsOk;
  if Sev = dsWarn then
  begin
    Add(Result, Line('DB path template', Settings.DbPathTemplate, Sev, dfDbTemplate));
    Add(Result, Line('  note',
      'pre-_D-RAG template: has no <projname>, so it cannot name a per-project index', dsWarn));
  end
  else
    Add(Result, Line('DB path template', Settings.DbPathTemplate, Sev));

  if Settings.IncludeLibraryDb then
    Add(Result, Line('Include library DB', 'yes', dsOk))
  else
    Add(Result, Line('Include library DB',
      'NO -- RTL/VCL symbols will not resolve; used-unit checks will over-report', dsWarn));

  { The manifest beside the BPL is what makes library resolution work at all
    once ExePath is a bare name -- so its presence is load-bearing, not trivia. }
  if TFile.Exists(ManifestPathBesideEngine) then
    Add(Result, Line('Manifest (beside BPL)', ManifestPathBesideEngine, dsOk))
  else
    Add(Result, Line('Manifest (beside BPL)',
      'MISSING at ' + ManifestPathBesideEngine + ' -- library index cannot be resolved from the manifest', dsBad));
end;

{ ---- the full report ---- }

function SeverityMark(ASeverity: TDiagSeverity): string;
begin
  case ASeverity of
    dsOk  : Result:= '[ ok ] ';
    dsWarn: Result:= '[warn] ';
    dsBad : Result:= '[BAD ] ';
  else
    Result:= '       ';
  end;
end;

procedure AppendGroup(ASb: TStringBuilder; const ATitle: string; const ALines: TDiagLines);
var
  L: TDiagLine;
begin
  ASb.AppendLine(ATitle);
  ASb.AppendLine(StringOfChar('-', Length(ATitle)));
  for L in ALines do
    ASb.AppendLine(Format('%s%-24s %s', [SeverityMark(L.Severity), L.Caption, L.Value]));
  ASb.AppendLine('');
end;

function TailOfPluginLog(ACount: Integer): string;
var
  Path : string       ;
  Lines: TStringList  ;
  I    : Integer      ;
  Sb   : TStringBuilder;
begin
  Result:= '';
  Path  := GetPluginLogPath;
  if not TFile.Exists(Path) then Exit('(no plugin log at ' + Path + ')');
  Lines:= TStringList.Create;
  try
    try
      { Share-deny-none: the log is appended to concurrently by design. }
      var Fs: TFileStream:= TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
      try
        Lines.LoadFromStream(Fs);
      finally
        Fs.Free;
      end;
    except
      on E: Exception do Exit('(plugin log unreadable: ' + E.Message + ')');
    end;
    Sb:= TStringBuilder.Create;
    try
      I:= Lines.Count - ACount;
      if I < 0 then I:= 0;
      while I < Lines.Count do
      begin
        Sb.AppendLine(Lines[I]);
        Inc(I);
      end;
      Result:= Sb.ToString;
    finally
      Sb.Free;
    end;
  finally
    Lines.Free;
  end;
end;

function BuildDiagnoseReport(ALogTailLines: Integer = 40): string;
var
  Sb: TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    Sb.AppendLine('drag-lint -- diagnose current state');
    Sb.AppendLine('generated ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    Sb.AppendLine('');

    AppendGroup(Sb, 'Versions'     , DiagVersions     );
    AppendGroup(Sb, 'Connections'  , DiagConnections  );
    AppendGroup(Sb, 'Indexes'      , DiagIndexes      );
    AppendGroup(Sb, 'Configuration', DiagConfiguration);
    AppendGroup(Sb, 'Process'      , DiagProcess      );

    Sb.AppendLine(Format('Plugin log (last %d lines) -- %s', [ALogTailLines, GetPluginLogPath]));
    Sb.AppendLine(StringOfChar('-', 60));
    Sb.AppendLine(TailOfPluginLog(ALogTailLines));

    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
