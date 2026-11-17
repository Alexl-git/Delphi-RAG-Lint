unit DragLint.Plugin.Cmd152;

{ The 1.52 command table: every 1.52 editor / menu command lives in its OWN
  unit (DragLint.Plugin.Cmd.<X>.pas) and registers ONE row here from its
  initialization section. DragLint.Plugin.Editor calls BuildCmd152Menu once,
  from RegisterDragLintMenu, so no 1.52 lane edits Editor.pas again.

  WHO OWNS WHAT.
    Items are created through the host's item factory (Editor's AddWrappedItem),
    so the click wrappers stay in Editor's GWrappers and the items' lifetime in
    the drag-lint root menu (GMenuItems): ONE owner, ONE teardown path, exactly
    as BuildReportsMenu does. A submenu this unit has to create is owned by its
    parent menu item and dies with the root.

  HIDDEN UNTIL ENABLED.
    A row whose Visible is False is still created, with TMenuItem.Visible =
    False, so the menu the user sees is unchanged until the owning lane flips
    Visible in its own unit. A submenu created here is visible only when at
    least one of its rows is.

  ONE TABLE, TWO SURFACES (lane PLUGCTX).
    Each row names the surfaces it appears on: the drag-lint main menu
    (BuildCmd152Menu) and/or the code editor's right-click menu, under one
    "drag-lint" submenu (DragLint.Plugin.EditorLocalMenu). Needs says what the
    caret must be on for the item to be enabled there.

  No ToolsAPI here: tests\plugin\run_v152_PLUGFRAME_cmdtable.ps1 and
  run_v152_PLUGCTX_menu.ps1 compile this unit and the six stubs into a console
  program. }

interface

uses
  Vcl.Menus;

type
  /// <summary>The click handler of one 1.52 command.</summary>
  /// <param name="Sender">The clicked TMenuItem (main menu) or the TAction
  /// behind the clicked item (editor right-click menu).</param>
  /// <remarks>Assignment-compatible with Editor's TMenuProc, so the host
  /// factory can hand it straight to AddWrappedItem.</remarks>
  TCmd152Click = procedure(Sender: TObject);

  /// <summary>Where a 1.52 command is offered.</summary>
  /// <remarks>csMainMenu = the drag-lint main menu; csEditorContext = the
  /// code editor's right-click menu, submenu "drag-lint".</remarks>
  TCmd152Surface = (csMainMenu, csEditorContext);

  /// <summary>The surfaces of one row; never empty.</summary>
  TCmd152Surfaces = set of TCmd152Surface;

  /// <summary>What the caret must be on for the command to be enabled in
  /// the editor right-click menu.</summary>
  /// <remarks>cnNothing = always enabled; cnSymbol = an identifier under the
  /// caret; cnFinding = a drag-lint finding on the caret line.</remarks>
  TCmd152Needs = (cnNothing, cnSymbol, cnFinding);

  /// <summary>One row of the 1.52 command table.</summary>
  /// <remarks>
  /// Id is unique, lower-case, and names the feature entry the owning lane
  /// adds. ParentPath is the submenu chain under the drag-lint root,
  /// levels separated by '>' (spaces around it ignored); '' means the root
  /// itself. A level is matched against existing captions with hotkey
  /// ampersands ignored; a level that does not exist is created at the end of
  /// its parent. AfterCaption names the sibling the item is inserted after
  /// (same matching); '' or a caption not found appends.
  /// </remarks>
  TCmd152Command = record
    /// <summary>Unique command id, e.g. 'check-init'.</summary>
    Id: string;
    /// <summary>The 1.52 lane that owns the stub unit, e.g. 'HBIDE'.</summary>
    OwnerLane: string;
    /// <summary>Submenu chain under the drag-lint root; '' = the root.</summary>
    ParentPath: string;
    /// <summary>Sibling to insert after; '' = append.</summary>
    AfterCaption: string;
    /// <summary>The menu caption.</summary>
    Caption: string;
    /// <summary>False until the owning lane ships the command.</summary>
    Visible: Boolean;
    /// <summary>The click handler; must not be nil.</summary>
    Click: TCmd152Click;
    /// <summary>Main menu and/or editor right-click; must not be empty.</summary>
    Surfaces: TCmd152Surfaces;
    /// <summary>Caret context the editor item needs to be enabled.</summary>
    Needs: TCmd152Needs;
  end;

  /// <summary>The host's item factory: creates one clickable item, wires its
  /// click and appends it to pParent.</summary>
  /// <param name="pParent">The submenu to append to.</param>
  /// <param name="pCaption">The item caption.</param>
  /// <param name="pClick">The click handler.</param>
  /// <returns>The new item, already a child of pParent.</returns>
  TCmd152AddItem = reference to function(pParent: TMenuItem; const pCaption: string;
    pClick: TCmd152Click): TMenuItem;

