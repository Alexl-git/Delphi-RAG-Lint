unit DragLint.Plugin.Wizard;

interface

uses
  System.SysUtils
  , System.Classes
  , ToolsAPI
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DragLint.Plugin.Wizard.Register (DragLint.Plugin.Wizard.pas)</para>
  /// <para>Used in units: DragLint.Plugin.Wizard</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintWizard = class(TInterfacedObject, IOTAWizard)
    public
      { IOTANotifier }
      procedure AfterSave;
      procedure BeforeSave;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.About.UnregisterDragLintAbout, DragLint.Plugin.DockForm.UnregisterDragLintDock, DragLint.Plugin.EditViewNotifier.UnregisterDragLintEditViewNotifier, DragLint.Plugin.FanOut.ShutdownFanOut, DragLint.Plugin.OpenSourceServer.StopOpenSourceServer, DragLint.Plugin.Options.UnregisterDragLintOptions, DragLint.Plugin.ProjectMenu.UnregisterProjectMenu, DragLint.Plugin.ProjectNotifier.UnregisterProjectNotifier, DragLint.Plugin.SaveNotifier.UnregisterAllSaveNotifiers</para>
      /// <para>Catches: Exception (empty)</para>
      /// <seealso cref="DragLint.Plugin.About.UnregisterDragLintAbout"/>
      /// <seealso cref="DragLint.Plugin.DockForm.UnregisterDragLintDock"/>
      /// <seealso cref="DragLint.Plugin.EditViewNotifier.UnregisterDragLintEditViewNotifier"/>
      /// <seealso cref="DragLint.Plugin.FanOut.ShutdownFanOut"/>
      /// <seealso cref="DragLint.Plugin.OpenSourceServer.StopOpenSourceServer"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Destroyed;
      procedure Modified;
      { IOTAWizard }
      /// <summary><!-- drag-lint:auto sum -->IOTAWizard</summary>
      /// <returns><!-- drag-lint:auto -->string -- Observed: 'drag-lint.wizard.v021'.</returns>
      function GetIDString: string;
      /// <returns><!-- drag-lint:auto -->string -- Observed: 'drag-lint'.</returns>
      function GetName    : string;
      /// <returns><!-- drag-lint:auto -->TWizardState -- Observed: [wsEnabled].</returns>
      function GetState: TWizardState;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.Editor.PluginBuildTag, ShowMessage</para>
      /// <seealso cref="DragLint.Plugin.Editor.PluginBuildTag"/>
      /// <seealso cref="DragLint.Plugin.Wizard.TDragLintWizard.AfterSave"/>
      /// <seealso cref="DragLint.Plugin.Wizard.TDragLintWizard.BeforeSave"/>
      /// <seealso cref="DragLint.Plugin.Wizard.TDragLintWizard.Destroyed"/>
      /// <seealso cref="DragLint.Plugin.Wizard.TDragLintWizard.GetIDString"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Execute;
  end;

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DragLint.Plugin.About.RegisterDragLintAbout, DragLint.Plugin.DbResolver.PublishLibraryDefaults, DragLint.Plugin.DockForm.RegisterDragLintDockable, DragLint.Plugin.Editor.RegisterDragLintMenu, DragLint.Plugin.GraphWindow.RegisterDragLintGraphDockable, DragLint.Plugin.OpenSourceServer.StartOpenSourceServer, DragLint.Plugin.Options.RegisterDragLintOptions, DragLint.Plugin.ProjectMenu.RegisterProjectMenu, DragLint.Plugin.Settings.MigrateGhostTextDefault, RegisterPackageWizard</para>
/// <para>Catches: Exception (empty)</para>
/// <seealso cref="DragLint.Plugin.About.RegisterDragLintAbout"/>
/// <seealso cref="DragLint.Plugin.DbResolver.PublishLibraryDefaults"/>
/// <seealso cref="DragLint.Plugin.DockForm.RegisterDragLintDockable"/>
/// <seealso cref="DragLint.Plugin.Editor.RegisterDragLintMenu"/>
/// <seealso cref="DragLint.Plugin.GraphWindow.RegisterDragLintGraphDockable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Register;

implementation

