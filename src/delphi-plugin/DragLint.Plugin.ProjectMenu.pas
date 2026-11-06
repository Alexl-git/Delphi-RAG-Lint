unit DragLint.Plugin.ProjectMenu;

{ Project Manager right-click entry: "drag-lint: Project Rules...".

  Activates the clicked project (so per-project drag-lint-lint.json rules are
  edited for the RIGHT project, not whatever happened to be active), then opens
  and focuses the existing "Lint Options" tab in the drag-lint dockable panel.

  Mechanism: IOTAProjectManager.AddMenuItemCreatorNotifier (the supported,
  non-deprecated hook -- NOT the older INTAProjectMenuCreatorNotifier) lets us
  add a single menu item to a project node's context menu. AddMenu is called by
  the IDE for every Project Manager selection; we only add our item when
  exactly one project node (not a file, not multi-select) is selected. }

interface

uses
  System.Classes
  , ToolsAPI
  ;

type
  /// <summary>The right-click menu item: activates the clicked project then opens
  /// the Lint Options dock tab scoped to it.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DragLint.Plugin.ProjectMenu.TDLProjectMenuCreator.AddMenu (DragLint.Plugin.ProjectMenu.pas)</para>
  /// <para>Used in units: DragLint.Plugin.ProjectMenu</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDLProjectRulesMenu = class(TInterfacedObject, IOTANotifier, IOTALocalMenu, IOTAProjectManagerMenu)
    private
      FProject         : IOTAProject;
      FIsMultiSelectable: Boolean;
    public
      /// <summary><!-- drag-lint:auto sum -->---- TDLProjectRulesMenu ----</summary>
      /// <param name="AProject"><!-- drag-lint:auto type -->const IOTAProject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.ProjectMenu.TDLProjectMenuCreator.AddMenu (DragLint.Plugin.ProjectMenu.pas)</para>
      /// <para>constructor</para>
      /// <para>Writes: FProject, FIsMultiSelectable</para>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.AfterSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.BeforeSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Destroyed"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Execute"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.GetCaption"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const AProject: IOTAProject);
      { IOTANotifier }
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      { IOTALocalMenu }
      /// <summary><!-- drag-lint:auto sum -->IOTALocalMenu</summary>
      /// <returns><!-- drag-lint:auto -->string -- Observed: MENU_CAPTION.</returns>
      function GetCaption: string;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      function GetChecked: Boolean;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True.</returns>
      function GetEnabled: Boolean;
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: 0.</returns>
      function GetHelpContext: Integer;
      /// <returns><!-- drag-lint:auto -->string -- Observed: MENU_NAME.</returns>
      function GetName: string;
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
      function GetParent: string;
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1.</returns>
      function GetPosition: Integer;
      /// <returns><!-- drag-lint:auto -->string -- Observed: MENU_VERB.</returns>
      function GetVerb: string;
      procedure SetCaption(const Value: string);
      procedure SetChecked(Value: Boolean);
      procedure SetEnabled(Value: Boolean);
      procedure SetHelpContext(Value: Integer);
      procedure SetName(const Value: string);
      procedure SetParent(const Value: string);
      procedure SetPosition(Value: Integer);
      procedure SetVerb(const Value: string);
      { IOTAProjectManagerMenu }
      /// <summary><!-- drag-lint:auto sum -->IOTAProjectManagerMenu</summary>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: FIsMultiSelectable.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FIsMultiSelectable</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.AfterSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.BeforeSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Create"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Destroyed"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetIsMultiSelectable: Boolean;
      /// <param name="Value"><!-- drag-lint:auto type -->Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Writes: FIsMultiSelectable</para>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.AfterSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.BeforeSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Create"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Destroyed"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Execute"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetIsMultiSelectable(Value: Boolean);
      /// <param name="MenuContextList"><!-- drag-lint:auto type -->const IInterfaceList</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.DockForm.ShowDragLintDockLintOptions, Supports</para>
      /// <para>Reads: FProject</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DragLint.Plugin.DockForm.ShowDragLintDockLintOptions"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.AfterSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.BeforeSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Create"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Destroyed"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Execute(const MenuContextList: IInterfaceList); overload;
      /// <param name="MenuContextList"><!-- drag-lint:auto type -->const IInterfaceList</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      function PreExecute(const MenuContextList: IInterfaceList): Boolean;
      /// <param name="MenuContextList"><!-- drag-lint:auto type -->const IInterfaceList</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      function PostExecute(const MenuContextList: IInterfaceList): Boolean;
  end;

  /// <summary>Creator notifier: adds TDLProjectRulesMenu to a single project
  /// node's context menu (not files, not multi-select).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DragLint.Plugin.ProjectMenu.RegisterProjectMenu (DragLint.Plugin.ProjectMenu.pas)</para>
  /// <para>Used in units: DragLint.Plugin.ProjectMenu</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDLProjectMenuCreator = class(TInterfacedObject, IOTANotifier, IOTAProjectMenuItemCreatorNotifier)
    public
      { IOTANotifier }
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      { IOTAProjectMenuItemCreatorNotifier }
      /// <summary><!-- drag-lint:auto sum -->IOTAProjectMenuItemCreatorNotifier</summary>
      /// <param name="Project"><!-- drag-lint:auto type -->const IOTAProject</param>
      /// <param name="IdentList"><!-- drag-lint:auto type -->const TStrings</param>
      /// <param name="ProjectManagerMenuList"><!-- drag-lint:auto type -->const IInterfaceList</param>
      /// <param name="IsMultiSelect"><!-- drag-lint:auto type -->Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Create, SameText</para>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectRulesMenu.Create"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectMenuCreator.AfterSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectMenuCreator.BeforeSave"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectMenuCreator.Destroyed"/>
      /// <seealso cref="DragLint.Plugin.ProjectMenu.TDLProjectMenuCreator.Modified"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AddMenu(const Project: IOTAProject; const IdentList: TStrings;
        const ProjectManagerMenuList: IInterfaceList; IsMultiSelect: Boolean);
  end;

