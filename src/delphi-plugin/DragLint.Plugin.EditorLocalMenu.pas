unit DragLint.Plugin.EditorLocalMenu;

{ The code editor's right-click menu (lane PLUGCTX, 1.52).

  WHICH HOOK. INTAEditorLocalMenu (IOTAEditorServices.GetEditorLocalMenu,
  ToolsAPI of Delphi 13). The IDE rebuilds the editor local menu every time it
  pops up, from the action lists registered here, and calls every action's
  OnUpdate first. So there is nothing per edit window to attach or detach: the
  menu survives editor open / close / undock by construction, and the
  enable-on-caret-context check runs exactly when the menu is about to show.
  (The older trick -- FindComponent('EditorLocalMenu') on each edit window
  form plus an OnPopup chain -- needs a notifier per window and breaks when
  another expert chains the same OnPopup.)

  WHAT. One "drag-lint" submenu, placed after the IDE's Refactor group, with
  one action per row of the 1.52 command table (DragLint.Plugin.Cmd152) whose
  Surfaces contain csEditorContext, in table order. A row that is not Visible
  gets a hidden action; the submenu is hidden while every row is. Enabled
  follows the row's Needs: an identifier under the caret (cnSymbol) or a
  drag-lint finding on the caret line (cnFinding).

  WHO OWNS WHAT. GActions (TActionList) owns every action; GHandler owns
  nothing. RegisterActionList does not take ownership, so
  UnregisterDragLintEditorLocalMenu unregisters FIRST and then frees the list.
  Both entry points are idempotent; the wizard's Destroyed, Editor's teardown
  and this unit's finalization all call Unregister, whichever runs first wins.

  Main thread only. }

interface

/// <summary>Registers the drag-lint submenu of the code editor's right-click
/// menu, built from the csEditorContext rows of the 1.52 command table.</summary>
/// <remarks>
/// Idempotent: a second call while registered does nothing. Call
/// after every DragLint.Plugin.Cmd.X unit has registered its row (i.e. from
/// the wizard's Register, not from an initialization section). Main thread
/// only. Silently does nothing when the IDE offers no
/// INTAEditorLocalMenu.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.RegisterDragLintMenu (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: DragLint.Plugin.Cmd152.Cmd152OnSurface, DragLint.Plugin.Cmd152.Cmd152Table, DragLint.Plugin.EditorLocalMenu.TEditorMenuHandler.Create, StringReplace, Supports, TAction</para>
/// <seealso cref="DragLint.Plugin.Cmd152.Cmd152OnSurface"/>
/// <seealso cref="DragLint.Plugin.Cmd152.Cmd152Table"/>
/// <seealso cref="DragLint.Plugin.EditorLocalMenu.TEditorMenuHandler.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RegisterDragLintEditorLocalMenu;

/// <summary>Unregisters the submenu and frees its actions.</summary>
/// <remarks>
/// Idempotent, never raises. Must run before the package unloads:
/// the IDE keeps the registered TActionList and would otherwise build the
/// next right-click menu from freed code.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.UnregisterDragLintMenu (DragLint.Plugin.Editor.pas), DragLint.Plugin.EditorLocalMenu.finalization (DragLint.Plugin.EditorLocalMenu.pas), DragLint.Plugin.Wizard.TDragLintWizard.Destroyed (DragLint.Plugin.Wizard.pas)</para>
/// <para>Calls: DragLint.Plugin.LspClient.DebugLog, FreeAndNil, Supports</para>
/// <para>Catches: Exception (swallowed)</para>
/// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure UnregisterDragLintEditorLocalMenu;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.ActnList,
  ToolsAPI,
  DragLint.Plugin.Cmd152,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.LspClient,
  DragLint.Plugin.Editor;

const
  { The submenu caption. The feature registry's Editor host is harvested from
    this constant (featuregen FeatureGen.Live) -- keep the name. }
  EDITOR_SUBMENU_CAPTION = 'drag-lint';
  { Action-list categories: the IDE nests 'X.Y' under the action of 'X'. }
  MENU_CATEGORY = 'DragLint';
  ITEMS_CATEGORY = MENU_CATEGORY + '.Commands';
  { One caret probe serves every OnUpdate of one popup. }
  CONTEXT_TTL_MS = 250;

type
  { Event sink for the actions. Holds the editor rows; Tag of an item action
    is its index in FRows. }
  TEditorMenuHandler = class
  private
    FRows: TArray<TCmd152Command>;
    FProbedAt: UInt64;
    FHasSymbol: Boolean;
    FHasFinding: Boolean;
    procedure ProbeCaret;
  public
    constructor Create(const pRows: TArray<TCmd152Command>);
    procedure SubmenuExecute(Sender: TObject);
    procedure ItemExecute(Sender: TObject);
    procedure ItemUpdate(Sender: TObject);
  end;

var
  GActions: TActionList;
  GHandler: TEditorMenuHandler;

constructor TEditorMenuHandler.Create(const pRows: TArray<TCmd152Command>);
begin
  inherited Create;
  FRows:= pRows;
end;

procedure TEditorMenuHandler.ProbeCaret;
var
  EditorServices: IOTAEditorServices;
