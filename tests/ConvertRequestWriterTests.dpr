program ConvertRequestWriterTests;
{$APPTYPE CONSOLE}
{ C-PLUGIN-CONVERT-HANDOFF: the plugin's half of the C12 contract, read back by the
  EDITOR's own parser, so a drift between the two halves fails here and not in an IDE.

  THE CASES, and what each one would catch being undone:
    1 the key-for-key document of the spec's example, as raw JSON.
    2 the editor's ParseConvertRequest accepts it and reads back every field; both scopes.
    3 the root is dropped; the root alone gives '' and no request.
    4 file name shape; LOCALAPPDATA in the folder.
    5 prune: an 8-day-old file goes, a 6-day-old one and a non-json stay; a missing folder is fine.
    6 the capability reader, against the editor's OWN CapabilitiesJson, and refusals.
    7 the launch command, with and without a request; the platform is never 'both'. }
uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Winapi.Windows,
  ConvRules.ConvertRequest in '..\src\tools\convrules-editor\ConvRules.ConvertRequest.pas',
  DragLint.Plugin.ConvertRequest in '..\src\delphi-plugin\DragLint.Plugin.ConvertRequest.pas';

var
  GPassed: Integer = 0;
  GFailed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then
  begin
    Inc(GPassed);
    Writeln('  [PASS] ', AName);
  end
  else
  begin
    Inc(GFailed);
    Writeln('  [FAIL] ', AName, ' ', ADetail);
  end;
end;

function Doc(const AScope: string; const ASel: TArray<TConvertComponent>; APid: Integer; AWhen: TDateTime): string;
var
  F: TConvertRequestFields;
begin
  F.Scope      := AScope;
  F.ProjectFile:= 'C:\P\CLIENT\App.dproj';
  F.ProjectDb  := 'C:\P\CLIENT\_D-RAG\App.sqlite';
  F.Platform   := 'Win64';
  F.Pas        := 'C:\P\CLIENT\DM\dmCP.pas';
  F.FormClass  := 'TdmCP';
  F.Components := ASel;
  F.IdePid     := APid;
  F.Written    := AWhen;
  Result:= BuildConvertRequestJson(F);
end;

function Comp(const AName, AType: string): TConvertComponent;
begin
  Result.Name:= AName;
  Result.TypeName:= AType;
end;

const
  PROJ = 'C:\P\CLIENT\App.dproj';
  DB   = 'C:\P\CLIENT\_D-RAG\App.sqlite';
  PAS  = 'C:\P\CLIENT\DM\dmCP.pas';
  WANT = '{"schema":"convert-request/1","written":"2026-10-06T14:02:11","source":"ide-menu","ide_pid":12345,'
    + '"scope":"selected","project_file":"C:\\P\\CLIENT\\App.dproj","project_db":"C:\\P\\CLIENT\\_D-RAG\\App.sqlite",'
    + '"platform":"Win64","units":[{"pas":"C:\\P\\CLIENT\\DM\\dmCP.pas","dfm":"C:\\P\\CLIENT\\DM\\dmCP.dfm",'
    + '"form_class":"TdmCP","components":[{"name":"tblFtrs","type":"TTable"},{"name":"qryScrap","type":"TQuery"}]}]}';

var
  When  : TDateTime;
  Json  : string;
  O     : TRequestOutcome;
  Sel   : TArray<TConvertComponent>;
  Dir   : string;