/// <summary>Registers the project-menu creator notifier with the IDE's Project
/// Manager so the "Project Rules..." item appears on project nodes. Idempotent
/// -- a second call is a no-op while already registered.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Wizard.Register (DragLint.Plugin.Wizard.pas)</para>
/// <para>Calls: Supports</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RegisterProjectMenu;

/// <summary>Unregisters the project-menu creator notifier. Idempotent; safe to
/// call even if RegisterProjectMenu was never called.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Wizard.TDragLintWizard.Destroyed (DragLint.Plugin.Wizard.pas), initialization/finalization (DragLint.Plugin.ProjectMenu.pas)</para>
/// <para>Calls: Supports</para>
/// <para>Catches: Exception (empty)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure UnregisterProjectMenu;

implementation

uses
  System.SysUtils
  , DragLint.Plugin.DockForm
  ;

const
  MENU_CAPTION = 'drag-lint: Project Rules...';
  MENU_VERB    = 'DragLint.ProjectRules';
  MENU_NAME    = 'DragLintProjectRulesMenuItem';

{ ---- TDLProjectRulesMenu ---- }

constructor TDLProjectRulesMenu.Create(const AProject: IOTAProject);
begin
  inherited Create;
  FProject:= AProject;
  FIsMultiSelectable:= False;
end;

{ IOTANotifier stubs }

procedure TDLProjectRulesMenu.AfterSave;
begin
end;

procedure TDLProjectRulesMenu.BeforeSave;
begin
end;

procedure TDLProjectRulesMenu.Destroyed;
begin
end;

procedure TDLProjectRulesMenu.Modified;
begin
end;

{ IOTALocalMenu }

function TDLProjectRulesMenu.GetCaption: string;
begin
  Result:= MENU_CAPTION;
end;

function TDLProjectRulesMenu.GetChecked: Boolean;
begin
  Result:= False;
end;

function TDLProjectRulesMenu.GetEnabled: Boolean;
begin
  Result:= True;
end;

function TDLProjectRulesMenu.GetHelpContext: Integer;
begin
  Result:= 0;
end;

function TDLProjectRulesMenu.GetName: string;
begin
  Result:= MENU_NAME;
end;

function TDLProjectRulesMenu.GetParent: string;
begin
  Result:= '';
end;

function TDLProjectRulesMenu.GetPosition: Integer;
begin
  Result:= -1; { let the IDE place it at the default position }