uses
  Vcl.Dialogs
  , DragLint.Plugin.FanOut
  , DragLint.Plugin.Editor
  , DragLint.Plugin.Options
  , DragLint.Plugin.ProjectMenu
  , DragLint.Plugin.EditViewNotifier
  , DragLint.Plugin.ProjectNotifier
  , DragLint.Plugin.SaveNotifier
  , DragLint.Plugin.OpenSourceServer
  , DragLint.Plugin.DockForm
  , DragLint.Plugin.GraphWindow
  , DragLint.Plugin.About
  , DragLint.Plugin.Settings      { MigrateGhostTextDefault -- see Register }
  , DragLint.Plugin.DbResolver    { PublishLibraryDefaults -- see Register }
  , DragLint.Plugin.ConvertSelectionEditor { C12 N7 -- see Register }
  ;

{$R 'DragLintSplash.res'}

procedure TDragLintWizard.AfterSave;
begin
end;

procedure TDragLintWizard.BeforeSave;
begin
end;

procedure TDragLintWizard.Destroyed;
begin
  { v0.40: wizard.Destroyed fires during IDE shutdown / package unload,
    BEFORE the BPL code segment is dropped. Strip every notifier we ever
    handed to the IDE so no module / view / IDE list keeps a dangling
    interface pointer into our soon-to-vanish vtable. Without this:
      - File > Exit AVs in TCodeIDocModule.AllowSave -> @IntfCopy
      - Editor paints AV in TOTAEditView.BeginPaint -> GetInterface
    All are idempotent; safe to call here in addition to the unit
    finalizations (which run later in the same shutdown). }
  { PLAN-lint-tree P3. FIRST, and for two reasons the others do not have: it
    holds an IOTAMessageNotifier the IDE would otherwise call back into, and it
    may have an engine child running RIGHT NOW. ShutdownFanOut kills that child
    and waits for it -- a dcc grandchild outliving the BPL that spawned it is a
    process nobody is left to reap. }
  try ShutdownFanOut; except end;
  try UnregisterAllSaveNotifiers; except end;
  try UnregisterDragLintEditViewNotifier; except end;
  try UnregisterProjectNotifier; except end;
  try StopOpenSourceServer; except end;
  try UnregisterDragLintDock; except end;
  try UnregisterDragLintOptions; except end;
  try UnregisterDragLintAbout;   except end;
  try UnregisterProjectMenu;     except end;
end;

procedure TDragLintWizard.Modified;
begin
end;

function TDragLintWizard.GetIDString: string;
begin
  Result:= 'drag-lint.wizard.v021';
end;

function TDragLintWizard.GetName: string;
begin
  Result:= 'drag-lint';
end;

function TDragLintWizard.GetState: TWizardState;
begin
  Result:= [wsEnabled];
end;

procedure TDragLintWizard.Execute;
begin
  ShowMessage(PluginBuildTag + #13#10#13#10 + 'Tools > drag-lint menu: Hover / Completion / Signature Help / Diagnostics / Open Plugin Log' + #13#10 + 'Version + engine self-info: Help > About > drag-lint');
end;

procedure Register;
begin
  { FIRST, before anything reads settings: an installation that stored
    EnableGhostText=0 under the old default would otherwise never see the new
    one, and KAI would keep failing to reach an unbound port. Runs once. }
  try MigrateGhostTextDefault; except end;
  { Central settings folder (%LOCALAPPDATA%\drag-lint\context-defaults.json): record which
    library index this install has per platform, so the LSP and the engine resolve a loose
    unit against the same library the IDE uses. Never blocks start-up. }
  PublishLibraryDefaults;
  RegisterPackageWizard(TDragLintWizard.Create);
  try RegisterDragLintAbout; except end;
  RegisterDragLintMenu;
  RegisterDragLintOptions;
  try RegisterProjectMenu; except end;
  { C12 N7: the designer right-click Convert entries (unregistered by the IDE with the package). }
  try RegisterConvertSelectionEditor; except end;
  StartOpenSourceServer;
  { Register the dockable forms at STARTUP so the IDE can restore them when it
    reloads a saved desktop that had them docked. Registering only on menu click
    (inside ShowDragLintDock/ShowDragLintGraph) is too late for desktop restore. }
  try RegisterDragLintDockable; except end;
  try RegisterDragLintGraphDockable; except end;
end;

end.
