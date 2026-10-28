unit FeatureGen.Live;

{ Live reads from the drag-lint engine and the product sources: the --help text,
  the usage line of one verb, and the whole live surface the registry checks
  compare against (port of Get-LiveSurface in tools\FeatureRegistry.psm1 and the
  harvest helpers in tests\autotest\lib\DocsSurfaceHarvest.ps1 and
  CliFlagVerbMap.ps1). Every regex, threshold and error text follows the
  PowerShell original; PowerShell's case-insensitive operators (-eq, -contains,
  -match, hashtable keys, Sort-Object -Unique) are mirrored with SameText /
  roIgnoreCase / case-insensitive dictionaries. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.Generics.Collections
  ;

type
  /// <summary>Raised when the engine cannot be run, or a live harvest yields nothing usable.</summary>
  EFeatureGenLive = class(Exception);

  /// <summary>The engine --help text and per-verb usage lookup.</summary>
  /// <remarks>Not thread-safe. Tests use LoadFromText so they never need the live engine.</remarks>
  TLiveHelp = class
  strict private
    FLines: TArray<string>;
  public
    /// <summary>Runs "pExe --help" (stderr discarded) and keeps its stdout, replacing any earlier load.</summary>
    /// <param name="pExe">Full path of drag-lint.exe.</param>
    /// <exception cref="EFeatureGenLive">The engine cannot be started.</exception>
    procedure Load(const pExe: string);
    /// <summary>Keeps pText as the help text, replacing any earlier load.</summary>
    /// <param name="pText">Help text, any line ending.</param>
    procedure LoadFromText(const pText: string);
    /// <summary>First help line that starts a verb entry.</summary>
    /// <param name="pVerb">Verb, or "verb sub" (single spaces).</param>
    /// <returns>The first line matching ^\s{2}drag-lint\s+verb(?=\s|$), trimmed, runs of spaces collapsed to one; '' when none.</returns>
    function UsageFor(const pVerb: string): string;
    /// <summary>The loaded help text, one element per line (no line ending).</summary>
    /// <returns>Empty before any load.</returns>
    function Lines: TArray<string>;
    /// <summary>The loaded help text with CRLF line ends (the shape PowerShell's Out-String gives).</summary>
    /// <returns>'' before any load.</returns>
    function Text: string;
    /// <summary>Every verb the help documents (Get-HelpVerbList): the token after "drag-lint" on a line that starts with two whitespace characters.</summary>
    /// <returns>Sorted, unique (case-insensitive, as Sort-Object -Unique).</returns>
    function Verbs: TArray<string>;
  end;

  /// <summary>One row of the plugin's REPORT_QUESTIONS catalog.</summary>
  TReportQuestion = record
    Id: string;
    /// <summary>Menu caption, '&amp;&amp;' already reduced to '&amp;'.</summary>
    Caption: string;
    /// <summary>The rtk* kind naming the report group.</summary>
    Kind: string;
  end;

  /// <summary>One node of the engine's code-built menu tree (menu-tree/1), flattened with its full path.</summary>
  TMenuNodeRow = record
    /// <summary>Full display path, segments joined by ' > ' ('drag-lint > Reports > Compare...'); '&amp;&amp;' reduced to '&amp;'.</summary>
    Path: string;
    /// <summary>The node's own caption ('&amp;&amp;' reduced to '&amp;'); '' for a separator.</summary>
    Caption: string;
    /// <summary>root | submenu | item | separator | header | dynamic (the engine's kind names).</summary>
    Kind: string;
    /// <summary>Qualified click handler; '' for a separator, header or submenu.</summary>
    Handler: string;
    /// <summary>file:line of the statement that made the node.</summary>
    Source: string;
    /// <summary>certain | derived | unknown.</summary>
    Confidence: string;
  end;

  /// <summary>The live surface the registry checks compare against (Get-LiveSurface).</summary>
  /// <remarks>Fields are public so tests can build or extend a surface in memory (positive
  /// controls) without touching a file. The object owns RuleCatalog and the dictionaries.
  /// Not thread-safe.</remarks>
  TLiveSurface = class
  public
    /// <summary>Repository root the surface was harvested from; '' for an in-memory surface.</summary>
    Repo: string;  // dl:ok public-field@79a8 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>Engine exe the surface was harvested with; check D renders with it.</summary>
    Engine: string;  // dl:ok public-field@925b -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>Set by the caller when Harvest raised (its message); the checks then report it as one B finding and stop.</summary>
    HarvestError: string;  // dl:ok public-field@87dc -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>The engine --help text (TLiveHelp.Text); the docs checks judge flags against it.</summary>
    HelpText: string;
    /// <summary>Verbs listed by --help (TLiveHelp.Verbs).</summary>
    HelpVerbs: TArray<string>;  // dl:ok public-field@881d -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>Verbs dispatched by DRagLint.CLI.pas (Args.Command = '..'), sorted unique.</summary>
    DispatchVerbs: TArray<string>;  // dl:ok public-field@0a5a -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>verb -> sorted subcommands (CliFlagVerbMap.ps1 Get-CliVerbSubcommandMap); verbs with none are absent. Keys are case-insensitive.
    /// Harvest raises when it is empty (unlike Get-LiveSurface), so check B cannot pass vacuously.</summary>
    SubMap: TDictionary<string, TArray<string>>;  // dl:ok public-field@16bc -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>Main-menu captions (menu items, section headers, About buttons, report rows and group headers), dialog buttons excluded; first-seen order, unique (ordinal).</summary>
    Captions: TArray<string>;  // dl:ok public-field@e790 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>TButton / TBitBtn / TSpeedButton captions of the menu sources.</summary>
    DialogButtons: TArray<string>;  // dl:ok public-field@d253 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>About window button captions (Add(Proc)Button).</summary>
    AboutButtons: TArray<string>;  // dl:ok public-field@25c2 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>ide-context hosts that have a harvester, in harvest order.</summary>
    ContextHosts: TArray<string>;  // dl:ok public-field@6cb7 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>host -> its context-menu captions (single '&amp;' accelerator dropped). Keys are case-insensitive.</summary>
    ContextCaptions: TDictionary<string, TArray<string>>;  // dl:ok public-field@273d -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>MCP tools announced by HandleToolsList (ToolDescriptor calls), sorted unique.</summary>
    McpTools: TArray<string>;  // dl:ok public-field@c21c -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>MCP tools dispatched (ToolName = '..'), sorted unique.</summary>
    McpDispatch: TArray<string>;  // dl:ok public-field@d4ad -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>The parsed "rules --json" output; owned.</summary>
    RuleCatalog: TJSONValue;  // dl:ok public-field@773c -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>REPORT_QUESTIONS rows in source order.</summary>
    ReportQuestions: TArray<TReportQuestion>;  // dl:ok public-field@2e3a -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>The REPORT_QUESTION_COUNT constant.</summary>
    ReportQuestionCount: Integer;  // dl:ok public-field@6ff2 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>rtk* kind -> report group caption (the case 'else' arm fills kinds no arm names). Keys are case-insensitive.</summary>
    GroupCaptions: TDictionary<string, string>;  // dl:ok public-field@bbcc -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>The -Question ValidateSet of charts\src\New-DiagramArtifact.ps1, in declaration order.</summary>
    ChartValidateSet: TArray<string>;  // dl:ok public-field@903c -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>charts\src\Emit-*.ps1 file names except Emit-Common.ps1, sorted.</summary>
    EmitterFiles: TArray<string>;  // dl:ok public-field@42e6 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>Exe names build\pack-lint-release.ps1 requires in the payload.</summary>
    PackExes: TArray<string>;  // dl:ok public-field@e813 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>DRAGLINT_VERSION.</summary>
    ProductVersion: string;  // dl:ok public-field@47b8 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>DRAGLINT_EXTRACTOR_VERSION.</summary>
    ExtractorVersion: string;  // dl:ok public-field@625d -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>DRAGLINT_RESOLVER_VERSION.</summary>
    ResolverVersion: string;  // dl:ok public-field@ced4 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>SCHEMA_VERSION of the storage schema.</summary>
    SchemaVersion: string;  // dl:ok public-field@fb00 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    /// <summary>Where the main-menu tree came from: MENU_SOURCE_TREE when the engine's menu-tree verb read it
    /// (MenuNodes carries full paths), MENU_SOURCE_REGEX when the engine lacks the verb (Captions only, leaf checks).</summary>
    MenuSource: string;  // dl:ok public-field@d8cd -- REVIEWED 2026-10-23: plain data-holder class read directly by the checker, as every other field of this surface
    /// <summary>Every node under the menu-tree roots in tree order (external roots left out), with full paths; empty in regex mode.</summary>
    MenuNodes: TArray<TMenuNodeRow>;  // dl:ok public-field@45fc -- REVIEWED 2026-10-23: plain data-holder class read directly by the checker, as every other field of this surface
    /// <summary>The engine's menu-tree notes (dynamic captions, unparented items); empty in regex mode.</summary>
    MenuNotes: TArray<string>;  // dl:ok public-field@575f -- REVIEWED 2026-10-23: plain data-holder class read directly by the checker, as every other field of this surface
    /// <summary>Constructor: creates an empty surface (all lists empty, dictionaries allocated).</summary>
    constructor Create;
    destructor Destroy; override;
    /// <summary>Harvests every surface kind from pRepo's sources and the engine, replacing the current contents.</summary>
    /// <param name="pRepo">Repository root (src\, build\, charts\).</param>
    /// <param name="pEngine">Full path of drag-lint.exe (--help and rules --json; stderr discarded).</param>
    /// <exception cref="EFeatureGenLive">A harvest is empty or under its threshold; the message is the PowerShell
    /// Get-LiveSurface text ('live surface: ...'), so check B can report it verbatim.</exception>
    procedure Harvest(const pRepo, pEngine: string);
    /// <summary>The verbs that have subcommands (SubMap keys), sorted.</summary>
    /// <returns>A new array.</returns>
    function SubVerbs: TArray<string>;
    /// <summary>True when MenuSource is MENU_SOURCE_TREE: checks B and C compare full menu paths.</summary>
    /// <returns>False in regex mode or on an in-memory surface that never set MenuSource.</returns>
    function HasMenuTree: Boolean;
    /// <summary>The clickable leaves of the menu tree: MenuNodes whose Kind is MENU_KIND_ITEM, in tree order.</summary>
    /// <returns>A new array; empty in regex mode.</returns>
    function MenuLeaves: TArray<TMenuNodeRow>;
  end;