end;

function TDLProjectRulesMenu.GetVerb: string;
begin
  Result:= MENU_VERB;
end;

procedure TDLProjectRulesMenu.SetCaption(const Value: string);
begin
  { read-only from our side -- the IDE never needs to rename this item }
end;

procedure TDLProjectRulesMenu.SetChecked(Value: Boolean);
begin
end;

procedure TDLProjectRulesMenu.SetEnabled(Value: Boolean);
begin
end;

procedure TDLProjectRulesMenu.SetHelpContext(Value: Integer);
begin
end;

procedure TDLProjectRulesMenu.SetName(const Value: string);
begin
end;

procedure TDLProjectRulesMenu.SetParent(const Value: string);
begin
end;

procedure TDLProjectRulesMenu.SetPosition(Value: Integer);
begin
end;

procedure TDLProjectRulesMenu.SetVerb(const Value: string);
begin
end;

{ IOTAProjectManagerMenu }

function TDLProjectRulesMenu.GetIsMultiSelectable: Boolean;
begin
  Result:= FIsMultiSelectable;
end;

procedure TDLProjectRulesMenu.SetIsMultiSelectable(Value: Boolean);
begin
  FIsMultiSelectable:= Value;
end;

procedure TDLProjectRulesMenu.Execute(const MenuContextList: IInterfaceList);
var
  ModSvcs: IOTAModuleServices;
  Group  : IOTAProjectGroup  ;
begin
  { Activate the clicked project first -- rules are per-project, so the dock's
    Lint Options tab must be scoped to what the user right-clicked, not whatever
    happened to be active before. }
  if FProject <> nil then
  begin
    if Supports(BorlandIDEServices, IOTAModuleServices, ModSvcs) then
    begin
      Group:= ModSvcs.MainProjectGroup;
      if Group <> nil then Group.ActiveProject:= FProject;
    end;
  end;

  DragLint.Plugin.DockForm.ShowDragLintDockLintOptions;
end;

function TDLProjectRulesMenu.PreExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result:= False; { False = let Execute run; True would skip it }
end;

function TDLProjectRulesMenu.PostExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result:= False;
end;

{ ---- TDLProjectMenuCreator ---- }

procedure TDLProjectMenuCreator.AfterSave;
begin
end;

procedure TDLProjectMenuCreator.BeforeSave;
begin
end;

procedure TDLProjectMenuCreator.Destroyed;
begin
end;

procedure TDLProjectMenuCreator.Modified;
begin
end;

procedure TDLProjectMenuCreator.AddMenu(const Project: IOTAProject; const IdentList: TStrings;
  const ProjectManagerMenuList: IInterfaceList; IsMultiSelect: Boolean);
var
  IsSingleProjectNode: Boolean;
begin
  { Only offer the item for a single, whole-project selection: not a file node,
    not a multi-select of several projects/files. sProjectContainer is the
    standard ToolsAPI ident for a project node (see ToolsAPI.pas). }
  IsSingleProjectNode:=
    (not IsMultiSelect) and (Project <> nil) and
    (IdentList <> nil) and (IdentList.Count = 1) and
    SameText(IdentList[0], sProjectContainer);

  if not IsSingleProjectNode then Exit;
  if ProjectManagerMenuList = nil then Exit;

  ProjectManagerMenuList.Add(TDLProjectRulesMenu.Create(Project));
end;

{ ---- registration ---- }

var
  GIndex: Integer = -1;

procedure RegisterProjectMenu;
var
  ProjMgr: IOTAProjectManager;
begin
  if GIndex >= 0 then Exit; { idempotent }
  if not Supports(BorlandIDEServices, IOTAProjectManager, ProjMgr) then Exit;
  GIndex:= ProjMgr.AddMenuItemCreatorNotifier(TDLProjectMenuCreator.Create);
end;

procedure UnregisterProjectMenu;
var
  ProjMgr: IOTAProjectManager;
begin
  if GIndex < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAProjectManager, ProjMgr) then
    try ProjMgr.RemoveMenuItemCreatorNotifier(GIndex); except end;
  GIndex:= -1;
end;

initialization

finalization
  try UnregisterProjectMenu; except end;

end.
