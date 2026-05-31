unit DragLint.Plugin.Wizard;

interface

uses
  System.SysUtils, System.Classes, ToolsAPI;

type
  TDragLintWizard = class(TInterfacedObject, IOTAWizard)
  public
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

procedure Register;

implementation

uses
  Vcl.Dialogs,
  DragLint.Plugin.Editor,
  DragLint.Plugin.Options,
  DragLint.Plugin.EditViewNotifier,
  DragLint.Plugin.ProjectNotifier,
  DragLint.Plugin.SaveNotifier;

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
    All four are idempotent; safe to call here in addition to the unit
    finalizations (which run later in the same shutdown). }
  try UnregisterAllSaveNotifiers;     except end;
  try UnregisterDragLintEditViewNotifier; except end;
  try UnregisterProjectNotifier;      except end;
end;

procedure TDragLintWizard.Modified;
begin
end;

function TDragLintWizard.GetIDString: string;
begin
  Result := 'drag-lint.wizard.v021';
end;

function TDragLintWizard.GetName: string;
begin
  Result := 'drag-lint';
end;

function TDragLintWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TDragLintWizard.Execute;
begin
  ShowMessage(PluginBuildTag + #13#10#13#10 +
    'Tools > drag-lint menu: Hover / Completion / Signature Help / Diagnostics / Test Connection / Open Plugin Log');
end;

procedure Register;
begin
  RegisterPackageWizard(TDragLintWizard.Create);
  RegisterDragLintMenu;
  RegisterDragLintOptions;
end;

end.