const
  /// <summary>MenuSource value: the tree came from the engine's menu-tree verb.</summary>
  MENU_SOURCE_TREE = 'menu-tree';
  /// <summary>MenuSource value: the engine lacks menu-tree; the flat regex harvest is all there is.</summary>
  MENU_SOURCE_REGEX = 'regex';
  /// <summary>Menu-tree node kind of a clickable leaf.</summary>
  MENU_KIND_ITEM = 'item';
  /// <summary>Menu-tree node kind of a caption the engine could not evaluate.</summary>
  MENU_KIND_DYNAMIC = 'dynamic';
  /// <summary>Menu-tree node kind of a separator ('-'); never a caption.</summary>
  MENU_KIND_SEPARATOR = 'separator';
  /// <summary>The IDE plugin project the menu tree is read from, repo-relative.</summary>
  PLUGIN_DPROJ = 'src\delphi-plugin\dclDragLintWizard.dproj';
  /// <summary>The plugin's project index, repo-relative (prepare_battery.ps1 keeps it current).</summary>
  PLUGIN_DB = 'src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite';

/// <summary>Runs a console program and returns its stdout, decoded as UTF-8.</summary>
/// <param name="pExe">Full path of the program (no PATH lookup).</param>
/// <param name="pArgs">Command-line arguments, already quoted.</param>
/// <returns>Everything the program wrote to stdout; '' when nothing.</returns>
/// <exception cref="EFeatureGenLive">The pipe cannot be created or the program cannot be started.</exception>
/// <remarks>stderr is discarded; waits for the program to exit; no timeout.</remarks>
function RunCapture(const pExe, pArgs: string): string;

/// <summary>RunCapture that also reports the program's exit code.</summary>
/// <param name="pExe">Full path of the program (no PATH lookup).</param>
/// <param name="pArgs">Command-line arguments, already quoted.</param>
/// <param name="pExitCode">Receives the process exit code.</param>
/// <returns>Everything the program wrote to stdout; '' when nothing.</returns>
/// <exception cref="EFeatureGenLive">The program cannot be started.</exception>
function RunCaptureCode(const pExe, pArgs: string; out pExitCode: Cardinal): string;

/// <summary>The comparison key of a menu path: every ' > ' segment CaptionKey'd, empty ones dropped, joined by ' > '.</summary>
/// <param name="pPath">'drag-lint > Uses &amp;&amp; Dependencies > Find Usages...'.</param>
/// <returns>'drag-lint > uses &amp; dependencies > find usages'. The engine's MenuPathKey is the same rule (shared test vector).</returns>
function MenuPathKey(const pPath: string): string;

/// <summary>Flattens a menu-tree/1 document (drag-lint menu-tree --format json) into path rows.</summary>
/// <param name="pJson">The document text.</param>
/// <param name="pNodes">Receives every node under "roots" in tree order with its full path; "external" roots are left out
/// (the drift rules ignore them). '&amp;&amp;' in captions is reduced to '&amp;' as in Captions.</param>
/// <param name="pNotes">Receives the document's "notes" strings.</param>
/// <exception cref="EFeatureGenLive">Not a JSON object, or its "schema" is not menu-tree/1.</exception>
procedure ParseMenuTreeJson(const pJson: string; out pNodes: TArray<TMenuNodeRow>; out pNotes: TArray<string>);

/// <summary>The normalised comparison key of a caption (Get-CaptionKey).</summary>
/// <param name="pCaption">Caption or menu-path segment.</param>
/// <returns>'&amp;&amp;' -> '&amp;', '...' and backtick/star/quote -> space, whitespace collapsed, trimmed, then
/// leading/trailing . , ; : ) ( trimmed, lower-cased.</returns>
function CaptionKey(const pCaption: string): string;

/// <summary>Sort-Object -Unique over strings: case-insensitive locale order, case-insensitive uniqueness.</summary>
/// <param name="pItems">Items in any order.</param>
/// <returns>A new sorted array; of items equal ignoring case, the first one kept.</returns>
function SortUniqueText(const pItems: TArray<string>): TArray<string>;

