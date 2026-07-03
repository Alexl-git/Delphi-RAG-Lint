unit DragLint.Plugin.Keyboard;

{ Keystroke bindings for the drag-lint IDE plugin.
  Registers Ctrl+Alt+H/C/S/D/... via IOTAKeyboardServices.AddKeyboardBinding.
  Each binding checks the corresponding Enable* setting before dispatching
  to the matching Invoke* procedure in DragLint.Plugin.Editor.

  Circular-uses note: Editor's implementation uses this unit (to call
  Register/Unregister), and this unit's implementation uses Editor (to call
  Invoke*).  Delphi allows mutual implementation-section references.

  TKeyBindingProc is "of object", so key handlers must be methods of the
  binding object itself, not plain procedures.

  Ctrl+Alt+M (Extract Method) is the one exception: it is self-contained in
  this unit rather than delegating to DragLint.Plugin.Editor, because it
  needs OTAPI selection-block access and a preview-dialog round trip that
  Editor.pas does not otherwise expose. It calls
  DragLint.Plugin.RefactorForm.ShowExtractMethodDialog directly. }

interface

procedure RegisterDragLintKeystrokes;
procedure UnregisterDragLintKeystrokes;

implementation

uses
  System.SysUtils
  , System.Classes
  , Vcl.Menus
  , Vcl.Dialogs
  , Winapi.Windows
  , ToolsAPI
  , DragLint.Plugin.Settings
  , DragLint.Plugin.Editor
  , DragLint.Plugin.EditViewNotifier
  , DragLint.Plugin.RefactorForm
  ;

{ Forward decl: ExtractMethodKey (declared below, before InvokeExtractMethod's
  own definition further down this implementation section) calls it. }
procedure InvokeExtractMethod; forward;

{ ---- IOTAKeyboardBinding implementation ---- }

type
  TDragLintKeyboardBinding = class(TInterfacedObject, IOTAKeyboardBinding)
    public
      { IOTANotifier stubs (required by IOTAKeyboardBinding's parent interface) }
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      { IOTAKeyboardBinding }
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName       : string;
      { Key handler methods (TKeyBindingProc = procedure(...) of object) }
      procedure HoverKey       (const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure CompletionKey  (const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure SignatureKey   (const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure DiagnosticsKey (const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure RenameKey      (const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure ExtractMethodKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure InlineInfoKey  (const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure FindUsagesKey  (const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure SymbolSearchKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
      procedure QuickFixUsesKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
  end;

  { IOTANotifier stubs }

procedure TDragLintKeyboardBinding.AfterSave;
begin
end;

procedure TDragLintKeyboardBinding.BeforeSave;
begin
end;

procedure TDragLintKeyboardBinding.Destroyed;
begin
end;

procedure TDragLintKeyboardBinding.Modified;
begin
end;

{ IOTAKeyboardBinding }

procedure TDragLintKeyboardBinding.BindKeyboard( const BindingServices: IOTAKeyBindingServices);
begin
  BindingServices.AddKeyBinding( [ShortCut(Ord('H'), [ssCtrl, ssAlt])], HoverKey       , nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('C'), [ssCtrl, ssAlt])], CompletionKey  , nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('S'), [ssCtrl, ssAlt])], SignatureKey   , nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('D'), [ssCtrl, ssAlt])], DiagnosticsKey , nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('R'), [ssCtrl, ssAlt])], RenameKey      , nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('M'), [ssCtrl, ssAlt])], ExtractMethodKey, nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('I'), [ssCtrl, ssAlt])], InlineInfoKey  , nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('F'), [ssCtrl, ssAlt])], FindUsagesKey  , nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('T'), [ssCtrl, ssAlt])], SymbolSearchKey, nil);
  BindingServices.AddKeyBinding( [ShortCut(Ord('U'), [ssCtrl, ssAlt])], QuickFixUsesKey, nil);
end;

function TDragLintKeyboardBinding.GetBindingType: TBindingType;
begin
  Result:= btPartial;
end;

function TDragLintKeyboardBinding.GetDisplayName: string;
begin
  Result:= 'drag-lint Keybindings';
end;

function TDragLintKeyboardBinding.GetName: string;
begin
  Result:= 'DragLint.KeyboardBinding';
end;

{ Key handlers — check Enable* settings, then dispatch to Editor.Invoke* }

procedure TDragLintKeyboardBinding.HoverKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableHover then Exit;
  InvokeHover(nil);
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.CompletionKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableCompletion then Exit;
  InvokeCompletion(nil);
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.SignatureKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableSignature then Exit;
  InvokeSignatureHelp(nil);
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.DiagnosticsKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableDiagnostics then Exit;
  InvokeDiagnostics(nil);
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.RenameKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  InvokeRename(nil);
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.ExtractMethodKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  InvokeExtractMethod;
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.InlineInfoKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  if not LoadSettings.EnableInlineMarkers then Exit;
  InvokeInlineInfo;
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.FindUsagesKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  InvokeFindUsages(nil);
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.SymbolSearchKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  InvokeSymbolSearch(nil);
  BindingResult:= krHandled;
end;