/// <summary>Adds one row to the 1.52 command table.</summary>
/// <param name="pCommand">The row. Id must be non-empty and unique; Click
/// must be assigned; Surfaces must not be empty.</param>
/// <exception cref="EArgumentException">Raised on an empty or duplicate Id, a
/// nil Click or empty Surfaces.</exception>
/// <remarks>Called from the initialization section of each
/// DragLint.Plugin.Cmd.X unit, i.e. on package load, before Register runs.
/// Not thread-safe; main thread only.</remarks>
procedure RegisterCmd152(const pCommand: TCmd152Command);

/// <summary>The registered rows, sorted by Id.</summary>
/// <returns>A copy of the table; changing it does not change the
/// registry.</returns>
function Cmd152Table: TArray<TCmd152Command>;

/// <summary>The rows offered on one surface, in table order.</summary>
/// <param name="pTable">The rows (normally Cmd152Table).</param>
/// <param name="pSurface">The surface asked for.</param>
/// <returns>Every row whose Surfaces contain pSurface.</returns>
function Cmd152OnSurface(const pTable: TArray<TCmd152Command>;
  pSurface: TCmd152Surface): TArray<TCmd152Command>;

/// <summary>Whether a row's editor item is enabled for the caret
/// context.</summary>
/// <param name="pCommand">The row.</param>
/// <param name="pHasSymbol">An identifier is under the caret.</param>
/// <param name="pHasFinding">A drag-lint finding is on the caret line.</param>
/// <returns>True for cnNothing; else the matching flag.</returns>
function Cmd152Enabled(const pCommand: TCmd152Command; pHasSymbol, pHasFinding: Boolean): Boolean;

/// <summary>The full right-click menu path of a row, as feature-registry
/// surfaces spell it.</summary>
/// <param name="pCommand">The row.</param>
/// <returns>'Editor context > drag-lint > ' + the caption, hotkey ampersands
/// removed; '' when the row is not on csEditorContext.</returns>
function Cmd152EditorPath(const pCommand: TCmd152Command): string;

/// <summary>Creates one menu item per csMainMenu row under pRoot, hidden when
/// the row is not Visible.</summary>
/// <param name="pRoot">The drag-lint root menu item.</param>
/// <param name="pTable">The rows to place, in order (normally Cmd152Table);
/// rows without csMainMenu are skipped.</param>
/// <param name="pAddItem">The host's item factory (see TCmd152AddItem).</param>
/// <remarks>Main thread only. Visible items and their order are untouched
/// when every row is hidden. A submenu created here gets Visible = True only
/// if one of its rows (at any depth) is visible; an existing submenu is never
/// changed.</remarks>
procedure BuildCmd152Menu(pRoot: TMenuItem; const pTable: TArray<TCmd152Command>;
  const pAddItem: TCmd152AddItem);

/// <summary>Renders a menu tree as text, one item per line, two spaces of
/// indent per level; a hidden item is suffixed ' [hidden]'.</summary>
/// <param name="pRoot">The item whose children are rendered (pRoot itself is
/// not).</param>
/// <param name="pVisibleOnly">True skips hidden items and everything under
/// them, i.e. renders what the user sees.</param>
/// <returns>The rendering, CRLF-separated, or '' for no children.</returns>
function DumpMenuTree(pRoot: TMenuItem; pVisibleOnly: Boolean): string;  // dl:ok unused-public-symbol@4abc -- test seam: run_v152_PLUGFRAME_cmdtable.ps1 and the owning lanes' menu runners render the tree with it

/// <summary>The shared body of a stub command that is not implemented yet.</summary>
/// <param name="pId">The command id, shown in the message.</param>
/// <remarks>Only reachable when a lane sets Visible before it replaces the
/// stub's click; shows a message box.</remarks>
procedure Cmd152NotYetAvailable(const pId: string);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Vcl.Dialogs;

const
  PATH_SEP = '>';
  INDENT_STEP = '  ';
  HIDDEN_SUFFIX = ' [hidden]';
  EDITOR_PATH_PREFIX = 'Editor context > drag-lint > ';

var
  GCommands: TList<TCmd152Command>;

procedure RegisterCmd152(const pCommand: TCmd152Command);
begin
  if Trim(pCommand.Id) = '' then raise EArgumentException.Create('RegisterCmd152: empty Id');
  if not Assigned(pCommand.Click) then
    raise EArgumentException.CreateFmt('RegisterCmd152: %s has no Click', [pCommand.Id]);
  if pCommand.Surfaces = [] then
    raise EArgumentException.CreateFmt('RegisterCmd152: %s has no Surfaces', [pCommand.Id]);
  for var Cmd in GCommands do
    if SameText(Cmd.Id, pCommand.Id) then
      raise EArgumentException.CreateFmt('RegisterCmd152: duplicate Id %s', [pCommand.Id]);
  GCommands.Add(pCommand);
end;

