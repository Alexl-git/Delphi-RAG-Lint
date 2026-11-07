unit DragLint.Plugin.ConvertRequest;

/// <summary>The pure half of the IDE hand-off to ConvRulesEditor (C12 plugin side): the
/// convert-request/1 document, its file name and folder, pruning, the launch command
/// lines and the reader of the editor's capabilities file.</summary>
/// <remarks>Contract: docs\superpowers\specs\2026-10-06-c12-ide-convert-menu-design.md,
/// "Hand-off contract". The reading half is ConvRules.ConvertRequest in the editor; the
/// test parses this unit's output with that unit. No VCL, no ToolsAPI.</remarks>

interface

type
  /// <summary>One component of the designer selection.</summary>
  TConvertComponent = record
    /// <summary>The component's Name on the form.</summary>
    Name    : string;
    /// <summary>The bare class, as IOTAComponent.GetComponentType gives it.</summary>
    TypeName: string;
  end;

  /// <summary>What a convert-request/1 document says.</summary>
  TConvertRequestFields = record
    /// <summary>selected or form.</summary>
    Scope      : string;
    /// <summary>The active project's file; must be the one ProjectDb belongs to.</summary>
    ProjectFile: string;
    /// <summary>The project index.</summary>
    ProjectDb  : string;
    /// <summary>The active platform, as Win32 or Win64.</summary>
    Platform   : string;
    /// <summary>Absolute path of the unit; its .dfm is the same name with .dfm.</summary>
    Pas        : string;
    /// <summary>The form or data module class.</summary>
    FormClass  : string;
    /// <summary>The selection WITHOUT the root (SelectionWithoutRoot).</summary>
    Components : TArray<TConvertComponent>;
    /// <summary>The IDE's process id.</summary>
    IdePid     : Integer;
    /// <summary>Stamped as ISO-8601 local time.</summary>
    Written    : TDateTime;
  end;

/// <summary>Drops the form itself from a designer selection.</summary>
/// <param name="pSelection">The selection, designer order.</param>
/// <param name="pRootName">The Name of the root component (case-insensitive).</param>
/// <returns>The rest, same order; empty when only the root was selected.</returns>
function SelectionWithoutRoot(const pSelection: TArray<TConvertComponent>; const pRootName: string): TArray<TConvertComponent>;

/// <summary>Builds a convert-request/1 document.</summary>
/// <param name="pFields">What the document says.</param>
/// <returns>The JSON text; '' when Components is empty, so an empty selection cannot
/// produce a request the editor would refuse with a less useful message.</returns>
function BuildConvertRequestJson(const pFields: TConvertRequestFields): string;

/// <summary>The folder requests live in.</summary>
/// <param name="pLocalAppData">%LOCALAPPDATA%. Not TEMP: TEMP is per-process, and the IDE
/// and a shell resolve it differently.</param>
/// <returns>...\drag-lint\convert-requests, no trailing delimiter.</returns>
function ConvertRequestsFolder(const pLocalAppData: string): string;

/// <summary>A request's file name.</summary>
/// <param name="pNow">The time to stamp.</param>
/// <param name="pPid">The IDE's process id.</param>
/// <returns>yyyymmdd-hhnnss-pid.json</returns>
function ConvertRequestFileName(pNow: TDateTime; pPid: Integer): string;

/// <summary>Deletes the .json files in a folder older than a number of days.</summary>
/// <param name="pFolder">The requests folder; a missing folder is not an error.</param>
/// <param name="pOlderThanDays">Age limit against the file's last write time.</param>
/// <param name="pNow">The current time.</param>
/// <returns>How many files were deleted.</returns>
/// <remarks>A file that cannot be deleted stays and is not counted: pruning must never
/// stop a hand-off. Only this folder, never recursive.</remarks>
function PruneConvertRequests(const pFolder: string; pOlderThanDays: Integer; pNow: TDateTime): Integer;

/// <summary>The editor's convert_request capability.</summary>
/// <param name="pJson">The text of the --write-capabilities file.</param>
/// <returns>The value, or 0 for garbage, another schema or a missing key.</returns>
function ParseEditorCapabilities(const pJson: string): Integer;

/// <summary>The command line that opens the editor.</summary>
/// <param name="pEditor">ConvRulesEditor.exe.</param>
/// <param name="pRequestFile">The request; '' opens the editor with no request.</param>
/// <param name="pPas">The unit for --form.</param>
/// <param name="pProjectDb">The index for --project-db; '' leaves the flag out.</param>
/// <param name="pPlatform">Win32 or Win64.</param>
/// <returns>The full command line; no .rules argument, the Convert tab needs no book.</returns>
function ConvertLaunchCommand(const pEditor, pRequestFile, pPas, pProjectDb, pPlatform: string): string;

implementation

uses
  System.SysUtils
  , System.DateUtils
  , System.IOUtils
  , System.JSON
  ;