begin
  var Now: UInt64:= TThread.GetTickCount64;
  if (FProbedAt <> 0) and (Now - FProbedAt < CONTEXT_TTL_MS) then Exit;
  FProbedAt:= Now;
  FHasSymbol:= False;
  FHasFinding:= False;
  try
    var Ident: string:= IdentifierAtCursor;
    FHasSymbol:= (Ident <> '') and not CharInSet(Ident[1], ['0'..'9']);
    if not Supports(BorlandIDEServices, IOTAEditorServices, EditorServices) then Exit;
    var View: IOTAEditView:= EditorServices.TopView;
    if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then Exit;
    { Position.Row is 1-based; the diagnostic cache is 0-based. }
    FHasFinding:= Length(Cache.GetForLine(View.Buffer.FileName, View.Position.Row - 1)) > 0;
  except
    { A failed probe leaves the context-bound items disabled; the menu must still show. }
    on E: Exception do DebugLog('editor menu: caret probe failed: ' + E.Message);
  end;
end;

procedure TEditorMenuHandler.SubmenuExecute(Sender: TObject);
begin
  { A submenu parent: the IDE opens the children, nothing to run. }
end;

procedure TEditorMenuHandler.ItemExecute(Sender: TObject);
begin
  var Index: Integer:= (Sender as TAction).Tag;
  if (Index >= 0) and (Index < Length(FRows)) then FRows[Index].Click(Sender);
end;

procedure TEditorMenuHandler.ItemUpdate(Sender: TObject);
begin
  var Action: TAction:= Sender as TAction;
  if (Action.Tag < 0) or (Action.Tag >= Length(FRows)) or not Action.Visible then Exit;
  ProbeCaret;
  Action.Enabled:= Cmd152Enabled(FRows[Action.Tag], FHasSymbol, FHasFinding);
end;

procedure RegisterDragLintEditorLocalMenu;
var
  EditorServices: IOTAEditorServices;
begin
  if GActions <> nil then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorServices) then Exit;
  var LocalMenu: INTAEditorLocalMenu:= EditorServices.GetEditorLocalMenu;
  if LocalMenu = nil then Exit;

  var Rows: TArray<TCmd152Command>:= Cmd152OnSurface(Cmd152Table, csEditorContext);
  GHandler:= TEditorMenuHandler.Create(Rows);
  GActions:= TActionList.Create(nil);

  { The submenu parent comes first; the IDE drops a child listed before it. }
  var Submenu: TAction:= TAction.Create(GActions);  // dl:ok object-leak@c543 -- owned by GActions (Create(GActions)); freed with it in UnregisterDragLintEditorLocalMenu
  Submenu.ActionList:= GActions;
  Submenu.Category:= MENU_CATEGORY;
  Submenu.Caption:= EDITOR_SUBMENU_CAPTION;
  Submenu.DisableIfNoHandler:= False;
  Submenu.OnExecute:= GHandler.SubmenuExecute;
  Submenu.Visible:= False;

  { 1.52 FUSCOPE: a row with an EditorParent sits one level deeper. Its parent action gets a
    category of its own directly under MENU_CATEGORY (so the IDE nests it under the
    "drag-lint" submenu action) and its children that category + '.Items' (so they nest
    under it, the one action of that category). One parent action per distinct name. }
  var SubCategories: TStringList:= TStringList.Create;
  try
  for var i:= 0 to High(Rows) do
  begin
    var Category: string:= ITEMS_CATEGORY;
    if Rows[i].EditorParent <> '' then
    begin
      var SubIndex: Integer:= SubCategories.IndexOfName(Rows[i].EditorParent);
      if SubIndex < 0 then
      begin
        var SubCategory: string:= MENU_CATEGORY + '.' + StringReplace(Rows[i].EditorParent, ' ', '', [rfReplaceAll]);
        var SubAction: TAction:= TAction.Create(GActions); { owned by GActions; freed with it in UnregisterDragLintEditorLocalMenu }
        SubAction.ActionList:= GActions;
        SubAction.Category:= SubCategory;
        SubAction.Caption:= Rows[i].EditorParent;
        SubAction.DisableIfNoHandler:= False;
        SubAction.OnExecute:= GHandler.SubmenuExecute;
        SubAction.Visible:= False;
        SubIndex:= SubCategories.Add(Rows[i].EditorParent + '=' + SubCategory);
        SubCategories.Objects[SubIndex]:= SubAction;
      end;
      Category:= SubCategories.ValueFromIndex[SubIndex] + '.Items';
      if Rows[i].Visible then TAction(SubCategories.Objects[SubIndex]).Visible:= True;
    end;
    var Item: TAction:= TAction.Create(GActions);  // dl:ok object-leak@cef6 -- owned by GActions (Create(GActions)); freed with it in UnregisterDragLintEditorLocalMenu
    Item.ActionList:= GActions;
    Item.Category:= Category;
    Item.Caption:= Rows[i].Caption;
    Item.Tag:= i;
    Item.Visible:= Rows[i].Visible;
    Item.OnExecute:= GHandler.ItemExecute;
    Item.OnUpdate:= GHandler.ItemUpdate;
    if Rows[i].Visible then Submenu.Visible:= True;
  end;
  finally
    SubCategories.Free;
  end;

  LocalMenu.RegisterActionList(GActions, MENU_CATEGORY, cEdMenuCatRefactor);
end;

procedure UnregisterDragLintEditorLocalMenu;
var
  EditorServices: IOTAEditorServices;
begin
  if GActions = nil then Exit;
  try
    if Supports(BorlandIDEServices, IOTAEditorServices, EditorServices) and
       (EditorServices.GetEditorLocalMenu <> nil) then
      EditorServices.GetEditorLocalMenu.UnregisterActionList(MENU_CATEGORY);
  except
    { IDE shutdown: the services may already be gone; freeing below is still right. }
    on E: Exception do DebugLog('editor menu: unregister failed: ' + E.Message);
  end;
  FreeAndNil(GActions);
  FreeAndNil(GHandler);
end;

initialization

finalization
  UnregisterDragLintEditorLocalMenu;

end.
