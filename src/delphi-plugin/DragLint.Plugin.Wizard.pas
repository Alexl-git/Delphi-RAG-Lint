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
  DragLint.Plugin.Editor;

procedure TDragLintWizard.AfterSave;
begin
end;

procedure TDragLintWizard.BeforeSave;
begin
end;

procedure TDragLintWizard.Destroyed;
begin
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
  ShowMessage('drag-lint v0.21.0-alpha'#13#10 +
    'Tools > drag-lint menu: Hover / Completion / Signature Help / Diagnostics');
end;

procedure Register;
begin
  RegisterPackageWizard(TDragLintWizard.Create);
  RegisterDragLintMenu;
end;

end.