const
  REQUEST_SCHEMA = 'convert-request/1';
  CAPABILITIES_SCHEMA = 'editor-capabilities/1';
  REQUEST_SOURCE = 'ide-menu';
  DFM_EXT = '.dfm';
  REQUEST_EXT = '.json';
  PLATFORM_WIN64 = 'win64';
  PLATFORM_WIN32 = 'win32';

function SelectionWithoutRoot(const pSelection: TArray<TConvertComponent>; const pRootName: string): TArray<TConvertComponent>;
begin
  Result:= nil;
  for var C in pSelection do
    if not SameText(C.Name, pRootName) then Result:= Result + [C];
end;

function BuildConvertRequestJson(const pFields: TConvertRequestFields): string;
var
  Doc  : TJSONObject;
  Units: TJSONArray ;
  U    : TJSONObject;
  Comps: TJSONArray ;
begin
  Result:= '';
  if Length(pFields.Components) = 0 then Exit;
  Doc:= TJSONObject.Create;
  try
    Doc.AddPair('schema'      , REQUEST_SCHEMA);
    Doc.AddPair('written'     , FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', pFields.Written));
    Doc.AddPair('source'      , REQUEST_SOURCE);
    Doc.AddPair('ide_pid'     , TJSONNumber.Create(pFields.IdePid));
    Doc.AddPair('scope'       , pFields.Scope);
    Doc.AddPair('project_file', pFields.ProjectFile);
    Doc.AddPair('project_db'  , pFields.ProjectDb);
    Doc.AddPair('platform'    , pFields.Platform);
    Units:= TJSONArray.Create;
    Doc.AddPair('units', Units);
    U:= TJSONObject.Create;
    Units.AddElement(U);
    U.AddPair('pas'       , pFields.Pas);
    U.AddPair('dfm'       , ChangeFileExt(pFields.Pas, DFM_EXT));
    U.AddPair('form_class', pFields.FormClass);
    Comps:= TJSONArray.Create;
    U.AddPair('components', Comps);
    for var C in pFields.Components do
      Comps.AddElement(TJSONObject.Create
        .AddPair('name', C.Name)
        .AddPair('type', C.TypeName));
    Result:= Doc.ToJSON;
  finally
    Doc.Free;
  end;
end;

function ConvertRequestsFolder(const pLocalAppData: string): string;
begin
  Result:= TPath.Combine(TPath.Combine(pLocalAppData, 'drag-lint'), 'convert-requests');
end;

function ConvertRequestFileName(pNow: TDateTime; pPid: Integer): string;
begin
  Result:= FormatDateTime('yyyymmdd"-"hhnnss', pNow) + '-' + IntToStr(pPid) + REQUEST_EXT;
end;

function PruneConvertRequests(const pFolder: string; pOlderThanDays: Integer; pNow: TDateTime): Integer;
begin
  Result:= 0;
  if not TDirectory.Exists(pFolder) then Exit;
  for var F in TDirectory.GetFiles(pFolder, '*' + REQUEST_EXT) do
    if DaysBetween(pNow, TFile.GetLastWriteTime(F)) >= pOlderThanDays then
    try
      TFile.Delete(F);
      Inc(Result);
    except  // dl:ok try-except-swallowed@16b2 -- a request in use stays for the next prune; pruning must never stop a hand-off
      on EInOutError do Continue; { in use or read-only: the next prune tries again }
    end;
end;

function ParseEditorCapabilities(const pJson: string): Integer;
var
  V     : TJSONValue;
  Schema: string    ;
begin
  Result:= 0;
  V:= TJSONObject.ParseJSONValue(pJson);
  try
    if V is not TJSONObject then Exit;
    if not V.TryGetValue<string>('schema', Schema) or (Schema <> CAPABILITIES_SCHEMA) then Exit;
    if not V.TryGetValue<Integer>('convert_request', Result) then Result:= 0;
  finally
    V.Free;
  end;
end;

{ win32 or win64; win32 for anything else. The hand-off never sends both. }
function EditorPlatformArg(const pPlatform: string): string;
begin
  Result:= if SameText(pPlatform, PLATFORM_WIN64) then PLATFORM_WIN64 else PLATFORM_WIN32;
end;

function ConvertLaunchCommand(const pEditor, pRequestFile, pPas, pProjectDb, pPlatform: string): string;
var
  Plat: string;
begin
  Plat:= EditorPlatformArg(pPlatform);
  Result:= Format('"%s"', [pEditor]);
  if pRequestFile <> '' then Result:= Result + Format(' --convert-request "%s"', [pRequestFile]);
  Result:= Result + Format(' --form "%s"', [pPas]);
  if pProjectDb <> '' then Result:= Result + Format(' --project-db "%s"', [pProjectDb]);
  Result:= Result + Format(' --from-platform %s --to-platform %s', [Plat, Plat]);
end;

end.