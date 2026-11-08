unit DragLint.Plugin.Bookmarks;

/// <summary>drag-lint > Bookmarks: lists, finds, strips and restores the `// dl:bk` comment
/// anchors of the current unit through the engine's bookmarks / bookmarks-strip /
/// bookmarks-restore verbs (E-BOOKMARKS, IDE half).</summary>
/// <remarks>Main thread only; every engine run is async (RunCliAsync), so the IDE never
/// waits on one. Nothing strips on its own (owner ruling 2026-09-22): Strip and Restore run
/// the verb's dry run first, show what it would do, and write only after a Yes. A unit with
/// unsaved changes is never stripped or restored. The pure half (command lines, JSON
/// readers, sidecar path) is DragLint.Plugin.BookmarksCore.</remarks>

interface

uses
  System.SysUtils
  ;

/// <summary>Lists the current unit's bookmarks and jumps to the one picked.</summary>
/// <param name="Sender">The menu item.</param>
procedure InvokeBookmarksList(Sender: TObject);

/// <summary>Asks for a bookmark number or CODE and jumps to it in the current unit.</summary>
/// <param name="Sender">The menu item.</param>
procedure InvokeBookmarksGoto(Sender: TObject);

/// <summary>Strips every bookmark from the current unit into a per-user sidecar, after a
/// dry run and a confirmation; the buffer is reloaded from disk.</summary>
/// <param name="Sender">The menu item.</param>
procedure InvokeBookmarksStrip(Sender: TObject);

/// <summary>Restores the bookmarks a picked sidecar recorded, after a dry run and a
/// confirmation; every open unit it touched is reloaded from disk.</summary>
/// <param name="Sender">The menu item.</param>
procedure InvokeBookmarksRestore(Sender: TObject);

var
  /// <summary>Opens AFile at ALine. Assigned by DragLint.Plugin.Editor (DLNavigateToSource)
  /// at wizard init, so this unit does not use Editor; nil = no jump.</summary>
  GBookmarkNavigate: TProc<string, Integer> = nil;
  /// <summary>Shows a pick list; returns the 0-based index picked or -1. Assigned by
  /// DragLint.Plugin.Editor (DLPickFromList) at wizard init; nil = the first row.</summary>
  GBookmarkPick: TFunc<string, string, TArray<string>, Integer> = nil;

implementation

uses
  System.IOUtils
  , System.UITypes
  , Vcl.Dialogs
  , ToolsAPI
  , DragLint.Plugin.BookmarksCore
  , DragLint.Plugin.CliAsync
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.Telemetry
  ;

const
  LOG_TOPIC = 'bookmarks';
  PAS_EXT = '.pas';
  EXIT_OK = 0;
  EXIT_NONE = 3;      { bookmarks / bookmarks-strip: no anchor found }
  EXIT_UNPLACED = 4;  { bookmarks-restore: at least one anchor could not be re-placed }
  CAPTION = 'drag-lint: Bookmarks';

{ ---- OTA ---- }

function CurrentModule: IOTAModule;
var
  MS: IOTAModuleServices;
begin
  Result:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then Result:= MS.CurrentModule;
end;

function FindModuleOf(const pPath: string): IOTAModule;
var
  MS: IOTAModuleServices;
begin
  Result:= nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then Result:= MS.FindModule(pPath);
end;

function ModuleIsDirty(const pModule: IOTAModule): Boolean;
begin
  Result:= False;
  for var I:= 0 to pModule.ModuleFileCount - 1 do
    if pModule.ModuleFileEditors[I].Modified then Exit(True);
end;