function Cmd152Table: TArray<TCmd152Command>;
begin
  Result:= GCommands.ToArray;
  TArray.Sort<TCmd152Command>(Result, TComparer<TCmd152Command>.Construct(
    function(const pLeft, pRight: TCmd152Command): Integer
    begin
      Result:= CompareText(pLeft.Id, pRight.Id);
    end));
end;

function Cmd152OnSurface(const pTable: TArray<TCmd152Command>;
  pSurface: TCmd152Surface): TArray<TCmd152Command>;
begin
  Result:= nil;
  for var Cmd in pTable do
    if pSurface in Cmd.Surfaces then Result:= Result + [Cmd];
end;

function Cmd152Enabled(const pCommand: TCmd152Command; pHasSymbol, pHasFinding: Boolean): Boolean;
begin
  case pCommand.Needs of
    cnSymbol : Result:= pHasSymbol;
    cnFinding: Result:= pHasFinding;
    else Result:= True;
  end;
end;

function Cmd152EditorPath(const pCommand: TCmd152Command): string;
begin
  Result:= if csEditorContext in pCommand.Surfaces then EDITOR_PATH_PREFIX + StripHotkey(pCommand.Caption) else '';
end;

{ Child of pParent whose caption equals pCaption, hotkey ampersands ignored. }
function FindChild(pParent: TMenuItem; const pCaption: string): TMenuItem;
begin
  Result:= nil;
  for var i:= 0 to pParent.Count - 1 do
    if SameText(StripHotkey(pParent.Items[i].Caption), StripHotkey(pCaption)) then Exit(pParent.Items[i]);
end;

{ Walks / creates the submenu chain; every submenu created is added to pCreated. }
function EnsurePath(pRoot: TMenuItem; const pPath: string; pCreated: TList<TMenuItem>): TMenuItem;
begin
  Result:= pRoot;
  for var Level in SplitString(pPath, PATH_SEP) do
  begin
    var LevelName: string:= Trim(Level);
    if LevelName = '' then Continue;
    var Child: TMenuItem:= FindChild(Result, LevelName);
    if Child = nil then
    begin
      Child:= TMenuItem.Create(Result);
      Child.Caption:= LevelName;
      Child.Visible:= False;
      Result.Add(Child);
      pCreated.Add(Child);
    end;
    Result:= Child;
  end;
end;

function HasVisibleChild(pItem: TMenuItem): Boolean;
begin
  Result:= False;
  for var i:= 0 to pItem.Count - 1 do
    if pItem.Items[i].Visible then Exit(True);
end;

procedure BuildCmd152Menu(pRoot: TMenuItem; const pTable: TArray<TCmd152Command>;
  const pAddItem: TCmd152AddItem);
begin
  if (pRoot = nil) or not Assigned(pAddItem) then Exit;
  var Created: TList<TMenuItem>:= TList<TMenuItem>.Create;
  try
    for var Cmd in Cmd152OnSurface(pTable, csMainMenu) do
    begin
      var Parent: TMenuItem:= EnsurePath(pRoot, Cmd.ParentPath, Created);
      var After: TMenuItem:= nil;
      if Cmd.AfterCaption <> '' then After:= FindChild(Parent, Cmd.AfterCaption);
      var Item: TMenuItem:= pAddItem(Parent, Cmd.Caption, Cmd.Click);
      Item.Visible:= Cmd.Visible;
      if After <> nil then
      begin
        Parent.Remove(Item);
        Parent.Insert(After.MenuIndex + 1, Item);
      end;
    end;
    { Deepest first: a created submenu is listed after its created parent. }
    for var i:= Created.Count - 1 downto 0 do Created[i].Visible:= HasVisibleChild(Created[i]);
  finally
    Created.Free;
  end;
end;

procedure DumpLevel(pItem: TMenuItem; pVisibleOnly: Boolean; const pIndent: string; pOut: TStringBuilder);
begin
  for var i:= 0 to pItem.Count - 1 do
  begin
    var Child: TMenuItem:= pItem.Items[i];
    if pVisibleOnly and not Child.Visible then Continue;
    pOut.Append(pIndent).Append(Child.Caption);
    if not Child.Visible then pOut.Append(HIDDEN_SUFFIX);
    pOut.Append(sLineBreak);
    DumpLevel(Child, pVisibleOnly, pIndent + INDENT_STEP, pOut);
  end;
end;

function DumpMenuTree(pRoot: TMenuItem; pVisibleOnly: Boolean): string;
begin
  var Builder: TStringBuilder:= TStringBuilder.Create;
  try
    if pRoot <> nil then DumpLevel(pRoot, pVisibleOnly, '', Builder);
    Result:= Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure Cmd152NotYetAvailable(const pId: string);
begin
  ShowMessage('drag-lint: "' + pId + '" is not available in this build yet.');
end;

initialization
  GCommands:= TList<TCmd152Command>.Create;

finalization
  FreeAndNil(GCommands);

end.