/// <summary>verb -> subcommands the verb accepts, derived from DRagLint.CLI.pas source (Get-CliVerbSubcommandMap).</summary>
/// <param name="pCliText">The whole CLI unit text.</param>
/// <param name="pOut">Receives verb -> sorted subcommands; verbs with none are not added. Not cleared first.</param>
/// <exception cref="EFeatureGenLive">The Run dispatcher implementation is not found.</exception>
/// <remarks>Comments, string literals (for the span scan) and inactive Win64 conditional branches are
/// blanked first; a subcommand belongs to every verb whose dispatch closure reaches its routine.</remarks>
procedure HarvestSubcommandMap(const pCliText: string; const pOut: TDictionary<string, TArray<string>>);

implementation

uses
  Winapi.Windows
  , System.IOUtils
  , System.RegularExpressions
  , System.Generics.Defaults
  ;

const
  CRLF = #13#10;
  MIN_HELP_VERBS = 20;
  MIN_DISPATCH_VERBS = 20;
  MIN_CAPTIONS = 40;
  RE_KIND_GROUP = 3;
  MENU_TREE_VERB = 'menu-tree';
  MENU_TREE_SCHEMA = 'menu-tree/1';
  MENU_TREE_EXIT_STALE = 3;
  PATH_SEP = ' > ';

function RunCapture(const pExe, pArgs: string): string;
var
  lCode: Cardinal;
begin
  Result := RunCaptureCode(pExe, pArgs, lCode);
end;

function RunCaptureCode(const pExe, pArgs: string; out pExitCode: Cardinal): string;
var
  lSa: TSecurityAttributes;
  lRead, lWrite, lNul: THandle;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lCmd: string;
  lBuf: array[0..4095] of Byte;  // dl:ok large-magic-number@f9bb -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
  lGot: DWORD;
  lMem: TMemoryStream;
  lBytes: TBytes;
  lCode: DWORD;