begin
  When:= EncodeDateTime(2026, 10, 6, 14, 2, 11, 0);
  Sel:= [Comp('tblFtrs', 'TTable'), Comp('qryScrap', 'TQuery')];

  Json:= Doc('selected', Sel, 12345, When);
  Check('1 the document, key for key', Json = WANT, Json);

  O:= ParseConvertRequest(Json);
  Check('2a the editor accepts it', O.Ok, O.Error);
  Check('2b schema, source, pid', (O.Request.Schema = REQUEST_SCHEMA) and (O.Request.Source = 'ide-menu') and (O.Request.IdePid = 12345));
  Check('2c scope', O.Request.Scope = rsSelected);
  Check('2d project and platform', (O.Request.ProjectFile = PROJ) and (O.Request.ProjectDb = DB) and (O.Request.Platform = 'Win64'));
  Check('2e the unit', (Length(O.Request.Units) = 1) and (O.Request.Units[0].Pas = PAS)
    and (O.Request.Units[0].Dfm = 'C:\P\CLIENT\DM\dmCP.dfm') and (O.Request.Units[0].FormClass = 'TdmCP'));
  Check('2f the components', (Length(O.Request.Units[0].Components) = 2)
    and (O.Request.Units[0].Components[1].Name = 'qryScrap') and (O.Request.Units[0].Components[1].TypeName = 'TQuery'));
  O:= ParseConvertRequest(Doc('form', Sel, 1, When));
  Check('2g the form scope', O.Ok and (O.Request.Scope = rsForm), O.Error);

  Sel:= SelectionWithoutRoot([Comp('dmCP', 'TdmCP'), Comp('tblFtrs', 'TTable')], 'DMCP');
  Check('3a the root is dropped', (Length(Sel) = 1) and (Sel[0].Name = 'tblFtrs'));
  Sel:= SelectionWithoutRoot([Comp('dmCP', 'TdmCP')], 'dmCP');
  Check('3b the root alone is an empty selection', Length(Sel) = 0);
  Check('3c an empty selection makes no request', Doc('selected', Sel, 1, When) = '');

  Check('4a file name', ConvertRequestFileName(When, 12345) = '20261006-140211-12345.json', ConvertRequestFileName(When, 12345));
  Check('4b folder', ConvertRequestsFolder('C:\Users\x\AppData\Local') = 'C:\Users\x\AppData\Local\drag-lint\convert-requests',
    ConvertRequestsFolder('C:\Users\x\AppData\Local'));

  Dir:= TPath.Combine(TPath.GetTempPath, 'dl-convert-prune-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'old.json'), 'x');
    TFile.WriteAllText(TPath.Combine(Dir, 'young.json'), 'x');
    TFile.WriteAllText(TPath.Combine(Dir, 'old.txt'), 'x');
    TFile.SetLastWriteTime(TPath.Combine(Dir, 'old.json'), IncDay(Now, -8));
    TFile.SetLastWriteTime(TPath.Combine(Dir, 'young.json'), IncDay(Now, -6));
    TFile.SetLastWriteTime(TPath.Combine(Dir, 'old.txt'), IncDay(Now, -8));
    Check('5a one file pruned', PruneConvertRequests(Dir, 7, Now) = 1);
    Check('5b the old one went', not TFile.Exists(TPath.Combine(Dir, 'old.json')));
    Check('5c positive control: the young one stayed', TFile.Exists(TPath.Combine(Dir, 'young.json')));
    Check('5d a file that is no request stayed', TFile.Exists(TPath.Combine(Dir, 'old.txt')));
  finally
    TDirectory.Delete(Dir, True);
  end;
  Check('5e a missing folder', PruneConvertRequests(Dir, 7, Now) = 0);

  Check('6a the editor''s own capabilities file', ParseEditorCapabilities(CapabilitiesJson) = CAPABILITY_CONVERT_REQUEST, CapabilitiesJson);
  Check('6b another schema', ParseEditorCapabilities('{"schema":"x/1","convert_request":1}') = 0);
  Check('6c garbage', ParseEditorCapabilities('not json') = 0);
  Check('6d a missing key', ParseEditorCapabilities('{"schema":"editor-capabilities/1"}') = 0);
  Check('6e an empty file', ParseEditorCapabilities('') = 0);

  Check('7a with a request', ConvertLaunchCommand('C:\e\ConvRulesEditor.exe', 'C:\r.json', PAS, DB, 'Win64')
    = '"C:\e\ConvRulesEditor.exe" --convert-request "C:\r.json" --form "C:\P\CLIENT\DM\dmCP.pas" --project-db "C:\P\CLIENT\_D-RAG\App.sqlite" --from-platform win64 --to-platform win64');
  Check('7b no request, no index', ConvertLaunchCommand('C:\e\ConvRulesEditor.exe', '', PAS, '', 'Win32')
    = '"C:\e\ConvRulesEditor.exe" --form "C:\P\CLIENT\DM\dmCP.pas" --from-platform win32 --to-platform win32');
  Check('7c never both', Pos('--from-platform win32 --to-platform win32', ConvertLaunchCommand('e', '', PAS, '', 'both')) > 0);

  Writeln(GPassed, ' passed, ', GFailed, ' failed');
  if GFailed > 0 then ExitCode:= 1;
end.