{ The current unit's .pas, or False with the reason shown. }
function CurrentPas(out pPas: string): Boolean;
var
  Module: IOTAModule;
begin
  pPas:= '';
  Module:= CurrentModule;
  if Module <> nil then pPas:= ChangeFileExt(Module.FileName, PAS_EXT);
  Result:= (pPas <> '') and FileExists(pPas);
  if not Result then ShowMessage('drag-lint: open a unit (.pas) first.');
end;

function Engine(out pExe: string): Boolean;
begin
  Result:= RequireEngine(pExe);
  if not Result then ShowMessage('drag-lint: ' + ENGINE_NOT_FOUND_MSG);
end;

{ The engine rewrites files on disk; a buffer with edits of its own would then be stale. }
function RefusedForUnsaved(const pPath: string): Boolean;
var
  Module: IOTAModule;
begin
  Module:= FindModuleOf(pPath);
  Result:= (Module <> nil) and ModuleIsDirty(Module);
  if Result then
    ShowMessage(ExtractFileName(pPath) + ' has unsaved changes -- save it first.');
end;

procedure ReloadFromDisk(const pPaths: TArray<string>);
begin
  for var P in pPaths do
    try
      var Module: IOTAModule:= FindModuleOf(P);
      if Module <> nil then Module.Refresh(True);
    except
      on E: Exception do DLT(LOG_TOPIC, 'reload ' + P + ': ' + E.ClassName + ': ' + E.Message);
    end;
end;

procedure Jump(const pRow: TBookmarkRow);
begin
  if Assigned(GBookmarkNavigate) then GBookmarkNavigate(pRow.FilePath, pRow.Line);
end;

{ ---- list / goto ---- }

procedure ListThen(const pCode: string; const pThen: TProc<TArray<TBookmarkRow>>);
var
  Exe: string;
  Pas: string;
begin
  if not CurrentPas(Pas) or not Engine(Exe) then Exit;
  RunCliAsync(BookmarksListCmdLine(Exe, Pas, pCode),
    procedure(AExitCode: Integer; const AOutput: string)
    var
      Rows: TArray<TBookmarkRow>;
    begin
      DLT(LOG_TOPIC, Format('list exit=%d', [AExitCode]));
      if (AExitCode = EXIT_NONE) or (ParseBookmarkRows(AOutput, Rows) and (Length(Rows) = 0)) then
        ShowMessage(if pCode = '' then 'drag-lint: no // dl:bk bookmark in ' + ExtractFileName(Pas) + '.'
                    else 'drag-lint: no bookmark ' + pCode + ' in ' + ExtractFileName(Pas) + '.')
      else if (AExitCode <> EXIT_OK) or (Length(Rows) = 0) then
        ShowMessage('drag-lint: bookmarks failed (exit ' + IntToStr(AExitCode) + '):' + sLineBreak + Trim(AOutput))
      else
        pThen(Rows);
    end);
end;

procedure InvokeBookmarksList(Sender: TObject);
begin
  ListThen('',
    procedure(ARows: TArray<TBookmarkRow>)
    var
      Items: TArray<string>;
      Pick : Integer;
    begin
      for var R in ARows do Items:= Items + [BookmarkRowText(R)];
      Pick:= if Assigned(GBookmarkPick) then GBookmarkPick(CAPTION, 'Go to bookmark:', Items) else 0;
      if (Pick >= 0) and (Pick < Length(ARows)) then Jump(ARows[Pick]);
    end);
end;

procedure InvokeBookmarksGoto(Sender: TObject);
var
  Code: string;
begin
  Code:= '';
  if not InputQuery(CAPTION, 'Bookmark number (3) or CODE (A7K3QX):', Code) then Exit;
  Code:= Trim(Code);
  if Code = '' then Exit;
  ListThen(Code,
    procedure(ARows: TArray<TBookmarkRow>)
    begin
      Jump(ARows[0]);
    end);
end;

{ ---- strip / restore ---- }

function SidecarFolder: string;
begin
  Result:= BookmarkSidecarFolder(GetEnvironmentVariable('LOCALAPPDATA'));
end;

procedure InvokeBookmarksStrip(Sender: TObject);
var
  Exe : string;
  Pas : string;
  Side: string;
begin
  if not CurrentPas(Pas) or not Engine(Exe) or RefusedForUnsaved(Pas) then Exit;
  Side:= BookmarkSidecarPath(GetEnvironmentVariable('LOCALAPPDATA'), Pas, Now);
  RunCliAsync(BookmarksStripCmdLine(Exe, Pas, Side, False),
    procedure(AExitCode: Integer; const AOutput: string)
    var
      C: TBookmarkVerbCounts;
    begin
      DLT(LOG_TOPIC, Format('strip dry run exit=%d', [AExitCode]));
      if AExitCode = EXIT_NONE then
      begin
        ShowMessage('drag-lint: no // dl:bk bookmark in ' + ExtractFileName(Pas) + ' -- nothing to strip.');
        Exit;
      end;
      if (AExitCode <> EXIT_OK) or not ParseBookmarkVerbCounts(AOutput, C) then
      begin
        ShowMessage('drag-lint: bookmarks-strip failed (exit ' + IntToStr(AExitCode) + '):' + sLineBreak + Trim(AOutput));
        Exit;
      end;
      if MessageDlg(Format('Strip %d bookmark(s) from %s?'#13#10#13#10'They are saved to %s; ' +
                           'drag-lint > Bookmarks > Restore puts them back.', [C.Count, ExtractFileName(Pas), Side]),
                    mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
      { The user may have typed into the unit while the dialog was up. }
      if RefusedForUnsaved(Pas) then Exit;
      TDirectory.CreateDirectory(SidecarFolder);
      RunCliAsync(BookmarksStripCmdLine(Exe, Pas, Side, True),
        procedure(AExit2: Integer; const AOut2: string)
        var
          C2: TBookmarkVerbCounts;
        begin
          DLT(LOG_TOPIC, Format('strip apply exit=%d', [AExit2]));
          ReloadFromDisk([Pas]);
          if (AExit2 = EXIT_OK) and ParseBookmarkVerbCounts(AOut2, C2) then
            ShowMessage(Format('drag-lint: stripped %d bookmark(s) from %s.', [C2.Count, ExtractFileName(Pas)]))
          else
            ShowMessage('drag-lint: bookmarks-strip --apply failed (exit ' + IntToStr(AExit2) + '):' + sLineBreak + Trim(AOut2));
        end);
    end);
end;

procedure InvokeBookmarksRestore(Sender: TObject);  // dl:ok too-many-exit-points@3fdf -- one Exit per refusal of a three-step flow (pick, dry run, apply); the steps are nested callbacks, so a single exit point would mean nesting each refusal
var
  Exe : string;
  Dlg : TOpenDialog;
  Side: string;
begin
  if not Engine(Exe) then Exit;
  Dlg:= TOpenDialog.Create(nil);
  try
    Dlg.Title     := CAPTION + ' -- pick the sidecar to restore';
    Dlg.Filter    := 'Bookmark sidecars (*.json)|*.json';
    Dlg.InitialDir:= SidecarFolder;
    Dlg.Options   := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    Side:= Dlg.FileName;
  finally
    Dlg.Free;
  end;
  RunCliAsync(BookmarksRestoreCmdLine(Exe, Side, False),
    procedure(AExitCode: Integer; const AOutput: string)
    var
      C: TBookmarkVerbCounts;
    begin
      DLT(LOG_TOPIC, Format('restore dry run exit=%d', [AExitCode]));
      if ((AExitCode <> EXIT_OK) and (AExitCode <> EXIT_UNPLACED)) or not ParseBookmarkVerbCounts(AOutput, C) then
      begin
        ShowMessage('drag-lint: bookmarks-restore failed (exit ' + IntToStr(AExitCode) + '):' + sLineBreak + Trim(AOutput));
        Exit;
      end;
      for var F in C.Files do
        if RefusedForUnsaved(F) then Exit;
      if C.Restored = 0 then
      begin
        ShowMessage(Format('drag-lint: nothing to restore -- %d already in place, %d cannot be placed.', [C.Already, C.Unplaced]));
        Exit;
      end;
      if MessageDlg(Format('Restore %d bookmark(s)?%s', [C.Restored,
                      if C.Unplaced > 0 then Format(#13#10#13#10'%d cannot be placed (their lines changed); ' +
                                                   'every file holding one is left untouched.', [C.Unplaced]) else '']),
                    mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
      for var F in C.Files do
        if RefusedForUnsaved(F) then Exit;
      RunCliAsync(BookmarksRestoreCmdLine(Exe, Side, True),
        procedure(AExit2: Integer; const AOut2: string)
        var
          C2: TBookmarkVerbCounts;
        begin
          DLT(LOG_TOPIC, Format('restore apply exit=%d', [AExit2]));
          if not ParseBookmarkVerbCounts(AOut2, C2) then
          begin
            ShowMessage('drag-lint: bookmarks-restore --apply failed (exit ' + IntToStr(AExit2) + '):' + sLineBreak + Trim(AOut2));
            Exit;
          end;
          ReloadFromDisk(C2.Files);
          ShowMessage(Format('drag-lint: restored %d bookmark(s); %d already in place; %d not placed.',
                             [C2.Restored, C2.Already, C2.Unplaced]));
        end);
    end);
end;

end.