begin
  Result := '';
  pExitCode := 0;
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;
  lSa.lpSecurityDescriptor := nil;
  if not CreatePipe(lRead, lWrite, @lSa, 0) then
    raise EFeatureGenLive.Create('cannot create pipe');
  SetHandleInformation(lRead, HANDLE_FLAG_INHERIT, 0);
  lNul := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_WRITE, @lSa, OPEN_EXISTING, 0, 0);
  try
    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    lSi.wShowWindow := SW_HIDE;
    lSi.hStdOutput := lWrite;
    lSi.hStdError := lNul;
    lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    lCmd := '"' + pExe + '" ' + pArgs;
    UniqueString(lCmd);
    if not CreateProcess(PChar(pExe), PChar(lCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, lSi, lPi) then
      raise EFeatureGenLive.CreateFmt('cannot start engine "%s"', [pExe]);
    CloseHandle(lWrite);
    lWrite := 0;
    lMem := TMemoryStream.Create;
    try
      while ReadFile(lRead, lBuf, SizeOf(lBuf), lGot, nil) and (lGot > 0) do
        lMem.WriteBuffer(lBuf, lGot);
      WaitForSingleObject(lPi.hProcess, INFINITE);
      if not GetExitCodeProcess(lPi.hProcess, lCode) then
        lCode := High(Cardinal);
      pExitCode := lCode;
      CloseHandle(lPi.hProcess);
      CloseHandle(lPi.hThread);
      if lMem.Size > 0 then
      begin
        SetLength(lBytes, lMem.Size);
        Move(lMem.Memory^, lBytes[0], lMem.Size);
        Result := TEncoding.UTF8.GetString(lBytes);
      end;
    finally
      lMem.Free;
    end;
  finally
    if lWrite <> 0 then
      CloseHandle(lWrite);
    CloseHandle(lRead);
    if lNul <> INVALID_HANDLE_VALUE then
      CloseHandle(lNul);
  end;
end;

{ ---- small helpers ---- }

function SortUniqueText(const pItems: TArray<string>): TArray<string>;
var
  lSorted: TArray<string>;
  lIdx: TArray<Integer>;
  lList: TList<string>;
  i: Integer;
begin
  SetLength(lIdx, Length(pItems));
  for i := 0 to High(lIdx) do
    lIdx[i] := i;
  TArray.Sort<Integer>(lIdx, TComparer<Integer>.Construct(
    function(const pA, pB: Integer): Integer
    begin
      Result := AnsiCompareText(pItems[pA], pItems[pB]);
      if Result = 0 then
        Result := pA - pB;
    end));
  SetLength(lSorted, Length(lIdx));
  for i := 0 to High(lIdx) do
    lSorted[i] := pItems[lIdx[i]];
  lList := TList<string>.Create;
  try
    for i := 0 to High(lSorted) do
      if (lList.Count = 0) or (AnsiCompareText(lList.Last, lSorted[i]) <> 0) then
        lList.Add(lSorted[i]);
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function Matches1(const pText, pRe: string; pOptions: TRegExOptions = []): TArray<string>;
var
  lM: TMatch;
  lList: TList<string>;
begin
  lList := TList<string>.Create;
  try
    for lM in TRegEx.Matches(pText, pRe, pOptions) do
      lList.Add(lM.Groups[1].Value);
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function FirstGroup(const pText, pRe: string): string;
var
  lM: TMatch;
begin
  lM := TRegEx.Match(pText, pRe);
  Result := (if lM.Success then lM.Groups[1].Value else '');
end;

function ReadText(const pPath: string): string;
begin
  if TFile.Exists(pPath) then
    Result := TFile.ReadAllText(pPath)
  else
    Result := '';
end;

{ ('&&' -> marker, '&' dropped, marker -> '&').Trim: a context-menu caption. }
function DropAccelerator(const pCaption: string): string;
begin
  Result := pCaption.Replace('&&', #1).Replace('&', '').Replace(#1, '&').Trim;
end;

function CaptionKey(const pCaption: string): string;
var
  lS: string;
begin
  lS := pCaption.Replace('&&', '&');
  lS := lS.Replace('...', ' ');
  lS := TRegEx.Replace(lS, '[`*"]', ' ');
  lS := TRegEx.Replace(lS, '\s+', ' ');
  Result := LowerCase(lS.Trim.Trim(['.', ',', ';', ':', ')', '(']));
end;

function MenuPathKey(const pPath: string): string;
var
  lSeg, lK: string;
  lList: TList<string>;
begin
  lList := TList<string>.Create;
  try
    for lSeg in TRegEx.Split(pPath, '\s+>\s+') do
    begin
      lK := CaptionKey(lSeg);
      if lK <> '' then
        lList.Add(lK);
    end;
    Result := string.Join(PATH_SEP, lList.ToArray);
  finally
    lList.Free;
  end;
end;

{ ---- menu-tree/1 ---- }

function JStr(const pObj: TJSONObject; const pName: string): string;
var
  lV: TJSONValue;
begin
  lV := pObj.GetValue(pName);
  if lV is TJSONString then
    Result := TJSONString(lV).Value
  else
    Result := '';
end;

procedure FlattenMenuNodes(const pArr: TJSONArray; const pParentPath: string; const pOut: TList<TMenuNodeRow>);
var
  lV: TJSONValue;
  lO: TJSONObject;
  lRow: TMenuNodeRow;
  lKids: TJSONValue;
begin
  if pArr = nil then
    Exit;
  for lV in pArr do
  begin
    if not (lV is TJSONObject) then
      Continue;
    lO := TJSONObject(lV);
    lRow.Kind := JStr(lO, 'kind');
    lRow.Caption := JStr(lO, 'caption').Replace('&&', '&').Trim;
    lRow.Handler := JStr(lO, 'handler');
    lRow.Source := JStr(lO, 'source');
    lRow.Confidence := JStr(lO, 'confidence');
    if pParentPath = '' then
      lRow.Path := lRow.Caption
    else if lRow.Caption = '' then
      lRow.Path := pParentPath
    else
      lRow.Path := pParentPath + PATH_SEP + lRow.Caption;
    pOut.Add(lRow);
    lKids := lO.GetValue('children');
    if lKids is TJSONArray then
      FlattenMenuNodes(TJSONArray(lKids), lRow.Path, pOut);
  end;
end;

procedure ParseMenuTreeJson(const pJson: string; out pNodes: TArray<TMenuNodeRow>; out pNotes: TArray<string>);
var
  lV, lN, lItem: TJSONValue;
  lO: TJSONObject;
  lList: TList<TMenuNodeRow>;
  lNotes: TList<string>;
begin
  pNodes := nil;
  pNotes := nil;
  lV := TJSONObject.ParseJSONValue(pJson, False, False);
  if not (lV is TJSONObject) then
  begin
    lV.Free;
    raise EFeatureGenLive.Create('live surface: menu-tree --format json did not return a JSON object');
  end;
  lList := TList<TMenuNodeRow>.Create;
  lNotes := TList<string>.Create;
  try
    lO := TJSONObject(lV);
    if JStr(lO, 'schema') <> MENU_TREE_SCHEMA then
      raise EFeatureGenLive.CreateFmt('live surface: menu-tree returned schema ''%s''; expected %s', [JStr(lO, 'schema'), MENU_TREE_SCHEMA]);
    lN := lO.GetValue('roots');
    if lN is TJSONArray then
      FlattenMenuNodes(TJSONArray(lN), '', lList);
    lN := lO.GetValue('notes');
    if lN is TJSONArray then
      for lItem in TJSONArray(lN) do
        if lItem is TJSONString then
          lNotes.Add(TJSONString(lItem).Value);
    pNodes := lList.ToArray;
    pNotes := lNotes.ToArray;
  finally
    lNotes.Free;
    lList.Free;
    lV.Free;
  end;
end;

{ ---- TLiveHelp ---- }

procedure TLiveHelp.Load(const pExe: string);
begin
  LoadFromText(RunCapture(pExe, '--help'));
  // a crashing or half-started engine prints (almost) nothing: never build pages from an empty help
  if TRegEx.Matches(Text, '(?m)^\s{2}drag-lint\s+[a-z]').Count < MIN_HELP_VERBS then
    raise EFeatureGenLive.CreateFmt('engine help from %s lists fewer than %d verbs (engine crashed or not started?)', [pExe, MIN_HELP_VERBS]);
end;

procedure TLiveHelp.LoadFromText(const pText: string);
begin
  FLines := pText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function TLiveHelp.Lines: TArray<string>;
begin
  Result := FLines;
end;

function TLiveHelp.Text: string;
begin
  Result := string.Join(CRLF, FLines);
end;

function TLiveHelp.Verbs: TArray<string>;
begin
  Result := SortUniqueText(Matches1(Text, '(?m)^\s{2}drag-lint\s+([a-z][a-z0-9-]*)'));
end;

function TLiveHelp.UsageFor(const pVerb: string): string;
var
  lRe: TRegEx;
  lLine: string;
begin
  Result := '';
  lRe := TRegEx.Create('^\s{2}drag-lint\s+' + TRegEx.Escape(pVerb) + '(?=\s|$)');
  for lLine in FLines do
    if lRe.IsMatch(lLine) then
      Exit(TRegEx.Replace(Trim(lLine), ' {2,}', ' '));
end;

{ ---- the CLI subcommand map (CliFlagVerbMap.ps1) ---- }

type
  TPascalProjections = record
    NoComments: string;
    Code: string;
  end;

  TCondFrame = class
  public
    IsActive: Boolean;  // dl:ok public-field@0096 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
    Decided: Boolean;  // dl:ok public-field@2073 -- REVIEWED 2026-10-19: plain data-holder class read directly by the generator units (the PowerShell original was a hashtable); a property adds no encapsulation here
  end;

function IsLineBreak(pCh: Char): Boolean;
begin
  Result := (pCh = #13) or (pCh = #10);
end;

// ConvertTo-PascalProjections: two offset-preserving projections; NoComments keeps string
// literals, Code blanks them too. Brace and paren-star directives are kept in both.
function PascalProjections(const pText: string): TPascalProjections;
var
  lN, i, j, k: Integer;
  lNc, lCd: TArray<Char>;
  lCh: Char;
  lDirective: Boolean;

  procedure Blank(pFrom, pTo: Integer; pKeep: Boolean);
  var
    q: Integer;
  begin
    for q := pFrom to pTo do
      if pKeep or IsLineBreak(pText[q + 1]) then
      begin
        lNc[q] := pText[q + 1];
        lCd[q] := pText[q + 1];
      end
      else
      begin
        lNc[q] := ' ';
        lCd[q] := ' ';
      end;
  end;

begin
  lN := Length(pText);
  SetLength(lNc, lN);
  SetLength(lCd, lN);
  i := 0;
  while i < lN do
  begin
    lCh := pText[i + 1];
    if lCh = '{' then
    begin
      lDirective := (i + 1 < lN) and (pText[i + 2] = '$');
      j := Pos('}', pText, i + 1) - 1;
      if j < 0 then
        j := lN - 1;
      Blank(i, j, lDirective);
      i := j + 1;
      Continue;
    end;
    if (lCh = '(') and (i + 1 < lN) and (pText[i + 2] = '*') then
    begin
      lDirective := (i + 2 < lN) and (pText[i + 1 + Length('(*')] = '$');
      j := Pos('*)', pText, i + 1 + Length('(*')) - 1;
      if j < 0 then
        j := lN - 2;
      j := j + 1;
      Blank(i, j, lDirective);
      i := j + 1;
      Continue;
    end;
    if (lCh = '/') and (i + 1 < lN) and (pText[i + 2] = '/') then
    begin
      k := i;
      while (k < lN) and not IsLineBreak(pText[k + 1]) do
      begin
        lNc[k] := ' ';
        lCd[k] := ' ';
        Inc(k);
      end;
      i := k;
      Continue;
    end;
    if lCh = '''' then
    begin
      j := Pos('''', pText, i + 2) - 1;
      if j < 0 then
        j := lN - 1;
      for k := i to j do
      begin
        lNc[k] := pText[k + 1];
        lCd[k] := (if IsLineBreak(pText[k + 1]) then pText[k + 1] else ' ');
      end;
      i := j + 1;
      Continue;
    end;
    lNc[i] := lCh;
    lCd[i] := lCh;
    Inc(i);
  end;
  SetString(Result.NoComments, PChar(lNc), lN);
  SetString(Result.Code, PChar(lCd), lN);
end;

const
  PASCAL_DEFINED: array[0..3] of string = ('WIN64', 'CPUX64', 'MSWINDOWS', 'WIN32API');
  PASCAL_UNDEFINED: array[0..6] of string = ('WIN32', 'CPUX86', 'LINUX', 'POSIX', 'MACOS', 'ANDROID', 'IOS');
  NOT_A_CALLEE: array[0..23] of string = ('if', 'and', 'or', 'not', 'while', 'until', 'case', 'then', 'do', 'to',
    'downto', 'in', 'is', 'xor', 'div', 'mod', 'Length', 'Assigned', 'SizeOf', 'High', 'Low', 'Ord', 'Writeln', 'Write');

function InText(const pValue: string; const pList: array of string): Boolean;
var
  lS: string;
begin
  Result := False;
  for lS in pList do
    if SameText(pValue, lS) then
      Exit(True);
end;

{ Resolve-PascalConditionals: blanks the branches a Win64 compile skips. Directives are
  located in Code (strings blanked); an unruled symbol keeps both branches. }
function ResolveConditionals(const pIn: TPascalProjections): TPascalProjections;
var
  lNc, lCd: TArray<Char>;
  lStack: TObjectList<TCondFrame>;
  lM, lBodyM: TMatch;
  lBody, lWord, lRest, lSym: string;
  lFrame, lTop: TCondFrame;
  lInactive: Boolean;
  k, lNext, lN: Integer;
  lSpace: Integer;

  procedure BlankAt(pIdx: Integer);
  begin
    if not IsLineBreak(lNc[pIdx]) then
    begin
      lNc[pIdx] := ' ';
      lCd[pIdx] := ' ';
    end;
  end;

  function Push(pActive, pDecided: Boolean): TCondFrame;
  begin
    Result := TCondFrame.Create;
    Result.IsActive := pActive;
    Result.Decided := pDecided;
    lStack.Add(Result);
  end;

begin
  lN := Length(pIn.Code);
  lNc := pIn.NoComments.ToCharArray;
  lCd := pIn.Code.ToCharArray;
  lStack := TObjectList<TCondFrame>.Create(True);
  try
    for lM in TRegEx.Matches(pIn.Code, '\{\$[^}]*\}') do
    begin
      lBody := lM.Value.Substring(Length('{$'), Length(lM.Value) - Length('{$}')).Trim;
      lSpace := 1;
      while (lSpace <= Length(lBody)) and not CharInSet(lBody[lSpace], [' ', #9, #13, #10]) do
        Inc(lSpace);
      lWord := UpperCase(Copy(lBody, 1, lSpace - 1));
      lBodyM := TRegEx.Match(lBody, '^\S+\s+(.*)$', [roIgnoreCase]);
      lRest := (if lBodyM.Success then lBodyM.Groups[1].Value.Trim else '');
      if lWord = 'IFDEF' then
      begin
        lSym := UpperCase(lRest);
        if InText(lSym, PASCAL_DEFINED) then
          Push(True, True)
        else if InText(lSym, PASCAL_UNDEFINED) then
          Push(False, True)
        else
          Push(True, False);
      end
      else if lWord = 'IFNDEF' then
      begin
        lSym := UpperCase(lRest);
        if InText(lSym, PASCAL_DEFINED) then
          Push(False, True)
        else if InText(lSym, PASCAL_UNDEFINED) then
          Push(True, True)
        else
          Push(True, False);
      end
      else if lWord = 'IF' then
        Push(True, False)
      else if lWord = 'ELSEIF' then
      begin
        if lStack.Count > 0 then
        begin
          lTop := lStack.Last;
          lTop.IsActive := True;
          lTop.Decided := False;
        end;
      end
      else if lWord = 'ELSE' then
      begin
        if lStack.Count > 0 then
        begin
          lTop := lStack.Last;
          if lTop.Decided then
            lTop.IsActive := not lTop.IsActive
          else
            lTop.IsActive := True;
        end;
      end
      else if (lWord = 'ENDIF') or (lWord = 'IFEND') then
      begin
        if lStack.Count > 0 then
          lStack.Delete(lStack.Count - 1);
      end;
      lInactive := False;
      for lFrame in lStack do
        if not lFrame.IsActive then
          lInactive := True;
      for k := lM.Index - 1 to lM.Index + lM.Length - 2 do
        BlankAt(k);
      if lInactive then
      begin
        lNext := Pos('{$', pIn.Code, lM.Index + lM.Length) - 1;
        if lNext < 0 then
          lNext := lN;
        for k := lM.Index + lM.Length - 1 to lNext - 1 do
          BlankAt(k);
      end;
    end;
  finally
    lStack.Free;
  end;
  SetString(Result.NoComments, PChar(lNc), lN);
  SetString(Result.Code, PChar(lCd), lN);
end;

type
  TStrSet = TDictionary<string, Boolean>;

{ Get-ArgsCallees: routines a span hands AArgs / Args to (a qualified call is not one). }
procedure ArgsCallees(const pSpan, pSelf: string; const pOut: TStrSet);
var
  lM: TMatch;
  lCallee: string;
begin
  for lM in TRegEx.Matches(pSpan, '(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*(?:AArgs|Args)\b') do
  begin
    lCallee := lM.Groups[1].Value;
    if SameText(lCallee, pSelf) or InText(lCallee, NOT_A_CALLEE) then
      Continue;
    pOut.AddOrSetValue(lCallee, True);
  end;
end;

function HasBody(const pSpan: string): Boolean;
begin
  Result := TRegEx.IsMatch(pSpan, '(?m)^begin\b', [roIgnoreCase, roMultiLine]);
end;

procedure HarvestSubcommandMap(const pCliText: string; const pOut: TDictionary<string, TArray<string>>);
const
  SUB_RE = '(?:\bAArgs|(?<![A-Za-z0-9_.])Args)\.SubCommand\s*(?:=|<>)\s*''([a-z0-9][a-z0-9-]*)''';
  HEADER_RE = '^(?:procedure|function)\s+([A-Za-z_][A-Za-z0-9_]*)';
var
  lRes: TPascalProjections;
  lHeaders, lArms: TMatchCollection;
  lPer: TObjectDictionary<string, TStrSet>;
  lRoutines: TObjectDictionary<string, TStrSet>;
  lDispatch: TObjectDictionary<string, TStrSet>;
  lVerbOrder: TList<string>;
  lM: TMatch;
  h, lFrom, lTo, lRunBeg, lRunEnd: Integer;
  lName, lSpan, lVerb, lEntry, lR, lC, lKey: string;
  lSet, lSubs, lSeen: TStrSet;
  lTodo: TStack<string>;
  lFound: Boolean;
  lArr: TArray<string>;

  procedure AddSub(const pRoutine, pSub: string);
  var
    lS: TStrSet;
  begin
    if not lPer.TryGetValue(pRoutine, lS) then
    begin
      lS := TStrSet.Create;
      lPer.Add(pRoutine, lS);
    end;
    lS.AddOrSetValue(pSub, True);
  end;

begin
  lRes := ResolveConditionals(PascalProjections(pCliText));
  lPer := TObjectDictionary<string, TStrSet>.Create([doOwnsValues], TIStringComparer.Ordinal);
  lRoutines := TObjectDictionary<string, TStrSet>.Create([doOwnsValues], TIStringComparer.Ordinal);
  lDispatch := TObjectDictionary<string, TStrSet>.Create([doOwnsValues], TIStringComparer.Ordinal);
  lVerbOrder := TList<string>.Create;
  try
    lHeaders := TRegEx.Matches(lRes.Code, HEADER_RE, [roMultiLine]);
    // routine -> subcommand literals in its own span; routine -> callees (Get-CliRoutineMap)
    for h := 0 to lHeaders.Count - 1 do
    begin
      lName := lHeaders[h].Groups[1].Value;
      lFrom := lHeaders[h].Index;
      lTo := (if h + 1 < lHeaders.Count then lHeaders[h + 1].Index else Length(lRes.Code) + 1);
      lSpan := Copy(lRes.Code, lFrom, lTo - lFrom);
      if not HasBody(lSpan) then
        Continue;
      for lM in TRegEx.Matches(Copy(lRes.NoComments, lFrom, lTo - lFrom), SUB_RE) do
        AddSub(lName, lM.Groups[1].Value);
      if not lRoutines.TryGetValue(lName, lSet) then
      begin
        lSet := TStrSet.Create;
        lRoutines.Add(lName, lSet);
      end;
      ArgsCallees(lSpan, lName, lSet);
    end;
    // the Run dispatcher: first header named Run whose span has a body
    lFound := False;
    lRunBeg := 0;
    lRunEnd := 0;
    for h := 0 to lHeaders.Count - 1 do
    begin
      if not SameText(lHeaders[h].Groups[1].Value, 'Run') then
        Continue;
      lFrom := lHeaders[h].Index;
      lTo := (if h + 1 < lHeaders.Count then lHeaders[h + 1].Index else Length(lRes.Code) + 1);
      if HasBody(Copy(lRes.Code, lFrom, lTo - lFrom)) then
      begin
        lFound := True;
        lRunBeg := lFrom;
        lRunEnd := lTo;
        Break;
      end;
    end;
    if not lFound then
      raise EFeatureGenLive.Create('the Run dispatcher implementation was not found in the lexed source');
    lArms := TRegEx.Matches(lRes.NoComments, 'Args\.Command\s*=\s*''([a-z0-9-]+)''');
    lArr := nil;
    for lM in lArms do
      if (lM.Index >= lRunBeg) and (lM.Index < lRunEnd) then
        lArr := lArr + [IntToStr(lM.Index) + #9 + lM.Groups[1].Value];
    for h := 0 to High(lArr) do
    begin
      lFrom := StrToInt(lArr[h].Split([#9])[0]);
      lVerb := lArr[h].Split([#9])[1];
      lTo := (if h < High(lArr) then StrToInt(lArr[h + 1].Split([#9])[0]) else lRunEnd);
      lSpan := Copy(lRes.Code, lFrom, lTo - lFrom);
      if not lDispatch.TryGetValue(lVerb, lSet) then
      begin
        lSet := TStrSet.Create;
        lDispatch.Add(lVerb, lSet);
        lVerbOrder.Add(lVerb);
      end;
      ArgsCallees(lSpan, 'Run', lSet);
      for lM in TRegEx.Matches(Copy(lRes.NoComments, lFrom, lTo - lFrom), SUB_RE) do
        AddSub('Run:' + lVerb, lM.Groups[1].Value);
    end;
    // verb -> transitive closure of subcommands
    for lVerb in SortUniqueText(lVerbOrder.ToArray) do
    begin
      lSubs := TStrSet.Create;
      try
        if lPer.TryGetValue('Run:' + lVerb, lSet) then
          for lKey in lSet.Keys do
            lSubs.AddOrSetValue(lKey, True);
        for lEntry in lDispatch[lVerb].Keys do
        begin
          lSeen := TStrSet.Create;
          lTodo := TStack<string>.Create;
          try
            lTodo.Push(lEntry);
            while lTodo.Count > 0 do
            begin
              lR := lTodo.Pop;
              if lSeen.ContainsKey(lR) then
                Continue;
              lSeen.Add(lR, True);
              if lPer.TryGetValue(lR, lSet) then
                for lKey in lSet.Keys do
                  lSubs.AddOrSetValue(lKey, True);
              if not lRoutines.TryGetValue(lR, lSet) then
                Continue;
              for lC in lSet.Keys do
                if not lSeen.ContainsKey(lC) then
                  lTodo.Push(lC);
            end;
          finally
            lTodo.Free;
            lSeen.Free;
          end;
        end;
        if lSubs.Count > 0 then
          pOut.AddOrSetValue(lVerb, SortUniqueText(lSubs.Keys.ToArray));
      finally
        lSubs.Free;
      end;
    end;
  finally
    lVerbOrder.Free;
    lDispatch.Free;
    lRoutines.Free;
    lPer.Free;
  end;
end;

{ ---- TLiveSurface ---- }

constructor TLiveSurface.Create;
begin
  inherited Create;
  SubMap := TDictionary<string, TArray<string>>.Create(TIStringComparer.Ordinal);
  ContextCaptions := TDictionary<string, TArray<string>>.Create(TIStringComparer.Ordinal);
  GroupCaptions := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
end;

destructor TLiveSurface.Destroy;
begin
  RuleCatalog.Free;
  GroupCaptions.Free;
  ContextCaptions.Free;
  SubMap.Free;
  inherited;  // dl:ok inherited-bare@246d -- REVIEWED 2026-10-19: the direct ancestor method is the intended one
end;

function TLiveSurface.SubVerbs: TArray<string>;
begin
  Result := SortUniqueText(SubMap.Keys.ToArray);
end;

function TLiveSurface.HasMenuTree: Boolean;
begin
  Result := MenuSource = MENU_SOURCE_TREE;
end;

function TLiveSurface.MenuLeaves: TArray<TMenuNodeRow>;
var
  lRow: TMenuNodeRow;
begin
  Result := nil;
  for lRow in MenuNodes do
    if lRow.Kind = MENU_KIND_ITEM then
      Result := Result + [lRow];
end;

{ The menu tree from the engine's menu-tree verb; MENU_SOURCE_REGEX when pHelpVerbs lacks the verb
  (a pre-1.33 engine, the golden stub): the flat regex captions are then all the checks have. }
procedure HarvestMenuTree(const pRepo, pEngine: string; const pHelpVerbs: TArray<string>; const pLive: TLiveSurface);
var
  lV, lProj, lDb, lOut, lHint: string;
  lHas: Boolean;
  lCode: Cardinal;
begin
  pLive.MenuSource := MENU_SOURCE_REGEX;
  pLive.MenuNodes := nil;
  pLive.MenuNotes := nil;
  lHas := False;
  for lV in pHelpVerbs do
    if SameText(lV, MENU_TREE_VERB) then
      lHas := True;
  if not lHas then
    Exit;
  lProj := TPath.Combine(pRepo, PLUGIN_DPROJ);
  lDb := TPath.Combine(pRepo, PLUGIN_DB);
  if not TFile.Exists(lDb) then
    raise EFeatureGenLive.CreateFmt('live surface: menu-tree needs the plugin index %s -- build it: "%s" index --project "%s" --db "%s"',
      [lDb, pEngine, lProj, lDb]);
  lOut := RunCaptureCode(pEngine, Format('%s --project "%s" --db "%s" --format json', [MENU_TREE_VERB, lProj, lDb]), lCode);
  if lCode <> 0 then
  begin
    lHint := (if lCode = MENU_TREE_EXIT_STALE then
      Format(' -- the plugin index is stale; refresh it: "%s" index --project "%s" --db "%s"', [pEngine, lProj, lDb])
      else '');
    raise EFeatureGenLive.CreateFmt('live surface: menu-tree exited %d%s%s', [lCode, lHint,
      (if lOut.Trim = '' then '' else ' (' + lOut.Trim.Split([#10])[0].Trim + ')')]);
  end;
  ParseMenuTreeJson(lOut, pLive.MenuNodes, pLive.MenuNotes);
  if Length(pLive.MenuLeaves) = 0 then
    raise EFeatureGenLive.Create('live surface: menu-tree returned no menu items under its roots');
  pLive.MenuSource := MENU_SOURCE_TREE;
end;

{ Get-MenuSourceText: Editor.pas + AboutForm.pas + ReportText.pas, concatenated. }
function MenuSourceText(const pRepo: string): string;
var
  lF: string;
begin
  Result := '';
  for lF in ['DragLint.Plugin.Editor.pas', 'DragLint.Plugin.AboutForm.pas', 'DragLint.Plugin.ReportText.pas'] do
    Result := Result + ReadText(TPath.Combine(pRepo, 'src\delphi-plugin\' + lF));  // dl:ok concat-in-loop@e2ec -- REVIEWED 2026-10-19: builds one small bounded text (tens of lines) whose bytes must match the PowerShell output; not a hot path
end;

{ Get-DialogButtonCaptionRegex; '' when no button variable is declared. }
function DialogButtonRegex(const pSource: string): string;
var
  lNames: TList<string>;
  lM: TMatch;
  lN, lAlt: string;
  lSorted: TArray<string>;

  procedure AddName(const pName: string);
  var
    lX: string;
  begin
    for lX in lNames do
      if SameText(lX, pName) then
        Exit;
    lNames.Add(pName);
  end;

begin
  lNames := TList<string>.Create;
  try
    for lM in TRegEx.Matches(pSource, '(?i)\b((?:\w+\s*,\s*)*\w+)\s*:\s*T(?:Button|BitBtn|SpeedButton)\b') do
      for lN in lM.Groups[1].Value.Split([',']) do
        AddName(lN.Trim);
    for lM in TRegEx.Matches(pSource, '(?i)\b(\w+)\s*:=\s*T(?:Button|BitBtn|SpeedButton)\.Create\b') do
      AddName(lM.Groups[1].Value);
    for lN in lNames.ToArray do
      if TRegEx.IsMatch(lN, '^T(?:Button|BitBtn|SpeedButton)$', [roIgnoreCase]) then
        lNames.Remove(lN);
    if lNames.Count = 0 then
      Exit('');
    lSorted := SortUniqueText(lNames.ToArray);
    lAlt := '';
    for lN in lSorted do
      lAlt := lAlt + (if lAlt = '' then '' else '|') + TRegEx.Escape(lN);
    Result := '(?i)\b(?:' + lAlt + ')\.Caption\s*:=\s*''([^'']+)''';
  finally
    lNames.Free;
  end;
end;

procedure TLiveSurface.Harvest(const pRepo, pEngine: string);
const
  CAPTION_RES: array[0..5] of string = (
    'AddWrappedItem\(\s*\w+\s*,\s*''([^'']+)''',
    'AddSectionHeader\(\s*\w+\s*,\s*''([^'']+)''',
    'Add(?:Proc)?Button\(\s*''([^'']+)''',
    '\.Caption\s*:=\s*''([^'']+)''',
    '\bCaption:\s*''([^'']+)''',
    '\brtk\w+\s*:\s*Result\s*:=\s*''([^'']+)''');
var
  lHelp: TLiveHelp;
  lCli, lMenu, lRx, lS, lRt, lElse, lCore, lSchemaPas, lPack, lChart, lBlock, lF: string;
  lList, lSeen: TList<string>;
  lM: TMatch;
  lQ: TReportQuestion;
  lQs: TList<TReportQuestion>;
  lV: TJSONValue;
  lTotal: Integer;
  lH: string;
  lArr: TArray<string>;
begin
  Repo := pRepo;
  Engine := pEngine;
  if not TFile.Exists(pEngine) then
    raise EFeatureGenLive.CreateFmt('live surface: engine exe not found: %s (full path; a bare ''drag-lint'' resolves off PATH to a stale build)', [pEngine]);
  lHelp := TLiveHelp.Create;
  try
    lHelp.Load(pEngine);
    HelpVerbs := lHelp.Verbs;
    HelpText := lHelp.Text;
  finally
    lHelp.Free;
  end;
  if Length(HelpVerbs) <= MIN_HELP_VERBS then
    raise EFeatureGenLive.CreateFmt('live surface: --help yielded %d verb(s); expected > 20 -- the harvest is broken, not the CLI', [Length(HelpVerbs)]);
  lCli := ReadText(TPath.Combine(pRepo, 'src\cli\DRagLint.CLI.pas'));
  DispatchVerbs := SortUniqueText(Matches1(lCli, 'Args\.Command\s*=\s*''([a-z][a-z0-9-]*)'''));
  if Length(DispatchVerbs) <= MIN_DISPATCH_VERBS then
    raise EFeatureGenLive.CreateFmt('live surface: dispatch scan yielded %d verb(s); expected > 20', [Length(DispatchVerbs)]);
  SubMap.Clear;
  HarvestSubcommandMap(lCli, SubMap);
  // Not in Get-LiveSurface: an empty map would let check B's subcommand loop pass vacuously.
  if SubMap.Count = 0 then
    raise EFeatureGenLive.Create('live surface: 0 subcommands harvested from DRagLint.CLI.pas; expected > 0');
  // main-menu captions, dialog buttons apart
  lMenu := MenuSourceText(pRepo);
  lRx := DialogButtonRegex(lMenu);
  DialogButtons := nil;
  if lRx <> '' then
  begin
    lList := TList<string>.Create;
    try
      for lM in TRegEx.Matches(lMenu, lRx) do
        lList.Add(lM.Groups[1].Value.Replace('&&', '&').Trim);
      DialogButtons := SortUniqueText(lList.ToArray);
    finally
      lList.Free;
    end;
    lMenu := TRegEx.Replace(lMenu, lRx, '');
  end;
  lSeen := TList<string>.Create;
  try
    for lRx in CAPTION_RES do
      for lM in TRegEx.Matches(lMenu, lRx) do
      begin
        lS := lM.Groups[1].Value.Replace('&&', '&').Trim;
        if not lSeen.Contains(lS) then
          lSeen.Add(lS);
      end;
    Captions := lSeen.ToArray;
  finally
    lSeen.Free;
  end;
  if Length(Captions) < MIN_CAPTIONS then
    raise EFeatureGenLive.CreateFmt('live surface: %d caption(s) harvested; expected >= 40', [Length(Captions)]);
  // the menu TREE (paths) from the engine, when it has the verb; the flat captions above stay the
  // source for ide-about, tool-window, dialog texts and the exemption liveness check in both modes
  HarvestMenuTree(pRepo, pEngine, HelpVerbs, Self);
  lArr := Matches1(ReadText(TPath.Combine(pRepo, 'src\delphi-plugin\DragLint.Plugin.AboutForm.pas')), 'Add(?:Proc)?Button\(\s*''([^'']+)''');
  SetLength(AboutButtons, Length(lArr));
  for lTotal := 0 to High(lArr) do
    AboutButtons[lTotal] := lArr[lTotal].Replace('&&', '&').Trim;
  AboutButtons := SortUniqueText(AboutButtons);
  // context menus, per ide-context host
  ContextCaptions.Clear;
  ContextHosts := ['Structure form', 'Project Manager'];
  lList := TList<string>.Create;
  try
    for lS in Matches1(ReadText(TPath.Combine(pRepo, 'src\delphi-plugin\DragLint.Plugin.StructureForm.pas')), 'AddPopupItem\(\s*\w+\s*,\s*''([^'']+)''') do
      if DropAccelerator(lS) <> '-' then
        lList.Add(DropAccelerator(lS));
    ContextCaptions.Add('Structure form', SortUniqueText(lList.ToArray));
    lList.Clear;
    for lS in Matches1(ReadText(TPath.Combine(pRepo, 'src\delphi-plugin\DragLint.Plugin.ProjectMenu.pas')), 'MENU_CAPTION\s*=\s*''([^'']+)''') do
      lList.Add(DropAccelerator(lS));
    ContextCaptions.Add('Project Manager', lList.ToArray);
  finally
    lList.Free;
  end;
  for lH in ContextHosts do
    if Length(ContextCaptions[lH]) = 0 then
      raise EFeatureGenLive.CreateFmt('live surface: 0 context-menu captions harvested for host ''%s''', [lH]);
  // MCP
  lS := ReadText(TPath.Combine(pRepo, 'src\mcp\DRagLint.MCP.Server.pas'));
  McpTools := SortUniqueText(Matches1(lS, 'ToolDescriptor\(\s*''([a-z_]+)'''));
  McpDispatch := SortUniqueText(Matches1(lS, 'ToolName\s*=\s*''([a-z_]+)'''));
  if Length(McpTools) = 0 then
    raise EFeatureGenLive.Create('live surface: 0 MCP tools harvested from HandleToolsList (ToolDescriptor calls)');
  // rule catalog
  FreeAndNil(RuleCatalog);
  lV := TJSONObject.ParseJSONValue(RunCapture(pEngine, 'rules --json'), False, False);
  RuleCatalog := lV;
  lTotal := 0;
  if (lV is TJSONObject) and (TJSONObject(lV).GetValue('summary') is TJSONObject) then
    lTotal := StrToIntDef(TJSONObject(TJSONObject(lV).GetValue('summary')).GetValue('total').Value, 0);
  if lTotal <= 0 then
    raise EFeatureGenLive.Create('live surface: rules --json reports total 0');
  // report questions
  lRt := ReadText(TPath.Combine(pRepo, 'src\delphi-plugin\DragLint.Plugin.ReportText.pas'));
  lQs := TList<TReportQuestion>.Create;
  try
    for lM in TRegEx.Matches(lRt, '\(Id:\s*''([a-z-]+)''\s*;\s*Caption:\s*''([^'']+)''\s*;\s*Kind:\s*(rtk\w+)\s*\)') do
    begin
      lQ.Id := lM.Groups[1].Value;
      lQ.Caption := lM.Groups[2].Value.Replace('&&', '&');
      lQ.Kind := lM.Groups[RE_KIND_GROUP].Value;
      lQs.Add(lQ);
    end;
    ReportQuestions := lQs.ToArray;
  finally
    lQs.Free;
  end;
  if Length(ReportQuestions) = 0 then
    raise EFeatureGenLive.Create('live surface: 0 REPORT_QUESTIONS rows harvested');
  lM := TRegEx.Match(lRt, 'REPORT_QUESTION_COUNT\s*=\s*(\d+)');
  if not lM.Success then
    raise EFeatureGenLive.Create('live surface: REPORT_QUESTION_COUNT not found');
  ReportQuestionCount := StrToInt(lM.Groups[1].Value);
  GroupCaptions.Clear;
  for lM in TRegEx.Matches(lRt, '\b(rtk\w+)\s*:\s*Result\s*:=\s*''([^'']+)''') do
    GroupCaptions.AddOrSetValue(lM.Groups[1].Value, lM.Groups[2].Value.Replace('&&', '&'));
  lElse := FirstGroup(lRt, '(?s)function ReportGroupCaption\b(?:(?!\b(?:function|procedure)\b).)*?\belse\s+Result\s*:=\s*''([^'']+)''\s*;\s*end;');
  if lElse <> '' then
    for lQ in ReportQuestions do
      if not GroupCaptions.ContainsKey(lQ.Kind) then
        GroupCaptions.Add(lQ.Kind, lElse.Replace('&&', '&'));
  // chart ValidateSet, by regex on the param block
  lChart := ReadText(TPath.Combine(pRepo, 'charts\src\New-DiagramArtifact.ps1'));
  lBlock := FirstGroup(lChart, '(?si)\[ValidateSet\(([^)]*)\)\]\s*\[string\]\s*\$Question\b');
  ChartValidateSet := Matches1(lBlock, '''([^'']+)''');
  if Length(ChartValidateSet) = 0 then
    raise EFeatureGenLive.Create('live surface: New-DiagramArtifact.ps1 -Question has no ValidateSet');
  lList := TList<string>.Create;
  try
    if TDirectory.Exists(TPath.Combine(pRepo, 'charts\src')) then
      for lF in TDirectory.GetFiles(TPath.Combine(pRepo, 'charts\src'), 'Emit-*.ps1') do
        if not SameText(ExtractFileName(lF), 'Emit-Common.ps1') then
          lList.Add(ExtractFileName(lF));
    EmitterFiles := SortUniqueText(lList.ToArray);
  finally
    lList.Free;
  end;
  // pack-lint-release payload
  lPack := ReadText(TPath.Combine(pRepo, 'build\pack-lint-release.ps1'));
  lM := TRegEx.Match(lPack, 'foreach \(\$need in ''([^)]+)''\)');
  PackExes := nil;
  if lM.Success then
  begin
    lArr := TRegEx.Split(lM.Groups[1].Value, '''\s*,\s*''');
    for lS in lArr do
      PackExes := PackExes + [lS.Trim([''''])];
  end;
  if Length(PackExes) = 0 then
    raise EFeatureGenLive.Create('live surface: pack-lint-release.ps1 payload exe list not found');
  // versions
  lCore := ReadText(TPath.Combine(pRepo, 'src\core\DRagLint.Core.Model.pas'));
  lSchemaPas := ReadText(TPath.Combine(pRepo, 'src\storage\DRagLint.Storage.Schema.pas'));
  ProductVersion := FirstGroup(lCore, 'DRAGLINT_VERSION\s*=\s*''([^'']+)''');
  ExtractorVersion := FirstGroup(lCore, 'DRAGLINT_EXTRACTOR_VERSION\s*=\s*''([^'']+)''');
  ResolverVersion := FirstGroup(lCore, 'DRAGLINT_RESOLVER_VERSION\s*=\s*''([^'']+)''');
  SchemaVersion := FirstGroup(lSchemaPas, 'SCHEMA_VERSION\s*=\s*(\d+)');
  if ProductVersion = '' then
    raise EFeatureGenLive.Create('live surface: DRAGLINT_VERSION not found in DRagLint.Core.Model.pas');
end;

end.