procedure TDragLintKeyboardBinding.QuickFixUsesKey(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  InvokeQuickFixUses(nil);
  BindingResult:= krHandled;
end;

{ ---- Extract Method (Ctrl+Alt+M) ---- }

function DLExtractMethodExe: string;
{ KEEP IN SYNC with DragLint.Plugin.Editor's private DLExe/DLExe64 (its
  implementation section -- neither is exported, so the logic is replicated
  here rather than called). Resolution order:
    1. the user-configured Settings ExePath override, if set and the file
       exists (same check DLExe performs; the shipped default value is the
       bare name 'drag-lint.exe', which fails FileExists and falls through);
    2. the Win64 build staged next to this BPL (third_party/dll-win64
       layout: "<bpl-dir>\..\dll-win64\drag-lint.exe") -- DLExe64's pick;
    3. bare "drag-lint.exe" (resolved via PATH by CreateProcess). }
var
  BplDir, Win64Exe: string;
begin
  Result:= LoadSettings.ExePath;
  if (Result <> '') and FileExists(Result) then Exit;
  BplDir  := ExtractFilePath(GetModuleName(HInstance));
  Win64Exe:= ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\drag-lint.exe';
  if FileExists(Win64Exe) then Exit(Win64Exe);
  Result:= 'drag-lint.exe';
end;

/// <summary>Ctrl+Alt+M handler. Reads the active IOTAEditView's non-empty
/// selection block and file name, saves the active module (the CLI reads
/// the file from disk), then opens the Extract Method preview dialog
/// (name prompt -&gt; dry-run preview -&gt; apply). On a successful apply the
/// module is closed and reopened so the IDE picks up the CLI's edits from
/// disk instead of showing the stale in-memory buffer.</summary>
/// <remarks>Shows a message and returns without opening the dialog if there
/// is no active editor view or the selection is empty (mirrors InvokeRename's
/// "no active editor view" guard in DragLint.Plugin.Editor). Call from the
/// main IDE thread only (creates a modal VCL form).</remarks>
procedure InvokeExtractMethod;
var
  ESS      : IOTAEditorServices ;
  MS       : IOTAModuleServices ;
  EditView : IOTAEditView       ;
  Block    : IOTAEditBlock      ;
  Modu     : IOTAModule         ;
  FilePath : string             ;
  FromLine : Integer            ;
  ToLine   : Integer            ;
  ExePath  : string             ;
  Applied  : Boolean            ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    ShowMessage('drag-lint: no editor services available');
    Exit;
  end;
  EditView:= ESS.TopView;
  if EditView = nil then
  begin
    ShowMessage('drag-lint: no active editor view');
    Exit;
  end;
  FilePath:= EditView.Buffer.FileName;
  if FilePath = '' then
  begin
    ShowMessage('drag-lint: active buffer has no file name');
    Exit;
  end;

  { Selection read: IOTAEditBlock rows are 1-based, matching --from-line/
    --to-line's contract. IsValid/Size = 0 both mean "no real selection". }
  Block:= EditView.Block;
  if (Block = nil) or not Block.IsValid or (Block.Size <= 0) then
  begin
    ShowMessage('drag-lint: select a run of statements first (Ctrl+Alt+M needs a non-empty selection).');
    Exit;
  end;
  FromLine:= Block.StartingRow;
  ToLine  := Block.EndingRow;
  { A selection ending at column 1 of ToLine does not actually include any
    text on that line (e.g. a whole-line selection made by dragging to the
    start of the next line) -- treat it as ending on the previous line, same
    convention editors use when reporting "lines selected". }
  if (ToLine > FromLine) and (Block.EndingColumn <= 1) then Dec(ToLine);

  { Save so the on-disk file matches the editor before the CLI reads it
    (same rule InvokeGenerateFormsCsv/InvokeUsesFix/etc. follow in Editor.pas). }
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;

  ExePath:= DLExtractMethodExe;

  Applied:= ShowExtractMethodDialog(FilePath, FromLine, ToLine, ExePath);

  if Applied then
  begin
    { Reload from disk: close the module (discarding the now-stale in-memory
      buffer) and reopen it so the IDE shows the CLI's edits. Mirrors the
      rename dialog's "the file changed on disk, show the new content"
      intent; rename itself never needed this because it can touch files
      that are not open, but Extract Method always rewrites the open file. }
    if Supports(BorlandIDEServices, IOTAModuleServices, MS) then
    begin
      Modu:= MS.FindModule(FilePath);
      if Modu <> nil then Modu.CloseModule(False);
      MS.OpenModule(FilePath);
    end;
  end;
end; // procedure

{ ---- register / unregister ---- }

var
  GBindingIndex: Integer                  = -1                  ;
  GBinding     : TDragLintKeyboardBinding = nil;

procedure RegisterDragLintKeystrokes;
var
  KS: IOTAKeyboardServices;
begin
  if not Supports(BorlandIDEServices, IOTAKeyboardServices, KS) then Exit;
  GBinding:= TDragLintKeyboardBinding.Create;
  GBindingIndex:= KS.AddKeyboardBinding(GBinding);
end;

procedure UnregisterDragLintKeystrokes;
var
  KS: IOTAKeyboardServices;
begin
  if GBindingIndex < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, KS) then KS.RemoveKeyboardBinding(GBindingIndex);
  GBindingIndex:= -1;
  GBinding:= nil;
end;

end.
